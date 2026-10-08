-- End-to-end test of 20261102000001_performance_2. Run by run_local.sh after
-- every migration; one transaction, rolled back at the end. Same fixture as
-- e2e_notifications.sql (company A: lines L1, L2; admin AA; supervisors SA, SC,
-- SB; students s1–s5, s7; company B: admin AB, student s6). s3's subscription
-- is made a term subscription awaiting payment, so it can take a receipt.
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


SET LOCAL session_replication_role = replica;
UPDATE public.subscriptions SET type = 'termly', period_code = 'first', academic_year = 2026, price = 3000
WHERE student_id = nt.id('s3');
SET LOCAL session_replication_role = origin;
INSERT INTO storage.buckets (id, name) VALUES ('receipts', 'receipts') ON CONFLICT DO NOTHING;
GRANT USAGE ON SCHEMA nt TO service_role;

-- The SQLSTATE a statement fails with, or NULL.
CREATE FUNCTION nt.code(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE; END $$;
-- How many rows a statement touched (0 when a policy hides them).
CREATE FUNCTION nt.touched(p_sql text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer; BEGIN EXECUTE p_sql; GET DIAGNOSTICS n = ROW_COUNT; RETURN n; END $$;
CREATE FUNCTION nt.sub(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM public.subscriptions WHERE student_id = nt.id(p_name) ORDER BY created_at DESC LIMIT 1 $$;
CREATE FUNCTION nt.path(p_name text, p_key text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT nt.id(p_name) || '/' || nt.sub(p_name) || '_' || p_key || '.jpg' $$;
CREATE FUNCTION nt.objects() RETURNS text LANGUAGE sql SECURITY DEFINER AS
  $$ SELECT COALESCE(string_agg(split_part(name, '_', 2), ',' ORDER BY name), '') FROM storage.objects WHERE bucket_id = 'receipts' AND name LIKE nt.id('s3') || '/%' $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nt TO authenticated, service_role;

-- =============================================================================
-- Who signed in
-- =============================================================================
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  PERFORM nt.login('AA');
  PERFORM nt.ok('R1 an admin', public.my_role() = 'admin');
  PERFORM nt.login('SA');
  PERFORM nt.ok('R2 a supervisor', public.my_role() = 'supervisor');
  PERFORM nt.login('s1');
  PERFORM nt.ok('R3 a student', public.my_role() = 'student');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  PERFORM nt.ok('R4 an account that is none of them', public.my_role() IS NULL);
END $$;

-- =============================================================================
-- Receipt image: a retry replaces its own, a failure removes its own
-- =============================================================================
SELECT nt.login('s3');
DO $$
BEGIN
  INSERT INTO storage.objects (bucket_id, name) VALUES ('receipts', nt.path('s3', 'k1'));
  PERFORM nt.ok('U1 the student uploads the image',  nt.objects() = 'k1.jpg', nt.objects());
  PERFORM nt.ok('U2 sending it again over itself (a retry) is allowed',
    nt.touched(format('UPDATE storage.objects SET name = name WHERE bucket_id = ''receipts'' AND name = %L', nt.path('s3', 'k1'))) = 1);
  PERFORM nt.ok('U3 a submission that failed takes its image back',
    nt.touched(format('DELETE FROM storage.objects WHERE bucket_id = ''receipts'' AND name = %L', nt.path('s3', 'k1'))) = 1
    AND nt.objects() = '', nt.objects());
  INSERT INTO storage.objects (bucket_id, name) VALUES ('receipts', nt.path('s3', 'k2'));
  INSERT INTO public.receipts (subscription_id, image_url) VALUES (nt.sub('s3'), nt.path('s3', 'k2'));
  PERFORM nt.ok('U4 once a receipt uses it, it can be neither replaced nor removed by the student',
    nt.touched(format('UPDATE storage.objects SET name = name WHERE bucket_id = ''receipts'' AND name = %L', nt.path('s3', 'k2'))) = 0
    AND nt.touched(format('DELETE FROM storage.objects WHERE bucket_id = ''receipts'' AND name = %L', nt.path('s3', 'k2'))) = 0
    AND nt.objects() = 'k2.jpg', nt.objects());
  PERFORM nt.ok('U5 a second receipt while one is under review: code BR002',
    nt.code(format('INSERT INTO public.receipts (subscription_id, image_url) VALUES (%L, %L)', nt.sub('s3'), nt.path('s3', 'k3'))) = 'BR002');
END $$;
SELECT nt.login('s1');
DO $$
BEGIN
  PERFORM nt.ok('U6 another student can neither replace, remove nor see it',
    nt.touched(format('UPDATE storage.objects SET name = name WHERE bucket_id = ''receipts'' AND name = %L', nt.path('s3', 'k2'))) = 0
    AND nt.touched(format('DELETE FROM storage.objects WHERE bucket_id = ''receipts'' AND name = %L', nt.path('s3', 'k2'))) = 0
    AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'receipts') = 0);
  PERFORM nt.ok('U7 nor put a file in that student''s folder',
    nt.err(format('INSERT INTO storage.objects (bucket_id, name) VALUES (''receipts'', %L)', nt.path('s3', 'k9'))) IS NOT NULL);
END $$;
RESET ROLE;
DO $$
DECLARE i int;
BEGIN
  PERFORM nt.ok('U8 the same image cannot belong to two receipts',
    nt.code(format('INSERT INTO public.receipts (subscription_id, image_url, company_id) SELECT subscription_id, image_url, company_id FROM public.receipts WHERE image_url = %L',
                   nt.path('s3', 'k2'))) IN ('23505', 'BR002'));
  -- Four more attempts refused one after another, then the limit.
  PERFORM nt.login('AA');
  FOR i IN 2..5 LOOP
    UPDATE public.receipts SET status = 'rejected', rejection_reason = 'غير واضح' WHERE subscription_id = nt.sub('s3') AND status = 'pending';
    INSERT INTO public.receipts (subscription_id, image_url) VALUES (nt.sub('s3'), nt.path('s3', 'a' || i));
  END LOOP;
  UPDATE public.receipts SET status = 'rejected', rejection_reason = 'غير واضح' WHERE subscription_id = nt.sub('s3') AND status = 'pending';
  PERFORM nt.ok('U9 the sixth attempt: code BR001, said in Arabic',
    nt.code(format('INSERT INTO public.receipts (subscription_id, image_url) VALUES (%L, %L)', nt.sub('s3'), nt.path('s3', 'a6'))) = 'BR001'
    AND nt.err(format('INSERT INTO public.receipts (subscription_id, image_url) VALUES (%L, %L)', nt.sub('s3'), nt.path('s3', 'a6'))) LIKE '%الحد الأقصى%');

  -- Left behind: one of yesterday's that nothing uses, one of today's, one in use.
  INSERT INTO storage.objects (bucket_id, name, created_at) VALUES
    ('receipts', nt.path('s3', 'old-unused'), now() - interval '2 days'),
    ('receipts', nt.path('s3', 'new-unused'), now());
  UPDATE storage.objects SET created_at = now() - interval '2 days' WHERE name = nt.path('s3', 'k2');
  PERFORM nt.ok('U10 the clean-up is given only what is a day old and unused',
    (SELECT string_agg(split_part(o, '_', 2), ',') FROM public.orphan_receipt_images() o) = 'old-unused.jpg',
    (SELECT string_agg(o, ',') FROM public.orphan_receipt_images() o));
END $$;
SET LOCAL ROLE authenticated;
SELECT nt.login('AA');
DO $$
BEGIN
  PERFORM nt.ok('U11 the clean-up list is not for signed-in users',
    nt.err('SELECT public.orphan_receipt_images()') LIKE '%permission denied%'
    AND nt.err('SELECT public.storage_cleanup_kick()') LIKE '%permission denied%'
    AND nt.err('SELECT * FROM public.confirmed_riders_in(public.cairo_today(), NULL, NULL)') LIKE '%permission denied%'
    AND nt.err('SELECT * FROM public.rider_trip_choices_in(public.cairo_today(), NULL)') LIKE '%permission denied%');
END $$;
RESET ROLE;
DO $$
BEGIN
  UPDATE public.subscriptions SET status = 'active' WHERE student_id = nt.id('s3');
  PERFORM nt.ok('U12 an active subscription takes no receipt: code BR003',
    nt.code(format('INSERT INTO public.receipts (subscription_id, image_url) VALUES (%L, %L)', nt.sub('s3'), nt.path('s3', 'z'))) = 'BR003');
END $$;

-- =============================================================================
-- Riders: the narrowed functions give exactly what the wide ones gave
-- =============================================================================
DO $$
DECLARE d date := public.cairo_today();
BEGIN
  INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, departure_time, is_returning)
  VALUES (nt.id('s4'), d, true, '07:10', false), (nt.id('s6'), d, true, '07:10', false);
  PERFORM nt.ok('V1 a company''s confirmed riders are the same rows',
    NOT EXISTS ((SELECT * FROM public.confirmed_riders(d) WHERE company_id = nt.id('co_a'))
                EXCEPT SELECT * FROM public.confirmed_riders_in(d, nt.id('co_a'), NULL))
    AND NOT EXISTS (SELECT * FROM public.confirmed_riders_in(d, nt.id('co_a'), NULL)
                    EXCEPT (SELECT * FROM public.confirmed_riders(d) WHERE company_id = nt.id('co_a')))
    AND (SELECT count(*) FROM public.confirmed_riders_in(d, nt.id('co_a'), NULL)) = 3
    AND (SELECT count(*) FROM public.confirmed_riders_in(d, NULL, NULL)) = (SELECT count(*) FROM public.confirmed_riders(d)));
  PERFORM nt.ok('V2 a line''s trip choices are the same rows',
    NOT EXISTS ((SELECT * FROM public.rider_trip_choices(d) WHERE line_id = nt.id('L1'))
                EXCEPT SELECT * FROM public.rider_trip_choices_in(d, ARRAY[nt.id('L1')]))
    AND NOT EXISTS (SELECT * FROM public.rider_trip_choices_in(d, ARRAY[nt.id('L1')])
                    EXCEPT (SELECT * FROM public.rider_trip_choices(d) WHERE line_id = nt.id('L1')))
    AND (SELECT count(*) FROM public.rider_trip_choices_in(d, ARRAY[nt.id('L1')])) = 2);
  PERFORM nt.ok('V3 riders of a company today',
    public.company_riders_on(nt.id('co_a'), d) = 3 AND public.company_riders_on(nt.id('co_b'), d) = 1);
END $$;

-- =============================================================================
-- Report and counts
-- =============================================================================
SET LOCAL ROLE authenticated;
SELECT nt.login('AA');
DO $$
DECLARE r jsonb; c jsonb;
BEGIN
  r := public.admin_subscription_report('{}'::jsonb);
  PERFORM nt.ok('P1 the report counts the company''s subscriptions and shows them all, each with its period name',
    (r->'totals'->>'count')::int = 6 AND jsonb_array_length(r->'rows') = 6
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'rows') x WHERE x->>'label' IS NULL)
    AND (SELECT count(*) FROM jsonb_array_elements(r->'rows') x WHERE x->>'label' = 'اشتراك يومي') = 5
    AND r->'totals'->>'revenue_annual' = r->'totals'->>'revenue_both', (r->'totals')::text);
  PERFORM nt.ok('P2 rows come newest payment first',
    (SELECT bool_and(ok) FROM (SELECT (x->>'paid_at') IS NULL
        OR lag(x->>'paid_at') OVER (ORDER BY i) IS NULL OR lag(x->>'paid_at') OVER (ORDER BY i) >= x->>'paid_at' AS ok
      FROM jsonb_array_elements(r->'rows') WITH ORDINALITY e(x, i)) o));
  PERFORM nt.ok('P3 filters still narrow it',
    (public.admin_subscription_report(jsonb_build_object('line_id', nt.id('L2')))->'totals'->>'count')::int = 1
    AND (public.admin_subscription_report('{"period": "first"}'::jsonb)->'totals'->>'count')::int = 1
    AND (public.admin_subscription_report('{"search": "s4"}'::jsonb)->'totals'->>'count')::int = 1);
  c := public.university_student_counts();
  PERFORM nt.ok('C1 a company admin counts its own members only', c = '{"جامعة": 6}'::jsonb, c::text);
END $$;
SELECT nt.login('AS');
DO $$
BEGIN
  PERFORM nt.ok('C2 the platform counts everyone', (public.university_student_counts()->>'جامعة')::int = 7,
    public.university_student_counts()::text);
  PERFORM nt.ok('P4 the platform''s report spans companies',
    (public.admin_subscription_report('{}'::jsonb)->'totals'->>'count')::int >= 7
    AND (public.admin_subscription_report(jsonb_build_object('company_id', nt.id('co_b')))->'totals'->>'count')::int = 1);
END $$;
SELECT nt.login('s1');
DO $$
BEGIN
  PERFORM nt.ok('C3 a student gets neither', nt.err('SELECT public.university_student_counts()') IS NOT NULL
    AND nt.err($q$SELECT public.admin_subscription_report('{}'::jsonb)$q$) IS NOT NULL);
  PERFORM nt.ok('K1 the catalog still lists what the student can buy',
    jsonb_typeof(public.get_subscription_catalog()->'companies') = 'array');
END $$;
RESET ROLE;

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
