-- The number a student sees on a receipt must not count the company's
-- customers: "receipt 00012" tells everyone it is the twelfth. Each receipt
-- therefore gets a reference that says nothing about how many came before it
-- (e.g. 26-7F3A9C2E). The running number stays for the company's own books,
-- where the dashboard shows it, and students can no longer read it at all.

ALTER TABLE public.subscription_receipts ADD COLUMN IF NOT EXISTS receipt_code text;

-- "YY-XXXXXXXX": the year and eight random characters, never used before.
CREATE OR REPLACE FUNCTION public.new_receipt_code() RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_code text;
BEGIN
  LOOP
    v_code := to_char(public.cairo_today(), 'YY') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.subscription_receipts r WHERE r.receipt_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;
REVOKE ALL ON FUNCTION public.new_receipt_code() FROM PUBLIC, anon, authenticated;

-- Receipts already issued get their reference once; nothing else about them changes.
ALTER TABLE public.subscription_receipts DISABLE TRIGGER trg_forbid_receipt_change;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.subscription_receipts WHERE receipt_code IS NULL ORDER BY receipt_no LOOP
    UPDATE public.subscription_receipts SET receipt_code = public.new_receipt_code() WHERE id = r.id;
  END LOOP;
END;
$$;
ALTER TABLE public.subscription_receipts ENABLE TRIGGER trg_forbid_receipt_change;
ALTER TABLE public.subscription_receipts ALTER COLUMN receipt_code SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS subscription_receipts_code_key ON public.subscription_receipts(receipt_code);

-- Signed-in users read every column except the running number. Company admins
-- get that number through the report, which checks who is asking.
REVOKE SELECT ON public.subscription_receipts FROM authenticated;
GRANT SELECT (id, subscription_id, company_id, student_id, receipt_code, company_name, student_name, student_phone,
              university_name, line_name, station_name, option, period_label, start_date, end_date, amount,
              payment_method, approved_at, issued_at, company_phone, company_address, company_commercial_register,
              company_tax_number, company_logo_path)
  ON public.subscription_receipts TO authenticated;

CREATE OR REPLACE FUNCTION public.issue_subscription_receipt(p_subscription_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  s record;
  r record;
  v_no integer;
BEGIN
  SELECT sub.id, sub.company_id, sub.student_id, sub.period_code, sub.start_date, sub.end_date, sub.price, sub.paid_at,
         public.period_label(sub) AS period_label, c.name AS company_name, st.full_name, st.phone,
         c.contact_phone, c.address, c.commercial_register, c.tax_number, c.logo_path,
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
    amount, payment_method, approved_at, company_phone, company_address, company_commercial_register,
    company_tax_number, company_logo_path, receipt_code)
  VALUES (s.id, s.company_id, s.student_id, v_no, s.company_name, s.full_name, s.phone, s.university_name, s.line_name,
    s.station_name, s.period_code, COALESCE(s.period_label, ''), s.start_date, s.end_date,
    COALESCE(r.amount, s.price), r.display_name, COALESCE(r.reviewed_at, s.paid_at),
    NULLIF(btrim(s.contact_phone), ''), NULLIF(btrim(s.address), ''), NULLIF(btrim(s.commercial_register), ''),
    NULLIF(btrim(s.tax_number), ''), s.logo_path, public.new_receipt_code());
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_subscription_report(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
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
        'receipt_no', (SELECT x.receipt_no FROM public.subscription_receipts x WHERE x.subscription_id = f.id),
        'receipt_code', (SELECT x.receipt_code FROM public.subscription_receipts x WHERE x.subscription_id = f.id))
        ORDER BY f.paid_at DESC NULLS LAST, f.created_at DESC)
      FROM (SELECT * FROM filtered LIMIT 2000) f), '[]'::jsonb)
  ) INTO v_data;
  RETURN v_data;
END;
$$;
