-- ==============================================================================
-- Migration: 20261114000001_security_hardening.sql
-- Run AFTER 20261113000001. Safe to re-run. Changes no answer and no rule.
--
-- Found in a security review of the live project (Supabase's security
-- advisors and the grants themselves):
-- 1. Two plain functions had no fixed search_path (advisor:
--    function_search_path_mutable). Both use built-ins only.
-- 2. anon and authenticated could TRUNCATE every public table: Supabase's
--    default grants. TRUNCATE ignores row-level security; the API cannot
--    issue it, but nothing needs it, so it is taken back, also for tables
--    made later.
-- ==============================================================================
BEGIN;

ALTER FUNCTION public.blocked_phone_message() SET search_path = '';
ALTER FUNCTION public.receipt_object_subscription(text) SET search_path = '';

REVOKE TRUNCATE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated;

COMMIT;
