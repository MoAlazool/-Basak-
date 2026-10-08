-- Subscription options: the sale rule, prices per line, the student catalog,
-- company names for sign-up and the receipt that never changes. Everything is
-- built in ONE transaction that is rolled back. Run against a local stack only:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/local/tenancy/subscription_options.sql
\set QUIET on
\pset format unaligned
\pset tuples_only on
BEGIN;
SET LOCAL client_min_messages = warning;

CREATE TEMP TABLE t_results (n serial, step text, ok boolean, detail text) ON COMMIT DROP;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
GRANT ALL ON t_results, t_ids TO authenticated, anon;
GRANT USAGE ON SEQUENCE t_results_n_seq TO authenticated, anon;

CREATE FUNCTION pg_temp.id(p text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM t_ids WHERE k = p $$;
CREATE FUNCTION pg_temp.act(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(p), 'role', 'authenticated')::text, true)
$$;
CREATE FUNCTION pg_temp.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO t_results (step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail)
$$;
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
CREATE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END $$;
-- "first:ok second:advance_off ..." for a line on a day.
CREATE FUNCTION pg_temp.sale(p_line uuid, p_on date) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(string_agg(o.option || ':' || COALESCE(o.reason, 'ok'), ' ' ORDER BY o.option), '')
  FROM public.line_sale_options_for(p_line, p_on, NULL) o
$$;

-- ------------------------------------------------------------------- fixture
DO $$
DECLARE
  k text; v uuid; v_co uuid; v_line uuid; s1 uuid; s2 uuid; s3 uuid; t uuid;
BEGIN
  FOREACH k IN ARRAY ARRAY['super', 'admin_x', 'admin_y', 'st1', 'st2', 'st3', 'st4', 'st5', 'st6'] LOOP
    v := gen_random_uuid();
    INSERT INTO t_ids VALUES (k, v);
    INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    VALUES (v, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'opt_' || k || '@local.test', now(), now());
  END LOOP;
  INSERT INTO public.admins (id, email, full_name, role) VALUES (pg_temp.id('super'), 'opt_super@local.test', 'Opt Super', 'super_admin');
  UPDATE public.app_settings SET annual_subscription_enabled = true WHERE id;

  FOREACH k IN ARRAY ARRAY['u1', 'u2', 'u3'] LOOP
    INSERT INTO public.universities (name) VALUES ('جامعة الخيارات ' || k) RETURNING id INTO v;
    INSERT INTO t_ids VALUES (k, v);
  END LOOP;

  FOREACH k IN ARRAY ARRAY['x', 'y'] LOOP
    INSERT INTO public.companies (name) VALUES ('Opt company ' || k) RETURNING id INTO v_co;
    INSERT INTO t_ids VALUES ('co_' || k, v_co);
    INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id)
    VALUES (pg_temp.id('admin_' || k), 'opt_admin_' || k || '@local.test', 'Opt Admin ' || k, 'company_admin', v_co, pg_temp.id('super'));
    INSERT INTO public.company_payment_methods (company_id, method_type, display_name, wallet_phone)
    VALUES (v_co, 'vodafone_cash', 'Opt cash ' || k, '01012345678') RETURNING id INTO v;
    INSERT INTO t_ids VALUES ('pm_' || k, v);
  END LOOP;

  -- Company x: one line for universities u1 and u2. Station 1 is served by two
  -- departures for everyone and one more for u2 only; station 2 by the first
  -- departure only; station 3 by none. One return leaves the university at 15:00.
  INSERT INTO public.lines (company_id, name, origin_name, price_termly, price_yearly, price_daily)
  VALUES (pg_temp.id('co_x'), 'Opt line', 'Opt origin', 1000, 1800, 50) RETURNING id INTO v_line;
  INSERT INTO t_ids VALUES ('line', v_line);
  INSERT INTO public.line_universities (line_id, university_id) VALUES (v_line, pg_temp.id('u1')), (v_line, pg_temp.id('u2'));
  INSERT INTO public.stations (line_id, name, order_index) VALUES (v_line, 'Opt station 1', 1) RETURNING id INTO s1;
  INSERT INTO public.stations (line_id, name, order_index) VALUES (v_line, 'Opt station 2', 2) RETURNING id INTO s2;
  INSERT INTO public.stations (line_id, name, order_index) VALUES (v_line, 'Opt station 3', 3) RETURNING id INTO s3;
  INSERT INTO t_ids VALUES ('s1', s1), ('s2', s2), ('s3', s3);
  INSERT INTO public.line_trips (line_id, direction, start_time) VALUES (v_line, 'departure', '07:00') RETURNING id INTO t;
  INSERT INTO t_ids VALUES ('dep1', t);
  INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES (t, s1, '07:10'), (t, s2, '07:20');
  INSERT INTO public.line_trips (line_id, direction, start_time) VALUES (v_line, 'departure', '09:00') RETURNING id INTO t;
  INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES (t, s1, '09:10');
  INSERT INTO public.line_trips (line_id, direction, start_time, university_id)
  VALUES (v_line, 'departure', '07:50', pg_temp.id('u2')) RETURNING id INTO t;
  INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES (t, s1, '08:00');
  INSERT INTO public.line_trips (line_id, direction, start_time) VALUES (v_line, 'return', '15:00') RETURNING id INTO t;
  INSERT INTO t_ids VALUES ('ret1', t);

  -- Company y: a line for u1 only, used for receipt numbering.
  INSERT INTO public.lines (company_id, name, price_termly, price_yearly, price_daily)
  VALUES (pg_temp.id('co_y'), 'Opt line y', 700, 1300, 40) RETURNING id INTO v_line;
  INSERT INTO t_ids VALUES ('line_y', v_line);
  INSERT INTO public.line_universities (line_id, university_id) VALUES (v_line, pg_temp.id('u1'));
  INSERT INTO public.stations (line_id, name, order_index) VALUES (v_line, 'Opt station y', 1) RETURNING id INTO s1;
  INSERT INTO t_ids VALUES ('s_y', s1);
  INSERT INTO public.line_trips (line_id, direction, start_time) VALUES (v_line, 'departure', '06:30') RETURNING id INTO t;
  INSERT INTO t_ids VALUES ('dep_y', t);
  INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time) VALUES (t, s1, '06:40');

  CREATE TEMP TABLE t_phones ON COMMIT DROP AS
    SELECT i.id, i.k, '0102222' || lpad(row_number() OVER (ORDER BY i.k)::text, 4, '0') AS phone
    FROM t_ids i WHERE i.k LIKE 'st_';
  UPDATE auth.users u SET email = p.phone || '@busak.app' FROM t_phones p WHERE p.id = u.id;
  INSERT INTO public.students (id, phone, full_name, university, university_id)
  SELECT p.id, p.phone, 'Opt student ' || p.k,
         'جامعة الخيارات ' || CASE p.k WHEN 'st2' THEN 'u2' WHEN 'st3' THEN 'u3' ELSE 'u1' END,
         pg_temp.id(CASE p.k WHEN 'st2' THEN 'u2' WHEN 'st3' THEN 'u3' ELSE 'u1' END)
  FROM t_phones p;
