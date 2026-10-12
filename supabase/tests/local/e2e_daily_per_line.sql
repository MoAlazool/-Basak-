-- Test of 20261125000003_daily_per_line: daily is sold on a line only while its
-- company sells daily and the line has a daily price.
-- Plain SQL, one transaction, rolled back. Fails (RAISE) unless every check
-- says ok = true.
--
-- Fixture (triggers off while it is written): company D selling daily, line LD
-- (daily 40) and line LZ (daily 0, switched off in the wizard), each with one
-- departure trip to the student's university. Student s1, a member of D.
BEGIN;

CREATE SCHEMA dl;
GRANT USAGE ON SCHEMA dl TO authenticated, anon;
CREATE TABLE dl.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE FUNCTION dl.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO dl.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION dl.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE || ' ' || SQLERRM; END $$;
CREATE FUNCTION dl.login(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true) $$;
-- The line's daily as the student's catalog shows it.
CREATE FUNCTION dl.daily(p_line uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT l->'daily' FROM jsonb_array_elements(public.get_subscription_catalog()->'companies') c,
                         jsonb_array_elements(c->'lines') l
  WHERE l->>'id' = p_line::text $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA dl TO authenticated, anon;
GRANT INSERT, SELECT ON dl.results TO authenticated;
GRANT USAGE ON SEQUENCE dl.results_n_seq TO authenticated;

SET LOCAL session_replication_role = replica;

INSERT INTO public.app_settings (id, daily_subscription_enabled) VALUES (true, true)
ON CONFLICT (id) DO UPDATE SET daily_subscription_enabled = true;

INSERT INTO auth.users (id, email)
SELECT ('7d000000-0000-4000-8000-0000000000' || x)::uuid, 'dl-' || x || '@example.invalid'
FROM unnest(ARRAY['a5', '51']) x;

INSERT INTO public.companies (id, name, status, is_active, daily_subscription_enabled) VALUES
  ('7d000000-0000-4000-8000-00000000c00d', 'اختبار اليومي', 'active', true, true);
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  ('7d000000-0000-4000-8000-0000000000a5', 'dl-a5@example.invalid', 'مدير المنصة', 'super_admin', NULL, NULL);
INSERT INTO public.universities (id, name, city, is_active) VALUES
  ('7d000000-0000-4000-8000-0000000000f1', 'جامعة اختبار اليومي', 'دمياط', true);
INSERT INTO public.lines (id, company_id, name, origin_name, destination_university_id, price_termly, price_yearly, price_daily, is_active) VALUES
  ('7d000000-0000-4000-8000-00000000a0d1', '7d000000-0000-4000-8000-00000000c00d', 'خط اليومي', 'أ', '7d000000-0000-4000-8000-0000000000f1', 3000, 6000, 40, true),
  ('7d000000-0000-4000-8000-00000000a0d2', '7d000000-0000-4000-8000-00000000c00d', 'خط بلا يومي', 'ب', '7d000000-0000-4000-8000-0000000000f1', 3000, 6000, 0, true);
INSERT INTO public.stations (id, line_id, name, order_index, company_id, is_active) VALUES
  ('7d000000-0000-4000-8000-00000000b0d1', '7d000000-0000-4000-8000-00000000a0d1', 'محطة أ', 0, '7d000000-0000-4000-8000-00000000c00d', true),
  ('7d000000-0000-4000-8000-00000000b0d2', '7d000000-0000-4000-8000-00000000a0d2', 'محطة ب', 0, '7d000000-0000-4000-8000-00000000c00d', true);
INSERT INTO public.line_trips (id, line_id, company_id, direction, label, start_time, university_id, is_active) VALUES
  ('7d000000-0000-4000-8000-00000000d0d1', '7d000000-0000-4000-8000-00000000a0d1', '7d000000-0000-4000-8000-00000000c00d', 'departure', 'أ', '07:00', '7d000000-0000-4000-8000-0000000000f1', true),
  ('7d000000-0000-4000-8000-00000000d0d2', '7d000000-0000-4000-8000-00000000a0d2', '7d000000-0000-4000-8000-00000000c00d', 'departure', 'ب', '07:00', '7d000000-0000-4000-8000-0000000000f1', true);
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time, company_id) VALUES
  ('7d000000-0000-4000-8000-00000000d0d1', '7d000000-0000-4000-8000-00000000b0d1', '07:00', '7d000000-0000-4000-8000-00000000c00d'),
  ('7d000000-0000-4000-8000-00000000d0d2', '7d000000-0000-4000-8000-00000000b0d2', '07:00', '7d000000-0000-4000-8000-00000000c00d');
