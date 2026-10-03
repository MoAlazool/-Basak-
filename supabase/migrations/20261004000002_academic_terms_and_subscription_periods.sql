-- ==============================================================================
-- Migration: 20261004000002_academic_terms_and_subscription_periods.sql
-- Run AFTER 20261004000001_supervisor_lines_and_permissions.sql. Safe to re-run.
--
--   1. academic_terms: the ONE place where semester dates live.
--        First semester   5 Sep -> 30 Jan
--        Second semester  1 Feb -> 30 Jun
--        Summer           1 Jul ->  1 Sep
--      Annual = every term flagged included_in_annual (first + second).
--      Every date used by subscriptions, receipts, expiry, dashboards and the
--      app is computed from this table by academic_periods().
--   2. Annual subscriptions can be switched off globally (super admin,
--      app_settings) and per company (company admin / super admin).
--   3. Subscriptions belong to a period (period_code + academic_year) with
--      server-computed dates. A student may hold one subscription per period,
--      so the next semester can be paid in advance: periods of the same student
--      may not overlap (exclusion constraint), replacing the old
--      "one pending/active subscription per student" index.
--   4. period_phase (current / upcoming / expired) and period_label are
--      exposed as computed fields for the dashboard and the app.
-- ==============================================================================
BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

-- ------------------------------------------------------------------------------
-- 1. Terms configuration
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.academic_terms (
  code text PRIMARY KEY CHECK (code IN ('first', 'second', 'summer')),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  sort_order int NOT NULL,
  -- Dates of academic year Y (e.g. 2026 = 2026/2027): make_date(Y + offset, month, day)
  start_month int NOT NULL CHECK (start_month BETWEEN 1 AND 12),
  start_day int NOT NULL CHECK (start_day BETWEEN 1 AND 31),
  start_year_offset int NOT NULL CHECK (start_year_offset IN (0, 1)),
  end_month int NOT NULL CHECK (end_month BETWEEN 1 AND 12),
  end_day int NOT NULL CHECK (end_day BETWEEN 1 AND 31),
  end_year_offset int NOT NULL CHECK (end_year_offset IN (0, 1)),
  included_in_annual boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

INSERT INTO public.academic_terms
  (code, name, sort_order, start_month, start_day, start_year_offset, end_month, end_day, end_year_offset, included_in_annual)
VALUES
  ('first',  'الفصل الدراسي الأول',  1, 9, 5, 0, 1, 30, 1, true),
  ('second', 'الفصل الدراسي الثاني', 2, 2, 1, 1, 6, 30, 1, true),
  ('summer', 'الفصل الصيفي',         3, 7, 1, 1, 9, 1,  1, false)
ON CONFLICT (code) DO NOTHING;

-- Concrete periods of one academic year, including the annual period.
CREATE OR REPLACE FUNCTION public.academic_periods(p_academic_year int)
RETURNS TABLE (
  period_code text, academic_year int, name text, label text, subscription_type text,
  start_date date, end_date date, included_in_annual boolean, sort_order int
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH t AS (
    SELECT code, name, sort_order, included_in_annual,
           make_date(p_academic_year + start_year_offset, start_month, start_day) AS s,
           make_date(p_academic_year + end_year_offset, end_month, end_day) AS e
    FROM public.academic_terms WHERE is_active
  )
  SELECT code, p_academic_year, name,
         name || ' ' || p_academic_year || '/' || (p_academic_year + 1),
         'termly', s, e, included_in_annual, sort_order
  FROM t
  UNION ALL
  SELECT 'annual', p_academic_year, 'اشتراك سنوي',
         'اشتراك سنوي ' || p_academic_year || '/' || (p_academic_year + 1),
         'yearly', min(s), max(e), false, 100
  FROM t WHERE included_in_annual HAVING count(*) > 0
$$;

CREATE OR REPLACE FUNCTION public.assert_academic_terms_valid()
RETURNS void LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  r record;
  v_prev_end date;
  y int;
BEGIN
  -- 2026..2028 covers leap and non-leap years for every offset.
  FOR y IN 2026..2028 LOOP
    v_prev_end := NULL;
    FOR r IN SELECT * FROM public.academic_periods(y) WHERE period_code <> 'annual' ORDER BY start_date LOOP
      IF r.end_date <= r.start_date THEN
        RAISE EXCEPTION 'تاريخ نهاية "%" يجب أن يكون بعد تاريخ بدايته.', r.name USING ERRCODE = '23514';
      END IF;
      IF v_prev_end IS NOT NULL AND r.start_date <= v_prev_end THEN
        RAISE EXCEPTION 'الفصل "%" يتداخل مع الفصل السابق له.', r.name USING ERRCODE = '23514';
      END IF;
      v_prev_end := r.end_date;
    END LOOP;
  END LOOP;
EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
  RAISE EXCEPTION 'تاريخ غير صالح في إعدادات الفصول الدراسية.' USING ERRCODE = '23514';
END;
$$;
CREATE OR REPLACE FUNCTION public.validate_academic_terms()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  PERFORM public.assert_academic_terms_valid();
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_validate_academic_terms ON public.academic_terms;
CREATE TRIGGER trg_validate_academic_terms
AFTER INSERT OR UPDATE OR DELETE ON public.academic_terms
FOR EACH STATEMENT EXECUTE FUNCTION public.validate_academic_terms();

CREATE OR REPLACE FUNCTION public.touch_academic_term()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  NEW.code := OLD.code;  -- codes are fixed identifiers
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_touch_academic_term ON public.academic_terms;
CREATE TRIGGER trg_touch_academic_term
BEFORE UPDATE ON public.academic_terms
FOR EACH ROW EXECUTE FUNCTION public.touch_academic_term();

ALTER TABLE public.academic_terms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.academic_terms FROM anon;
REVOKE INSERT, DELETE ON public.academic_terms FROM authenticated;
GRANT SELECT, UPDATE ON public.academic_terms TO authenticated;
DROP POLICY IF EXISTS academic_terms_read ON public.academic_terms;
CREATE POLICY academic_terms_read ON public.academic_terms FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS academic_terms_super_update ON public.academic_terms;
CREATE POLICY academic_terms_super_update ON public.academic_terms FOR UPDATE TO authenticated
USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- ------------------------------------------------------------------------------
-- 2. Annual subscription switch (global + per company)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  annual_subscription_enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
INSERT INTO public.app_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_settings FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.app_settings FROM authenticated;  -- via set_annual_subscription()
GRANT SELECT ON public.app_settings TO authenticated;
DROP POLICY IF EXISTS app_settings_read ON public.app_settings;
CREATE POLICY app_settings_read ON public.app_settings FOR SELECT TO authenticated USING (true);

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS annual_subscription_enabled boolean NOT NULL DEFAULT true;

-- Effective switch: global AND company (NULL company = global only).
CREATE OR REPLACE FUNCTION public.annual_subscription_enabled(p_company_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT annual_subscription_enabled FROM public.app_settings WHERE id), false)
     AND (p_company_id IS NULL OR COALESCE(
       (SELECT c.annual_subscription_enabled FROM public.companies c WHERE c.id = p_company_id), false))
$$;
GRANT EXECUTE ON FUNCTION public.annual_subscription_enabled(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_annual_subscription(p_enabled boolean, p_company_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_enabled IS NULL THEN RAISE EXCEPTION 'قيمة غير صالحة.'; END IF;
  IF p_company_id IS NULL THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'الإعداد العام متاح لمدير النظام فقط.' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_settings SET annual_subscription_enabled = p_enabled, updated_at = now(), updated_by = auth.uid() WHERE id;
  ELSE
    IF NOT (public.is_super_admin() OR (public.is_company_admin() AND p_company_id = public.current_admin_company_id())) THEN
      RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
    END IF;
    UPDATE public.companies SET annual_subscription_enabled = p_enabled WHERE id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.'; END IF;
  END IF;
  RETURN jsonb_build_object('global', public.annual_subscription_enabled(NULL),
    'company_id', p_company_id,
    'effective', public.annual_subscription_enabled(p_company_id));
END;
$$;
REVOKE ALL ON FUNCTION public.set_annual_subscription(boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_annual_subscription(boolean, uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. Which periods can be paid now
-- ------------------------------------------------------------------------------
-- termly: the current term (if any) and the next term (advance payment).
-- yearly: the annual period while its first term is current, or when it is the
--         next period to start; only if annual is enabled for the line's company.
CREATE OR REPLACE FUNCTION public.get_purchasable_periods(p_line_id uuid DEFAULT NULL, p_on date DEFAULT NULL)
RETURNS TABLE (
  period_code text, academic_year int, name text, label text, subscription_type text,
  start_date date, end_date date, phase text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  d date := COALESCE(p_on, public.cairo_today());
  y int := extract(year FROM COALESCE(p_on, public.cairo_today()))::int;
  v_annual boolean;
  v_company uuid;
BEGIN
  IF p_line_id IS NOT NULL THEN
    SELECT l.company_id INTO v_company FROM public.lines l WHERE l.id = p_line_id;
    v_annual := v_company IS NOT NULL AND public.annual_subscription_enabled(v_company);
  ELSE
    v_annual := public.annual_subscription_enabled(NULL);
  END IF;

  RETURN QUERY
  WITH all_p AS (
    SELECT * FROM public.academic_periods(y - 1)
    UNION ALL SELECT * FROM public.academic_periods(y)
    UNION ALL SELECT * FROM public.academic_periods(y + 1)
  ),
  terms AS (SELECT * FROM all_p a WHERE a.subscription_type = 'termly' AND a.end_date >= d),
  cur AS (SELECT * FROM terms t WHERE t.start_date <= d ORDER BY t.start_date LIMIT 1),
  nxt AS (SELECT * FROM terms t WHERE t.start_date > d ORDER BY t.start_date LIMIT 1),
  annual AS (
    SELECT a.* FROM all_p a
    WHERE a.subscription_type = 'yearly' AND v_annual AND a.end_date >= d
      AND (
        -- its first included term is running now
        (a.start_date <= d AND d <= (SELECT min(t.end_date) FROM all_p t
                                     WHERE t.academic_year = a.academic_year AND t.included_in_annual))
        -- or it is the very next period to start
        OR a.start_date = (SELECT n.start_date FROM nxt n)
      )
  ),
  picked AS (
    SELECT * FROM cur UNION ALL SELECT * FROM nxt UNION ALL SELECT * FROM annual
  )
  SELECT p.period_code, p.academic_year, p.name, p.label, p.subscription_type, p.start_date, p.end_date,
         CASE WHEN p.start_date <= d THEN 'current' ELSE 'upcoming' END
  FROM picked p
  ORDER BY p.start_date, p.subscription_type;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_purchasable_periods(uuid, date) TO authenticated;

-- The period a legacy (period-less) subscription belongs to: the period
-- containing p_date, otherwise the next one.
CREATE OR REPLACE FUNCTION public.period_for_date(p_type text, p_date date)
RETURNS TABLE (period_code text, academic_year int, start_date date, end_date date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.period_code, a.academic_year, a.start_date, a.end_date
  FROM (
    SELECT * FROM public.academic_periods(extract(year FROM p_date)::int - 1)
    UNION ALL SELECT * FROM public.academic_periods(extract(year FROM p_date)::int)
    UNION ALL SELECT * FROM public.academic_periods(extract(year FROM p_date)::int + 1)
  ) a
  WHERE a.subscription_type = CASE WHEN p_type = 'yearly' THEN 'yearly' ELSE 'termly' END
    AND a.end_date >= p_date
  ORDER BY (a.start_date <= p_date) DESC, a.start_date
  LIMIT 1
$$;

-- ------------------------------------------------------------------------------
-- 4. Subscriptions belong to periods
-- ------------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS period_code text,
  ADD COLUMN IF NOT EXISTS academic_year int,
  -- When the subscription was paid (receipt approved, cash daily, admin activation).
  -- Revenue uses this, so a paid semester still counts after it expires and an
  -- unpaid period that ended (also 'expired') never does.
  ADD COLUMN IF NOT EXISTS paid_at timestamptz;

UPDATE public.subscriptions s
SET paid_at = COALESCE(
  (SELECT max(r.reviewed_at) FROM public.receipts r WHERE r.subscription_id = s.id AND r.status = 'approved'),
  s.created_at)
-- Before this migration only active rows were ever expired, so both were paid.
WHERE s.paid_at IS NULL AND s.status IN ('active', 'expired');

ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_period_check;
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_period_check CHECK (
  period_code IS NULL
  OR (type = 'yearly' AND period_code = 'annual' AND academic_year IS NOT NULL)
  OR (type = 'termly' AND period_code IN ('first', 'second', 'summer') AND academic_year IS NOT NULL)
);

-- Backfill: open termly/yearly subscriptions move onto the configured periods.
-- Active ones use the period containing their start date; unpaid ones the
-- current (or next) period.
WITH fix AS (
  SELECT s.id, p.period_code, p.academic_year, p.start_date, p.end_date
  FROM public.subscriptions s
  CROSS JOIN LATERAL public.period_for_date(s.type,
    CASE WHEN s.status = 'active' AND s.start_date IS NOT NULL THEN s.start_date ELSE public.cairo_today() END) p
  WHERE s.type IN ('termly', 'yearly') AND s.period_code IS NULL
    AND s.status IN ('pending_payment', 'pending_review', 'active')
)
UPDATE public.subscriptions s
SET period_code = fix.period_code, academic_year = fix.academic_year,
    start_date = fix.start_date, end_date = fix.end_date
FROM fix WHERE fix.id = s.id;

ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_dates_order;
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_dates_order
  CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date) NOT VALID;

-- One subscription per period: open subscriptions of a student may not overlap.
DROP INDEX IF EXISTS public.idx_one_active_sub_per_student;
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_no_overlap;
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_no_overlap
  EXCLUDE USING gist (student_id WITH =, daterange(start_date, end_date, '[]') WITH &&)
  WHERE (status IN ('pending_payment', 'pending_review', 'active'));
CREATE INDEX IF NOT EXISTS idx_subscriptions_period ON public.subscriptions(academic_year, period_code);

-- Server-owned fields on insert (replaces the 20261002000002 version).
CREATE OR REPLACE FUNCTION public.enforce_subscription_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line record;
  v_ride_date date;
  v_period record;
  v_privileged boolean := auth.uid() IS NULL OR public.is_admin();
BEGIN
  PERFORM public.expire_finished_subscriptions(NEW.student_id);

  SELECT l.price_termly, l.price_yearly, l.price_daily, l.is_active, l.company_id, c.is_active AS company_active
  INTO v_line
  FROM public.lines l JOIN public.companies c ON c.id = l.company_id
  WHERE l.id = NEW.line_id;

  IF NOT v_privileged THEN
    IF NEW.student_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'لا يمكن إنشاء اشتراك لحساب آخر.';
    END IF;
    IF NOT FOUND OR NOT v_line.is_active OR NOT v_line.company_active THEN
      RAISE EXCEPTION 'هذا الخط غير متاح للاشتراك حالياً.';
    END IF;
    NEW.price := CASE NEW.type
      WHEN 'termly' THEN v_line.price_termly
      WHEN 'yearly' THEN v_line.price_yearly
      ELSE v_line.price_daily
    END;
    NEW.created_at := now();
  END IF;

  IF NEW.type = 'daily' THEN
    NEW.period_code := NULL;
    NEW.academic_year := NULL;
    IF NOT v_privileged OR NEW.start_date IS NULL THEN
      -- Cash on the bus: active immediately, valid for the next votable ride.
      v_ride_date := public.next_votable_ride_date();
      NEW.status := 'active';
      NEW.start_date := v_ride_date;
      NEW.end_date := v_ride_date;
    END IF;
  ELSE
    IF NEW.type = 'yearly' AND NOT public.annual_subscription_enabled(v_line.company_id) THEN
      RAISE EXCEPTION 'الاشتراك السنوي غير متاح حالياً.' USING ERRCODE = '23514';
    END IF;

    IF NEW.period_code IS NULL OR NEW.academic_year IS NULL THEN
      -- Older clients: the current period, otherwise the next one.
      SELECT * INTO v_period FROM public.get_purchasable_periods(NEW.line_id) p
      WHERE p.subscription_type = NEW.type ORDER BY p.start_date LIMIT 1;
    ELSE
      SELECT * INTO v_period FROM public.get_purchasable_periods(NEW.line_id) p
      WHERE p.subscription_type = NEW.type AND p.period_code = NEW.period_code
        AND p.academic_year = NEW.academic_year;
    END IF;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'فترة الاشتراك المختارة غير متاحة للدفع الآن.' USING ERRCODE = '23514';
    END IF;

    NEW.period_code := v_period.period_code;
    NEW.academic_year := v_period.academic_year;
    NEW.start_date := v_period.start_date;
    NEW.end_date := v_period.end_date;
    IF NOT v_privileged THEN
      NEW.status := 'pending_payment';
    END IF;
  END IF;

  NEW.paid_at := CASE WHEN NEW.status = 'active' THEN COALESCE(NEW.paid_at, now()) END;

  IF NEW.status IN ('pending_payment', 'pending_review', 'active') AND EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.student_id = NEW.student_id AND s.status IN ('pending_payment', 'pending_review', 'active')
      AND daterange(s.start_date, s.end_date, '[]') && daterange(NEW.start_date, NEW.end_date, '[]')
  ) THEN
    RAISE EXCEPTION 'لديك اشتراك يغطي هذه الفترة بالفعل.' USING ERRCODE = '23P01';
  END IF;

  RETURN NEW;
END;
$$;

-- Expiry: finished paid periods and unpaid periods that already ended.
DROP FUNCTION IF EXISTS public.expire_finished_subscriptions();
CREATE OR REPLACE FUNCTION public.expire_finished_subscriptions(p_student_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  UPDATE public.subscriptions
  SET status = 'expired'
  WHERE status IN ('active', 'pending_payment')
    AND end_date IS NOT NULL AND end_date < public.cairo_today()
    AND (p_student_id IS NULL OR student_id = p_student_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.expire_finished_subscriptions(uuid) FROM PUBLIC, anon, authenticated;
SELECT public.expire_finished_subscriptions();

-- Activation keeps the period dates; legacy rows without dates get a period.
CREATE OR REPLACE FUNCTION public.guard_subscription_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_period record;
BEGIN
  IF pg_trigger_depth() <= 1 AND auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'تعديل الاشتراك متاح للإدارة فقط. اعتماد الدفع يتم من خلال الإيصال.';
  END IF;

  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
    NEW.paid_at := COALESCE(NEW.paid_at, now());
  ELSIF NEW.status IN ('pending_payment', 'pending_review') THEN
    NEW.paid_at := NULL;  -- e.g. an admin reverting an activation
  END IF;

  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' AND NEW.end_date IS NULL THEN
    IF NEW.type IN ('termly', 'yearly') THEN
      SELECT * INTO v_period FROM public.period_for_date(NEW.type, COALESCE(NEW.start_date, public.cairo_today()));
      NEW.period_code := v_period.period_code;
      NEW.academic_year := v_period.academic_year;
      NEW.start_date := v_period.start_date;
      NEW.end_date := v_period.end_date;
    ELSE
      NEW.start_date := COALESCE(NEW.start_date, public.next_votable_ride_date());
      NEW.end_date := NEW.start_date;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Admin edits of the term dates follow through to open subscriptions.
CREATE OR REPLACE FUNCTION public.refresh_subscription_period_dates()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Validate before touching subscriptions (statement triggers fire by name).
  PERFORM public.assert_academic_terms_valid();
  UPDATE public.subscriptions s
  SET start_date = p.start_date, end_date = p.end_date
  FROM public.subscriptions x
  CROSS JOIN LATERAL public.academic_periods(x.academic_year) p
  WHERE x.id = s.id AND p.period_code = x.period_code
    AND x.status IN ('pending_payment', 'pending_review', 'active')
    AND (x.start_date IS DISTINCT FROM p.start_date OR x.end_date IS DISTINCT FROM p.end_date);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_refresh_subscription_period_dates ON public.academic_terms;
CREATE TRIGGER trg_refresh_subscription_period_dates
AFTER UPDATE ON public.academic_terms
FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_subscription_period_dates();

-- Computed fields: ?select=*,period_phase,period_label
CREATE OR REPLACE FUNCTION public.period_phase(s public.subscriptions)
RETURNS text LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN s.status = 'expired' OR s.end_date < public.cairo_today() THEN 'expired'
    WHEN s.start_date > public.cairo_today() THEN 'upcoming'
    ELSE 'current'
  END
$$;
CREATE OR REPLACE FUNCTION public.period_label(s public.subscriptions)
RETURNS text LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN s.type = 'daily' THEN 'اشتراك يومي'
    ELSE (SELECT p.label FROM public.academic_periods(s.academic_year) p WHERE p.period_code = s.period_code)
  END
$$;
GRANT EXECUTE ON FUNCTION public.period_phase(public.subscriptions), public.period_label(public.subscriptions) TO authenticated;

-- ------------------------------------------------------------------------------
-- 5. Receipts: belong to their subscription's folder, snapshot the amount,
--    activate without moving the period.
-- ------------------------------------------------------------------------------
ALTER TABLE public.receipts ADD COLUMN IF NOT EXISTS amount numeric(10, 2);
UPDATE public.receipts r SET amount = s.price
FROM public.subscriptions s WHERE s.id = r.subscription_id AND r.amount IS NULL;

CREATE OR REPLACE FUNCTION public.handle_new_receipt_upload()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub record;
  v_last_attempt int;
BEGIN
  SELECT * INTO v_sub FROM public.subscriptions WHERE id = NEW.subscription_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الاشتراك غير موجود.'; END IF;
  IF v_sub.type = 'daily' THEN
    RAISE EXCEPTION 'الاشتراك اليومي يُدفع نقداً ولا يحتاج إيصالاً.';
  END IF;
  IF v_sub.status = 'active' THEN
    RAISE EXCEPTION 'Subscription is already active. Cannot upload further receipts.';
  END IF;
  IF v_sub.status = 'expired' OR v_sub.end_date < public.cairo_today() THEN
    RAISE EXCEPTION 'انتهت فترة هذا الاشتراك. اختر الفترة الحالية أو القادمة.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.receipts WHERE subscription_id = NEW.subscription_id AND status = 'pending') THEN
    RAISE EXCEPTION 'يوجد إيصال قيد المراجعة لهذا الاشتراك بالفعل.';
  END IF;
  -- The image must be the student's own object for this subscription:
  -- receipts/{student_id}/{subscription_id}_{timestamp}.{ext}
  IF split_part(NEW.image_url, '/', 1) <> v_sub.student_id::text
     OR left(split_part(NEW.image_url, '/', 2), length(v_sub.id::text) + 1) <> v_sub.id::text || '_' THEN
    RAISE EXCEPTION 'مسار صورة الإيصال لا يطابق الاشتراك.' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(MAX(attempt_number), 0) INTO v_last_attempt
  FROM public.receipts WHERE subscription_id = NEW.subscription_id;
  IF v_last_attempt >= 5 THEN
    RAISE EXCEPTION 'Maximum receipt upload limit reached (5 attempts: initial + 4 re-uploads).';
  END IF;

  NEW.attempt_number := v_last_attempt + 1;
  NEW.status := 'pending';
  NEW.rejection_reason := NULL;
  NEW.reviewed_by := NULL;
  NEW.reviewed_at := NULL;
  NEW.amount := v_sub.price;
  NEW.created_at := now();

  UPDATE public.subscriptions SET status = 'pending_review' WHERE id = NEW.subscription_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_receipt_review()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status <> 'pending' THEN
      RAISE EXCEPTION 'تمت مراجعة هذا الإيصال بالفعل.';
    END IF;
    NEW.reviewed_at := now();
    NEW.reviewed_by := auth.uid();

    IF NEW.status = 'approved' THEN
      -- Dates were fixed by the period on creation (guard trigger fills legacy rows).
      UPDATE public.subscriptions SET status = 'active' WHERE id = NEW.subscription_id;
    ELSIF NEW.status = 'rejected' THEN
      IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
        RAISE EXCEPTION 'A written rejection reason is mandatory when rejecting a receipt.';
      END IF;
      UPDATE public.subscriptions SET status = 'pending_payment' WHERE id = NEW.subscription_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. A student can now hold a current AND an upcoming paid subscription.
--    Rider counts must only use the subscription valid on the ride date.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_line_rider_counts(p_line_id uuid, p_ride_date date)
RETURNS TABLE (
  station_id uuid, station_name text, order_index integer,
  departure_time time, return_time time, riding_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()
    ))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;

  RETURN QUERY
  SELECT st.id, st.name, st.order_index, st.departure_time, st.return_time,
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true)
  FROM public.stations st
  LEFT JOIN public.subscriptions sub ON sub.station_id = st.id AND sub.status = 'active'
    AND COALESCE(sub.start_date, p_ride_date) <= p_ride_date AND COALESCE(sub.end_date, p_ride_date) >= p_ride_date
  LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
  WHERE st.line_id = p_line_id
  GROUP BY st.id, st.name, st.order_index, st.departure_time, st.return_time
  ORDER BY st.order_index;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_line_rider_counts_with_returns(p_line_id uuid, p_ride_date date)
RETURNS TABLE (
  line_id uuid, line_name text, station_id uuid, station_name text, order_index integer,
  departure_time time, return_time time, riding_count bigint, returning_count bigint,
  schedule_id uuid, university_name text
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;

  RETURN QUERY
  WITH valid_subs AS (
    SELECT s.* FROM public.subscriptions s
    WHERE s.line_id = p_line_id AND s.status = 'active'
      AND COALESCE(s.start_date, p_ride_date) <= p_ride_date AND COALESCE(s.end_date, p_ride_date) >= p_ride_date
  ),
  trips AS (
    SELECT sch.id AS trip_schedule_id, sch.departure_time AS trip_departure,
           sch.return_time AS trip_return, u.name AS trip_university
    FROM public.line_university_schedules sch
    JOIN public.universities u ON u.id = sch.university_id
    WHERE sch.line_id = p_line_id
      AND (sch.is_active OR EXISTS (SELECT 1 FROM valid_subs s WHERE s.schedule_id = sch.id))
    UNION ALL
    SELECT NULL::uuid, NULL::time, NULL::time, NULL::text
    WHERE NOT public.line_uses_university_schedules(p_line_id)
       OR EXISTS (SELECT 1 FROM valid_subs s WHERE s.schedule_id IS NULL)
  )
  SELECT l.id, l.name, st.id, st.name, st.order_index,
    COALESCE(t.trip_departure, st.departure_time, st.departure_times[1], MIN(sub.departure_time)),
    COALESCE(t.trip_return, st.return_time, st.return_times[1], MIN(sub.return_time)),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true AND drs.is_returning = true),
    t.trip_schedule_id, t.trip_university
  FROM public.stations st
  JOIN public.lines l ON l.id = st.line_id
  CROSS JOIN trips t
  LEFT JOIN valid_subs sub ON sub.station_id = st.id
    AND sub.schedule_id IS NOT DISTINCT FROM t.trip_schedule_id
  LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
  WHERE st.line_id = p_line_id AND st.is_active = true AND l.is_active = true
  GROUP BY l.id, l.name, st.id, st.name, st.order_index, st.departure_time, st.departure_times,
    st.return_time, st.return_times, t.trip_schedule_id, t.trip_departure, t.trip_return, t.trip_university
  ORDER BY t.trip_departure NULLS LAST, st.order_index;
END;
$$;

-- Deleted accounts archive only what was actually paid for.
CREATE OR REPLACE FUNCTION public.archive_student_revenue_before_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.deleted_student_revenue (
    source_subscription_id, line_id, line_name, company_name, company_id, amount, subscription_type
  )
  SELECT sub.id, sub.line_id, l.name, c.name, l.company_id, sub.price, sub.type
  FROM public.subscriptions sub
  LEFT JOIN public.lines l ON l.id = sub.line_id
  LEFT JOIN public.companies c ON c.id = l.company_id
  WHERE sub.student_id = OLD.id AND sub.paid_at IS NOT NULL
  ON CONFLICT (source_subscription_id) DO NOTHING;
  RETURN OLD;
END;
$$;

-- Settings snapshot for the dashboards (scoped to the caller).
CREATE OR REPLACE FUNCTION public.get_subscription_settings()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE y int := extract(year FROM public.cairo_today())::int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'متاح للمسؤولين فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'annual_global', public.annual_subscription_enabled(NULL),
    'can_edit_global', public.is_super_admin(),
    'terms', (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.sort_order) FROM public.academic_terms t),
    'periods', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.start_date)
                FROM (SELECT * FROM public.academic_periods(y - 1) UNION ALL SELECT * FROM public.academic_periods(y)) p
                WHERE p.end_date >= public.cairo_today()),
    'purchasable', (SELECT jsonb_agg(to_jsonb(p)) FROM public.get_purchasable_periods(NULL) p),
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name,
               'annual_enabled', c.annual_subscription_enabled,
               'effective', public.annual_subscription_enabled(c.id)) ORDER BY c.name)
      FROM public.companies c
      WHERE public.is_super_admin() OR c.id = public.current_admin_company_id()), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_subscription_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_settings() TO authenticated;

COMMIT;

-- OPTIONAL (pg_cron): nightly expiry at 01:05 Cairo
--   SELECT cron.schedule('basak-expire-subscriptions', '5 22 * * *',
--                        $$SELECT public.expire_finished_subscriptions()$$);
