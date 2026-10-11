-- Test of 20261119000004_term_recap_release (term_recap_releases,
-- platform_publish_term_recap, platform_unpublish_term_recap,
-- platform_term_recap_overview, get_my_term_recap's `published`).
-- Plain SQL, one transaction, rolled back: run it after the migration, or paste
-- the migration (without its BEGIN/COMMIT) right after the BEGIN below. Nothing
-- persists. The last statement lists every check; all must say ok = true.
-- (Run on 2026-10-10 against hnwpkkryxovhmsrokdsd with the migration pasted in and
-- a RAISE in place of the last SELECT so the transaction could only roll back:
-- 35 of 35 ok; nothing persisted.)
--
-- Fixture (triggers off while it is written): company A (active) with line LA
-- (two stations, a departure trip) and students s1, s2 (university U1) on a paid
-- «first 2026» subscription; s1 rode 5 days (3 boarded going, 1 coming back),
-- s2 rode 2 days at the other station. Company B is active with nobody. A
-- platform admin, a company admin of A.
-- The platform's numbers include every real company too, so the checks look at
-- this fixture's own rows (its line, stations, company) inside the answer.
BEGIN;

CREATE SCHEMA tr;
GRANT USAGE ON SCHEMA tr TO authenticated, anon;
CREATE TABLE tr.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE FUNCTION tr.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO tr.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION tr.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE; END $$;
CREATE TABLE tr.out (who text PRIMARY KEY, body jsonb);
CREATE FUNCTION tr.keep(p_who text, p_body jsonb) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO tr.out VALUES (p_who, p_body) ON CONFLICT (who) DO UPDATE SET body = excluded.body RETURNING body $$;
CREATE FUNCTION tr.got(p_who text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT body FROM tr.out WHERE who = p_who $$;
CREATE FUNCTION tr.login(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tr TO authenticated, anon;
GRANT INSERT, SELECT, UPDATE ON tr.results, tr.out TO authenticated;
GRANT USAGE ON SEQUENCE tr.results_n_seq TO authenticated;

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, email)
SELECT ('7f000000-0000-4000-8000-0000000000' || x)::uuid, 'tr-' || x || '@example.invalid'
FROM unnest(ARRAY['a5', 'aa', '51', '52']) x;

INSERT INTO public.companies (id, name, status, is_active) VALUES
  ('7f000000-0000-4000-8000-00000000c00a', 'اختبار الملخص أ', 'active', true),
  ('7f000000-0000-4000-8000-00000000c00b', 'اختبار الملخص ب', 'active', true);
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  ('7f000000-0000-4000-8000-0000000000a5', 'tr-a5@example.invalid', 'مدير المنصة', 'super_admin', NULL, NULL),
  ('7f000000-0000-4000-8000-0000000000aa', 'tr-aa@example.invalid', 'مدير أ', 'company_admin', '7f000000-0000-4000-8000-00000000c00a', '7f000000-0000-4000-8000-0000000000a5');
INSERT INTO public.universities (id, name, city, is_active) VALUES
  ('7f000000-0000-4000-8000-0000000000f1', 'جامعة اختبار الملخص', 'دمياط', true);
INSERT INTO public.lines (id, company_id, name, origin_name, destination_university_id, price_termly, price_yearly, price_daily, is_active) VALUES
  ('7f000000-0000-4000-8000-00000000a001', '7f000000-0000-4000-8000-00000000c00a', 'خط الملخص', 'البداية', '7f000000-0000-4000-8000-0000000000f1', 3500, 6500, 0, true);
INSERT INTO public.stations (id, line_id, name, order_index, company_id, is_active) VALUES
  ('7f000000-0000-4000-8000-00000000b001', '7f000000-0000-4000-8000-00000000a001', 'محطة الملخص 1', 0, '7f000000-0000-4000-8000-00000000c00a', true),
  ('7f000000-0000-4000-8000-00000000b002', '7f000000-0000-4000-8000-00000000a001', 'محطة الملخص 2', 1, '7f000000-0000-4000-8000-00000000c00a', true);
INSERT INTO public.line_trips (id, line_id, company_id, direction, label, start_time, university_id, is_active) VALUES
  ('7f000000-0000-4000-8000-00000000d001', '7f000000-0000-4000-8000-00000000a001', '7f000000-0000-4000-8000-00000000c00a', 'departure', 'الأولى', '07:00', NULL, true);
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time, company_id) VALUES
  ('7f000000-0000-4000-8000-00000000d001', '7f000000-0000-4000-8000-00000000b001', '07:00', '7f000000-0000-4000-8000-00000000c00a'),
  ('7f000000-0000-4000-8000-00000000d001', '7f000000-0000-4000-8000-00000000b002', '07:15', '7f000000-0000-4000-8000-00000000c00a');

INSERT INTO public.students (id, phone, full_name, university, college, university_id)
SELECT ('7f000000-0000-4000-8000-0000000000' || x)::uuid, '0109997000' || right(x, 1), 'طالب ' || x, 'جامعة اختبار الملخص', 'الهندسة',
       '7f000000-0000-4000-8000-0000000000f1'
FROM unnest(ARRAY['51', '52']) x;
INSERT INTO public.company_students (company_id, student_id, status)
SELECT '7f000000-0000-4000-8000-00000000c00a', ('7f000000-0000-4000-8000-0000000000' || x)::uuid, 'active' FROM unnest(ARRAY['51', '52']) x;
INSERT INTO public.subscriptions (id, student_id, company_id, line_id, station_id, type, status, start_date, end_date, price,
                                  paid_at, period_code, academic_year, departure_trip_id, departure_time, return_time, created_at)
VALUES
  ('7f000000-0000-4000-8000-0000000005b1', '7f000000-0000-4000-8000-000000000051', '7f000000-0000-4000-8000-00000000c00a',
   '7f000000-0000-4000-8000-00000000a001', '7f000000-0000-4000-8000-00000000b001', 'termly', 'active', '2026-09-05', '2027-01-30', 3500,
   now() - interval '40 days', 'first', 2026, '7f000000-0000-4000-8000-00000000d001', '07:00', '14:00', now() - interval '40 days'),
  ('7f000000-0000-4000-8000-0000000005b2', '7f000000-0000-4000-8000-000000000052', '7f000000-0000-4000-8000-00000000c00a',
   '7f000000-0000-4000-8000-00000000a001', '7f000000-0000-4000-8000-00000000b002', 'termly', 'active', '2026-09-05', '2027-01-30', 3500,
   now() - interval '40 days', 'first', 2026, '7f000000-0000-4000-8000-00000000d001', '07:15', '14:00', now() - interval '40 days');
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, is_returning, company_id, subscription_id)
SELECT '7f000000-0000-4000-8000-000000000051'::uuid, d, true, d = date '2026-09-20', '7f000000-0000-4000-8000-00000000c00a'::uuid, '7f000000-0000-4000-8000-0000000005b1'::uuid
FROM unnest(ARRAY[date '2026-09-20', '2026-09-21', '2026-09-22', '2026-09-23', '2026-09-24']) d
UNION ALL
SELECT '7f000000-0000-4000-8000-000000000052'::uuid, d, true, false, '7f000000-0000-4000-8000-00000000c00a'::uuid, '7f000000-0000-4000-8000-0000000005b2'::uuid
FROM unnest(ARRAY[date '2026-09-20', '2026-09-21']) d
UNION ALL -- a day off does not count
SELECT '7f000000-0000-4000-8000-000000000052', date '2026-09-22', false, false, '7f000000-0000-4000-8000-00000000c00a', '7f000000-0000-4000-8000-0000000005b2';
INSERT INTO public.supervisor_scan_events (company_id, line_id, trip_id, station_id, student_id, subscription_id, ride_date, direction, result, scanned_at)
SELECT '7f000000-0000-4000-8000-00000000c00a', '7f000000-0000-4000-8000-00000000a001', '7f000000-0000-4000-8000-00000000d001',
       '7f000000-0000-4000-8000-00000000b001', '7f000000-0000-4000-8000-000000000051', '7f000000-0000-4000-8000-0000000005b1',
       d, dir, 'checked_in', d + time '07:05'
