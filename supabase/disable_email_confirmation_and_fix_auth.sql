-- ══════════════════════════════════════════════════════════════════
-- AUTO-CONFIRM USERS IN SUPABASE AUTH
-- Fixes "email rate limit exceeded" (Error 429)
-- Ensures Supabase NEVER requires email verification for @busak.app
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.auto_confirm_new_user()
RETURNS trigger AS $$
BEGIN
  NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, now());
  NEW.confirmed_at := COALESCE(NEW.confirmed_at, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_confirm_new_user ON auth.users;
CREATE TRIGGER trg_auto_confirm_new_user
  BEFORE INSERT OR UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_confirm_new_user();

-- Confirm all existing users in auth.users
UPDATE auth.users
SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
    confirmed_at = COALESCE(confirmed_at, now())
WHERE email_confirmed_at IS NULL;

-- Ensure public.students allows INSERT by anyone (anon and authenticated)
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_rw_students" ON public.students;
DROP POLICY IF EXISTS "anon_r_students" ON public.students;
DROP POLICY IF EXISTS "auth_own_student" ON public.students;
DROP POLICY IF EXISTS "Student register profile" ON public.students;

CREATE POLICY "anon_rw_students" ON public.students
    FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "auth_rw_students" ON public.students
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

SELECT 'Auto-confirm trigger active and student registration open ✓' AS result;
