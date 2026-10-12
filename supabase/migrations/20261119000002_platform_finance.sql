-- ==============================================================================
-- Migration: 20261119000002_platform_finance.sql
-- The platform owner's money and numbers (/platform/billing, /platform/analytics):
-- what each company pays the platform, the bills that come from it, what running
-- the platform costs, and one read of the whole platform with recommendations.
-- Platform-private: only the platform admin reads or writes any of it (RLS and
-- every function check is_super_admin()); company admins see nothing.
-- Safe to re-run. Additive only: three new tables and seven new functions.
--
-- Tables
--   company_plans      what a company pays the platform: a fee per cycle from a
--                      date. History is kept: a change ends the open plan the day
--                      before the new one starts and adds a row (one open plan per
--                      company). A plan replaced on its own first day ends the day
--                      before it started (it never applied).
--   platform_charges   one bill per company and period (unique company_id +
--                      period_start), made from the plan by platform_generate_charges.
--                      'due' until marked 'paid' (paid_at, method) or 'waived'.
--   platform_expenses  what running the platform costs, per calendar month
--                      (month = its first day). `recurring` rows are carried to the
--                      following months by platform_generate_charges.
--
-- Periods of a plan
--   monthly   from starts_on, one calendar month at a time (Jan 31 → Feb 28 → Mar 31…)
--   yearly    from starts_on, twelve months at a time
--   termly    the academic terms (academic_terms: active and part of the year, i.e.
--             the first and second terms); the first bill covers the term the plan
--             starts in (from its start date). Without usable terms: four months
--             at a time from starts_on.
--   A plan with fee 0 makes no bills. A bill is "overdue" 14 days after its period starts.
--
-- Functions (all: platform admin only, else 42501 with an Arabic sentence)
--   save_company_plan(p_company_id, p_fee, p_cycle, p_starts_on, p_note) → plan
--   platform_generate_charges(p_until) → {charges_created, expenses_carried, until}
--   set_platform_charge_status(p_charge_id, p_status, p_method, p_note) → charge
--   save_platform_expense(p_id, p_month, p_category, p_amount, p_note, p_recurring) → expense
--   delete_platform_expense(p_id) → {id}
--   platform_billing() → {today, grace_days, mrr, companies, plans, charges, expenses, pnl}
--   platform_analytics(p_from, p_to) → {period, finance, companies, students, usage, insights}
--
-- Definitions shared with company_analytics (20261118000001):
--   subscriber  a paid subscription that runs on the day: status 'active', or
--               'expired' that ended naturally (end_date before today).
--   revenue     a paid subscription counts its approved receipt's amount, else its
--               price, on the Cairo day it was paid (company_revenue_breakdown).
--   MRR         the open plans' fees per month: monthly as is, termly / 4, yearly / 12.
--   P&L         cash: collected = paid bills by the Cairo month of paid_at;
--               billed = bills not waived by their period's month; costs by month;
--               profit = collected − costs.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------- tables

CREATE TABLE IF NOT EXISTS public.company_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  fee_amount numeric(12,2) NOT NULL CHECK (fee_amount >= 0),
  cycle text NOT NULL CHECK (cycle IN ('monthly', 'termly', 'yearly')),
  starts_on date NOT NULL,
  ends_on date,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  -- ends_on = starts_on - 1: replaced on its first day, never applied.
  CONSTRAINT company_plans_dates CHECK (ends_on IS NULL OR ends_on >= starts_on - 1)
);
CREATE UNIQUE INDEX IF NOT EXISTS company_plans_one_open ON public.company_plans(company_id) WHERE ends_on IS NULL;
CREATE INDEX IF NOT EXISTS idx_company_plans_company ON public.company_plans(company_id, starts_on DESC);

CREATE TABLE IF NOT EXISTS public.platform_charges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES public.company_plans(id) ON DELETE SET NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  status text NOT NULL DEFAULT 'due' CHECK (status IN ('due', 'paid', 'waived')),
  paid_at timestamptz,
  method text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT platform_charges_period UNIQUE (company_id, period_start)
);
CREATE INDEX IF NOT EXISTS idx_platform_charges_due ON public.platform_charges(company_id, period_start) WHERE status = 'due';
CREATE INDEX IF NOT EXISTS idx_platform_charges_plan ON public.platform_charges(plan_id);

CREATE TABLE IF NOT EXISTS public.platform_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  month date NOT NULL CHECK (month = date_trunc('month', month)::date),
  category text NOT NULL CHECK (category IN ('hosting', 'database', 'sms', 'push', 'app_store', 'play_store', 'domain',
                                             'salaries', 'marketing', 'support', 'other')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  note text,
  recurring boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid
);
CREATE INDEX IF NOT EXISTS idx_platform_expenses_month ON public.platform_expenses(month);

