-- End-to-end test of 20261031000001_notification_system. Run by run_local.sh
-- after every migration; one transaction, rolled back at the end. Every step
-- runs with the role + JWT claims PostgREST would use for that user.
--
-- Same fixture as e2e_notifications.sql. Company A: line L1 (trips D1, D2),
-- line L2 (trip X2); admin AA; supervisors SA and SC on L1, SB on L2; students
-- s1, s2, s7 (L1, active), s3 (L1, awaiting payment), s4 (L2), s5 (ended).
-- Company B: line LB, admin AB, student s6. s1 and s4 study at one university.
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


INSERT INTO public.universities (id, name) VALUES ('e9800000-0000-0000-0000-000000000001', 'جامعة الاختبار');
UPDATE public.students SET university_id = 'e9800000-0000-0000-0000-000000000001' WHERE id IN (nt.id('s1'), nt.id('s4'));
GRANT USAGE ON SCHEMA nt TO service_role;
GRANT SELECT ON nt.sent TO service_role;

-- "phone,tablet": the installs registered for an account.
CREATE FUNCTION nt.devices(p_name text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(string_agg(d.installation_id, ',' ORDER BY d.installation_id), '')
  FROM public.push_devices d WHERE d.user_id = nt.id(p_name) $$;
-- "s1:queued,s2:skipped": the pushes of a notification.
CREATE FUNCTION nt.outbox(p_name text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(string_agg(x.name || ':' || o.status, ',' ORDER BY x.name COLLATE "C", o.status), '')
  FROM public.push_outbox o JOIN nt.names x ON x.id = o.user_id WHERE o.notification_id = nt.sent_id(p_name) $$;
CREATE FUNCTION nt.status(p_name text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
  $$ SELECT status FROM public.notifications WHERE id = nt.sent_id(p_name) $$;
-- "subscription.approved,…": the automatic notifications an account received, oldest first.
CREATE FUNCTION nt.system_for(p_name text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(string_agg(n.type, ',' ORDER BY n.sent_at), '')
  FROM public.notifications n JOIN public.notification_recipients r ON r.notification_id = n.id
  WHERE n.sender_role = 'system' AND r.user_id = nt.id(p_name) $$;
-- The ids on a page of the signed-in user's notifications, as sent names.
CREATE FUNCTION nt.page_names(p_page jsonb) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(string_agg(COALESCE(s.name, '?'), ',' ORDER BY i), '')
  FROM jsonb_array_elements(p_page->'items') WITH ORDINALITY e(f, i)
  LEFT JOIN nt.sent s ON s.id = (f->>'id')::uuid $$;
CREATE FUNCTION nt.force_due(p_name text) RETURNS void LANGUAGE sql SECURITY DEFINER AS
  $$ UPDATE public.notifications SET scheduled_at = now() - interval '1 minute' WHERE id = nt.sent_id(p_name) $$;
CREATE FUNCTION nt.opened(p_name text, p_user text) RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT r.opened_at IS NOT NULL AND r.read_at IS NOT NULL FROM public.notification_recipients r
  WHERE r.notification_id = nt.sent_id(p_name) AND r.user_id = nt.id(p_user) $$;
CREATE FUNCTION nt.note(p_name text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS
  $$ SELECT to_jsonb(x) FROM public.notifications x WHERE x.id = nt.sent_id(p_name) $$;
CREATE FUNCTION nt.tick() RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ SELECT public.notifications_tick() $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nt TO authenticated, service_role;

-- =============================================================================
-- Devices and preferences
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT nt.login('s1');
DO $$
BEGIN
  PERFORM public.register_push_device('install-phone', 'ios', repeat('a', 40), 'ar', '1.0.6');
  PERFORM public.register_push_device('install-tablet', 'android', repeat('b', 40), 'en', '1.0.6');
  PERFORM public.register_push_device('install-phone', 'ios', repeat('a', 40), 'ar', '1.0.6');
  PERFORM nt.ok('P1 an account has a row per install, however often it registers',
    nt.devices('s1') = 'install-phone,install-tablet', nt.devices('s1'));
  PERFORM nt.ok('P2 a device that is neither iOS nor Android is refused',
    nt.err($q$SELECT public.register_push_device('install-web0', 'web', repeat('z', 40))$q$) IS NOT NULL);
  PERFORM nt.ok('P3 the tables cannot be read directly',
    nt.err('SELECT 1 FROM public.push_devices') LIKE '%permission denied%'
    AND nt.err('SELECT 1 FROM public.push_outbox') LIKE '%permission denied%'
    AND nt.err('SELECT 1 FROM public.notification_preferences') LIKE '%permission denied%'
    AND nt.err('SELECT 1 FROM public.notification_audit') LIKE '%permission denied%'
    AND nt.err('SELECT 1 FROM public.push_runtime') LIKE '%permission denied%'
    AND nt.err('SELECT 1 FROM public.notification_templates') LIKE '%permission denied%');
  PERFORM nt.ok('P4 the dispatcher''s functions and the tick are not for signed-in users',
    nt.err('SELECT public.claim_push_outbox()') LIKE '%permission denied%'
    AND nt.err($q$SELECT public.complete_push_outbox('[]')$q$) LIKE '%permission denied%'
    AND nt.err('SELECT public.set_push_configured(true)') LIKE '%permission denied%'
    AND nt.err('SELECT public.notifications_tick()') LIKE '%permission denied%'
    AND nt.err($q$SELECT public.notify_student(NULL, NULL, 'x', NULL, NULL)$q$) LIKE '%permission denied%'
    AND nt.err('SELECT public.notification_deliver(gen_random_uuid())') LIKE '%permission denied%');
  PERFORM nt.ok('P5 preferences start with everything on',
    public.get_notification_preferences() = '{"push_enabled": true, "categories": {"subscription": true, "transport": true, "announcement": true, "reminder": true}}'::jsonb,
    public.get_notification_preferences()::text);
END $$;

-- The same phone, another account signs in: the token moves, it is never shared.
SELECT nt.login('s3');
DO $$
BEGIN
  PERFORM public.register_push_device('install-phone', 'ios', repeat('a', 40));
  PERFORM nt.ok('P6 a phone belongs to the account signed in on it now',
    nt.devices('s3') = 'install-phone' AND nt.devices('s1') = 'install-tablet', nt.devices('s1') || ' / ' || nt.devices('s3'));
  PERFORM public.unregister_push_device('install-tablet');
  PERFORM nt.ok('P7 signing out removes only one''s own device', nt.devices('s1') = 'install-tablet');
  PERFORM public.unregister_push_device('install-phone');
  PERFORM nt.ok('P8 signed out: no device left for the account', nt.devices('s3') = '');
END $$;
SELECT nt.login('s1');
SELECT public.register_push_device('install-phone', 'ios', repeat('a', 40));
SELECT nt.login('s2');
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM public.register_push_device('install-s2-phone', 'android', repeat('c', 40));
  r := public.set_notification_preferences(true, '{"announcement": false, "hack": true, "transport": "no"}');
  PERFORM nt.ok('P9 only known categories with true or false are kept',
    r->'categories' = '{"subscription": true, "transport": true, "announcement": false, "reminder": true}'::jsonb, r::text);
END $$;
SELECT nt.login('s6');
SELECT public.register_push_device('install-s6-phone', 'android', repeat('d', 40));

-- =============================================================================
-- Dashboard: preview, send, idempotency, outbox
-- =============================================================================
SELECT nt.login('AA');
DO $$
DECLARE r jsonb; r2 jsonb;
BEGIN
  r := public.preview_notification_audience(nt.id('co_a'), '{"kind": "company"}');
  PERFORM nt.ok('C1 preview of the company: students, supervisors and devices, from the server',
    r = '{"label": "كل طلاب الشركة", "students": 5, "supervisors": 3, "devices": 3}'::jsonb, r::text);
  PERFORM nt.ok('C2 a line of another company is not an audience',
    nt.err(format($q$SELECT public.preview_notification_audience(%L, '{"kind": "line", "line_id": "%s"}')$q$,
      nt.id('co_a'), nt.id('LB'))) LIKE '%الخط غير موجود%');
  PERFORM nt.ok('C3 one person cannot be chosen from the dashboard',
    nt.err(format($q$SELECT public.compose_notification(%L, 'x', 'y', '{"kind": "user", "user_id": "%s"}')$q$,
      nt.id('co_a'), nt.id('s1'))) LIKE '%اختر من يصلهم%');

  r := nt.keep('now', public.compose_notification(nt.id('co_a'), 'تنبيه', 'نص التنبيه.', '{"kind": "company"}',
                                                  p_idempotency_key := 'key-1', p_priority := 'high'));
  r2 := public.compose_notification(nt.id('co_a'), 'تنبيه', 'نص التنبيه.', '{"kind": "company"}', p_idempotency_key := 'key-1');
  PERFORM nt.ok('C4 sent now; the same key again is the same notification, not a second one',
    r->>'status' = 'sent' AND (r->>'students')::int = 5 AND NOT (r->>'duplicate')::boolean
    AND (r2->>'duplicate')::boolean AND r2->>'id' = r->>'id' AND (r2->>'students')::int = 5, r::text || r2::text);
  PERFORM nt.ok('C5 a push per device; skipped where the student turned the category off',
    nt.outbox('now') = 's1:queued,s1:queued,s2:skipped', nt.outbox('now'));
END $$;

SELECT nt.login('AB');
DO $$
BEGIN
  PERFORM nt.ok('C6 another company''s admin can neither preview, send, schedule nor list',
    nt.err(format($q$SELECT public.preview_notification_audience(%L, '{"kind": "company"}')$q$, nt.id('co_a'))) LIKE '%لا يمكنك%'
    AND nt.err(format($q$SELECT public.compose_notification(%L, 'x', 'y', '{"kind": "company"}')$q$, nt.id('co_a'))) LIKE '%لا يمكنك%'
    AND nt.err(format($q$SELECT public.compose_notification(%L, 'x', 'y', '{"kind": "company"}', now() + interval '1 hour')$q$, nt.id('co_a'))) LIKE '%لا يمكنك%'
    AND nt.err(format('SELECT public.get_company_notifications_page(%L)', nt.id('co_a'))) LIKE '%لا يمكنك%');
  PERFORM nt.ok('C7 nor write to their own company through a line of another',
    nt.err(format($q$SELECT public.compose_notification(%L, 'x', 'y', '{"kind": "line", "line_id": "%s"}')$q$,
      nt.id('co_b'), nt.id('L1'))) LIKE '%الخط غير موجود%');
END $$;

-- =============================================================================
-- The dispatcher
-- =============================================================================
SET LOCAL ROLE service_role;
DO $$
DECLARE a jsonb; b jsonb; c jsonb;
BEGIN
  a := public.claim_push_outbox(1);
  b := public.claim_push_outbox();
  c := public.claim_push_outbox();
  PERFORM nt.ok('D1 each push is handed out once', jsonb_array_length(a) = 1 AND jsonb_array_length(b) = 1
    AND jsonb_array_length(c) = 0 AND a->0->>'id' <> b->0->>'id', a::text);
  PERFORM nt.ok('D2 a claimed push carries the text, ids only in data, the type and the unread count',
    a->0->>'title' = 'تنبيه' AND a->0->>'type' = 'announcement.admin' AND a->0->>'category' = 'announcement'
    AND a->0->>'priority' = 'high' AND a->0->'data' = '{"route": "notifications"}'::jsonb
    AND (a->0->>'badge')::int = 1 AND a->0->>'token' IN (repeat('a', 40), repeat('b', 40))
    AND a->0->>'notification_id' = nt.sent_id('now')::text, (a->0)::text);
  PERFORM public.complete_push_outbox(jsonb_build_array(
    jsonb_build_object('id', a->0->'id', 'status', 'accepted', 'message_id', 'projects/x/messages/1'),
    jsonb_build_object('id', b->0->'id', 'status', 'invalid_token', 'error', 'UNREGISTERED')));
  PERFORM nt.ok('D3 accepted by the provider, and failed for a dead token',
    nt.outbox('now') = 's1:accepted,s1:failed,s2:skipped', nt.outbox('now'));
  PERFORM public.set_push_configured(true);
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM nt.ok('D4 the dead token''s device is switched off, the other is not',
    (SELECT count(*) FILTER (WHERE disabled_at IS NOT NULL) = 1 AND count(*) = 2
     FROM public.push_devices WHERE user_id = nt.id('s1')));
END $$;

SET LOCAL ROLE authenticated;
SELECT nt.login('AA');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.preview_notification_audience(nt.id('co_a'), '{"kind": "university", "university_id": "e9800000-0000-0000-0000-000000000001"}');
  PERFORM nt.ok('C8 preview of a university''s students',
    r = '{"label": "طلاب جامعة الاختبار", "students": 2, "supervisors": 0, "devices": 1}'::jsonb, r::text);
  r := nt.keep('uni', public.compose_notification(nt.id('co_a'), 'للجامعة', 'نص.',
    '{"kind": "university", "university_id": "e9800000-0000-0000-0000-000000000001"}'));
  PERFORM nt.ok('C9 a university: its students of this company only, no supervisors', nt.recipients('uni') = 's1,s4', nt.recipients('uni'));
  PERFORM nt.ok('C10 nothing is queued for a switched-off device', nt.outbox('uni') = 's1:queued', nt.outbox('uni'));
END $$;

SET LOCAL ROLE service_role;
DO $$
DECLARE a jsonb;
BEGIN
  a := public.claim_push_outbox();
  PERFORM public.complete_push_outbox(jsonb_build_array(jsonb_build_object('id', a->0->'id', 'status', 'retry', 'error', 'UNAVAILABLE')));
  PERFORM nt.ok('D5 a retry waits: back in the queue, not due yet',
    nt.outbox('uni') = 's1:queued' AND jsonb_array_length(public.claim_push_outbox()) = 0, nt.outbox('uni'));
END $$;
RESET ROLE;
UPDATE public.push_outbox SET next_attempt_at = now() - interval '1 second' WHERE status = 'queued';
SET LOCAL ROLE service_role;
DO $$
DECLARE a jsonb;
BEGIN
  a := public.claim_push_outbox();
  PERFORM public.complete_push_outbox(jsonb_build_array(jsonb_build_object('id', a->0->'id', 'status', 'retry', 'error', 'auth: token_401')));
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM nt.ok('D6 a push that never reached the provider does not use up an attempt',
    (SELECT o.status = 'queued' AND o.attempts = 1 FROM public.push_outbox o WHERE o.notification_id = nt.sent_id('uni')),
    (SELECT o.status || ' ' || o.attempts FROM public.push_outbox o WHERE o.notification_id = nt.sent_id('uni')));
  UPDATE public.push_outbox SET status = 'sending', claimed_at = now() - interval '10 minutes' WHERE notification_id = nt.sent_id('uni');
  UPDATE public.push_outbox SET next_attempt_at = now() WHERE notification_id = nt.sent_id('uni');
END $$;
SET LOCAL ROLE service_role;
DO $$
BEGIN
  PERFORM nt.ok('D7 a push stuck in sending is handed out again', jsonb_array_length(public.claim_push_outbox()) = 1);
END $$;
RESET ROLE;

-- =============================================================================
-- Scheduling
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT nt.login('AA');
DO $$
DECLARE r jsonb;
BEGIN
  r := nt.keep('later', public.compose_notification(nt.id('co_a'), 'لاحقاً', 'نص مؤجل.', '{"kind": "company"}', now() + interval '1 hour'));
  PERFORM nt.ok('T1 scheduled: stored, nobody has it yet',
    r->>'status' = 'scheduled' AND (r->>'students')::int = 5 AND nt.recipients('later') IS NULL, r::text);
  PERFORM nt.ok('T2 a time that has passed, or too far away, is refused',
    nt.err(format($q$SELECT public.compose_notification(%L, 'x', 'y', '{"kind": "company"}', now() - interval '1 minute')$q$, nt.id('co_a'))) LIKE '%موعداً قادماً%'
    AND nt.err(format($q$SELECT public.compose_notification(%L, 'x', 'y', '{"kind": "company"}', now() + interval '90 days')$q$, nt.id('co_a'))) LIKE '%موعداً قادماً%');
  PERFORM public.update_scheduled_notification(nt.sent_id('later'), 'لاحقاً (معدّل)', 'نص جديد.',
    jsonb_build_object('kind', 'line', 'line_id', nt.id('L2')), now() + interval '2 hours');
  r := public.get_company_notifications_page(nt.id('co_a'), p_status := 'scheduled');
  PERFORM nt.ok('T3 what is scheduled can be changed: text, audience and time',
    jsonb_array_length(r->'items') = 1 AND r->'items'->0->>'title' = 'لاحقاً (معدّل)' AND r->'items'->0->>'audience' = 'خط الثاني'
    AND r->'items'->0->'audience_spec'->>'kind' = 'line', r::text);
  PERFORM nt.keep('dropped', public.compose_notification(nt.id('co_a'), 'يُلغى', 'نص.', '{"kind": "company"}', now() + interval '1 hour'));
  PERFORM nt.keep('nobody', public.compose_notification(nt.id('co_a'), 'بلا ركاب', 'نص.',
    jsonb_build_object('kind', 'trip', 'line_id', nt.id('L1'), 'trip_id', nt.id('D2'),
                       'ride_date', ((now() + interval '1 hour') AT TIME ZONE 'Africa/Cairo')::date + 1), now() + interval '1 hour'));
  PERFORM public.cancel_scheduled_notification(nt.sent_id('dropped'));
  PERFORM nt.ok('T4 cancelled; it cannot be cancelled or changed again',
    nt.status('dropped') = 'cancelled'
    AND nt.err(format('SELECT public.cancel_scheduled_notification(%L)', nt.sent_id('dropped'))) LIKE '%من قبل%'
    AND nt.err(format($q$SELECT public.update_scheduled_notification(%L, 'x', 'y', '{"kind": "company"}', now() + interval '1 hour')$q$,
      nt.sent_id('dropped'))) LIKE '%بعد إرساله أو إلغائه%');
END $$;
SELECT nt.login('AB');
DO $$
BEGIN
  PERFORM nt.ok('T5 another company''s admin cannot change, cancel or delete it',
    nt.err(format($q$SELECT public.update_scheduled_notification(%L, 'x', 'y', '{"kind": "company"}', now() + interval '1 hour')$q$,
      nt.sent_id('later'))) LIKE '%لا يمكنك%'
    AND nt.err(format('SELECT public.cancel_scheduled_notification(%L)', nt.sent_id('later'))) LIKE '%لا يمكنك%'
    AND nt.err(format('SELECT public.delete_notification(%L)', nt.sent_id('later'))) LIKE '%لا يمكنك%');
END $$;
SELECT nt.login('s4');
DO $$
BEGIN
  PERFORM nt.tick();
  PERFORM nt.ok('T6 before its time nothing goes out, and the student does not see it',
    nt.status('later') = 'scheduled' AND nt.page_names(public.get_my_notifications_page()) = 'uni,now',
    nt.page_names(public.get_my_notifications_page()));
  PERFORM nt.force_due('later'); PERFORM nt.force_due('dropped'); PERFORM nt.force_due('nobody');
  PERFORM nt.tick();
  PERFORM nt.tick();
  PERFORM nt.ok('T7 at its time it goes out once, to the audience as it was last set',
    nt.status('later') = 'sent' AND nt.recipients('later') = 'SB,s4'
    AND nt.page_names(public.get_my_notifications_page()) = 'later,uni,now', nt.recipients('later'));
  PERFORM nt.ok('T8 a cancelled one never goes out; one that finds nobody is marked failed',
    nt.status('dropped') = 'cancelled' AND nt.recipients('dropped') IS NULL AND nt.status('nobody') = 'failed');
END $$;

-- =============================================================================
-- The app reads
-- =============================================================================
DO $$
DECLARE p jsonb; p2 jsonb; item jsonb;
BEGIN
  p := public.get_my_notifications_page(NULL, 2);
  p2 := public.get_my_notifications_page((p->>'next_before')::timestamptz, 2);
  PERFORM nt.ok('A1 pages: newest first, no overlap, an end',
    nt.page_names(p) = 'later,uni' AND p->>'next_before' IS NOT NULL AND (p->>'unread')::int = 3
    AND nt.page_names(p2) = 'now' AND p2->>'next_before' IS NULL, p::text);
  item := p->'items'->0;
  PERFORM nt.ok('A2 an item carries its type, category, where to go and when it was sent',
    item->>'type' = 'announcement.admin' AND item->>'category' = 'announcement' AND item->'data'->>'route' = 'notifications'
    AND item->>'sender_role' = 'admin' AND NOT (item->>'read')::boolean AND item ? 'title_en'
    AND (item->>'created_at')::timestamptz > (p->'items'->1->>'created_at')::timestamptz, item::text);
  PERFORM public.mark_notifications_read(ARRAY[nt.sent_id('uni')]);
  PERFORM nt.ok('A3 unread only, and the count follows',
    nt.page_names(public.get_my_notifications_page(p_unread_only := true)) = 'later,now' AND public.get_my_unread_count() = 2);
  PERFORM public.notification_opened(nt.sent_id('now'));
  PERFORM public.notification_opened(nt.sent_id('l1x'));
  PERFORM nt.ok('A4 a tap on the push opens it and reads it', public.get_my_unread_count() = 1
    AND nt.opened('now', 's4'));
  PERFORM nt.ok('A5 own topic only', public.can_join_topic('user:' || nt.id('s4'))
    AND NOT public.can_join_topic('user:' || nt.id('s1')) AND NOT public.can_join_topic('user:nothing'));
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM nt.ok('A6 reading tells the user''s other devices, and nobody else',
    (SELECT count(*) = 2 AND bool_and(m.topic = 'user:' || nt.id('s4')) FROM realtime.messages m WHERE m.payload->>'op' = 'READ'));
  PERFORM nt.ok('A7 a scheduled notification reaches its line only once it is sent',
    (SELECT string_agg(m.topic, ',' ORDER BY m.topic) FROM realtime.messages m
     WHERE (m.payload->>'id')::uuid = nt.sent_id('later') AND m.topic LIKE 'line:%') = 'line:' || nt.id('L2'));
END $$;
SET LOCAL ROLE authenticated;
SELECT nt.login('s6');
DO $$
BEGIN
  PERFORM public.notification_opened(nt.sent_id('now'));
  PERFORM public.mark_notifications_read(ARRAY[nt.sent_id('now'), nt.sent_id('uni')]);
  PERFORM nt.ok('A8 another company''s student has nothing, and cannot read or open ours',
    public.get_my_notifications_page()->'items' = '[]'::jsonb AND public.get_my_unread_count() = 0
    AND nt.recipients('now') NOT LIKE '%s6%' AND nt.opened('now', 's6') IS NULL);
END $$;

SELECT nt.login('AA');
DO $$
DECLARE p jsonb; p2 jsonb; row jsonb;
BEGIN
  p := public.get_company_notifications_page(nt.id('co_a'), NULL, 2);
  p2 := public.get_company_notifications_page(nt.id('co_a'), (p->>'next_before')::timestamptz, 10);
  PERFORM nt.ok('H1 history in pages, without the same row twice',
    jsonb_array_length(p->'items') = 2 AND p->>'next_before' IS NOT NULL AND p2->>'next_before' IS NULL
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') a JOIN jsonb_array_elements(p2->'items') b
                    ON a->>'id' = b->>'id'), p::text);
  SELECT x INTO row FROM jsonb_array_elements(p2->'items') x WHERE (x->>'id')::uuid = nt.sent_id('now');
  PERFORM nt.ok('H2 true counts: received, read, opened, and each push as it stands',
    (row->>'students')::int = 5 AND (row->>'read')::int = 1 AND (row->>'opened')::int = 1
    AND row->'push' = '{"devices": 3, "queued": 0, "accepted": 1, "failed": 1, "skipped": 1}'::jsonb
    AND (p->>'push_configured')::boolean, row::text);
  PERFORM nt.ok('H3 by status', (SELECT bool_and(x->>'status' = 'failed') AND count(*) = 1
    FROM jsonb_array_elements(public.get_company_notifications_page(nt.id('co_a'), p_status := 'failed')->'items') x));
END $$;

-- =============================================================================
-- Supervisors: ready-made messages
-- =============================================================================
SELECT nt.login('s1');
DO $$
BEGIN
  PERFORM nt.ok('Q1 a student has no ready-made messages and cannot send one',
    public.get_quick_notification_templates() = '[]'::jsonb
    AND nt.err(format($q$SELECT public.send_quick_notification('transport.cancelled', %L)$q$, nt.id('L1'))) LIKE '%مشرفي%');
END $$;
SELECT nt.login('SA');
DO $$
DECLARE r jsonb; r2 jsonb; n public.notifications%ROWTYPE; i int;
BEGIN
  PERFORM nt.ok('Q2 the supervisor''s list', (SELECT string_agg(t->>'key', ',') FROM jsonb_array_elements(public.get_quick_notification_templates()) t)
    = 'transport.delay,transport.departed,transport.arrived,transport.return_departing,transport.cancelled');
  r := nt.keep('delay', public.send_quick_notification('transport.delay', nt.id('L1'), nt.id('D1'), p_minutes := 10, p_idempotency_key := 'tap-1'));
  r2 := public.send_quick_notification('transport.delay', nt.id('L1'), nt.id('D1'), p_minutes := 10, p_idempotency_key := 'tap-1');
  PERFORM nt.ok('Q3 to today''s riders of the trip, with the minutes filled in; a repeated tap is the same one',
    (r->>'students')::int = 1 AND nt.recipients('delay') = 'SC,s1' AND (r2->>'duplicate')::boolean AND r2->>'id' = r->>'id', r::text);
  PERFORM nt.ok('Q4 the text is the template''s, in both languages, urgent, with the trip''s ids only',
    (SELECT x->>'type' = 'transport.delay' AND x->>'category' = 'transport' AND x->>'priority' = 'high'
       AND x->>'body' LIKE '%10 دقيقة%' AND x->>'body_en' LIKE '%10 minutes%' AND x->>'sender_role' = 'supervisor'
       AND x->'data' = jsonb_build_object('route', 'home', 'line_id', nt.id('L1'), 'trip_id', nt.id('D1'), 'ride_date', public.cairo_today())
     FROM nt.note('delay') x), nt.note('delay')::text);
  PERFORM nt.ok('Q5 minutes are required where the message needs them',
    nt.err(format($q$SELECT public.send_quick_notification('transport.delay', %L, %L)$q$, nt.id('L1'), nt.id('D1'))) LIKE '%الدقائق%'
    AND nt.err(format($q$SELECT public.send_quick_notification('transport.delay', %L, %L, p_minutes := 500)$q$, nt.id('L1'), nt.id('D1'))) LIKE '%الدقائق%');
  PERFORM nt.ok('Q6 only on assigned lines, only offered messages',
    nt.err(format($q$SELECT public.send_quick_notification('transport.cancelled', %L)$q$, nt.id('L2'))) LIKE '%المسندة إليك%'
    AND nt.err(format($q$SELECT public.send_quick_notification('transport.cancelled', %L)$q$, nt.id('LB'))) LIKE '%المسندة إليك%'
    AND nt.err(format($q$SELECT public.send_quick_notification('subscription.approved', %L)$q$, nt.id('L1'))) LIKE '%غير متاح%');
  PERFORM nt.ok('Q7 a return message does not go to a departure trip',
    nt.err(format($q$SELECT public.send_quick_notification('transport.return_departing', %L, %L, p_minutes := 5)$q$,
      nt.id('L1'), nt.id('D1'))) LIKE '%اتجاه%');
  PERFORM nt.ok('Q8 the same message to the same riders straight away is refused',
    nt.err(format($q$SELECT public.send_quick_notification('transport.delay', %L, %L, p_minutes := 10)$q$,
      nt.id('L1'), nt.id('D1'))) LIKE '%قبل قليل%');
  FOR i IN 1..11 LOOP
    PERFORM public.send_notification('رسالة ' || i, 'نص.', p_line_id := nt.id('L1'));
  END LOOP;
  PERFORM nt.ok('Q9 twelve an hour, then no more',
    nt.err(format($q$SELECT public.send_notification('x', 'y', p_line_id := %L)$q$, nt.id('L1'))) LIKE '%كثيرة%'
    AND nt.err(format($q$SELECT public.send_quick_notification('transport.cancelled', %L)$q$, nt.id('L1'))) LIKE '%كثيرة%');
END $$;
SELECT nt.login('AA');
SELECT public.delete_notification(nt.sent_id('delay'));
RESET ROLE;
DO $$
BEGIN
  PERFORM nt.ok('Q10 every send is on record, and stays when the notification is deleted',
    (SELECT count(*) FILTER (WHERE a.action = 'send') = 12 FROM public.notification_audit a WHERE a.actor_id = nt.id('SA'))
    AND (SELECT a.detail->>'template' = 'transport.delay' AND (a.detail->>'minutes')::int = 10
         FROM public.notification_audit a WHERE a.notification_id = nt.sent_id('delay') AND a.action = 'send')
    AND EXISTS (SELECT 1 FROM public.notification_audit a WHERE a.notification_id = nt.sent_id('delay') AND a.action = 'delete'
                  AND a.actor_id = nt.id('AA'))
    AND NOT EXISTS (SELECT 1 FROM public.notifications x WHERE x.id = nt.sent_id('delay')));
END $$;

-- =============================================================================
-- The platform (20261101000001)
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT nt.login('AA');
DO $$
BEGIN
  PERFORM nt.ok('X1 a company admin has no platform page',
    nt.err('SELECT public.platform_preview_notification()') LIKE '%المنصة فقط%'
    AND nt.err($q$SELECT public.platform_compose_notification('x', 'y')$q$) LIKE '%المنصة فقط%'
    AND nt.err('SELECT public.get_platform_notifications_page()') LIKE '%المنصة فقط%');
END $$;
SELECT nt.login('s1');
DO $$
BEGIN
  PERFORM nt.ok('X2 nor a student',
    nt.err('SELECT public.platform_preview_notification()') LIKE '%المنصة فقط%'
    AND nt.err($q$SELECT public.platform_compose_notification('x', 'y')$q$) LIKE '%المنصة فقط%'
    AND nt.err('SELECT public.get_platform_notifications_page()') LIKE '%المنصة فقط%');
END $$;
SELECT nt.login('AS');
DO $$
DECLARE r jsonb; r2 jsonb; p jsonb;
BEGIN
  r := public.platform_preview_notification(ARRAY[nt.id('co_a'), nt.id('co_b')]);
  PERFORM nt.ok('X3 the platform previews across companies', (r->>'companies')::int = 2 AND (r->>'students')::int = 6
    AND (r->>'supervisors')::int = 3, r::text);
  r := public.platform_compose_notification('من المنصة', 'تحديث مهم.', ARRAY[nt.id('co_a'), nt.id('co_b')], p_idempotency_key := 'plat-1');
  r2 := public.platform_compose_notification('من المنصة', 'تحديث مهم.', ARRAY[nt.id('co_a'), nt.id('co_b')], p_idempotency_key := 'plat-1');
  PERFORM nt.ok('X4 one notification per company; the same key again adds none',
    (r->>'companies')::int = 2 AND (r->>'students')::int = 6 AND NOT (r->>'duplicate')::boolean AND (r2->>'duplicate')::boolean, r::text || r2::text);
  r := public.platform_compose_notification('لشركة واحدة', 'نص.', ARRAY[nt.id('co_b')]);
  PERFORM nt.ok('X5 to the companies picked only', (r->>'companies')::int = 1 AND (r->>'students')::int = 1, r::text);
  p := public.get_platform_notifications_page(p_company_id := nt.id('co_b'));
  PERFORM nt.ok('X6 the platform sees every company''s history, by company, with the state of push',
    jsonb_array_length(p->'items') = 2 AND (SELECT bool_and(x->>'company_name' = 'E2E Notify B' AND x->>'type' = 'announcement.platform'
                                                             AND x->>'sender_name' = 'منصة باصك' AND (x->>'students')::int = 1)
                                            FROM jsonb_array_elements(p->'items') x)
    AND p->'push' ?& ARRAY['configured', 'devices', 'ios', 'android', 'queued', 'accepted_24h', 'failed_24h']
    AND jsonb_array_length(public.get_platform_notifications_page(p_limit := 100)->'items') > 10, p::text);
END $$;
SELECT nt.login('AB');
DO $$
DECLARE p jsonb;
BEGIN
  p := public.get_company_notifications_page(nt.id('co_b'));
  PERFORM nt.ok('X7 each company''s admin sees its own copy and nothing of the others',
    jsonb_array_length(p->'items') = 2 AND nt.err(format('SELECT public.get_company_notifications_page(%L)', nt.id('co_a'))) LIKE '%لا يمكنك%', p::text);
END $$;
SELECT nt.login('s6');
DO $$
BEGIN
  PERFORM nt.ok('X8 the other company''s student receives the platform''s two, unread',
    jsonb_array_length(public.get_my_notifications_page()->'items') = 2 AND public.get_my_unread_count() = 2);
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM nt.ok('X9 the platform dashboard hears of every notification, and each is filed under one company',
    (SELECT count(*) > 0 FROM realtime.messages m WHERE m.topic = 'platform' AND m.payload->>'table' = 'notifications')
    AND (SELECT count(*) = 3 AND count(DISTINCT company_id) = 2 FROM public.notifications WHERE type = 'announcement.platform')
    AND (SELECT count(*) = 3 FROM public.notification_audit WHERE actor_role = 'platform' AND actor_id = nt.id('AS')));
END $$;

-- =============================================================================
-- Automatic: subscriptions
-- =============================================================================
-- The company's admin changes the subscriptions (the guard reads the signed-in user).
SELECT nt.login('AA');
DELETE FROM realtime.messages;
UPDATE public.subscriptions SET status = 'pending_review' WHERE student_id = nt.id('s3');
UPDATE public.subscriptions SET status = 'active' WHERE student_id = nt.id('s3');
UPDATE public.subscriptions SET status = 'expired' WHERE student_id = nt.id('s7');
DO $$
DECLARE n public.notifications%ROWTYPE;
BEGIN
  PERFORM nt.ok('S1 proof received, then approved: told to that student', nt.system_for('s3') = 'subscription.payment_received,subscription.approved',
    nt.system_for('s3'));
  SELECT x.* INTO n FROM public.notifications x JOIN public.notification_recipients r ON r.notification_id = x.id
  WHERE r.user_id = nt.id('s3') AND x.type = 'subscription.approved';
  PERFORM nt.ok('S2 it opens the subscription, is urgent, and carries ids only',
    n.priority = 'high' AND n.category = 'subscription' AND n.sender_id IS NULL AND n.title_en IS NOT NULL
    AND n.data = jsonb_build_object('route', 'subscription', 'subscription_id',
          (SELECT s.id FROM public.subscriptions s WHERE s.student_id = nt.id('s3')))
    AND (SELECT count(*) = 1 FROM public.notification_recipients r WHERE r.notification_id = n.id), n.data::text);
  PERFORM nt.ok('S3 announced to that student, the company''s staff and the platform, to no line',
    (SELECT string_agg(DISTINCT m.topic, ',' ORDER BY m.topic) FROM realtime.messages m
     WHERE (m.payload->>'id')::uuid = n.id) = 'company:' || nt.id('co_a') || ',platform,user:' || nt.id('s3'));
  PERFORM nt.ok('S4 ended: told once', nt.system_for('s7') = 'subscription.expired', nt.system_for('s7'));

  UPDATE public.subscriptions SET end_date = public.cairo_today() + 3 WHERE student_id = nt.id('s2');
  UPDATE public.subscriptions SET start_date = public.cairo_today() - 5, end_date = public.cairo_today() - 1 WHERE student_id = nt.id('s4');
  PERFORM public.notifications_daily();
  PERFORM public.notifications_daily();
  PERFORM nt.ok('S5 three days before the end, and the day after it: each told once however often the day''s work runs',
    nt.system_for('s2') = 'subscription.expiring' AND nt.system_for('s4') = 'subscription.expired',
    nt.system_for('s2') || ' / ' || nt.system_for('s4'));
  UPDATE public.subscriptions SET status = 'expired' WHERE student_id = nt.id('s4');
  PERFORM nt.ok('S6 the status catching up later does not tell it again', nt.system_for('s4') = 'subscription.expired');

  DELETE FROM public.notification_templates WHERE key = 'subscription.rejected';
  ALTER TABLE public.notification_recipients ADD CONSTRAINT nt_break CHECK (user_id <> nt.id('s1')) NOT VALID;
  UPDATE public.subscriptions SET status = 'rejected' WHERE student_id = nt.id('s2');
  UPDATE public.subscriptions SET status = 'pending_review' WHERE student_id = nt.id('s1');
  PERFORM nt.ok('S7 a notification that cannot be made never stops the change itself',
    (SELECT status FROM public.subscriptions WHERE student_id = nt.id('s2')) = 'rejected'
    AND (SELECT status FROM public.subscriptions WHERE student_id = nt.id('s1')) = 'pending_review'
    AND nt.system_for('s1') = '' AND nt.system_for('s2') = 'subscription.expiring', nt.system_for('s1'));
  ALTER TABLE public.notification_recipients DROP CONSTRAINT nt_break;
END $$;

-- =============================================================================
\o
\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, step, left(detail, 160) AS detail FROM nt.results ORDER BY n;
DO $$ DECLARE f int; BEGIN
  SELECT count(*) INTO f FROM nt.results WHERE NOT ok;
  IF f > 0 THEN RAISE EXCEPTION '% test step(s) failed', f; END IF;
  RAISE NOTICE 'all % steps passed', (SELECT count(*) FROM nt.results);
END $$;
ROLLBACK;