FROM (VALUES (date '2026-09-20', 'departure'), ('2026-09-21', 'departure'), ('2026-09-22', 'departure'), ('2026-09-20', 'return')) v(d, dir);

SET LOCAL session_replication_role = origin;

-- =============================================================================
-- Who may call
-- =============================================================================
SET LOCAL ROLE anon;
SELECT tr.ok('anon cannot publish', tr.err($$SELECT public.platform_publish_term_recap(2026, 'first', NULL)$$) = '42501');
SELECT tr.ok('anon cannot read the overview', tr.err($$SELECT public.platform_term_recap_overview(2026, 'first')$$) = '42501');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT tr.login('7f000000-0000-4000-8000-0000000000aa');
SELECT tr.ok('a company admin cannot publish (42501)', tr.err($$SELECT public.platform_publish_term_recap(2026, 'first', NULL)$$) = '42501');
SELECT tr.ok('a company admin cannot stop it (42501)', tr.err($$SELECT public.platform_unpublish_term_recap(2026, 'first')$$) = '42501');
SELECT tr.ok('a company admin cannot read the overview (42501)', tr.err($$SELECT public.platform_term_recap_overview(2026, 'first')$$) = '42501');
SELECT tr.ok('a company admin cannot write the table', tr.err($$INSERT INTO public.term_recap_releases (academic_year, period_code, published_at) VALUES (2026, 'first', now())$$) = '42501');
SELECT tr.ok('a company admin can read releases (none yet)', tr.err($$SELECT count(*) FROM public.term_recap_releases$$) IS NULL);

