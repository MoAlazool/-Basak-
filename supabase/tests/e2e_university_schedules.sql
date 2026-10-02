-- End-to-end test for per-university line schedules. Impersonates real accounts
-- inside ONE transaction that is aborted at the end (deliberate exception), so
-- nothing is persisted. Run with:
--   npx.cmd supabase@latest db query --project-ref <ref> --linked -f supabase/tests/e2e_university_schedules.sql
BEGIN;

CREATE TEMP TABLE e2e_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON e2e_results TO authenticated;
GRANT USAGE ON SEQUENCE e2e_results_n_seq TO authenticated;

-- Fixture: S = a subscribed student on company line L; U1 = S's university;
-- U2 = another university; T = a student of neither (or of a third university).
CREATE TEMP TABLE e2e_ctx ON COMMIT DROP AS
WITH cadmin AS (
  SELECT id, company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1
), s AS (
  SELECT sub.student_id, sub.line_id, st.university_id
  FROM public.subscriptions sub
  JOIN public.lines l ON l.id = sub.line_id
  JOIN public.students st ON st.id = sub.student_id
  JOIN auth.users u ON u.id = sub.student_id
  WHERE l.company_id = (SELECT company_id FROM cadmin) AND sub.status = 'active' AND st.university_id IS NOT NULL
  LIMIT 1
)
SELECT
  (SELECT id FROM cadmin) AS cadmin_id,
  (SELECT company_id FROM cadmin) AS company_id,
  (SELECT id FROM public.supervisors WHERE company_id = (SELECT company_id FROM cadmin) LIMIT 1) AS supervisor_id,
  s.student_id AS s_id, s.line_id AS line_id, s.university_id AS u1,
  (SELECT id FROM public.universities WHERE id <> s.university_id ORDER BY name LIMIT 1) AS u2,
  -- Impersonation only needs the profile row (auth.uid() comes from the JWT claims).
  (SELECT st.id FROM public.students st
     WHERE st.university_id IS NOT NULL AND st.university_id <> s.university_id ORDER BY st.created_at LIMIT 1) AS t_id,
  (SELECT id FROM public.lines WHERE company_id <> (SELECT company_id FROM cadmin) LIMIT 1) AS foreign_line_id,
  (SELECT id FROM public.stations WHERE line_id = s.line_id AND is_active ORDER BY order_index LIMIT 1) AS station_id
FROM s;
-- U2 must not be T's university so T stays "not served" by line L.
UPDATE e2e_ctx SET u2 = (
  SELECT u.id FROM public.universities u
  WHERE u.id <> e2e_ctx.u1
    AND u.id IS DISTINCT FROM (SELECT university_id FROM public.students WHERE id = e2e_ctx.t_id)
  ORDER BY u.name LIMIT 1);
ALTER TABLE e2e_ctx ADD COLUMN t_uni uuid;
UPDATE e2e_ctx SET t_uni = (SELECT university_id FROM public.students WHERE id = e2e_ctx.t_id);
GRANT SELECT ON e2e_ctx TO authenticated;
-- T needs a free slot to attempt a new subscription.
DELETE FROM public.subscriptions WHERE student_id = (SELECT t_id FROM e2e_ctx);

-- ------------------------------------------------------------- COMPANY ADMIN
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_ok boolean; v_dep time;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO public.line_university_schedules(line_id, university_id, departure_time, return_time)
    VALUES (c.line_id, c.u1, '07:10', '14:00'), (c.line_id, c.u2, '07:35', '15:00');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: adds 2 university schedules to one line', true, NULL);

  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: line is still a single row (not duplicated)',
    count(*) = 1, count(*)::text FROM public.lines WHERE id = c.line_id;

  BEGIN
    INSERT INTO public.line_university_schedules(line_id, university_id, departure_time, return_time)
      VALUES (c.line_id, c.u1, '09:00', '16:00');
    v_ok := false;
  EXCEPTION WHEN unique_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: same university twice on a line is rejected', v_ok, NULL);

  BEGIN
    INSERT INTO public.line_university_schedules(line_id, university_id, departure_time, return_time)
      VALUES (c.foreign_line_id, c.u1, '07:00', '14:00');
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: cannot add schedules to another company line', v_ok, NULL);

  SELECT departure_time INTO v_dep FROM public.subscriptions WHERE student_id = c.s_id AND status = 'active';
  INSERT INTO e2e_results(step, ok, detail) SELECT 'existing subscriber adopted into own university trip',
    sub.schedule_id IS NOT NULL AND sub.departure_time = '07:10', sub.departure_time::text
    FROM public.subscriptions sub WHERE sub.student_id = c.s_id AND sub.status = 'active';

  UPDATE public.line_university_schedules SET departure_time = '07:15' WHERE line_id = c.line_id AND university_id = c.u1;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'schedule time edit propagates to subscriptions',
    sub.departure_time = '07:15', sub.departure_time::text
    FROM public.subscriptions sub WHERE sub.student_id = c.s_id AND sub.status = 'active';

  INSERT INTO e2e_results(step, ok, detail) SELECT 'rider counts are split per university trip',
    count(DISTINCT university_name) = 2, string_agg(DISTINCT university_name || ' ' || departure_time::text, ', ')
    FROM public.get_line_rider_counts_with_returns(c.line_id, CURRENT_DATE);
