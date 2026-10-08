-- ==============================================================================
-- Migration: 20261102000001_performance_2.sql
-- Run AFTER 20261101000001. Safe to re-run. Every function keeps its name,
-- arguments and the shape of what it returns: only how it is worked out changes.
-- Measured on a local database with 15,000 students (supabase/tests/local/perf).
--
-- 1. Financial report: the period name was looked up per subscription (four
--    fifths of its time), totals were thirteen passes, and the 2000 rows shown
--    were whichever came first, sorted afterwards. Now: names once per company
--    and year, totals in one pass, the newest 2000.
-- 2. Confirmed riders were worked out for every company and then filtered. The
--    company overview and the supervisor's screens now ask for theirs only.
-- 3. Company overview: approved receipts read once; the next ride day asked once.
-- 4. Catalog: what is on sale on a line worked out once, not twice.
-- 5. Receipt upload, for the app: a retry may replace its own image and a failed
--    submission may remove it (only while no receipt uses it); an image belongs
--    to one receipt; the refusals carry codes (BR001 limit reached, BR002 one is
--    already under review, BR003 already active); what is left behind is listed
--    for the clean-up function after a day.
-- 6. my_role(): the app learns who signed in with one request instead of three.
-- 7. university_student_counts(): the dashboard no longer downloads every
--    student to count them.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Confirmed riders of some lines or one company only
-- ------------------------------------------------------------------------------
-- confirmed_riders(p_date) for the students of p_company / p_line_ids (NULL: no
-- such limit). The same rows confirmed_riders would give once filtered: a
-- student still counts under their newest valid subscription, whichever it is.
CREATE OR REPLACE FUNCTION public.confirmed_riders_in(p_date date, p_company uuid, p_line_ids uuid[])
RETURNS TABLE(student_id uuid, company_id uuid, line_id uuid, station_id uuid, subscription_id uuid, is_returning boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.* FROM (
    SELECT DISTINCT ON (drs.student_id)
           drs.student_id, s.company_id, s.line_id, s.station_id, s.id, drs.is_returning
    FROM public.daily_ride_status drs
    JOIN public.subscriptions s ON s.student_id = drs.student_id AND s.status = 'active'
     AND COALESCE(s.start_date, p_date) <= p_date AND COALESCE(s.end_date, p_date) >= p_date
    WHERE drs.ride_date = p_date AND drs.is_riding
      AND drs.student_id IN (
        SELECT x.student_id FROM public.subscriptions x
        WHERE x.status = 'active' AND (p_company IS NULL OR x.company_id = p_company)
          AND (p_line_ids IS NULL OR x.line_id = ANY (p_line_ids)))
    ORDER BY drs.student_id, s.created_at DESC
  ) r
  WHERE (p_company IS NULL OR r.company_id = p_company) AND (p_line_ids IS NULL OR r.line_id = ANY (p_line_ids))
$$;

-- rider_trip_choices(p_date) for those lines only.
CREATE OR REPLACE FUNCTION public.rider_trip_choices_in(p_date date, p_line_ids uuid[])
RETURNS TABLE(student_id uuid, line_id uuid, station_id uuid, subscription_id uuid, direction text,
              chosen_time time without time zone, trip_id uuid)
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
  FROM public.confirmed_riders_in(p_date, NULL, p_line_ids) r
  JOIN public.daily_ride_status drs ON drs.student_id = r.student_id AND drs.ride_date = p_date
  JOIN public.subscriptions sub ON sub.id = r.subscription_id
  JOIN public.students stu ON stu.id = r.student_id
  CROSS JOIN LATERAL (VALUES
    ('departure'::text, COALESCE(drs.departure_time, sub.departure_time)),
    ('return'::text, CASE WHEN drs.is_returning THEN COALESCE(drs.return_time, sub.return_time) END)
  ) AS x(direction, chosen_time)
  WHERE x.chosen_time IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.confirmed_riders_in(date, uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rider_trip_choices_in(date, uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.company_riders_on(p_company_id uuid, p_date date)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN p_date >= public.cairo_today()
    THEN (SELECT count(*) FROM public.confirmed_riders_in(p_date, p_company_id, NULL))
    ELSE (SELECT count(*) FROM public.daily_ride_status d
          WHERE d.company_id = p_company_id AND d.ride_date = p_date AND d.is_riding)
  END
$$;

-- ------------------------------------------------------------------------------
-- 2. As they were (20261020000001, 20261022000001, 20261024000001), asking for
--    their own riders only; the overview reads receipts once; the catalog works
--    out a line's sale options once.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_overview_data(p_company_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH day AS (SELECT public.cairo_today() AS today, public.next_votable_ride_date(p_company_id) AS next_ride),
  since AS (SELECT public.report_baseline('financial', p_company_id) AS at),
  paid AS (
    -- One payment per subscription: the approved receipt amount, else the price.
    SELECT s.id, s.line_id, s.status, s.start_date, s.end_date, s.paid_at, COALESCE(a.amount, s.price) AS amount
    FROM public.subscriptions s
    -- The company's approved receipts read once, not looked up per subscription.
    LEFT JOIN (SELECT DISTINCT ON (r.subscription_id) r.subscription_id, r.amount
               FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'approved'
               ORDER BY r.subscription_id, r.reviewed_at DESC NULLS LAST) a ON a.subscription_id = s.id
    WHERE s.company_id = p_company_id AND s.paid_at IS NOT NULL
  ),
  running AS (
    -- Valid today, so a term paid in advance is not counted before it starts.
    SELECT p.* FROM paid p, day
    WHERE p.status = 'active' AND (p.start_date IS NULL OR p.start_date <= day.today)
      AND (p.end_date IS NULL OR p.end_date >= day.today)
  ),
  week AS (
    SELECT d::date AS ride_date, public.company_riders_on(p_company_id, d::date) AS riders
    FROM day, generate_series(day.today - 6, day.today, INTERVAL '1 day') d
  )
  SELECT jsonb_build_object(
    'company', (SELECT jsonb_build_object('id', c.id, 'name', c.name, 'status', c.status, 'created_at', c.created_at)
                FROM public.companies c WHERE c.id = p_company_id),
    'baseline', (SELECT at FROM since),
    'members', (SELECT count(*) FROM public.company_students m WHERE m.company_id = p_company_id AND m.status = 'active'),
    'active_subscriptions', (SELECT count(*) FROM running),
    'pending_receipts', (SELECT count(*) FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'pending'),
    'revenue', COALESCE((SELECT sum(p.amount) FROM paid p, since WHERE since.at IS NULL OR p.paid_at > since.at), 0)
             + COALESCE((SELECT sum(a.amount) FROM public.deleted_student_revenue a, since
                         WHERE a.company_id = p_company_id AND (since.at IS NULL OR a.archived_at > since.at)), 0),
    'riders_today', (SELECT riders FROM week, day WHERE week.ride_date = day.today),
    -- Students confirm for the NEXT ride once its vote opens; that day's count is what moves.
    'next_ride_date', (SELECT next_ride FROM day),
    'riders_next', (SELECT COALESCE((SELECT w.riders FROM week w WHERE w.ride_date = day.next_ride),
                                    public.company_riders_on(p_company_id, day.next_ride)) FROM day),
    'vote_closes_at', (SELECT left(v.closes_at::text, 5) FROM public.vote_settings(p_company_id) v),
    'riders_week', (SELECT jsonb_agg(jsonb_build_object('date', ride_date, 'riders', riders) ORDER BY ride_date) FROM week),
    'lines', (SELECT count(*) FROM public.lines l WHERE l.company_id = p_company_id),
    'active_lines', (SELECT count(*) FROM public.lines l WHERE l.company_id = p_company_id AND l.is_active),
    'supervisors', (SELECT count(*) FROM public.supervisors s WHERE s.company_id = p_company_id AND s.is_active),
    'admins', (SELECT count(*) FROM public.admins a WHERE a.company_id = p_company_id),
    'top_lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'is_active', l.is_active, 'subscribers', n)
                       ORDER BY n DESC, l.name)
      FROM (SELECT l.id, l.name, l.is_active,
                   (SELECT count(*) FROM running r WHERE r.line_id = l.id) AS n
            FROM public.lines l WHERE l.company_id = p_company_id) l), '[]'::jsonb)
  )
