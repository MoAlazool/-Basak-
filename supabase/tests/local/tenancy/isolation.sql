-- Tenant isolation test. Builds two complete companies (A and B) in ONE transaction
-- that is rolled back at the end, then acts as each kind of user through
-- request.jwt.claims. Run against a local stack only:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/local/tenancy/isolation.sql
\set QUIET on
\pset format unaligned
\pset tuples_only on
BEGIN;
SET LOCAL client_min_messages = warning;

CREATE TEMP TABLE t_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
GRANT ALL ON t_results, t_ids TO authenticated;
GRANT USAGE ON SEQUENCE t_results_n_seq TO authenticated;

-- ------------------------------------------------------------------- fixture
-- Every fixture line has one departure trip stopping at 07:10; test subscriptions take it.
CREATE FUNCTION pg_temp.iso_default_trip_time() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.departure_time := COALESCE(NEW.departure_time, '07:10');
  RETURN NEW;
END $$;
CREATE TRIGGER trg_a_iso_default_trip_time BEFORE INSERT ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION pg_temp.iso_default_trip_time();

DO $$
DECLARE
  k text; v uuid; co text; v_line uuid; v_station uuid; v_sup uuid; v_sub uuid; v_other uuid;
  v_today date := public.cairo_today();
BEGIN
  FOREACH k IN ARRAY ARRAY['super', 'admin_a', 'admin_b', 'sup_a', 'sup_b', 'a1', 'a2', 'b1', 'b2', 'shared', 'former', 'nobody'] LOOP
    v := gen_random_uuid();
    INSERT INTO t_ids VALUES (k, v);
    INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    VALUES (v, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iso_' || k || '@local.test', now(), now());
  END LOOP;

  INSERT INTO public.admins (id, email, full_name, role)
  SELECT id, 'iso_super@local.test', 'Iso Super', 'super_admin' FROM t_ids WHERE t_ids.k = 'super';
  INSERT INTO public.universities (name) VALUES ('جامعة العزل للاختبار') RETURNING id INTO v;
  INSERT INTO t_ids VALUES ('uni', v);

  FOREACH co IN ARRAY ARRAY['a', 'b'] LOOP
    INSERT INTO public.companies (name) VALUES ('Iso company ' || co) RETURNING id INTO v;
    INSERT INTO t_ids VALUES ('co_' || co, v);
    INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id)
    SELECT id, 'iso_admin_' || co || '@local.test', 'Iso Admin ' || co, 'company_admin', v,
           (SELECT id FROM t_ids WHERE t_ids.k = 'super')
    FROM t_ids WHERE t_ids.k = 'admin_' || co;
    INSERT INTO public.supervisors (id, phone, full_name, company_id)
    SELECT id, CASE co WHEN 'a' THEN '01099990001' ELSE '01099990002' END, 'Iso Supervisor ' || co, v
    FROM t_ids WHERE t_ids.k = 'sup_' || co RETURNING id INTO v_sup;
    INSERT INTO public.lines (company_id, name, price_termly, price_yearly, price_daily)
    VALUES (v, 'Iso line ' || co, 1000, 1800, 50) RETURNING id INTO v_line;
    INSERT INTO t_ids VALUES ('line_' || co, v_line);
    INSERT INTO public.stations (line_id, name, order_index, departure_times, return_times, departure_time, return_time)
    VALUES (v_line, 'Iso station ' || co, 1, ARRAY['07:00'::time], ARRAY['15:00'::time], '07:00', '15:00')
    RETURNING id INTO v_station;
    INSERT INTO t_ids VALUES ('station_' || co, v_station);
    INSERT INTO public.line_trips (line_id, direction, start_time) VALUES (v_line, 'departure', '07:00') RETURNING id INTO v;
    INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES (v, v_station, '07:10');
    INSERT INTO public.line_universities (line_id, university_id) SELECT v_line, id FROM t_ids WHERE t_ids.k = 'uni';
    INSERT INTO public.supervisor_lines (supervisor_id, line_id) VALUES (v_sup, v_line);
    INSERT INTO public.company_payment_methods (company_id, method_type, display_name, wallet_phone)
    VALUES ((SELECT id FROM t_ids WHERE t_ids.k = 'co_' || co), 'vodafone_cash', 'Iso cash ' || co, '01012345678');
  END LOOP;

  INSERT INTO public.students (id, phone, full_name, university, university_id)
  SELECT i.id, '0101111' || lpad(row_number() OVER ()::text, 4, '0'), 'Iso student ' || i.k,
         'جامعة العزل للاختبار', (SELECT id FROM t_ids WHERE t_ids.k = 'uni')
  FROM t_ids i WHERE i.k IN ('a1', 'a2', 'b1', 'b2', 'shared', 'former', 'nobody');

  FOREACH co IN ARRAY ARRAY['a', 'b'] LOOP
    SELECT id INTO v_line FROM t_ids WHERE t_ids.k = 'line_' || co;
    SELECT id INTO v_station FROM t_ids WHERE t_ids.k = 'station_' || co;
    SELECT id INTO v_sup FROM t_ids WHERE t_ids.k = 'sup_' || co;

    -- x1: a day pass valid today, with a ride vote, a scan, a complaint and a chat.
    SELECT id INTO v FROM t_ids WHERE t_ids.k = co || '1';
    INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price)
    VALUES (v, v_line, v_station, 'daily', 'active', v_today, v_today, 50) RETURNING id INTO v_sub;
    INSERT INTO t_ids VALUES ('sub_' || co || '1', v_sub);
    INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding) VALUES (v, v_today, true);
    INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, ride_date, direction, result)
    VALUES (v_sup, v, v_sub, v_line, v_today, 'departure', 'checked_in');
    INSERT INTO public.complaints (student_id, title, message) VALUES (v, 'Iso complaint ' || co, 'text');
    INSERT INTO public.chat_messages (student_id, supervisor_id, sender_role, message) VALUES (v, v_sup, 'student', 'hello');

    -- x2: a term subscription paid by an approved receipt.
    SELECT id INTO v FROM t_ids WHERE t_ids.k = co || '2';
    INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price)
    VALUES (v, v_line, v_station, 'termly', 'pending_payment', 1000) RETURNING id INTO v_sub;
    INSERT INTO t_ids VALUES ('sub_' || co || '2', v_sub);
    INSERT INTO public.receipts (subscription_id, image_url) VALUES (v_sub, v || '/' || v_sub || '_1.jpg');
    UPDATE public.receipts SET status = 'approved' WHERE subscription_id = v_sub;
  END LOOP;

  -- shared: rode with A yesterday (ended), rides with B today. An active member of both.
  SELECT id INTO v FROM t_ids WHERE t_ids.k = 'shared';
  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price)
  SELECT v, (SELECT id FROM t_ids WHERE t_ids.k = 'line_a'), (SELECT id FROM t_ids WHERE t_ids.k = 'station_a'),
         'daily', 'active', v_today - 1, v_today - 1, 50 RETURNING id INTO v_sub;
  INSERT INTO t_ids VALUES ('sub_shared_a', v_sub);
  INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding) VALUES (v, v_today - 1, true);
  UPDATE public.subscriptions SET status = 'expired' WHERE id = v_sub;
  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price)
  SELECT v, (SELECT id FROM t_ids WHERE t_ids.k = 'line_b'), (SELECT id FROM t_ids WHERE t_ids.k = 'station_b'),
         'daily', 'active', v_today, v_today, 50 RETURNING id INTO v_sub;
  INSERT INTO t_ids VALUES ('sub_shared_b', v_sub);
  INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding) VALUES (v, v_today, true);

  -- former: rode with A yesterday, was removed from A, rides with B today.
  SELECT id INTO v FROM t_ids WHERE t_ids.k = 'former';
  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price)
  SELECT v, (SELECT id FROM t_ids WHERE t_ids.k = 'line_a'), (SELECT id FROM t_ids WHERE t_ids.k = 'station_a'),
         'daily', 'active', v_today - 1, v_today - 1, 50 RETURNING id INTO v_sub;
  INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding) VALUES (v, v_today - 1, true);
  INSERT INTO public.complaints (student_id, title, message) VALUES (v, 'Iso former complaint', 'text');
  UPDATE public.subscriptions SET status = 'expired' WHERE id = v_sub;
  PERFORM public.company_remove_student((SELECT id FROM t_ids WHERE t_ids.k = 'co_a'), v);
  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price)
  SELECT v, (SELECT id FROM t_ids WHERE t_ids.k = 'line_b'), (SELECT id FROM t_ids WHERE t_ids.k = 'station_b'),
         'daily', 'active', v_today, v_today, 50;

  -- Password-reset requests waiting for an admin.
  INSERT INTO public.password_reset_requests (student_id)
  SELECT id FROM t_ids WHERE t_ids.k IN ('a1', 'b1', 'former');
