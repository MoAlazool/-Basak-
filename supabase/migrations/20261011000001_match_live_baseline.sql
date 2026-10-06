-- Brings a database built from these migrations in line with the live project,
-- which had a few objects created or dropped outside the migrations. Every
-- statement is a no-op on the live project.

-- Sign-ups use a phone-derived e-mail that cannot be confirmed by mail.
CREATE OR REPLACE FUNCTION public.auto_confirm_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, now());
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_auto_confirm_new_user ON auth.users;
CREATE TRIGGER trg_auto_confirm_new_user BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.auto_confirm_new_user();

-- A company admin may only add a subscription for a student already linked to
-- the company, and nobody may move a subscription to another student.
CREATE OR REPLACE FUNCTION public.guard_subscription_student_scope() RETURNS trigger
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

ALTER FUNCTION public.is_student() SET search_path = public;
ALTER FUNCTION public.is_supervisor() SET search_path = public;

-- The 1 pm reset was replaced by the vote window; nothing calls it any more.
DROP FUNCTION IF EXISTS public.reset_daily_rides_at_1pm();
