-- End-to-end test of 20261023000001_notifications_and_supervisor_photos. Run by
-- run_local.sh after every migration; builds its own two companies in ONE
-- transaction, rolled back at the end. Every step runs with the role + JWT
-- claims PostgREST would use for that user.
--
-- Company A: line L1 (trips D1 07:00 and D2 08:00 at S1), line L2 (trip X2).
--   Admin AA. Supervisors SA and SC on L1, SB on L2.
--   Students: s1 (L1, chose D1 today), s2 (L1, chose D2), s3 (L1, awaiting
--   payment), s7 (L1, no vote), s4 (L2), s5 (L1, ended yesterday).
-- Company B: line LB, admin AB, student s6.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\o /dev/null
BEGIN;

CREATE SCHEMA nt;
GRANT USAGE ON SCHEMA nt TO authenticated;
CREATE TABLE nt.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE TABLE nt.names (id uuid PRIMARY KEY, name text);
CREATE TABLE nt.sent (name text PRIMARY KEY, id uuid);
CREATE FUNCTION nt.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO nt.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION nt.login(p_name text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', (SELECT id FROM nt.names WHERE name = p_name), 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION nt.id(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM nt.names WHERE name = p_name $$;
CREATE FUNCTION nt.keep(p_name text, p_result jsonb) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
  INSERT INTO nt.sent VALUES (p_name, (p_result->>'id')::uuid); SELECT p_result $$;
CREATE FUNCTION nt.sent_id(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM nt.sent WHERE name = p_name $$;
-- Runs SQL as the current role; the error message, or NULL.
CREATE FUNCTION nt.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLERRM; END $$;
-- "SA,SC,s1": who received a notification (as postgres).
CREATE FUNCTION nt.recipients(p_name text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT string_agg(x.name, ',' ORDER BY x.name COLLATE "C") FROM public.notification_recipients r
  JOIN nt.names x ON x.id = r.user_id WHERE r.notification_id = nt.sent_id(p_name) $$;
-- "trip,l1,company": the signed-in user's feed by sent name, '*' marking unread.
CREATE FUNCTION nt.feed() RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(string_agg(COALESCE(s.name, '?') || CASE WHEN (f->>'read')::boolean THEN '' ELSE '*' END, ','
                             ORDER BY i), '')
  FROM jsonb_array_elements(public.get_my_notifications()) WITH ORDINALITY e(f, i)
  LEFT JOIN nt.sent s ON s.id = (f->>'id')::uuid $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nt TO authenticated;
GRANT SELECT ON nt.sent TO authenticated;

-- =============================================================================
-- Fixture (as postgres)
-- =============================================================================
INSERT INTO nt.names VALUES
  ('e9000000-0000-0000-0000-00000000000a', 'co_a'), ('e9000000-0000-0000-0000-00000000000b', 'co_b'),
  ('e9200000-0000-0000-0000-000000000001', 'L1'), ('e9200000-0000-0000-0000-000000000002', 'L2'),
  ('e9200000-0000-0000-0000-000000000003', 'LB'),
  ('e9300000-0000-0000-0000-000000000001', 'S1'), ('e9300000-0000-0000-0000-000000000002', 'S2'),
  ('e9300000-0000-0000-0000-000000000003', 'SBst'),
  ('e9400000-0000-0000-0000-0000000000d1', 'D1'), ('e9400000-0000-0000-0000-0000000000d2', 'D2'),
  ('e9400000-0000-0000-0000-0000000000e2', 'X2'), ('e9400000-0000-0000-0000-0000000000eb', 'XB'),
  ('e9500000-0000-0000-0000-0000000000a0', 'AS'),
  ('e9500000-0000-0000-0000-0000000000a1', 'AA'), ('e9500000-0000-0000-0000-0000000000a2', 'AB'),
  ('e9600000-0000-0000-0000-000000000001', 'SA'), ('e9600000-0000-0000-0000-000000000002', 'SB'),
  ('e9600000-0000-0000-0000-000000000003', 'SC'),
  ('e9700000-0000-0000-0000-000000000001', 's1'), ('e9700000-0000-0000-0000-000000000002', 's2'),
  ('e9700000-0000-0000-0000-000000000003', 's3'), ('e9700000-0000-0000-0000-000000000004', 's4'),
  ('e9700000-0000-0000-0000-000000000005', 's5'), ('e9700000-0000-0000-0000-000000000006', 's6'),
  ('e9700000-0000-0000-0000-000000000007', 's7');

INSERT INTO public.companies (id, name) VALUES (nt.id('co_a'), 'E2E Notify A'), (nt.id('co_b'), 'E2E Notify B');
INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily) VALUES
  (nt.id('L1'), nt.id('co_a'), 'خط الأول', 3000, 5500, 40),
  (nt.id('L2'), nt.id('co_a'), 'خط الثاني', 3000, 5500, 40),
  (nt.id('LB'), nt.id('co_b'), 'خط ب', 3000, 5500, 40);
INSERT INTO public.stations (id, line_id, name, order_index) VALUES
  (nt.id('S1'), nt.id('L1'), 'S1', 1), (nt.id('S2'), nt.id('L2'), 'S2', 1), (nt.id('SBst'), nt.id('LB'), 'SB', 1);
INSERT INTO public.line_trips (id, line_id, direction, start_time) VALUES
  (nt.id('D1'), nt.id('L1'), 'departure', '07:00'), (nt.id('D2'), nt.id('L1'), 'departure', '08:00'),
  (nt.id('X2'), nt.id('L2'), 'departure', '07:00'), (nt.id('XB'), nt.id('LB'), 'departure', '07:00');
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES
  (nt.id('D1'), nt.id('S1'), '07:10'), (nt.id('D2'), nt.id('S1'), '08:10'),
  (nt.id('X2'), nt.id('S2'), '07:10'), (nt.id('XB'), nt.id('SBst'), '07:10');

INSERT INTO auth.users (id, email)
SELECT id, CASE WHEN name LIKE 'A_' THEN lower(name) || '@e2e.test'
                WHEN name LIKE 'S_' THEN '0121777010' || right(id::text, 1) || '@busak.app'
                ELSE '0121777000' || right(id::text, 1) || '@busak.app' END
FROM nt.names WHERE name IN ('AS', 'AA', 'AB', 'SA', 'SB', 'SC', 's1', 's2', 's3', 's4', 's5', 's6', 's7');
INSERT INTO public.admins (id, email, full_name, role) VALUES (nt.id('AS'), 'as@e2e.test', 'المنصة', 'super_admin');
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  (nt.id('AA'), 'aa@e2e.test', 'مدير أ', 'company_admin', nt.id('co_a'), nt.id('AS')),
  (nt.id('AB'), 'ab@e2e.test', 'مدير ب', 'company_admin', nt.id('co_b'), nt.id('AS'));
INSERT INTO public.supervisors (id, phone, full_name, company_id)
SELECT id, '0121777010' || right(id::text, 1), 'مشرف ' || name, nt.id('co_a')
FROM nt.names WHERE name IN ('SA', 'SB', 'SC');
INSERT INTO public.supervisor_lines (supervisor_id, line_id) VALUES
  (nt.id('SA'), nt.id('L1')), (nt.id('SC'), nt.id('L1')), (nt.id('SB'), nt.id('L2'));
INSERT INTO public.students (id, phone, full_name, university)
SELECT id, '0121777000' || right(id::text, 1), 'طالب ' || name, 'جامعة'
FROM nt.names WHERE name LIKE 's_';

-- Subscriptions: (student, line, station, first trip, status, from, to).
INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, start_date, end_date, departure_trip_id)
SELECT nt.id(s), nt.id(l), nt.id(st), 'daily', status, 40, public.cairo_today() + f, public.cairo_today() + t, nt.id(trip)
FROM (VALUES ('s1', 'L1', 'S1', 'D1', 'active', 0, 1), ('s2', 'L1', 'S1', 'D1', 'active', 0, 1),
             ('s3', 'L1', 'S1', 'D1', 'pending_payment', 0, 1), ('s7', 'L1', 'S1', 'D1', 'active', 0, 1),
             ('s4', 'L2', 'S2', 'X2', 'active', 0, 1), ('s5', 'L1', 'S1', 'D1', 'expired', -30, -1),
             ('s6', 'LB', 'SBst', 'XB', 'active', 0, 1)) v(s, l, st, trip, status, f, t);
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, departure_time, is_returning) VALUES
  (nt.id('s1'), public.cairo_today(), true, '07:10', false),
  (nt.id('s2'), public.cairo_today(), true, '08:10', false);