$function$;

CREATE OR REPLACE FUNCTION public.get_supervisor_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    CROSS JOIN LATERAL public.rider_trip_choices_in(d.ride_date, (SELECT array_agg(a.line_id) FROM assigned a)) c
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
$function$;

CREATE OR REPLACE FUNCTION public.get_supervisor_trip_manifest(p_line_id uuid, p_direction text DEFAULT 'departure'::text, p_trip_id uuid DEFAULT NULL::uuid, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    FROM public.rider_trip_choices_in(v_date, ARRAY[p_line_id]) c
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
$function$;

CREATE OR REPLACE FUNCTION public.get_line_rider_counts_with_returns(p_line_id uuid, p_ride_date date)
 RETURNS TABLE(line_id uuid, line_name text, station_id uuid, station_name text, order_index integer, departure_time time without time zone, return_time time without time zone, riding_count bigint, returning_count bigint, schedule_id uuid, university_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    FROM public.rider_trip_choices_in(p_ride_date, ARRAY[p_line_id]) c
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
$function$;

CREATE OR REPLACE FUNCTION public.get_subscription_catalog()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH me AS (
    SELECT s.id, s.university_id, COALESCE(u.name, s.university) AS university
    FROM public.students s LEFT JOIN public.universities u ON u.id = s.university_id
    WHERE s.id = auth.uid()
  ),
  trips AS (
    SELECT t.* FROM public.line_trips t, me WHERE public.trip_serves_student(t, me.id)
  ),
  my_lines AS (
    SELECT l.* FROM public.lines l
    JOIN public.companies c ON c.id = l.company_id AND c.is_active AND c.status = 'active'
    WHERE l.is_active AND EXISTS (SELECT 1 FROM trips t WHERE t.line_id = l.id AND t.direction = 'departure')
  ),
  line_json AS (
    SELECT l.company_id, l.name, jsonb_build_object(
      'id', l.id, 'name', l.name, 'origin_name', COALESCE(l.origin_name, l.name),
      'university', (SELECT university FROM me),
      'first_departure', (SELECT min(t.start_time) FROM trips t WHERE t.line_id = l.id AND t.direction = 'departure'),
      'last_return', (SELECT max(t.start_time) FROM trips t WHERE t.line_id = l.id AND t.direction = 'return'),
      'stations', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name, 'order_index', st.order_index,
                 'departures', d.list) ORDER BY st.order_index, st.name)
        FROM public.stations st
        CROSS JOIN LATERAL (
          SELECT jsonb_agg(jsonb_build_object('trip_id', t.id, 'time', x.stop_time, 'label', t.label)
                           ORDER BY x.stop_time) AS list
          FROM trips t JOIN public.line_trip_stops x ON x.trip_id = t.id AND x.station_id = st.id
          WHERE t.line_id = l.id AND t.direction = 'departure') d
        -- A station no departure trip stops at cannot be boarded from.
        WHERE st.line_id = l.id AND st.is_active AND d.list IS NOT NULL), '[]'::jsonb),
      -- The way back: when the bus leaves the student's university. No stations.
      'returns', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('trip_id', t.id, 'time', t.start_time, 'label', t.label) ORDER BY t.start_time)
        FROM trips t WHERE t.line_id = l.id AND t.direction = 'return'), '[]'::jsonb),
      'options', COALESCE(sale.options, '[]'::jsonb),
      'from_price', sale.from_price,
      'daily', jsonb_build_object('enabled', public.daily_subscription_enabled(l.company_id), 'price', l.price_daily)
    ) AS j
    FROM my_lines l
    -- What is on sale on this line, worked out once (it was asked twice per line).
    CROSS JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object('option', o.option, 'academic_year', o.academic_year, 'name', o.name,
               'label', o.label, 'type', o.subscription_type, 'start_date', o.start_date, 'end_date', o.end_date,
               'phase', o.phase, 'price', o.price) ORDER BY o.start_date, o.subscription_type) AS options,
             min(o.price) AS from_price
      FROM public.line_sale_options_for(l.id, NULL, auth.uid()) o WHERE o.available) sale
  )
  SELECT jsonb_build_object(
    'university', (SELECT jsonb_build_object('id', university_id, 'name', university) FROM me),
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path,
               'lines', (SELECT jsonb_agg(lj.j ORDER BY lj.name) FROM line_json lj WHERE lj.company_id = c.id))
             ORDER BY c.name)
      FROM public.companies c WHERE EXISTS (SELECT 1 FROM line_json lj WHERE lj.company_id = c.id)), '[]'::jsonb))
