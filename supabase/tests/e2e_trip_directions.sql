-- End-to-end test: Going / Return trips for supervisors (manifest + check-in per
-- direction and trip) and the student company → line catalogue with the company
-- stored on the subscription (20261006000001). The manifest lists students by the
-- trip they chose for the day (20261022000001), so the student confirms the ride
-- first. ONE transaction, aborted at the end.
--   npx.cmd supabase@latest db query --project-ref <ref> --linked -f supabase/tests/e2e_trip_directions.sql
BEGIN;

CREATE TEMP TABLE e2e_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON e2e_results TO authenticated;
GRANT USAGE ON SEQUENCE e2e_results_n_seq TO authenticated;

CREATE TEMP TABLE e2e_ctx ON COMMIT DROP AS SELECT
  (SELECT id FROM public.admins WHERE role = 'super_admin' ORDER BY created_at LIMIT 1) AS super_id,
  (SELECT id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS cadmin_id,
  (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS company_id,
  NULL::uuid AS supervisor_id, NULL::uuid AS student_id, NULL::uuid AS qr, NULL::uuid AS uni,
  NULL::uuid AS line_id, NULL::uuid AS dep_trip, NULL::uuid AS ret_trip, NULL::uuid AS station2;
UPDATE e2e_ctx SET
  supervisor_id = (SELECT s.id FROM public.supervisors s JOIN auth.users u ON u.id = s.id
                   WHERE s.company_id = e2e_ctx.company_id AND s.is_active LIMIT 1),
  student_id = (SELECT id FROM public.students WHERE university_id IS NOT NULL ORDER BY created_at LIMIT 1);
UPDATE e2e_ctx SET qr = (SELECT qr_code_value FROM public.students WHERE id = e2e_ctx.student_id),
                   uni = (SELECT university_id FROM public.students WHERE id = e2e_ctx.student_id);
GRANT ALL ON e2e_ctx TO authenticated;
DELETE FROM public.subscriptions WHERE student_id = (SELECT student_id FROM e2e_ctx);

-- Company admin builds the line: Minyet El-Nasr → 3 stations → university, Going 07:00, Return 17:00.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_id uuid;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  v_id := public.save_line(jsonb_build_object(
    'name', 'E2E Going/Return', 'origin_name', 'منية النصر', 'destination_university_id', c.uni,
    'price_termly', 3000, 'price_yearly', 5500, 'price_daily', 40,
    'stations', jsonb_build_array(jsonb_build_object('name', 'S1'), jsonb_build_object('name', 'S2'), jsonb_build_object('name', 'S3')),
    'trips', jsonb_build_array(
      jsonb_build_object('direction', 'departure', 'start_time', '07:00', 'stops', jsonb_build_array(
        jsonb_build_object('station_index', 0, 'time', '07:10'), jsonb_build_object('station_index', 1, 'time', '07:20'),
        jsonb_build_object('station_index', 2, 'time', '07:30'))),
      jsonb_build_object('direction', 'return', 'start_time', '17:00', 'stops', jsonb_build_array(
        jsonb_build_object('station_index', 2, 'time', '17:15'), jsonb_build_object('station_index', 1, 'time', '17:25'),
        jsonb_build_object('station_index', 0, 'time', '17:35'))))));
  UPDATE e2e_ctx SET line_id = v_id,
    dep_trip = (SELECT id FROM public.line_trips WHERE line_id = v_id AND direction = 'departure'),
    ret_trip = (SELECT id FROM public.line_trips WHERE line_id = v_id AND direction = 'return'),
    station2 = (SELECT id FROM public.stations WHERE line_id = v_id AND order_index = 2);
END $$;
RESET ROLE;

-- Super admin assigns the supervisor to the new line.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', super_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
SELECT public.set_supervisor_lines(supervisor_id, ARRAY[line_id]) FROM e2e_ctx;
RESET ROLE;

-- ------------------------------------------------------------------ STUDENT
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', student_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_cat jsonb; v_line jsonb; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  v_cat := public.get_student_catalog();
  SELECT l INTO v_line FROM jsonb_array_elements(v_cat) co, jsonb_array_elements(co->'lines') l WHERE (l->>'id')::uuid = c.line_id;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('catalog: company → line with route, stations and times',
    v_line IS NOT NULL AND v_line->>'origin_name' = 'منية النصر' AND jsonb_array_length(v_line->'stations') = 3
      AND v_line->'departure_times' = '["07:00:00"]' AND v_line->'return_times' = '["17:00:00"]',
    v_line::text);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'catalog: only active companies with available lines',
    bool_and(EXISTS (SELECT 1 FROM public.companies x WHERE x.id = (co->>'id')::uuid AND x.is_active)
             AND jsonb_array_length(co->'lines') > 0), count(*)::text
    FROM jsonb_array_elements(v_cat) co;

  BEGIN
    INSERT INTO public.subscriptions(student_id, line_id, company_id, station_id, type, price, departure_trip_id, return_trip_id)
    VALUES (c.student_id, c.line_id, gen_random_uuid(), c.station2, 'daily', 0, c.dep_trip, c.ret_trip);
    v_ok := false;
  EXCEPTION WHEN check_violation OR foreign_key_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('subscription: company must match the line', v_ok, NULL);

  INSERT INTO public.subscriptions(student_id, line_id, station_id, type, price, departure_trip_id, return_trip_id)
  VALUES (c.student_id, c.line_id, c.station2, 'daily', 0, c.dep_trip, c.ret_trip);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'subscription: company + line + trips saved',
    company_id = c.company_id AND departure_time = '07:20' AND return_time = '17:25', company_id::text
    FROM public.subscriptions WHERE student_id = c.student_id AND line_id = c.line_id;
END $$;
RESET ROLE;

-- The daily subscription starts on the next ride day; make it valid today for the scan test.
SELECT set_config('request.jwt.claims', '', true);
UPDATE public.subscriptions SET start_date = public.cairo_today(), end_date = public.cairo_today()
WHERE student_id = (SELECT student_id FROM e2e_ctx) AND line_id = (SELECT line_id FROM e2e_ctx);
-- Open today's vote for the company whatever the time: 23:59:59 yesterday → 23:59:58 today.
UPDATE public.companies SET vote_opens_at = '23:59:59', vote_closes_at = '23:59:58', vote_reminder_minutes = 0,
  vote_reminder_off_weekdays = '{}', vote_reminder_off_dates = '{}'
WHERE id = (SELECT company_id FROM e2e_ctx);

-- ------------------------------------------------ SUPERVISOR, before the vote
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; m jsonb; st jsonb;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  IF c.supervisor_id IS NULL THEN RETURN; END IF;  -- reported below
  m := public.get_supervisor_trip_manifest(c.line_id, 'departure');
  SELECT s INTO st FROM jsonb_array_elements(m->'stations') s WHERE (s->>'id')::uuid = c.station2;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('going: before the vote the student is "not confirmed yet", on no station',
    jsonb_array_length(st->'students') = 0
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(m->'unconfirmed') u WHERE (u->>'id')::uuid = c.student_id),
    m->>'unconfirmed');
END $$;
RESET ROLE;

-- ------------------------------------------------ STUDENT confirms today's ride
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', student_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.toggle_student_daily_ride(public.cairo_today(), true, '07:20'::time, '17:25'::time, true);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('vote: the student confirms today, going 07:20 and back 17:25',
    (r->>'success')::boolean AND (r->>'is_riding')::boolean AND r->>'departure_time' = '07:20:00'
      AND r->>'return_time' = '17:25:00',
    r::text);