END $$;

-- ------------------------------------------------- the way back has no stations
DO $$
DECLARE v_line uuid := pg_temp.id('line'); v_trip uuid := pg_temp.id('ret1'); v_new uuid; v_sub uuid;
BEGIN
  PERFORM pg_temp.ok('a return trip is listed at every station of the line, at the time it leaves the university',
    (SELECT count(*) = 3 AND bool_and(x.stop_time = '15:00') FROM public.line_trip_stops x WHERE x.trip_id = v_trip),
    (SELECT string_agg(x.stop_time::text, ',') FROM public.line_trip_stops x WHERE x.trip_id = v_trip));
  UPDATE public.line_trip_stops SET stop_time = '17:45' WHERE trip_id = v_trip;
  PERFORM pg_temp.ok('a return trip cannot be given its own station times',
    (SELECT bool_and(x.stop_time = '15:00') FROM public.line_trip_stops x WHERE x.trip_id = v_trip));
  UPDATE public.line_trips SET start_time = '15:15' WHERE id = v_trip;
  PERFORM pg_temp.ok('moving the return time moves it everywhere',
    (SELECT count(*) = 3 AND bool_and(x.stop_time = '15:15') FROM public.line_trip_stops x WHERE x.trip_id = v_trip));
  UPDATE public.line_trips SET start_time = '15:00' WHERE id = v_trip;
  INSERT INTO public.stations (line_id, name, order_index) VALUES (v_line, 'Opt station 4', 4) RETURNING id INTO v_new;
  PERFORM pg_temp.ok('a new station needs nothing done for the way back',
    EXISTS (SELECT 1 FROM public.line_trip_stops x WHERE x.trip_id = v_trip AND x.station_id = v_new AND x.stop_time = '15:00'));
  DELETE FROM public.stations WHERE id = v_new;

  -- Boarding at station 2, which no return stop was ever entered for.
  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, type, status, start_date, end_date, price)
  VALUES (pg_temp.id('st6'), pg_temp.id('line_y'), pg_temp.id('s_y'), pg_temp.id('dep_y'), 'daily', 'active', public.cairo_today(), public.cairo_today(), 40)
  RETURNING id INTO v_sub;
  PERFORM pg_temp.ok('a line with no return trip asks for none',
    (SELECT return_trip_id IS NULL AND return_time IS NULL FROM public.subscriptions WHERE id = v_sub));
  DELETE FROM public.subscriptions WHERE id = v_sub;
  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, type, status, start_date, end_date, price)
  VALUES (pg_temp.id('st2'), v_line, pg_temp.id('s2'), pg_temp.id('dep1'), 'daily', 'active', public.cairo_today(), public.cairo_today(), 50)
  RETURNING id INTO v_sub;
  PERFORM pg_temp.ok('a student at any station gets the return from their university, without choosing a station for it',
    (SELECT return_trip_id = v_trip AND return_time = '15:00' FROM public.subscriptions WHERE id = v_sub),
    (SELECT return_time::text FROM public.subscriptions WHERE id = v_sub));
  DELETE FROM public.subscriptions WHERE id = v_sub;
