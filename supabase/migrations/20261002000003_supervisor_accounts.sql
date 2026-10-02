-- ==============================================================================
-- Migration: 20261002000003_supervisor_accounts.sql
-- Run AFTER 20261002000002_security_hardening.sql. Safe to re-run.
--
-- Supervisors are now created by the admin-create-supervisor Edge Function as
-- confirmed Auth users. This migration:
--   1. Re-links legacy supervisor rows whose id does not match their Auth user
--      (<phone>@busak.app). Without this the app cannot detect the supervisor role.
--   2. Removes the plaintext password columns (no longer read or written).
-- ==============================================================================
BEGIN;

UPDATE public.supervisors s
SET id = u.id,
    created_by_admin_id = COALESCE(
      s.created_by_admin_id,
      (SELECT a.id FROM public.admins a WHERE a.role = 'super_admin' ORDER BY a.created_at LIMIT 1)
    )
FROM auth.users u
WHERE u.email = s.phone || '@busak.app'
  AND u.id <> s.id
  AND NOT EXISTS (SELECT 1 FROM auth.users x WHERE x.id = s.id)
  AND NOT EXISTS (SELECT 1 FROM public.students st WHERE st.id = u.id)
  AND NOT EXISTS (SELECT 1 FROM public.supervisors o WHERE o.id = u.id);

ALTER TABLE public.supervisors DROP COLUMN IF EXISTS password;
ALTER TABLE public.students DROP COLUMN IF EXISTS password;

COMMIT;

-- Remaining orphans (profile rows without an Auth user cannot log in):
--   SELECT 'student' AS kind, id, phone FROM public.students s
--   WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.id)
--   UNION ALL
--   SELECT 'supervisor', id, phone FROM public.supervisors s
--   WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.id);
