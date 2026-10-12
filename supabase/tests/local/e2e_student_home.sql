-- Test of 20261125000001_student_home_bundle (get_student_home).
-- Plain SQL, one transaction, rolled back: run it after the migration, or paste
-- the migration (without its BEGIN/COMMIT) right after the BEGIN below. Nothing
-- persists. Fails (RAISE) unless every check says ok = true.
--
-- What it checks: who may call it, that a student gets only their own rows, and
-- that every part equals the answer of the function or read the app makes on
-- its own. (That the subscription and table parts equal what the API answers
-- for the app's separate requests, embeds and key order included, is checked
-- over HTTP by student_home_parity.mjs.)
--
-- Fixture (triggers off while it is written): company A with line LA (two
-- stations, a departure and a return trip), two supervisors on LA (sup1 its
-- primary contact), students s1 and s2. s1: an expired «second 2025» and a
-- current «first 2026» waiting for payment with a refused receipt, three votes
-- (one outside the asked days) and two boardings. s2: active «first 2026», one
-- vote. A company admin of A.
BEGIN;

CREATE SCHEMA sh;
GRANT USAGE ON SCHEMA sh TO authenticated, anon;
CREATE TABLE sh.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE FUNCTION sh.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO sh.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION sh.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE; END $$;
CREATE TABLE sh.out (who text PRIMARY KEY, body jsonb);
CREATE FUNCTION sh.keep(p_who text, p_body jsonb) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO sh.out VALUES (p_who, p_body) ON CONFLICT (who) DO UPDATE SET body = excluded.body RETURNING body $$;
CREATE FUNCTION sh.got(p_who text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT body FROM sh.out WHERE who = p_who $$;
CREATE FUNCTION sh.login(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sh TO authenticated, anon;
GRANT INSERT, SELECT, UPDATE ON sh.results, sh.out TO authenticated;
GRANT USAGE ON SEQUENCE sh.results_n_seq TO authenticated;

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, email)
SELECT ('7e000000-0000-4000-8000-0000000000' || x)::uuid, 'sh-' || x || '@example.invalid'
FROM unnest(ARRAY['a5', 'aa', '51', '52', 'e1', 'e2']) x;

INSERT INTO public.companies (id, name, status, is_active) VALUES
  ('7e000000-0000-4000-8000-00000000c00a', 'اختبار الرئيسية أ', 'active', true);
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  ('7e000000-0000-4000-8000-0000000000a5', 'sh-a5@example.invalid', 'مدير المنصة', 'super_admin', NULL, NULL),
  ('7e000000-0000-4000-8000-0000000000aa', 'sh-aa@example.invalid', 'مدير أ', 'company_admin', '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000000a5');
INSERT INTO public.universities (id, name, city, is_active) VALUES
  ('7e000000-0000-4000-8000-0000000000f1', 'جامعة اختبار الرئيسية', 'دمياط', true);
INSERT INTO public.supervisors (id, phone, full_name, company_id, created_by_admin_id, is_active) VALUES
  ('7e000000-0000-4000-8000-0000000000e1', '01099980001', 'مشرف أول', '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000000a5', true),
  ('7e000000-0000-4000-8000-0000000000e2', '01099980002', 'مشرف ثان', '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000000a5', true);
INSERT INTO public.lines (id, company_id, name, origin_name, destination_university_id, price_termly, price_yearly, price_daily, is_active, supervisor_id) VALUES
  ('7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000c00a', 'خط الرئيسية', 'البداية',
   '7e000000-0000-4000-8000-0000000000f1', 3500, 6500, 0, true, '7e000000-0000-4000-8000-0000000000e1');
INSERT INTO public.supervisor_lines (supervisor_id, line_id, company_id, assigned_by) VALUES
  ('7e000000-0000-4000-8000-0000000000e1', '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000000a5'),
  ('7e000000-0000-4000-8000-0000000000e2', '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000000a5');
INSERT INTO public.stations (id, line_id, name, order_index, company_id, is_active) VALUES
  ('7e000000-0000-4000-8000-00000000b001', '7e000000-0000-4000-8000-00000000a001', 'محطة الرئيسية 1', 0, '7e000000-0000-4000-8000-00000000c00a', true),
  ('7e000000-0000-4000-8000-00000000b002', '7e000000-0000-4000-8000-00000000a001', 'محطة الرئيسية 2', 1, '7e000000-0000-4000-8000-00000000c00a', true);
INSERT INTO public.line_trips (id, line_id, company_id, direction, label, start_time, university_id, is_active) VALUES
  ('7e000000-0000-4000-8000-00000000d001', '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000c00a', 'departure', 'الأولى', '07:00', '7e000000-0000-4000-8000-0000000000f1', true),
  ('7e000000-0000-4000-8000-00000000d002', '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000c00a', 'return', 'العودة', '15:00', '7e000000-0000-4000-8000-0000000000f1', true);
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time, company_id) VALUES
  ('7e000000-0000-4000-8000-00000000d001', '7e000000-0000-4000-8000-00000000b001', '07:00', '7e000000-0000-4000-8000-00000000c00a'),
  ('7e000000-0000-4000-8000-00000000d001', '7e000000-0000-4000-8000-00000000b002', '07:15', '7e000000-0000-4000-8000-00000000c00a'),
  ('7e000000-0000-4000-8000-00000000d002', '7e000000-0000-4000-8000-00000000b001', '15:30', '7e000000-0000-4000-8000-00000000c00a');

