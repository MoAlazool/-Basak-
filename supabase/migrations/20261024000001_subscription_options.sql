-- Subscription options a company sells, priced per line.
--   * options: first | second | both | summer. "both" = the first and second
--     semesters only (it replaces "annual"); summer is always separate.
--   * line_period_prices: one price and one on/off switch per line and option
--   * company_terms.is_on_sale and companies.advance_subscription_enabled
--   * line_sale_options(): the one rule deciding what can be bought. The catalog,
--     the dashboard preview and the insert check all read it.
--   * get_subscription_catalog(): lines for the signed-in student, described by
--     their own university, stations and the trips that stop at each station
--   * companies_for_university(): company names for the sign-up screen
--   * subscription_receipts: proof of payment, written once and never changed
-- The released app keeps working: type 'yearly', lines.price_termly/price_yearly,
-- get_student_catalog() and get_purchasable_periods() (which still says 'annual')
-- stay as a compatibility layer over the new model.

-- ---------------------------------------------------------------------------
-- 1. What a company sells
-- ---------------------------------------------------------------------------
ALTER TABLE public.company_terms ADD COLUMN IF NOT EXISTS is_on_sale boolean NOT NULL DEFAULT true;
ALTER TABLE public.academic_terms ADD COLUMN IF NOT EXISTS is_on_sale boolean NOT NULL DEFAULT true;
-- Summer is an extra the company switches on.
UPDATE public.company_terms SET is_on_sale = false WHERE code = 'summer';
UPDATE public.academic_terms SET is_on_sale = false WHERE code = 'summer';

-- Paying for the next period while one is still running.
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS advance_subscription_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.copy_default_terms(p_company_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.company_terms (company_id, code, name, sort_order, start_month, start_day, start_year_offset,
                                    end_month, end_day, end_year_offset, included_in_annual, is_active, is_on_sale)
  SELECT p_company_id, code, name, sort_order, start_month, start_day, start_year_offset,
         end_month, end_day, end_year_offset, included_in_annual, is_active, is_on_sale
  FROM public.academic_terms
  ON CONFLICT (company_id, code) DO NOTHING
$$;
REVOKE ALL ON FUNCTION public.copy_default_terms(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. "both" replaces "annual"
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_period_check;
UPDATE public.subscriptions SET period_code = 'both' WHERE period_code = 'annual';
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_period_check CHECK (
  period_code IS NULL
  OR (type = 'yearly' AND period_code = 'both' AND academic_year IS NOT NULL)
  OR (type = 'termly' AND period_code IN ('first', 'second', 'summer') AND academic_year IS NOT NULL));

-- The periods of one company for an academic year. NULL = the platform defaults.
-- "both" runs from the first day of the first semester to the last day of the second.
CREATE OR REPLACE FUNCTION public.company_periods(p_company_id uuid, p_academic_year integer)
RETURNS TABLE(period_code text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, included_in_annual boolean, sort_order integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH src AS (
    SELECT code, name, sort_order, included_in_annual, start_month, start_day, start_year_offset,
           end_month, end_day, end_year_offset
    FROM public.company_terms WHERE company_id = p_company_id AND is_active
    UNION ALL
    SELECT code, name, sort_order, included_in_annual, start_month, start_day, start_year_offset,
           end_month, end_day, end_year_offset
    FROM public.academic_terms
    WHERE is_active AND NOT EXISTS (SELECT 1 FROM public.company_terms WHERE company_id = p_company_id)
  ),
  t AS (
    SELECT code, name, sort_order, included_in_annual,
           make_date(p_academic_year + start_year_offset, start_month, start_day) AS s,
           make_date(p_academic_year + end_year_offset, end_month, end_day) AS e
    FROM src
  )
  SELECT code, p_academic_year, name,
         name || ' ' || p_academic_year || '/' || (p_academic_year + 1),
         'termly', s, e, included_in_annual, sort_order
  FROM t
  UNION ALL
  SELECT 'both', p_academic_year, 'الفصلان معاً',
         'الفصلان معاً ' || p_academic_year || '/' || (p_academic_year + 1),
         'yearly', f.s, n.e, false, 100
  FROM t f JOIN t n ON f.code = 'first' AND n.code = 'second'
$$;

-- Terms of one company (NULL = the defaults) must not be inverted or overlap.
CREATE OR REPLACE FUNCTION public.assert_terms_valid(p_company_id uuid) RETURNS void
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  r record;
  v_prev_end date;
  y int;
BEGIN
  -- 2026..2028 covers leap and non-leap years for every offset.
  FOR y IN 2026..2028 LOOP
    v_prev_end := NULL;
    FOR r IN SELECT * FROM public.company_periods(p_company_id, y) WHERE subscription_type = 'termly' ORDER BY start_date LOOP
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

-- ---------------------------------------------------------------------------
-- 3. Prices per line, per option
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.line_period_prices (
  line_id uuid NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id),
  option text NOT NULL CHECK (option IN ('first', 'second', 'both', 'summer')),
  price numeric(10, 2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  is_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (line_id, option)
);
CREATE INDEX IF NOT EXISTS idx_line_period_prices_company ON public.line_period_prices(company_id);

DROP TRIGGER IF EXISTS trg_tenant_company ON public.line_period_prices;
CREATE TRIGGER trg_tenant_company BEFORE INSERT OR UPDATE OF line_id, company_id ON public.line_period_prices
  FOR EACH ROW EXECUTE FUNCTION public.tenant_company_from_parent('line');

ALTER TABLE public.line_period_prices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.line_period_prices FROM anon;
-- Students read prices through the catalog, which applies the sale rule.
DROP POLICY IF EXISTS line_period_prices_company_manage ON public.line_period_prices;
CREATE POLICY line_period_prices_company_manage ON public.line_period_prices FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())))
  WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
