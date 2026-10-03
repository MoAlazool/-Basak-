-- ==============================================================================
-- Migration: 20261007000001_finance_payments_reset_universities.sql
-- Run AFTER 20261006000002_receipts_reviewer_fk.sql. Safe to re-run.
--
-- 1. Dashboard reset (NON-destructive): report_resets marks the point from
--    which the dashboard counts. No row is ever deleted; a reset can be undone.
-- 2. admin_subscription_report: every subscription classified by period
--    (first / second / summer / annual / daily), payment (paid / unpaid) and
--    phase (current / upcoming / expired), with revenue from actual payments
--    (one payment per subscription: paid_at + approved receipt amount).
-- 3. company_payment_methods (InstaPay / Vodafone Cash / bank) per company;
--    receipts.payment_method_id.
-- 4. students.must_change_password + password_admin_resets audit (no
--    passwords stored); the Auth password itself is changed by Edge Functions.
-- 5. line_universities: one line, several universities (stored once).
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Dashboard reset points
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.report_resets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope text NOT NULL CHECK (scope IN ('financial', 'all')),
  reset_at timestamptz NOT NULL DEFAULT now(),
  reset_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note text,
  undone_at timestamptz,
  undone_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.report_resets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.report_resets FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.report_resets FROM authenticated;
GRANT SELECT ON public.report_resets TO authenticated;
DROP POLICY IF EXISTS report_resets_read ON public.report_resets;
CREATE POLICY report_resets_read ON public.report_resets FOR SELECT TO authenticated USING (public.is_admin());

-- Effective start of the dashboard counting for a scope ('financial' also
-- honours 'all' resets). NULL = count everything.
CREATE OR REPLACE FUNCTION public.report_baseline(p_scope text DEFAULT 'financial')
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT max(reset_at) FROM public.report_resets
  WHERE undone_at IS NULL AND (scope = 'all' OR scope = p_scope)
$$;
GRANT EXECUTE ON FUNCTION public.report_baseline(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_reset_reports(p_scope text, p_confirm text, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تصفير البيانات متاح لمدير النظام فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_scope NOT IN ('financial', 'all') THEN
    RAISE EXCEPTION 'نوع التصفير غير صحيح.' USING ERRCODE = '23514';
  END IF;
  IF p_confirm IS DISTINCT FROM (CASE p_scope WHEN 'all' THEN 'RESET ALL DATA' ELSE 'RESET FINANCIAL DATA' END) THEN
    RAISE EXCEPTION 'عبارة التأكيد غير صحيحة.' USING ERRCODE = '23514';
  END IF;
  -- Guard against double clicks / repeated execution.
  PERFORM pg_advisory_xact_lock(hashtext('basak.report_reset'));
  IF EXISTS (SELECT 1 FROM public.report_resets WHERE undone_at IS NULL AND reset_at > now() - INTERVAL '1 minute') THEN
    RAISE EXCEPTION 'تم التصفير منذ أقل من دقيقة. انتظر قبل تكراره.' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.report_resets (scope, reset_by, note) VALUES (p_scope, auth.uid(), NULLIF(btrim(p_note), ''))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'scope', p_scope, 'reset_at', now());
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_undo_report_reset(p_reset_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'متاح لمدير النظام فقط.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.report_resets SET undone_at = now(), undone_by = auth.uid()
  WHERE id = p_reset_id AND undone_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'عملية التصفير غير موجودة أو أُلغيت بالفعل.' USING ERRCODE = 'P0002'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_reset_reports(text, text, text), public.admin_undo_report_reset(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reset_reports(text, text, text), public.admin_undo_report_reset(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 5 (needed by the report). Lines shared by several universities
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.line_universities (
  line_id uuid NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
  university_id uuid NOT NULL REFERENCES public.universities(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (line_id, university_id)
);
CREATE INDEX IF NOT EXISTS idx_line_universities_university ON public.line_universities(university_id);

-- Existing lines: destination, trip universities and subscribers' universities.
INSERT INTO public.line_universities (line_id, university_id)
SELECT id, destination_university_id FROM public.lines WHERE destination_university_id IS NOT NULL
UNION SELECT line_id, university_id FROM public.line_trips WHERE university_id IS NOT NULL
UNION SELECT s.line_id, st.university_id FROM public.subscriptions s JOIN public.students st ON st.id = s.student_id
      WHERE st.university_id IS NOT NULL
ON CONFLICT DO NOTHING;
UPDATE public.lines l SET destination_university_id = (
  SELECT lu.university_id FROM public.line_universities lu WHERE lu.line_id = l.id ORDER BY lu.created_at LIMIT 1)
WHERE l.destination_university_id IS NULL
  AND EXISTS (SELECT 1 FROM public.line_universities lu WHERE lu.line_id = l.id);

ALTER TABLE public.line_universities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.line_universities FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.line_universities FROM authenticated;  -- via save_line
GRANT SELECT ON public.line_universities TO authenticated;
GRANT ALL ON public.line_universities TO service_role;
DROP POLICY IF EXISTS line_universities_read ON public.line_universities;
CREATE POLICY line_universities_read ON public.line_universities FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.lines l WHERE l.id = line_universities.line_id));  -- follows lines RLS

-- A trip serves a student when the line serves the student's university
-- (lines without associations stay open) and the trip is open to it.
CREATE OR REPLACE FUNCTION public.trip_serves_student(p_trip public.line_trips, p_student_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH me AS (SELECT university_id FROM public.students WHERE id = p_student_id)
  SELECT p_trip.is_active
    AND (p_trip.university_id IS NULL OR p_trip.university_id = (SELECT university_id FROM me))
    AND (NOT EXISTS (SELECT 1 FROM public.line_universities lu WHERE lu.line_id = p_trip.line_id)
         OR EXISTS (SELECT 1 FROM public.line_universities lu
                    WHERE lu.line_id = p_trip.line_id AND lu.university_id = (SELECT university_id FROM me)))
$$;

-- Students read trips through RLS: apply the same line-university rule there.
DROP POLICY IF EXISTS line_trips_read_scope ON public.line_trips;
CREATE POLICY line_trips_read_scope ON public.line_trips FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_trips.line_id AND l.company_id = public.current_admin_company_id()))
  OR (public.is_supervisor() AND line_trips.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a))
  OR (NOT public.is_admin() AND public.trip_serves_student(line_trips, auth.uid())
      AND EXISTS (SELECT 1 FROM public.lines l WHERE l.id = line_trips.line_id AND l.is_active))
  OR EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.student_id = auth.uid()
             AND (s.departure_trip_id = line_trips.id OR s.return_trip_id = line_trips.id))
);

