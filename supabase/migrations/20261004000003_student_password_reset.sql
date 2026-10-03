-- ==============================================================================
-- Migration: 20261004000003_student_password_reset.sql
-- Run AFTER 20261004000002_academic_terms_and_subscription_periods.sql. Safe to re-run.
--
-- Student "Forgot password". Students sign in with their phone number (Auth
-- e-mail <phone>@busak.app, no SMS gateway), so Supabase cannot e-mail or text
-- them a recovery link. The reset is verified by the bus company instead:
--   1. The student taps "Forgot password" and enters their phone number
--      -> request_student_password_reset() opens a request (no account
--         enumeration: the answer is the same for unknown numbers).
--   2. The student's company admin (or the super admin) sees the request in the
--      dashboard, confirms the student's identity by phone and issues a
--      one-time 6-digit code (admin_issue_password_reset_code). Only a bcrypt
--      hash is stored; the code expires after 30 minutes and allows 5 tries.
--   3. In the app the student enters phone + code + new password. The
--      student-reset-password Edge Function checks the code
--      (check_student_password_reset_code), sets the password through the
--      Supabase Auth admin API and closes the request.
-- Passwords never touch these tables or the dashboard.
-- ==============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.password_reset_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'code_issued', 'completed', 'cancelled', 'expired')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  code_hash text,
  code_expires_at timestamptz,
  code_issued_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  code_issued_at timestamptz,
  failed_attempts int NOT NULL DEFAULT 0,
  closed_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_password_reset_open
  ON public.password_reset_requests(student_id) WHERE status IN ('pending', 'code_issued');
CREATE INDEX IF NOT EXISTS idx_password_reset_requested ON public.password_reset_requests(requested_at DESC);

ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.password_reset_requests FROM anon, authenticated;
GRANT ALL ON public.password_reset_requests TO service_role;