SELECT tr.login('7f000000-0000-4000-8000-000000000051');
SELECT tr.ok('a student cannot publish (42501)', tr.err($$SELECT public.platform_publish_term_recap(2026, 'first', NULL)$$) = '42501');
SELECT tr.keep('recap before', public.get_my_term_recap());
SELECT tr.ok('student before: published = false, no message, the rest as before',
             (SELECT body->'published' = 'false'::jsonb AND body->'published_message' = 'null'::jsonb
                     AND jsonb_array_length(body->'rides') = 5 AND (body->'summary'->>'boarded_departures')::int = 3
                     AND (body->'summary'->>'boarded_returns')::int = 1 AND body->'term'->>'code' = 'first'
                     AND (body->'term'->>'academic_year')::int = 2026
                     AND body ?& ARRAY['today', 'student', 'term', 'range', 'subscription', 'rides', 'summary', 'line', 'stop', 'timetable', 'trip_length', 'off']
              FROM tr.out WHERE who = 'recap before'), (SELECT (body - 'rides')::text FROM tr.out WHERE who = 'recap before'));

-- =============================================================================
-- The overview
-- =============================================================================
SELECT tr.login('7f000000-0000-4000-8000-0000000000a5');
SELECT tr.ok('bad term refused (22023)', tr.err($$SELECT public.platform_term_recap_overview(2026, 'both')$$) = '22023');
SELECT tr.keep('default', public.platform_term_recap_overview());
SELECT tr.keep('overview', public.platform_term_recap_overview(2026, 'first'));
SELECT tr.ok('no term given: first 2026 (the last that started, no window open on 10 October)',
             (SELECT body->'term'->>'period_code' = 'first' AND (body->'term'->>'academic_year')::int = 2026 FROM tr.out WHERE who = 'default'),
             (SELECT (body->'term')::text FROM tr.out WHERE who = 'default'));
SELECT tr.ok('term: dates, window, label',
             (SELECT body->'term'->>'start_date' = '2026-09-05' AND body->'term'->>'end_date' = '2027-01-30'
                     AND body->'term'->>'window_opens' = '2027-01-16' AND body->'term'->>'window_closes' = '2027-02-27'
                     AND body->'term'->>'label' LIKE '%2026/2027' FROM tr.out WHERE who = 'overview'),
             (SELECT (body->'term')::text FROM tr.out WHERE who = 'overview'));
SELECT tr.ok('company A: 2 students, 7 ride days, 4 boardings',
             (SELECT (c->>'students')::int = 2 AND (c->>'ride_days')::int = 7 AND (c->>'boardings')::int = 4
              FROM tr.out, jsonb_array_elements(body->'companies') c WHERE who = 'overview' AND c->>'id' = '7f000000-0000-4000-8000-00000000c00a'),
             (SELECT (body->'companies')::text FROM tr.out WHERE who = 'overview'));
SELECT tr.ok('company B (no rides) is not listed',
             (SELECT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(body->'companies') c WHERE c->>'id' = '7f000000-0000-4000-8000-00000000c00b')
              FROM tr.out WHERE who = 'overview'));
