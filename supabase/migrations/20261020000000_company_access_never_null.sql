-- ==============================================================================
-- Migration: 20261020000000_company_access_never_null.sql
-- Run AFTER 20261019000001. Safe to re-run.
--
-- Security fix. For anyone who is not an admin of the company,
-- can_manage_company() returned NULL instead of false (TRUE-less OR with a NULL
-- company comparison), and has_company_access() likewise. Policies treat NULL
-- as "no", but functions that check `IF NOT public.can_manage_company(...)`
-- let NULL through, so any signed-in account (a student too) could change or
-- read another company's data: save_line, delete_line, set_line_active (via
-- can_manage_line_company), set_annual_subscription, set_daily_subscription,
-- save_company_terms, admin_reset_reports, company_overview,
-- admin_subscription_report, company_remove_student, request_student_correction.
-- Both functions now always answer true or false (checked on the live database
-- in a rolled-back transaction: a student could flip a company's daily switch
-- before this, and is refused after it; admins and supervisors keep their access).
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.can_manage_company(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.is_super_admin()
      OR (p_company_id IS NOT NULL AND p_company_id = public.current_admin_company_id()
          AND public.company_is_active(p_company_id)), false)
$$;

CREATE OR REPLACE FUNCTION public.has_company_access(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.can_manage_company(p_company_id)
      OR (p_company_id IS NOT NULL AND p_company_id = public.current_supervisor_company_id()
          AND public.company_is_active(p_company_id)), false)
$$;

COMMIT;
