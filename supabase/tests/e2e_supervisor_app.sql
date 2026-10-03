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
  (SELECT id FROM public.lines WHERE company_id = (SELECT company_id FROM sup) AND is_active ORDER BY name LIMIT 1) AS own_line,
  (SELECT id FROM public.lines WHERE company_id <> (SELECT company_id FROM sup) LIMIT 1) AS foreign_line;
GRANT SELECT ON e2e_ctx TO authenticated;

-- A student outside the company for the "outside" case if none exists naturally.
-- (Created as postgres; rolled back with everything else.)

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; d jsonb; r jsonb; r2 jsonb; m jsonb; m0 jsonb; v_ok boolean; v_first text;
BEGIN
  SELECT * INTO c FROM e2e_ctx;

  m0 := public.get_supervisor_monthly_summary(NULL);  -- baseline: real scans already this month
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

  IF c.qr_ok IS NULL THEN
    -- Live data has no subscriber valid today on this company's lines; the scan
    -- flow is covered by e2e_trip_directions.sql with its own fixture.
    INSERT INTO e2e_results(step, ok, detail) VALUES ('scan steps', true, 'SKIPPED: no active subscriber today');
  ELSE
  r := public.supervisor_check_in_student(c.qr_ok, 'departure');
  v_first := r->>'result';  -- 'already_checked_in' if this student was really scanned today
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: active student is checked in',
    v_first IN ('checked_in', 'already_checked_in') AND r->'student'->>'full_name' IS NOT NULL, v_first);
  r2 := public.supervisor_check_in_student(c.qr_ok, 'departure');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: second scan is a duplicate, not a new check-in',
    r2->>'result' = 'already_checked_in' AND r2->>'checked_in_at' = r->>'checked_in_at', r2->>'result');
  -- One check-in per student, day and direction (20261006000001): the return trip is separate.
  r2 := public.supervisor_check_in_student(c.qr_ok, 'return');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: return trip is a separate check-in',
    r2->>'result' IN ('checked_in', 'already_checked_in') AND r2->>'direction' = 'return', r2->>'result');

  END IF;
  IF c.qr_outside IS NOT NULL THEN
    r := public.supervisor_check_in_student(c.qr_outside, 'departure');
    INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: student outside my lines is refused without details',
      r->>'result' = 'outside_assigned_lines' AND r->'student' IS NULL, r->>'result');
  END IF;
  r := public.supervisor_check_in_student(gen_random_uuid(), 'departure');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('scan: unknown QR is reported', r->>'result' = 'not_found', r->>'result');

  m := public.get_supervisor_monthly_summary(NULL);
  IF c.qr_ok IS NOT NULL THEN
  INSERT INTO e2e_results(step, ok, detail) VALUES ('monthly: counts move exactly with the new scans',
    (m->'totals'->>'checkins')::int - (m0->'totals'->>'checkins')::int = (v_first = 'checked_in')::int + (r2->>'result' = 'checked_in')::int
      AND (m->'totals'->>'scans')::int - (m0->'totals'->>'scans')::int >= 4,
    'before ' || (m0->'totals')::text || ' after ' || (m->'totals')::text);
  END IF;
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

-- Assignment (supervisor_lines via set_supervisor_lines) defines exactly the supervisor's lines.
ALTER TABLE e2e_ctx ADD COLUMN super_id uuid;
UPDATE e2e_ctx SET super_id = (SELECT id FROM public.admins WHERE role = 'super_admin' ORDER BY created_at LIMIT 1);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', super_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
SELECT public.set_supervisor_lines((SELECT supervisor_id FROM e2e_ctx), ARRAY[(SELECT own_line FROM e2e_ctx)]);
RESET ROLE;
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
DECLARE v_ok boolean; v_company uuid;
BEGIN
  IF (SELECT foreign_line FROM e2e_ctx) IS NULL THEN
    INSERT INTO public.companies(name, is_active) VALUES ('E2E other company', true) RETURNING id INTO v_company;
    INSERT INTO public.lines(company_id, name, origin_name, price_termly, price_yearly, price_daily, is_active)
    VALUES (v_company, 'E2E foreign line', 'X', 1, 1, 1, true);
    UPDATE e2e_ctx SET foreign_line = (SELECT id FROM public.lines WHERE name = 'E2E foreign line');
  END IF;
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
