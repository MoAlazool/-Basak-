-- ==============================================================================
-- Migration: 20261111000001_my_line_supervisors.sql
-- Run AFTER 20261110000001. Safe to re-run. Additive: one new function.
--
-- Every supervisor of a student's line, not only its primary contact. The app
-- read the supervisor through lines.supervisor_id, which holds ONE supervisor
-- (the earliest assigned), so a line with two supervisors showed its students
-- only the first. Students cannot read supervisor_lines, so this answers it
-- for them, for the lines of their active subscriptions only (the same rule
-- as is_my_supervisor, which already lets them read these supervisors' rows
-- and photos). Active supervisors only; per line the primary contact first,
-- then in the order they were assigned.
-- ==============================================================================
BEGIN;

-- [{"line_id", "id", "full_name", "phone", "profile_image_url"}, …]
CREATE OR REPLACE FUNCTION public.get_my_line_supervisors() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'line_id', x.line_id, 'id', x.id, 'full_name', x.full_name, 'phone', x.phone,
           'profile_image_url', x.profile_image_url)
         ORDER BY x.line_id, x.is_primary DESC, x.assigned_at, x.id), '[]'::jsonb)
  FROM (
    SELECT DISTINCT sl.line_id, s.id, s.full_name, s.phone, s.profile_image_url,
           COALESCE(l.supervisor_id = s.id, false) AS is_primary, sl.assigned_at
    FROM public.subscriptions sub
    JOIN public.supervisor_lines sl ON sl.line_id = sub.line_id
    JOIN public.supervisors s ON s.id = sl.supervisor_id AND s.is_active
    JOIN public.lines l ON l.id = sl.line_id
    WHERE auth.uid() IS NOT NULL AND sub.student_id = auth.uid() AND sub.status = 'active'
  ) x
$$;
REVOKE ALL ON FUNCTION public.get_my_line_supervisors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_line_supervisors() TO authenticated;

COMMIT;
