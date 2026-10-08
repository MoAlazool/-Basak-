-- A realistic-size dataset for measuring, on a LOCAL database only. Everything
-- it adds is marked (companies named 'PERF …', phones 0159…) and removed by
-- dataset_drop.sql. Triggers are off while loading (session_replication_role),
-- so company_id and friends are filled in here.
--   5 companies × 6 lines × 6 stations × 4 trips; 3000 students per company,
--   each with one current subscription (5% awaiting review with a pending
--   receipt) and one finished one with an approved receipt; votes for today;
--   30 days of scans; 300 sent notifications per company.
\set ON_ERROR_STOP 1
BEGIN;
SET LOCAL session_replication_role = replica;

CREATE TEMP TABLE perf_c AS
SELECT gen_random_uuid() AS id, n FROM generate_series(1, 5) n;
INSERT INTO public.companies (id, name) SELECT id, 'PERF شركة ' || n FROM perf_c;

CREATE TEMP TABLE perf_u AS SELECT id, row_number() OVER (ORDER BY id) AS n FROM (SELECT id FROM public.universities LIMIT 3) u;

CREATE TEMP TABLE perf_l AS
SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn, g.n FROM perf_c c, generate_series(1, 6) g(n);
INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily)
SELECT id, company_id, 'PERF خط ' || cn || '-' || n, 3000, 5500, 40 FROM perf_l;
INSERT INTO public.line_universities (line_id, university_id, company_id)
SELECT l.id, u.id, l.company_id FROM perf_l l, perf_u u;
INSERT INTO public.line_period_prices (line_id, company_id, option, price)
SELECT l.id, l.company_id, p, 3000 FROM perf_l l, unnest(ARRAY['first', 'second', 'both']) p
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE perf_s AS
SELECT gen_random_uuid() AS id, l.id AS line_id, l.company_id, g.n FROM perf_l l, generate_series(1, 6) g(n);
INSERT INTO public.stations (id, line_id, name, order_index, company_id)
SELECT id, line_id, 'PERF محطة ' || n, n, company_id FROM perf_s;

CREATE TEMP TABLE perf_t AS
SELECT gen_random_uuid() AS id, l.id AS line_id, l.company_id, g.n,
       CASE WHEN g.n <= 3 THEN 'departure' ELSE 'return' END AS direction,
       (SELECT u.id FROM perf_u u WHERE u.n = ((g.n - 1) % 3) + 1) AS university_id
FROM perf_l l, generate_series(1, 4) g(n);
INSERT INTO public.line_trips (id, line_id, direction, start_time, university_id, company_id)
SELECT id, line_id, direction, CASE WHEN direction = 'departure' THEN time '06:00' + n * interval '1 hour' ELSE time '15:00' END,
       university_id, company_id FROM perf_t;
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time, company_id)
SELECT t.id, s.id, CASE WHEN t.direction = 'departure' THEN time '06:00' + t.n * interval '1 hour' + s.n * interval '5 minutes' ELSE time '15:00' END,
       t.company_id
FROM perf_t t JOIN perf_s s ON s.line_id = t.line_id;

-- People.
CREATE TEMP TABLE perf_st AS
SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn, g.n,
       (SELECT l.id FROM perf_l l WHERE l.company_id = c.id AND l.n = (g.n % 6) + 1) AS line_id,
       (SELECT u.id FROM perf_u u WHERE u.n = (g.n % 3) + 1) AS university_id
FROM perf_c c, generate_series(1, 3000) g(n);
INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
SELECT id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'perf-' || id || '@local.test', now(), now(), '', '', '', ''
FROM perf_st;
INSERT INTO public.students (id, phone, full_name, university, university_id)
SELECT id, '0159' || cn || lpad(n::text, 6, '0'), 'PERF طالب ' || cn || '-' || n,
       (SELECT name FROM public.universities u WHERE u.id = university_id), university_id FROM perf_st;
INSERT INTO public.company_students (company_id, student_id) SELECT company_id, id FROM perf_st;

CREATE TEMP TABLE perf_sup AS
SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn FROM perf_c c;
CREATE TEMP TABLE perf_adm AS
SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn FROM perf_c c;
INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
SELECT id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'perf-' || id || '@local.test', now(), now(), '', '', '', ''
FROM (SELECT id FROM perf_sup UNION ALL SELECT id FROM perf_adm) x;
INSERT INTO public.supervisors (id, phone, full_name, company_id)
SELECT id, '01590000' || lpad(cn::text, 3, '0'), 'PERF مشرف ' || cn, company_id FROM perf_sup;
INSERT INTO public.supervisor_lines (supervisor_id, line_id, company_id)
SELECT s.id, l.id, l.company_id FROM perf_sup s JOIN perf_l l ON l.company_id = s.company_id AND l.n <= 3;
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id)
SELECT id, 'perf-admin-' || cn || '@local.test', 'PERF مدير ' || cn, 'company_admin', company_id,
       (SELECT a.id FROM public.admins a WHERE a.role = 'super_admin' LIMIT 1) FROM perf_adm;

