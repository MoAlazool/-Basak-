-- End-to-end test for the supervisor app RPCs (dashboard, QR check-in, monthly
-- summary) and supervisor scoping. Runs in ONE transaction aborted at the end.
--   npx.cmd supabase@latest db query --project-ref <ref> --linked -f supabase/tests/e2e_supervisor_app.sql
BEGIN;

CREATE TEMP TABLE e2e_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON e2e_results TO authenticated;
GRANT USAGE ON SEQUENCE e2e_results_n_seq TO authenticated;

CREATE TEMP TABLE e2e_ctx ON COMMIT DROP AS
WITH sup AS (
  SELECT s.id, s.company_id FROM public.supervisors s JOIN auth.users u ON u.id = s.id WHERE s.is_active LIMIT 1
)
SELECT
  (SELECT id FROM sup) AS supervisor_id,
  (SELECT company_id FROM sup) AS company_id,
  -- a student with an active subscription on the supervisor's company lines
  (SELECT st.qr_code_value FROM public.subscriptions sub
     JOIN public.lines l ON l.id = sub.line_id JOIN public.students st ON st.id = sub.student_id
     WHERE l.company_id = (SELECT company_id FROM sup) AND sub.status = 'active'
       AND (sub.end_date IS NULL OR sub.end_date >= public.cairo_today())
     LIMIT 1) AS qr_ok,
  -- a student with no subscription on the supervisor's lines (other company / none)
  (SELECT st.qr_code_value FROM public.students st
     WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
                       WHERE sub.student_id = st.id AND l.company_id = (SELECT company_id FROM sup))
     LIMIT 1) AS qr_outside,
  (SELECT id FROM public.lines WHERE company_id = (SELECT company_id FROM sup) ORDER BY name LIMIT 1) AS own_line,
  (SELECT id FROM public.lines WHERE company_id <> (SELECT company_id FROM sup) LIMIT 1) AS foreign_line;
GRANT SELECT ON e2e_ctx TO authenticated;

-- A student outside the company for the "outside" case if none exists naturally.
-- (Created as postgres; rolled back with everything else.)

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; d jsonb; r jsonb; r2 jsonb; m jsonb; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;

  d := public.get_supervisor_dashboard();
  INSERT INTO e2e_results(step, ok, detail) VALUES ('dashboard: profile is the caller with company',
    (d->'profile'->>'id')::uuid = c.supervisor_id AND d->'profile'->>'company_name' IS NOT NULL, d->'profile'->>'company_name');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('dashboard: lines all belong to own company',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(d->'lines') x JOIN public.lines l ON l.id = (x->>'id')::uuid
                WHERE l.company_id <> c.company_id) AND jsonb_array_length(d->'lines') > 0,
    jsonb_array_length(d->'lines')::text);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('dashboard: registered total = sum of station counts',
    (d->'totals'->>'registered_students')::int = (
      SELECT COALESCE(sum((s->>'registered_students')::int), 0)
      FROM jsonb_array_elements(d->'lines') l, jsonb_array_elements(l->'stations') s),
    d->'totals'->>'registered_students');

  r := public.supervisor_check_in_student(c.qr_ok, 'departure');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: active student is checked in',
    r->>'result' = 'checked_in' AND r->'student'->>'full_name' IS NOT NULL, r->>'result');
  r2 := public.supervisor_check_in_student(c.qr_ok, 'departure');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: second scan is a duplicate, not a new check-in',
    r2->>'result' = 'already_checked_in' AND r2->>'checked_in_at' = r->>'checked_in_at', r2->>'result');
  r2 := public.supervisor_check_in_student(c.qr_ok, 'return');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: return trip is a separate check-in', r2->>'result' = 'checked_in', r2->>'result');

  IF c.qr_outside IS NOT NULL THEN
    r := public.supervisor_check_in_student(c.qr_outside, 'departure');
    INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: student outside my lines is refused without details',
      r->>'result' = 'outside_assigned_lines' AND r->'student' IS NULL, r->>'result');
  END IF;
  r := public.supervisor_check_in_student(gen_random_uuid(), 'departure');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: unknown QR is reported', r->>'result' = 'not_found', r->>'result');

  m := public.get_supervisor_monthly_summary(NULL);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('monthly: counts come from the real scan log',
    (m->'totals'->>'checkins')::int = 2 AND (m->'totals'->>'duplicate_scans')::int = 1
      AND (m->'totals'->>'scans')::int >= 4 AND (m->'totals'->>'unique_students')::int = 1,
    (m->'totals')::text);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('monthly: one row per day up to today',
    jsonb_array_length(m->'days') = extract(day FROM public.cairo_today())::int, jsonb_array_length(m->'days')::text);

  INSERT INTO e2e_results(step, ok, detail) SELECT 'scan log: supervisor reads only own events',
    bool_and(supervisor_id = c.supervisor_id), count(*)::text FROM public.supervisor_scan_events;

  BEGIN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result)
      VALUES (c.supervisor_id, public.cairo_today(), 'departure', 'checked_in');
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan log: no direct writes (RPC only)', v_ok, NULL);
END $$;
RESET ROLE;

-- Direct assignment narrows the supervisor to that line only.
UPDATE public.lines SET supervisor_id = (SELECT supervisor_id FROM e2e_ctx) WHERE id = (SELECT own_line FROM e2e_ctx);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'assignment: direct line assignment narrows scope',
    count(*) = 1 AND bool_and(line_id = c.own_line), count(*)::text FROM public.get_supervisor_assigned_line_ids();
END $$;
RESET ROLE;

DO $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    UPDATE public.lines SET supervisor_id = (SELECT supervisor_id FROM e2e_ctx) WHERE id = (SELECT foreign_line FROM e2e_ctx);
    v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('assignment: cannot assign a supervisor to another company line', v_ok, NULL);
END $$;

-- Students and admins cannot use the supervisor RPCs.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id FROM public.students LIMIT 1), 'role', 'authenticated')::text, true);
DO $$
DECLARE v_ok boolean;
BEGIN
  BEGIN PERFORM public.supervisor_check_in_student(gen_random_uuid(), 'departure'); v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true; END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student: cannot check anyone in', v_ok, NULL);
  BEGIN PERFORM public.get_supervisor_dashboard(); v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true; END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student: cannot open the supervisor dashboard', v_ok, NULL);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: cannot read scan logs', count(*) = 0, count(*)::text
    FROM public.supervisor_scan_events;
END $$;
RESET ROLE;

DO $$ BEGIN
  RAISE EXCEPTION 'E2E_RESULTS %', (SELECT json_agg(json_build_object('n', n, 'step', step, 'ok', ok, 'detail', detail) ORDER BY n) FROM e2e_results);
END $$;
ROLLBACK;
