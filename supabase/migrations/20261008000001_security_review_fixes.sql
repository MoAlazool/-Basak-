-- ==============================================================================
-- Migration: 20261008000001_security_review_fixes.sql
-- Run AFTER 20261007000002. Safe to re-run.
--
-- 1. Company admins could attach a subscription on one of their lines to ANY
--    student id (INSERT, or UPDATE of student_id on one of their own rows).
--    That subscription is what scopes a student to a company, so it unlocked
--    reading / editing / deleting that student and issuing password-reset
--    codes for them (account takeover). Company admins may now only add
--    subscriptions for students already linked to their company, and nobody
--    but the Super Admin or the service role can move a subscription to
--    another student. New students are created by the admin-create-student
--    Edge Function (service role), which is unaffected.
-- 2. reset_daily_rides_at_1pm(): leftover of the old 1 PM rule, no longer
--    called by anything (voting is 4 PM - 6 AM, enforced in
--    toggle_student_daily_ride). Its Edge Function "daily-reset" had no
--    caller check, so both are removed.
-- 3. Functions without a fixed search_path (Supabase security advisor):
--    is_student(), is_supervisor(), prevent_student_profile_update(),
--    normalize_egyptian_phone() and the legacy auto_confirm_new_user().
-- 4. Storage policy "Students read receipts storage" (created by a legacy SQL
--    script, not by any migration, but present on the live project) let every
--    supervisor and every company admin read EVERY bank receipt image in the
--    bucket, across companies. Policies are OR-ed, so the scoped policies of
--    20261004000001 did not help. Owners, the Super Admin and the student's
--    own company admin keep access through "Scoped receipt image access".
-- ==============================================================================
BEGIN;

-- 1. ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_subscription_student_scope()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Service role / SQL editor and the Super Admin keep full control.
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
      RAISE EXCEPTION 'لا يمكن نقل الاشتراك إلى طالب آخر.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF public.is_company_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = NEW.student_id
      AND l.company_id = public.current_admin_company_id()
  ) THEN
    RAISE EXCEPTION 'هذا الطالب غير مرتبط بشركتك. أضف الطلاب الجدد من صفحة الطلاب.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_subscription_student_scope() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_subscription_student_scope ON public.subscriptions;
CREATE TRIGGER trg_guard_subscription_student_scope
BEFORE INSERT OR UPDATE OF student_id ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.guard_subscription_student_scope();

-- 2. ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.reset_daily_rides_at_1pm();

-- 3. ---------------------------------------------------------------------------
ALTER FUNCTION public.is_student() SET search_path = public;
ALTER FUNCTION public.is_supervisor() SET search_path = public;
ALTER FUNCTION public.prevent_student_profile_update() SET search_path = public;
ALTER FUNCTION public.normalize_egyptian_phone(text) SET search_path = public;
DO $$ BEGIN
  -- Created on the live project by a legacy script (auto-confirms phone sign-ups).
  IF to_regprocedure('public.auto_confirm_new_user()') IS NOT NULL THEN
    ALTER FUNCTION public.auto_confirm_new_user() SET search_path = public;
  END IF;
END $$;

-- 4. ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Students read receipts storage" ON storage.objects;

COMMIT;
