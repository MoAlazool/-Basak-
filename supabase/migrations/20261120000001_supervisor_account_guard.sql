-- ==============================================================================
-- Migration: 20261120000001_supervisor_account_guard.sql
-- Run AFTER 20261119000006. Safe to re-run.
--
-- Found by a security test: a company admin could write a supervisors row
-- directly (the supervisors_company_manage policy allows it) whose id was an
-- existing student's account, turning that student into a staff account.
-- A supervisor is made by the admin-create-supervisor function with a new
-- sign-in account; no row may take an account that is already a student's or
-- an admin's, whoever writes it. The dashboard never changes a supervisor's id.
-- Also: term_recap_assert_term gets a fixed search_path (advisor
-- function_search_path_mutable).
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.guard_supervisor_account() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.id IS NOT DISTINCT FROM OLD.id THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM public.students WHERE id = NEW.id)
     OR EXISTS (SELECT 1 FROM public.admins WHERE id = NEW.id) THEN
    RAISE EXCEPTION 'هذا الحساب لطالب أو لمسؤول، ولا يصلح حساباً لمشرف. أضف المشرف من صفحة المشرفين.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_supervisor_account() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_supervisor_account ON public.supervisors;
CREATE TRIGGER trg_guard_supervisor_account BEFORE INSERT OR UPDATE OF id ON public.supervisors
  FOR EACH ROW EXECUTE FUNCTION public.guard_supervisor_account();

ALTER FUNCTION public.term_recap_assert_term(integer, text) SET search_path = public;

COMMIT;
