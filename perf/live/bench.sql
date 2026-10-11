-- ==============================================================================
-- Live capacity benchmark helpers (docs/audit/2026-10-CAPACITY.md).
--
-- Everything lives in the schema `bench`, which is dropped at the end; the
-- application schema (public) is not changed. Data is written into the real
-- public tables for companies named 'BENCH …', using only sign-in accounts that
-- were created through the Auth Admin API by perf/live/auth_users.mjs (e-mail
-- ending @bench.busak.app). Nothing here writes to auth.*.
--
-- Bulk loading runs with session_replication_role = replica (per transaction):
-- the app's triggers would otherwise broadcast every inserted row on Realtime and
-- queue pushes. Every column those triggers would fill is filled here, and
-- bench.check() verifies the foreign keys afterwards.
--
-- One academic year of history (2025/26: first, second, summer) plus the term in
-- progress (first 2026/27, up to today). For a company with K active students a
-- regular term, at return rate R (default 0.6):
--   t1 first 2025   K active, all new
--   t2 second 2025  K active: R·K returning from t1, the rest new
--   t3 summer 2025  S = round(0.35·K) active: R·S returning from t2, the rest new
--   t4 first 2026   K active (current): R·K returning, the rest new
-- Usage profile per student: 25% light, 55% normal, 20% heavy.
--   ride days voted (of the term's Sun–Thu days): light 35%, normal 75%, heavy 95%
--   scans per riding day: light departure only (50% of days); normal departure
--   + return (90%); heavy departure + return (100%)
--   receipts: a rejected first attempt for light 5%, normal 10%, heavy 30%
-- Notifications follow the app's own retention (notifications_purge: subscription
-- notices 30 days, others 7 days), so only that window is stored.
-- ==============================================================================
CREATE SCHEMA IF NOT EXISTS bench;

-- A number in [0, 1) from any text, stable across runs.
CREATE OR REPLACE FUNCTION bench.h(p text) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$ SELECT ('x' || substr(md5(p), 1, 8))::bit(32)::bigint / 4294967296.0 $$;