END $$;

-- ------------------------------------------------------------ prices per line
DO $$
DECLARE v_line uuid := pg_temp.id('line');
BEGIN
  PERFORM pg_temp.ok('a new line gets a price row for each of the four options',
    (SELECT count(*) = 4 FROM public.line_period_prices WHERE line_id = v_line));
  PERFORM pg_temp.ok('first and second start enabled at the term price, both at the yearly price, summer off',
    (SELECT bool_and(CASE option WHEN 'first' THEN is_enabled AND price = 1000 WHEN 'second' THEN is_enabled AND price = 1000
                                 WHEN 'both' THEN is_enabled AND price = 1800 ELSE NOT is_enabled END)
     FROM public.line_period_prices WHERE line_id = v_line));
  PERFORM pg_temp.ok('the price rows carry the line''s company',
    (SELECT bool_and(company_id = pg_temp.id('co_x')) FROM public.line_period_prices WHERE line_id = v_line));

  UPDATE public.line_period_prices SET price = 1200 WHERE line_id = v_line AND option = 'second';
  UPDATE public.line_period_prices SET price = 2000 WHERE line_id = v_line AND option = 'both';
  PERFORM pg_temp.ok('lines.price_termly mirrors the first semester, price_yearly mirrors both',
    (SELECT price_termly = 1000 AND price_yearly = 2000 FROM public.lines WHERE id = v_line));
  UPDATE public.lines SET price_termly = 900 WHERE id = pg_temp.id('line_y');
  PERFORM pg_temp.ok('an older dashboard saving the line price carries it to first and second',
    (SELECT bool_and(price = 900) FROM public.line_period_prices WHERE line_id = pg_temp.id('line_y') AND option IN ('first', 'second')));
END $$;

-- ------------------------------------------------------------- the sale rule
DO $$
DECLARE
  v_line uuid := pg_temp.id('line');
  v_co uuid := pg_temp.id('co_x');
  y int := extract(year FROM public.cairo_today())::int;
  f record; s record; su record; b record;
  in_first date; in_second date; in_summer date; gap date;
BEGIN
  SELECT * INTO f FROM public.company_periods(v_co, y) WHERE period_code = 'first';
  SELECT * INTO s FROM public.company_periods(v_co, y) WHERE period_code = 'second';
  SELECT * INTO su FROM public.company_periods(v_co, y) WHERE period_code = 'summer';
  SELECT * INTO b FROM public.company_periods(v_co, y) WHERE period_code = 'both';
  in_first := f.start_date + 10; in_second := s.start_date + 10; in_summer := su.start_date + 10;
  gap := f.end_date + 1;

  PERFORM pg_temp.ok('"both" runs from the first day of first to the last day of second, without summer',
    b.start_date = f.start_date AND b.end_date = s.end_date AND b.end_date < su.start_date AND b.subscription_type = 'yearly');
  PERFORM pg_temp.ok('there is a day between first and second in this calendar', gap < s.start_date, gap::text);

  PERFORM pg_temp.ok('during first: first, second (in advance) and both are sold; summer is off sale',
    pg_temp.sale(v_line, in_first) = 'both:ok first:ok second:ok summer:company_not_selling', pg_temp.sale(v_line, in_first));

  UPDATE public.companies SET advance_subscription_enabled = false WHERE id = v_co;
  PERFORM pg_temp.ok('advance off: the next period is not sold while one is running',
    pg_temp.sale(v_line, in_first) = 'both:ok first:ok second:advance_off summer:company_not_selling', pg_temp.sale(v_line, in_first));
  PERFORM pg_temp.ok('advance off, between periods: the next period is sold; both is over for this year',
    pg_temp.sale(v_line, gap) LIKE 'both:not_in_season first:not_in_season second:ok %', pg_temp.sale(v_line, gap));
  PERFORM pg_temp.ok('advance off, during second: only second',
    pg_temp.sale(v_line, in_second) = 'both:advance_off first:advance_off second:ok summer:company_not_selling', pg_temp.sale(v_line, in_second));
  UPDATE public.companies SET advance_subscription_enabled = true WHERE id = v_co;

  PERFORM public.set_annual_subscription(false, v_co);
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;

DO $$
DECLARE
  v_line uuid := pg_temp.id('line');
  v_co uuid := pg_temp.id('co_x');
  y int := extract(year FROM public.cairo_today())::int;
  in_first date := (SELECT start_date + 10 FROM public.company_periods(pg_temp.id('co_x'), extract(year FROM public.cairo_today())::int) WHERE period_code = 'first');
  in_summer date := (SELECT start_date + 10 FROM public.company_periods(pg_temp.id('co_x'), extract(year FROM public.cairo_today())::int) WHERE period_code = 'summer');
