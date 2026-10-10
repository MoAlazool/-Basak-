-- ==============================================================================
-- Migration: 20261112000001_blocked_phones.sql
-- Run AFTER 20261111000001. Safe to re-run. Additive: one table, two triggers
-- and five functions.
--
-- Blocking a student: the platform admin stops a student instead of deleting
-- them (a deleted student could register again with the same number).
--   * The phone goes on public.blocked_phones. No student account may use it:
--     not the app's sign-up (refused before the account is made, and by the
--     database whatever the client sends), not an admin adding a student.
--   * The student's own account can no longer sign in (Auth's banned_until),
--     and its sessions end; the access token in hand lapses within the hour.
--   * Nothing is deleted: the account, its subscriptions and its history stay.
--     Unblocking undoes both. A number stays blocked after its account is
--     deleted, until it is unblocked.
-- Blocking is the platform admin's alone, like deleting an account.
-- ==============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.blocked_phones (
  phone text PRIMARY KEY CHECK (phone ~ '^[0-9]{8,15}$'),
  student_id uuid REFERENCES public.students(id) ON DELETE SET NULL,
  full_name text,
  reason text CHECK (reason IS NULL OR length(reason) <= 300),
  blocked_at timestamptz NOT NULL DEFAULT now(),
  blocked_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.blocked_phones ENABLE ROW LEVEL SECURITY;
-- Read and written through the functions below only.
REVOKE ALL ON public.blocked_phones FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_phone_blocked(p_phone text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.blocked_phones b
                 WHERE b.phone = public.normalize_egyptian_phone(COALESCE(p_phone, '')))
$$;
REVOKE ALL ON FUNCTION public.is_phone_blocked(text) FROM PUBLIC, anon, authenticated;

-- What a blocked number is told, wherever it is refused.
CREATE OR REPLACE FUNCTION public.blocked_phone_message() RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT 'هذا الرقم موقوف ولا يمكن التسجيل به. للاستفسار تواصل مع إدارة باصك.'::text
$$;

-- The app asks before it creates the account, to say why instead of failing.
-- Open to everyone: sign-up comes before sign-in.
CREATE OR REPLACE FUNCTION public.phone_can_register(p_phone text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT public.is_phone_blocked(p_phone)
$$;
REVOKE ALL ON FUNCTION public.phone_can_register(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.phone_can_register(text) TO anon, authenticated, service_role;

-- No student row with a blocked phone, whoever writes it.
CREATE OR REPLACE FUNCTION public.guard_blocked_student_phone() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.phone IS NOT DISTINCT FROM OLD.phone THEN
    RETURN NEW;
  END IF;
  IF public.is_phone_blocked(NEW.phone) THEN
    RAISE EXCEPTION '%', public.blocked_phone_message() USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_blocked_student_phone ON public.students;
CREATE TRIGGER trg_guard_blocked_student_phone BEFORE INSERT OR UPDATE OF phone ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_student_phone();

-- No new student sign-in account for a blocked phone either (its login is
-- <phone>@busak.app), so a refused sign-up leaves no account behind. Staff
-- accounts (another role) are not students and pass.
CREATE OR REPLACE FUNCTION public.guard_blocked_student_signup() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF COALESCE(NEW.raw_user_meta_data ->> 'role', 'student') = 'student'
     AND (public.is_phone_blocked(NEW.raw_user_meta_data ->> 'phone')
          OR public.is_phone_blocked(split_part(COALESCE(NEW.email, ''), '@', 1))) THEN
    RAISE EXCEPTION '%', public.blocked_phone_message() USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_blocked_student_signup ON auth.users;
CREATE TRIGGER trg_guard_blocked_student_signup BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.guard_blocked_student_signup();

-- Blocks the student's phone and stops their account signing in.
CREATE OR REPLACE FUNCTION public.block_student(p_student_id uuid, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_student public.students%ROWTYPE;
  v_phone text;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF public.is_super_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'حظر الطلاب متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_student FROM public.students WHERE id = p_student_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الطالب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF length(v_reason) > 300 THEN
    RAISE EXCEPTION 'سبب الحظر طويل جداً (300 حرف على الأكثر).' USING ERRCODE = '23514';
  END IF;
  v_phone := public.normalize_egyptian_phone(v_student.phone);

  INSERT INTO public.blocked_phones (phone, student_id, full_name, reason, blocked_by)
  VALUES (v_phone, v_student.id, v_student.full_name, v_reason, auth.uid())
  ON CONFLICT (phone) DO UPDATE
    SET student_id = EXCLUDED.student_id, full_name = EXCLUDED.full_name, reason = EXCLUDED.reason,
        blocked_at = now(), blocked_by = EXCLUDED.blocked_by;

  -- No sign-in from now on, and the sessions it has end.
  UPDATE auth.users SET banned_until = now() + interval '100 years' WHERE id = v_student.id;
  DELETE FROM auth.sessions WHERE user_id = v_student.id;

  RETURN jsonb_build_object('phone', v_phone, 'student_id', v_student.id, 'blocked', true);
END;
$$;
REVOKE ALL ON FUNCTION public.block_student(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.block_student(uuid, text) TO authenticated;

-- Unblocks a number, and lets the account that has it sign in again.
CREATE OR REPLACE FUNCTION public.unblock_phone(p_phone text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_phone text := public.normalize_egyptian_phone(COALESCE(p_phone, ''));
BEGIN
  IF public.is_super_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'حظر الطلاب متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.blocked_phones WHERE phone = v_phone;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  UPDATE auth.users SET banned_until = NULL
  WHERE id IN (SELECT s.id FROM public.students s WHERE public.normalize_egyptian_phone(s.phone) = v_phone);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.unblock_phone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unblock_phone(text) TO authenticated;

-- [{"phone", "student_id", "full_name", "reason", "blocked_at", "has_account"}], newest first.
CREATE OR REPLACE FUNCTION public.list_blocked_phones() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_super_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'حظر الطلاب متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'phone', b.phone, 'student_id', b.student_id, 'full_name', b.full_name, 'reason', b.reason,
             'blocked_at', b.blocked_at, 'has_account', b.student_id IS NOT NULL)
           ORDER BY b.blocked_at DESC)
    FROM public.blocked_phones b), '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.list_blocked_phones() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_blocked_phones() TO authenticated;

COMMIT;