$function$;

-- ------------------------------------------------------------------------------
-- 3. Financial report (as 20261030000001; see the head of this file)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_subscription_report(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid := NULLIF(p_filters->>'company_id', '')::uuid;
  v_university uuid := NULLIF(p_filters->>'university_id', '')::uuid;
  v_line uuid := NULLIF(p_filters->>'line_id', '')::uuid;
  v_year int := NULLIF(p_filters->>'academic_year', '')::int;
  -- first|second|both|summer|daily ('annual' is the older name of both)
  v_period text := NULLIF(replace(p_filters->>'period', 'annual', 'both'), '');
  v_payment text := NULLIF(p_filters->>'payment', '');      -- paid|unpaid
  v_phase text := NULLIF(p_filters->>'phase', '');          -- current|upcoming|expired
  v_search text := NULLIF(btrim(p_filters->>'search'), '');
  v_history boolean := COALESCE((p_filters->>'include_before_reset')::boolean, false);
  v_today date := public.cairo_today();
  v_data jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;
  IF public.is_company_admin() THEN v_company := public.current_admin_company_id(); END IF;
  IF v_company IS NOT NULL AND NOT public.can_manage_company(v_company) THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;

  WITH baselines AS (
    -- Each company counts from its own last reset.
    SELECT c.id, c.name, public.report_baseline('financial', c.id) AS since FROM public.companies c
    WHERE v_company IS NULL OR c.id = v_company
  ),
  filtered AS (
    SELECT s.id, s.type, s.status, s.academic_year, s.period_code, s.price, s.paid_at, s.start_date, s.end_date,
      s.created_at, s.company_id, st.full_name, st.phone, st.university AS university_name,
      l.name AS line_name, b.name AS company_name,
      COALESCE(s.period_code, CASE s.type WHEN 'daily' THEN 'daily' WHEN 'yearly' THEN 'both' END) AS period_key,
      CASE WHEN s.status = 'expired' OR s.end_date < v_today THEN 'expired'
           WHEN s.start_date > v_today THEN 'upcoming' ELSE 'current' END AS phase,
      (s.paid_at IS NOT NULL) AS is_paid,
      -- One payment per subscription: the approved receipt amount, else the price.
      CASE WHEN s.paid_at IS NOT NULL THEN COALESCE((
        SELECT r.amount FROM public.receipts r WHERE r.subscription_id = s.id AND r.status = 'approved'
        ORDER BY r.reviewed_at DESC NULLS LAST LIMIT 1), s.price) END AS paid_amount
    FROM public.subscriptions s
    JOIN public.students st ON st.id = s.student_id
    JOIN public.lines l ON l.id = s.line_id
    JOIN baselines b ON b.id = l.company_id
    WHERE (v_company IS NULL OR s.company_id = v_company)
      AND (v_university IS NULL OR st.university_id = v_university)
      AND (v_line IS NULL OR s.line_id = v_line)
      AND (v_year IS NULL OR s.academic_year = v_year)
      AND (v_search IS NULL OR st.full_name ILIKE '%' || v_search || '%' OR st.phone LIKE '%' || regexp_replace(v_search, '\D', '', 'g') || '%')
      AND (v_history OR b.since IS NULL OR COALESCE(s.paid_at, s.created_at) > b.since)
      AND (v_period IS NULL OR COALESCE(s.period_code, CASE s.type WHEN 'daily' THEN 'daily' WHEN 'yearly' THEN 'both' END) = v_period)
      AND (v_payment IS NULL OR (v_payment = 'paid') = (s.paid_at IS NOT NULL))
      AND (v_phase IS NULL OR v_phase = CASE WHEN s.status = 'expired' OR s.end_date < v_today THEN 'expired'
                                             WHEN s.start_date > v_today THEN 'upcoming' ELSE 'current' END)
  ),
  totals AS (
    SELECT count(*) AS n,
      count(*) FILTER (WHERE is_paid) AS paid,
      count(*) FILTER (WHERE NOT is_paid AND status IN ('pending_payment', 'pending_review', 'rejected')) AS unpaid,
      count(*) FILTER (WHERE phase = 'upcoming') AS upcoming,
      count(*) FILTER (WHERE phase = 'upcoming' AND is_paid) AS upcoming_paid,
      count(*) FILTER (WHERE phase = 'expired') AS expired,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid), 0) AS revenue,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'first'), 0) AS revenue_first,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'second'), 0) AS revenue_second,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'summer'), 0) AS revenue_summer,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'both'), 0) AS revenue_both,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'daily'), 0) AS revenue_daily
    FROM filtered
  ),
  shown AS (
    -- The newest 2000 (before, it was whichever 2000 came first).
    SELECT * FROM filtered ORDER BY paid_at DESC NULLS LAST, created_at DESC, id LIMIT 2000
  ),
  labels AS (
    -- The period names of each company and year on show, asked once each.
    SELECT k.company_id, k.academic_year, p.period_code, p.label
    FROM (SELECT DISTINCT company_id, academic_year FROM shown WHERE type <> 'daily') k
    CROSS JOIN LATERAL public.company_periods(k.company_id, k.academic_year) p
  )
  SELECT jsonb_build_object(
    'baseline', (SELECT max(since) FROM baselines),
    'totals', (SELECT jsonb_build_object(
      'count', n, 'paid', paid, 'unpaid', unpaid, 'upcoming', upcoming, 'upcoming_paid', upcoming_paid,
      'expired', expired, 'revenue', revenue, 'revenue_first', revenue_first, 'revenue_second', revenue_second,
      'revenue_summer', revenue_summer, 'revenue_both', revenue_both, 'revenue_annual', revenue_both,
      'revenue_daily', revenue_daily) FROM totals),
    'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', f.id, 'student_name', f.full_name, 'phone', f.phone, 'university', f.university_name,
        'company', f.company_name, 'line', f.line_name, 'type', f.type, 'period', f.period_key,
        'academic_year', f.academic_year,
        'label', CASE WHEN f.type = 'daily' THEN 'اشتراك يومي'
                      ELSE (SELECT lb.label FROM labels lb WHERE lb.company_id = f.company_id
                              AND lb.academic_year = f.academic_year AND lb.period_code = f.period_code) END,
        'status', f.status, 'phase', f.phase, 'paid', f.is_paid, 'amount', f.paid_amount, 'price', f.price,
        'paid_at', f.paid_at, 'start_date', f.start_date, 'end_date', f.end_date,
        'payment_method', (SELECT pm.display_name FROM public.receipts r
                           JOIN public.company_payment_methods pm ON pm.id = r.payment_method_id
                           WHERE r.subscription_id = f.id ORDER BY r.created_at DESC LIMIT 1),
        'receipt_no', x.receipt_no, 'receipt_code', x.receipt_code)
        ORDER BY f.paid_at DESC NULLS LAST, f.created_at DESC, f.id)
      FROM shown f LEFT JOIN public.subscription_receipts x ON x.subscription_id = f.id), '[]'::jsonb)
  ) INTO v_data;
  RETURN v_data;
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. Receipt upload: codes for the refusals, one image per receipt, a retry may
--    replace or remove its own unused image
-- ------------------------------------------------------------------------------
-- As 20261004000002 with Arabic texts and codes the app can tell apart.
CREATE OR REPLACE FUNCTION public.handle_new_receipt_upload()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sub record;
  v_last_attempt int;
