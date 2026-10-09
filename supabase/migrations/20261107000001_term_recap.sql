-- ==============================================================================
-- Migration: 20261107000001_term_recap.sql
-- Run AFTER 20261104000001 (it reads students.specialisation). Safe to re-run.
-- Additive: one new function, nothing else.
--
-- get_my_term_recap(): everything the student's end-of-term recap is built
-- from, in one answer, for the signed-in student only. It takes no student id:
-- every row it reads is filtered by auth.uid().
--
-- Which term: the period of p_subscription_id (one of the caller's own), or of
-- their running subscription, or the newest one that ended. "Both semesters"
-- gives the semester that is running (or the last one that started). p_from /
-- p_to replace the term's dates when given. Rides are counted up to today.
--
-- Answer:
--   today
--   student      {full_name, first_name, university, college, specialisation}
--   term         {code, academic_year, name, label, start_date, end_date}   (nulls when no term is known)
--   range        {from, to, until}       until = the earlier of `to` and today
--   subscription {id, type, status, period_code, academic_year, start_date, end_date, created_at, paid_at} | null
--   rides        [{date, weekday, departure_time, return_time, returns_by_bus, line_id, station_id,
--                  departure_minutes, boarded_departure, boarded_return}]   one per confirmed ride day, by date
--   summary      {ride_days, return_days, boarded_departures, boarded_returns, first_ride_date, last_ride_date}
--   line         {id, name, company_id, company_name, stations: [{id, name, order_index}]} | null   the most used line
--   stop         {id, name, order_index, rides, stops_used} | null                                   the most used stop
--   timetable    {departure_times: ["07:10", …], return_times: ["15:00", …]}   today's timetable at that stop
--   trip_length  {departure_minutes, return_minutes}
--   off          {weekdays: [5], dates: ["2026-10-06", …]}
--
-- weekday and off.weekdays are ISO numbers (1 = Monday … 7 = Sunday), as in the
-- vote settings. Times are "HH:MM".
--
-- What the data cannot give:
--   * The way back has no arrival time (a return trip is only when the bus
--     leaves the university), so trip_length.return_minutes is always null.
--   * departure_minutes of a ride is the stop-to-arrival time of the trip that
--     stops at the student's station at the time they chose, read from TODAY's
--     timetable. It is null when that trip has no arrival time, or when the
--     timetable has changed since the ride. trip_length.departure_minutes is the
--     average for the most used stop, to use where a ride has none.
--   * off.dates holds the official holidays that are still stored. The settings
--     keep only upcoming holidays: each time they are saved, past dates are
--     dropped, so holidays earlier in the term can be missing.
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_term_recap(
  p_subscription_id uuid DEFAULT NULL, p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_year integer := extract(year FROM public.cairo_today())::integer;
  v_student public.students%ROWTYPE;
  v_sub public.subscriptions%ROWTYPE;
  v_company uuid;
  v_term_code text;
  v_term_year integer;
  v_term_name text;
  v_term_label text;
  v_term_start date;
  v_term_end date;
  v_from date;
  v_to date;
  v_until date;
  v_rides jsonb;
  v_line uuid;
  v_station uuid;
  v_typical integer;
  v_off_weekdays integer[];
  v_off_dates date[];
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'متاح للطلاب فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_student FROM public.students WHERE id = v_me;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'متاح للطلاب فقط.' USING ERRCODE = '42501';
  END IF;

  -- ---- the subscription the recap is about -------------------------------
  IF p_subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub FROM public.subscriptions WHERE id = p_subscription_id AND student_id = v_me;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الاشتراك غير موجود.' USING ERRCODE = 'P0002';
    END IF;
  ELSE
    SELECT sub.* INTO v_sub
    FROM public.subscriptions sub
    WHERE sub.student_id = v_me AND sub.status IN ('active', 'expired') AND sub.type <> 'daily'
      AND COALESCE(sub.start_date, v_today) <= v_today
    ORDER BY (sub.status = 'active') DESC, sub.start_date DESC NULLS LAST, sub.created_at DESC
    LIMIT 1;
  END IF;
  v_company := v_sub.company_id;
  IF v_company IS NULL THEN
    SELECT drs.company_id INTO v_company
    FROM public.daily_ride_status drs
    WHERE drs.student_id = v_me AND drs.is_riding
    ORDER BY drs.ride_date DESC LIMIT 1;
  END IF;

  -- ---- the term ----------------------------------------------------------
  -- A semester subscription: its own semester. Both semesters: the one that is
  -- running, else the last that started, else the first.
  IF v_sub.id IS NOT NULL AND v_sub.period_code IS NOT NULL AND v_sub.academic_year IS NOT NULL THEN
    SELECT p.period_code, p.academic_year, p.name, p.label, p.start_date, p.end_date
    INTO v_term_code, v_term_year, v_term_name, v_term_label, v_term_start, v_term_end
    FROM public.company_periods(v_sub.company_id, v_sub.academic_year) p
    WHERE p.subscription_type = 'termly'
      AND (p.period_code = v_sub.period_code
           OR (v_sub.period_code NOT IN ('first', 'second', 'summer') AND p.period_code IN ('first', 'second')))
    ORDER BY (p.start_date <= v_today) DESC,
             CASE WHEN p.start_date <= v_today THEN p.start_date END DESC NULLS LAST,
             p.start_date
    LIMIT 1;
  END IF;
  -- No such subscription: the company's (or the platform's) term by the calendar.
  IF v_term_start IS NULL THEN
    SELECT p.period_code, p.academic_year, p.name, p.label, p.start_date, p.end_date
    INTO v_term_code, v_term_year, v_term_name, v_term_label, v_term_start, v_term_end
    FROM (SELECT * FROM public.company_periods(v_company, v_year - 1)
          UNION ALL
          SELECT * FROM public.company_periods(v_company, v_year)) p
    WHERE p.subscription_type = 'termly' AND p.start_date <= v_today
    ORDER BY p.start_date DESC
    LIMIT 1;
  END IF;

  v_from := COALESCE(p_from, v_term_start, v_today - 120);
  v_to := COALESCE(p_to, v_term_end, v_today);
  IF v_to < v_from OR v_to - v_from > 400 THEN
    RAISE EXCEPTION 'الفترة غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  v_until := LEAST(v_to, v_today);

  -- ---- the ride days -----------------------------------------------------
  -- One row per day the student confirmed a ride, with the subscription it was
  -- made under (the one recorded with it, else the one valid that day with the
  -- same company, so a ride is never put on another company's line). The
  -- times are the ones chosen for the day, else the subscription's.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'date', r.ride_date,
           'weekday', extract(isodow FROM r.ride_date)::integer,
           'departure_time', left(r.dep_time::text, 5),
           'return_time', left(r.ret_time::text, 5),
           'returns_by_bus', r.is_returning,
           'line_id', r.line_id,
           'station_id', r.station_id,
           'departure_minutes', r.departure_minutes,
           'boarded_departure', r.boarded_departure,
           'boarded_return', r.boarded_return)
         ORDER BY r.ride_date), '[]'::jsonb)
  INTO v_rides
  FROM (
    SELECT drs.ride_date, drs.is_returning, s.line_id, s.station_id,
           COALESCE(drs.departure_time, s.departure_time) AS dep_time,
           CASE WHEN drs.is_returning THEN COALESCE(drs.return_time, s.return_time) END AS ret_time,
           (SELECT (extract(epoch FROM (t.arrival_time - ts.stop_time)) / 60)::integer
            FROM public.line_trips t
            JOIN public.line_trip_stops ts ON ts.trip_id = t.id AND ts.station_id = s.station_id
            WHERE t.line_id = s.line_id AND t.direction = 'departure'
              AND ts.stop_time = COALESCE(drs.departure_time, s.departure_time)
              AND t.arrival_time > ts.stop_time
              AND (t.university_id IS NULL OR t.university_id = v_student.university_id)
            ORDER BY t.is_active DESC, t.university_id NULLS LAST, t.start_time
            LIMIT 1) AS departure_minutes,
           EXISTS (SELECT 1 FROM public.supervisor_scan_events e
                   WHERE e.student_id = v_me AND e.ride_date = drs.ride_date
                     AND e.direction = 'departure' AND e.result = 'checked_in') AS boarded_departure,
           EXISTS (SELECT 1 FROM public.supervisor_scan_events e
                   WHERE e.student_id = v_me AND e.ride_date = drs.ride_date
                     AND e.direction = 'return' AND e.result = 'checked_in') AS boarded_return
    FROM public.daily_ride_status drs
    LEFT JOIN LATERAL (
      SELECT x.id, x.line_id, x.station_id, x.departure_time, x.return_time
      FROM public.subscriptions x
      WHERE x.student_id = v_me
        AND (x.id = drs.subscription_id
             OR (x.status IN ('active', 'expired') AND x.company_id = drs.company_id
                 AND COALESCE(x.start_date, drs.ride_date) <= drs.ride_date
                 AND COALESCE(x.end_date, drs.ride_date) >= drs.ride_date))
      ORDER BY (x.id = drs.subscription_id) DESC NULLS LAST, x.created_at DESC
      LIMIT 1
    ) s ON true
    WHERE drs.student_id = v_me AND drs.is_riding AND drs.ride_date BETWEEN v_from AND v_until
  ) r;

  -- ---- the most used line and stop (a tie: the one used first) ------------
  SELECT (x->>'line_id')::uuid, (x->>'station_id')::uuid
  INTO v_line, v_station
  FROM jsonb_array_elements(v_rides) x
  WHERE x->>'line_id' IS NOT NULL AND x->>'station_id' IS NOT NULL
  GROUP BY x->>'line_id', x->>'station_id'
  ORDER BY count(*) DESC, min(x->>'date')
  LIMIT 1;
  IF v_line IS NULL THEN
    v_line := v_sub.line_id;
    v_station := v_sub.station_id;
  END IF;
  v_company := COALESCE((SELECT l.company_id FROM public.lines l WHERE l.id = v_line), v_company);

  -- How long the way there takes from that stop: the average over the going
  -- trips that stop there and have an arrival time.
  SELECT round(avg(extract(epoch FROM (t.arrival_time - ts.stop_time)) / 60))::integer
  INTO v_typical
  FROM public.line_trips t
  JOIN public.line_trip_stops ts ON ts.trip_id = t.id AND ts.station_id = v_station
  WHERE t.line_id = v_line AND t.direction = 'departure' AND t.is_active
    AND t.arrival_time > ts.stop_time
    AND (t.university_id IS NULL OR t.university_id = v_student.university_id);

  SELECT d.off_weekdays, d.off_dates INTO v_off_weekdays, v_off_dates
  FROM public.vote_reminder_days(v_company) d;

  RETURN jsonb_build_object(
    'today', v_today,
    'student', jsonb_build_object(
      'full_name', v_student.full_name,
      'first_name', split_part(btrim(v_student.full_name), ' ', 1),
      'university', COALESCE((SELECT u.name FROM public.universities u WHERE u.id = v_student.university_id),
                             v_student.university),
      'college', NULLIF(NULLIF(btrim(COALESCE(v_student.college, '')), ''), 'غير محدد'),
      'specialisation', NULLIF(btrim(COALESCE(v_student.specialisation, '')), '')),
    'term', jsonb_build_object(
      'code', v_term_code, 'academic_year', v_term_year, 'name', v_term_name, 'label', v_term_label,
      'start_date', v_term_start, 'end_date', v_term_end),
    'range', jsonb_build_object('from', v_from, 'to', v_to, 'until', v_until),
    'subscription', CASE WHEN v_sub.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_sub.id, 'type', v_sub.type, 'status', v_sub.status, 'period_code', v_sub.period_code,
      'academic_year', v_sub.academic_year, 'start_date', v_sub.start_date, 'end_date', v_sub.end_date,
      'created_at', v_sub.created_at, 'paid_at', v_sub.paid_at) END,
    'rides', v_rides,
    'summary', (
      SELECT jsonb_build_object(
        'ride_days', count(*),
        'return_days', count(*) FILTER (WHERE (x->>'returns_by_bus')::boolean),
        'boarded_departures', count(*) FILTER (WHERE (x->>'boarded_departure')::boolean),
        'boarded_returns', count(*) FILTER (WHERE (x->>'boarded_return')::boolean),
        'first_ride_date', min(x->>'date'),
        'last_ride_date', max(x->>'date'))
      FROM jsonb_array_elements(v_rides) x),
    'line', (
      SELECT jsonb_build_object(
        'id', l.id, 'name', l.name, 'company_id', l.company_id, 'company_name', c.name,
        'stations', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name, 'order_index', st.order_index)
                           ORDER BY st.order_index, st.name)
          FROM public.stations st
          WHERE st.line_id = l.id AND (st.is_active OR st.id = v_station)), '[]'::jsonb))
      FROM public.lines l
      LEFT JOIN public.companies c ON c.id = l.company_id
      WHERE l.id = v_line),
    'stop', (
      SELECT jsonb_build_object(
        'id', st.id, 'name', st.name, 'order_index', st.order_index,
        'rides', (SELECT count(*) FROM jsonb_array_elements(v_rides) x WHERE x->>'station_id' = st.id::text),
        'stops_used', (SELECT count(DISTINCT x->>'station_id') FROM jsonb_array_elements(v_rides) x
                       WHERE x->>'station_id' IS NOT NULL))
      FROM public.stations st
      WHERE st.id = v_station),
    'timetable', jsonb_build_object(
      'departure_times', (
        SELECT COALESCE(jsonb_agg(left(q.at_time::text, 5) ORDER BY q.at_time), '[]'::jsonb)
        FROM (SELECT DISTINCT ts.stop_time AS at_time
              FROM public.line_trips t
              JOIN public.line_trip_stops ts ON ts.trip_id = t.id AND ts.station_id = v_station
              WHERE t.line_id = v_line AND t.direction = 'departure' AND t.is_active
                AND (t.university_id IS NULL OR t.university_id = v_student.university_id)) q),
      'return_times', (
        SELECT COALESCE(jsonb_agg(left(q.at_time::text, 5) ORDER BY q.at_time), '[]'::jsonb)
        FROM (SELECT DISTINCT t.start_time AS at_time
              FROM public.line_trips t
              WHERE t.line_id = v_line AND t.direction = 'return' AND t.is_active
                AND (t.university_id IS NULL OR t.university_id = v_student.university_id)) q)),
    'trip_length', jsonb_build_object('departure_minutes', v_typical, 'return_minutes', NULL),
    'off', jsonb_build_object(
      'weekdays', to_jsonb(COALESCE(v_off_weekdays, '{}'::integer[])),
      'dates', (SELECT COALESCE(jsonb_agg(d ORDER BY d), '[]'::jsonb)
                FROM (SELECT DISTINCT d FROM unnest(COALESCE(v_off_dates, '{}'::date[])) d
                      WHERE d BETWEEN v_from AND v_to) y))
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_term_recap(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_term_recap(uuid, date, date) TO authenticated;

COMMIT;