BEGIN
  UPDATE public.companies SET annual_subscription_enabled = false WHERE id = v_co;
  PERFORM pg_temp.ok('company switches both off: not sold although the line offers it',
    pg_temp.sale(v_line, in_first) LIKE 'both:company_not_selling first:ok %', pg_temp.sale(v_line, in_first));
  UPDATE public.companies SET annual_subscription_enabled = true WHERE id = v_co;

  UPDATE public.company_terms SET is_on_sale = false WHERE company_id = v_co AND code = 'second';
  PERFORM pg_temp.ok('second off sale: second is not sold, and neither is both',
    pg_temp.sale(v_line, in_first) = 'both:company_not_selling first:ok second:company_not_selling summer:company_not_selling', pg_temp.sale(v_line, in_first));
  UPDATE public.company_terms SET is_on_sale = true WHERE company_id = v_co AND code = 'second';

  UPDATE public.line_period_prices SET is_enabled = false WHERE line_id = v_line AND option = 'first';
  UPDATE public.line_period_prices SET price = 0 WHERE line_id = v_line AND option = 'both';
  PERFORM pg_temp.ok('the line narrows the company: a switched-off option and one without a price are not sold',
    pg_temp.sale(v_line, in_first) LIKE 'both:no_price first:line_not_offering second:ok %', pg_temp.sale(v_line, in_first));
  UPDATE public.line_period_prices SET is_enabled = true WHERE line_id = v_line AND option = 'first';
  UPDATE public.line_period_prices SET price = 2000 WHERE line_id = v_line AND option = 'both';

  UPDATE public.line_period_prices SET is_enabled = true, price = 400 WHERE line_id = v_line AND option = 'summer';
  PERFORM pg_temp.ok('a line cannot sell what the company does not: summer stays off',
    pg_temp.sale(v_line, in_summer) LIKE '%summer:company_not_selling', pg_temp.sale(v_line, in_summer));
  UPDATE public.company_terms SET is_on_sale = true WHERE company_id = v_co AND code = 'summer';
  PERFORM pg_temp.ok('summer on for the company and the line: sold in summer as its own option',
    pg_temp.sale(v_line, in_summer) LIKE '%summer:ok', pg_temp.sale(v_line, in_summer));
  PERFORM pg_temp.ok('with summer on sale, both still ends with the second semester',
    (SELECT o.end_date < (SELECT x.start_date FROM public.line_sale_options_for(v_line, in_first, NULL) x WHERE x.option = 'summer')
     FROM public.line_sale_options_for(v_line, in_first, NULL) o WHERE o.option = 'both'));
  UPDATE public.company_terms SET is_on_sale = false WHERE company_id = v_co AND code = 'summer';

  UPDATE public.lines SET is_active = false WHERE id = v_line;
  PERFORM pg_temp.ok('a switched-off line sells nothing',
    pg_temp.sale(v_line, in_first) LIKE 'both:line_inactive first:line_inactive second:line_inactive%', pg_temp.sale(v_line, in_first));
  UPDATE public.lines SET is_active = true WHERE id = v_line;
  UPDATE public.companies SET status = 'suspended' WHERE id = v_co;
  PERFORM pg_temp.ok('a suspended company sells nothing',
    pg_temp.sale(v_line, in_first) LIKE 'both:company_inactive first:company_inactive%', pg_temp.sale(v_line, in_first));
  UPDATE public.companies SET status = 'active' WHERE id = v_co;
END $$;

-- ------------------------------------------- catalog, picker and insert agree
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  v_line uuid := pg_temp.id('line');
  c jsonb; l jsonb; v_before bigint; v_rule text; v_cat text; v_old text; r record;