BEGIN
  SELECT * INTO v_sub FROM public.subscriptions WHERE id = NEW.subscription_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الاشتراك غير موجود.'; END IF;
  IF v_sub.type = 'daily' THEN
    RAISE EXCEPTION 'الاشتراك اليومي يُدفع نقداً ولا يحتاج إيصالاً.';
  END IF;
  IF v_sub.status = 'active' THEN
    RAISE EXCEPTION 'اشتراكك مفعّل بالفعل ولا يحتاج إيصالاً آخر.' USING ERRCODE = 'BR003';
  END IF;
  IF v_sub.status = 'expired' OR v_sub.end_date < public.cairo_today() THEN
    RAISE EXCEPTION 'انتهت فترة هذا الاشتراك. اختر الفترة الحالية أو القادمة.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.receipts WHERE subscription_id = NEW.subscription_id AND status = 'pending') THEN
    RAISE EXCEPTION 'يوجد إيصال قيد المراجعة لهذا الاشتراك بالفعل.' USING ERRCODE = 'BR002';
  END IF;
  -- The image must be the student's own object for this subscription:
  -- receipts/{student_id}/{subscription_id}_{timestamp}.{ext}
  IF split_part(NEW.image_url, '/', 1) <> v_sub.student_id::text
     OR left(split_part(NEW.image_url, '/', 2), length(v_sub.id::text) + 1) <> v_sub.id::text || '_' THEN
    RAISE EXCEPTION 'مسار صورة الإيصال لا يطابق الاشتراك.' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(MAX(attempt_number), 0) INTO v_last_attempt
  FROM public.receipts WHERE subscription_id = NEW.subscription_id;
  IF v_last_attempt >= 5 THEN
    RAISE EXCEPTION 'وصلت إلى الحد الأقصى لعدد مرات رفع الإيصال (5 مرات). تواصل مع إدارة الشركة.' USING ERRCODE = 'BR001';
  END IF;

  NEW.attempt_number := v_last_attempt + 1;
  NEW.status := 'pending';
  NEW.rejection_reason := NULL;
  NEW.reviewed_by := NULL;
  NEW.reviewed_at := NULL;
  NEW.amount := v_sub.price;
  NEW.created_at := now();

  UPDATE public.subscriptions SET status = 'pending_review' WHERE id = NEW.subscription_id;
  RETURN NEW;