INSERT INTO public.students (id, phone, full_name, university, college, university_id)
SELECT ('7e000000-0000-4000-8000-0000000000' || x)::uuid, '0109998000' || right(x, 1), 'طالب ' || x, 'جامعة اختبار الرئيسية', 'الهندسة',
       '7e000000-0000-4000-8000-0000000000f1'
FROM unnest(ARRAY['51', '52']) x;
INSERT INTO public.company_students (company_id, student_id, status)
SELECT '7e000000-0000-4000-8000-00000000c00a', ('7e000000-0000-4000-8000-0000000000' || x)::uuid, 'active' FROM unnest(ARRAY['51', '52']) x;
INSERT INTO public.subscriptions (id, student_id, company_id, line_id, station_id, type, status, start_date, end_date, price,
                                  paid_at, period_code, academic_year, departure_trip_id, return_trip_id, departure_time, return_time, created_at)
VALUES
  ('7e000000-0000-4000-8000-0000000005a1', '7e000000-0000-4000-8000-000000000051', '7e000000-0000-4000-8000-00000000c00a',
   '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000b001', 'termly', 'expired', '2026-02-07', '2026-06-30', 3300,
   now() - interval '250 days', 'second', 2025, '7e000000-0000-4000-8000-00000000d001', '7e000000-0000-4000-8000-00000000d002', '07:00', '15:00', now() - interval '250 days'),
  ('7e000000-0000-4000-8000-0000000005b1', '7e000000-0000-4000-8000-000000000051', '7e000000-0000-4000-8000-00000000c00a',
   '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000b001', 'termly', 'pending_payment', '2026-09-05', '2027-01-30', 3500,
   NULL, 'first', 2026, '7e000000-0000-4000-8000-00000000d001', '7e000000-0000-4000-8000-00000000d002', '07:00', '15:00', now() - interval '5 days'),
  ('7e000000-0000-4000-8000-0000000005b2', '7e000000-0000-4000-8000-000000000052', '7e000000-0000-4000-8000-00000000c00a',
   '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000b002', 'termly', 'active', '2026-09-05', '2027-01-30', 3500,
   now() - interval '40 days', 'first', 2026, '7e000000-0000-4000-8000-00000000d001', NULL, '07:15', NULL, now() - interval '40 days');
INSERT INTO public.receipts (id, subscription_id, company_id, image_url, status, rejection_reason, attempt_number, created_at)
VALUES ('7e000000-0000-4000-8000-0000000006b1', '7e000000-0000-4000-8000-0000000005b1', '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-000000000051/x_1.jpg', 'rejected', 'غير واضح', 1, now() - interval '4 days');
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, is_returning, company_id, subscription_id)
VALUES ('7e000000-0000-4000-8000-000000000051', '2026-10-11', true, true, '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000005b1'),
       ('7e000000-0000-4000-8000-000000000051', '2026-10-12', false, false, '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000005b1'),
       ('7e000000-0000-4000-8000-000000000051', '2026-10-30', true, false, '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000005b1'),
       ('7e000000-0000-4000-8000-000000000052', '2026-10-11', true, true, '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-0000000005b2');
INSERT INTO public.supervisor_scan_events (company_id, line_id, trip_id, station_id, student_id, subscription_id, ride_date, direction, result, scanned_at)
SELECT '7e000000-0000-4000-8000-00000000c00a', '7e000000-0000-4000-8000-00000000a001', '7e000000-0000-4000-8000-00000000d001',
       '7e000000-0000-4000-8000-00000000b001', '7e000000-0000-4000-8000-000000000051', '7e000000-0000-4000-8000-0000000005a1',
       d, 'departure', 'checked_in', d + time '07:05'
FROM unnest(ARRAY[date '2026-03-01', '2026-03-02']) d;

SET LOCAL session_replication_role = origin;

-- =============================================================================
-- Who may call
-- =============================================================================
SELECT sh.ok('runs with the caller''s rights (row level security applies)',
             (SELECT NOT prosecdef FROM pg_proc WHERE oid = 'public.get_student_home(date, date, date, integer)'::regprocedure));
