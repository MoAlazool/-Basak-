-- ==============================================================================
-- Migration: 20261104000001_check_in_without_details.sql
-- Run AFTER 20261103000001. Safe to re-run. The app's call and answer are unchanged.
--
-- Fix: scanning a student whose subscription on the supervisor's line is not
-- active (expired, pending) failed with "Student is outside your assigned
-- lines.": supervisor_check_in_student ends by attaching the student's details
-- from lookup_student_by_qr, which refuses those students to a supervisor. The
-- whole scan was rolled back (not even logged) and the app showed only
-- "تعذر التحقق من الرمز" instead of "no active subscription".
-- Now the answer carries no details when the lookup refuses ('student': null);
-- the rest is as 20261023000001.
-- ==============================================================================
BEGIN;

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
  v_details jsonb;
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

  -- The student's details as this supervisor may see them: lookup_student_by_qr
  -- shows a supervisor only students with an active subscription on their
  -- lines and refuses the rest, which used to fail the whole scan.
  BEGIN
    v_details := public.lookup_student_by_qr(p_qr_code);
  EXCEPTION WHEN raise_exception THEN
    v_details := NULL;
  END;

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
    'student', v_details
  );
END;
$$;

REVOKE ALL ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) TO authenticated;

COMMIT;