END $$;
RESET ROLE;

-- ------------------------------------------------------- STUDENT S (served, U1)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', s_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student S: sees the line with ONLY own university time',
    count(*) = 1 AND bool_and(departure_time = '07:15' AND schedule_id IS NOT NULL), string_agg(university_name || ' ' || departure_time::text, ', ')
    FROM public.get_student_line_options() WHERE line_id = c.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student S: schedule table shows only own university row',
    count(*) = 1 AND bool_and(university_id = c.u1), count(*)::text
    FROM public.line_university_schedules WHERE line_id = c.line_id;
  BEGIN
    INSERT INTO public.line_university_schedules(line_id, university_id, departure_time, return_time)
      VALUES (c.line_id, c.u2, '06:00', '12:00');
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation OR unique_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student S: cannot create or alter schedules', v_ok, NULL);
END $$;
RESET ROLE;

-- ------------------------------------------------ STUDENT T (other university)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', t_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_ok boolean; v_msg text;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  IF c.t_id IS NULL THEN
    INSERT INTO e2e_results(step, ok, detail) VALUES ('student T: fixture exists', false, 'no student from another university');
    RETURN;
  END IF;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student T: line not offered to unserved university',
    count(*) = 0, count(*)::text FROM public.get_student_line_options() WHERE line_id = c.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student T: cannot read other universities schedules',
    count(*) = 0, count(*)::text FROM public.line_university_schedules WHERE line_id = c.line_id;
  BEGIN
    INSERT INTO public.subscriptions(student_id, line_id, station_id, type, price, departure_time, return_time)
      VALUES (c.t_id, c.line_id, c.station_id, 'termly', 0, '07:35', '15:00');
    v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student T: subscribing to an unserved line is rejected', v_ok, v_msg);
END $$;
RESET ROLE;

-- Student T becomes served by adding T's university (as company admin), then subscribes.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO public.line_university_schedules(line_id, university_id, departure_time, return_time)
    SELECT c.line_id, c.t_uni, '08:00', '16:00' WHERE c.t_uni IS NOT NULL;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', t_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  -- Client sends a wrong time and price; the server must enforce both.
  INSERT INTO public.subscriptions(student_id, line_id, station_id, type, price, departure_time, return_time)
    VALUES (c.t_id, c.line_id, c.station_id, 'termly', 0, '05:00', '05:30');
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student T: subscription gets own university time (server-owned)',
    sub.departure_time = '08:00' AND sub.return_time = '16:00' AND sub.schedule_id IS NOT NULL
      AND sub.status = 'pending_payment' AND sub.price > 0,
    sub.departure_time::text || ' / ' || sub.return_time::text || ' price ' || sub.price::text
    FROM public.subscriptions sub WHERE sub.student_id = c.t_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student T: sees only own university time on the line',
    count(*) = 1 AND bool_and(departure_time = '08:00'), string_agg(university_name || ' ' || departure_time::text, ', ')
    FROM public.get_student_line_options() WHERE line_id = c.line_id;
END $$;
RESET ROLE;

-- ------------------------------------------------------------------ SUPERVISOR
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'supervisor: sees every university trip of own line',
    count(*) >= 2, count(*)::text FROM public.line_university_schedules WHERE line_id = c.line_id;
END $$;
RESET ROLE;

DO $$ BEGIN
  RAISE EXCEPTION 'E2E_RESULTS %', (SELECT json_agg(json_build_object('n', n, 'step', step, 'ok', ok, 'detail', detail) ORDER BY n) FROM e2e_results);
END $$;
ROLLBACK;