-- =============================================================================
-- Sending
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT nt.login('AA');
DO $$
DECLARE r jsonb;
BEGIN
  r := nt.keep('company', public.send_notification('إجازة', 'غداً إجازة رسمية.', p_company_id := nt.id('co_a')));
  PERFORM nt.ok('N1 admin to the company: every open subscription that has not ended, and every supervisor',
    (r->>'students')::int = 5 AND nt.recipients('company') = 'SA,SB,SC,s1,s2,s3,s4,s7', nt.recipients('company'));
  r := nt.keep('l2', public.send_notification('تغيير', 'تغيير في موعد الخط.', p_line_id := nt.id('L2')));
  PERFORM nt.ok('N2 admin to one line: its students and its supervisor', nt.recipients('l2') = 'SB,s4', nt.recipients('l2'));
  PERFORM nt.ok('N3 the trip must be today or the next day',
    nt.err(format('SELECT public.send_notification(''x'', ''y'', p_line_id := %L, p_trip_id := %L, p_ride_date := public.cairo_today() + 2)',
      nt.id('L1'), nt.id('D1'))) LIKE '%اليوم أو الغد%');
  PERFORM nt.ok('N4 nobody to send to is refused',
    nt.err(format('SELECT public.send_notification(''x'', ''y'', p_line_id := %L, p_trip_id := %L, p_ride_date := public.cairo_today() + 1)',
      nt.id('L1'), nt.id('D1'))) LIKE '%لا يوجد طلاب%');
  PERFORM nt.ok('N5 a title is required',
    nt.err(format('SELECT public.send_notification('' '', ''y'', p_company_id := %L)', nt.id('co_a'))) LIKE '%عنوان%');