END;
$function$;

-- An image belongs to one receipt (where the data already allows it).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.receipts GROUP BY image_url HAVING count(*) > 1) THEN
    RAISE WARNING 'receipts.image_url has duplicates: the unique index was not created.';
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS uq_receipts_image_url ON public.receipts(image_url);
  END IF;
END;
$$;

-- A receipt uses this image (storage policies cannot read receipts for the student).
CREATE OR REPLACE FUNCTION public.receipt_image_in_use(p_path text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.receipts r WHERE r.image_url = p_path)
$$;
REVOKE ALL ON FUNCTION public.receipt_image_in_use(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receipt_image_in_use(text) TO authenticated;

-- A student may send the same image again over itself (a retry), or take it
-- back, only in their own folder and only while no receipt uses it.
DROP POLICY IF EXISTS "Students replace their unused receipt image" ON storage.objects;
CREATE POLICY "Students replace their unused receipt image" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'receipts' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
         AND NOT public.receipt_image_in_use(name))
  WITH CHECK (bucket_id = 'receipts' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
              AND NOT public.receipt_image_in_use(name));
DROP POLICY IF EXISTS "Students remove their unused receipt image" ON storage.objects;
CREATE POLICY "Students remove their unused receipt image" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'receipts' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
         AND NOT public.receipt_image_in_use(name));

