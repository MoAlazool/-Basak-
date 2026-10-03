-- ==============================================================================
-- Migration: 20261003000001_supervisor_app.sql
-- Run AFTER 20261002000004_line_university_schedules.sql. Safe to re-run.
--
-- Backend for the Android Supervisor Interface:
--   1. Assignment scope: a supervisor works the lines assigned to them
--      (lines.supervisor_id). With no direct assignment they cover every line of
--      their company (previous behaviour). Inactive supervisors get nothing.
--   2. supervisor_scan_events: every QR scan and the resulting check-in
--      (one check-in per student, ride date and direction).
--   3. RPCs: supervisor_check_in_student, get_supervisor_dashboard,
--      get_supervisor_monthly_summary. All scoped to auth.uid().
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Assignment scope
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_supervisor_assigned_line_ids()
RETURNS TABLE (line_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH me AS (
    SELECT s.id, s.company_id FROM public.supervisors s WHERE s.id = auth.uid() AND s.is_active
  ), direct AS (
    SELECT l.id FROM public.lines l JOIN me ON l.supervisor_id = me.id AND l.company_id = me.company_id
  )
  SELECT id FROM direct
  UNION
  SELECT l.id FROM public.lines l JOIN me ON l.company_id = me.company_id
  WHERE NOT EXISTS (SELECT 1 FROM direct)
$$;

-- A line can only be assigned to an active supervisor of the same company.
CREATE OR REPLACE FUNCTION public.validate_line_supervisor()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.supervisor_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.supervisors s
    WHERE s.id = NEW.supervisor_id AND s.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'المشرف المختار لا يتبع شركة هذا الخط.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_validate_line_supervisor ON public.lines;
CREATE TRIGGER trg_validate_line_supervisor
BEFORE INSERT OR UPDATE OF supervisor_id, company_id ON public.lines
FOR EACH ROW EXECUTE FUNCTION public.validate_line_supervisor();

-- ------------------------------------------------------------------------------
-- 2. Scan / check-in log
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.supervisor_scan_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id uuid NOT NULL REFERENCES public.supervisors(id) ON DELETE CASCADE,
  student_id uuid REFERENCES public.students(id) ON DELETE SET NULL,
  subscription_id uuid REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  line_id uuid REFERENCES public.lines(id) ON DELETE SET NULL,
  station_id uuid REFERENCES public.stations(id) ON DELETE SET NULL,
  schedule_id uuid REFERENCES public.line_university_schedules(id) ON DELETE SET NULL,
  ride_date date NOT NULL,
  direction text NOT NULL CHECK (direction IN ('departure', 'return')),
  result text NOT NULL CHECK (result IN (
    'checked_in', 'already_checked_in', 'no_active_subscription', 'outside_assigned_lines', 'not_found')),
  scanned_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_scan_checkin_once
  ON public.supervisor_scan_events(student_id, ride_date, direction) WHERE result = 'checked_in';
CREATE INDEX IF NOT EXISTS idx_scan_events_supervisor_date ON public.supervisor_scan_events(supervisor_id, ride_date);
CREATE INDEX IF NOT EXISTS idx_scan_events_line_date ON public.supervisor_scan_events(line_id, ride_date);

ALTER TABLE public.supervisor_scan_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.supervisor_scan_events FROM anon;
GRANT SELECT ON public.supervisor_scan_events TO authenticated;  -- writes only via RPC

DROP POLICY IF EXISTS scan_events_read_scope ON public.supervisor_scan_events;
CREATE POLICY scan_events_read_scope ON public.supervisor_scan_events FOR SELECT TO authenticated
USING (
  supervisor_id = auth.uid()
  OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.supervisors s
    WHERE s.id = supervisor_scan_events.supervisor_id AND s.company_id = public.current_admin_company_id()))
);

