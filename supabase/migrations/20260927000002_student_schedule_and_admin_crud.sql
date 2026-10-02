-- Student registration choices, profile photos, editable station schedules,
-- and validated student subscriptions.

CREATE TABLE IF NOT EXISTS public.universities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    city TEXT NOT NULL DEFAULT 'المنصورة',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.universities (name, city) VALUES
    ('جامعة المنصورة', 'المنصورة'),
    ('جامعة المنصورة الأهلية', 'جمصة'),
    ('جامعة الدلتا للعلوم والتكنولوجيا', 'جمصة'),
    ('جامعة حورس', 'دمياط الجديدة'),
    ('جامعة السلاب', 'المنصورة'),
    ('جامعة دمياط', 'دمياط الجديدة')
ON CONFLICT (name) DO NOTHING;

ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.universities TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.universities TO authenticated;
DROP POLICY IF EXISTS "Anyone can view active universities" ON public.universities;
DROP POLICY IF EXISTS "Admins manage universities" ON public.universities;
CREATE POLICY "Anyone can view active universities"
ON public.universities FOR SELECT TO anon, authenticated
USING (is_active = true OR public.is_admin());
CREATE POLICY "Admins manage universities"
ON public.universities FOR ALL TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.colleges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_college_per_university UNIQUE (university_id, name)
);
ALTER TABLE public.colleges ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.colleges TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.colleges TO authenticated;
DROP POLICY IF EXISTS "Anyone can view active colleges" ON public.colleges;
DROP POLICY IF EXISTS "Admins manage colleges" ON public.colleges;
CREATE POLICY "Anyone can view active colleges"
ON public.colleges FOR SELECT TO anon, authenticated
USING (is_active = true OR public.is_admin());
CREATE POLICY "Admins manage colleges"
ON public.colleges FOR ALL TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());

ALTER TABLE public.stations
    ADD COLUMN IF NOT EXISTS departure_times TIME[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS return_times TIME[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS departure_time TIME,
    ADD COLUMN IF NOT EXISTS return_time TIME,
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- Carry forward old single-time station schemas without losing their schedule.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'stations' AND column_name = 'departure_time'
    ) THEN
        EXECUTE 'UPDATE public.stations SET departure_times = ARRAY[departure_time] WHERE departure_time IS NOT NULL AND cardinality(departure_times) = 0';
        EXECUTE 'ALTER TABLE public.stations ALTER COLUMN departure_time DROP NOT NULL';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'stations' AND column_name = 'return_time'
    ) THEN
        EXECUTE 'UPDATE public.stations SET return_times = ARRAY[return_time] WHERE return_time IS NOT NULL AND cardinality(return_times) = 0';
        EXECUTE 'ALTER TABLE public.stations ALTER COLUMN return_time DROP NOT NULL';
    END IF;
END;
$$;

-- Keep the legacy single-time columns populated for QR and supervisor reports.
UPDATE public.stations
SET departure_time = departure_times[1]
WHERE departure_time IS NULL AND cardinality(departure_times) > 0;
UPDATE public.stations
SET return_time = return_times[1]
WHERE return_time IS NULL AND cardinality(return_times) > 0;

ALTER TABLE public.subscriptions
    ADD COLUMN IF NOT EXISTS departure_time TIME,
    ADD COLUMN IF NOT EXISTS return_time TIME;

ALTER TABLE public.students
    ADD COLUMN IF NOT EXISTS profile_image_url TEXT,
    ADD COLUMN IF NOT EXISTS college TEXT NOT NULL DEFAULT 'غير محدد';

-- Passwords belong only in Supabase Auth, never in the public student profile.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'students' AND column_name = 'password'
    ) THEN
        ALTER TABLE public.students ALTER COLUMN password DROP DEFAULT;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_subscription_station_times()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_line_id UUID;
    v_line_active BOOLEAN;
    v_departure_times TIME[];
    v_return_times TIME[];
BEGIN
    SELECT s.line_id, s.departure_times, s.return_times, l.is_active
    INTO v_line_id, v_departure_times, v_return_times, v_line_active
    FROM public.stations
    AS s
    INNER JOIN public.lines AS l ON l.id = s.line_id
    WHERE s.id = NEW.station_id AND s.is_active = true;

    IF NOT FOUND OR NOT v_line_active OR v_line_id <> NEW.line_id THEN
        RAISE EXCEPTION 'The selected station is not active on the selected line.';
    END IF;
    IF NEW.departure_time IS NULL OR NOT (NEW.departure_time = ANY(v_departure_times)) THEN
        RAISE EXCEPTION 'Choose an available departure time for the selected station.';
    END IF;
    IF NEW.return_time IS NULL OR NOT (NEW.return_time = ANY(v_return_times)) THEN
        RAISE EXCEPTION 'Choose an available return time for the selected station.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_subscription_station_times ON public.subscriptions;
CREATE TRIGGER trg_validate_subscription_station_times
BEFORE INSERT OR UPDATE OF line_id, station_id, departure_time, return_time
ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.validate_subscription_station_times();

-- QR lookup shows each student's selected trip times, with station defaults
-- retained for subscriptions created before this change.
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(p_qr_code UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_data JSONB;
BEGIN
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
                'departure_time', COALESCE(sub.departure_time, st.departure_time),
                'return_time', COALESCE(sub.return_time, st.return_time),
                'payment_date', (
                    SELECT r.reviewed_at FROM public.receipts r
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
            SELECT COALESCE(drs.is_riding, false)
            FROM public.daily_ride_status drs
            WHERE drs.student_id = s.id AND drs.ride_date = CURRENT_DATE
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

-- Private profile images. Student registration uploads to {auth.uid()}/avatar.ext.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('student-avatars', 'student-avatars', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

DROP POLICY IF EXISTS "Students and admins can view profile images" ON storage.objects;
DROP POLICY IF EXISTS "Students can upload own profile image" ON storage.objects;
DROP POLICY IF EXISTS "Students can replace own profile image" ON storage.objects;
CREATE POLICY "Students and admins can view profile images"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'student-avatars' AND (
    (storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()
));
CREATE POLICY "Students can upload own profile image"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'student-avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Students can replace own profile image"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'student-avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'student-avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
