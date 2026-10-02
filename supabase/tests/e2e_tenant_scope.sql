-- End-to-end tenant-scope test: Super Admin -> Company Admin -> Supervisor -> Student.
-- Impersonates real accounts through request.jwt.claims inside ONE transaction that
-- is aborted at the end (deliberate exception), so nothing is persisted. Run with:
--   npx.cmd supabase@latest db query --project-ref <ref> --linked -f supabase/tests/e2e_tenant_scope.sql
BEGIN;

CREATE TEMP TABLE e2e_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON e2e_results TO authenticated;
GRANT USAGE ON SEQUENCE e2e_results_n_seq TO authenticated;

CREATE TEMP TABLE e2e_ctx ON COMMIT DROP AS SELECT
  (SELECT id FROM public.admins WHERE role = 'super_admin' ORDER BY created_at LIMIT 1) AS super_id,
  (SELECT id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS cadmin_id,
  (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS company_id,
  (SELECT s.id FROM public.supervisors s JOIN auth.users u ON u.id = s.id
     WHERE s.company_id = (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1)
     LIMIT 1) AS supervisor_id,
  (SELECT sub.student_id FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
     JOIN auth.users u ON u.id = sub.student_id
     WHERE l.company_id = (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1)
     LIMIT 1) AS student_id;
GRANT SELECT ON e2e_ctx TO authenticated;

-- ---------------------------------------------------------------- SUPER ADMIN
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', super_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE v_company uuid; v_line uuid;
BEGIN
  INSERT INTO e2e_results(step, ok, detail) SELECT 'super: is_super_admin()', public.is_super_admin(), NULL;
  INSERT INTO public.companies(name, is_active) VALUES ('E2E other company', true) RETURNING id INTO v_company;
  INSERT INTO public.lines(company_id, name, price_termly, price_yearly, price_daily, is_active)
    VALUES (v_company, 'E2E other line', 1, 2, 3, true) RETURNING id INTO v_line;
  INSERT INTO public.stations(line_id, name, order_index, departure_times, return_times, departure_time, return_time)
    VALUES (v_line, 'E2E station', 1, ARRAY['07:00'::time], ARRAY['15:00'::time], '07:00', '15:00');
  INSERT INTO e2e_results(step, ok, detail) VALUES ('super: creates company+line+station for another company', true, NULL);
  INSERT INTO e2e_results(step, ok, detail)
    SELECT 'super: sees every company', count(*) = (SELECT count(*) FROM public.companies), count(*)::text FROM public.companies;
  INSERT INTO e2e_results(step, ok, detail)
    SELECT 'super: sees all admins', count(*) >= 2, count(*)::text FROM public.admins;
END $$;
RESET ROLE;

-- -------------------------------------------------------------- COMPANY ADMIN
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE v_company uuid := (SELECT company_id FROM e2e_ctx); v_other uuid; v_rows int; v_ok boolean;
BEGIN
  SELECT id INTO v_other FROM public.companies WHERE id <> v_company LIMIT 1;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: role resolved from admins table',
    public.is_company_admin() AND public.current_admin_company_id() = v_company, public.current_admin_company_id()::text;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: sees only its own company',
    count(*) = 1 AND bool_and(id = v_company), count(*)::text FROM public.companies;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: sees its lines and only its lines',
    count(*) > 0 AND bool_and(company_id = v_company), count(*)::text FROM public.lines;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: stations limited to own lines',
    bool_and(l.company_id = v_company), count(*)::text FROM public.stations s JOIN public.lines l ON l.id = s.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: subscriptions limited to own lines',
    COALESCE(bool_and(l.company_id = v_company), true), count(*)::text
    FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: sees its subscribed students',
    count(*) > 0, count(*)::text FROM public.students;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: supervisors limited to own company',
    COALESCE(bool_and(company_id = v_company), true), count(*)::text FROM public.supervisors;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: receipts limited to own lines',
    COALESCE(bool_and(l.company_id = v_company), true), count(*)::text
    FROM public.receipts r JOIN public.subscriptions sub ON sub.id = r.subscription_id JOIN public.lines l ON l.id = sub.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: sees only own admin row',
    count(*) = 1, count(*)::text FROM public.admins;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'company: can read universities catalog',
    count(*) >= 0, count(*)::text FROM public.universities;

  -- Writes into its own company are allowed.
  INSERT INTO public.lines(company_id, name, price_termly, price_yearly, price_daily, is_active)
    VALUES (v_company, 'E2E own line', 1, 2, 3, true);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: can create a line for its company', true, NULL);

  -- Writes into another company are blocked.
  BEGIN
    INSERT INTO public.lines(company_id, name, price_termly, price_yearly, price_daily, is_active)
      VALUES (v_other, 'E2E hijack', 1, 2, 3, true);
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: blocked from creating line in another company', v_ok, NULL);

  UPDATE public.lines SET price_daily = 999 WHERE company_id <> v_company;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: cannot edit other companies lines', v_rows = 0, v_rows::text);

  BEGIN
    UPDATE public.lines SET company_id = v_other WHERE company_id = v_company AND name = 'E2E own line';
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: cannot move its line to another company', v_ok, NULL);

  BEGIN
    INSERT INTO public.supervisors(id, full_name, phone, company_id) VALUES (gen_random_uuid(), 'x', '01099999999', v_other);
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation OR foreign_key_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: blocked from adding supervisor to another company', v_ok, NULL);

  UPDATE public.companies SET name = name WHERE id = v_company;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: cannot edit company records (super only)', v_rows = 0, v_rows::text);
END $$;
RESET ROLE;

-- Rider-count RPC against a foreign line id (looked up as postgres, called as company admin).
CREATE TEMP TABLE e2e_foreign ON COMMIT DROP AS
  SELECT id FROM public.lines WHERE company_id <> (SELECT company_id FROM e2e_ctx) LIMIT 1;
GRANT SELECT ON e2e_foreign TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    PERFORM * FROM public.get_line_rider_counts_with_returns((SELECT id FROM e2e_foreign), CURRENT_DATE);
    v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('company: rider-count RPC refuses foreign line', v_ok, NULL);
END $$;
RESET ROLE;

-- ----------------------------------------------------------------- SUPERVISOR
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', supervisor_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE v_company uuid := (SELECT company_id FROM e2e_ctx); v_ok boolean;
BEGIN
  IF (SELECT supervisor_id FROM e2e_ctx) IS NULL THEN
    INSERT INTO e2e_results(step, ok, detail) VALUES ('supervisor: linked Auth account exists', false, 'no supervisor with Auth user');
    RETURN;
  END IF;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'supervisor: is_supervisor()', public.is_supervisor(), NULL;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'supervisor: assigned lines = own company lines',
    count(*) > 0 AND bool_and(l.company_id = v_company), count(*)::text
    FROM public.get_supervisor_assigned_line_ids() a JOIN public.lines l ON l.id = a.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'supervisor: subscriptions limited to assigned lines',
    COALESCE(bool_and(l.company_id = v_company), true), count(*)::text
    FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id;
  BEGIN
    PERFORM * FROM public.get_line_rider_counts_with_returns((SELECT id FROM e2e_foreign), CURRENT_DATE);
    v_ok := false;
  EXCEPTION WHEN raise_exception THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('supervisor: rider-count RPC refuses foreign line', v_ok, NULL);
  BEGIN
    UPDATE public.subscriptions SET price = 0;
    v_ok := NOT FOUND;
  EXCEPTION WHEN raise_exception OR insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('supervisor: cannot edit subscription prices', v_ok, NULL);
END $$;
RESET ROLE;

-- -------------------------------------------------------------------- STUDENT
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', student_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE v_me uuid := (SELECT student_id FROM e2e_ctx); v_ok boolean; v_rows int;
BEGIN
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: not an admin', NOT public.is_admin(), NULL;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: sees only own profile',
    count(*) = 1 AND bool_and(id = v_me), count(*)::text FROM public.students;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: sees only own subscriptions',
    bool_and(student_id = v_me), count(*)::text FROM public.subscriptions;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: cannot read admins', count(*) = 0, count(*)::text FROM public.admins;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: sees active lines to subscribe',
    count(*) > 0 AND bool_and(is_active), count(*)::text FROM public.lines;
  BEGIN
    UPDATE public.subscriptions SET status = 'active', price = 0 WHERE student_id = v_me;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_ok := v_rows = 0;
  EXCEPTION WHEN raise_exception OR insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student: cannot self-activate or change price', v_ok, NULL);
  BEGIN
    INSERT INTO public.daily_ride_status(student_id, ride_date, is_riding) VALUES (v_me, CURRENT_DATE + 1, true);
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation OR not_null_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('student: ride votes only via RPC (no direct insert)', v_ok, NULL);
END $$;
RESET ROLE;

-- Abort on purpose: the error carries the results out and guarantees nothing persists.
DO $$ BEGIN
  RAISE EXCEPTION 'E2E_RESULTS %', (SELECT json_agg(json_build_object('n', n, 'step', step, 'ok', ok, 'detail', detail) ORDER BY n) FROM e2e_results);
END $$;
ROLLBACK;
