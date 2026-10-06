-- Query performance for the company-first model. Additive: indexes, and the three
-- policies created before the isolation migration moved to per-statement helpers.

-- Lists and counts are always "of one company".
CREATE INDEX IF NOT EXISTS idx_lines_company ON public.lines (company_id);
CREATE INDEX IF NOT EXISTS idx_supervisors_company ON public.supervisors (company_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_company_status ON public.subscriptions (company_id, status);
CREATE INDEX IF NOT EXISTS idx_receipts_company_pending ON public.receipts (company_id, created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_company_students_active ON public.company_students (company_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_scan_events_company_date ON public.supervisor_scan_events (company_id, ride_date);
CREATE INDEX IF NOT EXISTS idx_admins_company ON public.admins (company_id);
DROP INDEX IF EXISTS public.idx_subscriptions_company;         -- covered by (company_id, status)
DROP INDEX IF EXISTS public.idx_supervisor_scan_events_company; -- covered by (company_id, ride_date)

-- Searching students by part of a name or phone.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE INDEX IF NOT EXISTS idx_students_name_trgm ON public.students USING gin (full_name extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_students_phone_trgm ON public.students USING gin (phone extensions.gin_trgm_ops);

DROP POLICY IF EXISTS company_students_read ON public.company_students;
CREATE POLICY company_students_read ON public.company_students FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid())
      OR (SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()));

DROP POLICY IF EXISTS company_terms_read ON public.company_terms;
CREATE POLICY company_terms_read ON public.company_terms FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()));

DROP POLICY IF EXISTS report_resets_read ON public.report_resets;
CREATE POLICY report_resets_read ON public.report_resets FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()));