ALTER TABLE public.company_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_expenses ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.company_plans, public.platform_charges, public.platform_expenses FROM PUBLIC, anon, authenticated;
-- Reads only: every write goes through the functions below (SECURITY DEFINER).
GRANT SELECT ON public.company_plans, public.platform_charges, public.platform_expenses TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                 AND tablename = 'company_plans' AND policyname = 'company_plans_platform') THEN
    CREATE POLICY company_plans_platform ON public.company_plans FOR ALL TO authenticated
      USING ((SELECT public.is_super_admin())) WITH CHECK ((SELECT public.is_super_admin()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                 AND tablename = 'platform_charges' AND policyname = 'platform_charges_platform') THEN
    CREATE POLICY platform_charges_platform ON public.platform_charges FOR ALL TO authenticated
      USING ((SELECT public.is_super_admin())) WITH CHECK ((SELECT public.is_super_admin()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                 AND tablename = 'platform_expenses' AND policyname = 'platform_expenses_platform') THEN
    CREATE POLICY platform_expenses_platform ON public.platform_expenses FOR ALL TO authenticated
      USING ((SELECT public.is_super_admin())) WITH CHECK ((SELECT public.is_super_admin()));
  END IF;
END $$;

-- ---------------------------------------------------------- save_company_plan

CREATE OR REPLACE FUNCTION public.save_company_plan(
  p_company_id uuid, p_fee numeric, p_cycle text, p_starts_on date, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_open public.company_plans;
  v_last_end date;
  v_plan public.company_plans;
  v_ended uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'اشتراكات الشركات متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM public.companies c WHERE c.id = p_company_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.' USING ERRCODE = 'P0002'; END IF;
  IF p_fee IS NULL OR p_fee < 0 THEN RAISE EXCEPTION 'اكتب مبلغ الاشتراك (صفر أو أكثر).' USING ERRCODE = '22023'; END IF;
  IF p_fee > 9999999999 THEN RAISE EXCEPTION 'المبلغ أكبر من المسموح.' USING ERRCODE = '22023'; END IF;
  IF p_cycle IS NULL OR p_cycle NOT IN ('monthly', 'termly', 'yearly') THEN
    RAISE EXCEPTION 'اختر كل كم يُدفع الاشتراك: شهرياً أو كل فصل أو سنوياً.' USING ERRCODE = '22023';
  END IF;
  IF p_starts_on IS NULL THEN RAISE EXCEPTION 'اختر تاريخ بداية الاشتراك.' USING ERRCODE = '22023'; END IF;

  SELECT * INTO v_open FROM public.company_plans p WHERE p.company_id = p_company_id AND p.ends_on IS NULL;
  SELECT max(p.ends_on) INTO v_last_end FROM public.company_plans p WHERE p.company_id = p_company_id;
  IF v_open.id IS NOT NULL AND p_starts_on < v_open.starts_on THEN
    RAISE EXCEPTION 'الاشتراك الجديد لا يبدأ قبل بداية الاشتراك الحالي (%).', to_char(v_open.starts_on, 'YYYY-MM-DD') USING ERRCODE = '22023';
  END IF;
  IF v_last_end IS NOT NULL AND p_starts_on <= v_last_end THEN
    RAISE EXCEPTION 'الاشتراك الجديد يبدأ بعد آخر اشتراك انتهى (%).', to_char(v_last_end, 'YYYY-MM-DD') USING ERRCODE = '22023';
  END IF;

  IF v_open.id IS NOT NULL THEN
    UPDATE public.company_plans SET ends_on = p_starts_on - 1 WHERE id = v_open.id;
    v_ended := v_open.id;
  END IF;
  -- Bills not yet paid from the new start on are made again from the new plan;
  -- one that runs across the change ends the day before. Paid and waived bills stay.
  DELETE FROM public.platform_charges ch
  WHERE ch.company_id = p_company_id AND ch.status = 'due' AND ch.period_start >= p_starts_on;
  UPDATE public.platform_charges ch SET period_end = p_starts_on - 1
  WHERE ch.company_id = p_company_id AND ch.status = 'due' AND ch.period_end >= p_starts_on;

  INSERT INTO public.company_plans (company_id, fee_amount, cycle, starts_on, note, created_by)
  VALUES (p_company_id, round(p_fee, 2), p_cycle, p_starts_on, NULLIF(btrim(COALESCE(p_note, '')), ''), auth.uid())
  RETURNING * INTO v_plan;

  RETURN to_jsonb(v_plan) || jsonb_build_object('ended_plan_id', v_ended);
END;
$$;
REVOKE ALL ON FUNCTION public.save_company_plan(uuid, numeric, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_company_plan(uuid, numeric, text, date, text) TO authenticated;

-- -------------------------------------------------- platform_generate_charges

CREATE OR REPLACE FUNCTION public.platform_generate_charges(p_until date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_until date := COALESCE(p_until, v_today);
  v_terms boolean;
  v_y0 int;
  v_created int := 0;
  v_carried int := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'فواتير الشركات متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF v_until > v_today + 366 THEN
    RAISE EXCEPTION 'لا تُصدر فواتير لأكثر من سنة مقدماً.' USING ERRCODE = '22023';
  END IF;

  -- Terms are usable when the year has at least one active term whose end follows its start.
  SELECT bool_or(make_date(2000 + t.end_year_offset, t.end_month, 1) >= make_date(2000 + t.start_year_offset, t.start_month, 1)) INTO v_terms
  FROM public.academic_terms t WHERE t.is_active AND t.included_in_annual;
  v_terms := COALESCE(v_terms, false);
  SELECT COALESCE(extract(year FROM min(starts_on))::int - 1, extract(year FROM v_today)::int) INTO v_y0 FROM public.company_plans;

  WITH p AS (
    SELECT pl.* FROM public.company_plans pl
    WHERE pl.fee_amount > 0 AND pl.starts_on <= v_until AND (pl.ends_on IS NULL OR pl.ends_on >= pl.starts_on)
  ),
  stepped AS (
    SELECT p.id, p.company_id, p.fee_amount, p.ends_on, p.starts_on,
           CASE p.cycle WHEN 'monthly' THEN 1 WHEN 'yearly' THEN 12 ELSE 4 END AS step,
           (extract(year FROM age(v_until, p.starts_on)) * 12 + extract(month FROM age(v_until, p.starts_on)))::int AS months
    FROM p WHERE p.cycle <> 'termly' OR NOT v_terms
  ),
  by_step AS (
    SELECT s.id AS plan_id, s.company_id, s.fee_amount, s.ends_on,
           (s.starts_on + make_interval(months => k * s.step))::date AS ps,
           (s.starts_on + make_interval(months => (k + 1) * s.step))::date - 1 AS pe
    FROM stepped s CROSS JOIN LATERAL generate_series(0, s.months / s.step) k
  ),
  term_dates AS (
    -- Each term of each academic year (y = the year the academic year starts in);
    -- a day past the month's end (30 February) is the month's last day.
    SELECT y,
           LEAST(make_date(y + t.start_year_offset, t.start_month, 1) + (t.start_day - 1),
                 (make_date(y + t.start_year_offset, t.start_month, 1) + interval '1 month')::date - 1) AS ts,
           LEAST(make_date(y + t.end_year_offset, t.end_month, 1) + (t.end_day - 1),
                 (make_date(y + t.end_year_offset, t.end_month, 1) + interval '1 month')::date - 1) AS te
    FROM public.academic_terms t CROSS JOIN generate_series(v_y0, extract(year FROM v_until)::int) y
    WHERE v_terms AND t.is_active AND t.included_in_annual
  ),
  by_term AS (
    SELECT p.id AS plan_id, p.company_id, p.fee_amount, p.ends_on, GREATEST(d.ts, p.starts_on) AS ps, d.te AS pe
    FROM p JOIN term_dates d ON d.te >= d.ts AND d.te >= p.starts_on AND d.ts <= COALESCE(p.ends_on, d.ts)
    WHERE p.cycle = 'termly'
  ),
  periods AS (SELECT * FROM by_step UNION ALL SELECT * FROM by_term),
  ins AS (
    INSERT INTO public.platform_charges (company_id, plan_id, period_start, period_end, amount)
    SELECT x.company_id, x.plan_id, x.ps, LEAST(x.pe, COALESCE(x.ends_on, x.pe)), x.fee_amount
    FROM periods x
    WHERE x.ps <= v_until AND x.ps <= COALESCE(x.ends_on, x.ps)
    ON CONFLICT (company_id, period_start) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_created FROM ins;

  -- Recurring costs: the latest row of each (category, note) that is marked recurring
  -- is copied into every month after it, up to p_until's month (the copies stay recurring).
  WITH latest AS (
    SELECT DISTINCT ON (e.category, COALESCE(e.note, '')) e.*
    FROM public.platform_expenses e
    ORDER BY e.category, COALESCE(e.note, ''), e.month DESC, e.created_at DESC
  ),
  ins AS (
    INSERT INTO public.platform_expenses (month, category, amount, note, recurring, created_by)
    SELECT (l.month + make_interval(months => k))::date, l.category, l.amount, l.note, true, auth.uid()
    FROM latest l
    CROSS JOIN LATERAL generate_series(1, (extract(year FROM age(date_trunc('month', v_until)::date, l.month)) * 12
                                           + extract(month FROM age(date_trunc('month', v_until)::date, l.month)))::int) k
    WHERE l.recurring
    RETURNING 1
  )
  SELECT count(*) INTO v_carried FROM ins;

  RETURN jsonb_build_object('charges_created', v_created, 'expenses_carried', v_carried, 'until', v_until);
END;
$$;
REVOKE ALL ON FUNCTION public.platform_generate_charges(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_generate_charges(date) TO authenticated;

-- ------------------------------------------------- set_platform_charge_status

CREATE OR REPLACE FUNCTION public.set_platform_charge_status(
  p_charge_id uuid, p_status text, p_method text DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.platform_charges;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'فواتير الشركات متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('due', 'paid', 'waived') THEN
    RAISE EXCEPTION 'حالة الفاتورة غير معروفة.' USING ERRCODE = '22023';
  END IF;
  UPDATE public.platform_charges ch SET
    status = p_status,
    paid_at = CASE WHEN p_status = 'paid' THEN COALESCE(CASE WHEN ch.status = 'paid' THEN ch.paid_at END, now()) END,
    method = CASE WHEN p_status = 'paid' THEN NULLIF(btrim(COALESCE(p_method, '')), '') END,
    note = CASE WHEN p_note IS NULL THEN ch.note ELSE NULLIF(btrim(p_note), '') END
  WHERE ch.id = p_charge_id
  RETURNING * INTO v;
  IF v.id IS NULL THEN RAISE EXCEPTION 'الفاتورة غير موجودة.' USING ERRCODE = 'P0002'; END IF;
  RETURN to_jsonb(v) || jsonb_build_object('company_name', (SELECT c.name FROM public.companies c WHERE c.id = v.company_id));
END;
$$;
REVOKE ALL ON FUNCTION public.set_platform_charge_status(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_platform_charge_status(uuid, text, text, text) TO authenticated;

-- ---------------------------------------------------- expenses: save, delete

CREATE OR REPLACE FUNCTION public.save_platform_expense(
  p_id uuid, p_month date, p_category text, p_amount numeric, p_note text DEFAULT NULL, p_recurring boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.platform_expenses; v_month date := date_trunc('month', p_month)::date;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تكاليف التشغيل متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_month IS NULL THEN RAISE EXCEPTION 'اختر الشهر.' USING ERRCODE = '22023'; END IF;
  IF p_category IS NULL OR p_category NOT IN ('hosting', 'database', 'sms', 'push', 'app_store', 'play_store', 'domain',
                                              'salaries', 'marketing', 'support', 'other') THEN
    RAISE EXCEPTION 'اختر نوع التكلفة.' USING ERRCODE = '22023';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'اكتب مبلغاً أكبر من صفر.' USING ERRCODE = '22023'; END IF;
  IF p_amount > 9999999999 THEN RAISE EXCEPTION 'المبلغ أكبر من المسموح.' USING ERRCODE = '22023'; END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.platform_expenses (month, category, amount, note, recurring, created_by)
    VALUES (v_month, p_category, round(p_amount, 2), NULLIF(btrim(COALESCE(p_note, '')), ''), COALESCE(p_recurring, false), auth.uid())
    RETURNING * INTO v;
  ELSE
    UPDATE public.platform_expenses e SET month = v_month, category = p_category, amount = round(p_amount, 2),
      note = NULLIF(btrim(COALESCE(p_note, '')), ''), recurring = COALESCE(p_recurring, false)
    WHERE e.id = p_id RETURNING * INTO v;
    IF v.id IS NULL THEN RAISE EXCEPTION 'التكلفة غير موجودة.' USING ERRCODE = 'P0002'; END IF;
  END IF;
  RETURN to_jsonb(v);
END;
$$;
REVOKE ALL ON FUNCTION public.save_platform_expense(uuid, date, text, numeric, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_platform_expense(uuid, date, text, numeric, text, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_platform_expense(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تكاليف التشغيل متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.platform_expenses e WHERE e.id = p_id RETURNING e.id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'التكلفة غير موجودة.' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('id', v_id);
END;
$$;
REVOKE ALL ON FUNCTION public.delete_platform_expense(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_platform_expense(uuid) TO authenticated;

-- ------------------------------------------------------------ platform_billing
-- {today, grace_days, mrr,
--  companies [{id, name, status, created_at, plan {…}|null, monthly_fee, outstanding, overdue, oldest_due}],
--  plans     [{id, company_id, company_name, fee_amount, cycle, starts_on, ends_on, note, created_at, created_by_name}],
--  charges   [{id, company_id, company_name, plan_id, period_start, period_end, amount, status, paid_at, method, note, created_at}],
--  expenses  [{id, month, category, amount, note, recurring, created_at}],
--  pnl       [{month 'YYYY-MM', billed, collected, costs, profit}]}

CREATE OR REPLACE FUNCTION public.platform_billing()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_grace constant int := 14;
  v_first date;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'حسابات المنصة متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT date_trunc('month', min(d))::date INTO v_first FROM (
    SELECT min(period_start) AS d FROM public.platform_charges
    UNION ALL SELECT min(month) FROM public.platform_expenses
    UNION ALL SELECT min((paid_at AT TIME ZONE 'Africa/Cairo')::date) FROM public.platform_charges) x;
  IF v_first IS NOT NULL THEN v_first := GREATEST(v_first, (date_trunc('month', v_today) - interval '35 months')::date); END IF;

  RETURN (
    WITH open_plan AS (SELECT * FROM public.company_plans p WHERE p.ends_on IS NULL),
    dues AS (
      SELECT ch.company_id, sum(ch.amount) AS amount, min(ch.period_start) AS oldest,
             COALESCE(sum(ch.amount) FILTER (WHERE ch.period_start + v_grace < v_today), 0) AS overdue
      FROM public.platform_charges ch WHERE ch.status = 'due' AND ch.period_start <= v_today GROUP BY 1
    ),
    months AS (
      SELECT to_char(m, 'YYYY-MM') AS mo FROM generate_series(v_first, date_trunc('month', v_today)::date, interval '1 month') m
      WHERE v_first IS NOT NULL
    ),
    billed AS (SELECT to_char(period_start, 'YYYY-MM') AS mo, sum(amount) AS n FROM public.platform_charges WHERE status <> 'waived' GROUP BY 1),
    collected AS (SELECT to_char(paid_at AT TIME ZONE 'Africa/Cairo', 'YYYY-MM') AS mo, sum(amount) AS n
                  FROM public.platform_charges WHERE status = 'paid' AND paid_at IS NOT NULL GROUP BY 1),
    costs AS (SELECT to_char(month, 'YYYY-MM') AS mo, sum(amount) AS n FROM public.platform_expenses GROUP BY 1)
    SELECT jsonb_build_object(
      'today', v_today,
      'grace_days', v_grace,
      'mrr', (SELECT COALESCE(round(sum(CASE p.cycle WHEN 'monthly' THEN p.fee_amount WHEN 'termly' THEN p.fee_amount / 4 ELSE p.fee_amount / 12 END), 2), 0)
              FROM open_plan p JOIN public.companies c ON c.id = p.company_id
              WHERE p.starts_on <= v_today AND c.status <> 'archived'),
      'companies', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id', c.id, 'name', c.name, 'status', c.status, 'created_at', c.created_at,
          'plan', CASE WHEN p.id IS NOT NULL THEN jsonb_build_object('id', p.id, 'fee_amount', p.fee_amount, 'cycle', p.cycle,
                                                                       'starts_on', p.starts_on, 'note', p.note, 'created_at', p.created_at) END,
          'monthly_fee', CASE p.cycle WHEN 'monthly' THEN p.fee_amount WHEN 'termly' THEN round(p.fee_amount / 4, 2) WHEN 'yearly' THEN round(p.fee_amount / 12, 2) END,
          'outstanding', COALESCE(d.amount, 0), 'overdue', COALESCE(d.overdue, 0), 'oldest_due', d.oldest)
          ORDER BY c.status <> 'active', c.name)
        FROM public.companies c LEFT JOIN open_plan p ON p.company_id = c.id LEFT JOIN dues d ON d.company_id = c.id), '[]'::jsonb),
      'plans', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'company_id', p.company_id, 'company_name', c.name, 'fee_amount', p.fee_amount, 'cycle', p.cycle,
          'starts_on', p.starts_on, 'ends_on', p.ends_on, 'note', p.note, 'created_at', p.created_at, 'created_by_name', a.full_name)
          ORDER BY c.name, p.starts_on DESC, p.created_at DESC)
        FROM public.company_plans p JOIN public.companies c ON c.id = p.company_id LEFT JOIN public.admins a ON a.id = p.created_by), '[]'::jsonb),
      'charges', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id', ch.id, 'company_id', ch.company_id, 'company_name', c.name, 'plan_id', ch.plan_id,
          'period_start', ch.period_start, 'period_end', ch.period_end, 'amount', ch.amount, 'status', ch.status,
          'paid_at', ch.paid_at, 'method', ch.method, 'note', ch.note, 'created_at', ch.created_at)
          ORDER BY ch.period_start DESC, c.name)
        FROM public.platform_charges ch JOIN public.companies c ON c.id = ch.company_id), '[]'::jsonb),
      'expenses', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id', e.id, 'month', e.month, 'category', e.category, 'amount', e.amount, 'note', e.note,
          'recurring', e.recurring, 'created_at', e.created_at)
          ORDER BY e.month DESC, e.amount DESC, e.created_at DESC)
        FROM public.platform_expenses e), '[]'::jsonb),
      'pnl', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'month', m.mo, 'billed', COALESCE(b.n, 0), 'collected', COALESCE(k.n, 0), 'costs', COALESCE(x.n, 0),
          'profit', COALESCE(k.n, 0) - COALESCE(x.n, 0)) ORDER BY m.mo)
        FROM months m LEFT JOIN billed b ON b.mo = m.mo LEFT JOIN collected k ON k.mo = m.mo LEFT JOIN costs x ON x.mo = m.mo), '[]'::jsonb)
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION public.platform_billing() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_billing() TO authenticated;