BEGIN
  PERFORM pg_temp.act('st1');
  SELECT count(*) INTO v_before FROM public.subscriptions;
  c := public.get_subscription_catalog();
  l := c->'companies'->0->'lines'->0;
  PERFORM pg_temp.ok('the catalog names the student''s own university as the destination',
    c->'university'->>'name' = 'جامعة الخيارات u1' AND l->>'university' = 'جامعة الخيارات u1' AND l->>'name' = 'Opt line');
  PERFORM pg_temp.ok('a student sees only companies that serve their university (x and y for u1)',
    (SELECT string_agg(x->>'name', ',' ORDER BY x->>'name') FROM jsonb_array_elements(c->'companies') x
     WHERE x->>'name' LIKE 'Opt company%') = 'Opt company x,Opt company y');

  SELECT string_agg(o.option, ',' ORDER BY o.option) INTO v_rule FROM public.line_sale_options(v_line) o WHERE o.available;
  SELECT string_agg(o->>'option', ',' ORDER BY o->>'option') INTO v_cat FROM jsonb_array_elements(l->'options') o;
  SELECT string_agg(replace(p.period_code, 'annual', 'both'), ',' ORDER BY replace(p.period_code, 'annual', 'both')) INTO v_old
  FROM public.get_purchasable_periods(v_line) p;
  PERFORM pg_temp.ok('the rule, the catalog and the older picker offer the same options',
    v_rule = 'both,first,second' AND v_cat = v_rule AND v_old = v_rule, format('%s | %s | %s', v_rule, v_cat, v_old));
  PERFORM pg_temp.ok('the older picker still calls both "annual"',
    EXISTS (SELECT 1 FROM public.get_purchasable_periods(v_line) p WHERE p.period_code = 'annual' AND p.subscription_type = 'yearly'));
  PERFORM pg_temp.ok('each option carries its own price, and the card shows the lowest',
    (SELECT bool_and((o->>'price')::numeric = CASE o->>'option' WHEN 'first' THEN 1000 WHEN 'second' THEN 1200 ELSE 2000 END)
     FROM jsonb_array_elements(l->'options') o) AND (l->>'from_price')::numeric = 1000, (l->'options')::text);

  -- Times belong to trips, not to stations.
  PERFORM pg_temp.ok('station 1 lists one departure time per trip serving this university, in order',
    (SELECT jsonb_agg(d->>'time') FROM jsonb_array_elements(l->'stations'->0->'departures') d) = '["07:10:00", "09:10:00"]'::jsonb,
    (l->'stations'->0->'departures')::text);
  PERFORM pg_temp.ok('the way back is the time the bus leaves the university, on the line and not on a station',
    (l->'returns'->0->>'time') = '15:00:00' AND jsonb_array_length(l->'returns') = 1
    AND NOT (l->'stations'->0 ? 'returns'), (l->'returns')::text);
  PERFORM pg_temp.ok('station 2 is served by one departure',
    jsonb_array_length(l->'stations'->1->'departures') = 1 AND l->'stations'->1->'departures'->0->>'time' = '07:20:00');
  PERFORM pg_temp.ok('a station no departure stops at is not offered',
    jsonb_array_length(l->'stations') = 2);
  PERFORM pg_temp.ok('the card gives the first departure and the last return of the line',
    l->>'first_departure' = '07:00:00' AND l->>'last_return' = '15:00:00');

  PERFORM pg_temp.act('st2');
  l := public.get_subscription_catalog()->'companies'->0->'lines'->0;
  PERFORM pg_temp.ok('a student of another university gets that university''s extra trip at the same station',
    (SELECT jsonb_agg(d->>'time') FROM jsonb_array_elements(l->'stations'->0->'departures') d) = '["07:10:00", "08:00:00", "09:10:00"]'::jsonb
    AND l->>'university' = 'جامعة الخيارات u2', (l->'stations'->0->'departures')::text);
  PERFORM pg_temp.act('st3');
  PERFORM pg_temp.ok('a student whose university no company serves gets no companies',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.get_subscription_catalog()->'companies') x
                WHERE x->>'name' LIKE 'Opt company%'));

  PERFORM pg_temp.act('st1');
  PERFORM pg_temp.ok('browsing the catalog and the options writes nothing',
    (SELECT count(*) FROM public.subscriptions) = v_before);

  -- The insert takes the option and its price from the same rule.
  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, return_trip_id, type, price, period_code, academic_year)
  SELECT auth.uid(), v_line, pg_temp.id('s1'), pg_temp.id('dep1'), pg_temp.id('ret1'), 'termly', 1, 'second', o.academic_year
  FROM public.line_sale_options(v_line) o WHERE o.option = 'second';
  SELECT * INTO r FROM public.subscriptions WHERE student_id = auth.uid();
  PERFORM pg_temp.ok('second semester in advance: charged the second-semester price, waiting for payment',
    r.price = 1200 AND r.period_code = 'second' AND r.status = 'pending_payment' AND r.departure_time = '07:10', format('%s %s %s', r.price, r.period_code, r.status));
  PERFORM pg_temp.ok('the saved return is when the bus leaves the university, whatever was sent',
    r.return_time = '15:00' AND r.return_trip_id = pg_temp.id('ret1'), r.return_time::text);
  PERFORM pg_temp.denied('the student cannot delete the request once it exists',
    'DELETE FROM public.subscriptions WHERE student_id = auth.uid()');
  PERFORM pg_temp.denied('the student cannot change its line, station or period',
    format('UPDATE public.subscriptions SET period_code = ''first'', station_id = %L WHERE student_id = auth.uid()', pg_temp.id('s2')));
  PERFORM pg_temp.ok('an option the student already holds, and both, are no longer offered to them',
    (SELECT string_agg(o.option || ':' || COALESCE(o.reason, 'ok'), ' ' ORDER BY o.option) FROM public.line_sale_options(v_line) o)
      LIKE 'both:overlap first:ok second:overlap%');

  PERFORM pg_temp.act('st4');
  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, return_trip_id, type, price)
  VALUES (auth.uid(), v_line, pg_temp.id('s1'), pg_temp.id('dep1'), pg_temp.id('ret1'), 'yearly', 1);
  SELECT * INTO r FROM public.subscriptions WHERE student_id = auth.uid();
  PERFORM pg_temp.ok('older app, type yearly without a period: stored as both at the both price',
    r.period_code = 'both' AND r.type = 'yearly' AND r.price = 2000, format('%s %s %s', r.period_code, r.type, r.price));

  PERFORM pg_temp.act('st5');
  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, return_trip_id, type, price, period_code, academic_year)
  SELECT auth.uid(), v_line, pg_temp.id('s1'), pg_temp.id('dep1'), pg_temp.id('ret1'), 'yearly', 1, 'annual', o.academic_year
  FROM public.line_sale_options(v_line) o WHERE o.option = 'both';
  SELECT * INTO r FROM public.subscriptions WHERE student_id = auth.uid();
  PERFORM pg_temp.ok('older app sending "annual": stored as both',
    r.period_code = 'both' AND r.price = 2000
    AND (SELECT public.period_label(x) FROM public.subscriptions x WHERE x.id = r.id) LIKE 'الفصلان معاً%');
