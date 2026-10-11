-- Removes every tenant (company) and its data from the live project, keeping the
-- platform's reference data and the Super Admin. One transaction: all or nothing.
-- Students and supervisors are deleted the way the app deletes them: their row's
-- trg_delete_login_with_profile removes the matching auth.users login.
-- subscription_receipts is append-only (trg_forbid_receipt_change); the guard is
-- switched off for this transaction only and switched back on before COMMIT.
BEGIN;
DELETE FROM public.offers;                 -- offer_redemptions / offer_impressions cascade
DELETE FROM public.merchants;
DELETE FROM public.term_recap_releases;
DELETE FROM public.notifications;          -- notification_recipients / push_outbox cascade
DELETE FROM public.notification_audit;
DELETE FROM public.push_devices;
DELETE FROM public.notification_preferences;
DELETE FROM public.supervisor_scan_events;
DELETE FROM public.daily_ride_status;
DELETE FROM public.wallet_apple_registrations;
DELETE FROM public.wallet_apple_devices;
DELETE FROM public.wallet_passes;
ALTER TABLE public.subscription_receipts DISABLE TRIGGER trg_forbid_receipt_change;
DELETE FROM public.subscription_receipts;
ALTER TABLE public.subscription_receipts ENABLE TRIGGER trg_forbid_receipt_change;
DELETE FROM public.subscriptions;          -- receipts cascade
DELETE FROM public.complaints;
DELETE FROM public.chat_messages;
DELETE FROM public.students;               -- company_students, requests, invites cascade; login removed
DELETE FROM public.supervisors;            -- supervisor_lines cascade; login removed
DELETE FROM public.lines;                  -- stations, trips, stops, prices, line_universities, schedules cascade
DELETE FROM public.stations;
DELETE FROM public.deleted_student_revenue;
DELETE FROM public.blocked_phones;
DELETE FROM public.password_admin_resets;
DELETE FROM public.admins WHERE role <> 'super_admin';
DELETE FROM public.companies;              -- settings, terms, payment methods, plans, charges, governorates cascade
COMMIT;