END $$;

SELECT nt.login('SA');
DO $$
DECLARE r jsonb;
BEGIN
  r := nt.keep('l1', public.send_notification('الباص اتحرك', 'الباص تحرك من أول محطة.', p_line_id := nt.id('L1')));
  PERFORM nt.ok('N6 supervisor to their line: its students and the other supervisor, not the sender',
    nt.recipients('l1') = 'SC,s1,s2,s3,s7', nt.recipients('l1'));
  r := nt.keep('trip', public.send_notification('تأخير', 'رحلة 7 هتتأخر 10 دقائق.', p_line_id := nt.id('L1'), p_trip_id := nt.id('D1')));
  PERFORM nt.ok('N7 supervisor to today''s trip: only who chose it',
    (r->>'students')::int = 1 AND nt.recipients('trip') = 'SC,s1', nt.recipients('trip'));
  PERFORM nt.ok('N8 the audience is written out: line, trip and day',
    (SELECT f->>'audience' FROM jsonb_array_elements(public.get_my_notifications()) f
     WHERE (f->>'id')::uuid = nt.sent_id('trip')) = 'خط الأول · ذهاب 7:00 ص · ' || extract(day FROM public.cairo_today())::int
       || ' ' || (ARRAY['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر',
                        'نوفمبر', 'ديسمبر'])[extract(month FROM public.cairo_today())::int]);
  PERFORM nt.ok('N9 a supervisor cannot write to another line',
    nt.err(format('SELECT public.send_notification(''x'', ''y'', p_line_id := %L)', nt.id('L2'))) LIKE '%المسندة إليك%');
  PERFORM nt.ok('N10 a supervisor cannot write to the whole company',
    nt.err(format('SELECT public.send_notification(''x'', ''y'', p_company_id := %L)', nt.id('co_a'))) LIKE '%المسندة إليك%');
END $$;

