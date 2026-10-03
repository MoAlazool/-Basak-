-- End-to-end test for the Line + Stations + Trips redesign (20261005000001).
-- Runs in ONE transaction aborted at the end (deliberate exception): nothing persists.
--   npx.cmd supabase@latest db query --project-ref <ref> --linked -f supabase/tests/e2e_line_trips.sql
BEGIN;

CREATE TEMP TABLE e2e_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON e2e_results TO authenticated;
GRANT USAGE ON SEQUENCE e2e_results_n_seq TO authenticated;

CREATE TEMP TABLE e2e_ctx ON COMMIT DROP AS SELECT
  (SELECT id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS cadmin_id,
  (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS company_id,
  (SELECT id FROM public.companies WHERE id <> (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) LIMIT 1) AS other_company,
  (SELECT id FROM public.universities WHERE name LIKE '%الدلتا%' LIMIT 1) AS u_delta,
  (SELECT id FROM public.universities WHERE name NOT LIKE '%الدلتا%' ORDER BY name LIMIT 1) AS u_other,
  NULL::uuid AS line_id, NULL::uuid AS student_delta, NULL::uuid AS student_other;
UPDATE e2e_ctx SET
  student_delta = (SELECT id FROM public.students WHERE university_id = e2e_ctx.u_delta LIMIT 1),
  student_other = (SELECT id FROM public.students WHERE university_id IS DISTINCT FROM e2e_ctx.u_delta AND university_id IS NOT NULL LIMIT 1);
UPDATE e2e_ctx SET u_other = (SELECT university_id FROM public.students WHERE id = e2e_ctx.student_other);
GRANT ALL ON e2e_ctx TO authenticated;
-- Free the students' subscription slots for this test (rolled back).
DELETE FROM public.subscriptions WHERE student_id IN (SELECT student_delta FROM e2e_ctx UNION SELECT student_other FROM e2e_ctx);

-- ------------------------------------------------------------- COMPANY ADMIN
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_id uuid; v_ok boolean; v_msg text; v_line jsonb;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  -- Minyet El-Nasr → 3 stations → Delta University, built in ONE call.
  v_line := jsonb_build_object(
    'name', 'E2E منية النصر - الدلتا', 'origin_name', 'منية النصر', 'destination_university_id', c.u_delta,
    'price_termly', 3000, 'price_yearly', 5500, 'price_daily', 40,
    'stations', jsonb_build_array(jsonb_build_object('name', 'محطة 1'), jsonb_build_object('name', 'محطة 2'),
                                  jsonb_build_object('name', 'محطة 3')),
    'trips', jsonb_build_array(
      jsonb_build_object('direction', 'departure', 'label', 'أول رحلة', 'start_time', '07:00', 'arrival_time', '07:50',
        'university_id', c.u_delta, 'stops', jsonb_build_array(
          jsonb_build_object('station_index', 0, 'time', '07:10'), jsonb_build_object('station_index', 1, 'time', '07:20'),
          jsonb_build_object('station_index', 2, 'time', '07:30'))),
      jsonb_build_object('direction', 'departure', 'start_time', '08:00', 'stops', jsonb_build_array(
          jsonb_build_object('station_index', 0, 'time', '08:10'), jsonb_build_object('station_index', 2, 'time', '08:30'))),
      jsonb_build_object('direction', 'return', 'start_time', '14:00', 'stops', jsonb_build_array(
          jsonb_build_object('station_index', 2, 'time', '14:15'), jsonb_build_object('station_index', 1, 'time', '14:25'),
          jsonb_build_object('station_index', 0, 'time', '14:35')))));
  v_id := public.save_line(v_line);
  UPDATE e2e_ctx SET line_id = v_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'create: line + stations + trips + stop times in one call',
    (SELECT count(*) FROM public.stations WHERE line_id = v_id) = 3
    AND (SELECT count(*) FROM public.line_trips WHERE line_id = v_id) = 3
    AND (SELECT count(*) FROM public.line_trip_stops s JOIN public.line_trips t ON t.id = s.trip_id WHERE t.line_id = v_id) = 8
    AND (SELECT company_id FROM public.lines WHERE id = v_id) = c.company_id,
    (SELECT string_agg(name || '#' || order_index, ', ' ORDER BY order_index) FROM public.stations WHERE line_id = v_id);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'create: legacy station time lists synced from trips',
    departure_times = ARRAY['07:10'::time, '08:10'] AND return_times = ARRAY['14:35'::time], departure_times::text
    FROM public.stations WHERE line_id = v_id AND order_index = 1;

  -- Validation
  BEGIN
    PERFORM public.save_line(jsonb_set(v_line, '{trips,0,stops,1,time}', '"07:05"'));
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('validate: stop times must follow route order', v_ok, v_msg);
  BEGIN
    PERFORM public.save_line(v_line || '{"stations": []}');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('validate: a line needs stations', v_ok, v_msg);
  BEGIN
    PERFORM public.save_line(v_line || jsonb_build_object('trips', '[]'::jsonb));
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('validate: a line needs a departure trip', v_ok, v_msg);
  BEGIN
    PERFORM public.save_line(v_line || jsonb_build_object('origin_name', ''));
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('validate: start location is required', v_ok, v_msg);

  -- Company admin cannot create for another company (company_id is forced) nor edit foreign lines.
  v_id := public.save_line(v_line || jsonb_build_object('name', 'E2E forced', 'company_id', c.other_company));
  INSERT INTO e2e_results(step, ok, detail) SELECT 'perm: company admin always creates in own company',
    company_id = c.company_id, company_id::text FROM public.lines WHERE id = v_id;
  PERFORM public.delete_line(v_id);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'delete: an unused line is deleted permanently',
    NOT EXISTS (SELECT 1 FROM public.lines WHERE id = v_id), NULL;
END $$;
RESET ROLE;

-- Foreign line check needs the id of a line the company admin cannot see.
DO $$
DECLARE c record; v_foreign uuid; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  SELECT id INTO v_foreign FROM public.lines WHERE company_id <> c.company_id LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c.cadmin_id, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.set_line_active(v_foreign, false); v_ok := false;
  EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('perm: cannot disable another company''s line', v_ok, NULL);
  BEGIN
    PERFORM public.delete_line(v_foreign); v_ok := false;
  EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('perm: cannot delete another company''s line', v_ok, NULL);
END $$;

-- -------------------------------------------------------- STUDENT (Delta)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', student_delta, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_trip uuid; v_ret uuid; v_station uuid;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student (Delta): sees Delta trip + open trips (3)',
    count(*) = 3, count(*)::text FROM public.line_trips WHERE line_id = c.line_id;
  SELECT id INTO v_station FROM public.stations WHERE line_id = c.line_id AND order_index = 2;
  SELECT id INTO v_trip FROM public.line_trips WHERE line_id = c.line_id AND start_time = '07:00';
  SELECT id INTO v_ret FROM public.line_trips WHERE line_id = c.line_id AND direction = 'return';
  INSERT INTO public.subscriptions(student_id, line_id, station_id, type, price, departure_trip_id, return_trip_id)
  VALUES (c.student_delta, c.line_id, v_station, 'daily', 0, v_trip, v_ret);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: subscription times = stop times at the station',
    departure_time = '07:20' AND return_time = '14:25' AND departure_trip_id = v_trip,
    departure_time || ' / ' || return_time
    FROM public.subscriptions WHERE student_id = c.student_delta AND line_id = c.line_id;
END $$;
RESET ROLE;

-- -------------------------------------------------------- STUDENT (other university)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', student_other, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_trip uuid; v_station uuid; v_ok boolean; v_msg text;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  IF c.student_other IS NULL THEN RETURN; END IF;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student (other uni): Delta-only trip is hidden',
    count(*) = 2 AND bool_and(university_id IS NULL), count(*)::text FROM public.line_trips WHERE line_id = c.line_id;
  -- The Delta trip id, looked up as postgres via the ctx-free path: try station 2 at 07:20.
  SELECT id INTO v_station FROM public.stations WHERE line_id = c.line_id AND order_index = 2;
  BEGIN
    INSERT INTO public.subscriptions(student_id, line_id, station_id, type, price, departure_time)
    VALUES (c.student_other, c.line_id, v_station, 'daily', 0, '07:20');
    v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student (other uni): cannot ride the Delta-only trip', v_ok, v_msg);
END $$;
RESET ROLE;

-- ------------------------------------------------------------ EDIT the line
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_line jsonb; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_t1 uuid; v_r uuid; v_ok boolean; v_msg text;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  SELECT id INTO v_s1 FROM public.stations WHERE line_id = c.line_id AND order_index = 1;
  SELECT id INTO v_s2 FROM public.stations WHERE line_id = c.line_id AND order_index = 2;
  SELECT id INTO v_s3 FROM public.stations WHERE line_id = c.line_id AND order_index = 3;
  SELECT id INTO v_t1 FROM public.line_trips WHERE line_id = c.line_id AND start_time = '07:00';
  SELECT id INTO v_r FROM public.line_trips WHERE line_id = c.line_id AND direction = 'return';
  -- Rename, drop station 3, move the 07:00 trip 5 minutes later, drop the 08:00 trip.
  v_line := jsonb_build_object('id', c.line_id, 'name', 'E2E line edited', 'origin_name', 'منية النصر',
    'destination_university_id', c.u_delta, 'price_termly', 3000, 'price_yearly', 5500, 'price_daily', 40,
    'stations', jsonb_build_array(jsonb_build_object('id', v_s1, 'name', 'محطة 1'), jsonb_build_object('id', v_s2, 'name', 'محطة 2')),
    'trips', jsonb_build_array(
      jsonb_build_object('id', v_t1, 'direction', 'departure', 'start_time', '07:05', 'university_id', c.u_delta,
        'stops', jsonb_build_array(jsonb_build_object('station_index', 0, 'time', '07:15'), jsonb_build_object('station_index', 1, 'time', '07:25'))),
      jsonb_build_object('id', v_r, 'direction', 'return', 'start_time', '14:00',
        'stops', jsonb_build_array(jsonb_build_object('station_index', 1, 'time', '14:25'), jsonb_build_object('station_index', 0, 'time', '14:35')))));
  PERFORM public.save_line(v_line);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'edit: station ids kept, removed station gone, order intact',
    (SELECT array_agg(id ORDER BY order_index) FROM public.stations WHERE line_id = c.line_id AND is_active) = ARRAY[v_s1, v_s2]
    AND NOT EXISTS (SELECT 1 FROM public.stations WHERE id = v_s3),
    (SELECT string_agg(name, ', ' ORDER BY order_index) FROM public.stations WHERE line_id = c.line_id);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'edit: subscriber follows the new stop time',
    departure_time = '07:25', departure_time::text FROM public.subscriptions WHERE student_id = c.student_delta AND line_id = c.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'edit: unused removed trip deleted',
    (SELECT count(*) FROM public.line_trips WHERE line_id = c.line_id) = 2, (SELECT count(*) FROM public.line_trips WHERE line_id = c.line_id)::text;

  -- Deleting a line with a subscription is refused; disabling keeps everything.
  BEGIN
    PERFORM public.delete_line(c.line_id); v_ok := false;
  EXCEPTION WHEN foreign_key_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('delete: refused for a line with subscriptions', v_ok, v_msg);
  PERFORM public.set_line_active(c.line_id, false);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'disable: line kept with its data',
    NOT is_active AND (SELECT count(*) FROM public.subscriptions WHERE line_id = c.line_id) = 1, NULL
    FROM public.lines WHERE id = c.line_id;
END $$;
RESET ROLE;

-- Disabled line: hidden from students, no new subscriptions, no new supervisor assignments.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', student_other, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'disable: line no longer offered to students',
    NOT EXISTS (SELECT 1 FROM public.get_student_line_options() WHERE line_id = c.line_id)
    AND NOT EXISTS (SELECT 1 FROM public.lines WHERE id = c.line_id), NULL;
END $$;
RESET ROLE;
DO $$
DECLARE c record; v_sup uuid; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  SELECT id INTO v_sup FROM public.supervisors WHERE company_id = c.company_id LIMIT 1;
  IF v_sup IS NULL THEN RETURN; END IF;
  BEGIN
    INSERT INTO public.supervisor_lines(supervisor_id, line_id) VALUES (v_sup, c.line_id); v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('disable: no new supervisor assignment', v_ok, NULL);
END $$;

DO $$ BEGIN
  RAISE EXCEPTION 'E2E_RESULTS %', (SELECT json_agg(json_build_object('n', n, 'step', step, 'ok', ok, 'detail', detail) ORDER BY n) FROM e2e_results);
END $$;
ROLLBACK;
