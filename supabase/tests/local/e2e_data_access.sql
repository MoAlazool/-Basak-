-- End-to-end test of 20261103000001_data_access. Run by run_local.sh after every
-- migration; one transaction, rolled back at the end. Same fixture as
-- e2e_notifications.sql (company A: lines L1, L2; admin AA; supervisors SA, SC on
-- L1, SB on L2; students s1–s5, s7; company B: admin AB, student s6; platform
-- admin AS). s3's subscription is made a term subscription with a receipt
-- waiting for review.
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
CREATE FUNCTION nt.code(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE; END $$;
CREATE FUNCTION nt.sub(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM public.subscriptions WHERE student_id = nt.id(p_name) ORDER BY created_at DESC LIMIT 1 $$;
CREATE FUNCTION nt.receipt(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT id FROM public.receipts WHERE subscription_id = nt.sub(p_name) ORDER BY created_at DESC LIMIT 1 $$;
CREATE FUNCTION nt.sub_status(p_name text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT status FROM public.subscriptions WHERE id = nt.sub(p_name) $$;
-- "s7,s4": the students on a page, in order, by fixture name.
CREATE FUNCTION nt.page_students(p_page jsonb) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(string_agg(x.name, ',' ORDER BY i), '')
  FROM jsonb_array_elements(p_page->'rows') WITH ORDINALITY e(r, i) JOIN nt.names x ON x.id = (r->>'id')::uuid $$;
-- What the overview should say, worked out the long way.
CREATE FUNCTION nt.truth(p_company uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT jsonb_build_object(
    'running', (SELECT count(*) FROM public.subscriptions s WHERE s.company_id = p_company AND s.status = 'active'
                AND s.paid_at IS NOT NULL AND COALESCE(s.start_date, public.cairo_today()) <= public.cairo_today()
                AND COALESCE(s.end_date, public.cairo_today()) >= public.cairo_today()),
    'riders', (SELECT count(*) FROM public.confirmed_riders(public.cairo_today()) r WHERE r.company_id = p_company)) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nt TO authenticated;
-- A second, older subscription of s1 in company B: it must never show in company A's page.
SET LOCAL session_replication_role = replica;
INSERT INTO public.subscriptions (student_id, company_id, line_id, station_id, type, status, price, start_date, end_date)
VALUES (nt.id('s1'), nt.id('co_b'), nt.id('LB'), nt.id('SBst'), 'daily', 'expired', 40, public.cairo_today() - 60, public.cairo_today() - 30);
SET LOCAL session_replication_role = origin;
-- Join dates a minute apart so "newest first" has one answer.
UPDATE public.students st SET created_at = now() - (right(st.id::text, 1)::int) * interval '1 minute' WHERE st.id IN (SELECT id FROM nt.names WHERE name LIKE 's_');

SET LOCAL ROLE authenticated;
SELECT nt.login('s3');
INSERT INTO storage.objects (bucket_id, name) VALUES ('receipts', nt.id('s3') || '/' || nt.sub('s3') || '_k1.jpg');
INSERT INTO public.receipts (subscription_id, image_url) VALUES (nt.sub('s3'), nt.id('s3') || '/' || nt.sub('s3') || '_k1.jpg');

-- =============================================================================
-- Students page
-- =============================================================================
SELECT nt.login('AA');
DO $$
DECLARE p jsonb; p2 jsonb; row jsonb;
BEGIN
  p := public.get_company_students_page(nt.id('co_a'), p_with_total := true);
  PERFORM nt.ok('S1 the company''s members, newest first, with the total when asked',
    nt.page_students(p) = 's1,s2,s3,s4,s5,s7' AND (p->>'total')::int = 6 AND NOT (p->>'has_next')::boolean, nt.page_students(p));
  p := public.get_company_students_page(nt.id('co_a'), p_limit := 4);
  p2 := public.get_company_students_page(nt.id('co_a'), p_limit := 4, p_offset := 4);
  PERFORM nt.ok('S2 a page at a time, with whether there is another, and no total unless asked',
    nt.page_students(p) = 's1,s2,s3,s4' AND (p->>'has_next')::boolean AND p->>'total' IS NULL
    AND nt.page_students(p2) = 's5,s7' AND NOT (p2->>'has_next')::boolean, nt.page_students(p) || ' / ' || nt.page_students(p2));
  SELECT r INTO row FROM jsonb_array_elements(public.get_company_students_page(nt.id('co_a'))->'rows') r WHERE (r->>'id')::uuid = nt.id('s1');
  PERFORM nt.ok('S3 each student carries their subscriptions in this company only, with line and period',
    jsonb_array_length(row->'subscriptions') = 1 AND row->'subscriptions'->0->>'line_name' = 'خط الأول'
    AND row->'subscriptions'->0->>'status' = 'active' AND row->'subscriptions'->0 ? 'period_label'
    AND row ?& ARRAY['phone', 'full_name', 'university', 'college', 'profile_image_url', 'created_at'], row::text);
  PERFORM nt.ok('S4 search by part of a name, by phone in any digits, by university',
    nt.page_students(public.get_company_students_page(nt.id('co_a'), 'طالب s4')) = 's4'
    AND nt.page_students(public.get_company_students_page(nt.id('co_a'), '٠١٢١٧٧٧٠٠٠٧')) = 's7'
    AND nt.page_students(public.get_company_students_page(nt.id('co_a'), '0121 777 0002')) = 's2'
    AND (public.get_company_students_page(nt.id('co_a'), 'جامعة', p_with_total := true)->>'total')::int = 6
    AND (public.get_company_students_page(nt.id('co_a'), 'لا أحد', p_with_total := true)->>'total')::int = 0);
  PERFORM nt.ok('S5 another company''s students are not hers to list',
    nt.code(format('SELECT public.get_company_students_page(%L)', nt.id('co_b'))) = '42501');
END $$;
SELECT nt.login('AB');
DO $$
BEGIN
  PERFORM nt.ok('S6 company B sees its one member, and of s1 nothing',
    nt.page_students(public.get_company_students_page(nt.id('co_b'))) = 's6'
    AND nt.code(format('SELECT public.get_company_students_page(%L)', nt.id('co_a'))) = '42501');
END $$;
SELECT nt.login('s1');
DO $$
BEGIN
  PERFORM nt.ok('S7 a student or a supervisor cannot list students',
    nt.code(format('SELECT public.get_company_students_page(%L)', nt.id('co_a'))) = '42501');
  PERFORM nt.login('SA');
  PERFORM nt.ok('S8 nor a supervisor', nt.code(format('SELECT public.get_company_students_page(%L)', nt.id('co_a'))) = '42501');
END $$;
SELECT nt.login('AS');
DO $$
BEGIN
  PERFORM nt.ok('S9 the platform may open any company''s list',
    (public.get_company_students_page(nt.id('co_a'), p_with_total := true)->>'total')::int = 6
    AND (public.get_company_students_page(nt.id('co_b'), p_with_total := true)->>'total')::int = 1);
END $$;

-- =============================================================================
-- Receipts waiting, and the decision
-- =============================================================================
SELECT nt.login('AA');
DO $$
DECLARE p jsonb; r jsonb;
BEGIN
  p := public.get_pending_receipts_page(nt.id('co_a'));
  r := p->'rows'->0;
  PERFORM nt.ok('R1 the waiting receipt with its student, line, station and period, in one answer',
    jsonb_array_length(p->'rows') = 1 AND (p->>'total')::int = 1 AND NOT (p->>'has_more')::boolean
    AND (r->>'id')::uuid = nt.receipt('s3') AND r->>'student_name' = 'طالب s3' AND r->>'line_name' = 'خط الأول'
    AND r->>'station_name' = 'S1' AND r->>'company_name' = 'E2E Notify A' AND r->>'subscription_type' = 'termly'
    AND (r->>'price')::numeric = 3000 AND r->>'period_label' IS NOT NULL AND r->>'image_url' LIKE '%_k1.jpg'
    AND (r->>'attempt_number')::int = 1, r::text);
  PERFORM nt.ok('R2 a rejection needs its reason; a decision must be one of the two',
    nt.code(format($q$SELECT public.review_receipt(%L, 'rejected')$q$, nt.receipt('s3'))) = '22023'
    AND nt.code(format($q$SELECT public.review_receipt(%L, 'maybe')$q$, nt.receipt('s3'))) = '22023');
END $$;
SELECT nt.login('AB');
DO $$
BEGIN
  PERFORM nt.ok('R3 another company''s admin can neither see nor decide it',
    nt.code(format('SELECT public.get_pending_receipts_page(%L)', nt.id('co_a'))) = '42501'
    AND jsonb_array_length(public.get_pending_receipts_page(nt.id('co_b'))->'rows') = 0
    AND nt.code(format($q$SELECT public.review_receipt(%L, 'approved')$q$, nt.receipt('s3'))) = 'BR010'
    AND nt.sub_status('s3') = 'pending_review');
END $$;
SELECT nt.login('s3');
DO $$
BEGIN
  PERFORM nt.ok('R4 the student cannot approve their own receipt',
    nt.code(format($q$SELECT public.review_receipt(%L, 'approved')$q$, nt.receipt('s3'))) IS NOT NULL
    AND nt.sub_status('s3') = 'pending_review');
END $$;
SELECT nt.login('AA');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.review_receipt(nt.receipt('s3'), 'approved');
  PERFORM nt.ok('R5 approved: the subscription is active and the answer carries the company''s numbers as they are now',
    r->>'status' = 'approved' AND (r->>'company_id')::uuid = nt.id('co_a') AND r->>'reviewed_at' IS NOT NULL
    AND nt.sub_status('s3') = 'active' AND (r->'overview'->>'pending_receipts')::int = 0
    AND r->'overview' = public.company_overview(nt.id('co_a')), r::text);
  PERFORM nt.ok('R6 deciding it again is refused with its own code',
    nt.code(format($q$SELECT public.review_receipt(%L, 'rejected', 'x')$q$, nt.receipt('s3'))) = 'BR010');
END $$;

-- =============================================================================
-- Who may open a receipt image (the rule now finds the subscription by its id)
-- =============================================================================
RESET ROLE;
CREATE OR REPLACE FUNCTION nt.sees_image() RETURNS integer LANGUAGE sql AS
  $$ SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'receipts' AND name LIKE '%\_k1.jpg' $$;
GRANT EXECUTE ON FUNCTION nt.sees_image() TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  PERFORM nt.login('AA');
  PERFORM nt.ok('I1 the company''s admin opens the receipt image', nt.sees_image() = 1);
  PERFORM nt.login('AB');
  PERFORM nt.ok('I2 another company''s admin does not', nt.sees_image() = 0);
  PERFORM nt.login('s3');
  PERFORM nt.ok('I3 the student opens their own', nt.sees_image() = 1);
  PERFORM nt.login('s1');
  PERFORM nt.ok('I4 another student does not', nt.sees_image() = 0);
  PERFORM nt.login('SA');
  PERFORM nt.ok('I5 a supervisor does not', nt.sees_image() = 0);
  PERFORM nt.login('AS');
  PERFORM nt.ok('I6 the platform does', nt.sees_image() = 1);
  PERFORM nt.ok('I7 a file name that is not a receipt''s names no subscription',
    public.receipt_object_subscription('x/not-a-uuid_1.jpg') IS NULL AND public.receipt_object_subscription('x') IS NULL
    AND public.receipt_object_subscription(nt.id('s3') || '/' || nt.sub('s3') || '_k1.jpg') = nt.sub('s3'));
  PERFORM nt.login('AA');
END $$;

-- =============================================================================
-- Overview, rider counts, report pages
-- =============================================================================
DO $$
DECLARE o jsonb; r jsonb; r2 jsonb;
BEGIN
  o := public.company_overview(nt.id('co_a'));
  PERFORM nt.ok('O1 the overview counts running subscriptions, riders and the busiest lines as before',
    (o->>'active_subscriptions')::int = (nt.truth(nt.id('co_a'))->>'running')::int
    AND (o->>'riders_today')::int = (nt.truth(nt.id('co_a'))->>'riders')::int AND (o->>'riders_today')::int = 2
    AND (SELECT sum((l->>'subscribers')::int) FROM jsonb_array_elements(o->'top_lines') l) = (o->>'active_subscriptions')::int
    AND (o->>'lines')::int = 2
    AND jsonb_array_length(o->'top_lines') = 2 AND (o->>'members')::int = 6 AND jsonb_array_length(o->'riders_week') = 7, o::text);
  r := public.admin_subscription_report('{"limit": 2}'::jsonb);
  r2 := public.admin_subscription_report('{"limit": 2, "offset": 2}'::jsonb);
  PERFORM nt.ok('P1 the report''s rows come a page at a time; the totals always cover everything',
    jsonb_array_length(r->'rows') = 2 AND (r->>'rows_total')::int = 6 AND (r->'totals'->>'count')::int = 6
    AND jsonb_array_length(r2->'rows') = 2 AND r->'totals' = r2->'totals'
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'rows') a JOIN jsonb_array_elements(r2->'rows') b ON a->>'id' = b->>'id')
    AND jsonb_array_length(public.admin_subscription_report('{}'::jsonb)->'rows') = 6, r::text);
END $$;
SELECT nt.login('SA');
DO $$
DECLARE c jsonb;
BEGIN
  c := public.get_lines_rider_counts(ARRAY[nt.id('L1')], public.cairo_today());
  PERFORM nt.ok('C1 rider counts of the supervisor''s lines in one call, the same rows as asking line by line',
    c ? nt.id('L1')::text AND c->(nt.id('L1')::text) = (
      SELECT jsonb_agg(to_jsonb(x)) FROM public.get_line_rider_counts_with_returns(nt.id('L1'), public.cairo_today()) x), c::text);
  PERFORM nt.ok('C2 a line that is not theirs is refused exactly as it is line by line',
    (nt.err(format('SELECT public.get_lines_rider_counts(ARRAY[%L::uuid], public.cairo_today())', nt.id('L2'))) IS NOT NULL)
    = (nt.err(format('SELECT * FROM public.get_line_rider_counts_with_returns(%L, public.cairo_today())', nt.id('L2'))) IS NOT NULL)
    AND public.get_lines_rider_counts(NULL, public.cairo_today()) = '{}'::jsonb);
END $$;
SELECT nt.login('s1');
DO $$
DECLARE p jsonb;
BEGIN
  PERFORM nt.ok('C3 a student gets nobody''s rider counts',
    nt.err(format('SELECT public.get_lines_rider_counts(ARRAY[%L::uuid], public.cairo_today())', nt.id('L1'))) IS NOT NULL
    OR public.get_lines_rider_counts(ARRAY[nt.id('L1')], public.cairo_today()) = '{}'::jsonb);
  p := public.get_my_notifications_page();
  PERFORM nt.ok('N1 the inbox still answers with its shape', p ? 'items' AND p ? 'unread' AND p ? 'next_before');
  PERFORM nt.ok('K1 the catalog still answers with its shape',
    jsonb_typeof(public.get_subscription_catalog()->'companies') = 'array' AND public.get_subscription_catalog() ? 'university');
END $$;
RESET ROLE;

-- =============================================================================
\o
\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, step, left(detail, 200) AS detail FROM nt.results ORDER BY n;
DO $$ DECLARE f int; BEGIN
  SELECT count(*) INTO f FROM nt.results WHERE NOT ok;
  IF f > 0 THEN RAISE EXCEPTION '% test step(s) failed', f; END IF;
  RAISE NOTICE 'all % steps passed', (SELECT count(*) FROM nt.results);
END $$;
ROLLBACK;