-- Receipt images a day old that no receipt uses (a submission that failed and
-- could not clean up after itself). Read by the storage-cleanup function, which
-- removes them through the Storage API.
CREATE OR REPLACE FUNCTION public.orphan_receipt_images(p_limit integer DEFAULT 200)
RETURNS SETOF text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT o.name FROM storage.objects o
  WHERE o.bucket_id = 'receipts' AND o.created_at < now() - interval '24 hours'
    AND NOT EXISTS (SELECT 1 FROM public.receipts r WHERE r.image_url = o.name)
  ORDER BY o.created_at
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000)
$$;
REVOKE ALL ON FUNCTION public.orphan_receipt_images(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.orphan_receipt_images(integer) TO service_role;

-- Wakes storage-cleanup (next to push-dispatch, same secret) when there is
-- something to remove. Called once a day by notifications_daily.
CREATE OR REPLACE FUNCTION public.storage_cleanup_kick()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_runtime public.push_runtime%ROWTYPE;
BEGIN
  IF to_regnamespace('net') IS NULL THEN RETURN; END IF;
  SELECT * INTO v_runtime FROM public.push_runtime WHERE id AND dispatch_url LIKE '%/push-dispatch';
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.orphan_receipt_images(1)) THEN RETURN; END IF;
  EXECUTE 'SELECT net.http_post(url := $1, body := $2, headers := $3)'
    USING regexp_replace(v_runtime.dispatch_url, '/push-dispatch$', '/storage-cleanup'), '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_runtime.dispatch_secret);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'storage clean-up wake-up failed: %', SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public.storage_cleanup_kick() FROM PUBLIC, anon, authenticated;

