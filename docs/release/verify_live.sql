-- Read-only launch checks on the live project (Supabase → SQL Editor).
-- Runs in a READ ONLY transaction: it cannot change anything. It prints counts
-- and flags only: no names, phones, e-mails, tokens or secrets.
-- Paste the result into the release checklist (docs/release/APP_STORE_RELEASE.md §6).
BEGIN READ ONLY;

-- 1. Load-test leftovers (must all be 0 / false before launch).
SELECT 'bench schema exists' AS check, (to_regnamespace('bench') IS NOT NULL)::text AS value
UNION ALL SELECT 'bench auth accounts', count(*)::text FROM auth.users
  WHERE email LIKE '%@bench.busak.app' AND id <> 'c5ca34e1-0285-45ef-9ee6-8c7e656ca5f6'
UNION ALL SELECT 'BENCH companies', count(*)::text FROM public.companies WHERE name LIKE 'BENCH%'
-- 2. Push.
UNION ALL SELECT 'push configured', COALESCE((SELECT (configured AND dispatch_url IS NOT NULL AND dispatch_secret IS NOT NULL)::text
                                             FROM public.push_runtime WHERE id), 'no row')
UNION ALL SELECT 'push devices ios', count(*)::text FROM public.push_devices WHERE platform = 'ios'
UNION ALL SELECT 'push devices android', count(*)::text FROM public.push_devices WHERE platform = 'android'
-- 3. Store link for «تحديث من App Store» (set it once the App Store record exists).
UNION ALL SELECT 'ios store_url set', COALESCE((SELECT (store_url IS NOT NULL)::text FROM public.app_versions WHERE platform = 'ios'), 'no row')
-- 4. Tables in public without row level security (must be 0).
UNION ALL SELECT 'public tables without RLS', count(*)::text FROM pg_tables
  WHERE schemaname = 'public' AND NOT rowsecurity
-- 5. Storage buckets: private ones must stay private.
UNION ALL SELECT 'public buckets', string_agg(id, ', ' ORDER BY id) FROM storage.buckets WHERE public
UNION ALL SELECT 'receipts bucket private', COALESCE((SELECT (NOT public)::text FROM storage.buckets WHERE id = 'receipts'), 'missing')
-- 6. Scheduled jobs and their failures in the last 24 hours.
UNION ALL SELECT 'cron jobs', string_agg(jobname || ' [' || schedule || ']', '; ' ORDER BY jobname) FROM cron.job
UNION ALL SELECT 'cron failures 24h', count(*)::text FROM cron.job_run_details
  WHERE status = 'failed' AND start_time > now() - interval '24 hours'
-- 7. Accounts.
UNION ALL SELECT 'auth users', count(*)::text FROM auth.users
UNION ALL SELECT 'students', count(*)::text FROM public.students
UNION ALL SELECT 'companies active', count(*)::text FROM public.companies WHERE status = 'active';

-- 8. Edge functions are not visible from SQL: in Supabase → Edge Functions,
--    bench-admin and bench-load must not be listed.

ROLLBACK;
