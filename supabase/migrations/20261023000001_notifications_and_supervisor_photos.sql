-- ==============================================================================
-- Migration: 20261023000001_notifications_and_supervisor_photos.sql
-- Run AFTER 20261022000001. Safe to re-run.
--
-- 1. Notifications to students. A company admin writes to all the company's
--    students or one line; a supervisor to one of their lines, or to the riders
--    who chose one of its trips for today or the next day. Sent at once. The
--    recipients are fixed when it is sent and each keeps its own read time; the
--    supervisors of the lines concerned receive it too, and the company's admins
--    see everything sent with how many students read it. Clients read and write
--    through the functions below only (no direct table access).
-- 2. Supervisor photos: private bucket 'supervisor-avatars' (<supervisor id>/…),
--    uploaded by the company's admins and seen by the supervisor, those admins
--    and the students riding one of that supervisor's lines.
-- 3. supervisor_check_in_student also returns the student's ride vote for the
--    day ('ride_vote': riding or not, returning, chosen times; null: no vote).
-- 4. Fix: students could not read their own supervisor (name, phone, photo).
--    The policy looked the supervisor up in supervisor_lines, which students
--    cannot read, so the home screen's supervisor card never appeared.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Notifications
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  sender_role text NOT NULL CHECK (sender_role IN ('admin', 'supervisor')),
  sender_name text NOT NULL,
  -- NULL: every student of the company. With trip_id: who chose that trip on ride_date.
  line_id uuid REFERENCES public.lines(id) ON DELETE CASCADE,
  trip_id uuid REFERENCES public.line_trips(id) ON DELETE SET NULL,
  ride_date date,
  -- Who it went to, as shown: "كل طلاب الشركة", the line, or the line and trip.
  audience text NOT NULL,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 600),
  -- The moment it was sent (not the transaction's start), so the order is exact.
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (trip_id IS NULL OR line_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_notifications_company ON public.notifications(company_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.notification_recipients (
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_student boolean NOT NULL,
  read_at timestamptz,
  PRIMARY KEY (notification_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_notification_recipients_user ON public.notification_recipients(user_id);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_recipients ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notifications, public.notification_recipients FROM PUBLIC, anon, authenticated;

-- A new or deleted notification: the company's staff and the students of the
-- lines it concerns re-read their notifications.
CREATE OR REPLACE FUNCTION public.announce_notification() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.notifications := COALESCE(NEW, OLD);
  v_payload jsonb := jsonb_build_object('table', 'notifications', 'op', TG_OP, 'id', v_row.id,
                                        'company_id', v_row.company_id);
  v_line uuid;
BEGIN
  PERFORM public.announce('company:' || v_row.company_id, v_payload);
  FOR v_line IN SELECT l.id FROM public.lines l
                WHERE l.company_id = v_row.company_id AND (v_row.line_id IS NULL OR l.id = v_row.line_id) LOOP
    PERFORM public.announce('line:' || v_line, v_payload);
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_notification() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_announce_notification ON public.notifications;
CREATE TRIGGER trg_announce_notification AFTER INSERT OR DELETE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.announce_notification();

-- Sends a notification and returns {id, students}. Admins: p_company_id (all its
-- students) or p_line_id. Supervisors: p_line_id of their own, optionally with
-- p_trip_id (+ p_ride_date, today by default; today or the next day).
CREATE OR REPLACE FUNCTION public.send_notification(
  p_title text, p_body text, p_company_id uuid DEFAULT NULL, p_line_id uuid DEFAULT NULL,
  p_trip_id uuid DEFAULT NULL, p_ride_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_supervisor boolean := public.is_supervisor();
  v_line public.lines%ROWTYPE;
  v_trip public.line_trips%ROWTYPE;
  v_company uuid;
  v_date date;
  v_sender text;
  v_audience text;
  v_id uuid;
  v_students integer;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF char_length(btrim(COALESCE(p_title, ''))) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'اكتب عنواناً للإشعار (حتى 80 حرفاً).';
  END IF;
  IF char_length(btrim(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 600 THEN
    RAISE EXCEPTION 'اكتب نص الإشعار (حتى 600 حرف).';
  END IF;
  IF p_line_id IS NOT NULL THEN
    SELECT * INTO v_line FROM public.lines WHERE id = p_line_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.'; END IF;
  END IF;

  IF v_supervisor THEN
    IF p_line_id IS NULL OR NOT EXISTS (
         SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id) THEN
      RAISE EXCEPTION 'اختر خطاً من الخطوط المسندة إليك.';
    END IF;
    v_company := v_line.company_id;
    SELECT s.full_name INTO v_sender FROM public.supervisors s WHERE s.id = v_me;
  ELSE
    v_company := COALESCE(v_line.company_id, p_company_id);
    IF v_company IS NULL OR v_company IS DISTINCT FROM COALESCE(p_company_id, v_company)
       OR NOT public.can_manage_company(v_company) THEN
      RAISE EXCEPTION 'لا يمكنك إرسال إشعارات لهذه الشركة.';
    END IF;
    SELECT a.full_name INTO v_sender FROM public.admins a WHERE a.id = v_me;
  END IF;

  IF p_trip_id IS NOT NULL THEN
    SELECT * INTO v_trip FROM public.line_trips t WHERE t.id = p_trip_id AND t.line_id = p_line_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الرحلة غير موجودة على هذا الخط.'; END IF;
    v_date := COALESCE(p_ride_date, v_today);
    IF v_date NOT BETWEEN v_today AND v_today + 1 THEN
      RAISE EXCEPTION 'يمكن مراسلة ركاب رحلة اليوم أو الغد فقط.';
    END IF;
  ELSIF p_ride_date IS NOT NULL THEN
    RAISE EXCEPTION 'اختر الرحلة.';
  END IF;

  v_audience := CASE
    WHEN p_trip_id IS NOT NULL THEN format('%s · %s %s · %s', v_line.name,
      CASE v_trip.direction WHEN 'return' THEN 'عودة' ELSE 'ذهاب' END,
      to_char(v_trip.start_time, 'FMHH12:MI') || CASE WHEN v_trip.start_time < '12:00' THEN ' ص' ELSE ' م' END,
      -- "8 أكتوبر": a numeric date would flip around in right-to-left text.
      extract(day FROM v_date)::int || ' ' || (ARRAY['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو',
        'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'])[extract(month FROM v_date)::int])
    WHEN p_line_id IS NOT NULL THEN v_line.name
    ELSE 'كل طلاب الشركة' END;

  INSERT INTO public.notifications(company_id, sender_id, sender_role, sender_name, line_id, trip_id,
                                   ride_date, audience, title, body)
  VALUES (v_company, v_me, CASE WHEN v_supervisor THEN 'supervisor' ELSE 'admin' END,
          COALESCE(NULLIF(btrim(v_sender), ''), 'الإدارة'), p_line_id, p_trip_id, v_date, v_audience,
          btrim(p_title), btrim(p_body))
  RETURNING id INTO v_id;

  -- Students: the trip's riders for that day, else every open subscription of the
  -- company (or line) that has not ended.
  INSERT INTO public.notification_recipients(notification_id, user_id, is_student)
  SELECT v_id, x.student_id, true FROM (
    SELECT c.student_id FROM public.rider_trip_choices(v_date) c
    WHERE p_trip_id IS NOT NULL AND c.trip_id = p_trip_id
    UNION
    SELECT s.student_id FROM public.subscriptions s
    WHERE p_trip_id IS NULL AND s.company_id = v_company
      AND (p_line_id IS NULL OR s.line_id = p_line_id)
      AND s.status IN ('pending_payment', 'pending_review', 'active')
      AND (s.end_date IS NULL OR s.end_date >= v_today)
  ) x;
  GET DIAGNOSTICS v_students = ROW_COUNT;
  IF v_students = 0 THEN
    RAISE EXCEPTION 'لا يوجد طلاب يصلهم هذا الإشعار.';
  END IF;

  -- The other supervisors of the lines concerned.
  INSERT INTO public.notification_recipients(notification_id, user_id, is_student)
  SELECT DISTINCT v_id, sl.supervisor_id, false
  FROM public.supervisor_lines sl
  JOIN public.supervisors sv ON sv.id = sl.supervisor_id AND sv.is_active
  JOIN public.lines l ON l.id = sl.line_id
  WHERE l.company_id = v_company AND (p_line_id IS NULL OR sl.line_id = p_line_id)
    AND sl.supervisor_id <> v_me
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('id', v_id, 'students', v_students);
END;
$$;

-- The signed-in student's or supervisor's notifications of the last 60 days,
-- newest first: those they received, and (supervisors) those they sent.
CREATE OR REPLACE FUNCTION public.get_my_notifications(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
  FROM (
    SELECT n.id, n.title, n.body, n.created_at, n.sender_role, n.sender_name, n.audience,
           (r.user_id IS NULL OR r.read_at IS NOT NULL) AS read,
           n.sender_id IS NOT DISTINCT FROM auth.uid() AS mine
    FROM public.notifications n
    LEFT JOIN public.notification_recipients r ON r.notification_id = n.id AND r.user_id = auth.uid()
    WHERE auth.uid() IS NOT NULL
      AND (r.user_id IS NOT NULL OR n.sender_id = auth.uid())
      AND n.created_at > now() - interval '60 days'
    ORDER BY n.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200)
  ) x
$$;

-- Marks the signed-in user's notifications read: those in p_ids, or all.
CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids uuid[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  UPDATE public.notification_recipients
  SET read_at = now()
  WHERE user_id = auth.uid() AND read_at IS NULL
    AND (p_ids IS NULL OR notification_id = ANY (p_ids));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Everything sent in a company (dashboard), with how many students received
-- and read each one.
CREATE OR REPLACE FUNCTION public.get_company_notifications(p_company_id uuid, p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك عرض إشعارات هذه الشركة.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (
      SELECT n.id, n.title, n.body, n.created_at, n.sender_role, n.sender_name, n.audience, n.line_id,
             (SELECT count(*) FROM public.notification_recipients r
              WHERE r.notification_id = n.id AND r.is_student) AS students,
             (SELECT count(*) FROM public.notification_recipients r
              WHERE r.notification_id = n.id AND r.is_student AND r.read_at IS NOT NULL) AS read
      FROM public.notifications n
      WHERE n.company_id = p_company_id
      ORDER BY n.created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500)
    ) x);
END;
$$;

-- A company admin takes a notification back: it disappears for everyone.
CREATE OR REPLACE FUNCTION public.delete_notification(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM public.notifications WHERE id = p_id;
  IF v_company IS NULL OR NOT public.can_manage_company(v_company) THEN
    RAISE EXCEPTION 'لا يمكنك حذف هذا الإشعار.';
  END IF;
  DELETE FROM public.notifications WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.send_notification(text, text, uuid, uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_notifications(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_notifications_read(uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_company_notifications(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_notification(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_notification(text, text, uuid, uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_notifications(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_notifications(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_notification(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 2. Supervisor photos
-- ------------------------------------------------------------------------------
ALTER TABLE public.supervisors ADD COLUMN IF NOT EXISTS profile_image_url text;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('supervisor-avatars', 'supervisor-avatars', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = EXCLUDED.file_size_limit,
                               allowed_mime_types = EXCLUDED.allowed_mime_types;

-- The signed-in student rides one of this supervisor's lines now.
CREATE OR REPLACE FUNCTION public.is_my_supervisor(p_supervisor uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.subscriptions sub
    JOIN public.supervisor_lines sl ON sl.line_id = sub.line_id
    WHERE sub.student_id = auth.uid() AND sub.status = 'active' AND sl.supervisor_id = p_supervisor)
$$;
REVOKE ALL ON FUNCTION public.is_my_supervisor(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_my_supervisor(uuid) TO authenticated;

-- 4. Students read their supervisors through the helper (it reads supervisor_lines
--    for them); everything else as in 20261013000001.
DROP POLICY IF EXISTS supervisors_read_scope ON public.supervisors;
CREATE POLICY supervisors_read_scope ON public.supervisors FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
      OR id = (SELECT auth.uid())
      OR (NOT (SELECT public.is_staff_account()) AND public.is_my_supervisor(id)));

-- The platform and the supervisor's company admins (folder = supervisor id).
CREATE OR REPLACE FUNCTION public.can_manage_supervisor_photo(p_folder text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT public.can_manage_company(s.company_id)
                   FROM public.supervisors s WHERE s.id::text = p_folder), false)
$$;

-- Those, the supervisor, and the students riding one of the supervisor's lines.
CREATE OR REPLACE FUNCTION public.can_view_supervisor_photo(p_folder text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_folder = auth.uid()::text
    OR public.can_manage_supervisor_photo(p_folder)
    OR EXISTS (SELECT 1 FROM public.supervisors s
               WHERE s.id::text = p_folder AND public.is_my_supervisor(s.id)))
$$;
REVOKE ALL ON FUNCTION public.can_manage_supervisor_photo(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_view_supervisor_photo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_supervisor_photo(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_supervisor_photo(text) TO authenticated;

DROP POLICY IF EXISTS supervisor_photos_view ON storage.objects;
DROP POLICY IF EXISTS supervisor_photos_insert ON storage.objects;
DROP POLICY IF EXISTS supervisor_photos_update ON storage.objects;
DROP POLICY IF EXISTS supervisor_photos_delete ON storage.objects;
CREATE POLICY supervisor_photos_view ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'supervisor-avatars' AND public.can_view_supervisor_photo((storage.foldername(name))[1]));
CREATE POLICY supervisor_photos_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'supervisor-avatars' AND public.can_manage_supervisor_photo((storage.foldername(name))[1]));
CREATE POLICY supervisor_photos_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'supervisor-avatars' AND public.can_manage_supervisor_photo((storage.foldername(name))[1]))
  WITH CHECK (bucket_id = 'supervisor-avatars' AND public.can_manage_supervisor_photo((storage.foldername(name))[1]));
CREATE POLICY supervisor_photos_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'supervisor-avatars' AND public.can_manage_supervisor_photo((storage.foldername(name))[1]));

-- ------------------------------------------------------------------------------
-- 3. Check-in: the student's ride vote for the day (as 20261006000001, plus 'ride_vote')
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.supervisor_check_in_student(
  p_qr_code uuid, p_direction text DEFAULT 'departure', p_trip_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_student public.students%ROWTYPE;
  v_sub record;
  v_trip uuid;
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
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result, trip_id)
    VALUES (v_me, v_today, p_direction, 'not_found', p_trip_id);
    RETURN jsonb_build_object('result', 'not_found', 'message', 'رمز QR غير مسجل لأي طالب.');
  END IF;

  -- Students outside the supervisor's lines: log, reveal nothing about them.
  IF NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student.id
      AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
  ) THEN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result, trip_id)
    VALUES (v_me, v_today, p_direction, 'outside_assigned_lines', p_trip_id);
    RETURN jsonb_build_object('result', 'outside_assigned_lines',
      'message', 'هذا الطالب غير مشترك في الخطوط المسندة إليك.');
  END IF;

  SELECT sub.id, sub.line_id, sub.station_id, sub.schedule_id, sub.departure_trip_id, sub.return_trip_id INTO v_sub
  FROM public.subscriptions sub
  WHERE sub.student_id = v_student.id AND sub.status = 'active'
    AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
    AND (sub.start_date IS NULL OR sub.start_date <= v_today)
    AND (sub.end_date IS NULL OR sub.end_date >= v_today)
  ORDER BY sub.created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    v_result := 'no_active_subscription';
    INSERT INTO public.supervisor_scan_events(supervisor_id, student_id, ride_date, direction, result, trip_id)
    VALUES (v_me, v_student.id, v_today, p_direction, v_result, p_trip_id);
  ELSE
    -- The trip being scanned (if it is a trip of this line and direction), else
    -- the student's own trip for this direction.
    SELECT t.id INTO v_trip FROM public.line_trips t
    WHERE t.id = p_trip_id AND t.line_id = v_sub.line_id AND t.direction = p_direction;
    v_trip := COALESCE(v_trip, CASE p_direction WHEN 'departure' THEN v_sub.departure_trip_id ELSE v_sub.return_trip_id END);
    BEGIN
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, trip_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_trip, v_today, p_direction, 'checked_in');
      v_result := 'checked_in';
    EXCEPTION WHEN unique_violation THEN
      -- uq_scan_checkin_once_per_direction: already checked in for this direction today.
      v_result := 'already_checked_in';
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, trip_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_trip, v_today, p_direction, v_result);
    END;
  END IF;

  SELECT e.scanned_at, e.direction INTO v_first FROM public.supervisor_scan_events e
  WHERE e.student_id = v_student.id AND e.ride_date = v_today AND e.direction = p_direction AND e.result = 'checked_in';

  RETURN jsonb_build_object(
    'result', v_result,
    'message', CASE v_result
      WHEN 'checked_in' THEN CASE p_direction WHEN 'return' THEN 'تم تسجيل الطالب في رحلة العودة.' ELSE 'تم تسجيل الطالب في رحلة الذهاب.' END
      WHEN 'already_checked_in' THEN CASE p_direction WHEN 'return' THEN 'تم تسجيل هذا الطالب في رحلة العودة اليوم بالفعل.' ELSE 'تم تسجيل هذا الطالب في رحلة الذهاب اليوم بالفعل.' END
      ELSE 'لا يوجد اشتراك ساري لهذا الطالب اليوم.' END,
    'direction', p_direction,
    'trip_id', v_trip,
    'ride_date', v_today,
    'checked_in_at', v_first.scanned_at,
    'confirmed_ride_today', (SELECT CASE p_direction WHEN 'return' THEN drs.is_riding AND drs.is_returning ELSE drs.is_riding END
                             FROM public.daily_ride_status drs
                             WHERE drs.student_id = v_student.id AND drs.ride_date = v_today),
    'ride_vote', (SELECT jsonb_build_object('is_riding', drs.is_riding, 'is_returning', drs.is_returning,
                                            'departure_time', drs.departure_time, 'return_time', drs.return_time)
                  FROM public.daily_ride_status drs
                  WHERE drs.student_id = v_student.id AND drs.ride_date = v_today),
    'student', public.lookup_student_by_qr(p_qr_code)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) TO authenticated;

COMMIT;
