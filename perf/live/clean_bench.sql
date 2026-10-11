-- Removes everything the live benchmark added (perf/live/bench.sql), in one
-- transaction. Scope: the BENCH companies (bench.company) and the benchmark
-- accounts (e-mail @bench.busak.app). Nothing else is touched; the platform admin
-- is checked before and after.
--
-- Triggers are off for this transaction (session_replication_role = replica), as
-- they were while loading: otherwise every deleted row would be broadcast on
-- Realtime and the append-only receipt snapshots could not be removed. With
-- triggers off, cascades do not run either, so every table is cleared explicitly,
-- children first. The receipt-snapshot guard itself is not changed.
--
-- Afterwards: `node perf/live/auth_users.mjs delete` removes the accounts through
-- the Auth Admin API, then `DROP SCHEMA bench CASCADE`.
BEGIN;
SET LOCAL session_replication_role = replica;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE id = 'c5ca34e1-0285-45ef-9ee6-8c7e656ca5f6' AND role = 'super_admin') THEN
    RAISE EXCEPTION 'platform admin missing - aborting';
  END IF;
END $$;

CREATE TEMP TABLE bc ON COMMIT DROP AS SELECT id FROM bench.company;
CREATE TEMP TABLE bu ON COMMIT DROP AS
  SELECT id FROM auth.users WHERE email LIKE '%@bench.busak.app' AND id <> 'c5ca34e1-0285-45ef-9ee6-8c7e656ca5f6';

DELETE FROM public.push_outbox WHERE user_id IN (SELECT id FROM bu);
DELETE FROM public.notification_recipients WHERE user_id IN (SELECT id FROM bu);
DELETE FROM public.push_outbox WHERE notification_id IN (SELECT id FROM public.notifications WHERE company_id IN (SELECT id FROM bc));
DELETE FROM public.notification_recipients WHERE notification_id IN (SELECT id FROM public.notifications WHERE company_id IN (SELECT id FROM bc));
DELETE FROM public.notification_audit WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.notifications WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.push_devices WHERE user_id IN (SELECT id FROM bu);
DELETE FROM public.notification_preferences WHERE user_id IN (SELECT id FROM bu);
DELETE FROM public.supervisor_scan_events WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.daily_ride_status WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.wallet_apple_registrations WHERE student_id IN (SELECT id FROM bu);
DELETE FROM public.wallet_passes WHERE student_id IN (SELECT id FROM bu) OR company_id IN (SELECT id FROM bc);
DELETE FROM public.subscription_receipts WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.receipts WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.subscriptions WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.company_students WHERE company_id IN (SELECT id FROM bc) OR student_id IN (SELECT id FROM bu);
DELETE FROM public.password_reset_requests WHERE student_id IN (SELECT id FROM bu);
DELETE FROM public.student_correction_requests WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.company_invites WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.students WHERE id IN (SELECT id FROM bu);
DELETE FROM public.supervisor_lines WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.supervisors WHERE id IN (SELECT id FROM bu) OR company_id IN (SELECT id FROM bc);
DELETE FROM public.line_trip_stops WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.line_trips WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.line_university_schedules WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.line_period_prices WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.line_universities WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.stations WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.lines WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.admins WHERE company_id IN (SELECT id FROM bc) AND role = 'company_admin';
DELETE FROM public.company_terms WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.company_payment_methods WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.wallet_card_settings WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.company_governorates WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.company_receipt_counters WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.company_plans WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.platform_charges WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.report_resets WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.deleted_student_revenue WHERE company_id IN (SELECT id FROM bc);
DELETE FROM public.companies WHERE id IN (SELECT id FROM bc);
DELETE FROM bench.active; DELETE FROM bench.student; DELETE FROM bench.company;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE id = 'c5ca34e1-0285-45ef-9ee6-8c7e656ca5f6' AND role = 'super_admin') THEN
    RAISE EXCEPTION 'platform admin missing after clean-up - rolling back';
  END IF;
END $$;
COMMIT;