SELECT nt.login('s1');
DO $$ BEGIN
  PERFORM nt.ok('N11 a student cannot send',
    nt.err(format('SELECT public.send_notification(''x'', ''y'', p_line_id := %L)', nt.id('L1'))) LIKE '%لهذه الشركة%');
  PERFORM nt.ok('N12 the tables cannot be read directly',
    nt.err('SELECT count(*) FROM public.notifications') LIKE '%permission denied%'
    AND nt.err('SELECT count(*) FROM public.notification_recipients') LIKE '%permission denied%');
END $$;

SELECT nt.login('AB');
DO $$ BEGIN
  PERFORM nt.ok('N13 another company''s admin can neither send nor list',
    nt.err(format('SELECT public.send_notification(''x'', ''y'', p_company_id := %L)', nt.id('co_a'))) LIKE '%لهذه الشركة%'
    AND nt.err(format('SELECT public.send_notification(''x'', ''y'', p_line_id := %L)', nt.id('L1'))) LIKE '%لهذه الشركة%'
    AND nt.err(format('SELECT public.get_company_notifications(%L)', nt.id('co_a'))) LIKE '%هذه الشركة%');
END $$;

-- =============================================================================
-- Feeds and reading
-- =============================================================================
SELECT nt.login('s1');
DO $$ BEGIN
  PERFORM nt.ok('F1 student feed: newest first, all unread, not other lines', nt.feed() = 'trip*,l1*,company*', nt.feed());
  PERFORM nt.ok('F2 marking one read', public.mark_notifications_read(ARRAY[nt.sent_id('company')]) = 1
    AND nt.feed() = 'trip*,l1*,company', nt.feed());
  PERFORM nt.ok('F3 marking all read', public.mark_notifications_read() = 2 AND nt.feed() = 'trip,l1,company', nt.feed());
END $$;
SELECT nt.login('s4');
DO $$ BEGIN PERFORM nt.ok('F4 another line''s student', nt.feed() = 'l2*,company*', nt.feed()); END $$;
SELECT nt.login('s5');
DO $$ BEGIN PERFORM nt.ok('F5 an ended subscription receives nothing', nt.feed() = '', nt.feed()); END $$;
SELECT nt.login('s6');
DO $$ BEGIN PERFORM nt.ok('F6 another company''s student receives nothing', nt.feed() = '', nt.feed()); END $$;
SELECT nt.login('SA');
DO $$ BEGIN
  PERFORM nt.ok('F7 supervisor: what the admin sent (unread) and what they sent (read)',
    nt.feed() = 'trip,l1,company*', nt.feed());
END $$;
SELECT nt.login('SB');
DO $$ BEGIN PERFORM nt.ok('F8 supervisor of the other line', nt.feed() = 'l2*,company*', nt.feed()); END $$;

SELECT nt.login('AA');
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(format('%s %s/%s %s', s.name, x->>'read', x->>'students', x->>'sender_role'), ', ' ORDER BY i)
  INTO v FROM jsonb_array_elements(public.get_company_notifications(nt.id('co_a'))) WITH ORDINALITY e(x, i)
  JOIN nt.sent s ON s.id = (x->>'id')::uuid;
  PERFORM nt.ok('F9 the admin sees everything sent, with students read / received',
    v = 'trip 1/1 supervisor, l1 1/4 supervisor, l2 0/1 admin, company 1/5 admin', v);
END $$;

-- =============================================================================
-- Live update, deleting
-- =============================================================================
RESET ROLE;
DO $$ BEGIN
  PERFORM nt.ok('R1 a company notification is announced to the company and every line',
    (SELECT string_agg(DISTINCT m.topic, ',' ORDER BY m.topic) FROM realtime.messages m
     WHERE m.payload->>'id' = nt.sent_id('company')::text)
      = format('company:%s,line:%s,line:%s', nt.id('co_a'), nt.id('L1'), nt.id('L2')));
  PERFORM nt.ok('R2 a trip notification only to the company and its line',
    (SELECT string_agg(DISTINCT m.topic, ',' ORDER BY m.topic) FROM realtime.messages m
     WHERE m.payload->>'id' = nt.sent_id('trip')::text)
      = format('company:%s,line:%s', nt.id('co_a'), nt.id('L1')));