END $$;

RESET ROLE;
UPDATE public.companies SET advance_subscription_enabled = false WHERE id = pg_temp.id('co_x');
UPDATE public.line_period_prices SET is_enabled = false WHERE line_id = pg_temp.id('line') AND option = 'both';
SET LOCAL ROLE authenticated;
DO $$
DECLARE v_line uuid := pg_temp.id('line'); v_year int;
BEGIN
  PERFORM pg_temp.act('st6');
  SELECT o.academic_year INTO v_year FROM public.line_sale_options(v_line) o WHERE o.option = 'second';
  PERFORM pg_temp.ok('advance off: buying the next semester is refused by the database with a clear reason',
    pg_temp.err(format($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, return_trip_id, type, price, period_code, academic_year)
      VALUES (auth.uid(), %L, %L, %L, %L, 'termly', 1, 'second', %s)$q$, v_line, pg_temp.id('s1'), pg_temp.id('dep1'), pg_temp.id('ret1'), v_year))
      LIKE '%الاشتراك المسبق%');
  PERFORM pg_temp.ok('an option the line switched off is refused by the database',
    pg_temp.err(format($q$INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, return_trip_id, type, price, period_code, academic_year)
      VALUES (auth.uid(), %L, %L, %L, %L, 'yearly', 1, 'both', %s)$q$, v_line, pg_temp.id('s1'), pg_temp.id('dep1'), pg_temp.id('ret1'), v_year))
      LIKE '%غير متاحة للاشتراك على هذا الخط%');
  PERFORM pg_temp.ok('the catalog shows that student exactly what the database accepts (first only)',
    (SELECT string_agg(o->>'option', ',') FROM jsonb_array_elements(public.get_subscription_catalog()->'companies'->0->'lines'->0->'options') o) = 'first');

  -- Who may change prices and sale settings.
  PERFORM pg_temp.denied('a student cannot change a line''s prices',
    format('UPDATE public.line_period_prices SET price = 1 WHERE line_id = %L', v_line));
  PERFORM pg_temp.ok('a student cannot read the price table directly',
    (SELECT count(*) = 0 FROM public.line_period_prices));
  PERFORM pg_temp.denied('a student cannot change sale settings',
    format('SELECT public.set_company_sale_settings(%L, true)', pg_temp.id('co_x')));
  PERFORM pg_temp.act('admin_y');
  PERFORM pg_temp.denied('another company''s admin cannot change this line''s prices',
    format('UPDATE public.line_period_prices SET price = 1 WHERE line_id = %L', v_line));
  PERFORM pg_temp.denied('another company''s admin cannot change this company''s sale settings',
    format('SELECT public.set_company_sale_settings(%L, true)', pg_temp.id('co_x')));
  PERFORM pg_temp.ok('another company''s admin reads none of this company''s prices',
    (SELECT count(*) = 0 FROM public.line_period_prices WHERE line_id = v_line));

  PERFORM pg_temp.act('admin_x');
  PERFORM public.set_company_sale_settings(pg_temp.id('co_x'), true, '{"summer": true}');
  UPDATE public.line_period_prices SET is_enabled = true WHERE line_id = v_line AND option = 'both';
  PERFORM pg_temp.ok('the company''s own admin saves sale settings and prices',
    (SELECT advance_subscription_enabled FROM public.companies WHERE id = pg_temp.id('co_x'))
    AND (SELECT is_on_sale FROM public.company_terms WHERE company_id = pg_temp.id('co_x') AND code = 'summer')
    AND (SELECT is_enabled FROM public.line_period_prices WHERE line_id = v_line AND option = 'both'));
  PERFORM pg_temp.ok('the settings preview explains every option of every line',
    (SELECT jsonb_array_length(p->'options') >= 4 AND p->>'line' = 'Opt line'
     FROM jsonb_array_elements(public.get_subscription_settings(pg_temp.id('co_x'))->'sale_preview') p LIMIT 1)
    AND public.get_subscription_settings(pg_temp.id('co_x'))->>'advance_enabled' = 'true');
  PERFORM pg_temp.ok('reports find a both subscription under its new name and under "annual"',
    jsonb_array_length(public.admin_subscription_report('{"period": "both"}')->'rows') = 2
    AND jsonb_array_length(public.admin_subscription_report('{"period": "annual"}')->'rows') = 2);
END $$;