DROP POLICY IF EXISTS line_period_prices_read_scope ON public.line_period_prices;
CREATE POLICY line_period_prices_read_scope ON public.line_period_prices FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id())));

INSERT INTO public.line_period_prices (line_id, company_id, option, price, is_enabled)
SELECT l.id, l.company_id, o.option,
       CASE o.option WHEN 'both' THEN l.price_yearly ELSE l.price_termly END,
       CASE o.option WHEN 'both' THEN public.annual_subscription_enabled(l.company_id)
                     WHEN 'summer' THEN false ELSE true END
FROM public.lines l CROSS JOIN (VALUES ('first'), ('second'), ('both'), ('summer')) o(option)
ON CONFLICT (line_id, option) DO NOTHING;

-- lines.price_termly / price_yearly are a mirror for older clients:
-- price_termly = the first semester, price_yearly = both semesters.
CREATE OR REPLACE FUNCTION public.sync_line_prices_from_line() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.line_period_prices (line_id, company_id, option, price, is_enabled)
    SELECT NEW.id, NEW.company_id, o.option,
           CASE o.option WHEN 'both' THEN NEW.price_yearly ELSE NEW.price_termly END,
           CASE o.option WHEN 'both' THEN public.annual_subscription_enabled(NEW.company_id)
                         WHEN 'summer' THEN false ELSE true END
    FROM (VALUES ('first'), ('second'), ('both'), ('summer')) o(option)
    ON CONFLICT (line_id, option) DO NOTHING;
  ELSIF pg_trigger_depth() = 1 THEN
    -- An older dashboard saved the line: carry its two prices over.
    IF NEW.price_termly IS DISTINCT FROM OLD.price_termly THEN
      UPDATE public.line_period_prices SET price = NEW.price_termly, updated_at = now()
      WHERE line_id = NEW.id AND option IN ('first', 'second');
    END IF;
    IF NEW.price_yearly IS DISTINCT FROM OLD.price_yearly THEN
      UPDATE public.line_period_prices SET price = NEW.price_yearly, updated_at = now()
      WHERE line_id = NEW.id AND option = 'both';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_line_prices_from_line() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_sync_line_prices_from_line ON public.lines;
CREATE TRIGGER trg_sync_line_prices_from_line AFTER INSERT OR UPDATE OF price_termly, price_yearly ON public.lines
  FOR EACH ROW EXECUTE FUNCTION public.sync_line_prices_from_line();

CREATE OR REPLACE FUNCTION public.sync_line_from_prices() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF pg_trigger_depth() = 1 AND NEW.option IN ('first', 'both') THEN
    UPDATE public.lines
    SET price_termly = CASE WHEN NEW.option = 'first' THEN NEW.price ELSE price_termly END,
        price_yearly = CASE WHEN NEW.option = 'both' THEN NEW.price ELSE price_yearly END
    WHERE id = NEW.line_id
      AND (CASE WHEN NEW.option = 'first' THEN price_termly ELSE price_yearly END) IS DISTINCT FROM NEW.price;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_line_from_prices() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_sync_line_from_prices ON public.line_period_prices;
CREATE TRIGGER trg_sync_line_from_prices AFTER INSERT OR UPDATE OF price ON public.line_period_prices
  FOR EACH ROW EXECUTE FUNCTION public.sync_line_from_prices();

DROP TRIGGER IF EXISTS trg_announce_change ON public.line_period_prices;
CREATE TRIGGER trg_announce_change AFTER INSERT OR UPDATE OR DELETE ON public.line_period_prices
  FOR EACH ROW EXECUTE FUNCTION public.announce_change('line');