SELECT sh.ok('anon may not call it', NOT has_function_privilege('anon', 'public.get_student_home(date, date, date, integer)', 'EXECUTE'));
SELECT sh.ok('signed-in users may', has_function_privilege('authenticated', 'public.get_student_home(date, date, date, integer)', 'EXECUTE'));
SET LOCAL ROLE anon;
SELECT sh.ok('anon is refused (42501)', sh.err($$SELECT public.get_student_home('2026-10-12')$$) = '42501');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '', true);
SELECT sh.ok('no user in the token: nothing (null)', public.get_student_home('2026-10-12') IS NULL);

-- =============================================================================
-- s1: own rows only, every part as the app's own read
-- =============================================================================
SELECT sh.login('7e000000-0000-4000-8000-000000000051');
SELECT sh.keep('s1', public.get_student_home('2026-10-12', '2026-10-10', '2026-10-16')::jsonb);
SELECT sh.ok('profile: the student''s own row, every column',
             (SELECT body->'profile' = to_jsonb(s) FROM sh.out, public.students s WHERE who = 's1' AND s.id = '7e000000-0000-4000-8000-000000000051'));
SELECT sh.ok('subscriptions: both of s1, newest first, none of s2',
             (SELECT jsonb_array_length(body->'subscriptions') = 2
                     AND body->'subscriptions'->0->>'id' = '7e000000-0000-4000-8000-0000000005b1'
                     AND body->'subscriptions'->1->>'id' = '7e000000-0000-4000-8000-0000000005a1' FROM sh.out WHERE who = 's1'),
             (SELECT (body->'subscriptions')::text FROM sh.out WHERE who = 's1'));
SELECT sh.ok('current: the waiting «first 2026», with its embeds (the supervisor hidden: not running yet, as RLS says)',
             (SELECT body->'current'->>'id' = '7e000000-0000-4000-8000-0000000005b1'
                     AND body->'current'->'lines'->>'name' = 'خط الرئيسية'
                     AND body->'current'->'lines'->'companies'->>'name' = 'اختبار الرئيسية أ'
                     AND body->'current'->'lines'->'supervisors' = 'null'::jsonb
                     AND jsonb_array_length(body->'current'->'lines'->'line_trips') = 2
                     AND jsonb_array_length(body->'current'->'stations'->'line_trip_stops') = 2
                     AND body->'current'->'student'->>'university' = 'جامعة اختبار الرئيسية'
                     AND body->'current'->'departure_trip'->'universities'->>'name' = 'جامعة اختبار الرئيسية'
                     AND body->'current'->'return_trip'->>'start_time' = '15:00:00'
                     AND body->'current'->>'period_label' IS NOT NULL
                     AND body->'current'->>'period_phase' IS NOT NULL FROM sh.out WHERE who = 's1'),
             (SELECT (body->'current')::text FROM sh.out WHERE who = 's1'));
SELECT sh.ok('current is the same in the list',
             (SELECT body->'current' = body->'subscriptions'->0 FROM sh.out WHERE who = 's1'));
SELECT sh.ok('current: the same filter as the app (after its end it is gone)',
             (public.get_student_home('2027-02-01')::jsonb->'current') = 'null'::jsonb);
SELECT sh.ok('vote settings: those of the current subscription''s company',
             (SELECT body->'vote_company' = to_jsonb('7e000000-0000-4000-8000-00000000c00a'::text)
                     AND body->'vote_settings' = public.get_vote_settings('7e000000-0000-4000-8000-00000000c00a')
              FROM sh.out WHERE who = 's1'));
SELECT sh.ok('votes: the asked days only, s1''s only',
             (SELECT jsonb_array_length(body->'ride_days') = 2
                     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(body->'ride_days') d WHERE d->>'ride_date' NOT IN ('2026-10-11', '2026-10-12'))
              FROM sh.out WHERE who = 's1'), (SELECT (body->'ride_days')::text FROM sh.out WHERE who = 's1'));
SELECT sh.ok('votes: none asked, none read', (public.get_student_home('2026-10-12')::jsonb->'ride_days') = 'null'::jsonb);
SELECT sh.ok('receipts: the current subscription''s, newest attempt first',
             (SELECT body->>'receipts_of' = '7e000000-0000-4000-8000-0000000005b1' AND jsonb_array_length(body->'receipts') = 1
                     AND body->'receipts'->0->>'status' = 'rejected' AND body->'receipts'->0->>'rejection_reason' = 'غير واضح'
              FROM sh.out WHERE who = 's1'));
