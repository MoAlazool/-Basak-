-- End-to-end test of 20261022000001_rides_by_chosen_time: supervisors see riders
-- by the trip they chose FOR THE DAY. Run by run_local.sh after every migration;
-- builds its own company, line and students in ONE transaction, rolled back at
-- the end. Every supervisor step runs with the role + JWT claims PostgREST uses.
--
-- Line "E2E Choices": S1 → S2 → S3 → university.
--   Going   D1 07:00 (all)          S1 07:10, S2 07:20, S3 07:30
--           D2 08:00 (Uni Two only) S1 08:10, S2 08:20, S3 08:30
--           D3 06:00 (inactive)     S1 07:10
--   Return  R1 15:00 (all)          S3 15:15, S2 15:25, S1 15:35
--           R2 17:00 (all)          S3 17:15, S2 17:25, S1 17:35
-- Today's votes (A, B, H = Uni One; C, D, F = Uni Two; E = Uni One):
--   A  S1  07:10 → D1 (not the inactive D3), back 15:35 → R1
--   B  S2  07:20 → D1, returning with no time saved → their subscription's R2
--   C  S2  08:20 → D2, back 15:25 → R1
--   D  S3  07:30 → D1, not returning
--   H  S2  08:20, but D2 is closed to Uni One → their subscription's D1
--   E  S3  no vote at all (unconfirmed)
--   F  S1  voted "not riding" (neither riding nor unconfirmed)
-- Tomorrow: only A, 07:10 → D1.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\o /dev/null
BEGIN;