CREATE TABLE IF NOT EXISTS bench.company (
  seq int PRIMARY KEY, id uuid NOT NULL, k int NOT NULL, ret numeric NOT NULL, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS bench.student (
  id uuid PRIMARY KEY, company_id uuid NOT NULL, n int NOT NULL, profile text NOT NULL,
  line_id uuid, university_id uuid, station_id uuid, dep uuid, ret uuid);
CREATE TABLE IF NOT EXISTS bench.active (student_id uuid NOT NULL, term text NOT NULL, PRIMARY KEY (student_id, term));
CREATE TABLE IF NOT EXISTS bench.checkpoint (
  label text PRIMARY KEY, at timestamptz DEFAULT now(), companies int, active_per_term int, sizes jsonb);

CREATE OR REPLACE FUNCTION bench.terms() RETURNS TABLE (term text, code text, academic_year int, start_date date, end_date date, active_until date)
LANGUAGE sql STABLE AS $$
  SELECT * FROM (VALUES
    ('t1', 'first',  2025, date '2025-09-05', date '2026-01-30', date '2026-01-30'),
    ('t2', 'second', 2025, date '2026-02-01', date '2026-06-30', date '2026-06-30'),
    ('t3', 'summer', 2025, date '2026-07-01', date '2026-09-01', date '2026-09-01'),
    ('t4', 'first',  2026, date '2026-09-05', date '2027-01-30', LEAST(date '2027-01-30', public.cairo_today() - 1))
  ) v(term, code, academic_year, start_date, end_date, active_until)
$$;

-- Sun–Thu days of a term up to the day it is active until.
CREATE OR REPLACE FUNCTION bench.class_days(p_term text) RETURNS SETOF date LANGUAGE sql STABLE AS $$
  SELECT d::date FROM bench.terms() t, generate_series(t.start_date, t.active_until, interval '1 day') d
  WHERE t.term = p_term AND extract(dow FROM d) IN (0, 1, 2, 3, 4)
$$;

-- ------------------------------------------------------------------ company base
-- Company, its settings, two admins, lines, stations, trips, prices, supervisors,
-- and the students' accounts with their memberships and terms.
CREATE OR REPLACE FUNCTION bench.add_company(p_seq int, p_k int, p_ret numeric DEFAULT 0.6)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid := gen_random_uuid();
  v_super uuid := (SELECT id FROM public.admins WHERE role = 'super_admin' ORDER BY created_at LIMIT 1);
  v_lines int := GREATEST(2, ceil(p_k / 120.0)::int);
  v_s int := round(0.35 * p_k);
  v_new2 int := p_k - round(p_ret * p_k)::int;
  v_new3 int := v_s - round(p_ret * v_s)::int;
  v_new4 int := p_k - round(p_ret * p_k)::int;
  v_pool int;
BEGIN
  IF EXISTS (SELECT 1 FROM bench.company WHERE seq = p_seq) THEN RAISE EXCEPTION 'company % exists', p_seq; END IF;
  v_pool := p_k + v_new2 + v_new3 + v_new4;
  SET LOCAL session_replication_role = replica;

  INSERT INTO public.companies (id, name, status, contact_phone, address)
  VALUES (v_company, 'BENCH شركة ' || p_seq, 'active', '0100000' || lpad(p_seq::text, 4, '0'), 'المنصورة، شارع الجمهورية');
  INSERT INTO bench.company (seq, id, k, ret) VALUES (p_seq, v_company, p_k, p_ret);
  INSERT INTO public.company_terms (company_id, code, name, sort_order, start_month, start_day, start_year_offset,
                                    end_month, end_day, end_year_offset, included_in_annual, is_active, is_on_sale)
  SELECT v_company, code, name, sort_order, start_month, start_day, start_year_offset, end_month, end_day, end_year_offset,
         included_in_annual, is_active, is_on_sale FROM public.academic_terms;
  INSERT INTO public.company_payment_methods (company_id, method_type, display_name, account_holder, instapay_address, wallet_phone, sort_order)
  VALUES (v_company, 'instapay', 'إنستاباي', 'BENCH ' || p_seq, 'bench' || p_seq || '@instapay', NULL, 1),
         (v_company, 'vodafone_cash', 'فودافون كاش', 'BENCH ' || p_seq, NULL, '0100' || lpad(p_seq::text, 7, '0'), 2);
  INSERT INTO public.wallet_card_settings (company_id) VALUES (v_company);
  INSERT INTO public.company_governorates (company_id, governorate_code) SELECT v_company, code FROM public.governorates ORDER BY code LIMIT 1;
  INSERT INTO public.company_receipt_counters (company_id, last_no) VALUES (v_company, 0);

  -- Two admins from the free admin accounts.
  INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id)
  SELECT u.id, u.email, u.raw_user_meta_data->>'full_name', 'company_admin', v_company, v_super
  FROM auth.users u
  WHERE u.email LIKE 'admin-%@bench.busak.app' AND NOT EXISTS (SELECT 1 FROM public.admins a WHERE a.id = u.id)
  ORDER BY u.email LIMIT 2;
  IF NOT FOUND THEN RAISE EXCEPTION 'no free benchmark admin accounts'; END IF;

  -- Lines, two universities each, 6–9 stations, two departures and a return per university.
  CREATE TEMP TABLE b_l ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, g.n FROM generate_series(1, v_lines) g(n);
  INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily, origin_name, bus_capacity)
  SELECT id, v_company, 'BENCH خط ' || p_seq || '-' || n, 2500 + (n % 4) * 250, 4800 + (n % 4) * 400, 40, 'ميت غمر', 50 FROM b_l;
  CREATE TEMP TABLE b_lu ON COMMIT DROP AS
  SELECT l.id AS line_id, u.id AS university_id
  FROM b_l l CROSS JOIN LATERAL (SELECT id FROM public.universities WHERE is_active
                                 ORDER BY md5(id::text || l.n || p_seq) LIMIT 2) u;
  INSERT INTO public.line_universities (line_id, university_id, company_id) SELECT line_id, university_id, v_company FROM b_lu;
  INSERT INTO public.line_period_prices (line_id, company_id, option, price)
  SELECT l.id, v_company, o, CASE o WHEN 'both' THEN 4800 WHEN 'summer' THEN 1500 ELSE 2500 END + (l.n % 4) * 250
  FROM b_l l, unnest(ARRAY['first', 'second', 'both', 'summer']) o;
  CREATE TEMP TABLE b_s ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, l.id AS line_id, g.n FROM b_l l CROSS JOIN LATERAL generate_series(1, 6 + (l.n + p_seq) % 4) g(n);
  INSERT INTO public.stations (id, line_id, name, order_index, company_id)
  SELECT id, line_id, 'محطة ' || n, n, v_company FROM b_s;
  CREATE TEMP TABLE b_t ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, lu.line_id, lu.university_id, d.direction, d.k
  FROM b_lu lu, (VALUES ('departure', 1), ('departure', 2), ('return', 1)) d(direction, k);
  INSERT INTO public.line_trips (id, line_id, direction, label, start_time, university_id, company_id)
  SELECT id, line_id, direction, CASE direction WHEN 'departure' THEN 'ذهاب ' || k ELSE 'عودة' END,
         CASE direction WHEN 'departure' THEN time '06:00' + (k - 1) * interval '1 hour' ELSE time '15:00' END,
         university_id, v_company FROM b_t;
  INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time, company_id)
  SELECT t.id, s.id, CASE t.direction WHEN 'departure' THEN time '06:00' + (t.k - 1) * interval '1 hour' + s.n * interval '6 minutes'
                                      ELSE time '15:00' + s.n * interval '6 minutes' END, v_company
  FROM b_t t JOIN b_s s ON s.line_id = t.line_id;

  -- Supervisors: one a line and one spare, from the free supervisor accounts.
  CREATE TEMP TABLE b_sup ON COMMIT DROP AS
  SELECT u.id, u.raw_user_meta_data->>'phone' AS phone, u.raw_user_meta_data->>'full_name' AS full_name,
         row_number() OVER (ORDER BY u.email) AS n
  FROM auth.users u
  WHERE u.email LIKE '0105%@bench.busak.app' AND NOT EXISTS (SELECT 1 FROM public.supervisors s WHERE s.id = u.id)
  ORDER BY u.email LIMIT v_lines + 1;
  IF (SELECT count(*) FROM b_sup) < v_lines + 1 THEN RAISE EXCEPTION 'not enough benchmark supervisor accounts'; END IF;
  INSERT INTO public.supervisors (id, phone, full_name, company_id, created_by_admin_id)
  SELECT id, phone, full_name, v_company, v_super FROM b_sup;
  INSERT INTO public.supervisor_lines (supervisor_id, line_id, company_id, assigned_by)
  SELECT s.id, l.id, v_company, v_super FROM b_sup s JOIN b_l l ON l.n = s.n;
  UPDATE public.lines l SET supervisor_id = s.id FROM b_sup s JOIN b_l bl ON bl.n = s.n WHERE l.id = bl.id;

  -- Students: the pool of accounts this company will ever have this year.
  CREATE TEMP TABLE b_st ON COMMIT DROP AS
  SELECT u.id, u.raw_user_meta_data->>'phone' AS phone, u.raw_user_meta_data->>'full_name' AS full_name,
         row_number() OVER (ORDER BY u.email)::int AS n
  FROM auth.users u
  WHERE u.email LIKE '0125%@bench.busak.app' AND NOT EXISTS (SELECT 1 FROM public.students s WHERE s.id = u.id)
  ORDER BY u.email LIMIT v_pool;
  IF (SELECT count(*) FROM b_st) < v_pool THEN
    RAISE EXCEPTION 'need % free benchmark student accounts, have %', v_pool, (SELECT count(*) FROM b_st);
  END IF;
  INSERT INTO bench.student (id, company_id, n, profile, line_id, university_id)
  SELECT st.id, v_company, st.n,
         CASE WHEN bench.h(st.id || 'p') < 0.25 THEN 'light' WHEN bench.h(st.id || 'p') < 0.80 THEN 'normal' ELSE 'heavy' END,
         lu.line_id, lu.university_id
  FROM b_st st CROSS JOIN LATERAL (SELECT line_id, university_id FROM b_lu ORDER BY md5(line_id::text || university_id || st.id) LIMIT 1) lu;
  UPDATE bench.student bs SET
    station_id = (SELECT s.id FROM b_s s WHERE s.line_id = bs.line_id ORDER BY md5(s.id::text || bs.id) LIMIT 1),
    dep = (SELECT t.id FROM b_t t WHERE t.line_id = bs.line_id AND t.university_id = bs.university_id AND t.direction = 'departure'
           ORDER BY md5(t.id::text || bs.id) LIMIT 1),
    ret = (SELECT t.id FROM b_t t WHERE t.line_id = bs.line_id AND t.university_id = bs.university_id AND t.direction = 'return' LIMIT 1)
  WHERE bs.company_id = v_company;

  INSERT INTO public.students (id, phone, full_name, university, university_id, college, email, created_at, specialisation)
  SELECT st.id, st.phone, st.full_name, u.name, bs.university_id, 'كلية الهندسة', NULL,
         timestamptz '2025-09-01' + (st.n % 200) * interval '1 hour', CASE WHEN st.n % 3 = 0 THEN 'هندسة مدنية' END
  FROM b_st st JOIN bench.student bs ON bs.id = st.id JOIN public.universities u ON u.id = bs.university_id;
  INSERT INTO public.company_students (company_id, student_id, joined_at)
  SELECT v_company, id, timestamptz '2025-09-01' + (n % 200) * interval '1 hour' FROM b_st;

  -- Who is active in which term (n orders the pool: t1 = 1..K, then each term's newcomers).
  INSERT INTO bench.active SELECT id, 't1' FROM bench.student WHERE company_id = v_company AND n <= p_k;
  INSERT INTO bench.active
  SELECT id, 't2' FROM (SELECT id FROM bench.student WHERE company_id = v_company AND n <= p_k
                        ORDER BY bench.h(id || 't2') LIMIT p_k - v_new2) r
  UNION ALL SELECT id, 't2' FROM bench.student WHERE company_id = v_company AND n > p_k AND n <= p_k + v_new2;
  INSERT INTO bench.active
  SELECT a.student_id, 't3' FROM (SELECT student_id FROM bench.active a JOIN bench.student s ON s.id = a.student_id
                                  WHERE s.company_id = v_company AND a.term = 't2'
                                  ORDER BY bench.h(a.student_id || 't3') LIMIT v_s - v_new3) a
  UNION ALL SELECT id, 't3' FROM bench.student WHERE company_id = v_company AND n > p_k + v_new2 AND n <= p_k + v_new2 + v_new3;
  -- Returning in t4: last year's second-term and summer riders first, then earlier ones.
  INSERT INTO bench.active
  SELECT id, 't4' FROM (SELECT s.id FROM bench.student s
                        WHERE s.company_id = v_company AND s.n <= p_k + v_new2 + v_new3
                        ORDER BY (EXISTS (SELECT 1 FROM bench.active a WHERE a.student_id = s.id AND a.term IN ('t2', 't3'))) DESC,
                                 bench.h(s.id || 't4') LIMIT p_k - v_new4) r
  UNION ALL SELECT id, 't4' FROM bench.student WHERE company_id = v_company AND n > p_k + v_new2 + v_new3;

  -- Devices: one phone a person (disabled so no push is ever sent to these fake tokens).
  INSERT INTO public.push_devices (user_id, installation_id, platform, token, app_version, last_seen_at, disabled_at, disabled_reason)
  SELECT p.id, 'bench-' || p.id, CASE WHEN bench.h(p.id || 'os') < 0.3 THEN 'ios' ELSE 'android' END,
         repeat(md5(p.id::text), 5), '1.4.0', now() - (bench.h(p.id || 'seen') * 20) * interval '1 day', now(), 'benchmark'
  FROM (SELECT id FROM b_st UNION ALL SELECT id FROM b_sup
        UNION ALL SELECT id FROM public.admins WHERE company_id = v_company) p;

  RETURN jsonb_build_object('company', v_company, 'k', p_k, 'lines', v_lines, 'supervisors', v_lines + 1,
    'accounts', v_pool, 'active', (SELECT jsonb_object_agg(term, c) FROM (SELECT a.term, count(*) c FROM bench.active a
      JOIN bench.student s ON s.id = a.student_id WHERE s.company_id = v_company GROUP BY 1) x));
END;
$$;

-- ------------------------------------------------------------ subscriptions
-- t1+t2 actives who stay all year take "both" (yearly) a third of the time, the
-- others a termly subscription per term; summer is always separate. Past terms
-- are expired and paid; the current term: 82% active, 5% under review, 5% waiting
-- with a rejected receipt, 8% waiting to pay. Approved ones carry their receipt
-- snapshot (subscription_receipts).
CREATE OR REPLACE FUNCTION bench.add_subscriptions(p_seq int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid := (SELECT id FROM bench.company WHERE seq = p_seq);
  v_cname text := (SELECT name FROM public.companies WHERE id = v_company);
  v_method uuid := (SELECT id FROM public.company_payment_methods WHERE company_id = v_company ORDER BY sort_order LIMIT 1);
  v_n int;
BEGIN
  SET LOCAL session_replication_role = replica;
  CREATE TEMP TABLE b_sub ON COMMIT DROP AS
  WITH m AS (
    SELECT s.*, (SELECT array_agg(a.term ORDER BY a.term) FROM bench.active a WHERE a.student_id = s.id) AS terms
    FROM bench.student s WHERE s.company_id = v_company
  ), plan AS (
    SELECT m.*, x.term, x.kind FROM m CROSS JOIN LATERAL (
      SELECT 't1' AS term, 'both' AS kind WHERE m.terms @> ARRAY['t1', 't2'] AND bench.h(m.id || 'y25') < 0.33
      UNION ALL SELECT t, 'termly' FROM unnest(m.terms) t
      WHERE t <> 't4' AND NOT (t IN ('t1', 't2') AND m.terms @> ARRAY['t1', 't2'] AND bench.h(m.id || 'y25') < 0.33)
      UNION ALL SELECT 't4', CASE WHEN bench.h(m.id || 'y26') < 0.33 THEN 'both' ELSE 'termly' END WHERE m.terms @> ARRAY['t4']
    ) x
  )
  SELECT gen_random_uuid() AS id, p.id AS student_id, p.n, p.profile, p.line_id, p.station_id, p.dep, p.ret, p.university_id,
         p.term, p.kind, t.code, t.academic_year, t.start_date,
         CASE WHEN p.kind = 'both' THEN (SELECT end_date FROM bench.terms() WHERE term = CASE p.term WHEN 't1' THEN 't2' ELSE 't4' END)
              ELSE t.end_date END AS end_date,
         CASE WHEN p.term <> 't4' THEN 'expired'
              WHEN bench.h(p.id || 'st') < 0.82 THEN 'active' WHEN bench.h(p.id || 'st') < 0.87 THEN 'pending_review'
              ELSE 'pending_payment' END AS status,
         (p.term = 't4' AND bench.h(p.id || 'st') >= 0.87 AND bench.h(p.id || 'st') < 0.92) AS rejected_wait
  FROM plan p JOIN bench.terms() t ON t.term = p.term;
  UPDATE b_sub SET end_date = date '2027-06-30' WHERE kind = 'both' AND term = 't4';

  INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price, period_code,
                                    academic_year, paid_at, departure_trip_id, return_trip_id, company_id, departure_time,
                                    return_time, created_at)
  SELECT b.id, b.student_id, b.line_id, b.station_id, CASE b.kind WHEN 'both' THEN 'yearly' ELSE 'termly' END, b.status,
         b.start_date, b.end_date, lp.price, CASE b.kind WHEN 'both' THEN 'both' ELSE b.code END, b.academic_year,
         CASE WHEN b.status IN ('active', 'expired') THEN b.start_date - 2 + (b.n % 18) * interval '1 hour' END,
         b.dep, b.ret, v_company,
         (SELECT stop_time FROM public.line_trip_stops WHERE trip_id = b.dep AND station_id = b.station_id),
         (SELECT start_time FROM public.line_trips WHERE id = b.ret), b.start_date - 5 + (b.n % 18) * interval '1 hour'
  FROM b_sub b JOIN public.line_period_prices lp
    ON lp.line_id = b.line_id AND lp.option = CASE b.kind WHEN 'both' THEN 'both' ELSE b.code END;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- Receipts: a rejected first attempt for some, then the approved / pending one.
  INSERT INTO public.receipts (subscription_id, image_url, status, attempt_number, reviewed_at, amount, company_id,
                               created_at, rejection_reason, payment_method_id, reviewed_by)
  SELECT b.id, b.student_id || '/' || b.id || '_1.jpg', 'rejected', 1, b.start_date - 4, s.price, v_company,
         b.start_date - 5, 'الصورة غير واضحة', v_method, (SELECT id FROM public.admins WHERE company_id = v_company LIMIT 1)
  FROM b_sub b JOIN public.subscriptions s ON s.id = b.id
  WHERE b.rejected_wait OR (b.status IN ('active', 'expired', 'pending_review') AND bench.h(b.id || 'rej') <
        CASE b.profile WHEN 'light' THEN 0.05 WHEN 'normal' THEN 0.10 ELSE 0.30 END);
  INSERT INTO public.receipts (subscription_id, image_url, status, attempt_number, reviewed_at, amount, company_id,
                               created_at, payment_method_id, reviewed_by)
  SELECT b.id, b.student_id || '/' || b.id || '_2.jpg', CASE b.status WHEN 'pending_review' THEN 'pending' ELSE 'approved' END,
         COALESCE((SELECT max(r.attempt_number) FROM public.receipts r WHERE r.subscription_id = b.id), 0) + 1,
         CASE WHEN b.status <> 'pending_review' THEN b.start_date - 2 END, s.price, v_company, b.start_date - 3, v_method,
         CASE WHEN b.status <> 'pending_review' THEN (SELECT id FROM public.admins WHERE company_id = v_company LIMIT 1) END
  FROM b_sub b JOIN public.subscriptions s ON s.id = b.id WHERE b.status IN ('active', 'expired', 'pending_review');

  INSERT INTO public.subscription_receipts (subscription_id, company_id, student_id, receipt_no, company_name, student_name,
    student_phone, university_name, line_name, station_name, option, period_label, start_date, end_date, amount,
    payment_method, approved_at, issued_at, company_phone, company_address, receipt_code)
  SELECT s.id, v_company, s.student_id, row_number() OVER (ORDER BY s.paid_at, s.id), v_cname, st.full_name, st.phone,
         st.university, l.name, stn.name, s.period_code,
         CASE s.period_code WHEN 'first' THEN 'الفصل الدراسي الأول' WHEN 'second' THEN 'الفصل الدراسي الثاني'
              WHEN 'summer' THEN 'الفصل الصيفي' ELSE 'العام الدراسي' END || ' ' || s.academic_year || '/' || (s.academic_year + 1),
         s.start_date, s.end_date, s.price, 'إنستاباي', s.paid_at, s.paid_at, '01000000000', 'المنصورة',
         upper(substr(md5(s.id::text), 1, 10))
  FROM public.subscriptions s JOIN public.students st ON st.id = s.student_id JOIN public.lines l ON l.id = s.line_id
  JOIN public.stations stn ON stn.id = s.station_id
  WHERE s.company_id = v_company AND s.paid_at IS NOT NULL;
  UPDATE public.company_receipt_counters SET last_no = (SELECT count(*) FROM public.subscription_receipts WHERE company_id = v_company)
  WHERE company_id = v_company;

  -- Wallet card for about half of the current riders.
  INSERT INTO public.wallet_passes (student_id, platform, auth_token, company_id, content_hash)
  SELECT s.student_id, CASE WHEN bench.h(s.student_id || 'os') < 0.3 THEN 'apple' ELSE 'google' END,
         CASE WHEN bench.h(s.student_id || 'os') < 0.3 THEN md5(s.student_id::text || 'tok') END, v_company, md5(s.id::text)
  FROM public.subscriptions s WHERE s.company_id = v_company AND s.status = 'active' AND bench.h(s.student_id || 'w') < 0.5;

  RETURN jsonb_build_object('subscriptions', v_n);
END;
$$;

-- --------------------------------------------------------------- operations
-- One term of votes (daily_ride_status) and scans (supervisor_scan_events).
CREATE OR REPLACE FUNCTION bench.add_rides(p_seq int, p_term text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid := (SELECT id FROM bench.company WHERE seq = p_seq);
  v_votes int; v_scans int;
BEGIN
  SET LOCAL session_replication_role = replica;
  CREATE TEMP TABLE b_v ON COMMIT DROP AS
  SELECT s.id AS student_id, s.profile, s.line_id, s.station_id, s.dep, s.ret, d AS ride_date,
         sub.id AS subscription_id, sub.departure_time, sub.return_time,
         bench.h(s.id || d::text || 'r') AS r, bench.h(s.id || d::text || 'x') AS x
  FROM bench.student s
  JOIN bench.active a ON a.student_id = s.id AND a.term = p_term
  JOIN LATERAL (SELECT su.id, su.departure_time, su.return_time FROM public.subscriptions su
                JOIN bench.terms() t ON t.term = p_term
                WHERE su.student_id = s.id AND su.start_date <= t.start_date AND su.end_date >= t.start_date
                  AND su.paid_at IS NOT NULL LIMIT 1) sub ON true
  CROSS JOIN bench.class_days(p_term) d
  WHERE s.company_id = v_company
    AND bench.h(s.id || d::text || 'v') < CASE s.profile WHEN 'light' THEN 0.35 WHEN 'normal' THEN 0.75 ELSE 0.95 END;

  INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, is_returning, toggled_at, departure_time, return_time,
                                        company_id, subscription_id)
  SELECT student_id, ride_date, r >= 0.08, r >= 0.08 AND x < 0.85, ride_date - interval '8 hours', departure_time, return_time,
         v_company, subscription_id
  FROM b_v;
  GET DIAGNOSTICS v_votes = ROW_COUNT;

  INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, station_id, trip_id, ride_date,
                                             direction, result, scanned_at, company_id, supervisor_name)
  SELECT sl.supervisor_id, v.student_id, v.subscription_id, v.line_id, v.station_id,
         CASE dir WHEN 'departure' THEN v.dep ELSE v.ret END, v.ride_date, dir,
         CASE WHEN bench.h(v.student_id || v.ride_date::text || dir) < 0.02 THEN 'already_checked_in' ELSE 'checked_in' END,
         v.ride_date + CASE dir WHEN 'departure' THEN interval '6 hours 20 minutes' ELSE interval '15 hours 5 minutes' END,
         v_company, sup.full_name
  FROM b_v v
  JOIN public.supervisor_lines sl ON sl.line_id = v.line_id
  JOIN public.supervisors sup ON sup.id = sl.supervisor_id
  CROSS JOIN unnest(ARRAY['departure', 'return']) dir
  WHERE v.r >= 0.08
    AND bench.h(v.student_id || v.ride_date::text || 's') < CASE v.profile WHEN 'light' THEN 0.5 WHEN 'normal' THEN 0.9 ELSE 1.0 END
    AND (dir = 'departure' OR (v.profile <> 'light' AND v.x < 0.85));
  GET DIAGNOSTICS v_scans = ROW_COUNT;
  RETURN jsonb_build_object('term', p_term, 'votes', v_votes, 'scans', v_scans);
