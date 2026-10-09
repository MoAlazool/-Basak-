-- A realistic large dataset for measuring, on a LOCAL database only (never the
-- live project). Everything it adds is marked (companies named 'PERF …', phones
-- 0159…) and removed by dataset_drop.sql. Triggers are off while loading
-- (session_replication_role), so company_id and friends are filled in here.
--
--   psql "$DB" -v students=100000 -f dataset.sql        (default 100000)
--
-- Shape (for 100,000 students):
--   10 companies of very different sizes (the biggest has about a third of the
--   students, the smallest one in a hundred); every active university; 4–15
--   lines a company (about 150 students a line), 5–10 stations a line; three academic years
--   of subscriptions (finished terms with approved receipts, a current term that
--   is active, awaiting payment, under review, rejected, or absent); votes for
--   today and tomorrow; 30 days of scans; 60 days of notifications.
\set ON_ERROR_STOP 1
\if :{?students}
\else
\set students 100000
\endif
BEGIN;
SET LOCAL session_replication_role = replica;
SELECT setseed(0.42);

-- Companies and their share of the students.
CREATE TEMP TABLE perf_c AS
SELECT gen_random_uuid() AS id, n, w,
       sum(w) OVER (ORDER BY n) - w AS lo, sum(w) OVER (ORDER BY n) AS hi
FROM (VALUES (1, 0.33), (2, 0.20), (3, 0.14), (4, 0.10), (5, 0.08), (6, 0.06), (7, 0.04), (8, 0.02), (9, 0.02), (10, 0.01)) v(n, w);
INSERT INTO public.companies (id, name) SELECT id, 'PERF شركة ' || n FROM perf_c;

CREATE TEMP TABLE perf_u AS
SELECT id, name, row_number() OVER (ORDER BY name) AS n, count(*) OVER () AS total
FROM public.universities WHERE is_active;

CREATE TEMP TABLE perf_l AS
SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn, g.n,
       count(*) OVER (PARTITION BY c.id) AS lines_in_company
-- About 150 students a line (a few buses), and never fewer than four lines.
FROM perf_c c CROSS JOIN LATERAL generate_series(1, GREATEST(ceil(c.w * :students / 150.0)::int, 4)) g(n);
INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily)
SELECT id, company_id, 'PERF خط ' || cn || '-' || n, 2500 + (n % 5) * 250, 4800 + (n % 5) * 400, 40 FROM perf_l;
-- Each line serves two or three universities.
CREATE TEMP TABLE perf_lu AS
SELECT l.id AS line_id, l.company_id, u.id AS university_id, u.name AS university_name
FROM perf_l l JOIN perf_u u ON (u.n + l.n + l.cn) % GREATEST(u.total / 3, 1) = 0;
INSERT INTO public.line_universities (line_id, university_id, company_id)
SELECT line_id, university_id, company_id FROM perf_lu;
INSERT INTO public.line_period_prices (line_id, company_id, option, price)
SELECT l.id, l.company_id, p, CASE p WHEN 'both' THEN 4800 ELSE 2500 END + (l.n % 5) * 250
FROM perf_l l, unnest(ARRAY['first', 'second', 'both']) p ON CONFLICT DO NOTHING;

CREATE TEMP TABLE perf_s AS
SELECT gen_random_uuid() AS id, l.id AS line_id, l.company_id, g.n
FROM perf_l l CROSS JOIN LATERAL generate_series(1, 5 + (l.n * 3 + l.cn) % 6) g(n);
INSERT INTO public.stations (id, line_id, name, order_index, company_id)
SELECT id, line_id, 'PERF محطة ' || n, n, company_id FROM perf_s;

-- A departure trip (or two) for each university the line serves, and its return.
CREATE TEMP TABLE perf_t AS
SELECT gen_random_uuid() AS id, lu.line_id, lu.company_id, lu.university_id, d.direction, d.k
FROM perf_lu lu, (VALUES ('departure', 1), ('departure', 2), ('return', 1)) d(direction, k);
INSERT INTO public.line_trips (id, line_id, direction, start_time, university_id, company_id)
SELECT id, line_id, direction,
       CASE WHEN direction = 'departure' THEN time '05:30' + k * interval '1 hour' ELSE time '15:00' END,
       university_id, company_id FROM perf_t;
INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time, company_id)
SELECT t.id, s.id,
       CASE WHEN t.direction = 'departure' THEN time '05:30' + t.k * interval '1 hour' + s.n * interval '6 minutes' ELSE time '15:00' END,
       t.company_id
FROM perf_t t JOIN perf_s s ON s.line_id = t.line_id;

-- People. Names are combined from lists so that searches have something to find.
CREATE TEMP TABLE perf_names AS
SELECT ARRAY['محمد', 'أحمد', 'محمود', 'علي', 'عمر', 'يوسف', 'إبراهيم', 'مصطفى', 'خالد', 'حسن', 'كريم', 'عبد الرحمن',
             'فاطمة', 'مريم', 'نور', 'سارة', 'آية', 'هبة', 'منة', 'ياسمين', 'ندى', 'رنا', 'دينا', 'سلمى'] AS first,
       ARRAY['عادل', 'فؤاد', 'السيد', 'حسين', 'عبد الله', 'سعيد', 'جمال', 'رضا', 'شريف', 'طارق', 'ماهر', 'نبيل',
             'العزول', 'الشناوي', 'البنا', 'النجار', 'الصاوي', 'الجمال', 'غنيم', 'سالم', 'عوض', 'بدوي'] AS rest;

CREATE TEMP TABLE perf_st AS
SELECT gen_random_uuid() AS id, g.n, r.pick, r.a, r.b, r.c,
       (SELECT c.id FROM perf_c c WHERE r.pick >= c.lo AND r.pick < c.hi) AS company_id
FROM generate_series(1, :students) g(n)
CROSS JOIN LATERAL (SELECT random() AS pick, random() AS a, random() AS b, random() AS c WHERE g.n > 0) r;
UPDATE perf_st SET company_id = (SELECT id FROM perf_c WHERE n = 1) WHERE company_id IS NULL;
ALTER TABLE perf_st ADD COLUMN line_id uuid, ADD COLUMN university_id uuid;
UPDATE perf_st st SET (line_id, university_id) = (
  SELECT lu.line_id, lu.university_id FROM perf_lu lu WHERE lu.company_id = st.company_id
  ORDER BY md5(lu.line_id::text || lu.university_id::text || st.n::text) LIMIT 1);
CREATE INDEX ON perf_st (id);
CREATE INDEX ON perf_st (line_id);

INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
SELECT id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'perf-' || id || '@local.test', now(), now(), '', '', '', ''
FROM perf_st;
INSERT INTO public.students (id, phone, full_name, university, university_id, created_at)
SELECT st.id, '0159' || lpad(st.n::text, 7, '0'),
       nm.first[1 + floor(st.a * array_length(nm.first, 1))::int] || ' ' ||
       nm.rest[1 + floor(st.b * array_length(nm.rest, 1))::int] || ' ' ||
       nm.rest[1 + floor(st.c * array_length(nm.rest, 1))::int],
       u.name, st.university_id, now() - (st.a * 900) * interval '1 day'
FROM perf_st st CROSS JOIN perf_names nm JOIN perf_u u ON u.id = st.university_id;
INSERT INTO public.company_students (company_id, student_id) SELECT company_id, id FROM perf_st;

-- Staff: an admin a company, a supervisor for every three lines.
CREATE TEMP TABLE perf_adm AS SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn FROM perf_c c;
CREATE TEMP TABLE perf_sup AS
SELECT gen_random_uuid() AS id, c.id AS company_id, c.n AS cn, g.n
FROM perf_c c CROSS JOIN LATERAL generate_series(1, ceil((SELECT count(*) FROM perf_l l WHERE l.company_id = c.id) / 3.0)::int) g(n);
INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
SELECT id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'perf-' || id || '@local.test', now(), now(), '', '', '', ''
FROM (SELECT id FROM perf_sup UNION ALL SELECT id FROM perf_adm) x;
INSERT INTO public.supervisors (id, phone, full_name, company_id)
SELECT id, '0158' || lpad((cn * 1000 + n)::text, 7, '0'), 'PERF مشرف ' || cn || '-' || n, company_id FROM perf_sup;
INSERT INTO public.supervisor_lines (supervisor_id, line_id, company_id)
SELECT s.id, l.id, l.company_id FROM perf_sup s JOIN perf_l l ON l.company_id = s.company_id AND (l.n - 1) / 3 + 1 = s.n;
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id)
SELECT id, 'perf-admin-' || cn || '@local.test', 'PERF مدير ' || cn, 'company_admin', company_id,
       (SELECT a.id FROM public.admins a WHERE a.role = 'super_admin' LIMIT 1) FROM perf_adm;

