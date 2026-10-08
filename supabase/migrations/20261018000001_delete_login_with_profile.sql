-- ==============================================================================
-- Migration: 20261018000001_delete_login_with_profile.sql
-- Run AFTER 20261017000001. Safe to re-run.
--
-- Students and supervisors sign in as <phone>@busak.app. When only their
-- profile row was deleted (Table Editor, SQL, an older dashboard), the Auth
-- account stayed behind: useless, yet still holding the phone number, so
-- signing up with it again answered "phone already registered".
-- Deleting a students / supervisors row now deletes its Auth account too,
-- unless the same id still has another profile (student, supervisor or admin).
-- Deleting the Auth account first (the Edge Functions' way) cascades the row
-- as before; the trigger then finds no account left to delete.
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.delete_login_with_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.students WHERE id = OLD.id)
     OR EXISTS (SELECT 1 FROM public.supervisors WHERE id = OLD.id)
     OR EXISTS (SELECT 1 FROM public.admins WHERE id = OLD.id) THEN
    RETURN OLD;
  END IF;
  DELETE FROM auth.users WHERE id = OLD.id;
  RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_login_with_profile() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_delete_login_with_profile ON public.students;
CREATE TRIGGER trg_delete_login_with_profile AFTER DELETE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.delete_login_with_profile();

DROP TRIGGER IF EXISTS trg_delete_login_with_profile ON public.supervisors;
CREATE TRIGGER trg_delete_login_with_profile AFTER DELETE ON public.supervisors
  FOR EACH ROW EXECUTE FUNCTION public.delete_login_with_profile();

COMMIT;