END;
$$;

-- ------------------------------------------------------------ notifications
-- What the app keeps (notifications_purge): the last 30 days of subscription
-- notices, the last 7 days of everything else.
--   personal: the subscription notices of the current term made in the last 30 days
--   transport: per line and class day of the last 7 days, departed + arrived +
--              return departing, to the line's current riders
--   company:   two announcements in the last 7 days, to all current students
CREATE OR REPLACE FUNCTION bench.add_notifications(p_seq int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid := (SELECT id FROM bench.company WHERE seq = p_seq);
  v_cname text := (SELECT name FROM public.companies WHERE id = v_company);
  v_admin uuid := (SELECT id FROM public.admins WHERE company_id = v_company ORDER BY id LIMIT 1);
  v_today date := public.cairo_today();
  v_n int; v_r int;
BEGIN
  SET LOCAL session_replication_role = replica;
  CREATE TEMP TABLE b_n (id uuid, audience_kind text, line_id uuid, student uuid, at timestamptz) ON COMMIT DROP;

  -- Personal: payment received + approved (or rejected) for current-term subscriptions created in the window.
  WITH p AS (
    SELECT s.student_id, s.id, s.status, s.created_at, k.key, s.created_at + k.off AS at
    FROM public.subscriptions s
    CROSS JOIN LATERAL (VALUES ('subscription.payment_received', interval '1 day'), ('subscription.approved', interval '3 days'),
                               ('subscription.rejected', interval '2 days')) k(key, off)
    WHERE s.company_id = v_company AND s.created_at >= v_today - 29
      AND (k.key = 'subscription.payment_received' AND s.status <> 'pending_payment'
        OR k.key = 'subscription.approved' AND s.status = 'active'
        OR k.key = 'subscription.rejected' AND EXISTS (SELECT 1 FROM public.receipts r WHERE r.subscription_id = s.id AND r.status = 'rejected'))
  ), ins AS (
    INSERT INTO public.notifications (company_id, sender_role, sender_name, audience, title, body, type, category, data,
                                      status, sent_at, created_at, audience_spec, idempotency_key)
    SELECT v_company, 'system', v_cname, 'إشعار شخصي', t.title_ar, replace(t.body_ar, '{reason}', 'الصورة غير واضحة'), t.key,
           t.category, jsonb_build_object('route', t.route, 'subscription_id', p.id), 'sent', p.at, p.at,
           jsonb_build_object('kind', 'user', 'user_id', p.student_id, 'label', 'إشعار شخصي'), p.key || ':' || p.id
    FROM p JOIN public.notification_templates t ON t.key = p.key
    RETURNING id, (audience_spec->>'user_id')::uuid AS student, created_at
  )
  INSERT INTO b_n SELECT id, 'user', NULL, student, created_at FROM ins;

  -- Transport, per line and class day of the last week.
  WITH ev AS (
    SELECT l.id AS line_id, d::date AS day, k.key, d::date + k.at AS at
    FROM public.lines l
    CROSS JOIN generate_series(v_today - 6, v_today, interval '1 day') d
    CROSS JOIN (VALUES ('transport.departed', interval '6 hours'), ('transport.arrived', interval '8 hours'),
                       ('transport.return_departing', interval '15 hours')) k(key, at)
    WHERE l.company_id = v_company AND extract(dow FROM d) IN (0, 1, 2, 3, 4)
  ), ins AS (
    INSERT INTO public.notifications (company_id, sender_id, sender_role, sender_name, line_id, ride_date, audience, title, body,
                                      type, category, data, status, sent_at, created_at, audience_spec)
    SELECT v_company, sl.supervisor_id, 'supervisor', 'المشرف', ev.line_id, ev.day, 'ركاب الخط', t.title_ar, t.body_ar, t.key,
           t.category, jsonb_build_object('route', t.route), 'sent', ev.at, ev.at,
           jsonb_build_object('kind', 'line', 'line_id', ev.line_id)
    FROM ev JOIN public.notification_templates t ON t.key = ev.key
    JOIN LATERAL (SELECT supervisor_id FROM public.supervisor_lines WHERE line_id = ev.line_id LIMIT 1) sl ON true
    RETURNING id, line_id, created_at
  )
  INSERT INTO b_n SELECT id, 'line', line_id, NULL, created_at FROM ins;

  -- Company announcements.
  WITH ins AS (
    INSERT INTO public.notifications (company_id, sender_id, sender_role, sender_name, audience, title, body, type, category,
                                      status, sent_at, created_at, audience_spec)
    SELECT v_company, v_admin, 'admin', 'الإدارة', 'كل الطلاب', 'تنبيه من الإدارة', 'نص إعلان الإدارة رقم ' || g || ' لكل الطلاب.',
           'announcement.admin', 'announcement', 'sent', now() - g * interval '3 days', now() - g * interval '3 days',
           '{"kind": "company"}'::jsonb
    FROM generate_series(1, 2) g
    RETURNING id, created_at
  )
  INSERT INTO b_n SELECT id, 'company', NULL, NULL, created_at FROM ins;
  INSERT INTO public.notification_audit (company_id, actor_id, actor_role, action, notification_id)
  SELECT v_company, v_admin, 'admin', 'sent', id FROM b_n WHERE audience_kind = 'company';
  SELECT count(*) INTO v_n FROM b_n;

  -- Recipients: as notification_deliver() writes them.
  INSERT INTO public.notification_recipients (notification_id, user_id, is_student, read_at, opened_at)
  SELECT n.id, x.student_id, true,
         CASE WHEN bench.h(n.id::text || x.student_id) < 0.7 THEN n.at + interval '20 minutes' END,
         CASE WHEN bench.h(n.id::text || x.student_id) < 0.25 THEN n.at + interval '25 minutes' END
  FROM b_n n
  CROSS JOIN LATERAL (
    SELECT n.student AS student_id WHERE n.audience_kind = 'user'
    UNION ALL
    SELECT s.student_id FROM public.subscriptions s
    WHERE n.audience_kind IN ('line', 'company') AND s.company_id = v_company AND s.status = 'active'
      AND (n.audience_kind = 'company' OR s.line_id = n.line_id)
  ) x;
  GET DIAGNOSTICS v_r = ROW_COUNT;
  RETURN jsonb_build_object('notifications', v_n, 'recipients', v_r);
END;
$$;

-- ------------------------------------------------------------------ checks
-- Foreign keys of everything loaded with triggers off (should all be 0).
CREATE OR REPLACE FUNCTION bench.check() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'students_without_login', (SELECT count(*) FROM public.students s WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.id)),
    'supervisors_without_login', (SELECT count(*) FROM public.supervisors s WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.id)),
    'admins_without_login', (SELECT count(*) FROM public.admins a WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.id)),
    'subs_bad_refs', (SELECT count(*) FROM public.subscriptions s WHERE NOT EXISTS (SELECT 1 FROM public.students x WHERE x.id = s.student_id)
                        OR NOT EXISTS (SELECT 1 FROM public.stations x WHERE x.id = s.station_id)
                        OR NOT EXISTS (SELECT 1 FROM public.line_trips x WHERE x.id = s.departure_trip_id)),
    'receipts_orphan', (SELECT count(*) FROM public.receipts r WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.id = r.subscription_id)),
    'votes_orphan', (SELECT count(*) FROM public.daily_ride_status v WHERE NOT EXISTS (SELECT 1 FROM public.students s WHERE s.id = v.student_id)),
    'scans_orphan', (SELECT count(*) FROM public.supervisor_scan_events e WHERE NOT EXISTS (SELECT 1 FROM public.students s WHERE s.id = e.student_id)),
    'recipients_without_login', (SELECT count(*) FROM public.notification_recipients r WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = r.user_id)),
    'devices_without_login', (SELECT count(*) FROM public.push_devices d WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = d.user_id)),
    'stops_bad', (SELECT count(*) FROM public.line_trip_stops t WHERE NOT EXISTS (SELECT 1 FROM public.line_trips x WHERE x.id = t.trip_id)))