-- Subscriptions: a finished one (first term of last year) and a current one.
CREATE TEMP TABLE perf_sub AS
SELECT gen_random_uuid() AS id, st.id AS student_id, st.company_id, st.line_id, st.n, st.university_id, k AS cur,
       (SELECT s.id FROM perf_s s WHERE s.line_id = st.line_id AND s.n = (st.n % 6) + 1) AS station_id,
       (SELECT t.id FROM perf_t t WHERE t.line_id = st.line_id AND t.direction = 'departure' AND t.university_id = st.university_id) AS dep,
       (SELECT t.id FROM perf_t t WHERE t.line_id = st.line_id AND t.direction = 'return') AS ret
FROM perf_st st, (VALUES (false), (true)) v(k);
INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price,
                                  period_code, academic_year, paid_at, departure_trip_id, return_trip_id, company_id, created_at)
SELECT id, student_id, line_id, station_id, 'termly',
       CASE WHEN NOT cur THEN 'expired' WHEN n % 20 = 0 THEN 'pending_review' ELSE 'active' END,
       CASE WHEN cur THEN public.cairo_today() - 20 ELSE public.cairo_today() - 300 END,
       CASE WHEN cur THEN public.cairo_today() + 100 ELSE public.cairo_today() - 200 END,
       3000, CASE WHEN cur THEN 'first' ELSE 'second' END,
       CASE WHEN cur THEN 2026 ELSE 2025 END,
       CASE WHEN cur AND n % 20 = 0 THEN NULL WHEN cur THEN now() - interval '20 days' ELSE now() - interval '300 days' END,
       dep, ret, company_id, CASE WHEN cur THEN now() - interval '21 days' ELSE now() - interval '301 days' END
FROM perf_sub;
INSERT INTO public.receipts (subscription_id, image_url, status, attempt_number, reviewed_at, amount, company_id, created_at)
SELECT id, student_id || '/' || id || '_1700000000000.jpg',
       CASE WHEN cur AND n % 20 = 0 THEN 'pending' ELSE 'approved' END, 1,
       CASE WHEN cur AND n % 20 = 0 THEN NULL ELSE now() - interval '20 days' END, 3000, company_id,
       now() - (n % 500) * interval '1 minute'
FROM perf_sub;
INSERT INTO storage.objects (bucket_id, name, owner, metadata)
SELECT 'receipts', r.image_url, s.student_id, '{"size": 250000, "mimetype": "image/jpeg"}'::jsonb
FROM public.receipts r JOIN perf_sub s ON s.id = r.subscription_id WHERE r.status = 'pending';

-- Today's votes, and a month of scans.
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, is_returning, company_id, subscription_id)
SELECT student_id, public.cairo_today() + d, true, n % 2 = 0, company_id, id
FROM perf_sub, generate_series(0, 1) d WHERE cur AND n % 20 <> 0 AND n % 3 <> 0;
INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, station_id, trip_id, ride_date,
                                           direction, result, scanned_at, company_id)
SELECT (SELECT s.id FROM perf_sup s WHERE s.company_id = sub.company_id), sub.student_id, sub.id, sub.line_id, sub.station_id,
       sub.dep, public.cairo_today() - d, 'departure', 'checked_in', now() - d * interval '1 day', sub.company_id
FROM perf_sub sub, generate_series(1, 30) d WHERE sub.cur AND sub.n % 20 <> 0 AND (sub.n + d) % 4 = 0;

-- Notifications: 300 per company over two months, each to one line's students.
CREATE TEMP TABLE perf_n AS
SELECT gen_random_uuid() AS id, l.company_id, l.id AS line_id, g.n FROM perf_l l, generate_series(1, 50) g(n);
INSERT INTO public.notifications (id, company_id, sender_role, sender_name, line_id, audience, title, body, type, category,
                                  status, sent_at, created_at, audience_spec)
SELECT id, company_id, 'admin', 'PERF', line_id, 'PERF', 'PERF إشعار ' || n, 'نص الإشعار.', 'announcement.admin', 'announcement',
       'sent', now() - n * interval '1 day', now() - n * interval '1 day', jsonb_build_object('kind', 'line', 'line_id', line_id)
FROM perf_n;
INSERT INTO public.notification_recipients (notification_id, user_id, is_student, read_at)
SELECT pn.id, st.id, true, CASE WHEN (st.n + pn.n) % 3 = 0 THEN now() END
FROM perf_n pn JOIN perf_st st ON st.line_id = pn.line_id;
COMMIT;
ANALYZE;
SELECT 'students ' || count(*) FROM public.students WHERE phone LIKE '0159%'
UNION ALL SELECT 'subscriptions ' || count(*) FROM public.subscriptions
UNION ALL SELECT 'receipts ' || count(*) FROM public.receipts
UNION ALL SELECT 'scans ' || count(*) FROM public.supervisor_scan_events
UNION ALL SELECT 'notification recipients ' || count(*) FROM public.notification_recipients;