-- ---------------------------------------------------------------------------
-- 4. The one availability rule
-- ---------------------------------------------------------------------------
-- What a company sells on a day, before any line narrows it. One row per option
-- that exists in its calendar, with the reason when it is not available:
--   company_inactive     the company is suspended or archived
--   company_not_selling  the period is off sale (for "both": its switch is off,
--                        or the first or second semester is off sale)
--   advance_off          it is the next period, a period is running, and the
--                        company does not take advance payments
--   not_in_season        it is neither running nor next
-- "both" can be bought only until its first semester ends.
CREATE OR REPLACE FUNCTION public.company_sale_periods(p_company_id uuid, p_on date DEFAULT NULL)
RETURNS TABLE(option text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text, available boolean, reason text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  d date := COALESCE(p_on, public.cairo_today());
  y int := extract(year FROM COALESCE(p_on, public.cairo_today()))::int;
  v_company_ok boolean := p_company_id IS NULL OR EXISTS (
    SELECT 1 FROM public.companies c WHERE c.id = p_company_id AND c.is_active AND c.status = 'active');
  v_advance boolean := p_company_id IS NULL OR COALESCE(
    (SELECT c.advance_subscription_enabled FROM public.companies c WHERE c.id = p_company_id), false);
  v_both boolean := public.annual_subscription_enabled(p_company_id);
BEGIN
  RETURN QUERY
  WITH all_p AS (
    SELECT * FROM public.company_periods(p_company_id, y - 1)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, y)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, y + 1)
  ),
  sale AS (
    SELECT t.code, t.is_on_sale FROM public.company_terms t WHERE t.company_id = p_company_id
    UNION ALL
    SELECT t.code, t.is_on_sale FROM public.academic_terms t
    WHERE NOT EXISTS (SELECT 1 FROM public.company_terms x WHERE x.company_id = p_company_id)
  ),
  terms AS (
    SELECT a.*, COALESCE((SELECT s.is_on_sale FROM sale s WHERE s.code = a.period_code), false) AS sells
    FROM all_p a WHERE a.subscription_type = 'termly'
  ),
  clock AS (
    -- Only periods the company sells count as "running" or "next".
    SELECT EXISTS (SELECT 1 FROM terms t WHERE t.sells AND t.start_date <= d AND t.end_date >= d) AS in_term,
           (SELECT min(t.start_date) FROM terms t WHERE t.sells AND t.start_date > d) AS next_start
  ),
  cand AS (
    (SELECT DISTINCT ON (t.period_code) t.period_code, t.academic_year, t.name, t.label, t.subscription_type,
            t.start_date, t.end_date, t.sort_order, t.sells
     FROM terms t WHERE t.end_date >= d ORDER BY t.period_code, t.start_date)
    UNION ALL
    (SELECT a.period_code, a.academic_year, a.name, a.label, a.subscription_type, a.start_date, a.end_date, a.sort_order,
            v_both AND COALESCE((SELECT bool_and(s.is_on_sale) FROM sale s WHERE s.code IN ('first', 'second')), false)
     FROM all_p a
     WHERE a.period_code = 'both'
       AND (SELECT f.end_date FROM terms f WHERE f.period_code = 'first' AND f.academic_year = a.academic_year) >= d
     ORDER BY a.start_date LIMIT 1)
  ),
  judged AS (
    SELECT c.*, CASE
        WHEN NOT v_company_ok THEN 'company_inactive'
        WHEN NOT c.sells THEN 'company_not_selling'
        WHEN c.start_date <= d THEN NULL
        WHEN c.start_date = k.next_start AND (v_advance OR NOT k.in_term) THEN NULL
        WHEN c.start_date = k.next_start THEN 'advance_off'
        ELSE 'not_in_season' END AS why
    FROM cand c CROSS JOIN clock k
  )
  SELECT j.period_code, j.academic_year, j.name, j.label, j.subscription_type, j.start_date, j.end_date,
         CASE WHEN j.start_date <= d THEN 'current' ELSE 'upcoming' END, j.why IS NULL, j.why
  FROM judged j
  ORDER BY j.start_date, j.sort_order;
END;
$$;

-- What can be bought on one line. The company is the ceiling and the line can
-- only narrow it:
--   line_inactive      the line is switched off
--   line_not_offering  the line has this option switched off
--   no_price           the option has no price
--   overlap            the student already holds a subscription covering it
CREATE OR REPLACE FUNCTION public.line_sale_options_for(p_line_id uuid, p_on date, p_student_id uuid)
RETURNS TABLE(option text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text, price numeric, available boolean, reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.option, p.academic_year, p.name, p.label, p.subscription_type, p.start_date, p.end_date, p.phase,
         pr.price, w.why IS NULL, w.why
  FROM public.lines l
  CROSS JOIN LATERAL public.company_sale_periods(l.company_id, p_on) p
  LEFT JOIN public.line_period_prices pr ON pr.line_id = l.id AND pr.option = p.option
  CROSS JOIN LATERAL (SELECT CASE
      WHEN p.reason = 'company_inactive' THEN p.reason
      WHEN NOT l.is_active THEN 'line_inactive'
      WHEN p.reason = 'company_not_selling' THEN p.reason
      WHEN NOT COALESCE(pr.is_enabled, false) THEN 'line_not_offering'
      WHEN COALESCE(pr.price, 0) <= 0 THEN 'no_price'
      WHEN p.reason IS NOT NULL THEN p.reason
      WHEN p_student_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.subscriptions s
        WHERE s.student_id = p_student_id AND s.status IN ('pending_payment', 'pending_review', 'active')
          AND (s.end_date IS NULL OR s.end_date >= COALESCE(p_on, public.cairo_today()))
          AND daterange(s.start_date, s.end_date, '[]') && daterange(p.start_date, p.end_date, '[]')) THEN 'overlap'
    END AS why) w
  WHERE l.id = p_line_id
  ORDER BY p.start_date, p.subscription_type
$$;
REVOKE ALL ON FUNCTION public.company_sale_periods(uuid, date), public.line_sale_options_for(uuid, date, uuid)
  FROM PUBLIC, anon, authenticated;

