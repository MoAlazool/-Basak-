-- Store a student's chosen daily departure and return schedule with attendance.
ALTER TABLE public.daily_ride_status
    ADD COLUMN IF NOT EXISTS departure_time TIME,
    ADD COLUMN IF NOT EXISTS return_time TIME,
    ADD COLUMN IF NOT EXISTS is_returning BOOLEAN NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.toggle_student_daily_ride(
    p_ride_date DATE,
    p_is_riding BOOLEAN,
    p_departure_time TIME,
    p_return_time TIME,
    p_is_returning BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_student_id UUID := auth.uid();
    v_departure_times TIME[];
    v_return_times TIME[];
    v_has_active_sub BOOLEAN;
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Africa/Cairo';
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_ride_date < v_local_now::DATE THEN
        RAISE EXCEPTION 'Cannot confirm a ride for a past date.';
    END IF;
    IF p_ride_date = v_local_now::DATE
       AND v_local_now::TIME >= TIME '13:00' THEN
        RAISE EXCEPTION 'Ride confirmation for today is locked after 1:00 PM.';
    END IF;

    SELECT st.departure_times, st.return_times
    INTO v_departure_times, v_return_times
    FROM public.subscriptions AS sub
    INNER JOIN public.stations AS st ON st.id = sub.station_id
    INNER JOIN public.lines AS l ON l.id = sub.line_id
    WHERE sub.student_id = v_student_id
      AND sub.status = 'active'
      AND (sub.start_date IS NULL OR sub.start_date <= p_ride_date)
      AND (sub.end_date IS NULL OR sub.end_date >= p_ride_date)
      AND st.is_active = true
      AND l.is_active = true
    ORDER BY sub.created_at DESC
    LIMIT 1;

    v_has_active_sub := FOUND;
    IF NOT v_has_active_sub THEN
        RAISE EXCEPTION 'You do not have an active subscription for this date.';
    END IF;

    IF p_is_riding THEN
        IF p_departure_time IS NULL
           OR NOT (p_departure_time = ANY(COALESCE(v_departure_times, '{}'::TIME[]))) THEN
            RAISE EXCEPTION 'Choose an available departure time.';
        END IF;
        IF p_is_returning AND (
            p_return_time IS NULL
            OR NOT (p_return_time = ANY(COALESCE(v_return_times, '{}'::TIME[])))
        ) THEN
            RAISE EXCEPTION 'Choose an available return time or opt out of the return trip.';
        END IF;
    END IF;

    INSERT INTO public.daily_ride_status (
        student_id, ride_date, is_riding, departure_time, return_time,
        is_returning, toggled_at
    ) VALUES (
        v_student_id, p_ride_date, p_is_riding, p_departure_time,
        CASE WHEN p_is_returning THEN p_return_time ELSE NULL END,
        p_is_returning, now()
    )
    ON CONFLICT (student_id, ride_date)
    DO UPDATE SET
        is_riding = EXCLUDED.is_riding,
        departure_time = EXCLUDED.departure_time,
        return_time = EXCLUDED.return_time,
        is_returning = EXCLUDED.is_returning,
        toggled_at = now();

    RETURN jsonb_build_object(
        'success', true,
        'student_id', v_student_id,
        'ride_date', p_ride_date,
        'is_riding', p_is_riding,
        'departure_time', p_departure_time,
        'return_time', CASE WHEN p_is_returning THEN p_return_time ELSE NULL END,
        'is_returning', p_is_returning,
        'toggled_at', now()
    );
END;
$$;

REVOKE ALL ON FUNCTION public.toggle_student_daily_ride(DATE, BOOLEAN, TIME, TIME, BOOLEAN)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_student_daily_ride(DATE, BOOLEAN, TIME, TIME, BOOLEAN)
TO authenticated;

-- Keep older app builds functional, using the times saved on the active subscription.
CREATE OR REPLACE FUNCTION public.toggle_student_daily_ride(
    p_ride_date DATE,
    p_is_riding BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_departure_time TIME;
    v_return_time TIME;
    v_departure_times TIME[];
    v_return_times TIME[];
BEGIN
    SELECT sub.departure_time, sub.return_time, st.departure_times, st.return_times
    INTO v_departure_time, v_return_time, v_departure_times, v_return_times
    FROM public.subscriptions AS sub
    INNER JOIN public.stations AS st ON st.id = sub.station_id
    WHERE sub.student_id = auth.uid()
      AND sub.status = 'active'
      AND (sub.start_date IS NULL OR sub.start_date <= p_ride_date)
      AND (sub.end_date IS NULL OR sub.end_date >= p_ride_date)
    ORDER BY sub.created_at DESC
    LIMIT 1;

    IF v_departure_time IS NULL THEN
        v_departure_time := v_departure_times[1];
    END IF;
    IF v_return_time IS NULL THEN
        v_return_time := v_return_times[1];
    END IF;

    RETURN public.toggle_student_daily_ride(
        p_ride_date,
        p_is_riding,
        v_departure_time,
        v_return_time,
        v_return_time IS NOT NULL
    );
END;
$$;

REVOKE ALL ON FUNCTION public.toggle_student_daily_ride(DATE, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_student_daily_ride(DATE, BOOLEAN) TO authenticated;
