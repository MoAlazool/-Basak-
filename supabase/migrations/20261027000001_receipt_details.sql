-- What a printed receipt says about the company: its phone, address and, when
-- it has them, its commercial register and tax numbers. They are copied onto
-- each receipt when it is issued, like everything else on it, so a receipt
-- already issued keeps the details of its day.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS commercial_register text,
  ADD COLUMN IF NOT EXISTS tax_number text;

ALTER TABLE public.subscription_receipts
  ADD COLUMN IF NOT EXISTS company_phone text,
  ADD COLUMN IF NOT EXISTS company_address text,
  ADD COLUMN IF NOT EXISTS company_commercial_register text,
  ADD COLUMN IF NOT EXISTS company_tax_number text,
  ADD COLUMN IF NOT EXISTS company_logo_path text;

-- Receipts issued before these columns existed take the company's phone and
-- logo as they are today, once; nothing else about them is touched.
ALTER TABLE public.subscription_receipts DISABLE TRIGGER trg_forbid_receipt_change;
UPDATE public.subscription_receipts r
SET company_phone = NULLIF(btrim(c.contact_phone), ''), company_logo_path = c.logo_path
FROM public.companies c
WHERE c.id = r.company_id AND r.company_phone IS NULL AND r.company_logo_path IS NULL;
ALTER TABLE public.subscription_receipts ENABLE TRIGGER trg_forbid_receipt_change;

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
    company_tax_number, company_logo_path)
  VALUES (s.id, s.company_id, s.student_id, v_no, s.company_name, s.full_name, s.phone, s.university_name, s.line_name,
    s.station_name, s.period_code, COALESCE(s.period_label, ''), s.start_date, s.end_date,
    COALESCE(r.amount, s.price), r.display_name, COALESCE(r.reviewed_at, s.paid_at),
    NULLIF(btrim(s.contact_phone), ''), NULLIF(btrim(s.address), ''), NULLIF(btrim(s.commercial_register), ''),
    NULLIF(btrim(s.tax_number), ''), s.logo_path);
END;
$$;

-- The company's own admin (or the platform admin) sets what is printed.
CREATE OR REPLACE FUNCTION public.set_company_receipt_info(p_company_id uuid, p_phone text, p_address text,
                                                          p_commercial_register text, p_tax_number text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_company_id IS NULL OR NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك تعديل بيانات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  IF length(COALESCE(p_address, '')) > 200 OR length(COALESCE(p_commercial_register, '')) > 40
     OR length(COALESCE(p_tax_number, '')) > 40 OR length(COALESCE(p_phone, '')) > 30 THEN
    RAISE EXCEPTION 'أحد الحقول أطول من المسموح.' USING ERRCODE = '22001';
  END IF;
  UPDATE public.companies
  SET contact_phone = NULLIF(btrim(p_phone), ''), address = NULLIF(btrim(p_address), ''),
      commercial_register = NULLIF(btrim(p_commercial_register), ''), tax_number = NULLIF(btrim(p_tax_number), '')
  WHERE id = p_company_id;
  RETURN (SELECT jsonb_build_object('phone', c.contact_phone, 'address', c.address,
            'commercial_register', c.commercial_register, 'tax_number', c.tax_number)
          FROM public.companies c WHERE c.id = p_company_id);
END;
$$;
REVOKE ALL ON FUNCTION public.set_company_receipt_info(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_company_receipt_info(uuid, text, text, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_subscription_settings(p_company_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
    -- What is printed about the company on its receipts.
    'receipt_info', (SELECT jsonb_build_object('phone', c.contact_phone, 'address', c.address,
                       'commercial_register', c.commercial_register, 'tax_number', c.tax_number)
                     FROM public.companies c WHERE c.id = v_company),
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