-- For the signed-in caller: a student's own subscriptions are taken into account.
CREATE OR REPLACE FUNCTION public.line_sale_options(p_line_id uuid, p_on date DEFAULT NULL)
RETURNS TABLE(option text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text, price numeric, available boolean, reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.line_sale_options_for(p_line_id, p_on, auth.uid())
  WHERE public.can_manage_company((SELECT l.company_id FROM public.lines l WHERE l.id = p_line_id))
     OR EXISTS (SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.is_active
                  AND l.company_id IN (SELECT public.active_company_ids()))
$$;
REVOKE ALL ON FUNCTION public.line_sale_options(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.line_sale_options(uuid, date) TO authenticated, service_role;

-- Company-wide view of the same rule (settings page).
CREATE OR REPLACE FUNCTION public.company_purchasable_periods(p_company_id uuid, p_on date DEFAULT NULL)
RETURNS TABLE(period_code text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.option, p.academic_year, p.name, p.label, p.subscription_type, p.start_date, p.end_date, p.phase
  FROM public.company_sale_periods(p_company_id, p_on) p WHERE p.available
$$;

-- Older clients: same name, arguments and codes as before ("annual" for both).
CREATE OR REPLACE FUNCTION public.get_purchasable_periods(p_line_id uuid DEFAULT NULL, p_on date DEFAULT NULL)
RETURNS TABLE(period_code text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE o.option WHEN 'both' THEN 'annual' ELSE o.option END, o.academic_year, o.name, o.label,
         o.subscription_type, o.start_date, o.end_date, o.phase
  FROM public.line_sale_options_for(p_line_id, p_on, NULL) o
  WHERE p_line_id IS NOT NULL AND o.available
  UNION ALL
  -- No line at all previews the platform defaults.
  SELECT CASE p.period_code WHEN 'both' THEN 'annual' ELSE p.period_code END, p.academic_year, p.name, p.label,
         p.subscription_type, p.start_date, p.end_date, p.phase
  FROM public.company_purchasable_periods(NULL, p_on) p
  WHERE p_line_id IS NULL
$$;

-- ---------------------------------------------------------------------------
-- 5. Creating a subscription goes through the same rule
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_subscription_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line record;
  v_ride_date date;
  v_opt record;
  v_code text;
  v_reason text;
  v_privileged boolean := auth.uid() IS NULL OR public.is_admin();
BEGIN
  PERFORM public.expire_finished_subscriptions(NEW.student_id);

  SELECT l.price_daily, l.is_active, l.company_id, c.is_active AS company_active
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
    IF NEW.type = 'daily' THEN
      NEW.price := v_line.price_daily;
    END IF;
    NEW.created_at := now();
  END IF;

  IF NEW.type = 'daily' THEN
    NEW.period_code := NULL;
    NEW.academic_year := NULL;
    IF NOT v_privileged OR NEW.start_date IS NULL THEN
      -- Cash on the bus: active immediately, valid for the next votable ride.
      v_ride_date := public.next_votable_ride_date(v_line.company_id);
      NEW.status := 'active';
      NEW.start_date := v_ride_date;
      NEW.end_date := v_ride_date;
    END IF;
  ELSE
    -- Older clients say 'annual', or send a type with no period.
    v_code := CASE WHEN NEW.period_code = 'annual' OR (NEW.period_code IS NULL AND NEW.type = 'yearly')
                   THEN 'both' ELSE NEW.period_code END;

    -- The administration may register a student on a line that is switched off
    -- or has no price yet, and ahead of time; never for a period the company
    -- does not sell or that is out of season.
    SELECT * INTO v_opt FROM public.line_sale_options_for(NEW.line_id, NULL, NULL) o
    WHERE (CASE WHEN v_code IS NULL THEN o.subscription_type = 'termly' ELSE o.option = v_code END)
      AND (v_code IS NULL OR NEW.academic_year IS NULL OR o.academic_year = NEW.academic_year)
      AND (o.available OR (v_privileged AND o.reason IN
            ('company_inactive', 'line_inactive', 'line_not_offering', 'no_price', 'advance_off')))
    ORDER BY o.available DESC, o.start_date LIMIT 1;

    IF NOT FOUND THEN
      SELECT o.reason INTO v_reason FROM public.line_sale_options_for(NEW.line_id, NULL, NULL) o
      WHERE o.option = v_code ORDER BY o.start_date LIMIT 1;
      RAISE EXCEPTION '%', CASE
        WHEN v_code = 'both' AND v_reason = 'company_not_selling' THEN 'الاشتراك في الفصلين معاً غير متاح حالياً.'
        WHEN v_reason IN ('company_not_selling', 'line_not_offering', 'no_price') THEN 'هذه الفترة غير متاحة للاشتراك على هذا الخط.'
        WHEN v_reason = 'advance_off' THEN 'الاشتراك المسبق في الفترة القادمة غير متاح حالياً.'
        ELSE 'فترة الاشتراك المختارة غير متاحة للدفع الآن.' END USING ERRCODE = '23514';
    END IF;

    NEW.type := v_opt.subscription_type;
    NEW.period_code := v_opt.option;
    NEW.academic_year := v_opt.academic_year;
    NEW.start_date := v_opt.start_date;
    NEW.end_date := v_opt.end_date;
    IF NOT v_privileged THEN
      -- What was shown is what is charged.
      NEW.price := v_opt.price;
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

-- ---------------------------------------------------------------------------
-- 6. Company sale settings
-- ---------------------------------------------------------------------------
-- p_on_sale: {"first": true, "second": true, "summer": false}; missing keys are left as they are.
CREATE OR REPLACE FUNCTION public.set_company_sale_settings(p_company_id uuid, p_advance boolean DEFAULT NULL,
                                                           p_on_sale jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_company_id IS NULL OR NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  IF p_on_sale IS NOT NULL AND jsonb_typeof(p_on_sale) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'بيانات غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  PERFORM public.copy_default_terms(p_company_id);
  IF p_advance IS NOT NULL THEN
    UPDATE public.companies SET advance_subscription_enabled = p_advance WHERE id = p_company_id;
  END IF;
  IF p_on_sale IS NOT NULL THEN
    UPDATE public.company_terms t
    SET is_on_sale = (p_on_sale->>t.code)::boolean, updated_at = now(), updated_by = auth.uid()
    WHERE t.company_id = p_company_id AND p_on_sale ? t.code
      AND jsonb_typeof(p_on_sale->t.code) = 'boolean';
  END IF;
  RETURN jsonb_build_object(
    'advance_enabled', (SELECT c.advance_subscription_enabled FROM public.companies c WHERE c.id = p_company_id),
    'on_sale', (SELECT jsonb_object_agg(t.code, t.is_on_sale) FROM public.company_terms t WHERE t.company_id = p_company_id));
END;
$$;
REVOKE ALL ON FUNCTION public.set_company_sale_settings(uuid, boolean, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_company_sale_settings(uuid, boolean, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_subscription_settings(p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  y int := extract(year FROM public.cairo_today())::int;
  v_company uuid := CASE WHEN public.is_company_admin() THEN public.current_admin_company_id() ELSE p_company_id END;
BEGIN
  IF NOT public.is_admin() OR (v_company IS NOT NULL AND NOT public.can_manage_company(v_company)) THEN
    RAISE EXCEPTION 'متاح للمسؤولين فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'company_id', v_company,
    'annual_global', public.annual_subscription_enabled(NULL),
    'annual_company', (SELECT c.annual_subscription_enabled FROM public.companies c WHERE c.id = v_company),
    'annual_effective', public.annual_subscription_enabled(v_company),
    'advance_enabled', (SELECT c.advance_subscription_enabled FROM public.companies c WHERE c.id = v_company),
    'can_edit_global', public.is_super_admin(),
    'terms', CASE WHEN v_company IS NULL
      THEN (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.sort_order) FROM public.academic_terms t)
      ELSE (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.sort_order) FROM public.company_terms t WHERE t.company_id = v_company) END,
    'periods', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.start_date)
                FROM (SELECT * FROM public.company_periods(v_company, y - 1)
                      UNION ALL SELECT * FROM public.company_periods(v_company, y)) p
                WHERE p.end_date >= public.cairo_today()),
    'purchasable', (SELECT jsonb_agg(to_jsonb(p)) FROM public.company_purchasable_periods(v_company) p),
    -- Every option with the reason it is hidden, company-wide and per line.
    'sale_periods', (SELECT jsonb_agg(to_jsonb(p)) FROM public.company_sale_periods(v_company) p),
    'sale_preview', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('line_id', l.id, 'line', l.name, 'is_active', l.is_active,
               'options', (SELECT jsonb_agg(to_jsonb(o)) FROM public.line_sale_options_for(l.id, NULL, NULL) o))
             ORDER BY l.name)
      FROM public.lines l WHERE l.company_id = v_company), '[]'::jsonb),
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name,
               'annual_enabled', c.annual_subscription_enabled,
               'effective', public.annual_subscription_enabled(c.id)) ORDER BY c.name)
      FROM public.companies c
      WHERE public.is_super_admin() OR c.id = public.current_admin_company_id()), '[]'::jsonb)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. What a student can subscribe to