$$;

-- ----------------------------------------------------------------- measure
CREATE OR REPLACE FUNCTION bench.sizes() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'db', pg_database_size(current_database()),
    'schemas', (SELECT jsonb_object_agg(nspname, sz) FROM (SELECT n.nspname, sum(pg_total_relation_size(c.oid)) sz
                FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r', 'p', 'm') GROUP BY 1) x),
    'tables', (SELECT jsonb_object_agg(n.nspname || '.' || c.relname, jsonb_build_array(
                 (SELECT n_live_tup FROM pg_stat_all_tables st WHERE st.relid = c.oid), pg_relation_size(c.oid),
                 pg_indexes_size(c.oid), COALESCE(pg_total_relation_size(c.reltoastrelid), 0)))
               FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE c.relkind = 'r' AND n.nspname IN ('public', 'auth', 'realtime', 'storage')
                 AND pg_total_relation_size(c.oid) > 16384),
    'rows', jsonb_build_object(
      'companies', (SELECT count(*) FROM public.companies), 'students', (SELECT count(*) FROM public.students),
      'supervisors', (SELECT count(*) FROM public.supervisors), 'admins', (SELECT count(*) FROM public.admins),
      'lines', (SELECT count(*) FROM public.lines), 'stations', (SELECT count(*) FROM public.stations),
      'trips', (SELECT count(*) FROM public.line_trips), 'auth_users', (SELECT count(*) FROM auth.users),
      'subscriptions', (SELECT count(*) FROM public.subscriptions), 'receipts', (SELECT count(*) FROM public.receipts),
      'subscription_receipts', (SELECT count(*) FROM public.subscription_receipts),
      'votes', (SELECT count(*) FROM public.daily_ride_status), 'scans', (SELECT count(*) FROM public.supervisor_scan_events),
      'notifications', (SELECT count(*) FROM public.notifications),
      'recipients', (SELECT count(*) FROM public.notification_recipients),
      'push_devices', (SELECT count(*) FROM public.push_devices), 'wallet_passes', (SELECT count(*) FROM public.wallet_passes)))
$$;

CREATE OR REPLACE FUNCTION bench.checkpoint(p_label text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb := bench.sizes();
BEGIN
  INSERT INTO bench.checkpoint (label, companies, active_per_term, sizes)
  VALUES (p_label, (SELECT count(*) FROM bench.company), (SELECT sum(k) FROM bench.company), v)
  ON CONFLICT (label) DO UPDATE SET at = now(), companies = EXCLUDED.companies,
    active_per_term = EXCLUDED.active_per_term, sizes = EXCLUDED.sizes;
  RETURN jsonb_build_object('db', v->'db', 'rows', v->'rows');
END;
$$;

-- --------------------------------------------------------------- timing
-- Runs a statement p_n times as a signed-in user (RLS on, role authenticated) and
-- returns the median / p95 / max in ms and the size of the last answer in bytes.
CREATE OR REPLACE FUNCTION bench.timeit(p_user uuid, p_sql text, p_n int DEFAULT 30) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  t0 timestamptz; ms double precision[] := '{}'; v_bytes int; v_out text;
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  FOR i IN 1..p_n LOOP
    t0 := clock_timestamp();
    EXECUTE 'SELECT (' || p_sql || ')::text' INTO v_out;
    ms := ms || (extract(epoch FROM clock_timestamp() - t0) * 1000);
  END LOOP;
  EXECUTE 'RESET ROLE';
  v_bytes := octet_length(COALESCE(v_out, ''));
  RETURN jsonb_build_object(
    'median_ms', round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x) FROM unnest(ms) x)::numeric, 2),
    'p95_ms', round((SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY x) FROM unnest(ms) x)::numeric, 2),
    'max_ms', round((SELECT max(x) FROM unnest(ms) x)::numeric, 2), 'bytes', v_bytes, 'runs', p_n);
END;
$$;