-- ------------------------------------------- company names before an account
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);
DO $$
DECLARE j jsonb;
BEGIN
  -- Lines of other local demo companies that serve every university are left out.
  SELECT jsonb_agg(x) INTO j FROM jsonb_array_elements(public.companies_for_university(pg_temp.id('u1'))) x
  WHERE x->>'name' LIKE 'Opt company%';
  PERFORM pg_temp.ok('without an account: the companies serving a university, by name',
    (SELECT string_agg(x->>'name', ',' ORDER BY x->>'name') FROM jsonb_array_elements(j) x) = 'Opt company x,Opt company y', j::text);
  PERFORM pg_temp.ok('nothing but a name and a line count is given away',
    (SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k) = ARRAY['lines', 'name']) FROM jsonb_array_elements(j) x));
  PERFORM pg_temp.ok('a university only one company serves lists only that company',
    (SELECT jsonb_agg(x) FROM jsonb_array_elements(public.companies_for_university(pg_temp.id('u2'))) x
     WHERE x->>'name' LIKE 'Opt company%') = '[{"name": "Opt company x", "lines": 1}]'::jsonb);
  PERFORM pg_temp.ok('a university nobody serves gets an empty list',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.companies_for_university(pg_temp.id('u3'))) x
                WHERE x->>'name' LIKE 'Opt company%')
    AND public.companies_for_university(NULL) = '[]'::jsonb);
  PERFORM pg_temp.denied('without an account the sale options cannot be read',
    format('SELECT * FROM public.line_sale_options(%L)', pg_temp.id('line')));
  PERFORM pg_temp.denied('without an account the catalog cannot be read', 'SELECT public.get_subscription_catalog()');
END $$;

-- -------------------------------------------------- the receipt never changes
RESET ROLE;
DO $$
DECLARE v_sub uuid; v_sub_y uuid; v_before jsonb; r record;
BEGIN
  -- st1 pays the second semester by a transfer the admin approves.
  SELECT id INTO v_sub FROM public.subscriptions WHERE student_id = pg_temp.id('st1');
  INSERT INTO t_ids VALUES ('sub1', v_sub);
  INSERT INTO public.receipts (subscription_id, image_url, payment_method_id)
  VALUES (v_sub, pg_temp.id('st1') || '/' || v_sub || '_1.jpg', pg_temp.id('pm_x'));
  PERFORM pg_temp.ok('no receipt before approval',
    NOT EXISTS (SELECT 1 FROM public.subscription_receipts WHERE subscription_id = v_sub));
  UPDATE public.receipts SET status = 'approved' WHERE subscription_id = v_sub;
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT * INTO r FROM public.subscription_receipts WHERE subscription_id = v_sub;
  PERFORM pg_temp.ok('approval issues receipt no. 1 with the facts of that moment',
    r.receipt_no = 1 AND r.amount = 1200 AND r.payment_method = 'Opt cash x' AND r.line_name = 'Opt line'
    AND r.station_name = 'Opt station 1' AND r.company_name = 'Opt company x' AND r.university_name = 'جامعة الخيارات u1'
    AND r.option = 'second' AND r.period_label <> '' AND r.start_date IS NOT NULL AND r.approved_at IS NOT NULL
    AND r.student_name = 'Opt student st1', to_jsonb(r)::text);
  SET CONSTRAINTS ALL DEFERRED;

  -- st4 is activated by the administration without a transfer.
  UPDATE public.subscriptions SET status = 'active' WHERE student_id = pg_temp.id('st4');
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT * INTO r FROM public.subscription_receipts WHERE student_id = pg_temp.id('st4');
  PERFORM pg_temp.ok('the next approval of the same company is no. 2; without a transfer the amount is the price',
    r.receipt_no = 2 AND r.amount = 2000 AND r.payment_method IS NULL AND r.option = 'both', to_jsonb(r)::text);
  SET CONSTRAINTS ALL DEFERRED;

  -- Another company numbers its own receipts from 1.
  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, type, status, price, period_code, academic_year)
  SELECT pg_temp.id('st6'), pg_temp.id('line_y'), pg_temp.id('s_y'), pg_temp.id('dep_y'), 'termly', 'active', 900, 'first', o.academic_year
  FROM public.line_sale_options_for(pg_temp.id('line_y'), NULL, NULL) o WHERE o.option = 'first'
  RETURNING id INTO v_sub_y;
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM pg_temp.ok('another company starts its own numbering at 1',
    (SELECT receipt_no = 1 AND company_name = 'Opt company y' FROM public.subscription_receipts WHERE subscription_id = v_sub_y));
  SET CONSTRAINTS ALL DEFERRED;

  INSERT INTO public.subscriptions (student_id, line_id, station_id, departure_trip_id, return_trip_id, type, status, start_date, end_date, price)
  VALUES (pg_temp.id('st2'), pg_temp.id('line'), pg_temp.id('s1'), pg_temp.id('dep1'), pg_temp.id('ret1'), 'daily', 'active',
          public.cairo_today(), public.cairo_today(), 50);
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM pg_temp.ok('a daily cash ride has no receipt',
    NOT EXISTS (SELECT 1 FROM public.subscription_receipts WHERE student_id = pg_temp.id('st2')));
  SET CONSTRAINTS ALL DEFERRED;

  -- Everything it was copied from changes afterwards.
  SELECT to_jsonb(x) INTO v_before FROM public.subscription_receipts x WHERE x.subscription_id = v_sub;
  UPDATE public.lines SET name = 'Renamed line' WHERE id = pg_temp.id('line');
  UPDATE public.stations SET name = 'Renamed station' WHERE id = pg_temp.id('s1');
  UPDATE public.companies SET name = 'Renamed company' WHERE id = pg_temp.id('co_x');
  UPDATE public.universities SET name = 'Renamed university' WHERE id = pg_temp.id('u1');
  UPDATE public.company_payment_methods SET display_name = 'Renamed method' WHERE id = pg_temp.id('pm_x');
  UPDATE public.line_period_prices SET price = 9999 WHERE line_id = pg_temp.id('line');
  UPDATE public.subscriptions SET status = 'pending_payment' WHERE id = v_sub;
  UPDATE public.subscriptions SET status = 'active' WHERE id = v_sub;
  SET CONSTRAINTS ALL IMMEDIATE;
  PERFORM pg_temp.ok('after renaming the line, station, company, university and method, changing prices and re-activating: identical',
    (SELECT to_jsonb(x) = v_before FROM public.subscription_receipts x WHERE x.subscription_id = v_sub)
    AND (SELECT count(*) = 1 FROM public.subscription_receipts WHERE subscription_id = v_sub));
  SET CONSTRAINTS ALL DEFERRED;

  PERFORM pg_temp.ok('the database owner cannot edit a receipt',
    pg_temp.err(format('UPDATE public.subscription_receipts SET amount = 1 WHERE subscription_id = %L', v_sub)) LIKE '%لا يمكن تعديله%');
  PERFORM pg_temp.ok('the database owner cannot delete a receipt',
    pg_temp.err(format('DELETE FROM public.subscription_receipts WHERE subscription_id = %L', v_sub)) LIKE '%لا يمكن تعديله%');
  PERFORM pg_temp.ok('the table cannot be emptied either',
    pg_temp.err('TRUNCATE public.subscription_receipts') LIKE '%لا يمكن تعديله%');