-- ---------------------------------------------------------------------------
-- Lines are described by structure: the line's name, the student's own
-- university and the stations. A station has no time of its own: each trip that
-- stops there has its time, and return trips are listed apart from departures.
CREATE OR REPLACE FUNCTION public.get_subscription_catalog() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH me AS (
    SELECT s.id, s.university_id, COALESCE(u.name, s.university) AS university
    FROM public.students s LEFT JOIN public.universities u ON u.id = s.university_id
    WHERE s.id = auth.uid()
  ),
  trips AS (
    SELECT t.* FROM public.line_trips t, me WHERE public.trip_serves_student(t, me.id)
  ),
  my_lines AS (
    SELECT l.* FROM public.lines l
    JOIN public.companies c ON c.id = l.company_id AND c.is_active AND c.status = 'active'
    WHERE l.is_active AND EXISTS (SELECT 1 FROM trips t WHERE t.line_id = l.id AND t.direction = 'departure')
  ),
  line_json AS (
    SELECT l.company_id, l.name, jsonb_build_object(
      'id', l.id, 'name', l.name, 'origin_name', COALESCE(l.origin_name, l.name),
      'university', (SELECT university FROM me),
      'first_departure', (SELECT min(t.start_time) FROM trips t WHERE t.line_id = l.id AND t.direction = 'departure'),
      'last_return', (SELECT max(t.start_time) FROM trips t WHERE t.line_id = l.id AND t.direction = 'return'),
      'stations', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name, 'order_index', st.order_index,
                 'departures', d.list, 'returns', COALESCE(r.list, '[]'::jsonb)) ORDER BY st.order_index, st.name)
        FROM public.stations st
        CROSS JOIN LATERAL (
          SELECT jsonb_agg(jsonb_build_object('trip_id', t.id, 'time', x.stop_time, 'start', t.start_time, 'label', t.label)
                           ORDER BY x.stop_time) AS list
          FROM trips t JOIN public.line_trip_stops x ON x.trip_id = t.id AND x.station_id = st.id
          WHERE t.line_id = l.id AND t.direction = 'departure') d
        CROSS JOIN LATERAL (
          SELECT jsonb_agg(jsonb_build_object('trip_id', t.id, 'time', x.stop_time, 'start', t.start_time, 'label', t.label)
                           ORDER BY x.stop_time) AS list
          FROM trips t JOIN public.line_trip_stops x ON x.trip_id = t.id AND x.station_id = st.id
          WHERE t.line_id = l.id AND t.direction = 'return') r
        -- A station no departure trip stops at cannot be boarded from.
        WHERE st.line_id = l.id AND st.is_active AND d.list IS NOT NULL), '[]'::jsonb),
      'options', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('option', o.option, 'academic_year', o.academic_year, 'name', o.name,
                 'label', o.label, 'type', o.subscription_type, 'start_date', o.start_date, 'end_date', o.end_date,
                 'phase', o.phase, 'price', o.price) ORDER BY o.start_date, o.subscription_type)
        FROM public.line_sale_options_for(l.id, NULL, auth.uid()) o WHERE o.available), '[]'::jsonb),
      'from_price', (SELECT min(o.price) FROM public.line_sale_options_for(l.id, NULL, auth.uid()) o WHERE o.available),
      'daily', jsonb_build_object('enabled', public.daily_subscription_enabled(l.company_id), 'price', l.price_daily)
    ) AS j
    FROM my_lines l
  )
  SELECT jsonb_build_object(
    'university', (SELECT jsonb_build_object('id', university_id, 'name', university) FROM me),
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path,
               'lines', (SELECT jsonb_agg(lj.j ORDER BY lj.name) FROM line_json lj WHERE lj.company_id = c.id))
             ORDER BY c.name)
      FROM public.companies c WHERE EXISTS (SELECT 1 FROM line_json lj WHERE lj.company_id = c.id)), '[]'::jsonb))
