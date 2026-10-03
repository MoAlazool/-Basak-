-- ==============================================================================
-- Migration: 20261006000001_trip_directions_and_company.sql
-- Run AFTER 20261005000001_line_trips.sql. Safe to re-run.
--
-- 1. Going / Return attendance: one check-in per student, ride date AND
--    direction (supersedes the once-per-day rule of 20261004000001), each
--    recorded against the trip it belongs to (supervisor_scan_events.trip_id).
-- 2. get_supervisor_trip_manifest: one trip of one direction — route in travel
--    order, stop times, students per station, checked in / not yet.
-- 3. subscriptions.company_id: the company is stored with every subscription.
-- 4. get_student_catalog: companies → active lines available to the student,
--    with route, stations and trip times (subscription flow step 1-2).
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Attendance per direction and trip
-- ------------------------------------------------------------------------------
ALTER TABLE public.supervisor_scan_events
  ADD COLUMN IF NOT EXISTS trip_id uuid REFERENCES public.line_trips(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_scan_events_trip_date ON public.supervisor_scan_events(trip_id, ride_date);

UPDATE public.supervisor_scan_events e
SET trip_id = CASE e.direction WHEN 'departure' THEN s.departure_trip_id ELSE s.return_trip_id END
FROM public.subscriptions s
WHERE e.trip_id IS NULL AND s.id = e.subscription_id;

DROP INDEX IF EXISTS public.uq_scan_checkin_once_per_day;
CREATE UNIQUE INDEX IF NOT EXISTS uq_scan_checkin_once_per_direction
  ON public.supervisor_scan_events(student_id, ride_date, direction) WHERE result = 'checked_in';

DROP FUNCTION IF EXISTS public.supervisor_check_in_student(uuid, text);
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
    'student', public.lookup_student_by_qr(p_qr_code)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- 2. Trip manifest (Going or Return)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_supervisor_trip_manifest(
  p_line_id uuid, p_direction text DEFAULT 'departure', p_trip_id uuid DEFAULT NULL, p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_date date := COALESCE(p_date, public.cairo_today());
  v_now time := (now() AT TIME ZONE 'Africa/Cairo')::time;
  v_trip public.line_trips%ROWTYPE;
  v_line public.lines%ROWTYPE;
BEGIN
  IF p_direction NOT IN ('departure', 'return') THEN
    RAISE EXCEPTION 'اتجاه الرحلة غير صحيح.';
  END IF;
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;
  SELECT * INTO v_line FROM public.lines WHERE id = p_line_id;

  -- Chosen trip, else the next one still to leave today, else the first.
  SELECT * INTO v_trip FROM public.line_trips t
  WHERE t.line_id = p_line_id AND t.direction = p_direction AND t.is_active
    AND (p_trip_id IS NULL OR t.id = p_trip_id)
  ORDER BY (p_trip_id IS NULL AND t.start_time < v_now - INTERVAL '30 minutes'), t.start_time
  LIMIT 1;

  RETURN jsonb_build_object(
    'line', jsonb_build_object('id', v_line.id, 'name', v_line.name, 'origin_name', COALESCE(v_line.origin_name, v_line.name),
      'destination', (SELECT name FROM public.universities WHERE id = v_line.destination_university_id)),
    'direction', p_direction,
    'ride_date', v_date,
    'trips', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'label', t.label, 'start_time', t.start_time, 'arrival_time', t.arrival_time,
        'university', u.name,
        'students', (SELECT count(*) FROM public.subscriptions s
          WHERE s.status = 'active' AND COALESCE(s.start_date, v_date) <= v_date AND COALESCE(s.end_date, v_date) >= v_date
            AND (CASE p_direction WHEN 'departure' THEN s.departure_trip_id ELSE s.return_trip_id END) = t.id))
        ORDER BY t.start_time)
      FROM public.line_trips t LEFT JOIN public.universities u ON u.id = t.university_id
      WHERE t.line_id = p_line_id AND t.direction = p_direction AND t.is_active), '[]'::jsonb),
    'trip', CASE WHEN v_trip.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_trip.id, 'label', v_trip.label, 'start_time', v_trip.start_time, 'arrival_time', v_trip.arrival_time,
      'university', (SELECT name FROM public.universities WHERE id = v_trip.university_id)) END,
    'stations', CASE WHEN v_trip.id IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', st.id, 'name', st.name, 'order_index', st.order_index, 'stop_time', ts.stop_time,
        'students', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', stu.id, 'full_name', stu.full_name, 'phone', stu.phone, 'university', stu.university,
            'confirmed', COALESCE((SELECT CASE p_direction WHEN 'return' THEN drs.is_riding AND drs.is_returning ELSE drs.is_riding END
                                   FROM public.daily_ride_status drs WHERE drs.student_id = stu.id AND drs.ride_date = v_date), false),
            'checked_in_at', (SELECT min(e.scanned_at) FROM public.supervisor_scan_events e
                              WHERE e.student_id = stu.id AND e.ride_date = v_date AND e.direction = p_direction
                                AND e.result = 'checked_in'))
            ORDER BY stu.full_name)
          FROM public.subscriptions s JOIN public.students stu ON stu.id = s.student_id
          WHERE s.station_id = st.id AND s.status = 'active'
            AND COALESCE(s.start_date, v_date) <= v_date AND COALESCE(s.end_date, v_date) >= v_date
            AND (CASE p_direction WHEN 'departure' THEN s.departure_trip_id ELSE s.return_trip_id END) = v_trip.id), '[]'::jsonb))
        -- Travel order: forward for Going, reversed for Return.
        ORDER BY CASE WHEN p_direction = 'departure' THEN st.order_index ELSE -st.order_index END)
      FROM public.stations st
      LEFT JOIN public.line_trip_stops ts ON ts.station_id = st.id AND ts.trip_id = v_trip.id
      WHERE st.line_id = p_line_id AND st.is_active), '[]'::jsonb) END
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_supervisor_trip_manifest(uuid, text, uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supervisor_trip_manifest(uuid, text, uuid, date) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. Company stored with every subscription (always the line's company)
-- ------------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE RESTRICT;
UPDATE public.subscriptions s SET company_id = l.company_id
FROM public.lines l WHERE l.id = s.line_id AND s.company_id IS DISTINCT FROM l.company_id;
CREATE INDEX IF NOT EXISTS idx_subscriptions_company ON public.subscriptions(company_id);

CREATE OR REPLACE FUNCTION public.set_subscription_company()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM public.lines WHERE id = NEW.line_id;
  IF NEW.company_id IS NOT NULL AND NEW.company_id IS DISTINCT FROM v_company THEN
    RAISE EXCEPTION 'الخط المختار لا يتبع الشركة المختارة.' USING ERRCODE = '23514';
  END IF;
  NEW.company_id := v_company;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_set_subscription_company ON public.subscriptions;
CREATE TRIGGER trg_set_subscription_company
BEFORE INSERT OR UPDATE OF line_id, company_id ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.set_subscription_company();

-- ------------------------------------------------------------------------------
-- 4. Student catalogue: company → lines (active, serving the student)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_student_catalog()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH my_lines AS (
    SELECT l.* FROM public.lines l
    JOIN public.companies c ON c.id = l.company_id AND c.is_active
    WHERE l.is_active AND auth.uid() IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.line_trips t
                  WHERE t.line_id = l.id AND t.direction = 'departure' AND public.trip_serves_student(t, auth.uid()))
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name,
      'lines', (SELECT jsonb_agg(jsonb_build_object(
          'id', l.id, 'name', l.name, 'origin_name', COALESCE(l.origin_name, l.name),
          'destination', (SELECT name FROM public.universities WHERE id = l.destination_university_id),
          'price_termly', l.price_termly, 'price_yearly', l.price_yearly, 'price_daily', l.price_daily,
          'stations', (SELECT COALESCE(jsonb_agg(st.name ORDER BY st.order_index), '[]'::jsonb)
                       FROM public.stations st WHERE st.line_id = l.id AND st.is_active),
          'departure_times', (SELECT COALESCE(jsonb_agg(t.start_time ORDER BY t.start_time), '[]'::jsonb)
                              FROM public.line_trips t WHERE t.line_id = l.id AND t.direction = 'departure'
                                AND public.trip_serves_student(t, auth.uid())),
          'return_times', (SELECT COALESCE(jsonb_agg(t.start_time ORDER BY t.start_time), '[]'::jsonb)
                           FROM public.line_trips t WHERE t.line_id = l.id AND t.direction = 'return'
                             AND public.trip_serves_student(t, auth.uid())))
        ORDER BY l.name)
        FROM my_lines l WHERE l.company_id = c.id))
    ORDER BY c.name), '[]'::jsonb)
  FROM public.companies c
  WHERE EXISTS (SELECT 1 FROM my_lines l WHERE l.company_id = c.id)
$$;
REVOKE ALL ON FUNCTION public.get_student_catalog() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_catalog() TO authenticated;

COMMIT;
