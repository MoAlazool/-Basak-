-- ==============================================================================
-- Migration: 20261125000002_storage_hygiene.sql
-- Run AFTER 20261125000001. Safe to re-run. Nothing the apps read or write
-- changes; the database only keeps less that nobody uses.
--
-- 1. pg_cron's run history. Every run of every job leaves a row in
--    cron.job_run_details, kept for ever. The notification tick runs every
--    minute and the offers announcer every five: about 1,600 rows a day,
--    ≈ 100 MB a year on a 500 MB plan, read by nobody. A daily job now keeps
--    the last 7 days (what Supabase itself recommends). The jobs themselves
--    are untouched.
--
-- 2. Two indexes that copy another one exactly. students(phone) and
--    students(qr_code_value) each have a UNIQUE index (students_phone_key,
--    students_qr_code_value_key) and, from the first schema, a second plain
--    index on the same column. A lookup uses either; every insert and update
--    writes both, and both take space. The unique ones stay, so every lookup
--    keeps an index and uniqueness is still enforced.
-- ==============================================================================
BEGIN;

DROP INDEX IF EXISTS public.idx_students_phone;
DROP INDEX IF EXISTS public.idx_students_qr;

COMMIT;

-- Every night at 03:20 Cairo winter time (01:20 UTC), where pg_cron can be had.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'basak-cron-history-purge';
    PERFORM cron.schedule('basak-cron-history-purge', '20 1 * * *',
      $job$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$job$);
  ELSE
    RAISE NOTICE 'pg_cron is not installed: nothing to keep short.';
  END IF;
END $$;
