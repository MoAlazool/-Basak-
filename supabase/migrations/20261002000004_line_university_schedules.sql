-- ==============================================================================
-- Migration: 20261002000004_line_university_schedules.sql
-- Run AFTER 20261002000003_supervisor_accounts.sql. Safe to re-run.
--
-- One line can serve several universities, each with its own trip time:
--     ميت تمامه | University A | 07:10
--     ميت تمامه | University B | 07:35
-- The line is never duplicated; it owns rows in line_university_schedules.
--
-- Rules
--   * A line WITH active university schedules is "scheduled": a subscriber's
--     departure/return time comes from the schedule of the student's university
--     (server-owned, cannot be chosen freely). Students of other universities
--     cannot subscribe to it.
--   * A line WITHOUT schedules keeps the legacy per-station time lists.
--   * Students only see the schedule of their own university (RLS + RPC).
--   * Company admins manage schedules of their own lines only.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Schedules table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.line_university_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id uuid NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
  university_id uuid NOT NULL REFERENCES public.universities(id) ON DELETE RESTRICT,
  departure_time time NOT NULL,
  return_time time NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT line_university_schedules_unique UNIQUE (line_id, university_id)
);
CREATE INDEX IF NOT EXISTS idx_line_schedules_university ON public.line_university_schedules(university_id);

-- ------------------------------------------------------------------------------
-- 2. Students -> universities link (the text column stays for compatibility).
-- ------------------------------------------------------------------------------
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS university_id uuid REFERENCES public.universities(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_students_university ON public.students(university_id);

CREATE OR REPLACE FUNCTION public.sync_student_university_id()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.university IS DISTINCT FROM OLD.university OR NEW.university_id IS NULL THEN
    NEW.university_id := (SELECT u.id FROM public.universities u WHERE u.name = trim(NEW.university) LIMIT 1);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_student_university_id ON public.students;
CREATE TRIGGER trg_sync_student_university_id
BEFORE INSERT OR UPDATE OF university, university_id ON public.students
FOR EACH ROW EXECUTE FUNCTION public.sync_student_university_id();

UPDATE public.students s SET university_id = u.id
FROM public.universities u
WHERE s.university_id IS NULL AND u.name = trim(s.university);

-- Renaming a university keeps its students linked by id; refresh the label too.
CREATE OR REPLACE FUNCTION public.sync_university_name_to_students()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name THEN
    UPDATE public.students SET university = NEW.name WHERE university_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_university_name ON public.universities;
CREATE TRIGGER trg_sync_university_name
AFTER UPDATE OF name ON public.universities
FOR EACH ROW EXECUTE FUNCTION public.sync_university_name_to_students();

-- Students still cannot change their own university; only the rename cascade
-- above (a nested trigger) may relabel it.
CREATE OR REPLACE FUNCTION public.prevent_student_profile_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.phone IS DISTINCT FROM NEW.phone OR OLD.qr_code_value IS DISTINCT FROM NEW.qr_code_value
     OR (OLD.university IS DISTINCT FROM NEW.university AND pg_trigger_depth() <= 1) THEN
    RAISE EXCEPTION 'بيانات الهاتف والجامعة ورمز QR ثابتة. احذف الحساب وأعد التسجيل لتغييرها.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.current_student_university_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT university_id FROM public.students WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.line_uses_university_schedules(p_line_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.line_university_schedules
    WHERE line_id = p_line_id AND is_active
  )
