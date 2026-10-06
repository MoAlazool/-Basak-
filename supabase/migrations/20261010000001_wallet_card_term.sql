-- Wallet card: show which term the student's approved subscription is for.
--
-- The term appears together with the line and pickup station, under the same
-- rule: only for an APPROVED subscription (valid today, or approved in
-- advance). It names the period; it is not a validity check. Whether the
-- student may ride is still decided only by supervisor_check_in_student().
-- Installed cards pick the new field up the next time they are refreshed.
-- Safe to re-run.
BEGIN;

CREATE OR REPLACE FUNCTION public.wallet_card_content(p_student_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_student public.students%ROWTYPE;
  v_route record;
  v_company_id uuid;
  v_company public.companies%ROWTYPE;
  v_theme public.wallet_card_settings%ROWTYPE;
  v_photo jsonb;
BEGIN
  SELECT * INTO v_student FROM public.students WHERE id = p_student_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Route: only from an APPROVED subscription - the one valid today, else one
  -- approved in advance. A line the student merely selected (pending payment
  -- or review, rejected) is never shown.
  SELECT sub.company_id, l.name AS line_name, st.name AS station_name, public.period_label(sub) AS term
  INTO v_route
  FROM public.subscriptions sub
  JOIN public.lines l ON l.id = sub.line_id
  JOIN public.stations st ON st.id = sub.station_id
  WHERE sub.student_id = p_student_id AND sub.status = 'active'
    AND (sub.end_date IS NULL OR sub.end_date >= v_today)
  ORDER BY (COALESCE(sub.start_date, v_today) <= v_today) DESC,
           CASE WHEN COALESCE(sub.start_date, v_today) <= v_today THEN NULL ELSE sub.start_date END ASC NULLS FIRST,
           sub.created_at DESC
  LIMIT 1;

  -- Branding: that subscription's company, else the company of the last
  -- subscription that was ever approved, so the card keeps its look between
  -- semesters. A pending subscription with another company changes nothing.
  IF v_route.company_id IS NOT NULL THEN
    v_company_id := v_route.company_id;
  ELSE
    SELECT sub.company_id INTO v_company_id
    FROM public.subscriptions sub
    WHERE sub.student_id = p_student_id AND sub.status IN ('active', 'expired') AND sub.company_id IS NOT NULL
    ORDER BY COALESCE(sub.end_date, sub.start_date) DESC NULLS LAST, sub.created_at DESC
    LIMIT 1;
  END IF;
  IF v_company_id IS NOT NULL THEN
    SELECT * INTO v_company FROM public.companies WHERE id = v_company_id;
    SELECT * INTO v_theme FROM public.wallet_card_settings WHERE company_id = v_company_id;
  END IF;

  -- The photo's version changes when the file is replaced, even at the same path.
  IF NULLIF(btrim(COALESCE(v_student.profile_image_url, '')), '') IS NOT NULL THEN
    SELECT jsonb_build_object('path', v_student.profile_image_url,
                              'version', COALESCE(max(to_jsonb(o) ->> 'updated_at'), max(o.created_at::text), ''))
    INTO v_photo
    FROM storage.objects o
    WHERE o.bucket_id = 'student-avatars' AND o.name = v_student.profile_image_url
    HAVING count(*) > 0;
  END IF;

  RETURN jsonb_build_object(
    'student', jsonb_build_object(
      'id', v_student.id,
      'full_name', btrim(v_student.full_name),
      'qr_code_value', v_student.qr_code_value,
      'university', NULLIF(NULLIF(btrim(COALESCE(v_student.university, '')), ''), 'غير محدد'),
      -- "غير محدد" is the column default, i.e. missing: never print it.
      'college', NULLIF(NULLIF(btrim(COALESCE(v_student.college, '')), ''), 'غير محدد')),
    'photo', v_photo,
    'company', CASE WHEN v_company.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_company.id,
      'name', btrim(v_company.name),
      'logo_path', v_company.logo_path,
      'contact_phone', NULLIF(btrim(COALESCE(v_company.contact_phone, '')), ''),
      'contact_label', NULLIF(btrim(COALESCE(v_company.contact_label, '')), '')) END,
    'theme', jsonb_build_object(
      'background_color', COALESCE(v_theme.background_color, '#00658D'),
      'foreground_color', COALESCE(v_theme.foreground_color, '#FFFFFF'),
      'label_color', COALESCE(v_theme.label_color, '#D6EEF9'),
      'card_title', NULLIF(btrim(COALESCE(v_theme.card_title, '')), ''),
      'banner_path', v_theme.banner_path,
      'revision', COALESCE(v_theme.revision, 0)),
    'route', CASE WHEN v_route.line_name IS NULL THEN NULL ELSE jsonb_build_object(
      'line', NULLIF(btrim(v_route.line_name), ''),
      'station', NULLIF(btrim(COALESCE(v_route.station_name, '')), ''),
      -- Which term the approved subscription is for, e.g. "الفصل الدراسي الأول 2026/2027".
      'term', NULLIF(btrim(COALESCE(v_route.term, '')), '')) END
  );
END;
$$;

COMMIT;
