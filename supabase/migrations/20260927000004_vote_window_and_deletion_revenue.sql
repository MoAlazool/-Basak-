-- Daily ride votes run from 4 PM the previous day through 6 AM on the ride day.
-- Account deletion removes student data while preserving paid revenue without PII.

CREATE TABLE IF NOT EXISTS public.deleted_student_revenue (
    source_subscription_id UUID PRIMARY KEY,
    line_id UUID,
    line_name TEXT NOT NULL,
    company_name TEXT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
    subscription_type TEXT NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.deleted_student_revenue ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.deleted_student_revenue TO authenticated;
DROP POLICY IF EXISTS "Admins view deleted student revenue" ON public.deleted_student_revenue;
CREATE POLICY "Admins view deleted student revenue"
ON public.deleted_student_revenue FOR SELECT TO authenticated
USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.archive_student_revenue_before_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.deleted_student_revenue (
        source_subscription_id, line_id, line_name, company_name,
        amount, subscription_type
    )
    SELECT sub.id, sub.line_id, l.name, c.name, sub.price, sub.type
    FROM public.subscriptions AS sub
    LEFT JOIN public.lines AS l ON l.id = sub.line_id
    LEFT JOIN public.companies AS c ON c.id = l.company_id
    WHERE sub.student_id = OLD.id
      AND sub.status = 'active'
    ON CONFLICT (source_subscription_id) DO NOTHING;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_archive_student_revenue_before_delete ON public.students;
CREATE TRIGGER trg_archive_student_revenue_before_delete
BEFORE DELETE ON public.students
FOR EACH ROW EXECUTE FUNCTION public.archive_student_revenue_before_delete();

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
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Africa/Cairo';
    v_expected_ride_date DATE;
BEGIN
    IF v_student_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_local_now::TIME >= TIME '16:00' THEN
        v_expected_ride_date := v_local_now::DATE + 1;
    ELSE
        v_expected_ride_date := v_local_now::DATE;
    END IF;

    IF v_local_now::TIME >= TIME '06:00'
       AND v_local_now::TIME < TIME '16:00' THEN
        RAISE EXCEPTION 'التصويت مغلق. يفتح يومياً من الساعة ٤ مساءً حتى ٦ صباحاً.';
    END IF;

    IF p_ride_date <> v_expected_ride_date THEN
        RAISE EXCEPTION 'اختر تاريخ الرحلة المتاح للتصويت.';
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

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد اشتراك نشط لهذا التاريخ.';
    END IF;

    IF p_is_riding THEN
        IF p_departure_time IS NULL
           OR NOT (p_departure_time = ANY(COALESCE(v_departure_times, '{}'::TIME[]))) THEN
            RAISE EXCEPTION 'اختر موعد ذهاب متاحاً.';
        END IF;
        IF p_is_returning AND (
            p_return_time IS NULL
            OR NOT (p_return_time = ANY(COALESCE(v_return_times, '{}'::TIME[])))
        ) THEN
            RAISE EXCEPTION 'اختر موعد عودة متاحاً أو ألغِ رحلة العودة.';
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

-- Keep the older two-argument client RPC usable with station default times.
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

    IF v_departure_time IS NULL THEN v_departure_time := v_departure_times[1]; END IF;
    IF v_return_time IS NULL THEN v_return_time := v_return_times[1]; END IF;

    RETURN public.toggle_student_daily_ride(
        p_ride_date, p_is_riding, v_departure_time, v_return_time,
        v_return_time IS NOT NULL
    );
END;
$$;

REVOKE ALL ON FUNCTION public.toggle_student_daily_ride(DATE, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_student_daily_ride(DATE, BOOLEAN) TO authenticated;

-- Supervisors need both outbound counts and the number of students who selected
-- a return trip. Limit the SECURITY DEFINER query to their assigned company/lines.
CREATE OR REPLACE FUNCTION public.get_line_rider_counts_with_returns(
    p_line_id UUID,
    p_ride_date DATE
)
RETURNS TABLE (
    line_id UUID,
    line_name TEXT,
    station_id UUID,
    station_name TEXT,
    order_index INT,
    departure_time TIME,
    return_time TIME,
    riding_count BIGINT,
    returning_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() AND NOT EXISTS (
        SELECT 1 FROM public.get_supervisor_assigned_line_ids() AS assigned
        WHERE assigned.line_id = p_line_id
    ) THEN
        RAISE EXCEPTION 'هذا الخط غير مسند إلى حساب المشرف.';
    END IF;

    RETURN QUERY
    SELECT
        l.id,
        l.name,
        st.id,
        st.name,
        st.order_index,
        COALESCE(st.departure_time, st.departure_times[1]),
        COALESCE(st.return_time, st.return_times[1]),
        COUNT(drs.id) FILTER (WHERE drs.is_riding = true),
        COUNT(drs.id) FILTER (WHERE drs.is_riding = true AND drs.is_returning = true)
    FROM public.stations AS st
    INNER JOIN public.lines AS l ON l.id = st.line_id
    LEFT JOIN public.subscriptions AS sub
      ON sub.station_id = st.id AND sub.status = 'active'
    LEFT JOIN public.daily_ride_status AS drs
      ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
    WHERE st.line_id = p_line_id AND st.is_active = true AND l.is_active = true
    GROUP BY l.id, l.name, st.id, st.name, st.order_index, st.departure_time,
             st.departure_times, st.return_time, st.return_times
    ORDER BY st.order_index;
END;
$$;

REVOKE ALL ON FUNCTION public.get_line_rider_counts_with_returns(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_line_rider_counts_with_returns(UUID, DATE) TO authenticated;