CREATE SCHEMA rc;
GRANT USAGE ON SCHEMA rc TO authenticated;
CREATE TABLE rc.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE FUNCTION rc.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO rc.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION rc.login(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$;
-- One trip_times group of the dashboard.
CREATE FUNCTION rc.grp(d jsonb, p_date date, p_direction text, p_trip uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT g FROM jsonb_array_elements(d->'trip_times') g
  WHERE (g->>'ride_date')::date = p_date AND g->>'direction' = p_direction AND (g->>'trip_id')::uuid = p_trip $$;
-- "S1:1 S2:2 S3:1": names with a count, in the array's order.
CREATE FUNCTION rc.counts(a jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg((x->>'name') || ':' || (x->>'students'), ' ' ORDER BY i) FROM jsonb_array_elements(a) WITH ORDINALITY e(x, i) $$;
-- "A@S1 07:10": riders with their station and chosen time, in the array's order.
CREATE FUNCTION rc.riders(a jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(split_part(x->>'full_name', ' ', 2) || '@' || (x->>'station') || ' ' || left(x->>'time', 5), ', ' ORDER BY i)
  FROM jsonb_array_elements(a) WITH ORDINALITY e(x, i) $$;
-- "S1[A] S2[B,H] S3[]": the manifest's students per station.
CREATE FUNCTION rc.manifest(m jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg((s->>'name') || '[' || COALESCE((
      SELECT string_agg(split_part(x->>'full_name', ' ', 2) || CASE WHEN (x->>'confirmed')::boolean THEN '' ELSE '?' END, ',' ORDER BY j)
      FROM jsonb_array_elements(s->'students') WITH ORDINALITY f(x, j)), '') || ']', ' ' ORDER BY i)
  FROM jsonb_array_elements(m->'stations') WITH ORDINALITY e(s, i) $$;
CREATE FUNCTION rc.names(a jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT COALESCE(string_agg(split_part(x->>'full_name', ' ', 2), ',' ORDER BY i), '')
  FROM jsonb_array_elements(a) WITH ORDINALITY e(x, i) $$;
-- Student ids by letter: 'A' → e7600000-…-000000000041.
CREATE FUNCTION rc.sid(k text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('e7600000-0000-0000-0000-0000000000' || lpad(to_hex(ascii(k)), 2, '0'))::uuid $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rc TO authenticated;

-- =============================================================================
-- Fixture (as postgres)
-- =============================================================================
INSERT INTO public.companies (id, name) VALUES ('e7000000-0000-0000-0000-000000000001', 'E2E Choices Co');
INSERT INTO public.universities (id, name) VALUES
  ('e7100000-0000-0000-0000-000000000001', 'E2E Uni One'),
  ('e7100000-0000-0000-0000-000000000002', 'E2E Uni Two');
INSERT INTO public.lines (id, company_id, name, origin_name, destination_university_id, price_termly, price_yearly, price_daily)
VALUES ('e7200000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'E2E Choices', 'المنصورة',
        'e7100000-0000-0000-0000-000000000001', 3000, 5500, 40);
INSERT INTO public.stations (id, line_id, name, order_index) VALUES
  ('e7300000-0000-0000-0000-000000000001', 'e7200000-0000-0000-0000-000000000001', 'S1', 1),
  ('e7300000-0000-0000-0000-000000000002', 'e7200000-0000-0000-0000-000000000001', 'S2', 2),
  ('e7300000-0000-0000-0000-000000000003', 'e7200000-0000-0000-0000-000000000001', 'S3', 3);
INSERT INTO public.line_trips (id, line_id, direction, label, start_time, university_id, is_active) VALUES
  ('e7400000-0000-0000-0000-0000000000d1', 'e7200000-0000-0000-0000-000000000001', 'departure', 'D1', '07:00', NULL, true),
  ('e7400000-0000-0000-0000-0000000000d2', 'e7200000-0000-0000-0000-000000000001', 'departure', 'D2', '08:00', 'e7100000-0000-0000-0000-000000000002', true),
  ('e7400000-0000-0000-0000-0000000000d3', 'e7200000-0000-0000-0000-000000000001', 'departure', 'D3', '06:00', NULL, false),
  ('e7400000-0000-0000-0000-0000000000a1', 'e7200000-0000-0000-0000-000000000001', 'return', 'R1', '15:00', NULL, true),
  ('e7400000-0000-0000-0000-0000000000a2', 'e7200000-0000-0000-0000-000000000001', 'return', 'R2', '17:00', NULL, true);
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time)
SELECT ('e7400000-0000-0000-0000-0000000000' || t)::uuid, ('e7300000-0000-0000-0000-00000000000' || s)::uuid, x::time
FROM (VALUES ('d1', 1, '07:10'), ('d1', 2, '07:20'), ('d1', 3, '07:30'),
             ('d2', 1, '08:10'), ('d2', 2, '08:20'), ('d2', 3, '08:30'),
             ('d3', 1, '07:10'),
             ('a1', 3, '15:15'), ('a1', 2, '15:25'), ('a1', 1, '15:35'),
             ('a2', 3, '17:15'), ('a2', 2, '17:25'), ('a2', 1, '17:35')) v(t, s, x);

-- Supervisors: SA is assigned to the line, SB (same company) is not.
INSERT INTO auth.users (id, email) VALUES
  ('e7500000-0000-0000-0000-00000000000a', '01215550101@busak.app'),
  ('e7500000-0000-0000-0000-00000000000b', '01215550102@busak.app');
INSERT INTO public.supervisors (id, phone, full_name, company_id) VALUES
  ('e7500000-0000-0000-0000-00000000000a', '01215550101', 'E2E Supervisor A', 'e7000000-0000-0000-0000-000000000001'),
  ('e7500000-0000-0000-0000-00000000000b', '01215550102', 'E2E Supervisor B', 'e7000000-0000-0000-0000-000000000001');
INSERT INTO public.supervisor_lines (supervisor_id, line_id)
VALUES ('e7500000-0000-0000-0000-00000000000a', 'e7200000-0000-0000-0000-000000000001');

-- Students and their subscriptions (station, subscribed Going / Return trips).
CREATE TEMP TABLE rc_students (k text, uni int, station int, dep text, ret text) ON COMMIT DROP;
INSERT INTO rc_students VALUES
  ('A', 1, 1, 'd1', 'a1'), ('B', 1, 2, 'd1', 'a2'), ('C', 2, 2, 'd2', 'a1'), ('D', 2, 3, 'd1', 'a1'),
  ('E', 1, 3, 'd1', 'a1'), ('F', 2, 1, 'd2', 'a1'), ('H', 1, 2, 'd1', 'a1');
INSERT INTO auth.users (id, email) SELECT rc.sid(k), '0121555' || lpad(ascii(k)::text, 4, '0') || '@busak.app' FROM rc_students;
INSERT INTO public.students (id, phone, full_name, university, university_id)
SELECT rc.sid(k), '0121555' || lpad(ascii(k)::text, 4, '0'), 'E2E ' || k || ' Student',
       CASE uni WHEN 1 THEN 'E2E Uni One' ELSE 'E2E Uni Two' END,
       ('e7100000-0000-0000-0000-00000000000' || uni)::uuid
FROM rc_students;
INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, start_date, end_date,
                                  departure_trip_id, return_trip_id)
SELECT rc.sid(k), 'e7200000-0000-0000-0000-000000000001', ('e7300000-0000-0000-0000-00000000000' || station)::uuid,
       'daily', 'active', 40, public.cairo_today(), public.cairo_today() + 1,
       ('e7400000-0000-0000-0000-0000000000' || dep)::uuid, ('e7400000-0000-0000-0000-0000000000' || ret)::uuid
FROM rc_students;

-- The day's votes.
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, departure_time, return_time, is_returning)
SELECT rc.sid(k), public.cairo_today() + day, riding, dep::time, ret::time, back
FROM (VALUES ('A', 0, true, '07:10', '15:35', true),
             ('B', 0, true, '07:20', NULL, true),
             ('C', 0, true, '08:20', '15:25', true),
             ('D', 0, true, '07:30', NULL, false),
             ('H', 0, true, '08:20', NULL, false),
             ('F', 0, false, NULL, NULL, false),
             ('A', 1, true, '07:10', NULL, false)) v(k, day, riding, dep, ret, back);

-- =============================================================================
-- Supervisor A: dashboard trip_times by the chosen trip
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT rc.login('e7500000-0000-0000-0000-00000000000a');
DO $$
DECLARE
  d jsonb := public.get_supervisor_dashboard();
  v_today date := public.cairo_today();
  d1 uuid := 'e7400000-0000-0000-0000-0000000000d1'; d2 uuid := 'e7400000-0000-0000-0000-0000000000d2';
  r1 uuid := 'e7400000-0000-0000-0000-0000000000a1'; r2 uuid := 'e7400000-0000-0000-0000-0000000000a2';
  g jsonb;
BEGIN
  PERFORM rc.ok('T1 one group per chosen trip today: D1 4, D2 1, R1 2, R2 1 (none for the inactive D3)',
    (SELECT string_agg(format('%s %s', x->>'label', x->>'students'), ', ' ORDER BY x->>'direction', x->>'time')
       FROM jsonb_array_elements(d->'trip_times') x WHERE (x->>'ride_date')::date = v_today)
      = 'D1 4, D2 1, R1 2, R2 1',
    (SELECT string_agg(format('%s %s %s', x->>'ride_date', x->>'label', x->>'students'), ', ')
       FROM jsonb_array_elements(d->'trip_times') x));

  g := rc.grp(d, v_today, 'departure', d1);
  PERFORM rc.ok('T2 D1 leaves at its start time; riders per station in travel order',
    g->>'time' = '07:00:00' AND rc.counts(g->'stations') = 'S1:1 S2:2 S3:1', rc.counts(g->'stations'));
  PERFORM rc.ok('T3 D1 riders with station and chosen time; H (Uni One chose a Uni Two time) falls back to D1',
    rc.riders(g->'riders') = 'A@S1 07:10, B@S2 07:20, H@S2 08:20, D@S3 07:30', rc.riders(g->'riders'));
  PERFORM rc.ok('T4 D1 riders per university, most first',
    rc.counts(g->'universities') = 'E2E Uni One:3 E2E Uni Two:1', rc.counts(g->'universities'));

  g := rc.grp(d, v_today, 'departure', d2);
  PERFORM rc.ok('T5 D2 (Uni Two only) lists every stop, empty ones too, and its university',
    g->>'time' = '08:00:00' AND g->>'university' = 'E2E Uni Two'
      AND rc.counts(g->'stations') = 'S1:0 S2:1 S3:0' AND rc.riders(g->'riders') = 'C@S2 08:20',
    g::text);

  g := rc.grp(d, v_today, 'return', r1);
  PERFORM rc.ok('T6 R1 stations in return travel order (S3 → S1)',
    rc.counts(g->'stations') = 'S3:0 S2:1 S1:1' AND rc.riders(g->'riders') = 'C@S2 15:25, A@S1 15:35',
    rc.counts(g->'stations') || ' | ' || rc.riders(g->'riders'));
  PERFORM rc.ok('T7 R1 riders per university',
    rc.counts(g->'universities') = 'E2E Uni One:1 E2E Uni Two:1', rc.counts(g->'universities'));

  g := rc.grp(d, v_today, 'return', r2);
  PERFORM rc.ok('T8 returning with no time saved: the subscription''s return trip (B on R2)',
    rc.riders(g->'riders') = 'B@S2 17:25' AND rc.counts(g->'universities') = 'E2E Uni One:1', g::text);

  g := rc.grp(d, v_today + 1, 'departure', d1);
  PERFORM rc.ok('T9 the next ride day is grouped on its own (A on D1 tomorrow)',
    (g->>'students')::int = 1 AND rc.riders(g->'riders') = 'A@S1 07:10'
      AND (SELECT count(*) FROM jsonb_array_elements(d->'trip_times') x WHERE (x->>'ride_date')::date = v_today + 1) = 1,
    g::text);
END $$;

-- =============================================================================
-- Supervisor A: trip manifests
-- =============================================================================
DO $$
DECLARE
  l uuid := 'e7200000-0000-0000-0000-000000000001';
  d1 uuid := 'e7400000-0000-0000-0000-0000000000d1'; d2 uuid := 'e7400000-0000-0000-0000-0000000000d2';
  r1 uuid := 'e7400000-0000-0000-0000-0000000000a1';
  m jsonb;
BEGIN
  m := public.get_supervisor_trip_manifest(l, 'departure', d1);
  PERFORM rc.ok('M1 Going trips list the riders who chose each active trip',
    (SELECT string_agg(format('%s %s', x->>'label', x->>'students'), ', ' ORDER BY x->>'start_time') FROM jsonb_array_elements(m->'trips') x)
      = 'D1 4, D2 1',
    m->>'trips');
  PERFORM rc.ok('M2 D1 manifest: students at the station they chose it from',
    rc.manifest(m) = 'S1[A] S2[B,H] S3[D]', rc.manifest(m));
  PERFORM rc.ok('M3 each student carries the time they chose',
    (SELECT string_agg(split_part(x->>'full_name', ' ', 2) || ' ' || (x->>'chosen_time'), ', ' ORDER BY x->>'full_name')
       FROM jsonb_array_elements(m->'stations') s, jsonb_array_elements(s->'students') x)
      = 'A 07:10:00, B 07:20:00, D 07:30:00, H 08:20:00',
    m->>'stations');
  PERFORM rc.ok('M4 unconfirmed: subscribed with no vote (E); a "not riding" vote (F) is not listed',
    rc.names(m->'unconfirmed') = 'E' AND m->'unconfirmed'->0->>'station' = 'S3', m->>'unconfirmed');

  m := public.get_supervisor_trip_manifest(l, 'departure', d2);
  PERFORM rc.ok('M5 D2 manifest: only C', rc.manifest(m) = 'S1[] S2[C] S3[]', rc.manifest(m));

  m := public.get_supervisor_trip_manifest(l, 'return', r1);
  PERFORM rc.ok('M6 R1 manifest in return order, E still unconfirmed',
    rc.manifest(m) = 'S3[] S2[C] S1[A]' AND rc.names(m->'unconfirmed') = 'E',
    rc.manifest(m) || ' | ' || rc.names(m->'unconfirmed'));

  m := public.get_supervisor_trip_manifest(l, 'departure', d1, public.cairo_today() + 1);
  -- Unconfirmed students come in station order.
  PERFORM rc.ok('M7 the next ride day: its own choices and its own unconfirmed list',
    rc.manifest(m) = 'S1[A] S2[] S3[]' AND rc.names(m->'unconfirmed') = 'F,B,C,H,D,E',
    rc.manifest(m) || ' | ' || rc.names(m->'unconfirmed'));

  -- E boards D1 without having voted: listed there (not confirmed), off the Going unconfirmed list.
  PERFORM public.supervisor_check_in_student(
    (SELECT qr_code_value FROM public.students WHERE id = rc.sid('E')), 'departure', d1);
  m := public.get_supervisor_trip_manifest(l, 'departure', d1);
  PERFORM rc.ok('M8 a check-in without a vote shows on the scanned trip, marked unconfirmed',
    rc.manifest(m) = 'S1[A] S2[B,H] S3[D,E?]' AND rc.names(m->'unconfirmed') = ''
      AND (SELECT x->>'checked_in_at' FROM jsonb_array_elements(m->'stations') s, jsonb_array_elements(s->'students') x
           WHERE x->>'id' = rc.sid('E')::text) IS NOT NULL,
    rc.manifest(m) || ' | ' || rc.names(m->'unconfirmed'));
  m := public.get_supervisor_trip_manifest(l, 'return', r1);
  PERFORM rc.ok('M9 the Going check-in leaves E unconfirmed for the return',
    rc.names(m->'unconfirmed') = 'E', m->>'unconfirmed');
END $$;

-- =============================================================================
-- Supervisor A: rider counts per station and Going trip (with returns)
-- =============================================================================
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('%s %s %s/%s %s',
           CASE schedule_id WHEN 'e7400000-0000-0000-0000-0000000000d1' THEN 'D1'
                            WHEN 'e7400000-0000-0000-0000-0000000000d2' THEN 'D2' ELSE schedule_id::text END,
           station_name, riding_count, returning_count, COALESCE(left(return_time::text, 5), '-')), '; ' ORDER BY departure_time)
  INTO v FROM public.get_line_rider_counts_with_returns('e7200000-0000-0000-0000-000000000001', public.cairo_today());
  PERFORM rc.ok('C1 counts by the chosen trip: riders / returning and the earliest return per station',
    v = 'D1 S1 1/1 15:35; D1 S2 2/1 17:25; D1 S3 1/0 -; D2 S1 0/0 -; D2 S2 1/1 15:25; D2 S3 0/0 -', v);
END $$;

-- =============================================================================
-- Access
-- =============================================================================
DO $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM count(*) FROM public.rider_trip_choices(public.cairo_today());
  EXCEPTION WHEN insufficient_privilege THEN v_err := SQLERRM;
  END;
  PERFORM rc.ok('S1 the internal rider_trip_choices helper is not callable by app users', v_err IS NOT NULL, v_err);
END $$;

SELECT rc.login('e7500000-0000-0000-0000-00000000000b');
DO $$
DECLARE v_err text; d jsonb;
BEGIN
  BEGIN
    PERFORM public.get_supervisor_trip_manifest('e7200000-0000-0000-0000-000000000001', 'departure');
  EXCEPTION WHEN others THEN v_err := SQLERRM;
  END;
  d := public.get_supervisor_dashboard();
  PERFORM rc.ok('S2 a supervisor not on the line gets neither its manifest nor its riders',
    v_err LIKE '%غير مسند%' AND jsonb_array_length(d->'trip_times') = 0, v_err);
END $$;
RESET ROLE;

-- =============================================================================
\o
\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, step, detail FROM rc.results ORDER BY n;
DO $$ DECLARE f int; BEGIN
  SELECT count(*) INTO f FROM rc.results WHERE NOT ok;
  IF f > 0 THEN RAISE EXCEPTION '% test step(s) failed', f; END IF;
  RAISE NOTICE 'all % steps passed', (SELECT count(*) FROM rc.results);
END $$;
ROLLBACK;