-- Can the caller (admin) handle this student's requests?
CREATE OR REPLACE FUNCTION public.admin_can_manage_student(p_student_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = p_student_id AND l.company_id = public.current_admin_company_id()))
$$;
REVOKE ALL ON FUNCTION public.admin_can_manage_student(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_can_manage_student(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.normalize_egyptian_phone(p_phone text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d text := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
BEGIN
  IF d LIKE '20%' AND length(d) >= 12 THEN d := substr(d, 3); END IF;
  IF length(d) = 10 AND d LIKE '1%' THEN d := '0' || d; END IF;
  RETURN d;
END;
$$;

-- Step 1 (student, before sign-in).
CREATE OR REPLACE FUNCTION public.request_student_password_reset(p_phone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_phone text := public.normalize_egyptian_phone(p_phone);
  v_student uuid;
BEGIN
  IF v_phone !~ '^01[0125][0-9]{8}$' THEN
    RAISE EXCEPTION 'أدخل رقم هاتف مصري صحيح.' USING ERRCODE = '22023';
  END IF;

  -- Close requests whose code timed out.
  UPDATE public.password_reset_requests SET status = 'expired', closed_at = now()
  WHERE status = 'code_issued' AND code_expires_at < now();

  SELECT id INTO v_student FROM public.students WHERE phone = v_phone;
  IF v_student IS NOT NULL THEN
    INSERT INTO public.password_reset_requests (student_id) VALUES (v_student)
    ON CONFLICT (student_id) WHERE status IN ('pending', 'code_issued') DO NOTHING;
  END IF;
  -- Same answer whether or not the number is registered.
  RETURN jsonb_build_object('status', 'requested');
END;
$$;
REVOKE ALL ON FUNCTION public.request_student_password_reset(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_student_password_reset(text) TO anon, authenticated;

-- Dashboard list (scoped).
CREATE OR REPLACE FUNCTION public.admin_list_password_reset_requests()
RETURNS TABLE (
  id uuid, student_id uuid, student_name text, student_phone text, status text,
  requested_at timestamptz, code_issued_at timestamptz, code_expires_at timestamptz, failed_attempts int
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'متاح للمسؤولين فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT r.id, r.student_id, s.full_name, s.phone,
         CASE WHEN r.status = 'code_issued' AND r.code_expires_at < now() THEN 'expired' ELSE r.status END,
         r.requested_at, r.code_issued_at, r.code_expires_at, r.failed_attempts
  FROM public.password_reset_requests r JOIN public.students s ON s.id = r.student_id
  WHERE r.requested_at > now() - INTERVAL '30 days'
    AND public.admin_can_manage_student(r.student_id)
  ORDER BY (r.status IN ('pending', 'code_issued')) DESC, r.requested_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_password_reset_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_password_reset_requests() TO authenticated;

-- Step 2 (admin): returns the plain code ONCE; only its hash is stored.
CREATE OR REPLACE FUNCTION public.admin_issue_password_reset_code(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_req public.password_reset_requests%ROWTYPE;
  v_code text;
BEGIN
  SELECT * INTO v_req FROM public.password_reset_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT public.admin_can_manage_student(v_req.student_id) THEN
    RAISE EXCEPTION 'الطلب غير موجود أو خارج صلاحياتك.' USING ERRCODE = '42501';
  END IF;
  IF v_req.status NOT IN ('pending', 'code_issued') THEN
    RAISE EXCEPTION 'هذا الطلب مغلق. اطلب من الطالب إرسال طلب جديد.';
  END IF;

  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  UPDATE public.password_reset_requests
  SET status = 'code_issued', code_hash = crypt(v_code, gen_salt('bf', 8)),
      code_expires_at = now() + INTERVAL '30 minutes', code_issued_by = auth.uid(),
      code_issued_at = now(), failed_attempts = 0
  WHERE id = p_request_id;

  RETURN jsonb_build_object('code', v_code, 'expires_at', now() + INTERVAL '30 minutes');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_password_reset_code(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_password_reset_code(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_cancel_password_reset(p_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_student uuid;
BEGIN
  SELECT student_id INTO v_student FROM public.password_reset_requests WHERE id = p_request_id;
  IF v_student IS NULL OR NOT public.admin_can_manage_student(v_student) THEN
    RAISE EXCEPTION 'الطلب غير موجود أو خارج صلاحياتك.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.password_reset_requests SET status = 'cancelled', closed_at = now(), code_hash = NULL
  WHERE id = p_request_id AND status IN ('pending', 'code_issued');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cancel_password_reset(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_password_reset(uuid) TO authenticated;

-- Step 3 (service role only, from the student-reset-password Edge Function).
-- Returns a status instead of raising so failed attempts are counted.
CREATE OR REPLACE FUNCTION public.check_student_password_reset_code(p_phone text, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_req public.password_reset_requests%ROWTYPE;
BEGIN
  SELECT r.* INTO v_req
  FROM public.password_reset_requests r JOIN public.students s ON s.id = r.student_id
  WHERE s.phone = public.normalize_egyptian_phone(p_phone) AND r.status = 'code_issued'
  FOR UPDATE OF r;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_code');
  END IF;
  IF v_req.code_expires_at < now() THEN
    UPDATE public.password_reset_requests SET status = 'expired', closed_at = now(), code_hash = NULL WHERE id = v_req.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;
  IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' OR crypt(p_code, v_req.code_hash) <> v_req.code_hash THEN
    UPDATE public.password_reset_requests
    SET failed_attempts = failed_attempts + 1,
        status = CASE WHEN failed_attempts + 1 >= 5 THEN 'cancelled' ELSE status END,
        closed_at = CASE WHEN failed_attempts + 1 >= 5 THEN now() ELSE closed_at END,
        code_hash = CASE WHEN failed_attempts + 1 >= 5 THEN NULL ELSE code_hash END
    WHERE id = v_req.id;
    RETURN jsonb_build_object('ok', false,
      'reason', CASE WHEN v_req.failed_attempts + 1 >= 5 THEN 'locked' ELSE 'wrong_code' END,
      'attempts_left', greatest(0, 4 - v_req.failed_attempts));
  END IF;
  RETURN jsonb_build_object('ok', true, 'request_id', v_req.id, 'student_id', v_req.student_id);
END;
$$;
REVOKE ALL ON FUNCTION public.check_student_password_reset_code(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_student_password_reset_code(text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_student_password_reset(p_request_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.password_reset_requests SET status = 'completed', closed_at = now(), code_hash = NULL
  WHERE id = p_request_id AND status = 'code_issued'
$$;
REVOKE ALL ON FUNCTION public.complete_student_password_reset(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_student_password_reset(uuid) TO service_role;

COMMIT;
