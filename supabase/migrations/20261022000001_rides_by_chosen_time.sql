-- ==============================================================================
-- Migration: 20261022000001_rides_by_chosen_time.sql
-- Run AFTER 20261021000001. Safe to re-run.
--
-- Supervisors see riders by the trip they chose FOR THE DAY, not by the trip
-- recorded on their subscription (the app now records only the earliest trip
-- at the student's station there). A rider's choice is the stop time at their
-- station they confirmed in daily_ride_status; it belongs to the trip of that
-- line and direction stopping there at that time.
--
-- 1. rider_trip_choices(date): one row per confirmed rider and direction, with
--    the trip their chosen time belongs to (internal helper).
-- 2. get_supervisor_dashboard: trip_times grouped per trip, with the riders per
--    station, per university and the riders themselves.
-- 3. get_supervisor_trip_manifest: students by the trip they chose (plus anyone
--    checked in on it), their chosen time, and who has not confirmed yet.
-- 4. get_line_rider_counts_with_returns: counts by the chosen trips.
-- Existing keys and columns are kept for older app versions; only keys are added.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. The trip each confirmed rider chose for a day, per direction.
-- ------------------------------------------------------------------------------
-- The trip of the rider's line and direction that stops at their station at the
-- time they chose and is open to their university (active trips first, then
-- their university's, then the earliest); else the subscription's trip.
CREATE OR REPLACE FUNCTION public.rider_trip_choices(p_date date)
RETURNS TABLE(student_id uuid, line_id uuid, station_id uuid, subscription_id uuid,
              direction text, chosen_time time, trip_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.student_id, r.line_id, r.station_id, r.subscription_id, x.direction, x.chosen_time,
         COALESCE(
           (SELECT t.id
            FROM public.line_trips t
            JOIN public.line_trip_stops ts ON ts.trip_id = t.id AND ts.station_id = r.station_id
            WHERE t.line_id = r.line_id AND t.direction = x.direction AND ts.stop_time = x.chosen_time
              AND (t.university_id IS NULL OR t.university_id = stu.university_id)
            ORDER BY t.is_active DESC, t.university_id NULLS LAST, t.start_time
            LIMIT 1),
           CASE x.direction WHEN 'departure' THEN sub.departure_trip_id ELSE sub.return_trip_id END)
  FROM public.confirmed_riders(p_date) r
  JOIN public.daily_ride_status drs ON drs.student_id = r.student_id AND drs.ride_date = p_date
  JOIN public.subscriptions sub ON sub.id = r.subscription_id
  JOIN public.students stu ON stu.id = r.student_id
  CROSS JOIN LATERAL (VALUES
    ('departure'::text, COALESCE(drs.departure_time, sub.departure_time)),
    ('return'::text, CASE WHEN drs.is_returning THEN COALESCE(drs.return_time, sub.return_time) END)
  ) AS x(direction, chosen_time)
  WHERE x.chosen_time IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.rider_trip_choices(date) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 2. Supervisor dashboard: trip_times per chosen trip (today and the next ride
--    day), each with its stations, universities and riders.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_supervisor_dashboard()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
  ),
  -- Riders on the supervisor's lines today and the next ride day, by the trip
  -- their chosen time belongs to (no trip: grouped by the time itself).
  rides AS (
    SELECT d.ride_date, c.line_id, l.name AS line_name, c.direction, c.trip_id, c.chosen_time,
           CASE WHEN c.trip_id IS NULL THEN c.chosen_time END AS no_trip_time,
           c.student_id, stu.full_name, stu.phone, c.station_id, st.name AS station_name,
           CASE WHEN c.direction = 'departure' THEN st.order_index ELSE -st.order_index END AS travel_order,
           COALESCE(u.name, NULLIF(stu.university, ''), 'غير محددة') AS university
    FROM (VALUES (v_today), (v_today + 1)) AS d(ride_date)
    CROSS JOIN LATERAL public.rider_trip_choices(d.ride_date) c
    JOIN public.lines l ON l.id = c.line_id
    JOIN public.students stu ON stu.id = c.student_id
    LEFT JOIN public.universities u ON u.id = stu.university_id
    LEFT JOIN public.stations st ON st.id = c.station_id
    WHERE c.line_id IN (SELECT line_id FROM assigned)
  )
  SELECT jsonb_build_object(
    'today', v_today,
    'profile', (
      SELECT jsonb_build_object(
        'id', s.id, 'full_name', s.full_name, 'phone', s.phone, 'is_active', s.is_active,
        'created_at', s.created_at, 'company_id', s.company_id, 'company_name', c.name,
        'company_active', c.is_active,
        'assignment', CASE WHEN EXISTS (SELECT 1 FROM assigned) THEN 'direct' ELSE 'none' END,
        'vote', public.get_vote_settings(s.company_id))
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
    -- Students per trip on the supervisor's lines, by the trip each student chose
    -- for the day: today and, once tomorrow's vote has opened, the next ride day.
    -- 'time' is when the trip leaves (the chosen time when it matches no trip).
    'trip_times', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'ride_date', g.ride_date, 'line_id', g.line_id, 'line_name', g.line_name,
          'direction', g.direction, 'time', g.trip_time, 'students', g.students,
          'trip_id', g.trip_id, 'label', g.label, 'university', g.university,
          -- Travel order: every active stop of the trip (0 riders allowed) and any
          -- other station a rider boards at (no stop time).
          'stations', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', st.id, 'name', st.name, 'order_index', st.order_index, 'stop_time', ts.stop_time,
                'students', (SELECT count(*) FROM rides r
                             WHERE r.ride_date = g.ride_date AND r.line_id = g.line_id AND r.direction = g.direction
                               AND r.trip_id IS NOT DISTINCT FROM g.trip_id
                               AND r.no_trip_time IS NOT DISTINCT FROM g.no_trip_time
                               AND r.station_id = st.id))
              ORDER BY CASE WHEN g.direction = 'departure' THEN st.order_index ELSE -st.order_index END, st.name), '[]'::jsonb)
            FROM public.stations st
            LEFT JOIN public.line_trip_stops ts ON ts.trip_id = g.trip_id AND ts.station_id = st.id
            WHERE (st.line_id = g.line_id AND st.is_active AND ts.trip_id IS NOT NULL)
               OR st.id IN (SELECT r.station_id FROM rides r
                            WHERE r.ride_date = g.ride_date AND r.line_id = g.line_id AND r.direction = g.direction
                              AND r.trip_id IS NOT DISTINCT FROM g.trip_id
                              AND r.no_trip_time IS NOT DISTINCT FROM g.no_trip_time)),
          'universities', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('name', x.name, 'students', x.students)
                                      ORDER BY x.students DESC, x.name), '[]'::jsonb)
            FROM (SELECT r.university AS name, count(*) AS students FROM rides r
                  WHERE r.ride_date = g.ride_date AND r.line_id = g.line_id AND r.direction = g.direction
                    AND r.trip_id IS NOT DISTINCT FROM g.trip_id
                    AND r.no_trip_time IS NOT DISTINCT FROM g.no_trip_time
                  GROUP BY r.university) x),
          'riders', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', r.student_id, 'full_name', r.full_name, 'phone', r.phone,
                'station_id', r.station_id, 'station', r.station_name, 'university', r.university,
                'time', r.chosen_time)
              ORDER BY r.travel_order, r.full_name), '[]'::jsonb)
            FROM rides r
            WHERE r.ride_date = g.ride_date AND r.line_id = g.line_id AND r.direction = g.direction
              AND r.trip_id IS NOT DISTINCT FROM g.trip_id
              AND r.no_trip_time IS NOT DISTINCT FROM g.no_trip_time))
        ORDER BY g.ride_date, g.direction, g.trip_time, g.line_name, g.label, g.university)
      FROM (
        SELECT r.ride_date, r.line_id, r.line_name, r.direction, r.trip_id, r.no_trip_time,
               COALESCE(t.start_time, r.no_trip_time) AS trip_time, COALESCE(t.label, '') AS label,
               tu.name AS university, count(DISTINCT r.student_id) AS students
        FROM rides r
        LEFT JOIN public.line_trips t ON t.id = r.trip_id
        LEFT JOIN public.universities tu ON tu.id = t.university_id
        GROUP BY r.ride_date, r.line_id, r.line_name, r.direction, r.trip_id, r.no_trip_time,
                 t.start_time, t.label, tu.name
      ) g), '[]'::jsonb),
    'lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'name', l.name, 'is_active', l.is_active,
        'directly_assigned', true,
        'price_termly', l.price_termly, 'price_yearly', l.price_yearly, 'price_daily', l.price_daily,
        'registered_students', (SELECT count(*) FROM active_subs a WHERE a.line_id = l.id),
        'confirmed_today', (SELECT count(*) FROM active_subs a JOIN public.daily_ride_status drs
                              ON drs.student_id = a.student_id AND drs.ride_date = v_today AND drs.is_riding
                            WHERE a.line_id = l.id),
        -- Departure trips (university, start time, riders) for the Home screen;
        -- 'trips' carries both directions.
        'schedules', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
                      FROM jsonb_array_elements(public.line_trips_summary(l.id, v_today)) x
                      WHERE x->>'direction' = 'departure'),
        'trips', public.line_trips_summary(l.id, v_today),
        'origin_name', l.origin_name,
        'destination', (SELECT name FROM public.universities WHERE id = l.destination_university_id),
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

