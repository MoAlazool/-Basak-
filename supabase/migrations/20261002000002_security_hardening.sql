-- ==============================================================================
-- Migration: 20261002000002_security_hardening.sql
-- Project: باصك (Basak)
-- Source: project review on 2026-10-02
-- Safe to re-run. Run AFTER 20261002000001_company_admin_scope.sql.
--
-- Fixes:
--   1. Students could INSERT a subscription as 'active' with any price/end_date.
--   2. Supervisors could UPDATE any subscription column (price, dates, status).
--   3. Admin manual "active" status left start_date/end_date NULL (never expires).
--   4. Students could write daily_ride_status directly, bypassing the 4PM–6AM vote window.
--   5. Expired subscriptions stayed 'active' forever and blocked renewal (unique index).
--   6. Daily (cash) subscription ended "today" so it could never be used for a vote.
--   7. Universities/colleges unreadable before login (signup) and by company admins.
--   8. Legacy storage policies let anon/any user read every receipt image.
--   9. Legacy scripts dropped students/supervisors -> auth.users FKs (orphans, no cascade).
--  10. Any authenticated user (supervisor/admin) could insert themselves as a student.
-- ==============================================================================
BEGIN;

-- Cairo "today" and the ride date the current vote window targets.
CREATE OR REPLACE FUNCTION public.cairo_today()
RETURNS date LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT (now() AT TIME ZONE 'Africa/Cairo')::date
$$;

-- Votes run 16:00 (day before) -> 06:00 (ride day). A daily ticket bought now
-- is valid for the next ride the student can still vote for.
CREATE OR REPLACE FUNCTION public.next_votable_ride_date()
RETURNS date LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN (now() AT TIME ZONE 'Africa/Cairo')::time < TIME '06:00' THEN public.cairo_today()
    ELSE public.cairo_today() + 1
  END
$$;

-- ------------------------------------------------------------------------------
-- 5. Expiry: mark finished subscriptions as expired.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_finished_subscriptions()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  UPDATE public.subscriptions
  SET status = 'expired'
  WHERE status = 'active' AND end_date IS NOT NULL AND end_date < public.cairo_today();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.expire_finished_subscriptions() FROM PUBLIC, anon, authenticated;

-- One-time cleanup of rows that are already past their end date.
SELECT public.expire_finished_subscriptions();

-- ------------------------------------------------------------------------------
-- 1 + 6. Server-owned fields on subscription INSERT.
-- Service role / SQL editor (auth.uid() IS NULL) and admins keep full control.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_subscription_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line record;
  v_ride_date date;
BEGIN
  -- Free the one-active-subscription slot if the old one already ended.
  UPDATE public.subscriptions
  SET status = 'expired'
  WHERE student_id = NEW.student_id AND status = 'active'
    AND end_date IS NOT NULL AND end_date < public.cairo_today();

  IF auth.uid() IS NULL OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.student_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'لا يمكن إنشاء اشتراك لحساب آخر.';
  END IF;

  SELECT l.price_termly, l.price_yearly, l.price_daily, l.is_active, c.is_active AS company_active
  INTO v_line
  FROM public.lines l JOIN public.companies c ON c.id = l.company_id
  WHERE l.id = NEW.line_id;

  IF NOT FOUND OR NOT v_line.is_active OR NOT v_line.company_active THEN
    RAISE EXCEPTION 'هذا الخط غير متاح للاشتراك حالياً.';
  END IF;

  NEW.price := CASE NEW.type
    WHEN 'termly' THEN v_line.price_termly
    WHEN 'yearly' THEN v_line.price_yearly
    ELSE v_line.price_daily
  END;
  NEW.created_at := now();

  IF NEW.type = 'daily' THEN
    -- Cash on the bus: active immediately, valid for the next votable ride.
    v_ride_date := public.next_votable_ride_date();
    NEW.status := 'active';
    NEW.start_date := v_ride_date;
    NEW.end_date := v_ride_date;
  ELSE
    NEW.status := 'pending_payment';
    NEW.start_date := NULL;
    NEW.end_date := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_subscription_insert ON public.subscriptions;
CREATE TRIGGER trg_enforce_subscription_insert
BEFORE INSERT ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.enforce_subscription_insert();

-- ------------------------------------------------------------------------------
-- 2 + 3. Subscription UPDATE guard.
-- pg_trigger_depth() > 1 => the change comes from a receipt trigger
-- (upload -> pending_review, approve -> active, reject -> pending_payment).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_subscription_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF pg_trigger_depth() <= 1 AND auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'تعديل الاشتراك متاح للإدارة فقط. اعتماد الدفع يتم من خلال الإيصال.';
  END IF;

  -- Any path that activates a subscription without dates gets proper dates.
  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' AND NEW.end_date IS NULL THEN
    NEW.start_date := COALESCE(NEW.start_date, public.cairo_today());
    NEW.end_date := CASE NEW.type
      WHEN 'yearly' THEN (NEW.start_date + INTERVAL '1 year')::date
      WHEN 'termly' THEN (NEW.start_date + INTERVAL '4 months')::date
      ELSE public.next_votable_ride_date()
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_subscription_update ON public.subscriptions;
CREATE TRIGGER trg_guard_subscription_update
BEFORE UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.guard_subscription_update();

-- Supervisors never need a direct UPDATE path (they review receipts instead).
DROP POLICY IF EXISTS subscriptions_supervisor_update ON public.subscriptions;

