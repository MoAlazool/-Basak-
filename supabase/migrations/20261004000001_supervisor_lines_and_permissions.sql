-- ==============================================================================
-- Migration: 20261004000001_supervisor_lines_and_permissions.sql
-- Run AFTER 20261003000001_supervisor_app.sql. Safe to re-run.
--
--   1. supervisor_lines: the lines each supervisor is responsible for
--      (Company -> Line -> Supervisor). A supervisor may cover several lines and
--      a line may have several supervisors. This table is now the ONLY source of
--      a supervisor's scope: a supervisor with no assigned line sees no line
--      (the old "no assignment = every company line" fallback is removed).
--      lines.supervisor_id is kept as the line's primary contact for students
--      and is maintained from supervisor_lines.
--   2. Receipt review is restricted to company admins and the super admin.
--      Supervisors lose every read/update path to receipts and receipt images.
--   3. A student can be checked in (QR) only once per day, whatever the trip
--      direction or supervisor. Enforced by a unique index.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Supervisor -> line assignments
-- ------------------------------------------------------------------------------
-- A surrogate key keeps PostgREST from treating this table as a many-to-many
-- junction, which would make the existing lines -> supervisors embed ambiguous.
CREATE TABLE IF NOT EXISTS public.supervisor_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id uuid NOT NULL REFERENCES public.supervisors(id) ON DELETE CASCADE,
  line_id uuid NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
  assigned_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT supervisor_lines_unique UNIQUE (supervisor_id, line_id)
);
CREATE INDEX IF NOT EXISTS idx_supervisor_lines_line ON public.supervisor_lines(line_id);

CREATE OR REPLACE FUNCTION public.validate_supervisor_line()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.supervisors s JOIN public.lines l ON l.company_id = s.company_id
    WHERE s.id = NEW.supervisor_id AND l.id = NEW.line_id
  ) THEN
    RAISE EXCEPTION 'الخط المختار لا يتبع شركة المشرف.' USING ERRCODE = '23514';
  END IF;
  NEW.assigned_by := COALESCE(NEW.assigned_by, auth.uid());
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_validate_supervisor_line ON public.supervisor_lines;
CREATE TRIGGER trg_validate_supervisor_line
BEFORE INSERT OR UPDATE ON public.supervisor_lines
FOR EACH ROW EXECUTE FUNCTION public.validate_supervisor_line();