-- The day's work also wakes the clean-up of unused receipt images.
CREATE OR REPLACE FUNCTION public.notifications_daily()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := public.cairo_today();
  v_sub record;
BEGIN
  FOR v_sub IN SELECT s.id, s.company_id, s.student_id, s.end_date FROM public.subscriptions s
               WHERE s.status = 'active' AND s.end_date IN (v_today + 3, v_today - 1) LOOP
    PERFORM public.notify_student(v_sub.company_id, v_sub.student_id,
      CASE WHEN v_sub.end_date > v_today THEN 'subscription.expiring' ELSE 'subscription.expired' END,
      jsonb_build_object('subscription_id', v_sub.id),
      CASE WHEN v_sub.end_date > v_today THEN 'expiring:' ELSE 'expired:' END || v_sub.id);
  END LOOP;
  -- The app shows 90 days; the dashboard keeps half a year.
  DELETE FROM public.notifications
  WHERE status <> 'scheduled' AND COALESCE(sent_at, created_at) < now() - interval '180 days';
  DELETE FROM public.push_outbox WHERE created_at < now() - interval '30 days';
  DELETE FROM public.push_devices WHERE last_seen_at < now() - interval '180 days';
  DELETE FROM public.notification_audit WHERE at < now() - interval '2 years';
  PERFORM public.storage_cleanup_kick();
END;
$function$;

-- ------------------------------------------------------------------------------
-- 5. Small reads the clients were doing the long way
-- ------------------------------------------------------------------------------
-- Who signed in: 'admin', 'supervisor', 'student', or NULL (the order the app checked in).
CREATE OR REPLACE FUNCTION public.my_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN NULL
    WHEN EXISTS (SELECT 1 FROM public.admins a WHERE a.id = auth.uid()) THEN 'admin'
    WHEN EXISTS (SELECT 1 FROM public.supervisors s WHERE s.id = auth.uid()) THEN 'supervisor'
    WHEN EXISTS (SELECT 1 FROM public.students s WHERE s.id = auth.uid()) THEN 'student'
  END
$$;
REVOKE ALL ON FUNCTION public.my_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_role() TO authenticated;

-- Students per university name: all of them for the platform, a company's own
-- members for its admins. {"<university>": <count>, …}
CREATE OR REPLACE FUNCTION public.university_student_counts() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'متاح للإدارة فقط.' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_object_agg(x.university, x.n) FROM (
      SELECT s.university, count(*) AS n FROM public.students s
      WHERE s.university IS NOT NULL
        AND (public.is_super_admin() OR EXISTS (
              SELECT 1 FROM public.company_students m
              WHERE m.student_id = s.id AND m.company_id = public.current_admin_company_id() AND m.status = 'active'))
      GROUP BY s.university) x), '{}'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.university_student_counts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.university_student_counts() TO authenticated;

COMMIT;