END $$;

CREATE FUNCTION pg_temp.id(p text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM t_ids WHERE k = p $$;
CREATE FUNCTION pg_temp.act(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(p), 'role', 'authenticated')::text, true)
$$;
CREATE FUNCTION pg_temp.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO t_results (step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail)
$$;
-- Runs a statement that must be refused (an error) or touch nothing.
CREATE FUNCTION pg_temp.denied(p_step text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_rows bigint;
BEGIN
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM pg_temp.ok(p_step, v_rows = 0, v_rows || ' row(s)');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.ok(p_step, true, SQLSTATE);
  END;
END $$;

SET LOCAL ROLE authenticated;

-- ------------------------------------------------- every tenant table, both ways
DO $$
DECLARE
  r record; v_mine bigint; v_theirs bigint; me text; other text;
  v_tables text[] := ARRAY['lines', 'stations', 'line_trips', 'line_trip_stops', 'line_universities', 'supervisor_lines',
                           'supervisors', 'subscriptions', 'receipts', 'daily_ride_status', 'supervisor_scan_events',
                           'complaints', 'chat_messages', 'company_payment_methods', 'company_students', 'company_terms'];
  t text;
BEGIN
  FOR me, other IN VALUES ('a', 'b'), ('b', 'a') LOOP
    PERFORM pg_temp.act('admin_' || me);
    FOREACH t IN ARRAY v_tables LOOP
      EXECUTE format('SELECT count(*) FILTER (WHERE company_id = $1), count(*) FILTER (WHERE company_id IS DISTINCT FROM $1) FROM public.%I', t)
        INTO v_mine, v_theirs USING pg_temp.id('co_' || me);
      PERFORM pg_temp.ok(format('admin %s reads its own %s', me, t), v_mine > 0, v_mine::text);
      PERFORM pg_temp.ok(format('admin %s reads no other company''s %s', me, t), v_theirs = 0, v_theirs::text);
      PERFORM pg_temp.denied(format('admin %s cannot update company %s''s %s', me, other, t),
        format('UPDATE public.%I SET company_id = company_id WHERE company_id = %L', t, pg_temp.id('co_' || other)));
      PERFORM pg_temp.denied(format('admin %s cannot delete company %s''s %s', me, other, t),
        format('DELETE FROM public.%I WHERE company_id = %L', t, pg_temp.id('co_' || other)));
    END LOOP;
    PERFORM pg_temp.ok(format('admin %s sees only its own company', me),
      (SELECT count(*) = 1 AND bool_and(id = pg_temp.id('co_' || me)) FROM public.companies));
    PERFORM pg_temp.ok(format('admin %s sees only its own admins', me),
      (SELECT bool_and(company_id = pg_temp.id('co_' || me)) FROM public.admins));
  END LOOP;

  PERFORM pg_temp.act('super');
  FOREACH t IN ARRAY v_tables LOOP
    EXECUTE format('SELECT count(DISTINCT company_id) FROM public.%I WHERE company_id IN ($1, $2)', t)
      INTO v_mine USING pg_temp.id('co_a'), pg_temp.id('co_b');
    PERFORM pg_temp.ok(format('platform admin reads both companies'' %s', t), v_mine = 2, v_mine::text);
  END LOOP;
END $$;

-- Every table that carries company_id is protected, and by the shared rule.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname, c.relrowsecurity,
           (SELECT count(*) FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policies,
           (SELECT count(*) FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname
              AND (COALESCE(p.qual, '') || COALESCE(p.with_check, '')) ~ '(can_manage_company|has_company_access|managed_company_id|staff_company_id)\(') AS shared
    FROM pg_class c JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'company_id' AND NOT a.attisdropped
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
      AND c.relname <> 'password_admin_resets'  -- platform-only audit log; the company is a note
  LOOP
    PERFORM pg_temp.ok(format('%s: row-level security is on', r.relname), r.relrowsecurity);
    PERFORM pg_temp.ok(format('%s: uses the shared company rule (or has no client access)', r.relname),
      r.policies = 0 OR r.shared > 0, r.policies || ' policies');
  END LOOP;
END $$;

-- ------------------------------------------------------------ writes across
DO $$
BEGIN
  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.denied('admin A cannot create a line for company B', format(
    'INSERT INTO public.lines (company_id, name, price_termly, price_yearly, price_daily) VALUES (%L, ''x'', 1, 1, 1)', pg_temp.id('co_b')));
  PERFORM pg_temp.denied('admin A cannot add a station to B''s line', format(
    'INSERT INTO public.stations (line_id, name, order_index) VALUES (%L, ''x'', 9)', pg_temp.id('line_b')));
  PERFORM pg_temp.denied('admin A cannot add a station to B''s line by naming its own company', format(
    'INSERT INTO public.stations (line_id, company_id, name, order_index) VALUES (%L, %L, ''x'', 9)', pg_temp.id('line_b'), pg_temp.id('co_a')));
  PERFORM pg_temp.denied('admin A cannot add a payment method for B', format(
    'INSERT INTO public.company_payment_methods (company_id, method_type, display_name, wallet_phone) VALUES (%L, ''vodafone_cash'', ''x'', ''01012345678'')', pg_temp.id('co_b')));
  PERFORM pg_temp.denied('admin A cannot subscribe a student on B''s line', format(
    'INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price) VALUES (%L, %L, %L, ''daily'', ''active'', current_date + 30, current_date + 30, 1)',
    pg_temp.id('a1'), pg_temp.id('line_b'), pg_temp.id('station_b')));
  PERFORM pg_temp.denied('admin A cannot attach a subscription to a student who is not its member', format(
    'INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price) VALUES (%L, %L, %L, ''daily'', ''active'', current_date + 30, current_date + 30, 1)',
    pg_temp.id('b1'), pg_temp.id('line_a'), pg_temp.id('station_a')));
  PERFORM pg_temp.denied('admin A cannot attach a subscription to a student it removed', format(
    'INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, start_date, end_date, price) VALUES (%L, %L, %L, ''daily'', ''active'', current_date + 30, current_date + 30, 1)',
    pg_temp.id('former'), pg_temp.id('line_a'), pg_temp.id('station_a')));
  PERFORM pg_temp.denied('admin A cannot move its line to company B', format(
    'UPDATE public.lines SET company_id = %L WHERE id = %L', pg_temp.id('co_b'), pg_temp.id('line_a')));
  PERFORM pg_temp.denied('admin A cannot write memberships directly', format(
    'INSERT INTO public.company_students (company_id, student_id) VALUES (%L, %L)', pg_temp.id('co_a'), pg_temp.id('b1')));
  PERFORM pg_temp.denied('admin A cannot remove a student from company B', format(
    'SELECT public.company_remove_student(%L, %L)', pg_temp.id('co_b'), pg_temp.id('b1')));
END $$;

-- -------------------------------------------------------- students (membership)
DO $$
DECLARE v_rows bigint;
BEGIN
  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.ok('admin A sees its members and only them',
    (SELECT array_agg(id ORDER BY id) FROM public.students)
      = (SELECT array_agg(i.id ORDER BY i.id) FROM t_ids i WHERE i.k IN ('a1', 'a2', 'shared')),
    (SELECT count(*)::text FROM public.students));
  PERFORM pg_temp.ok('admin A no longer sees the student it removed',
    NOT EXISTS (SELECT 1 FROM public.students WHERE id = pg_temp.id('former')));
  PERFORM pg_temp.ok('admin A sees only its own subscription of the shared student',
    (SELECT array_agg(id) FROM public.subscriptions WHERE student_id = pg_temp.id('shared')) = ARRAY[pg_temp.id('sub_shared_a')]);
  PERFORM pg_temp.ok('admin A sees only its own ride of the shared student',
    (SELECT count(*) = 1 AND bool_and(company_id = pg_temp.id('co_a')) FROM public.daily_ride_status WHERE student_id = pg_temp.id('shared')));
  PERFORM pg_temp.denied('admin A cannot delete the shared student',
    format('DELETE FROM public.students WHERE id = %L', pg_temp.id('shared')));
  PERFORM pg_temp.denied('admin A cannot delete its own member''s account either',
    format('DELETE FROM public.students WHERE id = %L', pg_temp.id('a1')));
  PERFORM pg_temp.denied('admin A cannot rewrite a member''s profile',
    format('UPDATE public.students SET full_name = ''x'' WHERE id = %L', pg_temp.id('a1')));

  -- Removing a member ends what is open with this company only.
  PERFORM public.company_remove_student(pg_temp.id('co_a'), pg_temp.id('shared'));
  PERFORM pg_temp.ok('after removal, admin A cannot see the student',
    NOT EXISTS (SELECT 1 FROM public.students WHERE id = pg_temp.id('shared')));
  PERFORM pg_temp.act('admin_b');
  PERFORM pg_temp.ok('the removed student is untouched in company B',
    (SELECT status = 'active' FROM public.subscriptions WHERE id = pg_temp.id('sub_shared_b'))
    AND EXISTS (SELECT 1 FROM public.students WHERE id = pg_temp.id('shared')));
END $$;

-- ------------------------------------------------------------ password resets
DO $$
DECLARE v_req uuid;
BEGIN
  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.ok('admin A lists reset requests of its members only',
    (SELECT array_agg(student_id) FROM public.admin_list_password_reset_requests()) = ARRAY[pg_temp.id('a1')]);
  PERFORM pg_temp.denied('admin A cannot issue a reset code for B''s student', format(
    'SELECT public.admin_issue_password_reset_code((SELECT id FROM (SELECT set_config(''role'', ''postgres'', true)) x, public.password_reset_requests WHERE student_id = %L))', pg_temp.id('b1')));
END $$;
RESET ROLE;
CREATE TEMP TABLE t_reqs ON COMMIT DROP AS
  SELECT i.k, r.id FROM public.password_reset_requests r JOIN t_ids i ON i.id = r.student_id;
GRANT SELECT ON t_reqs TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.denied('admin A cannot issue a reset code for B''s student',
    format('SELECT public.admin_issue_password_reset_code(%L)', (SELECT id FROM t_reqs WHERE k = 'b1')));
  PERFORM pg_temp.denied('admin A cannot issue a reset code for a student it removed',
    format('SELECT public.admin_issue_password_reset_code(%L)', (SELECT id FROM t_reqs WHERE k = 'former')));
  PERFORM pg_temp.ok('admin A can issue a reset code for its own member',
    (public.admin_issue_password_reset_code((SELECT id FROM t_reqs WHERE k = 'a1'))->>'code') ~ '^[0-9]{6}$');
  PERFORM pg_temp.act('admin_b');
  PERFORM pg_temp.ok('admin B can issue a reset code for the student who moved to it',
    (public.admin_issue_password_reset_code((SELECT id FROM t_reqs WHERE k = 'former'))->>'code') ~ '^[0-9]{6}$');
END $$;

-- ---------------------------------------------------------------- supervisors
DO $$
BEGIN
  PERFORM pg_temp.act('sup_a');
  PERFORM pg_temp.ok('supervisor A reads its company''s lines and no others',
    (SELECT count(*) > 0 AND bool_and(company_id = pg_temp.id('co_a')) FROM public.lines));
  PERFORM pg_temp.ok('supervisor A reads no other company''s stations',
    (SELECT COALESCE(bool_and(company_id = pg_temp.id('co_a')), true) FROM public.stations));
  PERFORM pg_temp.ok('supervisor A reads no other company''s students',
    NOT EXISTS (SELECT 1 FROM public.students WHERE id IN (pg_temp.id('b1'), pg_temp.id('b2'))));
  PERFORM pg_temp.ok('supervisor A scanning B''s student learns nothing',
    (public.supervisor_check_in_student((SELECT qr_code_value FROM public.students WHERE id = pg_temp.id('a1')))->>'result')
      IN ('checked_in', 'already_checked_in'));
END $$;
RESET ROLE;
CREATE TEMP TABLE t_qr ON COMMIT DROP AS SELECT i.k, s.qr_code_value FROM public.students s JOIN t_ids i ON i.id = s.id;
GRANT SELECT ON t_qr TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.act('sup_a');
  v := public.supervisor_check_in_student((SELECT qr_code_value FROM t_qr WHERE k = 'b1'));
  PERFORM pg_temp.ok('supervisor A scanning B''s student is told only that they are outside its lines',
    v->>'result' = 'outside_assigned_lines' AND v->'student' IS NULL, v->>'result');
  PERFORM pg_temp.ok('the refused scan is recorded under the supervisor''s own company',
    (SELECT bool_and(company_id = pg_temp.id('co_a')) FROM public.supervisor_scan_events WHERE supervisor_id = pg_temp.id('sup_a')));
END $$;

-- ------------------------------------------------------------------- students
DO $$
BEGIN
  PERFORM pg_temp.act('a1');
  PERFORM pg_temp.ok('a student reads only their own student row',
    (SELECT count(*) = 1 AND bool_and(id = pg_temp.id('a1')) FROM public.students));
  PERFORM pg_temp.ok('a student reads only their own subscriptions, rides and complaints',
    (SELECT COALESCE(bool_and(student_id = pg_temp.id('a1')), true) FROM public.subscriptions)
    AND (SELECT COALESCE(bool_and(student_id = pg_temp.id('a1')), true) FROM public.daily_ride_status)
    AND (SELECT COALESCE(bool_and(student_id = pg_temp.id('a1')), true) FROM public.complaints));
  PERFORM pg_temp.ok('a student reads only their own memberships',
    (SELECT count(*) = 1 AND bool_and(student_id = pg_temp.id('a1')) FROM public.company_students));
  PERFORM pg_temp.ok('a student still browses active lines of every active company',
    (SELECT count(DISTINCT company_id) >= 2 FROM public.lines WHERE id IN (pg_temp.id('line_a'), pg_temp.id('line_b'))));
  PERFORM pg_temp.denied('a student cannot write a membership',
    format('INSERT INTO public.company_students (company_id, student_id) VALUES (%L, %L)', pg_temp.id('co_b'), pg_temp.id('a1')));

  -- Subscribing is what makes a student a member.
  PERFORM pg_temp.act('nobody');
  INSERT INTO public.complaints (student_id, title, message) VALUES (pg_temp.id('nobody'), 'Iso platform complaint', 'text');
  PERFORM pg_temp.ok('a complaint from a student with no company goes to the platform',
    (SELECT company_id IS NULL FROM public.complaints WHERE student_id = pg_temp.id('nobody')));
  INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price)
  VALUES (pg_temp.id('nobody'), pg_temp.id('line_b'), pg_temp.id('station_b'), 'daily', 0);
  PERFORM pg_temp.ok('subscribing makes the student a member of that company',
    (SELECT array_agg(company_id) FROM public.company_students WHERE student_id = pg_temp.id('nobody')) = ARRAY[pg_temp.id('co_b')]);
  INSERT INTO public.complaints (student_id, company_id, title, message)
  VALUES (pg_temp.id('nobody'), pg_temp.id('co_a'), 'Iso forged complaint', 'text');
  PERFORM pg_temp.ok('a complaint cannot be addressed to a company the student does not ride with',
    (SELECT company_id = pg_temp.id('co_b') FROM public.complaints WHERE title = 'Iso forged complaint'));

  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.ok('admin A sees neither the platform complaint nor B''s',
    NOT EXISTS (SELECT 1 FROM public.complaints WHERE title IN ('Iso platform complaint', 'Iso forged complaint', 'Iso complaint b')));
END $$;

-- ---------------------------------------------------- terms, resets, overview
DO $$
DECLARE v_before_a date; v_before_b date; v_b_periods jsonb; v jsonb; v_rev_b numeric;
BEGIN
  PERFORM pg_temp.act('super');
  SELECT start_date INTO v_before_b FROM public.subscriptions WHERE id = pg_temp.id('sub_b2');
  SELECT jsonb_agg(to_jsonb(p)) INTO v_b_periods FROM public.get_purchasable_periods(pg_temp.id('line_b')) p;
  v_rev_b := (public.company_overview(pg_temp.id('co_b'))->>'revenue')::numeric;
  v := public.platform_overview();
  PERFORM pg_temp.ok('platform overview has one row per company and adds them up',
    jsonb_array_length(v->'per_company') = (SELECT count(*) FROM public.companies)
    AND (v->>'revenue')::numeric = (SELECT sum((r->>'revenue')::numeric) FROM jsonb_array_elements(v->'per_company') r),
    v->>'revenue');

  PERFORM pg_temp.act('admin_a');
  SELECT start_date INTO v_before_a FROM public.subscriptions WHERE id = pg_temp.id('sub_a2');
  v := public.company_overview(pg_temp.id('co_a'));
  PERFORM pg_temp.ok('company A overview counts A only',
    (v->>'members')::int = 2 AND (v->>'revenue')::numeric = 1150 AND (v->>'lines')::int = 1, v::text);
  PERFORM pg_temp.denied('admin A cannot read company B''s overview',
    format('SELECT public.company_overview(%L)', pg_temp.id('co_b')));
  PERFORM pg_temp.denied('admin A cannot read the platform overview', 'SELECT public.platform_overview()');
  PERFORM pg_temp.denied('admin A cannot change company B''s terms',
    format('SELECT public.save_company_terms(%L, ''[]'')', pg_temp.id('co_b')));
  PERFORM pg_temp.denied('admin A cannot save overlapping terms', format(
    'SELECT public.save_company_terms(%L, ''[{"code":"second","start_month":9,"start_day":6,"start_year_offset":0}]'')', pg_temp.id('co_a')));

  -- Company A moves its running term one day earlier.
  PERFORM public.save_company_terms(pg_temp.id('co_a'), (
    SELECT jsonb_agg(jsonb_build_object('code', code, 'start_month', extract(month FROM d)::int, 'start_day', extract(day FROM d)::int))
    FROM (SELECT t.code, v_before_a - 1 AS d FROM public.company_terms t
          WHERE t.company_id = pg_temp.id('co_a')
            AND t.code = (SELECT period_code FROM public.subscriptions WHERE id = pg_temp.id('sub_a2'))) x));
  PERFORM pg_temp.ok('changing A''s terms moves A''s subscription',
    (SELECT start_date = v_before_a - 1 FROM public.subscriptions WHERE id = pg_temp.id('sub_a2')));
  PERFORM public.admin_reset_reports('financial', 'RESET FINANCIAL DATA', 'iso');
  PERFORM pg_temp.ok('resetting A''s reports clears A''s revenue',
    (public.company_overview(pg_temp.id('co_a'))->>'revenue')::numeric = 0);
  PERFORM pg_temp.ok('admin A sees only its own resets',
    (SELECT count(*) = 1 AND bool_and(company_id = pg_temp.id('co_a')) FROM public.report_resets WHERE note = 'iso'));

  PERFORM pg_temp.act('super');
  PERFORM pg_temp.ok('A''s term change left B''s subscription alone',
    (SELECT start_date = v_before_b FROM public.subscriptions WHERE id = pg_temp.id('sub_b2')));
  PERFORM pg_temp.ok('A''s term change left what B sells alone',
    (SELECT jsonb_agg(to_jsonb(p)) FROM public.get_purchasable_periods(pg_temp.id('line_b')) p) = v_b_periods);
  PERFORM pg_temp.ok('A''s reset left B''s revenue alone',
    (public.company_overview(pg_temp.id('co_b'))->>'revenue')::numeric = v_rev_b AND v_rev_b > 0, v_rev_b::text);
  PERFORM pg_temp.denied('the platform admin must name a company to reset',
    'SELECT public.admin_reset_reports(''financial'', ''RESET FINANCIAL DATA'', ''iso'')');
END $$;

-- ---------------------------------------------------------- suspended company
DO $$
BEGIN
  PERFORM pg_temp.act('super');
  UPDATE public.companies SET status = 'suspended' WHERE id = pg_temp.id('co_a');
  PERFORM pg_temp.ok('suspending keeps is_active in step',
    (SELECT NOT is_active FROM public.companies WHERE id = pg_temp.id('co_a')));

  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.ok('a suspended company''s admin is no longer an admin', NOT public.is_admin());
  PERFORM pg_temp.ok('a suspended company''s admin reads none of its data',
    NOT EXISTS (SELECT 1 FROM public.lines) AND NOT EXISTS (SELECT 1 FROM public.students)
    AND NOT EXISTS (SELECT 1 FROM public.subscriptions) AND NOT EXISTS (SELECT 1 FROM public.receipts));
  PERFORM pg_temp.ok('a suspended company''s admin still sees that the company is suspended',
    (SELECT status = 'suspended' FROM public.companies WHERE id = pg_temp.id('co_a')));
  PERFORM pg_temp.denied('a suspended company''s admin cannot read its overview',
    format('SELECT public.company_overview(%L)', pg_temp.id('co_a')));

  PERFORM pg_temp.act('sup_a');
  PERFORM pg_temp.ok('a suspended company''s supervisor is locked out',
    NOT public.is_supervisor() AND NOT EXISTS (SELECT 1 FROM public.lines) AND NOT EXISTS (SELECT 1 FROM public.students));

  PERFORM pg_temp.act('b1');
  PERFORM pg_temp.ok('students no longer see a suspended company or its lines',
    NOT EXISTS (SELECT 1 FROM public.companies WHERE id = pg_temp.id('co_a'))
    AND NOT EXISTS (SELECT 1 FROM public.lines WHERE company_id = pg_temp.id('co_a')));
  PERFORM pg_temp.denied('students cannot subscribe with a suspended company', format(
    'INSERT INTO public.subscriptions (student_id, line_id, station_id, type, price) VALUES (%L, %L, %L, ''daily'', 0)',
    pg_temp.id('nobody'), pg_temp.id('line_a'), pg_temp.id('station_a')));

  PERFORM pg_temp.act('super');
  UPDATE public.companies SET is_active = true WHERE id = pg_temp.id('co_a');
  PERFORM pg_temp.act('admin_a');
  PERFORM pg_temp.ok('reactivating restores the admin', public.is_admin() AND EXISTS (SELECT 1 FROM public.lines));
END $$;

-- The company of a row always follows its parent.
RESET ROLE;
DO $$
BEGIN
  UPDATE public.stations SET company_id = pg_temp.id('co_b') WHERE id = pg_temp.id('station_a');
  PERFORM pg_temp.ok('a station cannot be given another company than its line''s',
    (SELECT company_id = pg_temp.id('co_a') FROM public.stations WHERE id = pg_temp.id('station_a')));
  PERFORM pg_temp.denied('a line cannot be moved to another company, even by the database owner',
    format('UPDATE public.lines SET company_id = %L WHERE id = %L', pg_temp.id('co_b'), pg_temp.id('line_a')));
  PERFORM pg_temp.denied('a supervisor cannot be moved to another company',
    format('UPDATE public.supervisors SET company_id = %L WHERE id = %L', pg_temp.id('co_b'), pg_temp.id('sup_a')));
  -- One relationship per pair of tables, or the API cannot resolve nested queries.
  PERFORM pg_temp.ok('no pair of tables is linked by two foreign keys on the same column',
    NOT EXISTS (
      SELECT 1 FROM pg_constraint c
      WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND array_length(c.conkey, 1) > 1
        AND EXISTS (SELECT 1 FROM pg_constraint d
                    WHERE d.contype = 'f' AND d.conrelid = c.conrelid AND d.confrelid = c.confrelid AND d.oid <> c.oid
                      AND d.conkey <@ c.conkey)));
  PERFORM pg_temp.denied('two companies cannot share a name',
    'INSERT INTO public.companies (name) VALUES (''  ISO COMPANY A '')');
  PERFORM pg_temp.ok('a new company starts with its own copy of the terms',
    (SELECT count(*) = (SELECT count(*) FROM public.academic_terms) FROM public.company_terms WHERE company_id = pg_temp.id('co_b')));
END $$;

SELECT CASE WHEN ok THEN 'ok   ' ELSE 'FAIL ' END || step || COALESCE('  [' || detail || ']', '')
FROM t_results WHERE NOT ok ORDER BY n;
SELECT 'isolation: ' || count(*) FILTER (WHERE ok) || '/' || count(*) || ' passed' FROM t_results;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM t_results WHERE NOT ok) THEN RAISE EXCEPTION 'isolation test failed'; END IF;
END $$;
ROLLBACK;