SELECT tr.ok('totals hold at least the fixture, and every key is there',
             (SELECT (t->>'students')::int >= 2 AND (t->>'ride_days')::int >= 7 AND (t->>'boardings')::int >= 4 AND (t->>'return_days')::int >= 1
                     AND (t->>'companies')::int >= 1 AND t ?& ARRAY['lines', 'stations', 'universities', 'median_ride_days']
              FROM tr.out, LATERAL (SELECT body->'totals' AS t) x WHERE who = 'overview'),
             (SELECT (body->'totals')::text FROM tr.out WHERE who = 'overview'));
SELECT tr.ok('the line: 2 students, 7 days, with its company (when among the top 5)',
             (SELECT COALESCE(bool_and((l->>'students')::int = 2 AND (l->>'ride_days')::int = 7 AND l->>'company_name' = 'اختبار الملخص أ'), true)
              FROM tr.out, jsonb_array_elements(body->'top_lines') l WHERE who = 'overview' AND l->>'id' = '7f000000-0000-4000-8000-00000000a001'));
SELECT tr.ok('stations: s1''s stop 5 days, s2''s 2 (when among the top 5)',
             (SELECT COALESCE(bool_and(CASE s->>'id' WHEN '7f000000-0000-4000-8000-00000000b001' THEN (s->>'ride_days')::int = 5 AND s->>'line_name' = 'خط الملخص'
                                                       ELSE (s->>'ride_days')::int = 2 END), true)
              FROM tr.out, jsonb_array_elements(body->'top_stations') s WHERE who = 'overview'
                AND s->>'id' IN ('7f000000-0000-4000-8000-00000000b001', '7f000000-0000-4000-8000-00000000b002')));
SELECT tr.ok('options list the started terms, newest first, with published = false',
             (SELECT jsonb_array_length(body->'options') >= 2 AND body->'options'->0->>'period_code' = 'first'
                     AND (body->'options'->0->>'academic_year')::int = 2026 AND body->'options'->0->'published' = 'false'::jsonb
              FROM tr.out WHERE who = 'overview'), (SELECT (body->'options')::text FROM tr.out WHERE who = 'overview'));
SELECT tr.ok('no release yet; reach counts A''s students',
             (SELECT body->'release' = 'null'::jsonb AND (body->'reach'->>'students')::int >= 2 AND (body->'reach'->>'companies')::int >= 1
              FROM tr.out WHERE who = 'overview'), (SELECT (body->'reach')::text FROM tr.out WHERE who = 'overview'));

-- =============================================================================
-- Publishing
-- =============================================================================
SELECT tr.ok('a 601-character message is refused (22023)', tr.err(format($$SELECT public.platform_publish_term_recap(2026, 'first', %L)$$, repeat('أ', 601))) = '22023');
SELECT tr.ok('stopping what was never published: P0002', tr.err($$SELECT public.platform_unpublish_term_recap(2026, 'first')$$) = 'P0002');
SELECT tr.keep('publish', public.platform_publish_term_recap(2026, 'first', 'ملخصك جاهز، شاركه مع أصحابك.'));
SELECT tr.ok('publish: published, notified now, A counted',
             (SELECT (body->>'published')::boolean AND (body->>'notified_now')::boolean AND body->>'notified_at' IS NOT NULL
                     AND (body->>'notified_students')::int >= 2 AND body->>'published_by_name' = 'مدير المنصة'
                     AND body->>'message' = 'ملخصك جاهز، شاركه مع أصحابك.' FROM tr.out WHERE who = 'publish'),
             (SELECT body::text FROM tr.out WHERE who = 'publish'));
RESET ROLE;
SELECT tr.ok('one notification for company A, to its students, route recap',
             (SELECT count(*) = 1 AND bool_and(n.title = 'ملخص فصلك جاهز' AND n.type = 'announcement.platform' AND n.status = 'sent'
                                               AND n.data->>'route' = 'recap' AND n.data->>'period_code' = 'first' AND n.data->>'academic_year' = '2026'
                                               AND n.body = 'ملخصك جاهز، شاركه مع أصحابك.')
              FROM public.notifications n WHERE n.company_id = '7f000000-0000-4000-8000-00000000c00a'));
SELECT tr.ok('both students received it',
             (SELECT count(DISTINCT r.user_id) = 2 FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id = n.id
              WHERE n.company_id = '7f000000-0000-4000-8000-00000000c00a' AND r.is_student));
SELECT tr.ok('company B (no students) got none',
             (SELECT count(*) = 0 FROM public.notifications n WHERE n.company_id = '7f000000-0000-4000-8000-00000000c00b'));
SET LOCAL ROLE authenticated;