-- lines.supervisor_id = the earliest assigned active supervisor of the line.
CREATE OR REPLACE FUNCTION public.refresh_line_primary_supervisor(p_line_id uuid, p_exclude uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_primary uuid;
BEGIN
  SELECT sl.supervisor_id INTO v_primary
  FROM public.supervisor_lines sl JOIN public.supervisors s ON s.id = sl.supervisor_id
  WHERE sl.line_id = p_line_id AND sl.supervisor_id IS DISTINCT FROM p_exclude
  ORDER BY s.is_active DESC, sl.assigned_at, sl.supervisor_id
  LIMIT 1;
  UPDATE public.lines SET supervisor_id = v_primary
  WHERE id = p_line_id AND supervisor_id IS DISTINCT FROM v_primary;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_line_primary_supervisor(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sync_line_primary_supervisor()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM public.refresh_line_primary_supervisor(NEW.line_id);
  END IF;
  IF TG_OP IN ('DELETE', 'UPDATE') THEN
    PERFORM public.refresh_line_primary_supervisor(OLD.line_id, OLD.supervisor_id);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_line_primary_supervisor ON public.supervisor_lines;
CREATE TRIGGER trg_sync_line_primary_supervisor
AFTER INSERT OR UPDATE OR DELETE ON public.supervisor_lines
FOR EACH ROW EXECUTE FUNCTION public.sync_line_primary_supervisor();

-- Older dashboard builds still write lines.supervisor_id directly. Translate a
-- direct write (not one of our own nested updates) into assignment changes.
CREATE OR REPLACE FUNCTION public.translate_line_supervisor_write()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF pg_trigger_depth() > 1 OR NEW.supervisor_id IS NOT DISTINCT FROM OLD.supervisor_id THEN
    RETURN NULL;
  END IF;
  IF OLD.supervisor_id IS NOT NULL THEN
    DELETE FROM public.supervisor_lines WHERE line_id = NEW.id AND supervisor_id = OLD.supervisor_id;
  END IF;
  IF NEW.supervisor_id IS NOT NULL THEN
    INSERT INTO public.supervisor_lines (supervisor_id, line_id)
    VALUES (NEW.supervisor_id, NEW.id) ON CONFLICT (supervisor_id, line_id) DO NOTHING;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_translate_line_supervisor_write ON public.lines;
CREATE TRIGGER trg_translate_line_supervisor_write
AFTER UPDATE OF supervisor_id ON public.lines
FOR EACH ROW EXECUTE FUNCTION public.translate_line_supervisor_write();

-- Backfill. Direct assignments carry over. A supervisor who had none covered
-- every line of their company until now; keep that scope explicit so nobody
-- loses access on deploy (admins can narrow it from the dashboard).
INSERT INTO public.supervisor_lines (supervisor_id, line_id, assigned_at)
SELECT l.supervisor_id, l.id, s.created_at
FROM public.lines l JOIN public.supervisors s ON s.id = l.supervisor_id AND s.company_id = l.company_id
ON CONFLICT (supervisor_id, line_id) DO NOTHING;

-- assigned_at = now() keeps an existing direct supervisor as the line's primary contact.
INSERT INTO public.supervisor_lines (supervisor_id, line_id, assigned_at)
SELECT s.id, l.id, now()
FROM public.supervisors s JOIN public.lines l ON l.company_id = s.company_id
WHERE NOT EXISTS (SELECT 1 FROM public.lines d WHERE d.supervisor_id = s.id)
ON CONFLICT (supervisor_id, line_id) DO NOTHING;

ALTER TABLE public.supervisor_lines ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.supervisor_lines FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.supervisor_lines FROM authenticated;  -- writes via set_supervisor_lines()
GRANT SELECT ON public.supervisor_lines TO authenticated;
GRANT ALL ON public.supervisor_lines TO service_role;

DROP POLICY IF EXISTS supervisor_lines_read_scope ON public.supervisor_lines;
CREATE POLICY supervisor_lines_read_scope ON public.supervisor_lines FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()))
  OR supervisor_id = auth.uid()
);

-- The single scope helper used by every supervisor policy and RPC.
CREATE OR REPLACE FUNCTION public.get_supervisor_assigned_line_ids()
RETURNS TABLE (line_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT sl.line_id
  FROM public.supervisor_lines sl
  JOIN public.supervisors s ON s.id = sl.supervisor_id AND s.is_active
  JOIN public.lines l ON l.id = sl.line_id AND l.company_id = s.company_id
  WHERE sl.supervisor_id = auth.uid()
$$;

-- Replace the full set of lines of a supervisor atomically.
-- Callers: the super admin, the supervisor's company admin, or the service role
-- (admin-create-supervisor Edge Function).
CREATE OR REPLACE FUNCTION public.set_supervisor_lines(p_supervisor_id uuid, p_line_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_ids uuid[] := ARRAY(SELECT DISTINCT x FROM unnest(COALESCE(p_line_ids, '{}'::uuid[])) x WHERE x IS NOT NULL);
  v_foreign int;
BEGIN
  SELECT company_id INTO v_company FROM public.supervisors WHERE id = p_supervisor_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المشرف غير موجود.' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND v_company = public.current_admin_company_id())
    OR (auth.uid() IS NULL AND COALESCE(auth.role(), 'service_role') = 'service_role')
  ) THEN
    RAISE EXCEPTION 'غير مسموح بتعديل خطوط هذا المشرف.' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_foreign
  FROM unnest(v_ids) x
  WHERE NOT EXISTS (SELECT 1 FROM public.lines l WHERE l.id = x AND l.company_id = v_company);
  IF v_foreign > 0 THEN
    RAISE EXCEPTION 'بعض الخطوط المختارة لا تتبع شركة المشرف.' USING ERRCODE = '23514';
  END IF;

  DELETE FROM public.supervisor_lines WHERE supervisor_id = p_supervisor_id AND NOT (line_id = ANY(v_ids));
  INSERT INTO public.supervisor_lines (supervisor_id, line_id)
  SELECT p_supervisor_id, x FROM unnest(v_ids) x
  ON CONFLICT (supervisor_id, line_id) DO NOTHING;

  RETURN jsonb_build_object('supervisor_id', p_supervisor_id,
    'line_ids', to_jsonb(ARRAY(SELECT line_id FROM public.supervisor_lines WHERE supervisor_id = p_supervisor_id ORDER BY line_id)));
END;
$$;
REVOKE ALL ON FUNCTION public.set_supervisor_lines(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_supervisor_lines(uuid, uuid[]) TO authenticated, service_role;

-- Students see the supervisors assigned to the line of their active subscription.
DROP POLICY IF EXISTS supervisors_read_scope ON public.supervisors;
CREATE POLICY supervisors_read_scope ON public.supervisors FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND company_id = public.current_admin_company_id())
  OR (NOT public.is_admin() AND supervisors.id = auth.uid())
  OR (NOT public.is_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.supervisor_lines sl ON sl.line_id = sub.line_id
    WHERE sub.student_id = auth.uid() AND sub.status = 'active' AND sl.supervisor_id = supervisors.id
  ))
);

