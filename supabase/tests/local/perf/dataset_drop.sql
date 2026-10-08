-- Removes everything dataset.sql added (LOCAL database only).
\set ON_ERROR_STOP 1
BEGIN;
SET LOCAL session_replication_role = replica;
CREATE TEMP TABLE perf_c AS SELECT id FROM public.companies WHERE name LIKE 'PERF %';
CREATE TEMP TABLE perf_p AS
SELECT id FROM public.students WHERE phone LIKE '0159%'
UNION SELECT id FROM public.supervisors WHERE company_id IN (SELECT id FROM perf_c)
UNION SELECT id FROM public.admins WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM storage.objects WHERE bucket_id = 'receipts' AND owner IN (SELECT id FROM perf_p);
DELETE FROM public.notification_recipients WHERE notification_id IN (SELECT id FROM public.notifications WHERE company_id IN (SELECT id FROM perf_c));
DELETE FROM public.push_outbox WHERE notification_id IN (SELECT id FROM public.notifications WHERE company_id IN (SELECT id FROM perf_c));
DELETE FROM public.notifications WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.notification_audit WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.supervisor_scan_events WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.daily_ride_status WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.subscription_receipts WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.receipts WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.subscriptions WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.company_students WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.supervisor_lines WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.line_trip_stops WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.line_trips WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.stations WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.line_universities WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.line_period_prices WHERE line_id IN (SELECT id FROM public.lines WHERE company_id IN (SELECT id FROM perf_c));
DELETE FROM public.lines WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.supervisors WHERE id IN (SELECT id FROM perf_p);
DELETE FROM public.admins WHERE id IN (SELECT id FROM perf_p);
DELETE FROM public.students WHERE id IN (SELECT id FROM perf_p);
DELETE FROM public.company_receipt_counters WHERE company_id IN (SELECT id FROM perf_c);
DELETE FROM public.companies WHERE id IN (SELECT id FROM perf_c);
DELETE FROM auth.users WHERE id IN (SELECT id FROM perf_p);
COMMIT;
