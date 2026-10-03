-- End-to-end test of the 2026-10-04 changes, run by run_local.sh after every
-- migration (and the seed_before_* fixture) has been applied. Every step runs
-- with the same role + JWT claims PostgREST would use for that user.
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\o /dev/null

CREATE SCHEMA t;
GRANT USAGE ON SCHEMA t TO anon, authenticated, service_role;
CREATE TABLE t.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE TABLE t.vars (k text PRIMARY KEY, v text);
CREATE FUNCTION t.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO t.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION t.setv(p_k text, p_v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS
$$ INSERT INTO t.vars VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v $$;
CREATE FUNCTION t.getv(p_k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT v FROM t.vars WHERE k = p_k $$;
-- Runs SQL as the CURRENT role; returns the error message or NULL.
CREATE FUNCTION t.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLERRM; END $$;
CREATE FUNCTION t.login(p_uid uuid, p_role text DEFAULT 'authenticated') RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, false) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA t TO anon, authenticated, service_role;

-- ids
\set super     '''a0000000-0000-0000-0000-000000000001'''
\set admin1    '''a0000000-0000-0000-0000-000000000002'''
\set admin2    '''a0000000-0000-0000-0000-000000000003'''
\set sup1      '''b0000000-0000-0000-0000-000000000001'''
\set sup2      '''b0000000-0000-0000-0000-000000000002'''
\set sup3      '''b0000000-0000-0000-0000-000000000003'''
\set st1       '''c0000000-0000-0000-0000-000000000001'''
\set st2       '''c0000000-0000-0000-0000-000000000002'''
\set st3       '''c0000000-0000-0000-0000-000000000003'''

-- =============================================================================
-- A. Backfills done by the migrations (as postgres)
-- =============================================================================
DO $$
DECLARE r record; y int := extract(year FROM public.cairo_today())::int;
  first_start date; first_end date;
BEGIN
  SELECT start_date, end_date INTO first_start, first_end FROM public.academic_periods(
    CASE WHEN public.cairo_today() < make_date(y, 9, 5) THEN y - 1 ELSE y END) WHERE period_code = 'first';

  PERFORM t.ok('A1 terms seeded with the requested dates',
    (SELECT string_agg(format('%s:%s-%s>%s-%s', code, start_day, start_month, end_day, end_month), ' ' ORDER BY sort_order)
       FROM public.academic_terms) = 'first:5-9>30-1 second:1-2>30-6 summer:1-7>1-9');
  PERFORM t.ok('A2 S1 keeps its direct line only',
    ARRAY(SELECT line_id::text FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000001')
      = ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa']);
  PERFORM t.ok('A3 S2 (no direct line before) keeps its old company-wide scope explicitly',
    (SELECT count(*) FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000002') = 2);
  PERFORM t.ok('A4 primary contact of line aaaa is still S1',
    (SELECT supervisor_id::text FROM public.lines WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'b0000000-0000-0000-0000-000000000001');
  PERFORM t.ok('A5 duplicate same-day check-ins collapsed to one',
    (SELECT count(*) FROM public.supervisor_scan_events WHERE result = 'checked_in'
       AND student_id = 'c0000000-0000-0000-0000-000000000001') = 1);
  SELECT * INTO r FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000001';
  PERFORM t.ok('A6 legacy active termly moved onto the first semester',
    r.period_code = 'first' AND r.start_date = first_start AND r.end_date = first_end, format('%s %s..%s', r.period_code, r.start_date, r.end_date));
  SELECT * INTO r FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000002';
  PERFORM t.ok('A7 legacy unpaid termly got the current period dates',
    r.period_code = 'first' AND r.start_date = first_start AND r.status = 'pending_payment');
  SELECT * INTO r FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000003';
  PERFORM t.ok('A8 legacy yearly moved onto the annual period (5 Sep -> 30 Jun)',
    r.period_code = 'annual' AND r.start_date = first_start AND to_char(r.end_date, 'DD-MM') = '30-06');
  PERFORM t.ok('A9 dangling profile photo reference removed, real one kept',
    (SELECT profile_image_url FROM public.students WHERE id = 'c0000000-0000-0000-0000-000000000002') IS NULL
    AND (SELECT profile_image_url FROM public.students WHERE id = 'c0000000-0000-0000-0000-000000000001') IS NOT NULL);
  PERFORM t.ok('A10 old one-subscription-per-student index replaced by the period exclusion constraint',
    NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_one_active_sub_per_student')
    AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subscriptions_no_overlap'));
  PERFORM t.ok('A11 old supervisor payload (password column) is still rejected = was the dashboard 400',
    t.err($q$INSERT INTO public.supervisors (full_name, phone, company_id, password) VALUES ('x','01099999999','11111111-1111-1111-1111-111111111111','1')$q$) LIKE '%password%');
END $$;

SELECT t.setv('station', station_id::text), t.setv('dep', departure_time::text), t.setv('ret', return_time::text)
FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000001';
-- A student created now (for "older client" + expiry tests).
INSERT INTO auth.users (id, email) VALUES ('c0000000-0000-0000-0000-000000000004', '01100000004@busak.app');
INSERT INTO public.students (id, phone, full_name, university) VALUES ('c0000000-0000-0000-0000-000000000004', '01100000004', 'Student Four A B', 'جامعة المنصورة');

-- =============================================================================
-- B. Supervisor scope and line assignment
-- =============================================================================
SET ROLE authenticated;
SELECT t.login(:sup1);
DO $$
DECLARE d jsonb;
BEGIN
  PERFORM t.ok('B1 supervisor sees only assigned line',
    ARRAY(SELECT line_id::text FROM public.get_supervisor_assigned_line_ids()) = ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa']);
  d := public.get_supervisor_dashboard();
  PERFORM t.ok('B2 dashboard: 1 line, no receipt counters, trip_times present',
    jsonb_array_length(d->'lines') = 1 AND NOT (d->'totals' ? 'pending_receipts') AND d ? 'trip_times', d->>'totals');
  PERFORM t.ok('B3 supervisor cannot change assignments',
    t.err($q$SELECT public.set_supervisor_lines('b0000000-0000-0000-0000-000000000001', ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[])$q$) IS NOT NULL);
  PERFORM t.ok('B4 supervisor cannot write supervisor_lines directly',
    t.err($q$INSERT INTO public.supervisor_lines (supervisor_id, line_id) VALUES ('b0000000-0000-0000-0000-000000000001','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$q$) IS NOT NULL);
END $$;

SELECT t.login(:admin1);
DO $$
BEGIN
  PERFORM public.set_supervisor_lines('b0000000-0000-0000-0000-000000000002', ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[]);
  PERFORM t.ok('B5 company admin narrows S2 to line bbbb',
    ARRAY(SELECT line_id::text FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000002')
      = ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']);
  PERFORM t.ok('B6 company admin cannot touch another company''s supervisor',
    t.err($q$SELECT public.set_supervisor_lines('b0000000-0000-0000-0000-000000000003', ARRAY[]::uuid[])$q$) LIKE '%غير مسموح%');
  PERFORM t.ok('B7 a line of another company cannot be assigned',
    t.err($q$SELECT public.set_supervisor_lines('b0000000-0000-0000-0000-000000000001', ARRAY['cccccccc-cccc-cccc-cccc-cccccccccccc']::uuid[])$q$) LIKE '%لا تتبع%');
  PERFORM t.ok('B8 company admin sees only own company assignments',
    NOT EXISTS (SELECT 1 FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000003'));
  -- An old dashboard build writing lines.supervisor_id directly
  UPDATE public.lines SET supervisor_id = 'b0000000-0000-0000-0000-000000000002' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  PERFORM t.ok('B9 legacy direct line.supervisor_id write becomes an assignment',
    EXISTS (SELECT 1 FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000002' AND line_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    AND NOT EXISTS (SELECT 1 FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000001' AND line_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  PERFORM public.set_supervisor_lines('b0000000-0000-0000-0000-000000000001', ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa']::uuid[]);
  PERFORM public.set_supervisor_lines('b0000000-0000-0000-0000-000000000002', ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[]);
END $$;

-- The Edge Function path: service role, no user.
RESET ROLE; SELECT set_config('request.jwt.claims', '', false); SET ROLE service_role; SELECT t.login(NULL, 'service_role');
DO $$ BEGIN
  PERFORM t.ok('B10 service role (admin-create-supervisor) can assign lines',
    t.err($q$SELECT public.set_supervisor_lines('b0000000-0000-0000-0000-000000000003', ARRAY['cccccccc-cccc-cccc-cccc-cccccccccccc']::uuid[])$q$) IS NULL);
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false); SET ROLE anon; SELECT t.login(NULL, 'anon');
DO $$ BEGIN
  PERFORM t.ok('B11 anon cannot call set_supervisor_lines',
    t.err($q$SELECT public.set_supervisor_lines('b0000000-0000-0000-0000-000000000003', ARRAY[]::uuid[])$q$) LIKE '%permission denied%');
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false); SET ROLE authenticated;

-- A supervisor with no line sees nothing (the old company-wide fallback is gone).
SELECT t.login(:admin1);
SELECT public.set_supervisor_lines(:sup2, ARRAY[]::uuid[]);
SELECT t.login(:sup2);
DO $$ BEGIN
  PERFORM t.ok('B12 supervisor without lines sees no line',
    jsonb_array_length(public.get_supervisor_dashboard()->'lines') = 0
    AND (public.get_supervisor_dashboard()->'profile'->>'assignment') = 'none');
END $$;
SELECT t.login(:admin1);
SELECT public.set_supervisor_lines(:sup2, ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[]);

-- =============================================================================
-- C. Receipts: upload by student, review by admins only
-- =============================================================================
SELECT t.login(:st2);
DO $$
DECLARE v_path text := 'c0000000-0000-0000-0000-000000000002/d0000000-0000-0000-0000-000000000002_1700000000.jpg';
  r record;
BEGIN
  PERFORM t.ok('C1 student uploads receipt image into own folder',
    t.err(format($q$INSERT INTO storage.objects (bucket_id, name) VALUES ('receipts', %L)$q$, v_path)) IS NULL);
  PERFORM t.ok('C2 student cannot upload into another student''s folder',
    t.err($q$INSERT INTO storage.objects (bucket_id, name) VALUES ('receipts', 'c0000000-0000-0000-0000-000000000001/x_1.jpg')$q$) IS NOT NULL);
  PERFORM t.ok('C3 receipt pointing at another subscription''s image is rejected',
    t.err($q$INSERT INTO public.receipts (subscription_id, image_url) VALUES ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002/d0000000-0000-0000-0000-000000000001_1.jpg')$q$) LIKE '%لا يطابق%');
  INSERT INTO public.receipts (subscription_id, image_url) VALUES ('d0000000-0000-0000-0000-000000000002', v_path);
  SELECT r2.*, s.status AS sub_status INTO r FROM public.receipts r2 JOIN public.subscriptions s ON s.id = r2.subscription_id
  WHERE r2.subscription_id = 'd0000000-0000-0000-0000-000000000002';
  PERFORM t.ok('C4 receipt stored with attempt 1, amount snapshot, subscription pending_review',
    r.attempt_number = 1 AND r.amount = 3800 AND r.sub_status = 'pending_review', format('%s %s %s', r.attempt_number, r.amount, r.sub_status));
  PERFORM t.ok('C5 second receipt while one is pending is refused',
    t.err(format($q$INSERT INTO public.receipts (subscription_id, image_url) VALUES ('d0000000-0000-0000-0000-000000000002', %L)$q$,
      'c0000000-0000-0000-0000-000000000002/d0000000-0000-0000-0000-000000000002_2.jpg')) IS NOT NULL);
  PERFORM t.ok('C6 student can read own receipt + image',
    (SELECT count(*) FROM public.receipts) = 1 AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'receipts') = 1);
  PERFORM t.ok('C7 student cannot approve own receipt',
    (SELECT count(*) FROM (SELECT 1) x) = 1 AND t.err($q$UPDATE public.receipts SET status = 'approved'$q$) IS NULL
    AND (SELECT status FROM public.receipts LIMIT 1) = 'pending');
END $$;

SELECT t.login(:sup2);  -- assigned to the receipt's line bbbb
DO $$ BEGIN
  PERFORM t.ok('C8 supervisor of that very line sees no receipt row', (SELECT count(*) FROM public.receipts) = 0);
  PERFORM t.ok('C9 supervisor sees no receipt image', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'receipts') = 0);
  UPDATE public.receipts SET status = 'approved';
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);
DO $$ BEGIN
  PERFORM t.ok('C10b receipt still pending after supervisor attempt',
    (SELECT status FROM public.receipts WHERE subscription_id = 'd0000000-0000-0000-0000-000000000002') = 'pending');
END $$;
SET ROLE authenticated;

SELECT t.login(:admin2);  -- other company
DO $$ BEGIN
  PERFORM t.ok('C11 other company admin sees neither receipt, image nor photo',
    (SELECT count(*) FROM public.receipts) = 0 AND (SELECT count(*) FROM storage.objects) = 0);
  UPDATE public.receipts SET status = 'approved';
END $$;
SELECT t.login(:super);
DO $$ BEGIN
  PERFORM t.ok('C12 super admin sees receipt + image',
    (SELECT count(*) FROM public.receipts) = 1 AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'receipts') = 1);
END $$;
SELECT t.login(:admin1);
DO $$
DECLARE r record; before_start date; before_end date;
BEGIN
  PERFORM t.ok('C13 own company admin sees receipt + image',
    (SELECT count(*) FROM public.receipts) = 1 AND (SELECT count(*) FROM storage.objects WHERE bucket_id = 'receipts') = 1);
  PERFORM t.ok('C13b own company admin can open the student''s profile photo (was the avatar sign 400)',
    (SELECT count(*) FROM storage.objects WHERE bucket_id = 'student-avatars') = 1);
  SELECT start_date, end_date INTO before_start, before_end FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000002';
  UPDATE public.receipts SET status = 'approved' WHERE subscription_id = 'd0000000-0000-0000-0000-000000000002';
  SELECT s.*, public.period_phase(s) AS phase INTO r FROM public.subscriptions s WHERE id = 'd0000000-0000-0000-0000-000000000002';
  PERFORM t.ok('C14 approval activates for the period without moving its dates',
    r.status = 'active' AND r.start_date = before_start AND r.end_date = before_end AND r.phase = 'current',
    format('%s %s..%s %s', r.status, r.start_date, r.end_date, r.phase));
  PERFORM t.ok('C14b approval records paid_at (revenue)', r.paid_at IS NOT NULL);
  PERFORM t.ok('C15 reviewer recorded',
    (SELECT reviewed_by::text FROM public.receipts WHERE subscription_id = 'd0000000-0000-0000-0000-000000000002') = 'a0000000-0000-0000-0000-000000000002');
END $$;

-- =============================================================================
-- D. QR check-in: once per student per day
-- =============================================================================
SELECT t.login(:sup1);
DO $$
DECLARE r1 jsonb; r2 jsonb; qr uuid;
BEGIN
  SELECT qr_code_value INTO qr FROM public.students WHERE id = 'c0000000-0000-0000-0000-000000000001';
  r1 := public.supervisor_check_in_student(qr, 'departure');
  r2 := public.supervisor_check_in_student(qr, 'return');
  PERFORM t.ok('D1 first scan today checks in', r1->>'result' = 'checked_in', r1->>'result');
  PERFORM t.ok('D2 second scan the same day (even other direction) is rejected with a clear message',
    r2->>'result' = 'already_checked_in' AND r2->>'message' LIKE '%already been checked in today%'
    AND r2->>'checked_in_at' = r1->>'checked_in_at', r2->>'message');
  PERFORM t.ok('D3 supervisor cannot insert a check-in row directly',
    t.err(format($q$INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, ride_date, direction, result)
      VALUES (auth.uid(), 'c0000000-0000-0000-0000-000000000001', public.cairo_today() + 1, 'departure', 'checked_in')$q$)) IS NOT NULL);
END $$;
SELECT t.login(:admin1);
SELECT public.set_supervisor_lines(:sup2, ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']::uuid[]);
SELECT t.login(:sup2);
DO $$ BEGIN
  PERFORM t.ok('D4 another supervisor scanning the same student today is rejected too',
    public.supervisor_check_in_student((SELECT qr_code_value FROM public.students WHERE id = 'c0000000-0000-0000-0000-000000000001'))->>'result' = 'already_checked_in');
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);
DO $$ BEGIN
  PERFORM t.ok('D5 exactly one check-in row today',
    (SELECT count(*) FROM public.supervisor_scan_events WHERE student_id = 'c0000000-0000-0000-0000-000000000001'
       AND ride_date = public.cairo_today() AND result = 'checked_in') = 1);
  PERFORM t.ok('D6 database rejects a second check-in row even without the RPC',
    t.err($q$INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, ride_date, direction, result)
      VALUES ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', public.cairo_today(), 'return', 'checked_in')$q$) LIKE '%duplicate key%');
  PERFORM t.ok('D7 the same student can be checked in on a different day',
    t.err($q$INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, ride_date, direction, result)
      VALUES ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', public.cairo_today() + 1, 'departure', 'checked_in')$q$) IS NULL);
END $$;
SET ROLE authenticated;

-- =============================================================================
-- E. Periods, advance payment, annual switch
-- =============================================================================
SELECT t.login(:st1);
DO $$
DECLARE codes text; r record; sid uuid;
BEGIN
  SELECT string_agg(period_code || ':' || phase, ',' ORDER BY start_date, subscription_type) INTO codes
  FROM public.get_purchasable_periods('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM t.ok('E1 purchasable now: current first semester, annual, next (second) semester',
    codes = 'first:current,annual:current,second:upcoming', codes);

  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price, departure_time, return_time, period_code, academic_year)
  SELECT auth.uid(), s.line_id, s.station_id, 'termly', 1, s.departure_time, s.return_time, 'second', p.academic_year
  FROM public.subscriptions s, public.get_purchasable_periods(s.line_id) p
  WHERE s.id = 'd0000000-0000-0000-0000-000000000001' AND p.period_code = 'second'
  RETURNING id INTO sid;
  SELECT s.*, public.period_phase(s) AS phase, public.period_label(s) AS label INTO r FROM public.subscriptions s WHERE id = sid;
  PERFORM t.ok('E2 student pays next semester in advance: pending, 1 Feb -> 30 Jun, upcoming, server price',
    r.status = 'pending_payment' AND to_char(r.start_date, 'DD-MM') = '01-02' AND to_char(r.end_date, 'DD-MM') = '30-06'
    AND r.phase = 'upcoming' AND r.price = 3500, format('%s %s..%s %s %s %s', r.status, r.start_date, r.end_date, r.phase, r.price, r.label));
  PERFORM t.setv('st1_second', sid::text);
  PERFORM t.ok('E3 current subscription still shows as current',
    (SELECT public.period_phase(s) FROM public.subscriptions s WHERE id = 'd0000000-0000-0000-0000-000000000001') = 'current');
  PERFORM t.ok('E4 second subscription for an already covered period is refused',
    t.err($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price, departure_time, return_time, period_code, academic_year)
      SELECT auth.uid(), line_id, station_id, 'termly', 1, departure_time, return_time, 'first', academic_year
      FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000001'$q$) LIKE '%يغطي هذه الفترة%');
  PERFORM t.ok('E5 a period that is not yet payable (summer) is refused',
    t.err($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price, departure_time, return_time, period_code, academic_year)
      SELECT auth.uid(), line_id, station_id, 'termly', 1, departure_time, return_time, 'summer', academic_year
      FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000001'$q$) LIKE '%غير متاحة%');
  UPDATE public.subscriptions SET end_date = '2030-01-01', price = 1 WHERE id = sid;
  PERFORM t.ok('E6 student cannot edit subscription dates or price',
    (SELECT end_date <> '2030-01-01' AND price = 3500 FROM public.subscriptions WHERE id = sid));
END $$;

-- Annual switch
SELECT t.login(:admin1);
DO $$ BEGIN
  PERFORM t.ok('E7 company admin cannot change the global switch',
    t.err($q$SELECT public.set_annual_subscription(false)$q$) LIKE '%مدير النظام%');
  PERFORM t.ok('E8 company admin cannot change another company',
    t.err($q$SELECT public.set_annual_subscription(false, '22222222-2222-2222-2222-222222222222')$q$) IS NOT NULL);
  PERFORM public.set_annual_subscription(false, '11111111-1111-1111-1111-111111111111');
  PERFORM t.ok('E9 settings snapshot scoped to own company',
    jsonb_array_length(public.get_subscription_settings()->'companies') = 1
    AND (public.get_subscription_settings()->'companies'->0->>'effective')::boolean = false);
END $$;
SELECT t.login('c0000000-0000-0000-0000-000000000004');
DO $$ BEGIN
  PERFORM t.ok('E10 annual disabled for company 1: not offered',
    NOT EXISTS (SELECT 1 FROM public.get_purchasable_periods('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') WHERE period_code = 'annual')
    AND EXISTS (SELECT 1 FROM public.get_purchasable_periods('cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE period_code = 'annual'));
  PERFORM t.ok('E11 annual disabled for company 1: purchase refused by the database',
    t.err(format($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price, departure_time, return_time)
      VALUES (auth.uid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', %L, 'yearly', 1, %L, %L)$q$, t.getv('station'), t.getv('dep'), t.getv('ret')))
      LIKE '%السنوي غير متاح%');
END $$;
SELECT t.login(:super);
SELECT public.set_annual_subscription(false);
SELECT t.login('c0000000-0000-0000-0000-000000000004');
DO $$ BEGIN
  PERFORM t.ok('E12 super admin global switch off hides annual everywhere',
    NOT EXISTS (SELECT 1 FROM public.get_purchasable_periods('cccccccc-cccc-cccc-cccc-cccccccccccc') WHERE period_code = 'annual'));
END $$;
SELECT t.login(:super);
SELECT public.set_annual_subscription(true);
SELECT public.set_annual_subscription(true, '11111111-1111-1111-1111-111111111111');
SELECT t.login('c0000000-0000-0000-0000-000000000004');
DO $$
DECLARE r record;
BEGIN
  -- An older app build: no period fields at all.
  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price, departure_time, return_time)
  VALUES (auth.uid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', t.getv('station')::uuid, 'yearly', 1, t.getv('dep')::time, t.getv('ret')::time);
  SELECT * INTO r FROM public.subscriptions WHERE student_id = auth.uid();
  PERFORM t.ok('E13 annual re-enabled; older client without period gets the current annual period',
    r.period_code = 'annual' AND r.price = 6500 AND to_char(r.start_date, 'DD-MM') = '05-09', format('%s %s %s', r.period_code, r.price, r.start_date));
END $$;

-- Rider counts / trip times with a current AND an upcoming paid subscription.
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);
UPDATE public.subscriptions SET status = 'active' WHERE id = t.getv('st1_second')::uuid;
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, departure_time, return_time, is_returning)
SELECT 'c0000000-0000-0000-0000-000000000001', public.cairo_today(), true, departure_time, return_time, true
FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000001';
SET ROLE authenticated;
SELECT t.login(:sup1);
DO $$
DECLARE d jsonb; n bigint;
BEGIN
  SELECT sum(riding_count) INTO n FROM public.get_line_rider_counts_with_returns('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.cairo_today());
  PERFORM t.ok('E14 rider count does not double count a student holding current + upcoming subscriptions', n = 1, n::text);
  d := public.get_supervisor_dashboard();
  PERFORM t.ok('E15 dashboard trip_times: 1 student departing and 1 returning at their times',
    (SELECT count(*) FROM jsonb_array_elements(d->'trip_times') x
       WHERE (x->>'students')::int = 1 AND x->>'ride_date' = public.cairo_today()::text) = 2
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(d->'trip_times') x WHERE x->>'direction' = 'return'), d->>'trip_times');
END $$;

-- Term dates are edited in one place and follow through.
SELECT t.login(:admin1);
DO $$ BEGIN
  UPDATE public.academic_terms SET end_day = 31 WHERE code = 'first';
  PERFORM t.ok('E16 company admin cannot edit semester dates', (SELECT end_day FROM public.academic_terms WHERE code = 'first') = 30);
END $$;
SELECT t.login(:super);
DO $$ BEGIN
  PERFORM t.ok('E17 overlapping semesters are rejected',
    t.err($q$UPDATE public.academic_terms SET start_month = 1, start_day = 15 WHERE code = 'second'$q$) LIKE '%يتداخل%');
  PERFORM t.ok('E17b invalid day (31 Feb) is rejected',
    t.err($q$UPDATE public.academic_terms SET end_month = 2, end_day = 31 WHERE code = 'second'$q$) IS NOT NULL);
  UPDATE public.academic_terms SET end_day = 31 WHERE code = 'first';
  PERFORM t.ok('E18 super admin edit propagates to open first-semester subscriptions',
    (SELECT to_char(end_date, 'DD-MM') FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000001') = '31-01');
  UPDATE public.academic_terms SET end_day = 30 WHERE code = 'first';
END $$;

-- Expiry of an unpaid period that ended.
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);
DO $$ BEGIN
  INSERT INTO auth.users (id, email) VALUES ('c0000000-0000-0000-0000-000000000005', '01100000005@busak.app');
  INSERT INTO public.students (id, phone, full_name, university) VALUES ('c0000000-0000-0000-0000-000000000005', '01100000005', 'Student Five A B', 'جامعة المنصورة');
  INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price, departure_time, return_time)
  SELECT 'd0000000-0000-0000-0000-000000000099', 'c0000000-0000-0000-0000-000000000005', line_id, station_id, 'daily', 'active',
         public.cairo_today() - 3, public.cairo_today() - 3, 50, departure_time, return_time
  FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000002';
  PERFORM public.expire_finished_subscriptions();
  INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price, departure_time, return_time,
                                    period_code, academic_year)
  SELECT 'd0000000-0000-0000-0000-000000000098', 'c0000000-0000-0000-0000-000000000005', line_id, station_id, 'termly', 'pending_payment',
         public.cairo_today() - 200, public.cairo_today() - 100, 3500, departure_time, return_time, NULL, NULL
  FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000002';
  UPDATE public.subscriptions SET start_date = public.cairo_today() - 200, end_date = public.cairo_today() - 100
  WHERE id = 'd0000000-0000-0000-0000-000000000098';
  PERFORM public.expire_finished_subscriptions();
  PERFORM t.ok('E19b an unpaid period that ended expires but is not revenue',
    (SELECT status = 'expired' AND paid_at IS NULL FROM public.subscriptions WHERE id = 'd0000000-0000-0000-0000-000000000098'));
  PERFORM t.ok('E19 ended subscriptions are expired, period_phase expired',
    (SELECT status = 'expired' AND public.period_phase(s) = 'expired' FROM public.subscriptions s WHERE id = 'd0000000-0000-0000-0000-000000000099'));
END $$;

-- =============================================================================
-- F. Student password reset
-- =============================================================================
SET ROLE anon; SELECT t.login(NULL, 'anon');
DO $$ BEGIN
  PERFORM t.ok('F1 anon can request a reset; unknown number gets the same answer',
    public.request_student_password_reset('+20 110 000 0001')->>'status' = 'requested'
    AND public.request_student_password_reset('01555555555')->>'status' = 'requested');
  PERFORM t.ok('F2 invalid phone rejected', t.err($q$SELECT public.request_student_password_reset('123')$q$) IS NOT NULL);
  PERFORM t.ok('F3 anon cannot verify codes', t.err($q$SELECT public.check_student_password_reset_code('01100000001','000000')$q$) LIKE '%permission denied%');
  PERFORM t.ok('F4 anon cannot read reset requests', t.err($q$SELECT * FROM public.password_reset_requests$q$) LIKE '%permission denied%');
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);
SELECT t.setv('req', (SELECT id::text FROM public.password_reset_requests LIMIT 1));
SET ROLE authenticated;
SELECT t.login(:admin2);
DO $$ BEGIN
  PERFORM t.ok('F5 other company admin does not see the request',
    NOT EXISTS (SELECT 1 FROM public.admin_list_password_reset_requests() WHERE student_phone = '01100000001'));
  PERFORM t.ok('F6 other company admin cannot issue a code',
    t.err(format('SELECT public.admin_issue_password_reset_code(%L)', t.getv('req'))) IS NOT NULL);
END $$;
SELECT t.login(:admin1);
DO $$
DECLARE req uuid; c jsonb;
BEGIN
  SELECT id INTO req FROM public.admin_list_password_reset_requests() WHERE student_phone = '01100000001';
  PERFORM t.ok('F7 own company admin sees exactly one open request', req IS NOT NULL
    AND (SELECT count(*) FROM public.admin_list_password_reset_requests()) = 1);
  c := public.admin_issue_password_reset_code(req);
  PERFORM t.ok('F8 a 6-digit code is issued', c->>'code' ~ '^[0-9]{6}$');
  PERFORM t.setv('code', c->>'code');
  PERFORM t.ok('F9 authenticated users cannot verify codes themselves',
    t.err($q$SELECT public.check_student_password_reset_code('01100000001','000000')$q$) LIKE '%permission denied%');
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);
DO $$ BEGIN
  PERFORM t.ok('F10 only a bcrypt hash of the code is stored',
    (SELECT code_hash LIKE '$2a$%' AND code_hash <> t.getv('code') FROM public.password_reset_requests WHERE status = 'code_issued'));
END $$;
SET ROLE service_role; SELECT t.login(NULL, 'service_role');
DO $$
DECLARE w jsonb; g jsonb; wrong text := CASE WHEN t.getv('code') = '000000' THEN '111111' ELSE '000000' END;
BEGIN
  w := public.check_student_password_reset_code('01100000001', wrong);
  PERFORM t.ok('F11 wrong code counted', w->>'reason' = 'wrong_code' AND (w->>'attempts_left')::int = 4, w::text);
  g := public.check_student_password_reset_code('01100000001', t.getv('code'));
  PERFORM t.ok('F12 right code accepted for the right student',
    (g->>'ok')::boolean AND g->>'student_id' = 'c0000000-0000-0000-0000-000000000001', g::text);
  PERFORM public.complete_student_password_reset((g->>'request_id')::uuid);
  PERFORM t.ok('F13 code is single-use', public.check_student_password_reset_code('01100000001', t.getv('code'))->>'reason' = 'no_code');
END $$;
-- lockout after 5 wrong codes
RESET ROLE; SELECT set_config('request.jwt.claims', '', false); SET ROLE anon; SELECT t.login(NULL, 'anon');
SELECT public.request_student_password_reset('01100000001');
RESET ROLE; SELECT set_config('request.jwt.claims', '', false); SET ROLE authenticated; SELECT t.login(:super);
SELECT t.setv('code', public.admin_issue_password_reset_code((SELECT id FROM public.admin_list_password_reset_requests() WHERE status = 'pending' LIMIT 1))->>'code');
RESET ROLE; SELECT set_config('request.jwt.claims', '', false); SET ROLE service_role; SELECT t.login(NULL, 'service_role');
DO $$
DECLARE i int; last jsonb; wrong text := CASE WHEN t.getv('code') = '000000' THEN '111111' ELSE '000000' END;
BEGIN
  FOR i IN 1..5 LOOP last := public.check_student_password_reset_code('01100000001', wrong); END LOOP;
  PERFORM t.ok('F14 five wrong codes lock the request', last->>'reason' = 'locked', last::text);
  PERFORM t.ok('F15 the right code no longer works after lockout',
    public.check_student_password_reset_code('01100000001', t.getv('code'))->>'ok' = 'false');
END $$;
RESET ROLE; SELECT set_config('request.jwt.claims', '', false);

-- =============================================================================
-- G. Cascade: deleting a supervisor's account clears its assignments
-- =============================================================================
DELETE FROM auth.users WHERE id = 'b0000000-0000-0000-0000-000000000003';
DELETE FROM auth.users WHERE id = 'c0000000-0000-0000-0000-000000000005';
DO $$ BEGIN
  PERFORM t.ok('G0 deleting a student archives paid (incl. expired) revenue only',
    EXISTS (SELECT 1 FROM public.deleted_student_revenue WHERE source_subscription_id = 'd0000000-0000-0000-0000-000000000099')
    AND NOT EXISTS (SELECT 1 FROM public.deleted_student_revenue WHERE source_subscription_id = 'd0000000-0000-0000-0000-000000000098'));
END $$;
DO $$ BEGIN
  PERFORM t.ok('G1 supervisor deletion removes assignments and the line contact',
    NOT EXISTS (SELECT 1 FROM public.supervisor_lines WHERE supervisor_id = 'b0000000-0000-0000-0000-000000000003')
    AND (SELECT supervisor_id FROM public.lines WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') IS NULL);
END $$;

-- =============================================================================
\o
\echo
SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, step, detail FROM t.results ORDER BY n;
DO $$ DECLARE f int; BEGIN
  SELECT count(*) INTO f FROM t.results WHERE NOT ok;
  IF f > 0 THEN RAISE EXCEPTION '% test step(s) failed', f; END IF;
  RAISE NOTICE 'all % steps passed', (SELECT count(*) FROM t.results);
END $$;
