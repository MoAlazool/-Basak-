-- ==============================================================================
-- Migration: 20261104000001_student_specialisation.sql
-- Run AFTER 20261103000001. Safe to re-run. Additive: one nullable column, one
-- new function, and one more key in two dashboard answers.
--
-- A student's specialisation (department), optional. It travels the way the
-- college does:
--   * written with the profile row at sign-up (the student's own INSERT), and
--   * changed afterwards only through update_my_profile, which now has a second
--     form taking the specialisation too. The three-argument form the released
--     app calls is left exactly as it is.
-- The dashboard shows it, read-only, wherever it shows the college:
-- get_company_students_page and get_pending_receipts_page answer one more key,
-- 'specialisation'. Their arguments, checks and every other key are unchanged.
-- ==============================================================================
BEGIN;

-- students is read by every screen. The ALTERs below need it exclusively for a
-- moment (the CHECK reads each row once: milliseconds at 100,000 rows). If
-- something else holds the table, give up after 5 seconds and change nothing,
-- rather than queue every reader behind this migration; then run it again.
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.students ADD COLUMN IF NOT EXISTS specialisation text;
ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_specialisation_length;
ALTER TABLE public.students ADD CONSTRAINT students_specialisation_length
  CHECK (specialisation IS NULL OR length(specialisation) <= 80);

-- The profile's optional details with the specialisation. Empty values clear a
-- field. The older form does its own part (and its own checks); this one adds
-- the specialisation and answers the profile as saved, with one more key.
CREATE OR REPLACE FUNCTION public.update_my_profile(p_email text, p_college text, p_birth_date date, p_specialisation text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_specialisation text := NULLIF(btrim(COALESCE(p_specialisation, '')), '');
  v_saved jsonb;
BEGIN
  IF length(COALESCE(v_specialisation, '')) > 80 THEN
    RAISE EXCEPTION 'اسم التخصص طويل جداً.' USING ERRCODE = '23514';
  END IF;
  v_saved := public.update_my_profile(p_email, p_college, p_birth_date);
  UPDATE public.students SET specialisation = v_specialisation WHERE id = auth.uid();
  RETURN v_saved || jsonb_build_object('specialisation', v_specialisation);
END;
$$;
REVOKE ALL ON FUNCTION public.update_my_profile(text, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_profile(text, text, date, text) TO authenticated;

-- ------------------------------------------------------------------------------
-- Dashboard: the two answers that carry the college now carry the
-- specialisation as well. Both bodies are those of 20261103000001 with the one
-- key added (marked "added").
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_company_students_page(
  p_company_id uuid, p_search text DEFAULT NULL, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0,
  p_with_total boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
  -- A phone typed with Arabic digits or spaces is still that phone.
  v_digits text := NULLIF(regexp_replace(translate(COALESCE(p_search, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '\D', '', 'g'), '');
  v_rows jsonb;
  v_count integer;
  v_total integer;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك عرض طلاب هذه الشركة.' USING ERRCODE = '42501';
  END IF;

  WITH page AS (
    SELECT st.id, st.phone, st.full_name, st.university, st.college, st.specialisation, st.profile_image_url, st.created_at
    FROM public.company_students m
    JOIN public.students st ON st.id = m.student_id
    WHERE m.company_id = p_company_id AND m.status = 'active'
      AND (v_search IS NULL
           OR st.full_name ILIKE '%' || v_search || '%'
           OR st.university ILIKE '%' || v_search || '%'
           OR (v_digits IS NOT NULL AND st.phone LIKE '%' || v_digits || '%'))
    ORDER BY st.created_at DESC, st.id
    LIMIT v_limit + 1 OFFSET v_offset
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', p.id, 'phone', p.phone, 'full_name', p.full_name, 'university', p.university, 'college', p.college,
           'specialisation', p.specialisation,  -- added
           'profile_image_url', p.profile_image_url, 'created_at', p.created_at,
           'subscriptions', COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
                      'id', s.id, 'status', s.status, 'type', s.type, 'price', s.price, 'created_at', s.created_at,
                      'start_date', s.start_date, 'end_date', s.end_date,
                      'period_label', public.period_label(s), 'period_phase', public.period_phase(s),
                      'departure_time', s.departure_time, 'return_time', s.return_time,
                      'line_name', l.name, 'trip_label', t.label, 'trip_university', u.name)
                    ORDER BY s.created_at DESC)
             FROM public.subscriptions s
             LEFT JOIN public.lines l ON l.id = s.line_id
             LEFT JOIN public.line_trips t ON t.id = s.departure_trip_id
             LEFT JOIN public.universities u ON u.id = t.university_id
             WHERE s.student_id = p.id AND s.company_id = p_company_id), '[]'::jsonb))
           ORDER BY p.created_at DESC, p.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count FROM page p;

  IF COALESCE(p_with_total, false) THEN
    SELECT count(*) INTO v_total
    FROM public.company_students m
    JOIN public.students st ON st.id = m.student_id
    WHERE m.company_id = p_company_id AND m.status = 'active'
      AND (v_search IS NULL
           OR st.full_name ILIKE '%' || v_search || '%'
           OR st.university ILIKE '%' || v_search || '%'
           OR (v_digits IS NOT NULL AND st.phone LIKE '%' || v_digits || '%'));
  END IF;

  -- The extra row only says there is a next page.
  IF v_count > v_limit THEN v_rows := v_rows - v_limit; END IF;
  RETURN jsonb_build_object('rows', v_rows, 'has_next', v_count > v_limit, 'total', v_total);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pending_receipts_page(p_company_id uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_rows jsonb;
  v_count integer;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك عرض إيصالات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  WITH page AS (
    SELECT r.id, r.image_url, r.attempt_number, r.created_at, r.amount, r.subscription_id
    FROM public.receipts r
    WHERE r.company_id = p_company_id AND r.status = 'pending'
    ORDER BY r.created_at, r.id
    LIMIT v_limit + 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', p.id, 'image_url', p.image_url, 'attempt_number', p.attempt_number, 'created_at', p.created_at,
           'amount', p.amount, 'subscription_id', p.subscription_id, 'student_id', s.student_id,
           'student_name', st.full_name, 'student_phone', st.phone, 'university', st.university, 'college', st.college,
           'specialisation', st.specialisation,  -- added
           'company_id', l.company_id, 'company_name', c.name, 'line_name', l.name, 'station_name', sn.name,
           'departure_time', s.departure_time, 'return_time', s.return_time, 'subscription_type', s.type,
           'period_label', public.period_label(s), 'period_start', s.start_date, 'period_end', s.end_date,
           'period_phase', public.period_phase(s), 'price', s.price)
           ORDER BY p.created_at, p.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count
  FROM page p
  LEFT JOIN public.subscriptions s ON s.id = p.subscription_id
  LEFT JOIN public.students st ON st.id = s.student_id
  LEFT JOIN public.lines l ON l.id = s.line_id
  LEFT JOIN public.companies c ON c.id = l.company_id
  LEFT JOIN public.stations sn ON sn.id = s.station_id;

  IF v_count > v_limit THEN v_rows := v_rows - v_limit; END IF;
  RETURN jsonb_build_object('rows', v_rows, 'has_more', v_count > v_limit,
    'total', (SELECT count(*) FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'pending'));
END;
$$;

REVOKE ALL ON FUNCTION public.get_company_students_page(uuid, text, integer, integer, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_pending_receipts_page(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_company_students_page(uuid, text, integer, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_receipts_page(uuid, integer) TO authenticated;

COMMIT;
