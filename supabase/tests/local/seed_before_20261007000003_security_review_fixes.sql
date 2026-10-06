-- Fixture: storage policy found on the live project (2026-10-04) that no
-- migration creates; it came from a legacy SQL script. It lets every
-- supervisor and every company admin read every receipt image in the bucket.
-- 20261007000003 must drop it (checked by tests C9 / C11).
DROP POLICY IF EXISTS "Students read receipts storage" ON storage.objects;
CREATE POLICY "Students read receipts storage" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'receipts' AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin() OR public.is_supervisor()));