-- ------------------------------------------------------------------------------
-- 3a. Scan a QR and check the student in.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.supervisor_check_in_student(p_qr_code uuid, p_direction text DEFAULT 'departure')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_student public.students%ROWTYPE;
  v_sub record;
  v_result text;
  v_event_id uuid;
  v_first timestamptz;
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
    RETURN jsonb_build_object('result', 'not_found');
  END IF;

  -- Students outside the supervisor's lines: log, reveal nothing about them.
  IF NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student.id
      AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
  ) THEN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result)
    VALUES (v_me, v_today, p_direction, 'outside_assigned_lines');
    RETURN jsonb_build_object('result', 'outside_assigned_lines');
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
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_today, p_direction, 'checked_in')
      RETURNING id INTO v_event_id;
      v_result := 'checked_in';
    EXCEPTION WHEN unique_violation THEN
      v_result := 'already_checked_in';
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_today, p_direction, v_result);
    END;
  END IF;

  SELECT min(e.scanned_at) INTO v_first FROM public.supervisor_scan_events e
  WHERE e.student_id = v_student.id AND e.ride_date = v_today AND e.direction = p_direction AND e.result = 'checked_in';

  RETURN jsonb_build_object(
    'result', v_result,
    'direction', p_direction,
    'ride_date', v_today,
    'checked_in_at', v_first,
    'confirmed_ride_today', (SELECT drs.is_riding FROM public.daily_ride_status drs
                             WHERE drs.student_id = v_student.id AND drs.ride_date = v_today),
    'student', public.lookup_student_by_qr(p_qr_code)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.supervisor_check_in_student(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_check_in_student(uuid, text) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3b. Home + profile data in one call.
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
        'assignment', CASE WHEN EXISTS (SELECT 1 FROM public.lines l WHERE l.supervisor_id = s.id)
                           THEN 'direct' ELSE 'company' END)
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
                           WHERE e.supervisor_id = v_me AND e.ride_date = v_today AND e.result = 'checked_in'),
      'pending_payment', (SELECT count(*) FROM public.subscriptions sub
                          WHERE sub.status IN ('pending_payment', 'pending_review')
                            AND sub.line_id IN (SELECT line_id FROM assigned)),
      'pending_receipts', (SELECT count(*) FROM public.receipts r JOIN public.subscriptions sub ON sub.id = r.subscription_id
                           WHERE r.status = 'pending' AND sub.line_id IN (SELECT line_id FROM assigned))),
    'lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'name', l.name, 'is_active', l.is_active,
        'directly_assigned', COALESCE(l.supervisor_id = v_me, false),
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
                                 WHERE e.station_id = st.id AND e.ride_date = v_today AND e.result = 'checked_in'
                                   AND e.direction = 'departure'))
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
-- 3c. Monthly activity summary of the calling supervisor.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_supervisor_monthly_summary(p_month date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_start date := date_trunc('month', COALESCE(p_month, public.cairo_today()))::date;
  v_end date := (date_trunc('month', COALESCE(p_month, public.cairo_today())) + INTERVAL '1 month - 1 day')::date;
  v_last date;
  v_data jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.supervisors WHERE id = v_me) THEN
    RAISE EXCEPTION 'هذا الحساب ليس حساب مشرف.';
  END IF;
  v_last := LEAST(v_end, public.cairo_today());

  WITH ev AS (
    SELECT * FROM public.supervisor_scan_events
    WHERE supervisor_id = v_me AND ride_date BETWEEN v_start AND v_end
  ),
  line_students AS (
    SELECT DISTINCT sub.student_id FROM public.subscriptions sub
    WHERE sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
  ),
  confirmed AS (
    SELECT drs.ride_date, count(*) AS n FROM public.daily_ride_status drs
    WHERE drs.is_riding AND drs.ride_date BETWEEN v_start AND v_end
      AND drs.student_id IN (SELECT student_id FROM line_students)
    GROUP BY drs.ride_date
  ),
  days AS (SELECT d::date AS day FROM generate_series(v_start, GREATEST(v_last, v_start), INTERVAL '1 day') d)
  SELECT jsonb_build_object(
    'month', v_start,
    'month_end', v_end,
    'totals', jsonb_build_object(
      'checkins', (SELECT count(*) FROM ev WHERE result = 'checked_in'),
      'departure_checkins', (SELECT count(*) FROM ev WHERE result = 'checked_in' AND direction = 'departure'),
      'return_checkins', (SELECT count(*) FROM ev WHERE result = 'checked_in' AND direction = 'return'),
      'unique_students', (SELECT count(DISTINCT student_id) FROM ev WHERE result = 'checked_in'),
      'scans', (SELECT count(*) FROM ev),
      'duplicate_scans', (SELECT count(*) FROM ev WHERE result = 'already_checked_in'),
      'rejected_scans', (SELECT count(*) FROM ev WHERE result IN ('no_active_subscription', 'outside_assigned_lines', 'not_found')),
      'active_days', (SELECT count(DISTINCT ride_date) FROM ev WHERE result = 'checked_in'),
      'confirmed_rides', (SELECT COALESCE(sum(n), 0) FROM confirmed)),
    'results', COALESCE((SELECT jsonb_object_agg(result, n) FROM (SELECT result, count(*) n FROM ev GROUP BY result) r), '{}'::jsonb),
    'days', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'date', d.day,
        'checkins', (SELECT count(*) FROM ev WHERE ev.ride_date = d.day AND result = 'checked_in'),
        'departure', (SELECT count(*) FROM ev WHERE ev.ride_date = d.day AND result = 'checked_in' AND direction = 'departure'),
        'return', (SELECT count(*) FROM ev WHERE ev.ride_date = d.day AND result = 'checked_in' AND direction = 'return'),
        'scans', (SELECT count(*) FROM ev WHERE ev.ride_date = d.day),
        'confirmed', COALESCE((SELECT n FROM confirmed WHERE confirmed.ride_date = d.day), 0))
        ORDER BY d.day)
      FROM days d WHERE d.day <= v_last), '[]'::jsonb),
    'stations', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('station', st.name, 'line', l.name, 'checkins', x.n) ORDER BY x.n DESC)
      FROM (SELECT station_id, count(*) n FROM ev WHERE result = 'checked_in' AND station_id IS NOT NULL GROUP BY station_id) x
      JOIN public.stations st ON st.id = x.station_id JOIN public.lines l ON l.id = st.line_id), '[]'::jsonb)
  ) INTO v_data;

  RETURN v_data;
END;
$$;
REVOKE ALL ON FUNCTION public.get_supervisor_monthly_summary(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supervisor_monthly_summary(date) TO authenticated;

COMMIT;
