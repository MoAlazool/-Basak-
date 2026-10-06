-- Terms and report resets become each company's own.
--   * company_terms: a company's semester dates, copied from the platform
--     defaults (academic_terms) when the company is created
--   * report_resets.company_id: a reset clears one company's reports
-- Editing one company no longer moves another company's subscriptions or numbers.
-- The functions the mobile app calls keep their names and arguments.

-- ---------------------------------------------------------------------------
-- 1. Per-company terms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_terms (
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  code text NOT NULL CHECK (code IN ('first', 'second', 'summer')),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  sort_order integer NOT NULL,
  start_month integer NOT NULL CHECK (start_month BETWEEN 1 AND 12),
  start_day integer NOT NULL CHECK (start_day BETWEEN 1 AND 31),
  start_year_offset integer NOT NULL CHECK (start_year_offset IN (0, 1)),
  end_month integer NOT NULL CHECK (end_month BETWEEN 1 AND 12),
  end_day integer NOT NULL CHECK (end_day BETWEEN 1 AND 31),
  end_year_offset integer NOT NULL CHECK (end_year_offset IN (0, 1)),
  included_in_annual boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  PRIMARY KEY (company_id, code)
);

ALTER TABLE public.company_terms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_terms_read ON public.company_terms;
CREATE POLICY company_terms_read ON public.company_terms FOR SELECT TO authenticated
  USING (public.has_company_access(company_id));