-- ---------------------------------------------------------- platform_analytics
-- p_from / p_to: Cairo days, inclusive (NULL = from the beginning / up to today).
-- The previous period (for the comparisons) is the same number of days just
-- before p_from; with p_from NULL there is none and those comparisons are skipped.
--
-- {period {from, to, previous_from, previous_to},
--  finance {mrr, billed, collected, outstanding, overdue [{company_id, name, amount, oldest_due}],
--           costs_total, costs_by_category [{category, amount}],
--           by_month [{month, billed, collected, costs, profit}], profit, margin,
--           cost_per_company, cost_per_student, subscribers, active_companies},
--  companies {counts {total, active, suspended, archived},
--             list [{id, name, status, created_at, students, subscribers, subscribers_before, lines, active_lines,
--                    ride_days, riders_avg, confirm_rate, company_revenue, plan_fee, plan_cycle, outstanding,
--                    overdue, last_admin_seen, median_review_hours, reviewed, health}]},
--  students {total, with_company, without_company, subscribers, new_in_period,
--            new_by_month [{month, count}], by_university [{id, name, students, companies, lines}],
--            by_college [{name, count}] (top 20), by_specialisation [{name, count}] (top 10)},
--  usage {daily [{date, confirmed, boarded}], devices {ios, android},
--         app_versions [{platform, version, devices}], latest {ios, android},
--         push_7d {accepted, failed, failure_rate}},
--  insights [{key, severity 'act'|'watch'|'good', data}]}
--
-- health (active companies; 0–100): admin seen in the last 7 days 25 (14 days 15,
-- 30 days 5); confirmation rate × 30; nothing outstanding 25 (outstanding but not
-- overdue 15, overdue 0); receipts reviewed within 24 hours or none 20 (48 hours 10).

