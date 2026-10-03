-- ==============================================================================
-- Migration: 20261006000002_receipts_reviewer_fk.sql
-- Safe to re-run.
--
-- receipts.reviewed_by referenced supervisors(id) (from when supervisors
-- reviewed receipts). Review is admin-only since 20261004000001, and the review
-- trigger stores auth.uid() — an admin id — so every approval / rejection
-- failed with 409 (receipts_reviewed_by_fkey). The reviewer is any Auth user
-- (admin, or a supervisor in historical rows).
-- ==============================================================================
BEGIN;

ALTER TABLE public.receipts DROP CONSTRAINT IF EXISTS receipts_reviewed_by_fkey;
ALTER TABLE public.receipts
  ADD CONSTRAINT receipts_reviewed_by_fkey
  FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

COMMIT;