-- ------------------------------------------------------------------------------
-- 2. Receipt review: company admins and the super admin only.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS receipts_read_scope ON public.receipts;
CREATE POLICY receipts_read_scope ON public.receipts FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.id = subscription_id AND l.company_id = public.current_admin_company_id()
  ))
  OR EXISTS (SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id AND sub.student_id = auth.uid())
);

DROP POLICY IF EXISTS receipts_company_review ON public.receipts;
CREATE POLICY receipts_company_review ON public.receipts FOR UPDATE TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.id = subscription_id AND l.company_id = public.current_admin_company_id()
  ))
)
WITH CHECK (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.id = subscription_id AND l.company_id = public.current_admin_company_id()
  ))
);

-- Defence in depth: whatever policy might be added later, only an admin
-- (or the service role) can change a receipt's review state.
CREATE OR REPLACE FUNCTION public.receipts_review_admin_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() AND (
    NEW.status IS DISTINCT FROM OLD.status
    OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
    OR NEW.image_url IS DISTINCT FROM OLD.image_url
  ) THEN
    RAISE EXCEPTION 'مراجعة الإيصالات متاحة لمدير الشركة ومدير النظام فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_receipts_review_admin_only ON public.receipts;
CREATE TRIGGER trg_receipts_review_admin_only
BEFORE UPDATE ON public.receipts
FOR EACH ROW EXECUTE FUNCTION public.receipts_review_admin_only();

-- Receipt images and profile photos: the owner, the student's company admin,
-- the super admin. NOTE: inside these sub-queries an unqualified "name" binds
-- to lines.name (the line's name), not to the storage object's path. The
-- previous versions of these policies had exactly that bug, so company admins
-- could never open a receipt image or a student photo (signing them returned
-- 400 "Object not found"). Always use objects.name here.
DROP POLICY IF EXISTS "Admin and supervisor scoped receipt access" ON storage.objects;
DROP POLICY IF EXISTS "Supervisors can view assigned line student receipts" ON storage.objects;
DROP POLICY IF EXISTS "Scoped receipt image access" ON storage.objects;
CREATE POLICY "Scoped receipt image access" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'receipts' AND (
    (storage.foldername(objects.name))[1] = auth.uid()::text
    OR public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
      WHERE sub.student_id::text = (storage.foldername(objects.name))[1]
        AND left(split_part(objects.name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
        AND l.company_id = public.current_admin_company_id()
    ))
  )
);

DROP POLICY IF EXISTS "Admins can manage scoped receipt objects" ON storage.objects;
CREATE POLICY "Admins can manage scoped receipt objects" ON storage.objects FOR ALL TO authenticated
USING (
  bucket_id = 'receipts' AND (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id::text = (storage.foldername(objects.name))[1]
      AND left(split_part(objects.name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
      AND l.company_id = public.current_admin_company_id()
  )))
)
WITH CHECK (
  bucket_id = 'receipts' AND (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id::text = (storage.foldername(objects.name))[1]
      AND left(split_part(objects.name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
      AND l.company_id = public.current_admin_company_id()
  )))
);

