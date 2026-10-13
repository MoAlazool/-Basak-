-- The universities each of the supervisor's lines serves, so Trips can list
-- every one of them by its riders, those nobody from has confirmed included.
-- A line serves the universities set on it, its destination, and those its
-- trips are reserved for. Names as the riders' universities are named.
CREATE OR REPLACE FUNCTION public.get_my_line_universities()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH mine AS (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a),
  served AS (
    SELECT lu.line_id, lu.university_id FROM public.line_universities lu WHERE lu.line_id IN (SELECT line_id FROM mine)
    UNION
    SELECT l.id, l.destination_university_id FROM public.lines l
    WHERE l.id IN (SELECT line_id FROM mine) AND l.destination_university_id IS NOT NULL
    UNION
    SELECT t.line_id, t.university_id FROM public.line_trips t
    WHERE t.line_id IN (SELECT line_id FROM mine) AND t.university_id IS NOT NULL
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('line_id', s.line_id, 'name', u.name) ORDER BY s.line_id, u.name), '[]'::jsonb)
  FROM served s JOIN public.universities u ON u.id = s.university_id
$function$;

REVOKE ALL ON FUNCTION public.get_my_line_universities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_line_universities() TO authenticated;