$$;
GRANT EXECUTE ON FUNCTION public.current_student_university_id(), public.line_uses_university_schedules(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. Subscriptions remember which university schedule they ride on.
-- ------------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS schedule_id uuid REFERENCES public.line_university_schedules(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_subscriptions_schedule ON public.subscriptions(schedule_id);

-- Stations of a scheduled line do not need their own time lists.
ALTER TABLE public.stations ALTER COLUMN departure_times SET DEFAULT '{}';
ALTER TABLE public.stations ALTER COLUMN return_times SET DEFAULT '{}';

-- ------------------------------------------------------------------------------
-- 4. Subscription validation (station + university schedule or legacy times).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_subscription_station_times()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line_id uuid;
  v_line_active boolean;
  v_departure_times time[];
  v_return_times time[];
  v_university_id uuid;
  v_schedule record;
BEGIN
  -- Status/date changes (receipt review, expiry) must not be re-validated
  -- against schedules or stations that may have changed since.
  IF TG_OP = 'UPDATE'
     AND NEW.station_id IS NOT DISTINCT FROM OLD.station_id
     AND NEW.line_id IS NOT DISTINCT FROM OLD.line_id
     AND NEW.schedule_id IS NOT DISTINCT FROM OLD.schedule_id
     AND NEW.departure_time IS NOT DISTINCT FROM OLD.departure_time
     AND NEW.return_time IS NOT DISTINCT FROM OLD.return_time THEN
    RETURN NEW;
  END IF;

  SELECT s.line_id, s.departure_times, s.return_times, l.is_active
  INTO v_line_id, v_departure_times, v_return_times, v_line_active
  FROM public.stations s JOIN public.lines l ON l.id = s.line_id
  WHERE s.id = NEW.station_id AND s.is_active = true;
  IF NOT FOUND OR NOT v_line_active OR v_line_id <> NEW.line_id THEN
    RAISE EXCEPTION 'المحطة المختارة غير متاحة على هذا الخط.';
  END IF;

  IF public.line_uses_university_schedules(NEW.line_id) THEN
    -- Schedule propagation (time edited by an admin) keeps the same schedule.
    IF TG_OP = 'UPDATE' AND pg_trigger_depth() > 1 AND NEW.schedule_id IS NOT NULL
       AND NEW.schedule_id IS NOT DISTINCT FROM OLD.schedule_id THEN
      RETURN NEW;
    END IF;

    SELECT university_id INTO v_university_id FROM public.students WHERE id = NEW.student_id;
    SELECT sch.id, sch.departure_time, sch.return_time INTO v_schedule
    FROM public.line_university_schedules sch
    WHERE sch.line_id = NEW.line_id AND sch.university_id = v_university_id AND sch.is_active;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'هذا الخط لا يخدم جامعة الطالب. اختر خطاً يخدم جامعتك.';
    END IF;
    IF NEW.schedule_id IS NOT NULL AND NEW.schedule_id <> v_schedule.id THEN
      RAISE EXCEPTION 'موعد الجامعة المختار لا يطابق جامعة الطالب.';
    END IF;
    -- Times are server-owned for scheduled lines.
    NEW.schedule_id := v_schedule.id;
    NEW.departure_time := v_schedule.departure_time;
    NEW.return_time := v_schedule.return_time;
    RETURN NEW;
  END IF;

  NEW.schedule_id := NULL;
  IF NEW.departure_time IS NULL OR NOT (NEW.departure_time = ANY(v_departure_times)) THEN
    RAISE EXCEPTION 'اختر موعد ذهاب متاحاً للمحطة المختارة.';
  END IF;
  IF NEW.return_time IS NULL OR NOT (NEW.return_time = ANY(v_return_times)) THEN
    RAISE EXCEPTION 'اختر موعد عودة متاحاً للمحطة المختارة.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_subscription_station_times ON public.subscriptions;
CREATE TRIGGER trg_validate_subscription_station_times
BEFORE INSERT OR UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.validate_subscription_station_times();

-- ------------------------------------------------------------------------------
-- 5. Keep subscriptions and upcoming ride votes in step with schedule changes.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_line_university_schedule()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND (NEW.line_id <> OLD.line_id OR NEW.university_id <> OLD.university_id) THEN
    IF EXISTS (SELECT 1 FROM public.subscriptions WHERE schedule_id = NEW.id) THEN
      RAISE EXCEPTION 'لا يمكن نقل موعد مرتبط باشتراكات. عطّله وأضف موعداً جديداً.';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND (NEW.departure_time <> OLD.departure_time OR NEW.return_time <> OLD.return_time) THEN
    UPDATE public.daily_ride_status d
    SET departure_time = CASE WHEN d.departure_time = OLD.departure_time THEN NEW.departure_time ELSE d.departure_time END,
        return_time = CASE WHEN d.return_time = OLD.return_time THEN NEW.return_time ELSE d.return_time END
    WHERE d.ride_date >= public.cairo_today()
      AND d.student_id IN (
        SELECT sub.student_id FROM public.subscriptions sub
        WHERE sub.schedule_id = NEW.id AND sub.status IN ('pending_payment', 'pending_review', 'active'));
    UPDATE public.subscriptions
    SET departure_time = NEW.departure_time, return_time = NEW.return_time
    WHERE schedule_id = NEW.id AND status IN ('pending_payment', 'pending_review', 'active');
  END IF;

  -- A newly active schedule adopts current subscribers of that university on the line.
  IF NEW.is_active AND (TG_OP = 'INSERT' OR NOT OLD.is_active) THEN
    UPDATE public.subscriptions sub
    SET schedule_id = NEW.id, departure_time = NEW.departure_time, return_time = NEW.return_time
    FROM public.students st
    WHERE st.id = sub.student_id AND st.university_id = NEW.university_id
      AND sub.line_id = NEW.line_id AND sub.schedule_id IS NULL
      AND sub.status IN ('pending_payment', 'pending_review', 'active');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_apply_line_university_schedule ON public.line_university_schedules;
CREATE TRIGGER trg_apply_line_university_schedule
AFTER INSERT OR UPDATE ON public.line_university_schedules
FOR EACH ROW EXECUTE FUNCTION public.apply_line_university_schedule();

-- ------------------------------------------------------------------------------
-- 6. RLS: same tenant scope as stations; students see only their university.
-- ------------------------------------------------------------------------------
ALTER TABLE public.line_university_schedules ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.line_university_schedules TO authenticated;
REVOKE ALL ON public.line_university_schedules FROM anon;

DROP POLICY IF EXISTS line_schedules_read_scope ON public.line_university_schedules;
CREATE POLICY line_schedules_read_scope ON public.line_university_schedules FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()))
  OR (public.is_supervisor() AND line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a))
  OR (NOT public.is_admin() AND is_active AND university_id = public.current_student_university_id())
  OR EXISTS (SELECT 1 FROM public.subscriptions sub
             WHERE sub.schedule_id = line_university_schedules.id AND sub.student_id = auth.uid())
);

