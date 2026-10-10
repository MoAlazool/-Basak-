-- End-to-end test of 20261109000001_company_branding. Run by run_local.sh after
-- every migration; one transaction, rolled back at the end. Same fixture as
-- e2e_data_access.sql (company A: lines L1, L2; admin AA; supervisors SA, SB, SC;
-- students s1-s5, s7; company B: admin AB, student s6; platform admin AS; s3 has a
-- term subscription with a receipt waiting for review).
--
-- Covers: who may add, list, overwrite and delete files of the artwork bucket;
-- set_company_branding (who, which paths, the uploaded file, what it answers,
-- when Wallet cards are queued); that the logo printed on an issued receipt
-- outlives its replacement; and that every answer which names a company carries
-- logo_path and emblem_path.
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
-- Helpers for this test (as postgres)
-- =============================================================================
RESET ROLE;
-- 'A/emblem/e1/master.png' -> '<company A id>/emblem/e1/master.png'
CREATE FUNCTION nt.path(p text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT CASE left(p, 2) WHEN 'A/' THEN nt.id('co_a') || substr(p, 2) WHEN 'B/' THEN nt.id('co_b') || substr(p, 2) ELSE p END $$;
-- Each as the signed-in role: the error of adding a file (NULL = added), and how many rows a write touched.
CREATE FUNCTION nt.put(p text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN INSERT INTO storage.objects (bucket_id, name) VALUES ('wallet-assets', nt.path(p)); RETURN NULL;
EXCEPTION WHEN others THEN RETURN SQLERRM; END $$;
CREATE FUNCTION nt.del(p text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN DELETE FROM storage.objects WHERE bucket_id = 'wallet-assets' AND name LIKE nt.path(p) || '%'; GET DIAGNOSTICS n = ROW_COUNT; RETURN n; END $$;
CREATE FUNCTION nt.overwrite(p text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN UPDATE storage.objects SET metadata = '{"x": 1}' WHERE bucket_id = 'wallet-assets' AND name LIKE nt.path(p) || '%'; GET DIAGNOSTICS n = ROW_COUNT; RETURN n;
EXCEPTION WHEN others THEN RETURN -1; END $$;
CREATE FUNCTION nt.lists(p text) RETURNS integer LANGUAGE sql AS
  $$ SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'wallet-assets' AND name LIKE nt.path(p) || '%' $$;
-- How many files really exist (as postgres).
CREATE FUNCTION nt.files(p text) RETURNS integer LANGUAGE sql SECURITY DEFINER AS
  $$ SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'wallet-assets' AND name LIKE nt.path(p) || '%' $$;
CREATE FUNCTION nt.brand(p_company text, p_logo text, p_emblem text) RETURNS jsonb LANGUAGE sql AS
  $$ SELECT public.set_company_branding(nt.id(p_company), nt.path(p_logo), nt.path(p_emblem)) $$;
CREATE FUNCTION nt.brand_code(p_company text, p_logo text, p_emblem text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN PERFORM nt.brand(p_company, p_logo, p_emblem); RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE; END $$;
CREATE FUNCTION nt.saved(p_company text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT COALESCE(logo_path, '-') || ' | ' || COALESCE(emblem_path, '-') FROM public.companies WHERE id = nt.id(p_company) $$;
CREATE FUNCTION nt.receipt_logo(p_name text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT company_logo_path FROM public.subscription_receipts WHERE subscription_id = nt.sub(p_name) $$;
-- How many installed Wallet cards of a company wait for delivery (as postgres).
CREATE FUNCTION nt.dirty_cards(p_company text) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS
  $$ SELECT count(*)::int FROM public.wallet_passes WHERE company_id = nt.id(p_company) AND dirty_at IS NOT NULL $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nt TO authenticated, anon;
GRANT USAGE ON SCHEMA nt TO anon;

DO $$
DECLARE b storage.buckets%ROWTYPE;
BEGIN
  SELECT * INTO b FROM storage.buckets WHERE id = 'wallet-assets';
  PERFORM nt.ok('B0 the artwork bucket is public, PNG only, 2 MB a file',
    b.public AND b.allowed_mime_types = ARRAY['image/png'] AND b.file_size_limit = 2097152, to_jsonb(b)::text);
  PERFORM nt.ok('B1 a new company has neither mark', nt.saved('co_a') = '- | -');
END $$;

-- =============================================================================
-- The bucket: who adds, lists, overwrites and deletes
-- =============================================================================
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  PERFORM nt.login('AA');
  PERFORM nt.ok('F1 a company''s admin adds its logo, emblem and banner files',
    nt.put('A/logo/l1/master.png') IS NULL AND nt.put('A/logo/l1/google.png') IS NULL AND nt.put('A/logo/l1/icon@2x.png') IS NULL
    AND nt.put('A/emblem/e1/master.png') IS NULL AND nt.put('A/emblem/e1/small.png') IS NULL
    AND nt.put('A/banner/b1/google.png') IS NULL);
  PERFORM nt.ok('F2 ... but nothing into another company''s folder', nt.put('B/emblem/e1/master.png') IS NOT NULL
    AND nt.put('B/logo/x/master.png') IS NOT NULL);
  PERFORM nt.ok('F3 only PNG files in a logo, banner or emblem folder: no SVG, no HTML, no other place',
    nt.put('A/emblem/e1/mark.svg') IS NOT NULL AND nt.put('A/emblem/e1/page.html') IS NOT NULL
    AND nt.put('A/other/e1/master.png') IS NOT NULL AND nt.put('A/master.png') IS NOT NULL
    AND nt.put('A/emblem/e1/deep/master.png') IS NOT NULL AND nt.put('A/emblem/../../x/master.png') IS NOT NULL);
  PERFORM nt.ok('F4 a file is never overwritten in place, even by its own company', nt.overwrite('A/emblem/e1/') = 0);
  PERFORM nt.ok('F5 the company lists its own folder', nt.lists('A/') = 6, nt.lists('A/')::text);

  PERFORM nt.login('AB');
  PERFORM nt.ok('F6 another company''s admin cannot add to it, list it, overwrite it or delete from it',
    nt.put('A/emblem/e9/master.png') IS NOT NULL AND nt.lists('A/') = 0 AND nt.overwrite('A/') = 0 AND nt.del('A/') = 0
    AND nt.files('A/') = 6);
  PERFORM nt.login('s1');
  PERFORM nt.ok('F7 a student cannot add, list, overwrite or delete',
    nt.put('A/emblem/e9/master.png') IS NOT NULL AND nt.lists('A/') = 0 AND nt.overwrite('A/') = 0 AND nt.del('A/') = 0
    AND nt.files('A/') = 6);
  PERFORM nt.login('SA');
  PERFORM nt.ok('F8 nor can the company''s own supervisor',
    nt.put('A/emblem/e9/master.png') IS NOT NULL AND nt.lists('A/') = 0 AND nt.overwrite('A/') = 0 AND nt.del('A/') = 0
    AND nt.files('A/') = 6);
  PERFORM nt.login('AS');
  PERFORM nt.ok('F9 the platform admin adds to any company''s folder and lists it',
    nt.put('B/emblem/e1/master.png') IS NULL AND nt.put('B/emblem/e1/small.png') IS NULL AND nt.lists('A/') = 6);
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);
DO $$
BEGIN
  PERFORM nt.ok('F10 signed out: nothing can be added, listed or deleted, and the function cannot be called',
    nt.put('A/emblem/e9/master.png') IS NOT NULL AND nt.lists('A/') = 0 AND nt.del('A/') = 0
    AND nt.brand_code('co_a', NULL, 'A/emblem/e1') = '42501' AND nt.files('A/') = 6);
END $$;
RESET ROLE;

-- An installed Wallet card of company A, up to date: only a new logo may queue it.
INSERT INTO public.wallet_passes (student_id, platform, company_id, auth_token, content_hash)
VALUES (nt.id('s1'), 'apple', nt.id('co_a'), 'e2e-branding-token', md5(public.wallet_card_content(nt.id('s1'))::text));

-- =============================================================================
-- set_company_branding
-- =============================================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM nt.login('s1');
  PERFORM nt.ok('R1 a student cannot set a company''s identity', nt.brand_code('co_a', NULL, 'A/emblem/e1') = '42501');
  PERFORM nt.login('SA');
  PERFORM nt.ok('R2 nor its supervisor', nt.brand_code('co_a', NULL, 'A/emblem/e1') = '42501');
  PERFORM nt.login('AB');
  PERFORM nt.ok('R3 nor another company''s admin', nt.brand_code('co_a', NULL, 'A/emblem/e1') = '42501'
    AND nt.saved('co_a') = '- | -');

  PERFORM nt.login('AA');
  PERFORM nt.ok('R4 a path outside the company''s own folder is refused',
    nt.brand_code('co_a', NULL, 'B/emblem/e1') = '22023' AND nt.brand_code('co_a', 'B/logo/x', NULL) = '22023');
  PERFORM nt.ok('R5 so is the wrong kind of folder, a file, a URL or a path that climbs out',
    nt.brand_code('co_a', NULL, 'A/logo/l1') = '22023' AND nt.brand_code('co_a', 'A/emblem/e1', NULL) = '22023'
    AND nt.brand_code('co_a', NULL, 'A/emblem/e1/master.png') = '22023'
    AND nt.brand_code('co_a', NULL, 'https://example.com/' || nt.path('A/emblem/e1')) = '22023'
    AND nt.brand_code('co_a', NULL, 'A/emblem/../emblem/e1') = '22023');
  PERFORM nt.ok('R6 and a folder nothing was uploaded to', nt.brand_code('co_a', NULL, 'A/emblem/nothing') = '22023'
    AND nt.brand_code('co_a', 'A/logo/nothing', NULL) = '22023' AND nt.saved('co_a') = '- | -');

  r := nt.brand('co_a', NULL, 'A/emblem/e1');
  PERFORM nt.ok('R7 the emblem alone: saved, and no Wallet card is queued (the cards do not show it)',
    nt.saved('co_a') = '- | ' || nt.path('A/emblem/e1') AND nt.dirty_cards('co_a') = 0, r::text);
  r := nt.brand('co_a', 'A/logo/l1', 'A/emblem/e1');
  PERFORM nt.ok('R8 both: the answer is what was saved, nothing is stale, and the new logo queues the company''s cards',
    r->>'logo_path' = nt.path('A/logo/l1') AND r->>'emblem_path' = nt.path('A/emblem/e1') AND r->'stale' = '[]'::jsonb
    AND r->>'company_id' = nt.id('co_a')::text AND nt.saved('co_a') = nt.path('A/logo/l1') || ' | ' || nt.path('A/emblem/e1')
    AND nt.dirty_cards('co_a') = 1, r::text);
END $$;
RESET ROLE;
-- The card is delivered: it now shows the new logo.
UPDATE public.wallet_passes SET dirty_at = NULL, content_hash = md5(public.wallet_card_content(student_id)::text)
WHERE company_id = nt.id('co_a');
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM nt.login('AA');
  r := nt.brand('co_a', 'A/logo/l1', 'A/emblem/e1');
  PERFORM nt.ok('R9 saving the same again changes nothing and queues no card',
    r->'stale' = '[]'::jsonb AND r->>'logo_path' = nt.path('A/logo/l1') AND nt.dirty_cards('co_a') = 0);
  PERFORM nt.ok('R10 files in use cannot be deleted, by their own company either',
    nt.del('A/logo/l1/') = 0 AND nt.del('A/emblem/e1/') = 0 AND nt.files('A/') = 6);
  PERFORM nt.login('AB');
  PERFORM nt.ok('R11 a company cannot point at another company''s folder', nt.brand_code('co_b', NULL, 'A/emblem/e1') = '22023'
    AND nt.saved('co_b') = '- | -');

  -- A receipt is issued while l1 is the logo: approving s3's payment prints it.
  PERFORM nt.login('AA');
  PERFORM public.review_receipt(nt.receipt('s3'), 'approved');
  -- The receipt is issued at the end of the approving transaction: here, now.
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  PERFORM nt.ok('R12 an issued receipt carries the logo of the day it was issued', nt.receipt_logo('s3') = nt.path('A/logo/l1'),
    nt.receipt_logo('s3'));

  PERFORM nt.put('A/logo/l2/master.png');
  PERFORM nt.put('A/emblem/e2/master.png');
  PERFORM nt.put('A/emblem/e2/small.png');
  r := nt.brand('co_a', 'A/logo/l2', 'A/emblem/e2');
  PERFORM nt.ok('R13 replaced: the old emblem is stale, the old logo is not (a receipt shows it)',
    r->'stale' = jsonb_build_array(nt.path('A/emblem/e1')) AND r->>'logo_path' = nt.path('A/logo/l2'), r::text);
  PERFORM nt.ok('R14 the stale folder can now be removed; the receipt''s logo and the current marks cannot',
    nt.del('A/emblem/e1/') = 2 AND nt.del('A/logo/l1/') = 0 AND nt.del('A/logo/l2/') = 0 AND nt.del('A/emblem/e2/') = 0
    AND nt.files('A/logo/l1/') = 3);
  PERFORM nt.ok('R15 the receipt still shows the logo it was issued with', nt.receipt_logo('s3') = nt.path('A/logo/l1'));

  r := nt.brand('co_a', NULL, '  ');
  PERFORM nt.ok('R16 removing both: nothing is saved, and both folders are stale',
    nt.saved('co_a') = '- | -' AND r->'logo_path' = 'null'::jsonb AND r->'emblem_path' = 'null'::jsonb
    AND r->'stale' @> jsonb_build_array(nt.path('A/logo/l2'), nt.path('A/emblem/e2')) AND jsonb_array_length(r->'stale') = 2, r::text);
  PERFORM nt.ok('R17 ... and can be removed', nt.del('A/logo/l2/') = 1 AND nt.del('A/emblem/e2/') = 2);
  r := nt.brand('co_a', 'A/logo/l1', NULL);
  PERFORM nt.ok('R18 an older logo that still has its files can be chosen again', r->>'logo_path' = nt.path('A/logo/l1'));

  -- The Wallet banner lives in the same bucket and follows the same rule.
  PERFORM public.set_wallet_card_settings(nt.id('co_a'), '#00658D', '#FFFFFF', '#D6EEF9', NULL,
    nt.path('A/banner/b1'), nt.path('A/logo/l1'), NULL, NULL);
  PERFORM nt.ok('R19 the Wallet banner in use cannot be deleted; saving the Wallet design keeps the logo',
    nt.del('A/banner/b1/') = 0 AND nt.saved('co_a') = nt.path('A/logo/l1') || ' | -');
  PERFORM public.set_wallet_card_settings(nt.id('co_a'), '#00658D', '#FFFFFF', '#D6EEF9', NULL, NULL, nt.path('A/logo/l1'), NULL, NULL);
  PERFORM nt.ok('R20 ... and can once the design no longer uses it', nt.del('A/banner/b1/') = 1);

  PERFORM nt.login('AS');
  r := nt.brand('co_b', NULL, 'B/emblem/e1');
  PERFORM nt.ok('R21 the platform admin sets any company''s identity', nt.saved('co_b') = '- | ' || nt.path('B/emblem/e1'), r::text);
  PERFORM nt.ok('R22 even the platform cannot store another company''s folder, or a URL, on a company directly',
    nt.err(format('UPDATE public.companies SET emblem_path = %L WHERE id = %L', nt.path('A/emblem/e1'), nt.id('co_b'))) IS NOT NULL
    AND nt.err(format('UPDATE public.companies SET emblem_path = %L WHERE id = %L', 'https://x.test/a.png', nt.id('co_b'))) IS NOT NULL);
  PERFORM nt.ok('R23 a company that does not exist', nt.brand_code('AS', NULL, NULL) IS NOT NULL);
  PERFORM nt.login('AA');
  PERFORM nt.err(format('UPDATE public.companies SET emblem_path = %L, logo_path = NULL WHERE id = %L', nt.path('A/emblem/e2'), nt.id('co_a')));
  PERFORM nt.ok('R24 a company''s admin cannot write the columns directly, only through the function',
    nt.saved('co_a') = nt.path('A/logo/l1') || ' | -');
END $$;

-- =============================================================================
-- Every answer that names a company carries both marks
-- =============================================================================
DO $$
DECLARE o jsonb; c jsonb; n jsonb;
BEGIN
  PERFORM nt.login('AA');
  PERFORM nt.put('A/emblem/e3/master.png');
  PERFORM nt.brand('co_a', 'A/logo/l1', 'A/emblem/e3');
  o := public.company_overview(nt.id('co_a'));
  PERFORM nt.ok('V1 the company''s overview', o->'company'->>'logo_path' = nt.path('A/logo/l1')
    AND o->'company'->>'emblem_path' = nt.path('A/emblem/e3') AND o->'company'->>'name' = 'E2E Notify A'
    AND o ?& ARRAY['members', 'revenue', 'top_lines', 'riders_week'], (o->'company')::text);
  PERFORM public.compose_notification(nt.id('co_a'), 'تنبيه', 'نص التنبيه.', '{"kind": "company"}');

  PERFORM nt.login('AS');
  SELECT r->'company' INTO c FROM jsonb_array_elements(public.platform_overview()->'per_company') r
  WHERE r->'company'->>'id' = nt.id('co_a')::text;
  PERFORM nt.ok('V2 the platform''s list of companies', c->>'logo_path' = nt.path('A/logo/l1')
    AND c->>'emblem_path' = nt.path('A/emblem/e3'), c::text);
  SELECT r->'company' INTO c FROM jsonb_array_elements(public.platform_overview()->'per_company') r
  WHERE r->'company'->>'id' = nt.id('co_b')::text;
  PERFORM nt.ok('V3 ... a company without a logo answers null, not a missing key',
    c ? 'logo_path' AND c->'logo_path' = 'null'::jsonb AND c->>'emblem_path' = nt.path('B/emblem/e1'), c::text);

  PERFORM nt.login('s1');
  SELECT x INTO c FROM jsonb_array_elements(public.get_subscription_catalog()->'companies') x WHERE x->>'id' = nt.id('co_a')::text;
  PERFORM nt.ok('V4 the app''s catalog', c->>'logo_path' = nt.path('A/logo/l1') AND c->>'emblem_path' = nt.path('A/emblem/e3')
    AND jsonb_typeof(c->'lines') = 'array', (c - 'lines')::text);
  PERFORM nt.ok('V5 a student reads both from the company row (the subscription''s company)',
    (SELECT logo_path || ' | ' || emblem_path FROM public.companies WHERE id = nt.id('co_a')) = nt.saved('co_a'));
  n := public.get_my_notifications_page()->'items'->0;
  PERFORM nt.ok('V6 a notification says which company it is from',
    n->'company'->>'id' = nt.id('co_a')::text AND n->'company'->>'name' = 'E2E Notify A'
    AND n->'company'->>'logo_path' = nt.path('A/logo/l1') AND n->'company'->>'emblem_path' = nt.path('A/emblem/e3')
    AND n ?& ARRAY['id', 'title', 'body', 'read', 'sender_role', 'data'], n::text);
  PERFORM nt.login('SA');
  PERFORM nt.ok('V7 a supervisor reads both from their own company''s row',
    (SELECT emblem_path FROM public.companies WHERE id = nt.id('co_a')) = nt.path('A/emblem/e3'));
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