-- Subscriptions. Terms: first (Sep–Jan) and second (Feb–Jun) of the last three
-- academic years. A student has some of the finished ones and, most of them, the
-- current one in one of its states.
CREATE TEMP TABLE perf_terms AS
SELECT y AS academic_year, code,
       make_date(y + CASE code WHEN 'first' THEN 0 ELSE 1 END, CASE code WHEN 'first' THEN 9 ELSE 2 END, 15) AS start_date,
       make_date(y + 1, CASE code WHEN 'first' THEN 1 ELSE 6 END, 25) AS end_date
FROM generate_series(extract(year FROM public.cairo_today())::int - 3, extract(year FROM public.cairo_today())::int) y,
     unnest(ARRAY['first', 'second']) code;
DELETE FROM perf_terms WHERE start_date > public.cairo_today() + 40;

CREATE TEMP TABLE perf_sub AS
SELECT gen_random_uuid() AS id, st.id AS student_id, st.company_id, st.line_id, st.university_id, st.n,
       t.academic_year, t.code, t.start_date, t.end_date,
       (t.end_date >= public.cairo_today()) AS cur,
       CASE WHEN t.end_date < public.cairo_today() THEN 'expired'
            WHEN h < 0.70 THEN 'active' WHEN h < 0.76 THEN 'pending_payment'
            WHEN h < 0.80 THEN 'pending_review' ELSE 'rejected' END AS status
FROM perf_st st CROSS JOIN perf_terms t
CROSS JOIN LATERAL (SELECT ('x' || substr(md5(st.id::text || t.academic_year || t.code), 1, 8))::bit(32)::bigint / 4294967296.0 AS h) r
WHERE CASE WHEN t.end_date >= public.cairo_today() THEN r.h < 0.82   -- most have the current term
           ELSE r.h < 0.45 END;                                      -- and under half of each past one
ALTER TABLE perf_sub ADD COLUMN station_id uuid, ADD COLUMN dep uuid, ADD COLUMN ret uuid;
UPDATE perf_sub sub SET
  station_id = (SELECT s.id FROM perf_s s WHERE s.line_id = sub.line_id ORDER BY md5(s.id::text || sub.student_id::text) LIMIT 1),
  dep = (SELECT t.id FROM perf_t t WHERE t.line_id = sub.line_id AND t.university_id = sub.university_id AND t.direction = 'departure'
         ORDER BY md5(t.id::text || sub.student_id::text) LIMIT 1),
  ret = (SELECT t.id FROM perf_t t WHERE t.line_id = sub.line_id AND t.university_id = sub.university_id AND t.direction = 'return' LIMIT 1);

INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price,
                                  period_code, academic_year, paid_at, departure_trip_id, return_trip_id, company_id,
                                  departure_time, return_time, created_at)
SELECT sub.id, sub.student_id, sub.line_id, sub.station_id, 'termly', sub.status, sub.start_date, sub.end_date, 2500,
       sub.code, sub.academic_year,
       CASE WHEN sub.status IN ('active', 'expired') THEN sub.start_date - 3 + (sub.n % 20) * interval '1 hour' END,
       sub.dep, sub.ret, sub.company_id,
       (SELECT ts.stop_time FROM public.line_trip_stops ts WHERE ts.trip_id = sub.dep AND ts.station_id = sub.station_id),
       time '15:00', sub.start_date - 5 + (sub.n % 20) * interval '1 hour'
FROM perf_sub sub;

-- Receipts: approved for what was paid, pending for what is under review, a
-- rejected first attempt for some.
INSERT INTO public.receipts (subscription_id, image_url, status, attempt_number, reviewed_at, amount, company_id, created_at, rejection_reason)
SELECT id, student_id || '/' || id || '_a1.jpg',
       CASE status WHEN 'pending_review' THEN 'pending' WHEN 'rejected' THEN 'rejected' ELSE 'approved' END, 1,
       CASE WHEN status <> 'pending_review' THEN start_date - 3 END, 2500, company_id,
       CASE WHEN status = 'pending_review' THEN now() - (n % 2000) * interval '1 minute' ELSE start_date - 4 END,
       CASE WHEN status = 'rejected' THEN 'الصورة غير واضحة' END