END $$;

SET LOCAL ROLE authenticated;
SELECT nt.login('SA');
DO $$ BEGIN
  PERFORM nt.ok('D1 a supervisor cannot delete', nt.err(format('SELECT public.delete_notification(%L)', nt.sent_id('trip'))) IS NOT NULL);
END $$;
SELECT nt.login('AA');
SELECT public.delete_notification(nt.sent_id('trip'));
SELECT nt.login('s1');
DO $$ BEGIN PERFORM nt.ok('D2 the admin deletes it for everyone', nt.feed() = 'l1,company', nt.feed()); END $$;

-- =============================================================================
-- Supervisor photos
-- =============================================================================
SELECT nt.login('AA');
DO $$ BEGIN
  PERFORM nt.ok('P1 the company admin uploads the supervisor''s photo and saves its path',
    nt.err(format('INSERT INTO storage.objects (bucket_id, name) VALUES (''supervisor-avatars'', %L)', nt.id('SA') || '/1.jpg')) IS NULL
    AND nt.err(format('UPDATE public.supervisors SET profile_image_url = %L WHERE id = %L', nt.id('SA') || '/1.jpg', nt.id('SA'))) IS NULL);
END $$;
SELECT nt.login('AB');
DO $$ BEGIN
  PERFORM nt.ok('P2 another company''s admin cannot upload or see it',
    nt.err(format('INSERT INTO storage.objects (bucket_id, name) VALUES (''supervisor-avatars'', %L)', nt.id('SA') || '/2.jpg')) IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'supervisor-avatars'));
END $$;
CREATE FUNCTION pg_temp.sees_photo() RETURNS boolean LANGUAGE sql AS
  $$ SELECT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'supervisor-avatars') $$;
SELECT nt.login('SA');
DO $$ BEGIN PERFORM nt.ok('P3 the supervisor sees their photo', pg_temp.sees_photo()); END $$;
SELECT nt.login('s1');
DO $$ BEGIN
  PERFORM nt.ok('P4 a student riding the supervisor''s line sees the photo and its path',
    pg_temp.sees_photo() AND (SELECT profile_image_url FROM public.supervisors WHERE id = nt.id('SA')) IS NOT NULL);
END $$;
SELECT nt.login('s4');
DO $$ BEGIN PERFORM nt.ok('P5 a student of another line does not', NOT pg_temp.sees_photo()); END $$;
SELECT nt.login('SB');
DO $$ BEGIN PERFORM nt.ok('P6 another supervisor does not', NOT pg_temp.sees_photo()); END $$;

-- =============================================================================
-- Check-in: the day's vote
-- =============================================================================
SELECT nt.login('SA');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.supervisor_check_in_student((SELECT qr_code_value FROM public.students WHERE id = nt.id('s1')), 'departure', nt.id('D1'));
  PERFORM nt.ok('V1 the scan shows the vote with the chosen time',
    (r->'ride_vote'->>'is_riding')::boolean AND r->'ride_vote'->>'departure_time' = '07:10:00'
      AND NOT (r->'ride_vote'->>'is_returning')::boolean, r->>'ride_vote');
  r := public.supervisor_check_in_student((SELECT qr_code_value FROM public.students WHERE id = nt.id('s7')), 'departure', nt.id('D1'));
  PERFORM nt.ok('V2 no vote: ride_vote is null', r->>'result' = 'checked_in' AND r ? 'ride_vote'
    AND jsonb_typeof(r->'ride_vote') = 'null', r::text);
END $$;
RESET ROLE;

-- =============================================================================
\o
\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, step, detail FROM nt.results ORDER BY n;
DO $$ DECLARE f int; BEGIN
  SELECT count(*) INTO f FROM nt.results WHERE NOT ok;
  IF f > 0 THEN RAISE EXCEPTION '% test step(s) failed', f; END IF;
  RAISE NOTICE 'all % steps passed', (SELECT count(*) FROM nt.results);
END $$;
ROLLBACK;
