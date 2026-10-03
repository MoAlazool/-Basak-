-- End-to-end test for 20261007000001: dashboard reset (non-destructive),
-- subscription report, company payment methods, password-reset bookkeeping and
-- multi-university lines. ONE transaction, aborted at the end: nothing persists.
--   npx.cmd supabase@latest db query --project-ref <ref> --linked -f supabase/tests/e2e_finance_payments.sql
BEGIN;

CREATE TEMP TABLE e2e_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
GRANT ALL ON e2e_results TO authenticated;
GRANT USAGE ON SEQUENCE e2e_results_n_seq TO authenticated;

CREATE TEMP TABLE e2e_ctx ON COMMIT DROP AS SELECT
  (SELECT id FROM public.admins WHERE role = 'super_admin' ORDER BY created_at LIMIT 1) AS super_id,
  (SELECT id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS cadmin_id,
  (SELECT company_id FROM public.admins WHERE role = 'company_admin' ORDER BY created_at LIMIT 1) AS company_id,
  NULL::uuid AS other_company, NULL::uuid AS stu_a, NULL::uuid AS stu_b, NULL::uuid AS uni_a, NULL::uuid AS uni_b,
  NULL::uuid AS uni_c, NULL::uuid AS line_id, NULL::uuid AS method_id, NULL::uuid AS other_method,
  (SELECT count(*) FROM public.subscriptions) AS subs_before, (SELECT count(*) FROM public.receipts) AS receipts_before;
-- Two students of different universities; a third university nobody here attends.
UPDATE e2e_ctx SET stu_a = (SELECT id FROM public.students WHERE university_id IS NOT NULL ORDER BY created_at LIMIT 1);
UPDATE e2e_ctx SET uni_a = (SELECT university_id FROM public.students WHERE id = e2e_ctx.stu_a);
UPDATE e2e_ctx SET stu_b = (SELECT id FROM public.students WHERE university_id IS NOT NULL AND university_id <> e2e_ctx.uni_a ORDER BY created_at LIMIT 1);
UPDATE e2e_ctx SET uni_b = (SELECT university_id FROM public.students WHERE id = e2e_ctx.stu_b);
UPDATE e2e_ctx SET uni_c = (SELECT id FROM public.universities WHERE id NOT IN (e2e_ctx.uni_a, COALESCE(e2e_ctx.uni_b, e2e_ctx.uni_a)) LIMIT 1);
INSERT INTO public.companies(name, is_active) VALUES ('E2E other company', true);
UPDATE e2e_ctx SET other_company = (SELECT id FROM public.companies WHERE name = 'E2E other company');
INSERT INTO public.company_payment_methods(company_id, method_type, display_name, wallet_phone)
SELECT other_company, 'vodafone_cash', 'E2E other wallet', '01000000000' FROM e2e_ctx;
UPDATE e2e_ctx SET other_method = (SELECT id FROM public.company_payment_methods WHERE display_name = 'E2E other wallet');
GRANT ALL ON e2e_ctx TO authenticated;
DELETE FROM public.subscriptions WHERE student_id IN (SELECT stu_a FROM e2e_ctx UNION SELECT stu_b FROM e2e_ctx);

-- =================================================================== COMPANY ADMIN
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', cadmin_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_ok boolean; v_msg text; v_line jsonb; v_id uuid;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  -- ---- multi-university line ----
  v_line := jsonb_build_object('name', 'E2E shared line', 'origin_name', 'منية النصر',
    'price_termly', 3000, 'price_yearly', 5500, 'price_daily', 40,
    'university_ids', jsonb_build_array(c.uni_a, c.uni_c),
    'stations', jsonb_build_array(jsonb_build_object('name', 'S1')),
    'trips', jsonb_build_array(
      jsonb_build_object('direction', 'departure', 'start_time', '07:00', 'university_id', c.uni_a,
        'stops', jsonb_build_array(jsonb_build_object('station_index', 0, 'time', '07:10'))),
      jsonb_build_object('direction', 'departure', 'start_time', '07:20', 'university_id', c.uni_c,
        'stops', jsonb_build_array(jsonb_build_object('station_index', 0, 'time', '07:30'))),
      jsonb_build_object('direction', 'return', 'start_time', '15:00',
        'stops', jsonb_build_array(jsonb_build_object('station_index', 0, 'time', '15:20')))));
  v_id := public.save_line(v_line);
  UPDATE e2e_ctx SET line_id = v_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'line: one line stored for two universities',
    (SELECT count(*) FROM public.line_universities WHERE line_id = v_id) = 2
    AND (SELECT count(*) FROM public.lines WHERE name = 'E2E shared line') = 1, NULL;
  BEGIN
    PERFORM public.save_line(v_line || jsonb_build_object('university_ids', '[]'::jsonb));
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('line: at least one university required', v_ok, v_msg);
  BEGIN
    PERFORM public.save_line(jsonb_set(v_line || jsonb_build_object('university_ids', jsonb_build_array(c.uni_a)),
      '{trips,1,university_id}', to_jsonb(c.uni_c)));
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('line: trip university must be one of the line''s', v_ok, v_msg);

  BEGIN
    -- Universities A and C selected, but both departure trips restricted to A.
    PERFORM public.save_line(jsonb_set(v_line, '{trips,1,university_id}', to_jsonb(c.uni_a)));
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('line: every selected university needs a departure trip', v_ok, v_msg);

  -- ---- payment methods ----
  INSERT INTO public.company_payment_methods(company_id, method_type, display_name, instapay_address, instructions)
  VALUES (c.company_id, 'instapay', 'InstaPay الشركة', 'basak@instapay', 'حوّل ثم ارفع الإيصال')
  RETURNING id INTO v_id;
  UPDATE e2e_ctx SET method_id = v_id;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('payments: company admin adds a method for own company', true, NULL);
  BEGIN
    INSERT INTO public.company_payment_methods(company_id, method_type, display_name, instapay_address)
    VALUES (c.other_company, 'instapay', 'hijack', 'x@instapay');
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('payments: cannot add a method to another company', v_ok, NULL);
  UPDATE public.company_payment_methods SET display_name = 'x' WHERE company_id = c.other_company;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'payments: cannot see or edit another company''s methods',
    NOT EXISTS (SELECT 1 FROM public.company_payment_methods WHERE company_id = c.other_company), NULL;
  BEGIN
    INSERT INTO public.company_payment_methods(company_id, method_type, display_name, wallet_phone)
    VALUES (c.company_id, 'vodafone_cash', 'bad wallet', '123');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('payments: invalid Vodafone Cash number rejected', v_ok, NULL);

  -- ---- password flag + audit ----
  BEGIN
    UPDATE public.students SET must_change_password = false WHERE id = c.stu_a;
    v_ok := NOT FOUND;
  EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('password: admins cannot flip the must-change flag directly', v_ok, NULL);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'password: company admin cannot read the reset audit',
    count(*) = 0, count(*)::text FROM public.password_admin_resets;

  -- ---- reset is super-admin only ----
  BEGIN
    PERFORM public.admin_reset_reports('financial', 'RESET FINANCIAL DATA');
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('reset: company admin is refused', v_ok, NULL);
END $$;
RESET ROLE;

-- =================================================================== STUDENTS
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', stu_a, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; v_station uuid; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student (university A): sees only A''s trip + open trips',
    count(*) = 2 AND bool_and(university_id IS NULL OR university_id = c.uni_a), count(*)::text
    FROM public.line_trips WHERE line_id = c.line_id;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student: sees only active methods of the available company',
    count(*) >= 1 AND bool_and(company_id = c.company_id AND is_active), string_agg(display_name, ', ')
    FROM public.company_payment_methods WHERE company_id IN (c.company_id, c.other_company);
  SELECT id INTO v_station FROM public.stations WHERE line_id = c.line_id;
  INSERT INTO public.subscriptions(student_id, line_id, station_id, type, price,
    departure_trip_id, return_trip_id)
  SELECT c.stu_a, c.line_id, v_station, 'daily', 0,
    (SELECT id FROM public.line_trips WHERE line_id = c.line_id AND start_time = '07:00'),
    (SELECT id FROM public.line_trips WHERE line_id = c.line_id AND direction = 'return');
  BEGIN
    UPDATE public.students SET must_change_password = false WHERE id = c.stu_a;
    v_ok := NOT FOUND;
  EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('password: students cannot clear their own flag', v_ok, NULL);
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', stu_b, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  IF c.stu_b IS NULL THEN RETURN; END IF;
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student (university B, not served): line hidden',
    count(*) = 0, count(*)::text FROM public.line_trips WHERE line_id = c.line_id;
  -- B may legitimately use the main company; another company is never visible.
  INSERT INTO e2e_results(step, ok, detail) SELECT 'student (B): no access to another company''s payment details',
    NOT EXISTS (SELECT 1 FROM public.company_payment_methods WHERE id = c.other_method), NULL;
END $$;
RESET ROLE;

-- Receipts: the payment method must belong to the subscription's company.
SELECT set_config('request.jwt.claims', '', true);
DO $$
DECLARE c record; v_sub uuid; v_ok boolean;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  SELECT id INTO v_sub FROM public.subscriptions WHERE student_id = c.stu_a AND line_id = c.line_id;
  UPDATE public.subscriptions SET type = 'termly', status = 'pending_payment', paid_at = NULL WHERE id = v_sub;
  BEGIN
    INSERT INTO public.receipts(subscription_id, image_url, status, payment_method_id)
    VALUES (v_sub, c.stu_a || '/' || v_sub || '_x.jpg', 'pending', c.other_method);
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('receipt: another company''s payment method is rejected', v_ok, NULL);
  INSERT INTO public.receipts(subscription_id, image_url, status, payment_method_id)
  VALUES (v_sub, c.stu_a || '/' || v_sub || '_y.jpg', 'pending', c.method_id);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'receipt: linked to student, company subscription and method',
    r.payment_method_id = c.method_id AND s.company_id = c.company_id AND s.student_id = c.stu_a, NULL
    FROM public.receipts r JOIN public.subscriptions s ON s.id = r.subscription_id WHERE r.subscription_id = v_sub;
END $$;

-- =================================================================== SUPER ADMIN
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', super_id, 'role', 'authenticated')::text, true) FROM e2e_ctx;
DO $$
DECLARE c record; r jsonb; r2 jsonb; v_ok boolean; v_reset jsonb;
BEGIN
  SELECT * INTO c FROM e2e_ctx;
  r := public.admin_subscription_report('{}'::jsonb);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('report: revenue = sum of paid rows (no double counting)',
    (r->'totals'->>'revenue')::numeric = (SELECT COALESCE(sum((x->>'amount')::numeric), 0) FROM jsonb_array_elements(r->'rows') x WHERE (x->>'paid')::boolean)
    AND (r->'totals'->>'revenue')::numeric = (r->'totals'->>'revenue_first')::numeric + (r->'totals'->>'revenue_second')::numeric
      + (r->'totals'->>'revenue_summer')::numeric + (r->'totals'->>'revenue_annual')::numeric + (r->'totals'->>'revenue_daily')::numeric,
    (r->'totals')::text);
  r2 := public.admin_subscription_report(jsonb_build_object('payment', 'unpaid', 'search',
    (SELECT phone FROM public.students WHERE id = c.stu_a)));
  INSERT INTO e2e_results(step, ok, detail) VALUES ('report: search by phone + unpaid filter finds the student',
    jsonb_array_length(r2->'rows') = 1 AND (r2->'rows'->0->>'paid')::boolean = false
      AND r2->'rows'->0->>'payment_method' = 'InstaPay الشركة', r2->'rows'->0->>'student_name');

  BEGIN
    PERFORM public.admin_reset_reports('all', 'reset all data');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('reset: wrong confirmation phrase refused', v_ok, NULL);
  v_reset := public.admin_reset_reports('financial', 'RESET FINANCIAL DATA', 'E2E');
  r2 := public.admin_subscription_report('{}'::jsonb);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('reset: dashboard counts start from zero',
    (r2->'totals'->>'count')::int = 0 AND (r2->'totals'->>'revenue')::numeric = 0, (r2->'totals')::text);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'reset: nothing deleted from the database',
    (SELECT count(*) FROM public.subscriptions) >= c.subs_before AND (SELECT count(*) FROM public.receipts) >= c.receipts_before, NULL;
  r2 := public.admin_subscription_report('{"include_before_reset": true}'::jsonb);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('reset: full history still available',
    (r2->'totals'->>'count')::int = (r->'totals'->>'count')::int, (r2->'totals'->>'count'));
  BEGIN
    PERFORM public.admin_reset_reports('financial', 'RESET FINANCIAL DATA');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  INSERT INTO e2e_results(step, ok, detail) VALUES ('reset: repeated execution within a minute refused', v_ok, NULL);
  PERFORM public.admin_undo_report_reset((v_reset->>'id')::uuid);
  r2 := public.admin_subscription_report('{}'::jsonb);
  INSERT INTO e2e_results(step, ok, detail) VALUES ('reset: undo restores the previous figures',
    (r2->'totals'->>'count')::int = (r->'totals'->>'count')::int, NULL);
  INSERT INTO e2e_results(step, ok, detail) SELECT 'payments: super admin sees every company''s methods',
    count(DISTINCT company_id) >= 2, count(*)::text FROM public.company_payment_methods;
END $$;
RESET ROLE;

DO $$ BEGIN
  RAISE EXCEPTION 'E2E_RESULTS %', (SELECT json_agg(json_build_object('n', n, 'step', step, 'ok', ok, 'detail', detail) ORDER BY n) FROM e2e_results);
END $$;
ROLLBACK;