SELECT tr.keep('publish again', public.platform_publish_term_recap(2026, 'first', NULL));
SELECT tr.ok('publish again: still published since the first time, message cleared, nothing sent',
             (SELECT (body->>'published')::boolean AND NOT (body->>'notified_now')::boolean AND body->>'message' IS NULL
                     AND body->>'published_at' = tr.got('publish')->>'published_at' FROM tr.out WHERE who = 'publish again'));
SELECT tr.keep('overview after', public.platform_term_recap_overview(2026, 'first'));
SELECT tr.ok('overview shows the release and the option as published',
             (SELECT (body->'release'->>'published')::boolean AND body->'options'->0->'published' = 'true'::jsonb
              FROM tr.out WHERE who = 'overview after'));

SELECT tr.login('7f000000-0000-4000-8000-000000000052');
SELECT tr.keep('recap s2 published', public.get_my_term_recap());
SELECT tr.ok('student: published = true; the message empty after it was cleared',
             (SELECT body->'published' = 'true'::jsonb AND body->'published_message' = 'null'::jsonb AND jsonb_array_length(body->'rides') = 2
              FROM tr.out WHERE who = 'recap s2 published'));
SELECT tr.ok('a student reads the release row too', (SELECT count(*) = 1 FROM public.term_recap_releases WHERE academic_year = 2026));

SELECT tr.login('7f000000-0000-4000-8000-0000000000a5');
SELECT public.platform_publish_term_recap(2026, 'first', 'رسالة ثانية');
SELECT tr.login('7f000000-0000-4000-8000-000000000051');
SELECT tr.ok('student: the message follows', (SELECT public.get_my_term_recap()->>'published_message' = 'رسالة ثانية'));

-- =============================================================================
-- Stopping
-- =============================================================================
SELECT tr.login('7f000000-0000-4000-8000-0000000000a5');
SELECT tr.keep('unpublish', public.platform_unpublish_term_recap(2026, 'first'));
SELECT tr.ok('unpublish: not published, stamped',
             (SELECT NOT (body->>'published')::boolean AND body->>'unpublished_at' IS NOT NULL FROM tr.out WHERE who = 'unpublish'));
SELECT tr.login('7f000000-0000-4000-8000-000000000051');
SELECT tr.ok('student after stopping: published = false, no message',
             (SELECT r->'published' = 'false'::jsonb AND r->'published_message' = 'null'::jsonb FROM (SELECT public.get_my_term_recap() r) x));
SELECT tr.login('7f000000-0000-4000-8000-0000000000a5');
SELECT tr.keep('republish', public.platform_publish_term_recap(2026, 'first', NULL));
SELECT tr.ok('republish: published again, a new published_at, no second notification',
             (SELECT (body->>'published')::boolean AND NOT (body->>'notified_now')::boolean AND body->>'unpublished_at' IS NULL
              FROM tr.out WHERE who = 'republish'));
RESET ROLE;
SELECT tr.ok('still one notification for company A',
             (SELECT count(*) = 1 FROM public.notifications n WHERE n.company_id = '7f000000-0000-4000-8000-00000000c00a'));
SELECT tr.ok('another term is not published', (SELECT NOT EXISTS (SELECT 1 FROM public.term_recap_releases WHERE academic_year = 2026 AND period_code = 'second')));

-- 20261121000001: each change of what students see is told to their phones.
SELECT tr.ok('publishing, stopping and publishing again each reach every line''s topic once',
             (SELECT count(DISTINCT m.topic) >= 1 AND count(*) = 3 * count(DISTINCT m.topic)
              FROM realtime.messages m WHERE m.payload->>'table' = 'term_recap_releases' AND m.topic LIKE 'line:%'),
             (SELECT count(*) || ' messages on ' || count(DISTINCT m.topic) || ' line topics'
              FROM realtime.messages m WHERE m.payload->>'table' = 'term_recap_releases' AND m.topic LIKE 'line:%'));
UPDATE public.term_recap_releases SET message = 'كلمة جديدة' WHERE academic_year = 2026 AND period_code = 'first';
SELECT tr.ok('a change that students do not see (the message alone) is not announced',
             (SELECT count(*) = 3 * count(DISTINCT m.topic)
              FROM realtime.messages m WHERE m.payload->>'table' = 'term_recap_releases' AND m.topic LIKE 'line:%'));

SELECT n, step, ok, detail FROM tr.results ORDER BY n;
ROLLBACK;