DROP POLICY IF EXISTS "Students and scoped admins can view profile images" ON storage.objects;
CREATE POLICY "Students and scoped admins can view profile images" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'student-avatars' AND (
    (storage.foldername(objects.name))[1] = auth.uid()::text OR public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
      WHERE sub.student_id::text = (storage.foldername(objects.name))[1]
        AND l.company_id = public.current_admin_company_id()
    ))
  )
);

-- QR lookup: the approval date comes from receipts, so only admins get it.
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(p_qr_code uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_student_id uuid;
  v_today date := public.cairo_today();
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
        'payment_date', CASE WHEN public.is_admin() THEN (
          SELECT r.reviewed_at FROM public.receipts r
          WHERE r.subscription_id = sub.id AND r.status = 'approved'
          ORDER BY r.reviewed_at DESC LIMIT 1) END
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
      -- The subscription valid today first, then the newest one.
      ORDER BY (sub.status = 'active' AND COALESCE(sub.start_date, v_today) <= v_today
                AND COALESCE(sub.end_date, v_today) >= v_today) DESC,
               sub.created_at DESC
      LIMIT 1
    ),
    'today_ride_status', (SELECT COALESCE(drs.is_riding, false)
      FROM public.daily_ride_status drs WHERE drs.student_id = s.id AND drs.ride_date = v_today)
  ) INTO v_data FROM public.students s WHERE s.id = v_student_id;

  RETURN v_data;
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. One successful QR check-in per student per day.
-- ------------------------------------------------------------------------------
-- Earlier rows allowed one check-in per direction; keep the first of each day.
UPDATE public.supervisor_scan_events e
SET result = 'already_checked_in'
WHERE e.result = 'checked_in' AND EXISTS (
  SELECT 1 FROM public.supervisor_scan_events f
  WHERE f.student_id = e.student_id AND f.ride_date = e.ride_date AND f.result = 'checked_in'
    AND (f.scanned_at, f.id) < (e.scanned_at, e.id));

DROP INDEX IF EXISTS public.uq_scan_checkin_once;
CREATE UNIQUE INDEX IF NOT EXISTS uq_scan_checkin_once_per_day
  ON public.supervisor_scan_events(student_id, ride_date) WHERE result = 'checked_in';

CREATE OR REPLACE FUNCTION public.supervisor_check_in_student(p_qr_code uuid, p_direction text DEFAULT 'departure')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_student public.students%ROWTYPE;
  v_sub record;
  v_result text;
  v_first record;