-- Saved through save_company_terms() so the three terms are checked together.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.company_terms FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.copy_default_terms(p_company_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.company_terms (company_id, code, name, sort_order, start_month, start_day, start_year_offset,
                                    end_month, end_day, end_year_offset, included_in_annual, is_active)
  SELECT p_company_id, code, name, sort_order, start_month, start_day, start_year_offset,
         end_month, end_day, end_year_offset, included_in_annual, is_active
  FROM public.academic_terms
  ON CONFLICT (company_id, code) DO NOTHING
$$;
REVOKE ALL ON FUNCTION public.copy_default_terms(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.init_company_terms() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.copy_default_terms(NEW.id);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.init_company_terms() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_init_company_terms ON public.companies;
CREATE TRIGGER trg_init_company_terms AFTER INSERT ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.init_company_terms();

SELECT public.copy_default_terms(c.id) FROM public.companies c;

-- The periods of one company for an academic year. NULL = the platform defaults.
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
  SELECT 'annual', p_academic_year, 'اشتراك سنوي',
         'اشتراك سنوي ' || p_academic_year || '/' || (p_academic_year + 1),
         'yearly', min(s), max(e), false, 100
  FROM t WHERE included_in_annual HAVING count(*) > 0
$$;

CREATE OR REPLACE FUNCTION public.company_period_for_date(p_company_id uuid, p_type text, p_date date)
RETURNS TABLE(period_code text, academic_year integer, start_date date, end_date date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.period_code, a.academic_year, a.start_date, a.end_date
  FROM (
    SELECT * FROM public.company_periods(p_company_id, extract(year FROM p_date)::int - 1)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, extract(year FROM p_date)::int)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, extract(year FROM p_date)::int + 1)
  ) a
  WHERE a.subscription_type = CASE WHEN p_type = 'yearly' THEN 'yearly' ELSE 'termly' END
    AND a.end_date >= p_date
  ORDER BY (a.start_date <= p_date) DESC, a.start_date
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.period_label(s public.subscriptions) RETURNS text
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN s.type = 'daily' THEN 'اشتراك يومي'
    ELSE (SELECT p.label FROM public.company_periods(s.company_id, s.academic_year) p WHERE p.period_code = s.period_code)
  END
$$;

-- What can be paid for now with one company: the running term, the next one, and
-- the annual plan while its first term runs or when it is next to start.
CREATE OR REPLACE FUNCTION public.company_purchasable_periods(p_company_id uuid, p_on date DEFAULT NULL)
RETURNS TABLE(period_code text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  d date := COALESCE(p_on, public.cairo_today());
  y int := extract(year FROM COALESCE(p_on, public.cairo_today()))::int;
  v_annual boolean := public.annual_subscription_enabled(p_company_id);
BEGIN
  RETURN QUERY
  WITH all_p AS (
    SELECT * FROM public.company_periods(p_company_id, y - 1)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, y)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, y + 1)
  ),
  terms AS (SELECT * FROM all_p a WHERE a.subscription_type = 'termly' AND a.end_date >= d),
  cur AS (SELECT * FROM terms t WHERE t.start_date <= d ORDER BY t.start_date LIMIT 1),
  nxt AS (SELECT * FROM terms t WHERE t.start_date > d ORDER BY t.start_date LIMIT 1),
  annual AS (
    SELECT a.* FROM all_p a
    WHERE a.subscription_type = 'yearly' AND v_annual AND a.end_date >= d
      AND (
        (a.start_date <= d AND d <= (SELECT min(t.end_date) FROM all_p t
                                     WHERE t.academic_year = a.academic_year AND t.included_in_annual))
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

-- Same name and arguments as before; the line decides whose terms apply.
CREATE OR REPLACE FUNCTION public.get_purchasable_periods(p_line_id uuid DEFAULT NULL, p_on date DEFAULT NULL)
RETURNS TABLE(period_code text, academic_year integer, name text, label text, subscription_type text,
              start_date date, end_date date, phase text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.company_purchasable_periods(
    (SELECT l.company_id FROM public.lines l WHERE l.id = p_line_id), p_on)
  -- An unknown line sells nothing; no line at all previews the platform defaults.
  WHERE p_line_id IS NULL OR EXISTS (SELECT 1 FROM public.lines l WHERE l.id = p_line_id)
$$;

CREATE OR REPLACE FUNCTION public.guard_subscription_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
      SELECT * INTO v_period
      FROM public.company_period_for_date(NEW.company_id, NEW.type, COALESCE(NEW.start_date, public.cairo_today()));
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
    FOR r IN SELECT * FROM public.company_periods(p_company_id, y) WHERE period_code <> 'annual' ORDER BY start_date LOOP
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

-- The defaults are a template now: editing them no longer moves anyone's subscription.
DROP TRIGGER IF EXISTS trg_refresh_subscription_period_dates ON public.academic_terms;
DROP FUNCTION IF EXISTS public.refresh_subscription_period_dates();

-- Saves a company's terms together, then moves that company's open subscriptions
-- to the new dates. p_terms: [{code, name?, start_month, start_day, start_year_offset,
-- end_month, end_day, end_year_offset, included_in_annual?, is_active?}]
CREATE OR REPLACE FUNCTION public.save_company_terms(p_company_id uuid, p_terms jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_moved int;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_terms) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'بيانات الفصول غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  PERFORM public.copy_default_terms(p_company_id);

  UPDATE public.company_terms t
  SET name = COALESCE(NULLIF(btrim(x.name), ''), t.name),
      start_month = COALESCE(x.start_month, t.start_month), start_day = COALESCE(x.start_day, t.start_day),
      start_year_offset = COALESCE(x.start_year_offset, t.start_year_offset),
      end_month = COALESCE(x.end_month, t.end_month), end_day = COALESCE(x.end_day, t.end_day),
      end_year_offset = COALESCE(x.end_year_offset, t.end_year_offset),
      included_in_annual = COALESCE(x.included_in_annual, t.included_in_annual),
      is_active = COALESCE(x.is_active, t.is_active),
      updated_at = now(), updated_by = auth.uid()
  FROM jsonb_to_recordset(p_terms) AS x(code text, name text, start_month int, start_day int, start_year_offset int,
                                        end_month int, end_day int, end_year_offset int,
                                        included_in_annual boolean, is_active boolean)
  WHERE t.company_id = p_company_id AND t.code = x.code;

  PERFORM public.assert_terms_valid(p_company_id);

  UPDATE public.subscriptions s
  SET start_date = p.start_date, end_date = p.end_date
  FROM public.subscriptions x
  CROSS JOIN LATERAL public.company_periods(p_company_id, x.academic_year) p
  WHERE x.id = s.id AND x.company_id = p_company_id AND p.period_code = x.period_code
    AND x.status IN ('pending_payment', 'pending_review', 'active')
    AND (x.start_date IS DISTINCT FROM p.start_date OR x.end_date IS DISTINCT FROM p.end_date);
  GET DIAGNOSTICS v_moved = ROW_COUNT;
  RETURN jsonb_build_object('moved_subscriptions', v_moved);
END;
$$;

-- Settings of one company. A company admin always gets their own; the platform
-- admin names the company, or passes nothing to see the platform defaults.
DROP FUNCTION IF EXISTS public.get_subscription_settings();
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
    'can_edit_global', public.is_super_admin(),
    'terms', CASE WHEN v_company IS NULL
      THEN (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.sort_order) FROM public.academic_terms t)
      ELSE (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.sort_order) FROM public.company_terms t WHERE t.company_id = v_company) END,
    'periods', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.start_date)
                FROM (SELECT * FROM public.company_periods(v_company, y - 1)
                      UNION ALL SELECT * FROM public.company_periods(v_company, y)) p
                WHERE p.end_date >= public.cairo_today()),
    'purchasable', (SELECT jsonb_agg(to_jsonb(p)) FROM public.company_purchasable_periods(v_company) p),
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name,
               'annual_enabled', c.annual_subscription_enabled,
               'effective', public.annual_subscription_enabled(c.id)) ORDER BY c.name)
      FROM public.companies c
      WHERE public.is_super_admin() OR c.id = public.current_admin_company_id()), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.company_periods(uuid, integer), public.company_period_for_date(uuid, text, date),
  public.company_purchasable_periods(uuid, date), public.assert_terms_valid(uuid),
  public.save_company_terms(uuid, jsonb), public.get_subscription_settings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_periods(uuid, integer), public.company_period_for_date(uuid, text, date),
  public.company_purchasable_periods(uuid, date), public.assert_terms_valid(uuid),
  public.save_company_terms(uuid, jsonb), public.get_subscription_settings(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Per-company report resets
-- ---------------------------------------------------------------------------
-- NULL = a reset made before companies had their own; it stays a floor for all.
ALTER TABLE public.report_resets
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_report_resets_company ON public.report_resets (company_id, reset_at DESC);

DROP POLICY IF EXISTS report_resets_read ON public.report_resets;
CREATE POLICY report_resets_read ON public.report_resets FOR SELECT TO authenticated
  USING (public.is_super_admin() OR (company_id IS NOT NULL AND public.can_manage_company(company_id)));

DROP FUNCTION IF EXISTS public.report_baseline(text);
CREATE OR REPLACE FUNCTION public.report_baseline(p_scope text DEFAULT 'financial', p_company_id uuid DEFAULT NULL)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT max(reset_at) FROM public.report_resets
  WHERE undone_at IS NULL AND (scope = 'all' OR scope = p_scope)
    AND (company_id IS NULL OR company_id = COALESCE(p_company_id, public.current_admin_company_id()))
$$;

DROP FUNCTION IF EXISTS public.admin_reset_reports(text, text, text);
CREATE OR REPLACE FUNCTION public.admin_reset_reports(p_scope text, p_confirm text, p_note text DEFAULT NULL,
                                                      p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid;
  v_company uuid := CASE WHEN public.is_company_admin() THEN public.current_admin_company_id() ELSE p_company_id END;
BEGIN
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'اختر الشركة التي تريد تصفير تقاريرها.' USING ERRCODE = '22023';
  END IF;
  IF NOT public.can_manage_company(v_company) THEN
    RAISE EXCEPTION 'تصفير التقارير متاح لإدارة الشركة فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_scope NOT IN ('financial', 'all') THEN
    RAISE EXCEPTION 'نوع التصفير غير صحيح.' USING ERRCODE = '23514';
  END IF;
  IF p_confirm IS DISTINCT FROM (CASE p_scope WHEN 'all' THEN 'RESET ALL DATA' ELSE 'RESET FINANCIAL DATA' END) THEN
    RAISE EXCEPTION 'عبارة التأكيد غير صحيحة.' USING ERRCODE = '23514';
  END IF;
  -- Guard against double clicks / repeated execution.
  PERFORM pg_advisory_xact_lock(hashtext('basak.report_reset.' || v_company));
  IF EXISTS (SELECT 1 FROM public.report_resets
             WHERE company_id = v_company AND undone_at IS NULL AND reset_at > now() - INTERVAL '1 minute') THEN
    RAISE EXCEPTION 'تم التصفير منذ أقل من دقيقة. انتظر قبل تكراره.' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.report_resets (company_id, scope, reset_by, note)
  VALUES (v_company, p_scope, auth.uid(), NULLIF(btrim(p_note), ''))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'company_id', v_company, 'scope', p_scope, 'reset_at', now());
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_undo_report_reset(p_reset_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid; v_found boolean;
BEGIN
  SELECT company_id, true INTO v_company, v_found FROM public.report_resets WHERE id = p_reset_id AND undone_at IS NULL;
  IF v_found IS NULL THEN
    RAISE EXCEPTION 'عملية التصفير غير موجودة أو أُلغيت بالفعل.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT (public.is_super_admin() OR (v_company IS NOT NULL AND public.can_manage_company(v_company))) THEN
    RAISE EXCEPTION 'غير مسموح بإلغاء هذا التصفير.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.report_resets SET undone_at = now(), undone_by = auth.uid() WHERE id = p_reset_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_subscription_report(p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid := NULLIF(p_filters->>'company_id', '')::uuid;
  v_university uuid := NULLIF(p_filters->>'university_id', '')::uuid;
  v_line uuid := NULLIF(p_filters->>'line_id', '')::uuid;
  v_year int := NULLIF(p_filters->>'academic_year', '')::int;
  v_period text := NULLIF(p_filters->>'period', '');        -- first|second|summer|annual|daily
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
      COALESCE(s.period_code, CASE s.type WHEN 'daily' THEN 'daily' WHEN 'yearly' THEN 'annual' END) AS period_key,
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
      'revenue_annual', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'annual'),
      'revenue_daily', (SELECT COALESCE(sum(paid_amount), 0) FROM filtered WHERE is_paid AND period_key = 'daily')),
    'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', f.id, 'student_name', f.full_name, 'phone', f.phone, 'university', f.university_name,
        'company', f.company_name, 'line', f.line_name, 'type', f.type, 'period', f.period_key,
        'academic_year', f.academic_year, 'label', f.period_label_text,
        'status', f.status, 'phase', f.phase, 'paid', f.is_paid, 'amount', f.paid_amount, 'price', f.price,
        'paid_at', f.paid_at, 'start_date', f.start_date, 'end_date', f.end_date, 'payment_method', f.payment_method)
        ORDER BY f.paid_at DESC NULLS LAST, f.created_at DESC)
      FROM (SELECT * FROM filtered LIMIT 2000) f), '[]'::jsonb)
  ) INTO v_data;
  RETURN v_data;
END;
$$;

REVOKE ALL ON FUNCTION public.report_baseline(text, uuid), public.admin_reset_reports(text, text, text, uuid),
  public.admin_undo_report_reset(uuid), public.admin_subscription_report(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_baseline(text, uuid), public.admin_reset_reports(text, text, text, uuid),
  public.admin_undo_report_reset(uuid), public.admin_subscription_report(jsonb) TO authenticated, service_role;