-- ------------------------------------------------------------------------------
-- 3. Trip manifest (Going or Return) by the trip each student chose for the day.
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
  v_data jsonb;
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

  -- The riders of this line and direction on v_date and the trip they chose.
  WITH choices AS (
    SELECT c.student_id, c.station_id, c.chosen_time, c.trip_id
    FROM public.rider_trip_choices(v_date) c
    WHERE c.line_id = p_line_id AND c.direction = p_direction
  )
  SELECT jsonb_build_object(
    'line', jsonb_build_object('id', v_line.id, 'name', v_line.name, 'origin_name', COALESCE(v_line.origin_name, v_line.name),
      'destination', (SELECT name FROM public.universities WHERE id = v_line.destination_university_id)),
    'direction', p_direction,
    'ride_date', v_date,
    'trips', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'label', t.label, 'start_time', t.start_time, 'arrival_time', t.arrival_time,
        'university', u.name,
        'students', (SELECT count(*) FROM choices c WHERE c.trip_id = t.id))
        ORDER BY t.start_time)
      FROM public.line_trips t LEFT JOIN public.universities u ON u.id = t.university_id
      WHERE t.line_id = p_line_id AND t.direction = p_direction AND t.is_active), '[]'::jsonb),
    'trip', CASE WHEN v_trip.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_trip.id, 'label', v_trip.label, 'start_time', v_trip.start_time, 'arrival_time', v_trip.arrival_time,
      'university', (SELECT name FROM public.universities WHERE id = v_trip.university_id)) END,
    'stations', CASE WHEN v_trip.id IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', st.id, 'name', st.name, 'order_index', st.order_index, 'stop_time', ts.stop_time,
        -- Who chose this trip at this station, and anyone checked in on it here.
        'students', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', stu.id, 'full_name', stu.full_name, 'phone', stu.phone, 'university', stu.university,
            'confirmed', m.confirmed,
            'chosen_time', (SELECT c.chosen_time FROM choices c WHERE c.student_id = stu.id LIMIT 1),
            'checked_in_at', (SELECT min(e.scanned_at) FROM public.supervisor_scan_events e
                              WHERE e.student_id = stu.id AND e.ride_date = v_date AND e.direction = p_direction
                                AND e.result = 'checked_in'))
            ORDER BY stu.full_name)
          FROM (
            SELECT c.student_id, true AS confirmed FROM choices c
            WHERE c.trip_id = v_trip.id AND c.station_id = st.id
            UNION
            SELECT e.student_id, false FROM public.supervisor_scan_events e
            WHERE e.result = 'checked_in' AND e.ride_date = v_date AND e.direction = p_direction
              AND e.trip_id = v_trip.id AND e.station_id = st.id AND e.student_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM choices c WHERE c.student_id = e.student_id AND c.trip_id = v_trip.id)
          ) m JOIN public.students stu ON stu.id = m.student_id), '[]'::jsonb))
        -- Travel order: forward for Going, reversed for Return.
        ORDER BY CASE WHEN p_direction = 'departure' THEN st.order_index ELSE -st.order_index END)
      FROM public.stations st
      LEFT JOIN public.line_trip_stops ts ON ts.station_id = st.id AND ts.trip_id = v_trip.id
      WHERE st.line_id = p_line_id AND st.is_active), '[]'::jsonb) END,
    -- Subscribed for v_date but no ride vote at all, and not checked in for this direction.
    'unconfirmed', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
          'id', x.id, 'full_name', x.full_name, 'phone', x.phone, 'university', x.university, 'station', x.station)
        ORDER BY x.order_index, x.full_name)
      FROM (
        SELECT DISTINCT ON (stu.id) stu.id, stu.full_name, stu.phone, stu.university,
               st.name AS station, st.order_index
        FROM public.subscriptions s
        JOIN public.students stu ON stu.id = s.student_id
        LEFT JOIN public.stations st ON st.id = s.station_id
        WHERE s.line_id = p_line_id AND s.status = 'active'
          AND COALESCE(s.start_date, v_date) <= v_date AND COALESCE(s.end_date, v_date) >= v_date
          AND NOT EXISTS (SELECT 1 FROM public.daily_ride_status drs
                          WHERE drs.student_id = stu.id AND drs.ride_date = v_date)
          AND NOT EXISTS (SELECT 1 FROM public.supervisor_scan_events e
                          WHERE e.student_id = stu.id AND e.ride_date = v_date AND e.direction = p_direction
                            AND e.result = 'checked_in')
        ORDER BY stu.id, s.created_at DESC
      ) x), '[]'::jsonb)
  ) INTO v_data;
  RETURN v_data;