BEGIN
  IF NOT public.is_supervisor() THEN
    RAISE EXCEPTION 'هذه العملية متاحة لمشرفي الحافلات النشطين فقط.';
  END IF;
  IF p_direction NOT IN ('departure', 'return') THEN
    RAISE EXCEPTION 'اتجاه الرحلة غير صحيح.';
  END IF;

  SELECT * INTO v_student FROM public.students WHERE qr_code_value = p_qr_code;
  IF NOT FOUND THEN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result)
    VALUES (v_me, v_today, p_direction, 'not_found');
    RETURN jsonb_build_object('result', 'not_found', 'message', 'رمز QR غير مسجل لأي طالب.');
  END IF;

  -- Students outside the supervisor's lines: log, reveal nothing about them.
  IF NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student.id
      AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
  ) THEN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result)
    VALUES (v_me, v_today, p_direction, 'outside_assigned_lines');
    RETURN jsonb_build_object('result', 'outside_assigned_lines',
      'message', 'هذا الطالب غير مشترك في الخطوط المسندة إليك.');
  END IF;

  SELECT sub.id, sub.line_id, sub.station_id, sub.schedule_id INTO v_sub
  FROM public.subscriptions sub
  WHERE sub.student_id = v_student.id AND sub.status = 'active'
    AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
    AND (sub.start_date IS NULL OR sub.start_date <= v_today)
    AND (sub.end_date IS NULL OR sub.end_date >= v_today)
  ORDER BY sub.created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    v_result := 'no_active_subscription';
    INSERT INTO public.supervisor_scan_events(supervisor_id, student_id, ride_date, direction, result)
    VALUES (v_me, v_student.id, v_today, p_direction, v_result);
  ELSE
    BEGIN
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_today, p_direction, 'checked_in');
      v_result := 'checked_in';
    EXCEPTION WHEN unique_violation THEN
      -- uq_scan_checkin_once_per_day: this student was already checked in today.
      v_result := 'already_checked_in';
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_today, p_direction, v_result);
    END;
  END IF;

  SELECT e.scanned_at, e.direction INTO v_first FROM public.supervisor_scan_events e
  WHERE e.student_id = v_student.id AND e.ride_date = v_today AND e.result = 'checked_in';

  RETURN jsonb_build_object(
    'result', v_result,
    'message', CASE v_result
      WHEN 'checked_in' THEN 'تم تسجيل حضور الطالب بنجاح.'
      WHEN 'already_checked_in' THEN 'تم تسجيل حضور هذا الطالب اليوم بالفعل. This student has already been checked in today.'
      ELSE 'لا يوجد اشتراك ساري لهذا الطالب اليوم.' END,
    'direction', COALESCE(v_first.direction, p_direction),
    'ride_date', v_today,
    'checked_in_at', v_first.scanned_at,
    'confirmed_ride_today', (SELECT drs.is_riding FROM public.daily_ride_status drs
                             WHERE drs.student_id = v_student.id AND drs.ride_date = v_today),
    'student', public.lookup_student_by_qr(p_qr_code)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.supervisor_check_in_student(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_check_in_student(uuid, text) TO authenticated;

-- ------------------------------------------------------------------------------
-- 4. Supervisor dashboard: assigned lines only, no receipt data.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_supervisor_dashboard()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_data jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.supervisors WHERE id = v_me) THEN
    RAISE EXCEPTION 'هذا الحساب ليس حساب مشرف.';
  END IF;

  WITH assigned AS (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a),
  active_subs AS (
    SELECT sub.* FROM public.subscriptions sub
    WHERE sub.status = 'active' AND sub.line_id IN (SELECT line_id FROM assigned)
      AND (sub.start_date IS NULL OR sub.start_date <= v_today)
      AND (sub.end_date IS NULL OR sub.end_date >= v_today)
  )
  SELECT jsonb_build_object(
    'today', v_today,
    'profile', (
      SELECT jsonb_build_object(
        'id', s.id, 'full_name', s.full_name, 'phone', s.phone, 'is_active', s.is_active,
        'created_at', s.created_at, 'company_id', s.company_id, 'company_name', c.name,
        'company_active', c.is_active,
        'assignment', CASE WHEN EXISTS (SELECT 1 FROM assigned) THEN 'direct' ELSE 'none' END)
      FROM public.supervisors s LEFT JOIN public.companies c ON c.id = s.company_id
      WHERE s.id = v_me),
    'totals', jsonb_build_object(
      'lines', (SELECT count(*) FROM assigned),
      'registered_students', (SELECT count(DISTINCT student_id) FROM active_subs),
      'stations', (SELECT count(*) FROM public.stations st WHERE st.is_active AND st.line_id IN (SELECT line_id FROM assigned)),
      'confirmed_today', (SELECT count(*) FROM public.daily_ride_status drs
                          WHERE drs.ride_date = v_today AND drs.is_riding
                            AND drs.student_id IN (SELECT student_id FROM active_subs)),
      'checked_in_today', (SELECT count(*) FROM public.supervisor_scan_events e
                           WHERE e.supervisor_id = v_me AND e.ride_date = v_today AND e.result = 'checked_in')),
    -- Students per trip time on the supervisor's lines, from the students' ride
    -- confirmations: today and, once tomorrow's vote has opened, the next ride day.
    'trip_times', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'ride_date', t.ride_date, 'line_id', t.line_id, 'line_name', t.line_name,
          'direction', t.direction, 'time', t.trip_time, 'students', t.students)
        ORDER BY t.ride_date, t.direction, t.trip_time, t.line_name)
      FROM (
        SELECT drs.ride_date, l.id AS line_id, l.name AS line_name, x.direction, x.trip_time,
               count(DISTINCT drs.student_id) AS students
        FROM public.daily_ride_status drs
        JOIN public.subscriptions sub ON sub.student_id = drs.student_id AND sub.status = 'active'
          AND sub.line_id IN (SELECT line_id FROM assigned)
          AND COALESCE(sub.start_date, drs.ride_date) <= drs.ride_date
          AND COALESCE(sub.end_date, drs.ride_date) >= drs.ride_date
        JOIN public.lines l ON l.id = sub.line_id
        CROSS JOIN LATERAL (VALUES
          ('departure', COALESCE(drs.departure_time, sub.departure_time)),
          ('return', CASE WHEN drs.is_returning THEN COALESCE(drs.return_time, sub.return_time) END)
        ) AS x(direction, trip_time)
        WHERE drs.is_riding AND x.trip_time IS NOT NULL
          AND drs.ride_date IN (v_today, public.next_votable_ride_date())
        GROUP BY drs.ride_date, l.id, l.name, x.direction, x.trip_time
      ) t), '[]'::jsonb),
    'lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'name', l.name, 'is_active', l.is_active,
        'directly_assigned', true,
        'price_termly', l.price_termly, 'price_yearly', l.price_yearly, 'price_daily', l.price_daily,
        'registered_students', (SELECT count(*) FROM active_subs a WHERE a.line_id = l.id),
        'confirmed_today', (SELECT count(*) FROM active_subs a JOIN public.daily_ride_status drs
                              ON drs.student_id = a.student_id AND drs.ride_date = v_today AND drs.is_riding
                            WHERE a.line_id = l.id),
        'schedules', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'university', u.name, 'departure_time', sch.departure_time, 'return_time', sch.return_time,
            'registered_students', (SELECT count(*) FROM active_subs a WHERE a.schedule_id = sch.id))
            ORDER BY sch.departure_time)
          FROM public.line_university_schedules sch JOIN public.universities u ON u.id = sch.university_id
          WHERE sch.line_id = l.id AND sch.is_active), '[]'::jsonb),
        'stations', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', st.id, 'name', st.name, 'order_index', st.order_index,
            'departure_times', st.departure_times, 'return_times', st.return_times,
            'registered_students', (SELECT count(*) FROM active_subs a WHERE a.station_id = st.id),
            'confirmed_today', (SELECT count(*) FROM active_subs a JOIN public.daily_ride_status drs
                                  ON drs.student_id = a.student_id AND drs.ride_date = v_today AND drs.is_riding
                                WHERE a.station_id = st.id),
            'checked_in_today', (SELECT count(*) FROM public.supervisor_scan_events e
                                 WHERE e.station_id = st.id AND e.ride_date = v_today AND e.result = 'checked_in'))
            ORDER BY st.order_index)
          FROM public.stations st WHERE st.line_id = l.id AND st.is_active), '[]'::jsonb))
        ORDER BY l.name)
      FROM public.lines l WHERE l.id IN (SELECT line_id FROM assigned)), '[]'::jsonb)
  ) INTO v_data;

  RETURN v_data;
