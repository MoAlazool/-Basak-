-- ==============================================================================
-- Migration: 20260926000003_storage_setup.sql
-- Project: University Bus Subscription System (باصك - Basak)
-- Description: Storage bucket for bank transfer receipts and storage RLS policies
-- ==============================================================================

-- 1. Create a private bucket for subscription receipts
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'receipts',
    'receipts',
    false, -- Private bucket: access requires authenticated RLS or signed URLs
    5242880, -- 5 MB maximum file size
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

-- 2. Storage RLS Policies on storage.objects

-- Students can upload receipts into their own folder: receipts/{student_id}/*
CREATE POLICY "Students can upload their own receipts"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Students can read their own uploaded receipts
CREATE POLICY "Students can read their own receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Supervisors can read receipts for students on their assigned lines
CREATE POLICY "Supervisors can view assigned line student receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'receipts'
    AND (
        public.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.subscriptions sub
            WHERE sub.student_id::text = (storage.foldername(name))[1]
              AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
        )
    )
);

-- Admins can view and delete all receipts in the bucket
CREATE POLICY "Admins full access on receipts bucket"
ON storage.objects FOR ALL
TO authenticated
USING (
    bucket_id = 'receipts' AND public.is_admin()
)
WITH CHECK (
    bucket_id = 'receipts' AND public.is_admin()
);