END $$;
RESET ROLE;

-- --------------------------------------------------------------- SUPERVISOR
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; m jsonb; r jsonb; st jsonb;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  IF c.supervisor_id IS NULL THEN
    INSERT INTO e2e_results(step, ok, detail) VALUES ('supervisor fixture', false, 'no supervisor'); RETURN;
  END IF;

  m := public.get_supervisor_trip_manifest(c.line_id, 'departure');
  SELECT s INTO st FROM jsonb_array_elements(m->'stations') s WHERE (s->>'id')::uuid = c.station2;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('going: manifest lists the student at their station, not checked in',
    (m->'trip'->>'id')::uuid = c.dep_trip AND jsonb_array_length(st->'students') = 1
      AND (st->'students'->0->>'id')::uuid = c.student_id AND (st->'students'->0->>'confirmed')::boolean
      AND st->'students'->0->>'chosen_time' = '07:20:00'
      AND st->'students'->0->>'checked_in_at' IS NULL AND st->>'stop_time' = '07:20:00'
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(m->'unconfirmed') u WHERE (u->>'id')::uuid = c.student_id),
    (SELECT string_agg(s->>'name', ' → ') FROM jsonb_array_elements(m->'stations') s));

  m := public.get_supervisor_trip_manifest(c.line_id, 'return');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('return: university → S3 → S2 → S1 (travel order), 17:00',
    (SELECT array_agg(s->>'name') FROM jsonb_array_elements(m->'stations') s) = ARRAY['S3', 'S2', 'S1']
      AND m->'trip'->>'start_time' = '17:00:00',
    (SELECT string_agg((s->>'name') || ' ' || (s->>'stop_time'), ' → ') FROM jsonb_array_elements(m->'stations') s));

  r := public.supervisor_check_in_student(c.qr, 'departure', c.dep_trip);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('going: QR check-in recorded on the departure trip',
    r->>'result' = 'checked_in' AND (r->>'trip_id')::uuid = c.dep_trip, r->>'result');

  m := public.get_supervisor_trip_manifest(c.line_id, 'return');
  SELECT s INTO st FROM jsonb_array_elements(m->'stations') s WHERE (s->>'id')::uuid = c.station2;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('return: still "not checked in" after the going check-in',
    jsonb_array_length(st->'students') = 1 AND st->'students'->0->>'chosen_time' = '17:25:00'
      AND st->'students'->0->>'checked_in_at' IS NULL, st::text);

  r := public.supervisor_check_in_student(c.qr, 'return', c.ret_trip);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('return: QR check-in recorded on the return trip',
    r->>'result' = 'checked_in' AND (r->>'trip_id')::uuid = c.ret_trip, r->>'result');
  r := public.supervisor_check_in_student(c.qr, 'return', c.ret_trip);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('return: a second return scan is a duplicate',
    r->>'result' = 'already_checked_in', r->>'result');

  m := public.get_supervisor_trip_manifest(c.line_id, 'return');
  SELECT s INTO st FROM jsonb_array_elements(m->'stations') s WHERE (s->>'id')::uuid = c.station2;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('return: manifest now shows the student checked in',
    st->'students'->0->>'checked_in_at' IS NOT NULL, NULL);

  INSERT INTO e2e_results(step, ok, detail) SELECT 'log: one check-in per direction, each on its trip',
    count(*) = 2 AND count(DISTINCT trip_id) = 2, count(*)::text
    FROM public.supervisor_scan_events WHERE student_id = c.student_id AND ride_date = public.cairo_today()
      AND result = 'checked_in' AND line_id = c.line_id;
END $$;
RESET ROLE;

DO $$ BEGIN
  RAISE EXCEPTION 'E2E_RESULTS %', (SELECT json_agg(json_build_object('n', n, 'step', step, 'ok', ok, 'detail', detail) ORDER BY n) FROM e2e_results);
END $$;
ROLLBACK;