-- Receipt review: Cairo dates instead of UTC CURRENT_DATE.
CREATE OR REPLACE FUNCTION public.handle_receipt_review()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub_type text;
  v_start date := public.cairo_today();
  v_end date;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status <> 'pending' THEN
      RAISE EXCEPTION 'تمت مراجعة هذا الإيصال بالفعل.';
    END IF;
    NEW.reviewed_at := now();
    NEW.reviewed_by := auth.uid();

    IF NEW.status = 'approved' THEN
      SELECT type INTO v_sub_type FROM public.subscriptions WHERE id = NEW.subscription_id;
      v_end := CASE v_sub_type
        WHEN 'yearly' THEN (v_start + INTERVAL '1 year')::date
        WHEN 'termly' THEN (v_start + INTERVAL '4 months')::date
        ELSE v_start
      END;
      UPDATE public.subscriptions
      SET status = 'active', start_date = v_start, end_date = v_end
      WHERE id = NEW.subscription_id;
    ELSIF NEW.status = 'rejected' THEN
      IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
        RAISE EXCEPTION 'A written rejection reason is mandatory when rejecting a receipt.';
      END IF;
      UPDATE public.subscriptions SET status = 'pending_payment' WHERE id = NEW.subscription_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. Daily ride rows are written ONLY through toggle_student_daily_ride().
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS daily_rides_student_insert ON public.daily_ride_status;
DROP POLICY IF EXISTS daily_rides_student_update ON public.daily_ride_status;

-- ------------------------------------------------------------------------------
-- 7. Academic catalog: readable before login and by every admin.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS universities_student_read ON public.universities;
DROP POLICY IF EXISTS universities_anon_read ON public.universities;
DROP POLICY IF EXISTS universities_auth_read ON public.universities;
CREATE POLICY universities_anon_read ON public.universities FOR SELECT TO anon
USING (is_active);
CREATE POLICY universities_auth_read ON public.universities FOR SELECT TO authenticated
USING (is_active OR public.is_super_admin());

DROP POLICY IF EXISTS colleges_student_read ON public.colleges;
DROP POLICY IF EXISTS colleges_anon_read ON public.colleges;
DROP POLICY IF EXISTS colleges_auth_read ON public.colleges;
CREATE POLICY colleges_anon_read ON public.colleges FOR SELECT TO anon
USING (is_active);
CREATE POLICY colleges_auth_read ON public.colleges FOR SELECT TO authenticated
USING (is_active OR public.is_super_admin());

GRANT SELECT ON public.universities, public.colleges TO anon;

-- ------------------------------------------------------------------------------
-- 8. Remove legacy storage policies (complete_reset_and_fix.sql) and any anon
--    access on storage.objects.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_r_receipts_storage" ON storage.objects;
DROP POLICY IF EXISTS "auth_r_own_receipt_file" ON storage.objects;
DROP POLICY IF EXISTS "auth_upload_receipts" ON storage.objects;  -- duplicate of "Students can upload their own receipts"
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects' AND 'anon' = ANY(roles)
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', p.policyname);
  END LOOP;
END $$;

-- ------------------------------------------------------------------------------
-- 9. Restore cascade from auth.users. NOT VALID = existing orphans are kept
--    (list them with the query at the bottom) but new rows and deletes are enforced.
-- ------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'students_id_fkey') THEN
    ALTER TABLE public.students ADD CONSTRAINT students_id_fkey
      FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'supervisors_id_fkey') THEN
    ALTER TABLE public.supervisors ADD CONSTRAINT supervisors_id_fkey
      FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;
  END IF;
END $$;
ALTER TABLE public.students ALTER COLUMN id DROP DEFAULT;
ALTER TABLE public.supervisors ALTER COLUMN id DROP DEFAULT;

-- ------------------------------------------------------------------------------
-- 10. Only plain users (not staff) can register a student profile.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS students_register_self ON public.students;
CREATE POLICY students_register_self ON public.students FOR INSERT TO authenticated
WITH CHECK (
  students.id = auth.uid()
  AND NOT public.is_admin()
  AND NOT EXISTS (SELECT 1 FROM public.supervisors s WHERE s.id = auth.uid())
);

COMMIT;

-- ------------------------------------------------------------------------------
-- OPTIONAL (run separately):
-- a) Nightly expiry job, if the pg_cron extension is enabled (Database > Extensions):
--      SELECT cron.schedule('basak-expire-subscriptions', '5 22 * * *',
--                           $$SELECT public.expire_finished_subscriptions()$$);
--    (22:05 UTC = 01:05 Cairo). The insert trigger above already frees the slot
--    on renewal, so this job only keeps reports/rider counts accurate.
--
-- b) Orphan check (profiles with no Auth user = cannot log in, phone is locked):
--      SELECT 'student' AS kind, id, phone FROM public.students s
--      WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.id)
--      UNION ALL
--      SELECT 'supervisor', id, phone FROM public.supervisors s
--      WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.id);
--
-- c) AFTER deploying the admin-create-supervisor Edge Function and the updated
--    SupervisorsPage / mobile login (no more plaintext passwords):
--      ALTER TABLE public.supervisors DROP COLUMN IF EXISTS password;
--      ALTER TABLE public.students DROP COLUMN IF EXISTS password;
-- ------------------------------------------------------------------------------