FROM perf_sub WHERE status IN ('active', 'expired', 'pending_review', 'rejected');
INSERT INTO storage.objects (bucket_id, name, owner, metadata)
SELECT 'receipts', r.image_url, s.student_id, '{"size": 180000, "mimetype": "image/jpeg"}'::jsonb
FROM public.receipts r JOIN perf_sub s ON s.id = r.subscription_id WHERE r.status = 'pending';

-- Today's and tomorrow's votes (a bit over half of the active riders), a month of scans.
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, is_returning, company_id, subscription_id)
SELECT student_id, public.cairo_today() + d, true, n % 3 <> 0, company_id, id
FROM perf_sub, generate_series(0, 1) d WHERE cur AND status = 'active' AND (n + d) % 9 < 5;
INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, station_id, trip_id, ride_date,
                                           direction, result, scanned_at, company_id)
SELECT (SELECT sl.supervisor_id FROM public.supervisor_lines sl WHERE sl.line_id = sub.line_id LIMIT 1),
       sub.student_id, sub.id, sub.line_id, sub.station_id, sub.dep, public.cairo_today() - d, 'departure', 'checked_in',
       now() - d * interval '1 day', sub.company_id
FROM perf_sub sub, generate_series(1, 30) d WHERE sub.cur AND sub.status = 'active' AND (sub.n + d) % 5 = 0;

-- Notifications: one a day per line for 60 days (every third one to the whole
-- company instead), received by the students of that line or company who have
-- the current term.
CREATE TEMP TABLE perf_n AS
SELECT gen_random_uuid() AS id, l.company_id, CASE WHEN g.n % 3 = 0 AND l.n = 1 THEN NULL ELSE l.id END AS line_id, l.id AS a_line, g.n
FROM perf_l l, generate_series(1, 60) g(n) WHERE g.n % 3 <> 0 OR l.n = 1;
INSERT INTO public.notifications (id, company_id, sender_role, sender_name, line_id, audience, title, body, type, category,
                                  status, sent_at, created_at, audience_spec)
SELECT id, company_id, 'admin', 'PERF', line_id, 'PERF', 'PERF إشعار ' || n, 'نص الإشعار رقم ' || n || '.', 'announcement.admin',
       'announcement', 'sent', now() - n * interval '1 day', now() - n * interval '1 day',
       CASE WHEN line_id IS NULL THEN '{"kind": "company"}'::jsonb ELSE jsonb_build_object('kind', 'line', 'line_id', line_id) END
FROM perf_n;
INSERT INTO public.notification_recipients (notification_id, user_id, is_student, read_at)
SELECT pn.id, sub.student_id, true, CASE WHEN (sub.n + pn.n) % 3 <> 0 THEN now() - pn.n * interval '1 day' END
FROM perf_n pn JOIN perf_sub sub ON sub.cur AND sub.company_id = pn.company_id AND (pn.line_id IS NULL OR sub.line_id = pn.line_id)
WHERE pn.line_id IS NOT NULL OR pn.n % 6 = 0;   -- whole-company notices: every sixth day
COMMIT;
ANALYZE;
SELECT 'companies ' || count(*) FROM public.companies WHERE name LIKE 'PERF %'
UNION ALL SELECT 'lines ' || count(*) FROM public.lines WHERE name LIKE 'PERF %'
UNION ALL SELECT 'students ' || count(*) FROM public.students WHERE phone LIKE '0159%'
UNION ALL SELECT 'subscriptions ' || count(*) FROM public.subscriptions
UNION ALL SELECT 'receipts ' || count(*) || ' (pending ' || count(*) FILTER (WHERE status = 'pending') || ')' FROM public.receipts
UNION ALL SELECT 'votes ' || count(*) FROM public.daily_ride_status
UNION ALL SELECT 'scans ' || count(*) FROM public.supervisor_scan_events
UNION ALL SELECT 'notifications ' || count(*) FROM public.notifications
UNION ALL SELECT 'notification recipients ' || count(*) FROM public.notification_recipients
UNION ALL SELECT 'students in the largest company ' || max(c) FROM (SELECT count(*) c FROM public.company_students GROUP BY company_id) x;