$$;
REVOKE ALL ON FUNCTION public.get_subscription_catalog() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_catalog() TO authenticated, service_role;

-- Older app: same shape, with the prices taken from the options on sale.
CREATE OR REPLACE FUNCTION public.get_student_catalog()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH my_lines AS (
    SELECT l.* FROM public.lines l
    JOIN public.companies c ON c.id = l.company_id AND c.is_active
    WHERE l.is_active AND auth.uid() IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.line_trips t
                  WHERE t.line_id = l.id AND t.direction = 'departure' AND public.trip_serves_student(t, auth.uid()))
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name,
      'lines', (SELECT jsonb_agg(jsonb_build_object(
          'id', l.id, 'name', l.name, 'origin_name', COALESCE(l.origin_name, l.name),
          'destination', (SELECT name FROM public.universities WHERE id = l.destination_university_id),
          'universities', public.line_university_names(l.id),
          'price_termly', COALESCE((SELECT o.price FROM public.line_sale_options_for(l.id, NULL, NULL) o
                                    WHERE o.available AND o.subscription_type = 'termly'
                                    ORDER BY o.start_date LIMIT 1), l.price_termly),
          'price_yearly', COALESCE((SELECT p.price FROM public.line_period_prices p
                                    WHERE p.line_id = l.id AND p.option = 'both'), l.price_yearly),
          'price_daily', l.price_daily,
          'stations', (SELECT COALESCE(jsonb_agg(st.name ORDER BY st.order_index), '[]'::jsonb)
                       FROM public.stations st WHERE st.line_id = l.id AND st.is_active),
          'departure_times', (SELECT COALESCE(jsonb_agg(t.start_time ORDER BY t.start_time), '[]'::jsonb)
                              FROM public.line_trips t WHERE t.line_id = l.id AND t.direction = 'departure'
                                AND public.trip_serves_student(t, auth.uid())),
          'return_times', (SELECT COALESCE(jsonb_agg(t.start_time ORDER BY t.start_time), '[]'::jsonb)
                           FROM public.line_trips t WHERE t.line_id = l.id AND t.direction = 'return'
                             AND public.trip_serves_student(t, auth.uid())))
        ORDER BY l.name)
        FROM my_lines l WHERE l.company_id = c.id))
    ORDER BY c.name), '[]'::jsonb)
  FROM public.companies c
  WHERE EXISTS (SELECT 1 FROM my_lines l WHERE l.company_id = c.id)
$$;

-- Sign-up screen, before an account exists: company names only.
CREATE OR REPLACE FUNCTION public.companies_for_university(p_university_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', x.name, 'lines', x.n) ORDER BY x.name), '[]'::jsonb)
  FROM (
    SELECT c.name, count(*) AS n
    FROM public.companies c JOIN public.lines l ON l.company_id = c.id AND l.is_active
    WHERE c.is_active AND c.status = 'active' AND p_university_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.line_trips t
                  WHERE t.line_id = l.id AND t.direction = 'departure' AND t.is_active
                    AND (t.university_id IS NULL OR t.university_id = p_university_id))
      AND (NOT EXISTS (SELECT 1 FROM public.line_universities lu WHERE lu.line_id = l.id)
           OR EXISTS (SELECT 1 FROM public.line_universities lu
                      WHERE lu.line_id = l.id AND lu.university_id = p_university_id))
    GROUP BY c.id, c.name) x
$$;
REVOKE ALL ON FUNCTION public.companies_for_university(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.companies_for_university(uuid) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. Proof of payment that never changes
-- ---------------------------------------------------------------------------
-- A copy of the facts at the moment the subscription was approved. It holds no
-- foreign keys on purpose: renaming or removing a line, station, university,
-- company or student afterwards leaves the receipt exactly as it was issued.
CREATE TABLE IF NOT EXISTS public.subscription_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL UNIQUE,
  company_id uuid NOT NULL,
  student_id uuid NOT NULL,
  receipt_no integer NOT NULL,
  company_name text NOT NULL,
  student_name text NOT NULL,
  student_phone text,
  university_name text,
  line_name text NOT NULL,
  station_name text,
  option text,
  period_label text NOT NULL,
  start_date date,
  end_date date,
  amount numeric(10, 2) NOT NULL,
  payment_method text,
  approved_at timestamptz NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, receipt_no)
);
CREATE INDEX IF NOT EXISTS idx_subscription_receipts_student ON public.subscription_receipts(student_id);

ALTER TABLE public.subscription_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.subscription_receipts FROM anon, authenticated;
GRANT SELECT ON public.subscription_receipts TO authenticated;
DROP POLICY IF EXISTS subscription_receipts_read ON public.subscription_receipts;
CREATE POLICY subscription_receipts_read ON public.subscription_receipts FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid()) OR (SELECT public.is_super_admin())
         OR company_id = (SELECT public.managed_company_id()));

CREATE OR REPLACE FUNCTION public.forbid_receipt_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'إيصال الاشتراك لا يمكن تعديله أو حذفه بعد إصداره.' USING ERRCODE = '42501';
END;
$$;
REVOKE ALL ON FUNCTION public.forbid_receipt_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_forbid_receipt_change ON public.subscription_receipts;
CREATE TRIGGER trg_forbid_receipt_change BEFORE UPDATE OR DELETE ON public.subscription_receipts
  FOR EACH ROW EXECUTE FUNCTION public.forbid_receipt_change();