INSERT INTO public.students (id, phone, full_name, university, college, university_id) VALUES
  ('7d000000-0000-4000-8000-000000000051', '01099970051', 'طالب اليومي', 'جامعة اختبار اليومي', 'الهندسة', '7d000000-0000-4000-8000-0000000000f1');
INSERT INTO public.company_students (company_id, student_id, status) VALUES
  ('7d000000-0000-4000-8000-00000000c00d', '7d000000-0000-4000-8000-000000000051', 'active');

SET LOCAL session_replication_role = origin;

-- 1. The catalog: a line without a daily price offers no daily.
SET LOCAL ROLE authenticated;
SELECT dl.login('7d000000-0000-4000-8000-000000000051');
SELECT dl.ok('1a priced line offers daily', dl.daily('7d000000-0000-4000-8000-00000000a0d1') = '{"enabled": true, "price": 40}'::jsonb,
             dl.daily('7d000000-0000-4000-8000-00000000a0d1')::text);
SELECT dl.ok('1b line with daily 0 does not', dl.daily('7d000000-0000-4000-8000-00000000a0d2') = '{"enabled": false, "price": 0}'::jsonb,
             dl.daily('7d000000-0000-4000-8000-00000000a0d2')::text);

-- 2. The student cannot take daily on that line, even asking directly.
SELECT dl.ok('2 daily on a line with no daily price is refused',
  dl.err($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, departure_trip_id)
           VALUES (auth.uid(), '7d000000-0000-4000-8000-00000000a0d2', '7d000000-0000-4000-8000-00000000b0d2', 'daily', 'active', 0,
                   '7d000000-0000-4000-8000-00000000d0d2')$q$) LIKE '23514%اليومي غير متاح%');

-- 3. On the priced line it works as before, at the line's price. (The insert runs
--    in its own statement so the check below sees its row.)
CREATE TEMP TABLE dl_e3 AS SELECT dl.err($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, departure_trip_id)
           VALUES (auth.uid(), '7d000000-0000-4000-8000-00000000a0d1', '7d000000-0000-4000-8000-00000000b0d1', 'daily', 'pending_payment', 1,
                   '7d000000-0000-4000-8000-00000000d0d1')$q$) AS e;
SELECT dl.ok('3 daily on the priced line: active, the line''s price', (SELECT e IS NULL FROM dl_e3)
  AND (SELECT s.price = 40 AND s.status = 'active' FROM public.subscriptions s
       WHERE s.student_id = auth.uid() AND s.line_id = '7d000000-0000-4000-8000-00000000a0d1' AND s.type = 'daily'),
  (SELECT e FROM dl_e3));
RESET ROLE;

-- 4. The company stops selling daily: no line offers it, and a request is refused.
UPDATE public.companies SET daily_subscription_enabled = false WHERE id = '7d000000-0000-4000-8000-00000000c00d';
DELETE FROM public.subscriptions WHERE student_id = '7d000000-0000-4000-8000-000000000051';
SET LOCAL ROLE authenticated;
SELECT dl.login('7d000000-0000-4000-8000-000000000051');
SELECT dl.ok('4a company not selling daily: the priced line offers none', (dl.daily('7d000000-0000-4000-8000-00000000a0d1')->>'enabled')::boolean = false);
SELECT dl.ok('4b and a direct request is refused',
  dl.err($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, departure_trip_id)
           VALUES (auth.uid(), '7d000000-0000-4000-8000-00000000a0d1', '7d000000-0000-4000-8000-00000000b0d1', 'daily', 'active', 40,
                   '7d000000-0000-4000-8000-00000000d0d1')$q$) LIKE '23514%');
RESET ROLE;

-- 5. The administration is unchanged: it may still register a daily ride on any line.
UPDATE public.companies SET daily_subscription_enabled = true WHERE id = '7d000000-0000-4000-8000-00000000c00d';
SET LOCAL ROLE authenticated;
SELECT dl.login('7d000000-0000-4000-8000-0000000000a5');
SELECT dl.ok('5 an admin may register daily on a line with no daily price',
  dl.err($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, type, status, price, departure_trip_id)
           VALUES ('7d000000-0000-4000-8000-000000000051', '7d000000-0000-4000-8000-00000000a0d2', '7d000000-0000-4000-8000-00000000b0d2',
                   'daily', 'active', 0, '7d000000-0000-4000-8000-00000000d0d2')$q$) IS NULL);
RESET ROLE;

SELECT n, step, ok, detail FROM dl.results ORDER BY n;
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(step || COALESCE(' — ' || detail, ''), E'\n') INTO bad FROM dl.results WHERE NOT ok;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'e2e_daily_per_line failed:%', E'\n' || bad; END IF;
  IF (SELECT count(*) FROM dl.results) <> 7 THEN RAISE EXCEPTION 'e2e_daily_per_line: expected 7 checks'; END IF;
END $$;

ROLLBACK;
