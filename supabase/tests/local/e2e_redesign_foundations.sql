-- End-to-end test of the redesign's backend foundations:
--   20261104000002_student_specialisation   (A)
--   20261105000001_line_bus_capacity        (B)
--   20261106000001_app_versions             (C)
--   20261107000001_term_recap               (D)
--   20261108000001_boarded_rides_count      (E)
-- Run by run_local.sh after every migration; builds its own two companies in ONE
-- transaction, rolled back at the end. Every step runs with the role and the
-- JWT claims PostgREST uses.
--
-- Company A: line L1 (S1 → S2 → university), admin AA, supervisor SA, student s1.
--   Going   D1 07:00, arrives 08:00   S1 07:10, S2 07:20
--           D2 08:00, no arrival time S1 08:10
--   Return  R1 15:00, R2 17:00
-- Company B: line LB, admin AB, supervisor SB, student s2.  AS = platform admin.
-- s1's rides (days from today): -40 (before the range), -9 07:10 back 15:00,
--   -8 08:10 not back, -7 no times saved (the subscription's), -6 "not riding",
--   +1 (tomorrow, not counted yet).
-- s1 was scanned: -9 going and return, -8 going, and a repeat on -7 (not a boarding).
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\o /dev/null
BEGIN;

CREATE SCHEMA rf;
GRANT USAGE ON SCHEMA rf TO authenticated, anon;
CREATE TABLE rf.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE TABLE rf.names (id uuid PRIMARY KEY, name text);
CREATE FUNCTION rf.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO rf.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION rf.id(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM rf.names WHERE name = p_name $$;
CREATE FUNCTION rf.login(p_name text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', (SELECT id FROM rf.names WHERE name = p_name), 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION rf.logout() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', '{"role":"anon"}', true) $$;
-- Runs SQL as the current role; the SQLSTATE, or NULL when it worked.
CREATE FUNCTION rf.code(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE; END $$;
CREATE FUNCTION rf.day(p_offset integer) RETURNS text LANGUAGE sql STABLE AS
  $$ SELECT (public.cairo_today() + p_offset)::text $$;
-- As postgres: what is stored, whatever the caller may read.
CREATE FUNCTION rf.specialisation(p_name text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT specialisation FROM public.students WHERE id = rf.id(p_name) $$;
CREATE FUNCTION rf.capacity(p_name text) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT bus_capacity FROM public.lines WHERE id = rf.id(p_name) $$;
CREATE FUNCTION rf.sub(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM public.subscriptions WHERE student_id = rf.id(p_name) ORDER BY created_at DESC LIMIT 1 $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rf TO authenticated, anon;

-- =============================================================================
-- Fixture (as postgres)
-- =============================================================================
INSERT INTO rf.names VALUES
  ('ea000000-0000-0000-0000-00000000000a', 'co_a'), ('ea000000-0000-0000-0000-00000000000b', 'co_b'),
  ('ea100000-0000-0000-0000-000000000001', 'U1'),
  ('ea200000-0000-0000-0000-000000000001', 'L1'), ('ea200000-0000-0000-0000-000000000002', 'LB'),
  ('ea300000-0000-0000-0000-000000000001', 'S1'), ('ea300000-0000-0000-0000-000000000002', 'S2'),
  ('ea300000-0000-0000-0000-000000000003', 'SBst'),
  ('ea400000-0000-0000-0000-0000000000d1', 'D1'), ('ea400000-0000-0000-0000-0000000000d2', 'D2'),
  ('ea400000-0000-0000-0000-0000000000a1', 'R1'), ('ea400000-0000-0000-0000-0000000000a2', 'R2'),
  ('ea400000-0000-0000-0000-0000000000db', 'DB'),
  ('ea500000-0000-0000-0000-0000000000a0', 'AS'),
  ('ea500000-0000-0000-0000-0000000000a1', 'AA'), ('ea500000-0000-0000-0000-0000000000a2', 'AB'),
  ('ea600000-0000-0000-0000-000000000001', 'SA'), ('ea600000-0000-0000-0000-000000000002', 'SB'),
  ('ea700000-0000-0000-0000-000000000001', 's1'), ('ea700000-0000-0000-0000-000000000002', 's2'),
  ('ea700000-0000-0000-0000-000000000003', 's3');

INSERT INTO public.companies (id, name) VALUES (rf.id('co_a'), 'E2E Redesign A'), (rf.id('co_b'), 'E2E Redesign B');
INSERT INTO public.universities (id, name) VALUES (rf.id('U1'), 'E2E Redesign Uni');
INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily) VALUES
  (rf.id('L1'), rf.id('co_a'), 'خط التجربة', 3000, 5500, 40),
  (rf.id('LB'), rf.id('co_b'), 'خط ب', 3000, 5500, 40);
INSERT INTO public.stations (id, line_id, name, order_index) VALUES
  (rf.id('S1'), rf.id('L1'), 'S1', 1), (rf.id('S2'), rf.id('L1'), 'S2', 2), (rf.id('SBst'), rf.id('LB'), 'SB', 1);
INSERT INTO public.line_trips (id, line_id, direction, start_time, arrival_time) VALUES
  (rf.id('D1'), rf.id('L1'), 'departure', '07:00', '08:00'),
  (rf.id('D2'), rf.id('L1'), 'departure', '08:00', NULL),
  (rf.id('R1'), rf.id('L1'), 'return', '15:00', NULL),
  (rf.id('R2'), rf.id('L1'), 'return', '17:00', NULL),
  (rf.id('DB'), rf.id('LB'), 'departure', '07:00', NULL);
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES
  (rf.id('D1'), rf.id('S1'), '07:10'), (rf.id('D1'), rf.id('S2'), '07:20'),
  (rf.id('D2'), rf.id('S1'), '08:10'), (rf.id('DB'), rf.id('SBst'), '07:10');

INSERT INTO auth.users (id, email)
SELECT id, CASE WHEN name LIKE 'A_' THEN lower(name) || '@redesign.test'
                WHEN name LIKE 'S_' THEN '0121888010' || right(id::text, 1) || '@busak.app'
                ELSE '0121888000' || right(id::text, 1) || '@busak.app' END
FROM rf.names WHERE name IN ('AS', 'AA', 'AB', 'SA', 'SB', 's1', 's2', 's3');
INSERT INTO public.admins (id, email, full_name, role) VALUES (rf.id('AS'), 'as@redesign.test', 'المنصة', 'super_admin');
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  (rf.id('AA'), 'aa@redesign.test', 'مدير أ', 'company_admin', rf.id('co_a'), rf.id('AS')),
  (rf.id('AB'), 'ab@redesign.test', 'مدير ب', 'company_admin', rf.id('co_b'), rf.id('AS'));
INSERT INTO public.supervisors (id, phone, full_name, company_id) VALUES
  (rf.id('SA'), '01218880101', 'مشرف أ', rf.id('co_a')), (rf.id('SB'), '01218880102', 'مشرف ب', rf.id('co_b'));
INSERT INTO public.supervisor_lines (supervisor_id, line_id) VALUES (rf.id('SA'), rf.id('L1')), (rf.id('SB'), rf.id('LB'));
INSERT INTO public.students (id, phone, full_name, university, university_id, college) VALUES
  (rf.id('s1'), '01218880001', 'سارة أحمد علي', 'E2E Redesign Uni', rf.id('U1'), 'الهندسة'),
  (rf.id('s2'), '01218880002', 'منى محمود حسن', 'E2E Redesign Uni', rf.id('U1'), 'غير محدد');

-- Subscriptions are made the ordinary way (so membership and the company follow),
-- then s1's becomes a first-semester subscription that started a month ago.
INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, start_date, end_date, departure_trip_id)
VALUES (rf.id('s1'), rf.id('L1'), rf.id('S1'), 'daily', 'active', 40, public.cairo_today(), public.cairo_today() + 1, rf.id('D1')),
       (rf.id('s2'), rf.id('LB'), rf.id('SBst'), 'daily', 'active', 40, public.cairo_today(), public.cairo_today() + 1, rf.id('DB'));

SET LOCAL session_replication_role = replica;
UPDATE public.subscriptions
SET type = 'termly', period_code = 'first', academic_year = 2026, price = 3000, company_id = rf.id('co_a'),
    start_date = public.cairo_today() - 30, end_date = public.cairo_today() + 30,
    departure_time = '07:10', return_time = '15:00', return_trip_id = rf.id('R1')
WHERE student_id = rf.id('s1');
UPDATE public.subscriptions SET company_id = rf.id('co_b'), start_date = public.cairo_today() - 30 WHERE student_id = rf.id('s2');
INSERT INTO public.company_students (company_id, student_id) VALUES (rf.id('co_a'), rf.id('s1')), (rf.id('co_b'), rf.id('s2'))
ON CONFLICT DO NOTHING;

INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, departure_time, return_time, is_returning, subscription_id, company_id)
SELECT rf.id('s1'), public.cairo_today() + v.day, v.riding, v.dep::time, v.ret::time, v.back, rf.sub('s1'), rf.id('co_a')
FROM (VALUES (-40, true, '07:10', '15:00', true),
             (-9, true, '07:10', '15:00', true),
             (-8, true, '08:10', NULL, false),
             (-7, true, NULL, NULL, true),
             (-6, false, NULL, NULL, false),
             (1, true, '07:10', NULL, false)) v(day, riding, dep, ret, back);
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, departure_time, is_returning, subscription_id, company_id)
VALUES (rf.id('s2'), public.cairo_today() - 9, true, '07:10', false, rf.sub('s2'), rf.id('co_b'));

INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, station_id, company_id, ride_date, direction, result)
SELECT rf.id('SA'), rf.id('s1'), rf.sub('s1'), rf.id('L1'), rf.id('S1'), rf.id('co_a'), public.cairo_today() + v.day, v.direction, v.result
FROM (VALUES (-9, 'departure', 'checked_in'), (-9, 'return', 'checked_in'), (-8, 'departure', 'checked_in'),
             (-7, 'departure', 'already_checked_in')) v(day, direction, result);
INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, station_id, company_id, ride_date, direction, result)
VALUES (rf.id('SB'), rf.id('s2'), rf.sub('s2'), rf.id('LB'), rf.id('SBst'), rf.id('co_b'), public.cairo_today() - 9, 'departure', 'checked_in');

-- A receipt of s1 waiting for review (for the dashboard's list).
INSERT INTO public.receipts (subscription_id, image_url, company_id)
VALUES (rf.sub('s1'), rf.id('s1') || '/' || rf.sub('s1') || '_k1.jpg', rf.id('co_a'));
SET LOCAL session_replication_role = origin;

-- Fridays off, one holiday inside the range and one long before it.
UPDATE public.app_settings
SET vote_reminder_off_weekdays = '{5}',
    vote_reminder_off_dates = ARRAY[public.cairo_today() - 10, public.cairo_today() - 200]
WHERE id;

-- =============================================================================
-- A. Specialisation
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT rf.login('s1');
DO $$
DECLARE saved jsonb; v_err text;
BEGIN
  saved := public.update_my_profile('Sara@Example.com', 'الهندسة', NULL, '  هندسة مدنية ');
  PERFORM rf.ok('A1 the four-argument form saves the specialisation, trimmed, with the rest of the profile',
    saved->>'specialisation' = 'هندسة مدنية' AND saved->>'college' = 'الهندسة' AND saved->>'email' = 'sara@example.com'
      AND rf.specialisation('s1') = 'هندسة مدنية', saved::text);
  PERFORM rf.ok('A2 the student reads it on their own row',
    (SELECT specialisation FROM public.students WHERE id = rf.id('s1')) = 'هندسة مدنية');

  saved := public.update_my_profile('sara@example.com', 'الهندسة', NULL);
  PERFORM rf.ok('A3 the older three-argument form still answers its three keys and leaves the specialisation alone',
    NOT (saved ? 'specialisation') AND saved ? 'college' AND saved ? 'email' AND saved ? 'birth_date'
      AND rf.specialisation('s1') = 'هندسة مدنية', saved::text);

  PERFORM rf.ok('A4 a specialisation longer than 80 characters is refused',
    rf.code(format('SELECT public.update_my_profile(NULL, NULL, NULL, %L)', repeat('ت', 81))) = '23514'
      AND rf.specialisation('s1') = 'هندسة مدنية');

  UPDATE public.students SET specialisation = 'تغيير مباشر' WHERE id = rf.id('s1');
  PERFORM rf.ok('A5 a student still cannot update their row directly', rf.specialisation('s1') = 'هندسة مدنية');

  saved := public.update_my_profile('sara@example.com', 'الهندسة', NULL, '   ');
  PERFORM rf.ok('A6 an empty value clears it', saved->'specialisation' = 'null'::jsonb AND rf.specialisation('s1') IS NULL, saved::text);
  PERFORM public.update_my_profile('sara@example.com', 'الهندسة', NULL, 'هندسة مدنية');
END $$;

-- Sign-up writes the row itself, as it does the college.
SELECT rf.login('s3');
DO $$
DECLARE v_code text;
BEGIN
  v_code := rf.code(format(
    'INSERT INTO public.students (id, phone, full_name, university, college, specialisation) VALUES (%L, %L, %L, %L, %L, %L)',
    rf.id('s3'), '01218880003', 'هدى سمير فؤاد', 'E2E Redesign Uni', 'العلوم', 'فيزياء'));
  PERFORM rf.ok('A7 a new student writes the specialisation with their profile at sign-up',
    v_code IS NULL AND rf.specialisation('s3') = 'فيزياء', v_code);
END $$;

SELECT rf.login('SA');
SELECT rf.ok('A8 a supervisor cannot use the profile function',
  rf.code($q$SELECT public.update_my_profile(NULL, NULL, NULL, 'x')$q$) = '42501');

SELECT rf.login('AA');
DO $$
DECLARE r jsonb;
BEGIN
  SELECT x INTO r FROM jsonb_array_elements(public.get_company_students_page(rf.id('co_a'))->'rows') x
  WHERE (x->>'id')::uuid = rf.id('s1');
  PERFORM rf.ok('A9 the dashboard''s students page carries the specialisation next to the college',
    r->>'specialisation' = 'هندسة مدنية' AND r->>'college' = 'الهندسة' AND r ? 'subscriptions' AND r ? 'profile_image_url', r::text);
  SELECT x INTO r FROM jsonb_array_elements(public.get_pending_receipts_page(rf.id('co_a'))->'rows') x
  WHERE (x->>'student_id')::uuid = rf.id('s1');
  PERFORM rf.ok('A10 so does the receipts review list',
    r->>'specialisation' = 'هندسة مدنية' AND r->>'college' = 'الهندسة' AND r ? 'period_label' AND r ? 'image_url', r::text);
END $$;
SELECT rf.login('AB');
SELECT rf.ok('A11 another company''s admin still gets neither list',
  rf.code(format('SELECT public.get_company_students_page(%L)', rf.id('co_a'))) = '42501'
    AND rf.code(format('SELECT public.get_pending_receipts_page(%L)', rf.id('co_a'))) = '42501');

-- =============================================================================
-- B. Bus capacity
-- =============================================================================
SELECT rf.login('AA');
DO $$
BEGIN
  PERFORM rf.ok('B1 the company''s admin sets its line''s capacity',
    public.set_line_bus_capacity(rf.id('L1'), 50) = 50 AND rf.capacity('L1') = 50);
  PERFORM rf.ok('B2 zero, a negative number and more than 500 are refused',
    rf.code(format('SELECT public.set_line_bus_capacity(%L, 0)', rf.id('L1'))) = '23514'
      AND rf.code(format('SELECT public.set_line_bus_capacity(%L, -3)', rf.id('L1'))) = '23514'
      AND rf.code(format('SELECT public.set_line_bus_capacity(%L, 501)', rf.id('L1'))) = '23514'
      AND rf.capacity('L1') = 50);
  PERFORM rf.ok('B3 not another company''s line, and not a line that does not exist',
    rf.code(format('SELECT public.set_line_bus_capacity(%L, 30)', rf.id('LB'))) = '42501'
      AND rf.code(format('SELECT public.set_line_bus_capacity(%L, 30)', rf.id('U1'))) = 'P0002'
      AND rf.capacity('LB') IS NULL);
END $$;

SELECT rf.login('SA');
DO $$
DECLARE c jsonb := public.get_my_line_capacities();
BEGIN
  PERFORM rf.ok('B4 a supervisor reads the capacity of their own lines only',
    jsonb_array_length(c) = 1 AND (c->0->>'line_id')::uuid = rf.id('L1') AND (c->0->>'bus_capacity')::int = 50, c::text);
  PERFORM rf.ok('B5 a supervisor cannot set it',
    rf.code(format('SELECT public.set_line_bus_capacity(%L, 10)', rf.id('L1'))) = '42501' AND rf.capacity('L1') = 50);
END $$;
SELECT rf.login('SB');
SELECT rf.ok('B6 a line with no capacity answers null', c = jsonb_build_array(jsonb_build_object('line_id', rf.id('LB'), 'bus_capacity', NULL)), c::text)
FROM (SELECT public.get_my_line_capacities() AS c) x;
SELECT rf.login('s1');
SELECT rf.ok('B7 a student gets an empty list and cannot set anything',
  public.get_my_line_capacities() = '[]'::jsonb
    AND rf.code(format('SELECT public.set_line_bus_capacity(%L, 10)', rf.id('L1'))) = '42501');
SELECT rf.login('AS');
SELECT rf.ok('B8 the platform admin clears it with null',
  public.set_line_bus_capacity(rf.id('L1'), NULL) IS NULL AND rf.capacity('L1') IS NULL);
RESET ROLE;
SELECT rf.ok('B9 the column itself refuses zero',
  rf.code(format('UPDATE public.lines SET bus_capacity = 0 WHERE id = %L', rf.id('L1'))) = '23514');

-- =============================================================================
-- C. App versions
-- =============================================================================
SET LOCAL ROLE anon;
SELECT rf.logout();
DO $$
DECLARE v jsonb := public.get_app_version('android');
BEGIN
  PERFORM rf.ok('C1 before sign-in the app reads its platform''s row; it starts by asking nobody to update',
    v->>'platform' = 'android' AND v->>'min_version' = '0.0.0' AND v->>'latest_version' = '0.0.0'
      AND v->'whats_new' = '[]'::jsonb AND v->'store_url' = 'null'::jsonb, v::text);
  PERFORM rf.ok('C2 an unknown platform answers nothing', public.get_app_version('web') IS NULL AND public.get_app_version(NULL) IS NULL);
  PERFORM rf.ok('C3 the table itself is closed to a signed-out client, and so is saving',
    rf.code('SELECT count(*) FROM public.app_versions') = '42501'
      AND rf.code($q$SELECT public.save_app_version('android', '1.0.0', '1.0.0')$q$) = '42501');
END $$;

SET LOCAL ROLE authenticated;
SELECT rf.login('s1');
SELECT rf.ok('C4 a student sees no row of the table and cannot save',
  (SELECT count(*) FROM public.app_versions) = 0
    AND rf.code($q$SELECT public.save_app_version('android', '1.0.0', '1.0.0')$q$) = '42501');
SELECT rf.login('AA');
SELECT rf.ok('C5 nor can a company''s admin',
  (SELECT count(*) FROM public.app_versions) = 0
    AND rf.code($q$SELECT public.save_app_version('android', '1.0.0', '1.0.0')$q$) = '42501');

SELECT rf.login('AS');
DO $$
DECLARE v jsonb;
BEGIN
  v := public.save_app_version('iOS', ' 2.3.0 ', '2.5.0', ARRAY['  دخول أسرع بالبصمة ', '', 'ملخّص الترم'], ' https://apps.apple.com/app/id1 ');
  PERFORM rf.ok('C6 the platform admin saves a platform: trimmed, empty lines dropped',
    v->>'platform' = 'ios' AND v->>'min_version' = '2.3.0' AND v->>'latest_version' = '2.5.0'
      AND v->'whats_new' = '["دخول أسرع بالبصمة", "ملخّص الترم"]'::jsonb
      AND v->>'store_url' = 'https://apps.apple.com/app/id1', v::text);
  PERFORM rf.ok('C7 and reads both rows, with who saved it',
    (SELECT count(*) FROM public.app_versions) = 2
      AND (SELECT updated_by FROM public.app_versions WHERE platform = 'ios') = rf.id('AS'));
  PERFORM rf.ok('C8 versions compare by number: 2.9.0 may be the minimum of 2.10.0, not the other way round',
    rf.code($q$SELECT public.save_app_version('android', '2.9.0', '2.10.0')$q$) IS NULL
      AND rf.code($q$SELECT public.save_app_version('android', '2.10.0', '2.9.0')$q$) = '23514'
      AND public.get_app_version('android')->>'min_version' = '2.9.0');
  PERFORM rf.ok('C9 refused: a version that is not numbers and dots, a fourth line, a line over 120 characters, a link that is not https, an unknown platform',
    rf.code($q$SELECT public.save_app_version('android', 'v2', '2.0.0')$q$) = '23514'
      AND rf.code($q$SELECT public.save_app_version('android', '1.0.0', '2.0.0', ARRAY['a', 'b', 'c', 'd'])$q$) = '23514'
      AND rf.code(format($q$SELECT public.save_app_version('android', '1.0.0', '2.0.0', ARRAY[%L])$q$, repeat('س', 121))) = '23514'
      AND rf.code($q$SELECT public.save_app_version('android', '1.0.0', '2.0.0', '{}', 'http://example.com')$q$) = '23514'
      AND rf.code($q$SELECT public.save_app_version('web', '1.0.0', '2.0.0')$q$) = '22023');
  PERFORM rf.ok('C10 even the platform admin writes only through the function',
    rf.code($q$UPDATE public.app_versions SET min_version = '9.0.0'$q$) = '42501'
      AND rf.code($q$DELETE FROM public.app_versions$q$) = '42501');
END $$;

SET LOCAL ROLE anon;
SELECT rf.logout();
SELECT rf.ok('C11 the signed-out app reads what was saved', public.get_app_version('ios')->>'min_version' = '2.3.0');

-- =============================================================================
-- D. Term recap
-- =============================================================================
SELECT rf.ok('D1 a signed-out client cannot ask for a recap', rf.code('SELECT public.get_my_term_recap()') = '42501');

SET LOCAL ROLE authenticated;
SELECT rf.login('s1');
DO $$
DECLARE
  r jsonb := public.get_my_term_recap(p_from := public.cairo_today() - 20, p_to := public.cairo_today() + 10);
  t jsonb := public.get_my_term_recap();
  v_first record;
BEGIN
  PERFORM rf.ok('D2 one ride per confirmed day in the range, up to today: not the day before the range, not "not riding", not tomorrow',
    (SELECT string_agg(x->>'date', ',' ORDER BY i) FROM jsonb_array_elements(r->'rides') WITH ORDINALITY e(x, i))
      = rf.day(-9) || ',' || rf.day(-8) || ',' || rf.day(-7), r->>'rides');
  PERFORM rf.ok('D3 each ride carries its ISO weekday',
    (SELECT bool_and((x->>'weekday')::int = extract(isodow FROM (x->>'date')::date)::int) FROM jsonb_array_elements(r->'rides') x));
  PERFORM rf.ok('D4 a ride with its chosen times: 07:10 there (50 minutes to the university), back at 15:00, boarded both ways',
    r->'rides'->0->>'departure_time' = '07:10' AND r->'rides'->0->>'return_time' = '15:00'
      AND (r->'rides'->0->>'returns_by_bus')::boolean AND (r->'rides'->0->>'departure_minutes')::int = 50
      AND (r->'rides'->0->>'boarded_departure')::boolean AND (r->'rides'->0->>'boarded_return')::boolean
      AND (r->'rides'->0->>'line_id')::uuid = rf.id('L1') AND (r->'rides'->0->>'station_id')::uuid = rf.id('S1'),
    (r->'rides'->0)::text);
  PERFORM rf.ok('D5 not returning: no return time; a trip without an arrival time: no minutes',
    r->'rides'->1->>'departure_time' = '08:10' AND r->'rides'->1->'return_time' = 'null'::jsonb
      AND NOT (r->'rides'->1->>'returns_by_bus')::boolean AND r->'rides'->1->'departure_minutes' = 'null'::jsonb
      AND (r->'rides'->1->>'boarded_departure')::boolean AND NOT (r->'rides'->1->>'boarded_return')::boolean,
    (r->'rides'->1)::text);
  PERFORM rf.ok('D6 no times saved for the day: the subscription''s; a repeated scan is not a boarding',
    r->'rides'->2->>'departure_time' = '07:10' AND r->'rides'->2->>'return_time' = '15:00'
      AND (r->'rides'->2->>'departure_minutes')::int = 50
      AND NOT (r->'rides'->2->>'boarded_departure')::boolean, (r->'rides'->2)::text);
  PERFORM rf.ok('D7 the summary counts them',
    r->'summary' = jsonb_build_object('ride_days', 3, 'return_days', 2, 'boarded_departures', 2, 'boarded_returns', 1,
                                      'first_ride_date', rf.day(-9), 'last_ride_date', rf.day(-7)), r->>'summary');
  PERFORM rf.ok('D8 the most used line with its stations in route order, and the most used stop',
    (r->'line'->>'id')::uuid = rf.id('L1') AND (r->'line'->>'company_id')::uuid = rf.id('co_a')
      AND r->'line'->>'company_name' = 'E2E Redesign A'
      AND (SELECT string_agg(x->>'name', ',' ORDER BY i) FROM jsonb_array_elements(r->'line'->'stations') WITH ORDINALITY e(x, i)) = 'S1,S2'
      AND (r->'stop'->>'id')::uuid = rf.id('S1') AND (r->'stop'->>'rides')::int = 3 AND (r->'stop'->>'stops_used')::int = 1,
    (r->'line')::text || ' ' || (r->'stop')::text);
  PERFORM rf.ok('D9 the timetable at that stop, and how long the way there takes; the way back has no length',
    r->'timetable' = '{"departure_times": ["07:10", "08:10"], "return_times": ["15:00", "17:00"]}'::jsonb
      AND r->'trip_length' = '{"departure_minutes": 50, "return_minutes": null}'::jsonb,
    (r->'timetable')::text || ' ' || (r->'trip_length')::text);
  PERFORM rf.ok('D10 the student: first name, university, college, specialisation',
    r->'student' = jsonb_build_object('full_name', 'سارة أحمد علي', 'first_name', 'سارة', 'university', 'E2E Redesign Uni',
                                      'college', 'الهندسة', 'specialisation', 'هندسة مدنية'), r->>'student');
  PERFORM rf.ok('D11 days off: the weekdays, and the holidays inside the range only',
    r->'off' = jsonb_build_object('weekdays', '[5]'::jsonb, 'dates', jsonb_build_array(rf.day(-10))), r->>'off');
  PERFORM rf.ok('D12 the range as asked, counted up to today',
    r->'range' = jsonb_build_object('from', rf.day(-20), 'to', rf.day(10), 'until', rf.day(0)) AND r->>'today' = rf.day(0), r->>'range');
  PERFORM rf.ok('D13 the subscription it is about',
    (r->'subscription'->>'id')::uuid = rf.sub('s1') AND r->'subscription'->>'type' = 'termly'
      AND r->'subscription'->>'period_code' = 'first' AND r->'subscription'->>'start_date' = rf.day(-30), r->>'subscription');

  SELECT p.name, p.label, p.start_date, p.end_date INTO v_first
  FROM public.company_periods(rf.id('co_a'), 2026) p WHERE p.period_code = 'first';
  PERFORM rf.ok('D14 with no dates given: the semester of the student''s subscription, as the company set it',
    t->'term' = jsonb_build_object('code', 'first', 'academic_year', 2026, 'name', v_first.name, 'label', v_first.label,
                                   'start_date', v_first.start_date, 'end_date', v_first.end_date)
      AND t->'range'->>'from' = v_first.start_date::text AND t->'range'->>'to' = v_first.end_date::text, t->>'term');
  PERFORM rf.ok('D15 dates the wrong way round, or more than 400 days apart, are refused',
    rf.code(format('SELECT public.get_my_term_recap(NULL, %L, %L)', rf.day(0), rf.day(-1))) = '22023'
      AND rf.code(format('SELECT public.get_my_term_recap(NULL, %L, %L)', rf.day(-500), rf.day(0))) = '22023');
  PERFORM rf.ok('D16 another student''s subscription is "not found"',
    rf.code(format('SELECT public.get_my_term_recap(%L)', rf.sub('s2'))) = 'P0002');
END $$;

SELECT rf.login('s2');
DO $$
DECLARE r jsonb := public.get_my_term_recap(p_from := public.cairo_today() - 20, p_to := public.cairo_today() + 10);
BEGIN
  PERFORM rf.ok('D17 another student gets their own rides, line and name, and nothing of the first',
    jsonb_array_length(r->'rides') = 1 AND (r->'rides'->0->>'line_id')::uuid = rf.id('LB')
      AND (r->'line'->>'id')::uuid = rf.id('LB') AND r->'student'->>'first_name' = 'منى'
      AND r->'student'->'college' = 'null'::jsonb AND r->'student'->'specialisation' = 'null'::jsonb
      AND r::text NOT LIKE '%' || rf.id('L1')::text || '%' AND r::text NOT LIKE '%سارة%',
    r::text);
  PERFORM rf.ok('D18 and cannot ask for the first student''s subscription',
    rf.code(format('SELECT public.get_my_term_recap(%L)', rf.sub('s1'))) = 'P0002');
END $$;

SELECT rf.login('s3');
DO $$
DECLARE r jsonb := public.get_my_term_recap();
BEGIN
  PERFORM rf.ok('D19 a student who never rode: no rides, no line, no stop, zeros in the summary',
    r->'rides' = '[]'::jsonb AND r->'line' = 'null'::jsonb AND r->'stop' = 'null'::jsonb AND r->'subscription' = 'null'::jsonb
      AND (r->'summary'->>'ride_days')::int = 0 AND r->'timetable' = '{"departure_times": [], "return_times": []}'::jsonb, r::text);
END $$;

SELECT rf.login('SA');
SELECT rf.ok('D20 a supervisor has no recap', rf.code('SELECT public.get_my_term_recap()') = '42501');
SELECT rf.login('AS');
SELECT rf.ok('D21 nor has an admin', rf.code('SELECT public.get_my_term_recap()') = '42501');

-- =============================================================================
-- E. Boarded rides
-- =============================================================================
SELECT rf.login('s1');
SELECT rf.ok('E1 a student''s boarded rides: every successful check-in, going and return, whatever the date',
  public.get_my_boarded_rides_count() = 3, public.get_my_boarded_rides_count()::text);
SELECT rf.ok('E2 the scan log itself stays closed to students',
  (SELECT count(*) FROM public.supervisor_scan_events) = 0);
SELECT rf.login('s2');
SELECT rf.ok('E3 each student gets their own number', public.get_my_boarded_rides_count() = 1);
SELECT rf.login('s3');
SELECT rf.ok('E4 none yet', public.get_my_boarded_rides_count() = 0);
SELECT rf.login('SA');
SELECT rf.ok('E5 a supervisor''s own number is 0, however many they scanned', public.get_my_boarded_rides_count() = 0);
SET LOCAL ROLE anon;
SELECT rf.logout();
SELECT rf.ok('E6 a signed-out client cannot ask', rf.code('SELECT public.get_my_boarded_rides_count()') = '42501');
RESET ROLE;

-- =============================================================================
\o
\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, step, left(detail, 200) AS detail FROM rf.results ORDER BY n;
DO $$ DECLARE f int; BEGIN
  SELECT count(*) INTO f FROM rf.results WHERE NOT ok;
  IF f > 0 THEN RAISE EXCEPTION '% test step(s) failed', f; END IF;
  RAISE NOTICE 'all % steps passed', (SELECT count(*) FROM rf.results);
END $$;
ROLLBACK;
