-- ==============================================================================
-- Migration: 20260926000005_receipt_triggers.sql
-- Project: University Bus Subscription System (باصك - Basak)
-- Description: Business rules triggers for receipt attempts, rejection reasons,
--              and automatic subscription status transitions.
-- ==============================================================================

-- 1. FUNCTION & TRIGGER: Auto-calculate attempt_number and enforce max 5 attempts (4 re-uploads)
CREATE OR REPLACE FUNCTION public.handle_new_receipt_upload()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_last_attempt INT;
    v_sub_status TEXT;
BEGIN
    -- Check current subscription status
    SELECT status INTO v_sub_status
    FROM public.subscriptions
    WHERE id = NEW.subscription_id;

    IF v_sub_status = 'active' THEN
        RAISE EXCEPTION 'Subscription is already active. Cannot upload further receipts.';
    END IF;

    -- Count previous attempts
    SELECT COALESCE(MAX(attempt_number), 0) INTO v_last_attempt
    FROM public.receipts
    WHERE subscription_id = NEW.subscription_id;

    IF v_last_attempt >= 5 THEN
        RAISE EXCEPTION 'Maximum receipt upload limit reached (5 attempts: initial + 4 re-uploads).';
    END IF;

    NEW.attempt_number := v_last_attempt + 1;
    NEW.status := 'pending';
    NEW.created_at := now();

    -- Update parent subscription status to pending_review
    UPDATE public.subscriptions
    SET status = 'pending_review'
    WHERE id = NEW.subscription_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_new_receipt ON public.receipts;
CREATE TRIGGER trg_handle_new_receipt
BEFORE INSERT ON public.receipts
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_receipt_upload();

-- 2. FUNCTION & TRIGGER: Handle receipt review (approval / rejection)
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
    -- Verify status change
    IF NEW.status != OLD.status THEN
        NEW.reviewed_at := now();
        NEW.reviewed_by := auth.uid();

        IF NEW.status = 'approved' THEN
            -- Fetch subscription type to determine end_date
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

            -- Activate subscription
            UPDATE public.subscriptions
            SET 
                status = 'active',
                start_date = v_start,
                end_date = v_end
            WHERE id = NEW.subscription_id;

        ELSIF NEW.status = 'rejected' THEN
            -- Enforce non-empty rejection reason
            IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
                RAISE EXCEPTION 'A written rejection reason is mandatory when rejecting a receipt.';
            END IF;

            -- Update subscription to rejected
            UPDATE public.subscriptions
            SET status = 'rejected'
            WHERE id = NEW.subscription_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_receipt_review ON public.receipts;
CREATE TRIGGER trg_handle_receipt_review
BEFORE UPDATE ON public.receipts
FOR EACH ROW
EXECUTE FUNCTION public.handle_receipt_review();

-- 3. FUNCTION & TRIGGER: Prevent profile edits on student table (Delete-and-re-register only)
CREATE OR REPLACE FUNCTION public.prevent_student_profile_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Prevent changing phone, university, or qr_code_value
    IF OLD.phone != NEW.phone OR OLD.qr_code_value != NEW.qr_code_value OR OLD.university != NEW.university THEN
        RAISE EXCEPTION 'Profile editing is not allowed. To modify your data, you must delete your account and register again.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_student_update ON public.students;
CREATE TRIGGER trg_prevent_student_update
BEFORE UPDATE ON public.students
FOR EACH ROW
EXECUTE FUNCTION public.prevent_student_profile_update();