CREATE OR REPLACE FUNCTION public.platform_analytics(p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_grace constant int := 14;
  v_to date;
  v_lo date;
  v_prev_from date;
  v_prev_to date;
  v_subs int;
  v_subs_prev int;
  v_costs numeric;
  v_costs_prev numeric;
  v_active int;
  v_finance jsonb;
  v_companies jsonb;
  v_students jsonb;
  v_usage jsonb;
  v_insights jsonb;
  v_blank constant text[] := ARRAY['', '-', '--', '—', '.', '..', '?', '؟', 'n/a', 'na', 'none', 'null', 'لا يوجد', 'لا أعرف',
                                   'لا اعرف', 'غير محدد', 'غير محددة', 'غير معروف', 'غير معروفة', 'لم يحدد', 'لم تحدد'];
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تحليلات المنصة متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from > p_to THEN
    RAISE EXCEPTION 'بداية الفترة بعد نهايتها.' USING ERRCODE = '22023';
  END IF;
  v_to := LEAST(COALESCE(p_to, v_today), v_today);
  v_lo := COALESCE(p_from, DATE '2000-01-01');
  IF p_from IS NOT NULL AND p_from <= v_to THEN
    v_prev_to := p_from - 1;
    v_prev_from := p_from - (v_to - p_from + 1);
  END IF;

  -- Platform subscribers on the period's last day (and the previous period's), students counted once.
  SELECT count(DISTINCT s.student_id) INTO v_subs FROM public.subscriptions s
  WHERE s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
    AND COALESCE(s.start_date, v_to) <= v_to AND COALESCE(s.end_date, v_to) >= v_to;
  IF v_prev_to IS NOT NULL THEN
    SELECT count(DISTINCT s.student_id) INTO v_subs_prev FROM public.subscriptions s
    WHERE s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
      AND COALESCE(s.start_date, v_prev_to) <= v_prev_to AND COALESCE(s.end_date, v_prev_to) >= v_prev_to;
    SELECT COALESCE(sum(e.amount), 0) INTO v_costs_prev FROM public.platform_expenses e
    WHERE e.month BETWEEN date_trunc('month', v_prev_from)::date AND v_prev_to;
  END IF;
  SELECT COALESCE(sum(e.amount), 0) INTO v_costs FROM public.platform_expenses e
  WHERE e.month BETWEEN date_trunc('month', v_lo)::date AND v_to;
  SELECT count(*) INTO v_active FROM public.companies c WHERE c.status = 'active';

  -- ----------------------------------------------------------------- finance
  WITH ch AS (SELECT * FROM public.platform_charges),
  co AS (SELECT id, name FROM public.companies),
  months AS (
    SELECT to_char(m, 'YYYY-MM') AS mo
    FROM generate_series(
      date_trunc('month', COALESCE(p_from, LEAST(
        (SELECT min(period_start) FROM ch), (SELECT min(month) FROM public.platform_expenses),
        (SELECT min((paid_at AT TIME ZONE 'Africa/Cairo')::date) FROM ch))))::date,
      date_trunc('month', v_to)::date, interval '1 month') m
  ),
  billed AS (SELECT to_char(period_start, 'YYYY-MM') AS mo, sum(amount) AS n FROM ch
             WHERE status <> 'waived' AND period_start BETWEEN v_lo AND v_to GROUP BY 1),
  collected AS (SELECT to_char(paid_at AT TIME ZONE 'Africa/Cairo', 'YYYY-MM') AS mo, sum(amount) AS n FROM ch
                WHERE status = 'paid' AND (paid_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to GROUP BY 1),
  costs AS (SELECT to_char(month, 'YYYY-MM') AS mo, sum(amount) AS n FROM public.platform_expenses
            WHERE month BETWEEN date_trunc('month', v_lo)::date AND v_to GROUP BY 1),
  overdue AS (
    SELECT ch.company_id, co.name, sum(ch.amount) AS amount, min(ch.period_start) AS oldest
    FROM ch JOIN co ON co.id = ch.company_id
    WHERE ch.status = 'due' AND ch.period_start + v_grace < v_today GROUP BY 1, 2
  ),
  totals AS (
    SELECT (SELECT COALESCE(sum(n), 0) FROM billed) AS billed, (SELECT COALESCE(sum(n), 0) FROM collected) AS collected
  )
  SELECT jsonb_build_object(
    'mrr', (SELECT COALESCE(round(sum(CASE p.cycle WHEN 'monthly' THEN p.fee_amount WHEN 'termly' THEN p.fee_amount / 4 ELSE p.fee_amount / 12 END), 2), 0)
            FROM public.company_plans p JOIN public.companies c ON c.id = p.company_id
            WHERE p.ends_on IS NULL AND p.starts_on <= v_today AND c.status <> 'archived'),
    'billed', t.billed,
    'collected', t.collected,
    'outstanding', (SELECT COALESCE(sum(amount), 0) FROM ch WHERE status = 'due' AND period_start <= v_today),
    'overdue', COALESCE((SELECT jsonb_agg(jsonb_build_object('company_id', o.company_id, 'name', o.name, 'amount', o.amount, 'oldest_due', o.oldest)
                                          ORDER BY o.oldest, o.amount DESC) FROM overdue o), '[]'::jsonb),
    'costs_total', v_costs,
    'costs_by_category', COALESCE((SELECT jsonb_agg(jsonb_build_object('category', category, 'amount', n) ORDER BY n DESC, category)
                                   FROM (SELECT category, sum(amount) AS n FROM public.platform_expenses
                                         WHERE month BETWEEN date_trunc('month', v_lo)::date AND v_to GROUP BY 1) x), '[]'::jsonb),
    'by_month', COALESCE((SELECT jsonb_agg(jsonb_build_object('month', m.mo, 'billed', COALESCE(b.n, 0), 'collected', COALESCE(k.n, 0),
                                                              'costs', COALESCE(x.n, 0), 'profit', COALESCE(k.n, 0) - COALESCE(x.n, 0)) ORDER BY m.mo)
                          FROM months m LEFT JOIN billed b ON b.mo = m.mo LEFT JOIN collected k ON k.mo = m.mo LEFT JOIN costs x ON x.mo = m.mo), '[]'::jsonb),
    'profit', t.collected - v_costs,
    'margin', CASE WHEN t.collected > 0 THEN round((t.collected - v_costs) / t.collected, 3) END,
    'cost_per_company', CASE WHEN v_active > 0 THEN round(v_costs / v_active, 2) END,
    'cost_per_student', CASE WHEN v_subs > 0 THEN round(v_costs / v_subs, 2) END,
    'cost_per_student_before', CASE WHEN v_subs_prev > 0 THEN round(v_costs_prev / v_subs_prev, 2) END,
    'subscribers', v_subs,
    'active_companies', v_active
  ) INTO v_finance FROM totals t;

  -- --------------------------------------------------------------- companies
  WITH mem AS (SELECT company_id, count(*) AS n FROM public.company_students WHERE status = 'active' GROUP BY 1),
  psubs AS (
    SELECT s.company_id, s.student_id, s.start_date, s.end_date FROM public.subscriptions s
    WHERE s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
      AND COALESCE(s.start_date, v_to) <= v_to AND COALESCE(s.end_date, v_lo) >= v_lo
  ),
  subs_now AS (
    SELECT company_id, count(DISTINCT student_id) AS n FROM psubs
    WHERE COALESCE(start_date, v_to) <= v_to AND COALESCE(end_date, v_to) >= v_to GROUP BY 1
  ),
  subs_prev AS (
    SELECT s.company_id, count(DISTINCT s.student_id) AS n FROM public.subscriptions s
    WHERE v_prev_to IS NOT NULL AND s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
      AND COALESCE(s.start_date, v_prev_to) <= v_prev_to AND COALESCE(s.end_date, v_prev_to) >= v_prev_to
    GROUP BY 1
  ),
  ln AS (SELECT company_id, count(*) AS n, count(*) FILTER (WHERE is_active) AS a FROM public.lines GROUP BY 1),
  conf AS (
    SELECT d.company_id, d.ride_date AS d, count(*) AS n FROM public.daily_ride_status d
    WHERE d.is_riding AND d.ride_date BETWEEN v_lo AND v_to AND d.company_id IS NOT NULL GROUP BY 1, 2
  ),
  sub_groups AS (SELECT company_id, start_date, end_date, count(DISTINCT student_id) AS n FROM psubs GROUP BY 1, 2, 3),
  day_subs AS (
    SELECT c.company_id, c.d, sum(g.n) AS n FROM conf c
    JOIN sub_groups g ON g.company_id = c.company_id AND c.d BETWEEN COALESCE(g.start_date, c.d) AND COALESCE(g.end_date, c.d)
    GROUP BY 1, 2
  ),
  rides AS (
    SELECT c.company_id, count(*) AS days, sum(c.n) AS conf, sum(COALESCE(s.n, 0)) AS subs
    FROM conf c LEFT JOIN day_subs s ON s.company_id = c.company_id AND s.d = c.d GROUP BY 1
  ),
  rev AS (
    SELECT s.company_id, sum(COALESCE(a.amount, s.price)) AS amount
    FROM public.subscriptions s
    LEFT JOIN LATERAL (SELECT r.amount FROM public.receipts r WHERE r.subscription_id = s.id AND r.status = 'approved'
                       ORDER BY r.reviewed_at DESC NULLS LAST LIMIT 1) a ON true
    WHERE s.paid_at IS NOT NULL AND (s.paid_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to
    GROUP BY 1
  ),
  plan AS (SELECT company_id, fee_amount, cycle FROM public.company_plans WHERE ends_on IS NULL),
  dues AS (
    SELECT company_id, sum(amount) AS amount, COALESCE(sum(amount) FILTER (WHERE period_start + v_grace < v_today), 0) AS overdue
    FROM public.platform_charges WHERE status = 'due' AND period_start <= v_today GROUP BY 1
  ),
  seen AS (
    SELECT a.company_id, max(u.last_sign_in_at) AS at FROM public.admins a JOIN auth.users u ON u.id = a.id
    WHERE a.role = 'company_admin' AND a.company_id IS NOT NULL GROUP BY 1
  ),
  rv AS (
    SELECT r.company_id, count(*) AS n,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY GREATEST(extract(epoch FROM r.reviewed_at - r.created_at) / 3600.0, 0)) AS h
    FROM public.receipts r
    WHERE r.status IN ('approved', 'rejected') AND r.reviewed_at IS NOT NULL
      AND (r.reviewed_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to
    GROUP BY 1
  ),
  cr AS (
    SELECT c.id, c.name, c.status, c.created_at,
           COALESCE(m.n, 0) AS students, COALESCE(sn.n, 0) AS subscribers,
           CASE WHEN v_prev_to IS NOT NULL THEN COALESCE(sp.n, 0) END AS subscribers_before,
           COALESCE(l.n, 0) AS lines, COALESCE(l.a, 0) AS active_lines,
           COALESCE(r.days, 0) AS ride_days,
           CASE WHEN r.days > 0 THEN round(r.conf::numeric / r.days, 1) ELSE 0 END AS riders_avg,
           CASE WHEN r.subs > 0 THEN round(LEAST(r.conf::numeric / r.subs, 1), 3) END AS confirm_rate,
           COALESCE(rv2.amount, 0) AS company_revenue,
           p.fee_amount AS plan_fee, p.cycle AS plan_cycle,
           COALESCE(d.amount, 0) AS outstanding, COALESCE(d.overdue, 0) AS overdue,
           se.at AS last_admin_seen,
           round(q.h::numeric, 1) AS median_review_hours, COALESCE(q.n, 0) AS reviewed
    FROM public.companies c
    LEFT JOIN mem m ON m.company_id = c.id
    LEFT JOIN subs_now sn ON sn.company_id = c.id
    LEFT JOIN subs_prev sp ON sp.company_id = c.id
    LEFT JOIN ln l ON l.company_id = c.id
    LEFT JOIN rides r ON r.company_id = c.id
    LEFT JOIN rev rv2 ON rv2.company_id = c.id
    LEFT JOIN plan p ON p.company_id = c.id
    LEFT JOIN dues d ON d.company_id = c.id
    LEFT JOIN seen se ON se.company_id = c.id
    LEFT JOIN rv q ON q.company_id = c.id
  )
  SELECT jsonb_build_object(
    'counts', jsonb_build_object('total', count(*), 'active', count(*) FILTER (WHERE status = 'active'),
                                 'suspended', count(*) FILTER (WHERE status = 'suspended'), 'archived', count(*) FILTER (WHERE status = 'archived')),
    'list', COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'status', status, 'created_at', created_at, 'students', students, 'subscribers', subscribers,
      'subscribers_before', subscribers_before, 'lines', lines, 'active_lines', active_lines, 'ride_days', ride_days,
      'riders_avg', riders_avg, 'confirm_rate', confirm_rate, 'company_revenue', company_revenue,
      'plan_fee', plan_fee, 'plan_cycle', plan_cycle, 'outstanding', outstanding, 'overdue', overdue,
      'last_admin_seen', last_admin_seen, 'median_review_hours', median_review_hours, 'reviewed', reviewed,
      'health', CASE WHEN status = 'active' THEN LEAST(100,
          CASE WHEN last_admin_seen > now() - interval '7 days' THEN 25 WHEN last_admin_seen > now() - interval '14 days' THEN 15
               WHEN last_admin_seen > now() - interval '30 days' THEN 5 ELSE 0 END
        + COALESCE(round(30 * confirm_rate), 0)
        + CASE WHEN overdue > 0 THEN 0 WHEN outstanding > 0 THEN 15 ELSE 25 END
        + CASE WHEN reviewed = 0 OR median_review_hours <= 24 THEN 20 WHEN median_review_hours <= 48 THEN 10 ELSE 0 END)::int END)
      ORDER BY status <> 'active', subscribers DESC, name), '[]'::jsonb)
  ) INTO v_companies FROM cr;

  -- ---------------------------------------------------------------- students
  WITH st AS (
    SELECT s.id, s.created_at, s.university_id,
           NULLIF(regexp_replace(btrim(COALESCE(s.college, '')), '\s+', ' ', 'g'), '') AS college,
           NULLIF(regexp_replace(btrim(COALESCE(s.specialisation, '')), '\s+', ' ', 'g'), '') AS spec
    FROM public.students s
  ),
  members AS (SELECT DISTINCT m.student_id, m.company_id FROM public.company_students m WHERE m.status = 'active'),
  col AS (SELECT college AS name, count(*) AS n FROM st WHERE lower(COALESCE(college, '')) <> ALL (v_blank) GROUP BY 1),
  spc AS (SELECT spec AS name, count(*) AS n FROM st WHERE lower(COALESCE(spec, '')) <> ALL (v_blank) GROUP BY 1),
  uni_students AS (SELECT university_id AS id, count(*) AS n FROM st GROUP BY 1),
  uni_companies AS (
    SELECT st.university_id AS id, count(DISTINCT mb.company_id) AS n
    FROM st JOIN members mb ON mb.student_id = st.id JOIN public.companies c ON c.id = mb.company_id AND c.status = 'active'
    GROUP BY 1
  ),
  uni_lines AS (
    SELECT x.university_id AS id, count(DISTINCT x.line_id) AS n
    FROM public.line_universities x JOIN public.lines l ON l.id = x.line_id AND l.is_active
    JOIN public.companies c ON c.id = l.company_id AND c.status = 'active'
    GROUP BY 1
  ),
  uni AS (
    SELECT u.id, u.name, COALESCE(s.n, 0) AS students, COALESCE(c.n, 0) AS companies, COALESCE(l.n, 0) AS lines
    FROM public.universities u
    LEFT JOIN uni_students s ON s.id = u.id LEFT JOIN uni_companies c ON c.id = u.id LEFT JOIN uni_lines l ON l.id = u.id
    WHERE u.is_active OR s.n > 0
    UNION ALL
    SELECT NULL, NULL, s.n, 0, 0 FROM uni_students s WHERE s.id IS NULL
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM st),
    'with_company', (SELECT count(DISTINCT student_id) FROM members),
    'without_company', (SELECT count(*) FROM st WHERE NOT EXISTS (SELECT 1 FROM members mb WHERE mb.student_id = st.id)),
    'subscribers', v_subs,
    'new_in_period', (SELECT count(*) FROM st WHERE (st.created_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to),
    'new_by_month', COALESCE((SELECT jsonb_agg(jsonb_build_object('month', mo, 'count', n) ORDER BY mo)
                              FROM (SELECT to_char(st.created_at AT TIME ZONE 'Africa/Cairo', 'YYYY-MM') AS mo, count(*) AS n FROM st
                                    WHERE (st.created_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to GROUP BY 1) x), '[]'::jsonb),
    'by_university', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'students', students, 'companies', companies, 'lines', lines)
                                                ORDER BY students DESC, name NULLS LAST) FROM uni), '[]'::jsonb),
    'by_college', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'count', n) ORDER BY n DESC, name)
                            FROM (SELECT name, n FROM col ORDER BY n DESC, name LIMIT 20) c1), '[]'::jsonb),
    'by_specialisation', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'count', n) ORDER BY n DESC, name)
                                   FROM (SELECT name, n FROM spc ORDER BY n DESC, name LIMIT 10) s1), '[]'::jsonb)
  ) INTO v_students;

  -- ------------------------------------------------------------------- usage
  WITH days AS (
    SELECT d.ride_date AS d, count(*) AS n FROM public.daily_ride_status d
    WHERE d.is_riding AND d.ride_date BETWEEN GREATEST(v_lo, v_to - 120) AND v_to
    GROUP BY 1 ORDER BY 1 DESC LIMIT 60
  ),
  board AS (
    SELECT e.ride_date AS d, count(DISTINCT e.student_id) AS n FROM public.supervisor_scan_events e
    WHERE e.result = 'checked_in' AND e.ride_date IN (SELECT d FROM days) GROUP BY 1
  ),
  dev AS (SELECT platform, app_version FROM public.push_devices WHERE disabled_at IS NULL),
  outbox AS (
    SELECT count(*) FILTER (WHERE status = 'accepted') AS ok, count(*) FILTER (WHERE status = 'failed') AS bad
    FROM public.push_outbox WHERE updated_at > now() - interval '7 days' AND status IN ('accepted', 'failed')
  )
  SELECT jsonb_build_object(
    'daily', COALESCE((SELECT jsonb_agg(jsonb_build_object('date', d.d, 'confirmed', d.n, 'boarded', COALESCE(b.n, 0)) ORDER BY d.d)
                       FROM days d LEFT JOIN board b ON b.d = d.d), '[]'::jsonb),
    'devices', jsonb_build_object('ios', (SELECT count(*) FROM dev WHERE platform = 'ios'),
                                  'android', (SELECT count(*) FROM dev WHERE platform = 'android')),
    'app_versions', COALESCE((SELECT jsonb_agg(jsonb_build_object('platform', platform, 'version', version, 'devices', n)
                                               ORDER BY platform, CASE WHEN version ~ '^\d+(\.\d+){0,2}$' THEN public.app_version_parts(version) END DESC NULLS LAST, n DESC)
                              FROM (SELECT platform, COALESCE(NULLIF(btrim(app_version), ''), '?') AS version, count(*) AS n
                                    FROM dev GROUP BY 1, 2) x), '[]'::jsonb),
    'latest', (SELECT jsonb_object_agg(v.platform, v.latest_version) FROM public.app_versions v),
    'push_7d', (SELECT jsonb_build_object('accepted', ok, 'failed', bad,
                                          'failure_rate', CASE WHEN ok + bad > 0 THEN round(bad::numeric / (ok + bad), 3) END) FROM outbox)
  ) INTO v_usage;

  -- ---------------------------------------------------------------- insights
  -- Rule-based, from the numbers above; at most three cards per rule, 'act' first.
  WITH co AS (SELECT x FROM jsonb_array_elements(v_companies->'list') x),
  ver AS (
    SELECT d.platform, v.latest_version AS latest, count(*) AS total,
           count(*) FILTER (WHERE public.app_version_parts(d.app_version) < public.app_version_parts(v.latest_version)) AS old
    FROM public.push_devices d JOIN public.app_versions v ON v.platform = d.platform
    WHERE d.disabled_at IS NULL AND NULLIF(btrim(d.app_version), '') IS NOT NULL AND d.app_version ~ '^\d+(\.\d+){0,2}$'
    GROUP BY 1, 2
  ),
  cps AS (
    SELECT (v_finance->>'cost_per_student')::numeric AS now_v, (v_finance->>'cost_per_student_before')::numeric AS before_v
  ),
  cand(key, severity, weight, data) AS (
    SELECT 'company_overdue', 'act', (o->>'amount')::numeric,
           jsonb_build_object('company_id', o->'company_id', 'name', o->'name', 'amount', o->'amount', 'oldest_due', o->'oldest_due',
                              'days', v_today - (o->>'oldest_due')::date)
    FROM jsonb_array_elements(v_finance->'overdue') o
    UNION ALL
    SELECT 'no_plan', 'act', count(*)::numeric,
           jsonb_build_object('count', count(*), 'companies', jsonb_agg(jsonb_build_object('id', x->'id', 'name', x->'name') ORDER BY x->>'name'))
    FROM co WHERE x->>'status' = 'active' AND x->'plan_fee' = 'null'::jsonb
    HAVING count(*) > 0
    UNION ALL
    SELECT 'unprofitable', 'act', v_costs - (v_finance->>'collected')::numeric,
           jsonb_build_object('costs', v_costs, 'collected', v_finance->'collected', 'loss', v_costs - (v_finance->>'collected')::numeric)
    WHERE v_costs > 0 AND v_costs > (v_finance->>'collected')::numeric
    UNION ALL
    SELECT 'company_inactive', 'watch',
           COALESCE(v_today - ((x->>'last_admin_seen')::timestamptz AT TIME ZONE 'Africa/Cairo')::date, 9999)::numeric,
           jsonb_build_object('company_id', x->'id', 'name', x->'name', 'last_seen', x->'last_admin_seen',
                              'days', v_today - ((x->>'last_admin_seen')::timestamptz AT TIME ZONE 'Africa/Cairo')::date)
    FROM co WHERE x->>'status' = 'active'
      AND (x->'last_admin_seen' = 'null'::jsonb OR (x->>'last_admin_seen')::timestamptz < now() - interval '14 days')
      -- A company created in the last two weeks has not had the time.
      AND (x->>'created_at')::timestamptz < now() - interval '14 days'
    UNION ALL
    SELECT 'company_declining', 'watch', ((x->>'subscribers_before')::numeric - (x->>'subscribers')::numeric),
           jsonb_build_object('company_id', x->'id', 'name', x->'name', 'now', x->'subscribers', 'before', x->'subscribers_before',
                              'pct', round(100 * (1 - (x->>'subscribers')::numeric / NULLIF((x->>'subscribers_before')::numeric, 0))))
    FROM co WHERE x->>'status' = 'active' AND x->'subscribers_before' <> 'null'::jsonb
      AND (x->>'subscribers_before')::int >= 10 AND (x->>'subscribers')::numeric <= 0.8 * (x->>'subscribers_before')::numeric
    UNION ALL
    SELECT 'slow_reviews', 'watch', (x->>'median_review_hours')::numeric,
           jsonb_build_object('company_id', x->'id', 'name', x->'name', 'median_hours', x->'median_review_hours', 'reviewed', x->'reviewed')
    FROM co WHERE x->>'status' = 'active' AND (x->>'reviewed')::int >= 5 AND (x->>'median_review_hours')::numeric > 24
    UNION ALL
    SELECT 'old_app_versions', 'watch', round(100.0 * old / NULLIF(total, 0)),
           jsonb_build_object('platform', platform, 'latest', latest, 'old', old, 'total', total, 'pct', round(100.0 * old / NULLIF(total, 0)))
    FROM ver WHERE total >= 5 AND old >= 0.25 * total
    UNION ALL
    SELECT 'cost_per_student_rising', 'watch', round(100 * (now_v / NULLIF(before_v, 0) - 1)),
           jsonb_build_object('now', now_v, 'before', before_v, 'pct', round(100 * (now_v / NULLIF(before_v, 0) - 1)))
    FROM cps WHERE now_v IS NOT NULL AND before_v > 0 AND now_v >= 1.1 * before_v
    UNION ALL
    SELECT 'university_opportunity', 'good', (u->>'students')::numeric,
           jsonb_build_object('university_id', u->'id', 'name', u->'name', 'students', u->'students', 'lines', u->'lines', 'companies', u->'companies')
    FROM jsonb_array_elements(v_students->'by_university') u
    WHERE u->'id' <> 'null'::jsonb AND (u->>'students')::int >= 20 AND (u->>'lines')::int <= 1
  ),
  ranked AS (
    SELECT c.*, row_number() OVER (PARTITION BY c.key ORDER BY c.weight DESC NULLS LAST) AS k,
           CASE c.severity WHEN 'act' THEN 0 WHEN 'watch' THEN 1 ELSE 2 END AS sev
    FROM cand c
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('key', key, 'severity', severity, 'data', data) ORDER BY sev, key, weight DESC NULLS LAST), '[]'::jsonb)
  INTO v_insights FROM ranked WHERE k <= 3;

  RETURN jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', v_to, 'previous_from', v_prev_from, 'previous_to', v_prev_to),
    'finance', v_finance,
    'companies', v_companies,
    'students', v_students,
    'usage', v_usage,
    'insights', v_insights
  );
END;
$$;
REVOKE ALL ON FUNCTION public.platform_analytics(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_analytics(date, date) TO authenticated;

COMMIT;
