-- ==============================================================================
-- Migration: 20260926000004_daily_reset_logic.sql
-- Project: University Bus Subscription System (باصك - Basak)
-- Description: 1:00 PM cutoff enforcement, rider count queries, QR lookup function
-- ==============================================================================

-- 1. FUNCTION: Toggle Daily Ride with strict 1:00 PM cutoff validation
CREATE OR REPLACE FUNCTION public.toggle_student_daily_ride(
    p_ride_date DATE,
    p_is_riding BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_has_active_sub BOOLEAN;
    v_current_time TIME := CURRENT_TIME;
    v_current_date DATE := CURRENT_DATE;
    v_result JSONB;
BEGIN
    v_student_id := auth.uid();
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Validate active subscription
    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions
        WHERE student_id = v_student_id
          AND status = 'active'
          AND (start_date IS NULL OR start_date <= p_ride_date)
          AND (end_date IS NULL OR end_date >= p_ride_date)
    ) INTO v_has_active_sub;

    IF NOT v_has_active_sub THEN
        RAISE EXCEPTION 'You do not have an active subscription for this date.';
    END IF;

    -- Business Rule: Cannot toggle past dates
    IF p_ride_date < v_current_date THEN
        RAISE EXCEPTION 'Cannot toggle ride status for past dates.';
    END IF;

    -- Business Rule: At 1:00 PM (13:00), toggle is locked for today's ride
    IF p_ride_date = v_current_date AND v_current_time >= '13:00:00'::TIME THEN
        RAISE EXCEPTION 'Ride status for today is locked after 1:00 PM.';
    END IF;

    -- Upsert the daily ride status
    INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, toggled_at)
    VALUES (v_student_id, p_ride_date, p_is_riding, now())
    ON CONFLICT (student_id, ride_date)
    DO UPDATE SET 
        is_riding = EXCLUDED.is_riding,
        toggled_at = now();

    SELECT jsonb_build_object(
        'success', true,
        'student_id', v_student_id,
        'ride_date', p_ride_date,
        'is_riding', p_is_riding,
        'toggled_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- 2. FUNCTION: Auto-reset logic for daily rides (called daily at 13:00 / 1:00 PM)
-- Resets tomorrow's default to false for any pre-existing records or cleans up.
CREATE OR REPLACE FUNCTION public.reset_daily_rides_at_1pm()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Ensure default for tomorrow (CURRENT_DATE + 1) is false unless toggled after 13:00
    -- This function can be scheduled via pg_cron or invoked via Supabase Scheduled Edge Function.
    UPDATE public.daily_ride_status
    SET is_riding = false
    WHERE ride_date = (CURRENT_DATE + 1)
      AND toggled_at < (CURRENT_DATE || ' 13:00:00')::TIMESTAMPTZ;
END;
$$;

-- 3. FUNCTION: Get live Rider Counts by Line and Station for Today or Tomorrow
CREATE OR REPLACE FUNCTION public.get_line_rider_counts(
    p_line_id UUID,
    p_ride_date DATE
)
RETURNS TABLE (
    station_id UUID,
    station_name TEXT,
    order_index INT,
    departure_time TIME,
    return_time TIME,
    riding_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT 
        st.id AS station_id,
        st.name AS station_name,
        st.order_index,
        st.departure_time,
        st.return_time,
        COUNT(drs.id) FILTER (WHERE drs.is_riding = true) AS riding_count
    FROM public.stations st
    LEFT JOIN public.subscriptions sub ON sub.station_id = st.id AND sub.status = 'active'
    LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
    WHERE st.line_id = p_line_id
    GROUP BY st.id, st.name, st.order_index, st.departure_time, st.return_time
    ORDER BY st.order_index ASC;
$$;

-- 4. FUNCTION: Supervisor QR Lookup (Lookup ONLY - Does NOT write attendance)
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(
    p_qr_code UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_data JSONB;
BEGIN
    -- Check caller is supervisor or admin
    IF NOT (public.is_supervisor() OR public.is_admin()) THEN
        RAISE EXCEPTION 'Access denied. Only supervisors and admins can perform QR lookups.';
    END IF;

    SELECT jsonb_build_object(
        'id', s.id,
        'full_name', s.full_name,
        'phone', s.phone,
        'university', s.university,
        'subscription', (
            SELECT jsonb_build_object(
                'id', sub.id,
                'type', sub.type,
                'status', sub.status,
                'start_date', sub.start_date,
                'end_date', sub.end_date,
                'line_name', l.name,
                'station_name', st.name,
                'departure_time', st.departure_time,
                'return_time', st.return_time,
                'payment_date', (
                    SELECT reviewed_at 
                    FROM public.receipts r 
                    WHERE r.subscription_id = sub.id AND r.status = 'approved' 
                    ORDER BY r.reviewed_at DESC LIMIT 1
                )
            )
            FROM public.subscriptions sub
            INNER JOIN public.lines l ON l.id = sub.line_id
            INNER JOIN public.stations st ON st.id = sub.station_id
            WHERE sub.student_id = s.id 
              AND sub.status IN ('active', 'pending_review', 'pending_payment')
            ORDER BY sub.created_at DESC
            LIMIT 1
        ),
        'today_ride_status', (
            SELECT COALESCE(is_riding, false)
            FROM public.daily_ride_status
            WHERE student_id = s.id AND ride_date = CURRENT_DATE
        )
    ) INTO v_data
    FROM public.students s
    WHERE s.qr_code_value = p_qr_code;

    IF v_data IS NULL THEN
        RAISE EXCEPTION 'Student not found with the provided QR code.';
    END IF;

    RETURN v_data;
END;
$$;
