-- Ensure receipt review works for authenticated administrators and that
-- supervisors can only sign images belonging to subscriptions on their lines.

-- reviewed_by was restricted to supervisors even though admins may review too.
ALTER TABLE public.receipts
    DROP CONSTRAINT IF EXISTS receipts_reviewed_by_fkey;

ALTER TABLE public.receipts
    ADD CONSTRAINT receipts_reviewed_by_fkey
    FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- A rejected payment remains payable and can be uploaded again.
CREATE OR REPLACE FUNCTION public.handle_receipt_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sub_type TEXT;
    v_start DATE := CURRENT_DATE;
    v_end DATE;
BEGIN
    IF NEW.status != OLD.status THEN
        NEW.reviewed_at := now();
        NEW.reviewed_by := auth.uid();

        IF NEW.status = 'approved' THEN
            SELECT type INTO v_sub_type
            FROM public.subscriptions
            WHERE id = NEW.subscription_id;

            IF v_sub_type = 'yearly' THEN
                v_end := v_start + INTERVAL '1 year';
            ELSIF v_sub_type = 'termly' THEN
                v_end := v_start + INTERVAL '4 months';
            ELSE
                v_end := v_start + INTERVAL '1 day';
            END IF;

            UPDATE public.subscriptions
            SET status = 'active', start_date = v_start, end_date = v_end
            WHERE id = NEW.subscription_id;
        ELSIF NEW.status = 'rejected' THEN
            IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
                RAISE EXCEPTION 'A written rejection reason is mandatory when rejecting a receipt.';
            END IF;

            UPDATE public.subscriptions
            SET status = 'pending_payment'
            WHERE id = NEW.subscription_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Keep direct line assignments limited to active supervisor accounts.
CREATE OR REPLACE FUNCTION public.get_supervisor_assigned_line_ids()
RETURNS TABLE (line_id UUID)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT l.id
    FROM public.lines l
    INNER JOIN public.supervisors s ON s.id = l.supervisor_id
    WHERE s.id = auth.uid() AND s.is_active = true
    UNION
    SELECT l.id
    FROM public.lines l
    INNER JOIN public.supervisors s ON s.company_id = l.company_id
    WHERE s.id = auth.uid() AND s.is_active = true;
$$;

-- The storage object path is {student_id}/{subscription_id}_{timestamp}.{ext}.
-- Match that exact subscription, rather than granting access to all objects for
-- a student who may have receipts on more than one line over time.
DROP POLICY IF EXISTS "Supervisors can view assigned line student receipts" ON storage.objects;
CREATE POLICY "Supervisors can view assigned line student receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'receipts'
    AND (
        public.is_admin()
        OR EXISTS (
            SELECT 1
            FROM public.subscriptions sub
            WHERE sub.student_id::text = split_part(name, '/', 1)
              AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
              AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
        )
    )
);
