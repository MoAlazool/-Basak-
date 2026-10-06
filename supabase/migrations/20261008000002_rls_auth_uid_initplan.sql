-- ==============================================================================
-- Migration: 20261008000002_rls_auth_uid_initplan.sql
-- Run AFTER 20261008000001. Safe to re-run.
--
-- Performance (Supabase advisor "auth_rls_initplan"): policies that call
-- auth.uid() directly re-evaluate it for EVERY row scanned. Wrapped as
-- (SELECT auth.uid()) Postgres evaluates it once per query (an InitPlan).
-- Same value, same access rules: each policy is re-applied from its own
-- current definition with only that call wrapped.
-- ==============================================================================
BEGIN;

DO $$
DECLARE
  p record;
  v_using text;
  v_check text;
  -- auth.uid() not already inside "SELECT auth.uid()".
  c_bare constant text := '(?<!SELECT )auth\.uid\(\)';
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname IN ('public', 'storage')
      AND (qual ~ c_bare OR with_check ~ c_bare)
  LOOP
    v_using := regexp_replace(p.qual, c_bare, '(SELECT auth.uid())', 'g');
    v_check := regexp_replace(p.with_check, c_bare, '(SELECT auth.uid())', 'g');
    EXECUTE format('ALTER POLICY %I ON %I.%I%s%s',
      p.policyname, p.schemaname, p.tablename,
      CASE WHEN v_using IS NULL THEN '' ELSE format(' USING (%s)', v_using) END,
      CASE WHEN v_check IS NULL THEN '' ELSE format(' WITH CHECK (%s)', v_check) END);
  END LOOP;
END $$;

COMMIT;