SELECT sh.ok('inbox: get_my_notifications_page''s first page',
             (SELECT body->'inbox' = public.get_my_notifications_page(NULL, 30, false) FROM sh.out WHERE who = 's1'));
SELECT sh.ok('invites: get_my_invites()', (SELECT body->'invites' = public.get_my_invites() FROM sh.out WHERE who = 's1'));
SELECT sh.ok('offers: get_my_offers()', (SELECT body->'offers' = public.get_my_offers() FROM sh.out WHERE who = 's1'));
SELECT sh.ok('supervisors: get_my_line_supervisors() (none: s1 has no running subscription)',
             (SELECT body->'line_supervisors' = public.get_my_line_supervisors() AND body->'line_supervisors' = '[]'::jsonb FROM sh.out WHERE who = 's1'));
SELECT sh.ok('boarded rides: get_my_boarded_rides_count() = 2',
             (SELECT (body->>'boarded_rides')::int = 2 AND (body->>'boarded_rides')::int = public.get_my_boarded_rides_count() FROM sh.out WHERE who = 's1'));
SELECT sh.ok('recap releases: as the table reads',
             (SELECT jsonb_array_length(body->'recap_releases') = (SELECT count(*) FROM public.term_recap_releases) FROM sh.out WHERE who = 's1'));
SELECT sh.ok('nothing of s2 anywhere in s1''s answer',
             (SELECT position('7e000000-0000-4000-8000-000000000052' IN body::text) = 0
                     AND position('7e000000-0000-4000-8000-0000000005b2' IN body::text) = 0 FROM sh.out WHERE who = 's1'));

-- =============================================================================
-- s2: an active subscription, both supervisors of the line
-- =============================================================================
SELECT sh.login('7e000000-0000-4000-8000-000000000052');
SELECT sh.keep('s2', public.get_student_home('2026-10-12', '2026-10-10', '2026-10-16')::jsonb);
SELECT sh.ok('s2: own profile, own subscription, own vote',
             (SELECT body->'profile'->>'id' = '7e000000-0000-4000-8000-000000000052'
                     AND jsonb_array_length(body->'subscriptions') = 1 AND body->'current'->>'status' = 'active'
                     AND jsonb_array_length(body->'ride_days') = 1 AND jsonb_array_length(body->'receipts') = 0
                     AND body->'current'->'return_trip' = 'null'::jsonb
                     AND body->'current'->'lines'->'supervisors'->>'full_name' = 'مشرف أول' FROM sh.out WHERE who = 's2'),
             (SELECT body::text FROM sh.out WHERE who = 's2'));
SELECT sh.ok('s2: both supervisors of the line, primary first',
             (SELECT body->'line_supervisors' = public.get_my_line_supervisors() AND jsonb_array_length(body->'line_supervisors') = 2
                     AND body->'line_supervisors'->0->>'full_name' = 'مشرف أول' FROM sh.out WHERE who = 's2'));
SELECT sh.ok('nothing of s1 anywhere in s2''s answer',
             (SELECT position('7e000000-0000-4000-8000-000000000051' IN body::text) = 0
                     AND position('7e000000-0000-4000-8000-0000000005b1' IN body::text) = 0 FROM sh.out WHERE who = 's2'));

-- =============================================================================
-- Not a student
-- =============================================================================
SELECT sh.login('7e000000-0000-4000-8000-0000000000e1');
SELECT sh.keep('sup', public.get_student_home('2026-10-12', '2026-10-10', '2026-10-16')::jsonb);
SELECT sh.ok('a supervisor: no student row, no subscriptions, no votes, no receipts',
             (SELECT body->'profile' = 'null'::jsonb AND body->'subscriptions' = '[]'::jsonb AND body->'current' = 'null'::jsonb
                     AND body->'ride_days' = '[]'::jsonb AND body->'receipts' = '[]'::jsonb AND (body->>'boarded_rides')::int = 0
              FROM sh.out WHERE who = 'sup'), (SELECT body::text FROM sh.out WHERE who = 'sup'));
SELECT sh.login('7e000000-0000-4000-8000-0000000000aa');
SELECT sh.ok('a company admin: no student''s rows either',
             (SELECT j->'profile' = 'null'::jsonb AND j->'subscriptions' = '[]'::jsonb AND j->'current' = 'null'::jsonb
              FROM (SELECT public.get_student_home('2026-10-12')::jsonb AS j) x));
RESET ROLE;

SELECT n, step, ok, detail FROM sh.results ORDER BY n;
DO $$ DECLARE v_bad int; BEGIN
  SELECT count(*) INTO v_bad FROM sh.results WHERE NOT ok;
  IF v_bad > 0 THEN RAISE EXCEPTION '% test step(s) failed', v_bad; END IF;
END $$;
ROLLBACK;