END;
$$;
REVOKE ALL ON FUNCTION public.get_supervisor_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supervisor_dashboard() TO authenticated;

-- ------------------------------------------------------------------------------
-- 5. Profile photos: a student's photo path must live in the student's folder,
--    and drop references to photos that were never stored (signing them is
--    what produced the 400 "Object not found" responses in the dashboard).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_student_profile_image()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.profile_image_url IS NOT NULL AND btrim(NEW.profile_image_url) = '' THEN
    NEW.profile_image_url := NULL;
  END IF;
  IF NEW.profile_image_url IS NOT NULL AND split_part(NEW.profile_image_url, '/', 1) <> NEW.id::text THEN
    RAISE EXCEPTION 'مسار صورة الطالب غير صالح.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_validate_student_profile_image ON public.students;
CREATE TRIGGER trg_validate_student_profile_image
BEFORE INSERT OR UPDATE OF profile_image_url ON public.students
FOR EACH ROW EXECUTE FUNCTION public.validate_student_profile_image();

UPDATE public.students s SET profile_image_url = NULL
WHERE s.profile_image_url IS NOT NULL
  AND (split_part(s.profile_image_url, '/', 1) <> s.id::text
       OR NOT EXISTS (SELECT 1 FROM storage.objects o
                      WHERE o.bucket_id = 'student-avatars' AND o.name = s.profile_image_url));

COMMIT;