DROP POLICY IF EXISTS line_schedules_company_manage ON public.line_university_schedules;
CREATE POLICY line_schedules_company_manage ON public.line_university_schedules FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id())))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id())));

-- ------------------------------------------------------------------------------
-- 7. Student line catalogue: legacy lines + scheduled lines serving my university.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_student_line_options()
RETURNS TABLE (
  line_id uuid, uses_university_schedules boolean, schedule_id uuid,
  university_name text, departure_time time, return_time time
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT l.id,
         public.line_uses_university_schedules(l.id),
         sch.id, u.name, sch.departure_time, sch.return_time
  FROM public.lines l
  JOIN public.companies c ON c.id = l.company_id AND c.is_active
  LEFT JOIN public.line_university_schedules sch
    ON sch.line_id = l.id AND sch.is_active AND sch.university_id = public.current_student_university_id()
  LEFT JOIN public.universities u ON u.id = sch.university_id
  WHERE l.is_active
    AND auth.uid() IS NOT NULL
    AND (sch.id IS NOT NULL OR NOT public.line_uses_university_schedules(l.id))
$$;
REVOKE ALL ON FUNCTION public.get_student_line_options() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_line_options() TO authenticated;

-- ------------------------------------------------------------------------------
-- 8. Ride confirmation accepts the schedule time for scheduled subscriptions.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.toggle_student_daily_ride(
  p_ride_date date, p_is_riding boolean, p_departure_time time, p_return_time time, p_is_returning boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_student_id uuid := auth.uid();
  v_departure_times time[];
  v_return_times time[];
  v_local_now timestamp := now() AT TIME ZONE 'Africa/Cairo';
  v_expected_ride_date date;
BEGIN
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_local_now::time >= TIME '16:00' THEN v_expected_ride_date := v_local_now::date + 1;
  ELSE v_expected_ride_date := v_local_now::date; END IF;
  IF v_local_now::time >= TIME '06:00' AND v_local_now::time < TIME '16:00' THEN
    RAISE EXCEPTION 'التصويت مغلق. يفتح يومياً من الساعة ٤ مساءً حتى ٦ صباحاً.';
  END IF;
  IF p_ride_date <> v_expected_ride_date THEN RAISE EXCEPTION 'اختر تاريخ الرحلة المتاح للتصويت.'; END IF;

  SELECT CASE WHEN sch.id IS NOT NULL THEN ARRAY[sch.departure_time] ELSE st.departure_times END,
         CASE WHEN sch.id IS NOT NULL THEN ARRAY[sch.return_time] ELSE st.return_times END
  INTO v_departure_times, v_return_times
  FROM public.subscriptions sub
  JOIN public.stations st ON st.id = sub.station_id
  JOIN public.lines l ON l.id = sub.line_id
  LEFT JOIN public.line_university_schedules sch ON sch.id = sub.schedule_id
  WHERE sub.student_id = v_student_id AND sub.status = 'active'
    AND (sub.start_date IS NULL OR sub.start_date <= p_ride_date)
    AND (sub.end_date IS NULL OR sub.end_date >= p_ride_date)
    AND st.is_active = true AND l.is_active = true
  ORDER BY sub.created_at DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'لا يوجد اشتراك نشط لهذا التاريخ.'; END IF;

  IF p_is_riding THEN
    IF p_departure_time IS NULL OR NOT (p_departure_time = ANY(COALESCE(v_departure_times, '{}'::time[]))) THEN
      RAISE EXCEPTION 'اختر موعد ذهاب متاحاً.';
    END IF;
    IF p_is_returning AND (p_return_time IS NULL OR NOT (p_return_time = ANY(COALESCE(v_return_times, '{}'::time[])))) THEN
      RAISE EXCEPTION 'اختر موعد عودة متاحاً أو ألغِ رحلة العودة.';
    END IF;
  END IF;

  INSERT INTO public.daily_ride_status(student_id, ride_date, is_riding, departure_time, return_time, is_returning, toggled_at)
  VALUES (v_student_id, p_ride_date, p_is_riding, p_departure_time,
          CASE WHEN p_is_returning THEN p_return_time ELSE NULL END, p_is_returning, now())
  ON CONFLICT (student_id, ride_date) DO UPDATE SET is_riding = EXCLUDED.is_riding,
    departure_time = EXCLUDED.departure_time, return_time = EXCLUDED.return_time,
    is_returning = EXCLUDED.is_returning, toggled_at = now();

  RETURN jsonb_build_object('success', true, 'student_id', v_student_id, 'ride_date', p_ride_date,
    'is_riding', p_is_riding, 'departure_time', p_departure_time,
    'return_time', CASE WHEN p_is_returning THEN p_return_time ELSE NULL END,
    'is_returning', p_is_returning, 'toggled_at', now());
END;
$$;

-- ------------------------------------------------------------------------------
-- 9. Rider counts per station AND university trip (supervisor + dashboards).
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_line_rider_counts_with_returns(uuid, date);
CREATE FUNCTION public.get_line_rider_counts_with_returns(p_line_id uuid, p_ride_date date)
RETURNS TABLE (
  line_id uuid, line_name text, station_id uuid, station_name text, order_index integer,
  departure_time time, return_time time, riding_count bigint, returning_count bigint,
  schedule_id uuid, university_name text
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;

  RETURN QUERY
  WITH trips AS (
    -- One trip per university schedule (active, or still carrying active riders) ...
    SELECT sch.id AS trip_schedule_id, sch.departure_time AS trip_departure,
           sch.return_time AS trip_return, u.name AS trip_university
    FROM public.line_university_schedules sch
    JOIN public.universities u ON u.id = sch.university_id
    WHERE sch.line_id = p_line_id
      AND (sch.is_active OR EXISTS (
        SELECT 1 FROM public.subscriptions s WHERE s.schedule_id = sch.id AND s.status = 'active'))
    UNION ALL
    -- ... plus the legacy station-time trip when the line has no schedules or legacy riders.
    SELECT NULL::uuid, NULL::time, NULL::time, NULL::text
    WHERE NOT public.line_uses_university_schedules(p_line_id)
       OR EXISTS (SELECT 1 FROM public.subscriptions s
                  WHERE s.line_id = p_line_id AND s.schedule_id IS NULL AND s.status = 'active')
  )
  SELECT l.id, l.name, st.id, st.name, st.order_index,
    COALESCE(t.trip_departure, st.departure_time, st.departure_times[1], MIN(sub.departure_time)),
    COALESCE(t.trip_return, st.return_time, st.return_times[1], MIN(sub.return_time)),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true AND drs.is_returning = true),
    t.trip_schedule_id, t.trip_university
  FROM public.stations st
  JOIN public.lines l ON l.id = st.line_id
  CROSS JOIN trips t
  LEFT JOIN public.subscriptions sub ON sub.station_id = st.id AND sub.status = 'active'
    AND sub.schedule_id IS NOT DISTINCT FROM t.trip_schedule_id
  LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
  WHERE st.line_id = p_line_id AND st.is_active = true AND l.is_active = true
  GROUP BY l.id, l.name, st.id, st.name, st.order_index, st.departure_time, st.departure_times,
    st.return_time, st.return_times, t.trip_schedule_id, t.trip_departure, t.trip_return, t.trip_university
  ORDER BY t.trip_departure NULLS LAST, st.order_index;
END;
$$;
REVOKE ALL ON FUNCTION public.get_line_rider_counts_with_returns(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_line_rider_counts_with_returns(uuid, date) TO authenticated;

-- ------------------------------------------------------------------------------
-- 10. QR lookup also reports the student's university trip.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(p_qr_code uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_student_id uuid;
  v_data jsonb;
BEGIN
  IF NOT (public.is_supervisor() OR public.is_admin()) THEN
    RAISE EXCEPTION 'Access denied. Only supervisors and admins can perform QR lookups.';
  END IF;

  SELECT s.id INTO v_student_id FROM public.students s WHERE s.qr_code_value = p_qr_code;
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Student not found with the provided QR code.';
  END IF;

  IF public.is_company_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = v_student_id AND l.company_id = public.current_admin_company_id()
  ) THEN
    RAISE EXCEPTION 'Student is outside your company.';
  END IF;

  IF public.is_supervisor() AND NOT public.is_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student_id AND sub.status = 'active'
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ) THEN
    RAISE EXCEPTION 'Student is outside your assigned lines.';
  END IF;

  SELECT jsonb_build_object(
    'id', s.id, 'full_name', s.full_name, 'phone', s.phone, 'university', s.university,
    'subscription', (
      SELECT jsonb_build_object(
        'id', sub.id, 'type', sub.type, 'status', sub.status,
        'start_date', sub.start_date, 'end_date', sub.end_date,
        'line_name', l.name, 'station_name', st.name,
        'university_schedule', u.name,
        'departure_time', COALESCE(sub.departure_time, sch.departure_time, st.departure_time),
        'return_time', COALESCE(sub.return_time, sch.return_time, st.return_time),
        'payment_date', (SELECT r.reviewed_at FROM public.receipts r
          WHERE r.subscription_id = sub.id AND r.status = 'approved'
          ORDER BY r.reviewed_at DESC LIMIT 1)
      )
      FROM public.subscriptions sub
      JOIN public.lines l ON l.id = sub.line_id
      JOIN public.stations st ON st.id = sub.station_id
      LEFT JOIN public.line_university_schedules sch ON sch.id = sub.schedule_id
      LEFT JOIN public.universities u ON u.id = sch.university_id
      WHERE sub.student_id = s.id AND sub.status IN ('active', 'pending_review', 'pending_payment')
        AND (NOT public.is_company_admin() OR l.company_id = public.current_admin_company_id())
        AND (NOT public.is_supervisor() OR public.is_admin() OR sub.line_id IN (
          SELECT line_id FROM public.get_supervisor_assigned_line_ids()))
      ORDER BY sub.created_at DESC LIMIT 1
    ),
    'today_ride_status', (SELECT COALESCE(drs.is_riding, false)
      FROM public.daily_ride_status drs WHERE drs.student_id = s.id AND drs.ride_date = CURRENT_DATE)
  ) INTO v_data FROM public.students s WHERE s.id = v_student_id;

  RETURN v_data;
END;
$$;

COMMIT;