DROP TRIGGER IF EXISTS trg_forbid_receipt_truncate ON public.subscription_receipts;
CREATE TRIGGER trg_forbid_receipt_truncate BEFORE TRUNCATE ON public.subscription_receipts
  FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_receipt_change();

-- Receipt numbers run per company: 1, 2, 3 ...
CREATE TABLE IF NOT EXISTS public.company_receipt_counters (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  last_no integer NOT NULL DEFAULT 0
);
ALTER TABLE public.company_receipt_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.company_receipt_counters FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.issue_subscription_receipt(p_subscription_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s record;
  r record;
  v_no integer;
BEGIN
  SELECT sub.id, sub.company_id, sub.student_id, sub.period_code, sub.start_date, sub.end_date, sub.price, sub.paid_at,
         public.period_label(sub) AS period_label, c.name AS company_name, st.full_name, st.phone,
         COALESCE(u.name, st.university) AS university_name, l.name AS line_name, sn.name AS station_name
  INTO s
  FROM public.subscriptions sub
  JOIN public.companies c ON c.id = sub.company_id
  JOIN public.students st ON st.id = sub.student_id
  JOIN public.lines l ON l.id = sub.line_id
  LEFT JOIN public.stations sn ON sn.id = sub.station_id
  LEFT JOIN public.universities u ON u.id = st.university_id
  WHERE sub.id = p_subscription_id AND sub.type <> 'daily' AND sub.paid_at IS NOT NULL
    AND sub.status IN ('active', 'expired');
  IF NOT FOUND OR EXISTS (SELECT 1 FROM public.subscription_receipts x WHERE x.subscription_id = p_subscription_id) THEN
    RETURN;
  END IF;

  SELECT rc.amount, pm.display_name, rc.reviewed_at INTO r
  FROM public.receipts rc LEFT JOIN public.company_payment_methods pm ON pm.id = rc.payment_method_id
  WHERE rc.subscription_id = p_subscription_id AND rc.status = 'approved'
  ORDER BY rc.reviewed_at DESC NULLS LAST LIMIT 1;

  INSERT INTO public.company_receipt_counters AS k (company_id, last_no) VALUES (s.company_id, 1)
  ON CONFLICT (company_id) DO UPDATE SET last_no = k.last_no + 1
  RETURNING k.last_no INTO v_no;

  INSERT INTO public.subscription_receipts (subscription_id, company_id, student_id, receipt_no, company_name,
    student_name, student_phone, university_name, line_name, station_name, option, period_label, start_date, end_date,
    amount, payment_method, approved_at)
  VALUES (s.id, s.company_id, s.student_id, v_no, s.company_name, s.full_name, s.phone, s.university_name, s.line_name,
    s.station_name, s.period_code, COALESCE(s.period_label, ''), s.start_date, s.end_date,
    COALESCE(r.amount, s.price), r.display_name, COALESCE(r.reviewed_at, s.paid_at));
END;
$$;
REVOKE ALL ON FUNCTION public.issue_subscription_receipt(uuid) FROM PUBLIC, anon, authenticated;

-- Runs at the end of the transaction, when the approved payment receipt (amount
-- and method) is already saved.
CREATE OR REPLACE FUNCTION public.issue_receipt_on_activation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.issue_subscription_receipt(NEW.id);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.issue_receipt_on_activation() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_issue_subscription_receipt ON public.subscriptions;
CREATE CONSTRAINT TRIGGER trg_issue_subscription_receipt AFTER INSERT OR UPDATE OF status ON public.subscriptions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW WHEN (NEW.status = 'active' AND NEW.type <> 'daily')
  EXECUTE FUNCTION public.issue_receipt_on_activation();

-- Subscriptions paid before receipts existed get one, in the order they were
-- paid. Not run here on purpose: a receipt keeps the line and station names of
-- the moment it is issued, so names are put right first and this is run once after.
CREATE OR REPLACE FUNCTION public.issue_missing_subscription_receipts() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_before bigint;
BEGIN
  SELECT count(*) INTO v_before FROM public.subscription_receipts;
  FOR v_id IN SELECT id FROM public.subscriptions
              WHERE type <> 'daily' AND paid_at IS NOT NULL AND status IN ('active', 'expired')
              ORDER BY paid_at, created_at LOOP
    PERFORM public.issue_subscription_receipt(v_id);
  END LOOP;
  RETURN (SELECT count(*) FROM public.subscription_receipts) - v_before;
END;
$$;
REVOKE ALL ON FUNCTION public.issue_missing_subscription_receipts() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Reports count "both" (older dashboards still ask for and read "annual")
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_subscription_report(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company uuid := NULLIF(p_filters->>'company_id', '')::uuid;
  v_university uuid := NULLIF(p_filters->>'university_id', '')::uuid;
  v_line uuid := NULLIF(p_filters->>'line_id', '')::uuid;
  v_year int := NULLIF(p_filters->>'academic_year', '')::int;
  -- first|second|both|summer|daily ('annual' is the older name of both)
  v_period text := NULLIF(replace(p_filters->>'period', 'annual', 'both'), '');
  v_payment text := NULLIF(p_filters->>'payment', '');      -- paid|unpaid
  v_phase text := NULLIF(p_filters->>'phase', '');          -- current|upcoming|expired
  v_search text := NULLIF(btrim(p_filters->>'search'), '');
  v_history boolean := COALESCE((p_filters->>'include_before_reset')::boolean, false);
  v_data jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;
  IF public.is_company_admin() THEN v_company := public.current_admin_company_id(); END IF;
  IF v_company IS NOT NULL AND NOT public.can_manage_company(v_company) THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;

  WITH baselines AS (
    -- Each company counts from its own last reset.
    SELECT c.id, public.report_baseline('financial', c.id) AS since FROM public.companies c
    WHERE v_company IS NULL OR c.id = v_company
  ),
  base AS (
    SELECT s.*, st.full_name, st.phone, st.university AS university_name, st.university_id,
      l.name AS line_name, c.name AS company_name, c.id AS company_ref, public.period_label(s) AS period_label_text,
      COALESCE(s.period_code, CASE s.type WHEN 'daily' THEN 'daily' WHEN 'yearly' THEN 'both' END) AS period_key,
      CASE WHEN s.status = 'expired' OR s.end_date < public.cairo_today() THEN 'expired'
           WHEN s.start_date > public.cairo_today() THEN 'upcoming' ELSE 'current' END AS phase,
      (s.paid_at IS NOT NULL) AS is_paid,
      -- One payment per subscription: the approved receipt amount, else the price.
      CASE WHEN s.paid_at IS NOT NULL THEN COALESCE((
        SELECT r.amount FROM public.receipts r WHERE r.subscription_id = s.id AND r.status = 'approved'
        ORDER BY r.reviewed_at DESC NULLS LAST LIMIT 1), s.price) END AS paid_amount,
      (SELECT pm.display_name FROM public.receipts r JOIN public.company_payment_methods pm ON pm.id = r.payment_method_id
       WHERE r.subscription_id = s.id ORDER BY r.created_at DESC LIMIT 1) AS payment_method
    FROM public.subscriptions s
    JOIN public.students st ON st.id = s.student_id
    JOIN public.lines l ON l.id = s.line_id
    JOIN public.companies c ON c.id = l.company_id
    JOIN baselines b ON b.id = l.company_id
    WHERE (v_university IS NULL OR st.university_id = v_university)
      AND (v_line IS NULL OR s.line_id = v_line)
      AND (v_year IS NULL OR s.academic_year = v_year)
      AND (v_search IS NULL OR st.full_name ILIKE '%' || v_search || '%' OR st.phone LIKE '%' || regexp_replace(v_search, '\D', '', 'g') || '%')
      AND (v_history OR b.since IS NULL OR COALESCE(s.paid_at, s.created_at) > b.since)
  ),
  filtered AS (
    SELECT * FROM base
    WHERE (v_period IS NULL OR period_key = v_period)
      AND (v_payment IS NULL OR (v_payment = 'paid') = is_paid)
      AND (v_phase IS NULL OR phase = v_phase)
  )
  SELECT jsonb_build_object(
    'baseline', (SELECT max(since) FROM baselines),
    'totals', jsonb_build_object(
      'count', (SELECT count(*) FROM filtered),
      'paid', (SELECT count(*) FROM filtered WHERE is_paid),
      'unpaid', (SELECT count(*) FROM filtered WHERE NOT is_paid AND status IN ('pending_payment', 'pending_review', 'rejected')),
      'upcoming', (SELECT count(*) FROM filtered WHERE phase = 'upcoming'),
      'upcoming_paid', (SELECT count(*) FROM filtered WHERE phase = 'upcoming' AND is_paid),
      'expired', (SELECT count(*) FROM filtered WHERE phase = 'expired'),
      'revenue', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid),
      'revenue_first', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'first'),
      'revenue_second', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'second'),
      'revenue_summer', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'summer'),
      'revenue_both', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'both'),
      'revenue_annual', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'both'),
      'revenue_daily', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'daily')),
    'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', f.id, 'student_name', f.full_name, 'phone', f.phone, 'university', f.university_name,
        'company', f.company_name, 'line', f.line_name, 'type', f.type, 'period', f.period_key,
        'academic_year', f.academic_year, 'label', f.period_label_text,
        'status', f.status, 'phase', f.phase, 'paid', f.is_paid, 'amount', f.paid_amount, 'price', f.price,
        'paid_at', f.paid_at, 'start_date', f.start_date, 'end_date', f.end_date, 'payment_method', f.payment_method,
        'receipt_no', (SELECT x.receipt_no FROM public.subscription_receipts x WHERE x.subscription_id = f.id))
        ORDER BY f.paid_at DESC NULLS LAST, f.created_at DESC)
      FROM (SELECT * FROM filtered LIMIT 2000) f), '[]'::jsonb)
  ) INTO v_data;
  RETURN v_data;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. An invitation shows the price that will be charged
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_invites() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', i.id, 'company_id', i.company_id, 'company_name', c.name,
      'line_name', l.name, 'station_name', st.name, 'subscription_type', i.subscription_type,
      'price', CASE WHEN i.subscription_type = 'daily' THEN l.price_daily ELSE COALESCE(
        (SELECT o.price FROM public.line_sale_options_for(l.id, NULL, NULL) o
         WHERE o.price > 0 AND (CASE WHEN i.period_code IS NULL THEN o.available AND o.subscription_type = i.subscription_type
                                     ELSE o.option = replace(i.period_code, 'annual', 'both') END)
         ORDER BY o.start_date LIMIT 1),
        CASE i.subscription_type WHEN 'yearly' THEN l.price_yearly ELSE l.price_termly END) END,
      'created_at', i.created_at, 'expires_at', i.expires_at) ORDER BY i.created_at DESC), '[]'::jsonb)
  FROM public.company_invites i
  JOIN public.companies c ON c.id = i.company_id AND c.status = 'active'
  JOIN public.lines l ON l.id = i.line_id
  JOIN public.stations st ON st.id = i.station_id
  WHERE i.student_id = auth.uid() AND i.status = 'pending' AND i.expires_at > now()
$$;