END $$;

SET LOCAL ROLE authenticated;
DO $$
BEGIN
  PERFORM pg_temp.act('st1');
  PERFORM pg_temp.ok('a student reads their own receipt and nobody else''s',
    (SELECT count(*) = 1 AND bool_and(student_id = auth.uid()) FROM public.subscription_receipts));
  PERFORM pg_temp.denied('a student cannot edit their receipt', 'UPDATE public.subscription_receipts SET amount = 1');
  PERFORM pg_temp.denied('a student cannot delete their receipt', 'DELETE FROM public.subscription_receipts');
  PERFORM pg_temp.denied('a student cannot write a receipt',
    format('INSERT INTO public.subscription_receipts (subscription_id, company_id, student_id, receipt_no, company_name, student_name, line_name, period_label, amount, approved_at)
            VALUES (%L, %L, %L, 99, ''x'', ''x'', ''x'', ''x'', 1, now())', gen_random_uuid(), pg_temp.id('co_x'), pg_temp.id('st1')));
  PERFORM pg_temp.act('admin_x');
  PERFORM pg_temp.ok('the company reads its own receipts only',
    (SELECT count(*) = 2 AND bool_and(company_id = pg_temp.id('co_x')) FROM public.subscription_receipts));
  PERFORM pg_temp.denied('the company admin cannot edit a receipt', 'UPDATE public.subscription_receipts SET amount = 1');
  PERFORM pg_temp.denied('the company admin cannot delete a receipt', 'DELETE FROM public.subscription_receipts');
  PERFORM pg_temp.act('admin_y');
  PERFORM pg_temp.ok('another company reads only its own',
    (SELECT count(*) = 1 AND bool_and(company_id = pg_temp.id('co_y')) FROM public.subscription_receipts));
  PERFORM pg_temp.act('super');
  PERFORM pg_temp.denied('the platform admin cannot edit a receipt', 'UPDATE public.subscription_receipts SET amount = 1');
END $$;
RESET ROLE;

-- The student leaves: the company's record stays as issued.
DO $$
DECLARE v_before jsonb;
BEGIN
  SELECT to_jsonb(x) INTO v_before FROM public.subscription_receipts x WHERE x.student_id = pg_temp.id('st4');
  DELETE FROM public.students WHERE id = pg_temp.id('st4');
  PERFORM pg_temp.ok('removing the student account leaves the issued receipt untouched',
    (SELECT to_jsonb(x) = v_before FROM public.subscription_receipts x WHERE x.student_id = pg_temp.id('st4')));
END $$;

SELECT CASE WHEN ok THEN 'ok   ' ELSE 'FAIL ' END || step || COALESCE('  [' || detail || ']', '')
FROM t_results WHERE NOT ok ORDER BY n;
SELECT 'subscription options: ' || count(*) FILTER (WHERE ok) || '/' || count(*) || ' passed' FROM t_results;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM t_results WHERE NOT ok) THEN RAISE EXCEPTION 'subscription options test failed'; END IF;
END $$;
ROLLBACK;