END;
$$;
REVOKE ALL ON FUNCTION public.get_supervisor_trip_manifest(uuid, text, uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supervisor_trip_manifest(uuid, text, uuid, date) TO authenticated;

-- ------------------------------------------------------------------------------
-- 4. Rider counts per station and departure trip, by the trips riders chose.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_line_rider_counts_with_returns(p_line_id uuid, p_ride_date date)
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
  WITH choices AS (
    SELECT c.student_id, c.station_id, c.direction, c.chosen_time, c.trip_id
    FROM public.rider_trip_choices(p_ride_date) c
    WHERE c.line_id = p_line_id
  ),
  -- Departure riders with their return time (NULL = not returning).
  riders AS (
    SELECT d.student_id, d.station_id, d.trip_id, r.chosen_time AS back_time
    FROM choices d
    LEFT JOIN choices r ON r.student_id = d.student_id AND r.direction = 'return'
    WHERE d.direction = 'departure'
  )
  SELECT l.id, l.name, st.id, st.name, st.order_index,
    ts.stop_time,
    MIN(rd.back_time),
    COUNT(rd.student_id),
    COUNT(rd.back_time),
    t.id,
    NULLIF(concat_ws(' · ', NULLIF(t.label, ''), u.name), '')
  FROM public.line_trips t
  JOIN public.line_trip_stops ts ON ts.trip_id = t.id
  JOIN public.stations st ON st.id = ts.station_id AND st.is_active
  JOIN public.lines l ON l.id = t.line_id
  LEFT JOIN public.universities u ON u.id = t.university_id
  LEFT JOIN riders rd ON rd.station_id = st.id AND rd.trip_id = t.id
  WHERE t.line_id = p_line_id AND t.direction = 'departure' AND l.is_active
    AND (t.is_active OR EXISTS (SELECT 1 FROM riders v WHERE v.trip_id = t.id))
  GROUP BY l.id, l.name, st.id, st.name, st.order_index, ts.stop_time, t.id, t.label, t.start_time, u.name
  ORDER BY t.start_time, st.order_index;
END;
$$;

COMMIT;