-- ------------------------------------------------------------------------------
-- 2. Subscription classification report
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_subscription_report(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
  v_baseline timestamptz := public.report_baseline('financial');
  v_data jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;
  IF public.is_company_admin() THEN v_company := public.current_admin_company_id(); END IF;

  WITH base AS (
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
    WHERE (v_company IS NULL OR l.company_id = v_company)
      AND (v_university IS NULL OR st.university_id = v_university)
      AND (v_line IS NULL OR s.line_id = v_line)
      AND (v_year IS NULL OR s.academic_year = v_year)
      AND (v_search IS NULL OR st.full_name ILIKE '%' || v_search || '%' OR st.phone LIKE '%' || regexp_replace(v_search, '\D', '', 'g') || '%')
      AND (v_history OR v_baseline IS NULL OR COALESCE(s.paid_at, s.created_at) > v_baseline)
  ),
  filtered AS (
    SELECT * FROM base
    WHERE (v_period IS NULL OR period_key = v_period)
      AND (v_payment IS NULL OR (v_payment = 'paid') = is_paid)
      AND (v_phase IS NULL OR phase = v_phase)
  )
  SELECT jsonb_build_object(
    'baseline', v_baseline,
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
REVOKE ALL ON FUNCTION public.admin_subscription_report(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_subscription_report(jsonb) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. Company payment methods
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  method_type text NOT NULL CHECK (method_type IN ('instapay', 'vodafone_cash', 'bank')),
  display_name text NOT NULL CHECK (btrim(display_name) <> ''),
  account_holder text,
  instapay_address text,
  wallet_phone text,
  bank_name text,
  bank_account_number text,
  iban text,
  instructions text,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payment_method_fields CHECK (
    (method_type = 'instapay' AND NULLIF(btrim(instapay_address), '') IS NOT NULL)
    OR (method_type = 'vodafone_cash' AND wallet_phone ~ '^01[0-9]{9}$')
    OR (method_type = 'bank' AND NULLIF(btrim(bank_name), '') IS NOT NULL AND NULLIF(btrim(bank_account_number), '') IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_payment_methods_company ON public.company_payment_methods(company_id, is_active, sort_order);

ALTER TABLE public.company_payment_methods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.company_payment_methods FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_payment_methods TO authenticated;

DROP POLICY IF EXISTS payment_methods_read ON public.company_payment_methods;
CREATE POLICY payment_methods_read ON public.company_payment_methods FOR SELECT TO authenticated
USING (
  public.can_manage_line_company(company_id)
  -- Students: active methods of a company they can subscribe to or are subscribed with.
  OR (NOT public.is_admin() AND is_active AND (
    EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.student_id = auth.uid() AND s.company_id = company_payment_methods.company_id)
    OR EXISTS (SELECT 1 FROM public.lines l JOIN public.companies c ON c.id = l.company_id AND c.is_active
               WHERE l.company_id = company_payment_methods.company_id AND l.is_active
                 AND EXISTS (SELECT 1 FROM public.line_trips t WHERE t.line_id = l.id AND t.direction = 'departure'
                             AND public.trip_serves_student(t, auth.uid())))))
);
DROP POLICY IF EXISTS payment_methods_manage ON public.company_payment_methods;
CREATE POLICY payment_methods_manage ON public.company_payment_methods FOR ALL TO authenticated
USING (public.can_manage_line_company(company_id))
WITH CHECK (public.can_manage_line_company(company_id));

ALTER TABLE public.receipts
  ADD COLUMN IF NOT EXISTS payment_method_id uuid REFERENCES public.company_payment_methods(id) ON DELETE SET NULL;

-- The chosen method must be an active method of the subscription's company.
CREATE OR REPLACE FUNCTION public.validate_receipt_payment_method()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.payment_method_id IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.payment_method_id IS DISTINCT FROM OLD.payment_method_id)
     AND NOT EXISTS (
       SELECT 1 FROM public.company_payment_methods pm JOIN public.subscriptions s ON s.id = NEW.subscription_id
       JOIN public.lines l ON l.id = s.line_id
       WHERE pm.id = NEW.payment_method_id AND pm.company_id = l.company_id AND pm.is_active) THEN
    RAISE EXCEPTION 'وسيلة الدفع المختارة غير متاحة لشركة هذا الاشتراك.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_validate_receipt_payment_method ON public.receipts;
CREATE TRIGGER trg_validate_receipt_payment_method
BEFORE INSERT OR UPDATE OF payment_method_id ON public.receipts
FOR EACH ROW EXECUTE FUNCTION public.validate_receipt_payment_method();

-- ------------------------------------------------------------------------------
-- 4. Admin-assisted password reset bookkeeping (no passwords stored anywhere)
-- ------------------------------------------------------------------------------
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.password_admin_resets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES public.students(id) ON DELETE SET NULL,
  reset_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  generated boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.password_admin_resets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.password_admin_resets FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.password_admin_resets FROM authenticated;  -- service role only
GRANT SELECT ON public.password_admin_resets TO authenticated;
DROP POLICY IF EXISTS password_admin_resets_read ON public.password_admin_resets;
CREATE POLICY password_admin_resets_read ON public.password_admin_resets FOR SELECT TO authenticated
USING (public.is_super_admin());

-- The flag can only be changed by the service role (Edge Functions): company
-- admins may update other student columns, students cannot update at all.
CREATE OR REPLACE FUNCTION public.guard_must_change_password()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.must_change_password IS DISTINCT FROM OLD.must_change_password AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'لا يمكن تعديل حالة كلمة المرور مباشرة.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_must_change_password ON public.students;
CREATE TRIGGER trg_guard_must_change_password
BEFORE UPDATE OF must_change_password ON public.students
FOR EACH ROW EXECUTE FUNCTION public.guard_must_change_password();

-- ------------------------------------------------------------------------------
-- Student catalogue: also return the universities each line serves.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.line_university_names(p_line_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(u.name ORDER BY u.name), '[]'::jsonb)
  FROM public.line_universities lu JOIN public.universities u ON u.id = lu.university_id
  WHERE lu.line_id = p_line_id
$$;
GRANT EXECUTE ON FUNCTION public.line_university_names(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 5. save_line: + university_ids (at least one), trip universities must be among them.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_line(p_line jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line_id uuid := NULLIF(p_line->>'id', '')::uuid;
  v_company uuid := NULLIF(p_line->>'company_id', '')::uuid;
  v_existing public.lines%ROWTYPE;
  v_name text := btrim(COALESCE(p_line->>'name', ''));
  v_origin text := btrim(COALESCE(p_line->>'origin_name', ''));
  v_dest uuid := NULLIF(p_line->>'destination_university_id', '')::uuid;
  -- Universities served by the line (shared route, stored once).
  v_unis uuid[] := ARRAY(SELECT DISTINCT x::uuid FROM jsonb_array_elements_text(COALESCE(p_line->'university_ids', '[]'::jsonb)) x
                         WHERE NULLIF(x, '') IS NOT NULL);
  v_stations jsonb := COALESCE(p_line->'stations', '[]'::jsonb);
  v_trips jsonb := COALESCE(p_line->'trips', '[]'::jsonb);
  v_station_ids uuid[] := '{}';
  v_kept_trips uuid[] := '{}';
  v_station jsonb;
  v_trip jsonb;
  v_stop jsonb;
  v_sid uuid;
  v_tid uuid;
  v_idx int;
  v_prev time;
  v_time time;
  v_order int;
  v_seen text[] := '{}';
  v_key text;
BEGIN
  IF v_line_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.lines WHERE id = v_line_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.' USING ERRCODE = 'P0002'; END IF;
    IF NOT public.can_manage_line_company(v_existing.company_id) THEN
      RAISE EXCEPTION 'غير مسموح بتعديل هذا الخط.' USING ERRCODE = '42501';
    END IF;
    v_company := v_existing.company_id;  -- a line never changes company
  ELSE
    IF public.is_company_admin() THEN v_company := public.current_admin_company_id(); END IF;
    IF v_company IS NULL OR NOT public.can_manage_line_company(v_company) THEN
      RAISE EXCEPTION 'غير مسموح بإنشاء خط لهذه الشركة.' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ---- validation --------------------------------------------------------
  IF v_name = '' THEN RAISE EXCEPTION 'اكتب اسم الخط.' USING ERRCODE = '23514'; END IF;
  IF v_origin = '' THEN RAISE EXCEPTION 'حدد نقطة البداية.' USING ERRCODE = '23514'; END IF;
  IF cardinality(v_unis) = 0 AND v_dest IS NOT NULL THEN v_unis := ARRAY[v_dest]; END IF;
  IF cardinality(v_unis) = 0 THEN
    RAISE EXCEPTION 'اختر جامعة واحدة على الأقل يخدمها الخط.' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_unis) u WHERE NOT EXISTS (SELECT 1 FROM public.universities x WHERE x.id = u)) THEN
    RAISE EXCEPTION 'إحدى الجامعات المختارة غير موجودة.' USING ERRCODE = '23514';
  END IF;
  -- The route's end label: the chosen destination when it is one of the
  -- line's universities, otherwise the first selected university.
  IF v_dest IS NULL OR NOT (v_dest = ANY (v_unis)) THEN v_dest := v_unis[1]; END IF;
  IF COALESCE((p_line->>'price_termly')::numeric, -1) < 0 OR COALESCE((p_line->>'price_yearly')::numeric, -1) < 0
     OR COALESCE((p_line->>'price_daily')::numeric, -1) < 0 THEN
    RAISE EXCEPTION 'الأسعار مطلوبة ولا يمكن أن تكون سالبة.' USING ERRCODE = '23514';
  END IF;
  IF jsonb_array_length(v_stations) = 0 THEN
    RAISE EXCEPTION 'أضف محطة واحدة على الأقل بين البداية والوجهة.' USING ERRCODE = '23514';
  END IF;
  FOR v_idx IN 0 .. jsonb_array_length(v_stations) - 1 LOOP
    IF btrim(COALESCE(v_stations->v_idx->>'name', '')) = '' THEN
      RAISE EXCEPTION 'اسم المحطة رقم % فارغ.', v_idx + 1 USING ERRCODE = '23514';
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_trips) t WHERE t->>'direction' = 'departure') THEN
    RAISE EXCEPTION 'أضف رحلة ذهاب واحدة على الأقل بموعد انطلاقها.' USING ERRCODE = '23514';
  END IF;

  FOR v_trip IN SELECT * FROM jsonb_array_elements(v_trips) LOOP
    IF v_trip->>'direction' NOT IN ('departure', 'return') THEN
      RAISE EXCEPTION 'نوع الرحلة غير صحيح.' USING ERRCODE = '23514';
    END IF;
    IF NULLIF(v_trip->>'start_time', '') IS NULL THEN
      RAISE EXCEPTION 'حدد موعد انطلاق كل رحلة.' USING ERRCODE = '23514';
    END IF;
    IF NULLIF(v_trip->>'university_id', '') IS NOT NULL
       AND NOT ((v_trip->>'university_id')::uuid = ANY (v_unis)) THEN
      RAISE EXCEPTION 'جامعة إحدى الرحلات ليست من جامعات الخط المختارة.' USING ERRCODE = '23514';
    END IF;
    v_key := (v_trip->>'direction') || '|' || (v_trip->>'start_time')::time || '|' || COALESCE(v_trip->>'university_id', '');
    IF v_key = ANY (v_seen) THEN
      RAISE EXCEPTION 'رحلتان بنفس الاتجاه والموعد والجامعة. عدّل إحداهما.' USING ERRCODE = '23514';
    END IF;
    v_seen := v_seen || v_key;
    IF jsonb_array_length(COALESCE(v_trip->'stops', '[]'::jsonb)) = 0 THEN
      RAISE EXCEPTION 'رحلة % لا تمر بأي محطة. حدد موعد المرور على المحطات.', (v_trip->>'start_time')::time
        USING ERRCODE = '23514';
    END IF;
    -- Stop times follow the route: forward for departures, reversed for returns,
    -- and never before the trip's start time.
    v_prev := (v_trip->>'start_time')::time;
    FOR v_stop IN
      SELECT s FROM jsonb_array_elements(v_trip->'stops') s
      ORDER BY CASE WHEN v_trip->>'direction' = 'departure' THEN (s->>'station_index')::int
                    ELSE -(s->>'station_index')::int END
    LOOP
      v_idx := (v_stop->>'station_index')::int;
      IF v_idx IS NULL OR v_idx < 0 OR v_idx >= jsonb_array_length(v_stations) THEN
        RAISE EXCEPTION 'محطة غير معروفة في إحدى الرحلات.' USING ERRCODE = '23514';
      END IF;
      v_time := NULLIF(v_stop->>'time', '')::time;
      IF v_time IS NULL THEN CONTINUE; END IF;
      IF v_time < v_prev THEN
        RAISE EXCEPTION 'موعد محطة "%" (%) في رحلة % أسبق من المحطة التي قبلها. المواعيد يجب أن تكون بترتيب المسار.',
          v_stations->v_idx->>'name', v_time, (v_trip->>'start_time')::time USING ERRCODE = '23514';
      END IF;
      v_prev := v_time;
    END LOOP;
    IF NULLIF(v_trip->>'arrival_time', '') IS NOT NULL AND (v_trip->>'arrival_time')::time < v_prev THEN
      RAISE EXCEPTION 'موعد الوصول في رحلة % أسبق من آخر محطة.', (v_trip->>'start_time')::time USING ERRCODE = '23514';
    END IF;
  END LOOP;

  -- ---- line --------------------------------------------------------------
  IF v_line_id IS NULL THEN
    INSERT INTO public.lines (company_id, name, origin_name, destination_university_id,
                              price_termly, price_yearly, price_daily, is_active)
    VALUES (v_company, v_name, v_origin, v_dest, (p_line->>'price_termly')::numeric,
            (p_line->>'price_yearly')::numeric, (p_line->>'price_daily')::numeric,
            COALESCE((p_line->>'is_active')::boolean, true))
    RETURNING id INTO v_line_id;
  ELSE
    UPDATE public.lines SET name = v_name, origin_name = v_origin, destination_university_id = v_dest,
      price_termly = (p_line->>'price_termly')::numeric, price_yearly = (p_line->>'price_yearly')::numeric,
      price_daily = (p_line->>'price_daily')::numeric,
      is_active = COALESCE((p_line->>'is_active')::boolean, is_active)
    WHERE id = v_line_id;
  END IF;

  -- ---- universities served by the line --------------------------------------
  DELETE FROM public.line_universities WHERE line_id = v_line_id AND NOT (university_id = ANY (v_unis));
  INSERT INTO public.line_universities (line_id, university_id)
  SELECT v_line_id, u FROM unnest(v_unis) u ON CONFLICT DO NOTHING;

  -- ---- stations (keep ids; move order out of the way of the unique index) ---
  UPDATE public.stations SET order_index = -1000 - order_index WHERE line_id = v_line_id;
  v_order := 0;
  FOR v_station IN SELECT * FROM jsonb_array_elements(v_stations) LOOP
    v_order := v_order + 1;
    v_sid := NULLIF(v_station->>'id', '')::uuid;
    IF v_sid IS NOT NULL AND EXISTS (SELECT 1 FROM public.stations WHERE id = v_sid AND line_id = v_line_id) THEN
      UPDATE public.stations SET name = btrim(v_station->>'name'), order_index = v_order, is_active = true
      WHERE id = v_sid;
    ELSE
      INSERT INTO public.stations (line_id, name, order_index, departure_times, return_times, is_active)
      VALUES (v_line_id, btrim(v_station->>'name'), v_order, '{}', '{}', true)
      RETURNING id INTO v_sid;
    END IF;
    v_station_ids := v_station_ids || v_sid;
  END LOOP;
  -- Removed stations: delete when unused, otherwise retire them (history kept).
  DELETE FROM public.stations st WHERE st.line_id = v_line_id AND NOT (st.id = ANY (v_station_ids))
    AND NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.station_id = st.id)
    AND NOT EXISTS (SELECT 1 FROM public.supervisor_scan_events e WHERE e.station_id = st.id);
  UPDATE public.stations st SET is_active = false, order_index = 10000 + abs(order_index)
  WHERE st.line_id = v_line_id AND NOT (st.id = ANY (v_station_ids));

  -- ---- trips + stop times ---------------------------------------------------
  FOR v_trip IN SELECT * FROM jsonb_array_elements(v_trips) LOOP
    v_tid := NULLIF(v_trip->>'id', '')::uuid;
    IF v_tid IS NOT NULL AND EXISTS (SELECT 1 FROM public.line_trips WHERE id = v_tid AND line_id = v_line_id) THEN
      UPDATE public.line_trips SET direction = v_trip->>'direction', label = btrim(COALESCE(v_trip->>'label', '')),
        start_time = (v_trip->>'start_time')::time, arrival_time = NULLIF(v_trip->>'arrival_time', '')::time,
        university_id = NULLIF(v_trip->>'university_id', '')::uuid,
        is_active = COALESCE((v_trip->>'is_active')::boolean, true), updated_at = now()
      WHERE id = v_tid;
      DELETE FROM public.line_trip_stops WHERE trip_id = v_tid;
    ELSE
      INSERT INTO public.line_trips (line_id, direction, label, start_time, arrival_time, university_id, is_active)
      VALUES (v_line_id, v_trip->>'direction', btrim(COALESCE(v_trip->>'label', '')),
              (v_trip->>'start_time')::time, NULLIF(v_trip->>'arrival_time', '')::time,
              NULLIF(v_trip->>'university_id', '')::uuid, COALESCE((v_trip->>'is_active')::boolean, true))
      RETURNING id INTO v_tid;
    END IF;
    v_kept_trips := v_kept_trips || v_tid;
    INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time)
    SELECT v_tid, v_station_ids[(s->>'station_index')::int + 1], (s->>'time')::time
    FROM jsonb_array_elements(v_trip->'stops') s
    WHERE NULLIF(s->>'time', '') IS NOT NULL;
  END LOOP;
  -- Removed trips: delete when unused, otherwise deactivate (history kept).
  DELETE FROM public.line_trips t WHERE t.line_id = v_line_id AND NOT (t.id = ANY (v_kept_trips))
    AND NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.departure_trip_id = t.id OR s.return_trip_id = t.id);
  UPDATE public.line_trips t SET is_active = false, updated_at = now()
  WHERE t.line_id = v_line_id AND NOT (t.id = ANY (v_kept_trips));

  -- Current subscribers follow their trip's new stop time.
  UPDATE public.subscriptions sub SET departure_time = s.stop_time
  FROM public.line_trip_stops s
  WHERE sub.line_id = v_line_id AND s.trip_id = sub.departure_trip_id AND s.station_id = sub.station_id
    AND sub.status IN ('pending_payment', 'pending_review', 'active') AND sub.departure_time IS DISTINCT FROM s.stop_time;
  UPDATE public.subscriptions sub SET return_time = s.stop_time
  FROM public.line_trip_stops s
  WHERE sub.line_id = v_line_id AND s.trip_id = sub.return_trip_id AND s.station_id = sub.station_id
    AND sub.status IN ('pending_payment', 'pending_review', 'active') AND sub.return_time IS DISTINCT FROM s.stop_time;

  PERFORM public.sync_station_times(v_line_id);
  RETURN v_line_id;
END;
$$;

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
          'price_termly', l.price_termly, 'price_yearly', l.price_yearly, 'price_daily', l.price_daily,
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

COMMIT;
