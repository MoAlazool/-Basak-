-- ==============================================================================
-- Migration: 20261108000001_boarded_rides_count.sql
-- Run AFTER 20261107000001. Safe to re-run. Additive: one new function.
--
-- The app asks for a store rating after a student's fifth boarded ride. A
-- boarded ride is a successful check-in by a supervisor (going and return are
-- one each). Students cannot read the scan log, and still cannot: this answers
-- one number, the caller's own. Anyone who is not a student gets 0.
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_boarded_rides_count() RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::integer
  FROM public.supervisor_scan_events e
  WHERE e.student_id = auth.uid() AND e.result = 'checked_in'
$$;
REVOKE ALL ON FUNCTION public.get_my_boarded_rides_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_boarded_rides_count() TO authenticated;

COMMIT;
