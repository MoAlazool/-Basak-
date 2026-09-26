-- ==============================================================================
-- PROJECT: University Bus Subscription System (باصك - Basak)
-- MASTER MIGRATION SCRIPT (Run this in Supabase SQL Editor)
-- Includes: Extensions, Tables, Indexes, Constraints, RLS, Storage, Triggers,
--           Daily 1:00 PM cutoff functions, QR Lookup, and Seed Data.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- STEP 1: EXTENSIONS & TABLES
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. COMPANIES
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. SUPERVISORS (Provisioned by Admin only)
CREATE TABLE IF NOT EXISTS public.supervisors (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    created_by_admin_id UUID REFERENCES auth.users(id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. LINES
CREATE TABLE IF NOT EXISTS public.lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    supervisor_id UUID REFERENCES public.supervisors(id) ON DELETE SET NULL,
    price_termly NUMERIC(10, 2) NOT NULL CHECK (price_termly >= 0),
    price_yearly NUMERIC(10, 2) NOT NULL CHECK (price_yearly >= 0),
    price_daily NUMERIC(10, 2) NOT NULL CHECK (price_daily >= 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. STATIONS
CREATE TABLE IF NOT EXISTS public.stations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    line_id UUID NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    order_index INT NOT NULL DEFAULT 0,
    departure_time TIME NOT NULL,
    return_time TIME NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_line_order UNIQUE (line_id, order_index)
);

-- 5. STUDENTS
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    university TEXT NOT NULL,
    qr_code_value UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_students_phone ON public.students(phone);
CREATE INDEX IF NOT EXISTS idx_students_qr ON public.students(qr_code_value);

-- 6. ADMINS
CREATE TABLE IF NOT EXISTS public.admins (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. SUBSCRIPTIONS
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    line_id UUID NOT NULL REFERENCES public.lines(id) ON DELETE RESTRICT,
    station_id UUID NOT NULL REFERENCES public.stations(id) ON DELETE RESTRICT,
    type TEXT NOT NULL CHECK (type IN ('termly', 'yearly', 'daily')),
    status TEXT NOT NULL DEFAULT 'pending_payment' CHECK (status IN ('pending_payment', 'pending_review', 'active', 'rejected', 'expired')),
    start_date DATE,
    end_date DATE,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Hard Rule: A student can only have ONE active/pending subscription at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_sub_per_student 
ON public.subscriptions (student_id) 
WHERE status IN ('pending_payment', 'pending_review', 'active');

CREATE INDEX IF NOT EXISTS idx_subscriptions_student ON public.subscriptions(student_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_line ON public.subscriptions(line_id);

-- 8. RECEIPTS (Payment Review)
CREATE TABLE IF NOT EXISTS public.receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    rejection_reason TEXT,
    attempt_number INT NOT NULL DEFAULT 1 CHECK (attempt_number BETWEEN 1 AND 5),
    reviewed_by UUID REFERENCES public.supervisors(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    -- Hard Rule: Mandatory written rejection reason on rejection
    CONSTRAINT check_mandatory_rejection_reason CHECK (
        status != 'rejected' OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0)
    ),
    CONSTRAINT unique_sub_attempt UNIQUE (subscription_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS idx_receipts_sub ON public.receipts(subscription_id);

-- 9. DAILY RIDE STATUS (Nazel Bokra)
CREATE TABLE IF NOT EXISTS public.daily_ride_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    ride_date DATE NOT NULL,
    is_riding BOOLEAN NOT NULL DEFAULT false,
    toggled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_student_ride_date UNIQUE (student_id, ride_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_ride_date ON public.daily_ride_status(ride_date, is_riding);

-- 10. CHAT MESSAGES (Realtime)
CREATE TABLE IF NOT EXISTS public.chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    supervisor_id UUID NOT NULL REFERENCES public.supervisors(id) ON DELETE CASCADE,
    sender_role TEXT NOT NULL CHECK (sender_role IN ('student', 'supervisor')),
    message TEXT NOT NULL CHECK (length(trim(message)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. COMPLAINTS
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- STEP 2: ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------------------------
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supervisors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_ride_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;

-- Helper Functions
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.is_supervisor()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM public.supervisors WHERE id = auth.uid() AND is_active = true);
$$;

CREATE OR REPLACE FUNCTION public.is_student()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM public.students WHERE id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.get_supervisor_assigned_line_ids()
RETURNS TABLE (line_id UUID) LANGUAGE sql SECURITY DEFINER STABLE AS $$
    SELECT l.id FROM public.lines l WHERE l.supervisor_id = auth.uid()
    UNION
    SELECT l.id FROM public.lines l
    INNER JOIN public.supervisors s ON s.company_id = l.company_id
    WHERE s.id = auth.uid() AND s.is_active = true;
$$;

-- Policies: Companies, Lines, Stations
CREATE POLICY "Public read companies" ON public.companies FOR SELECT TO authenticated USING (is_active = true OR public.is_admin());
CREATE POLICY "Admin write companies" ON public.companies FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Public read lines" ON public.lines FOR SELECT TO authenticated USING (is_active = true OR public.is_admin() OR public.is_supervisor());
CREATE POLICY "Admin write lines" ON public.lines FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Public read stations" ON public.stations FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admin write stations" ON public.stations FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Policies: Supervisors & Students
CREATE POLICY "Read supervisor" ON public.supervisors FOR SELECT TO authenticated USING (id = auth.uid() OR public.is_admin());
CREATE POLICY "Admin write supervisor" ON public.supervisors FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Student read own profile" ON public.students FOR SELECT TO authenticated USING (id = auth.uid() OR public.is_admin() OR public.is_supervisor());
CREATE POLICY "Student register profile" ON public.students FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
CREATE POLICY "Student delete own profile" ON public.students FOR DELETE TO authenticated USING (id = auth.uid() OR public.is_admin());
CREATE POLICY "Admin write students" ON public.students FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Policies: Subscriptions & Receipts
CREATE POLICY "Student read subscriptions" ON public.subscriptions FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_admin() OR line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids()));
CREATE POLICY "Student create subscription" ON public.subscriptions FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "Student delete subscription" ON public.subscriptions FOR DELETE TO authenticated USING (student_id = auth.uid() OR public.is_admin());
CREATE POLICY "Supervisor update subscription" ON public.subscriptions FOR UPDATE TO authenticated USING (public.is_admin() OR line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids()));
CREATE POLICY "Admin write subscriptions" ON public.subscriptions FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "View receipts" ON public.receipts FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id AND (sub.student_id = auth.uid() OR sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())))
    OR public.is_admin()
);
CREATE POLICY "Upload receipts" ON public.receipts FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id AND sub.student_id = auth.uid())
);
CREATE POLICY "Review receipts" ON public.receipts FOR UPDATE TO authenticated USING (
    public.is_admin() OR EXISTS (SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids()))
);

-- Policies: Daily Ride Status (Nazel Bokra)
CREATE POLICY "Student view ride status" ON public.daily_ride_status FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_admin() OR public.is_supervisor());
CREATE POLICY "Student insert ride status" ON public.daily_ride_status FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "Student update ride status" ON public.daily_ride_status FOR UPDATE TO authenticated USING (student_id = auth.uid() OR public.is_admin());

-- Policies: Chat & Complaints
CREATE POLICY "Chat view" ON public.chat_messages FOR SELECT TO authenticated USING (student_id = auth.uid() OR supervisor_id = auth.uid() OR public.is_admin());
CREATE POLICY "Chat insert" ON public.chat_messages FOR INSERT TO authenticated WITH CHECK ((sender_role = 'student' AND student_id = auth.uid()) OR (sender_role = 'supervisor' AND supervisor_id = auth.uid()) OR public.is_admin());

CREATE POLICY "Complaints view" ON public.complaints FOR SELECT TO authenticated USING (student_id = auth.uid() OR public.is_admin());
CREATE POLICY "Complaints insert" ON public.complaints FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "Complaints admin" ON public.complaints FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- STEP 3: STORAGE SETUP (Receipts Bucket)
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('receipts', 'receipts', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = false;

CREATE POLICY "Students upload receipts storage" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'receipts' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Students read receipts storage" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'receipts' AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin() OR public.is_supervisor()));

-- ------------------------------------------------------------------------------
-- STEP 4: FUNCTIONS & TRIGGERS (1:00 PM Cutoff, Auto-Status, Attempt Counter)
-- ------------------------------------------------------------------------------

-- 1. Daily Ride Toggle with 1:00 PM Cutoff
CREATE OR REPLACE FUNCTION public.toggle_student_daily_ride(p_ride_date DATE, p_is_riding BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_student_id UUID := auth.uid();
    v_has_active_sub BOOLEAN;
BEGIN
    IF v_student_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Validate active subscription
    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions
        WHERE student_id = v_student_id AND status = 'active'
          AND (start_date IS NULL OR start_date <= p_ride_date)
          AND (end_date IS NULL OR end_date >= p_ride_date)
    ) INTO v_has_active_sub;

    IF NOT v_has_active_sub THEN
        RAISE EXCEPTION 'لا يوجد اشتراك نشط لهذا التاريخ.';
    END IF;

    -- Prevent past date toggles
    IF p_ride_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'لا يمكن تعديل الحضور لتواريخ سابقة.';
    END IF;

    -- 1:00 PM (13:00) Cutoff Rule for today's ride
    IF p_ride_date = CURRENT_DATE AND CURRENT_TIME >= '13:00:00'::TIME THEN
        RAISE EXCEPTION 'تم إغلاق تأكيد حضور اليوم بعد الساعة 1:00 ظهراً.';
    END IF;

    INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, toggled_at)
    VALUES (v_student_id, p_ride_date, p_is_riding, now())
    ON CONFLICT (student_id, ride_date)
    DO UPDATE SET is_riding = EXCLUDED.is_riding, toggled_at = now();

    RETURN jsonb_build_object('success', true, 'is_riding', p_is_riding);
END;
$$;

-- 2. Rider Counts per Station
CREATE OR REPLACE FUNCTION public.get_line_rider_counts(p_line_id UUID, p_ride_date DATE)
RETURNS TABLE (station_id UUID, station_name TEXT, order_index INT, departure_time TIME, return_time TIME, riding_count BIGINT)
LANGUAGE sql SECURITY DEFINER STABLE AS $$
    SELECT 
        st.id, st.name, st.order_index, st.departure_time, st.return_time,
        COUNT(drs.id) FILTER (WHERE drs.is_riding = true)
    FROM public.stations st
    LEFT JOIN public.subscriptions sub ON sub.station_id = st.id AND sub.status = 'active'
    LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
    WHERE st.line_id = p_line_id
    GROUP BY st.id, st.name, st.order_index, st.departure_time, st.return_time
    ORDER BY st.order_index ASC;
$$;

-- 3. QR Student Lookup (Lookup ONLY - Does NOT write attendance)
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(p_qr_code UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
    v_data JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', s.id,
        'full_name', s.full_name,
        'phone', s.phone,
        'university', s.university,
        'subscription', (
            SELECT jsonb_build_object(
                'id', sub.id, 'type', sub.type, 'status', sub.status,
                'start_date', sub.start_date, 'end_date', sub.end_date,
                'line_name', l.name, 'station_name', st.name,
                'departure_time', st.departure_time, 'return_time', st.return_time,
                'payment_date', (SELECT reviewed_at FROM public.receipts r WHERE r.subscription_id = sub.id AND r.status = 'approved' ORDER BY r.reviewed_at DESC LIMIT 1)
            )
            FROM public.subscriptions sub
            INNER JOIN public.lines l ON l.id = sub.line_id
            INNER JOIN public.stations st ON st.id = sub.station_id
            WHERE sub.student_id = s.id AND sub.status IN ('active', 'pending_review', 'pending_payment')
            ORDER BY sub.created_at DESC LIMIT 1
        ),
        'today_ride_status', (
            SELECT COALESCE(is_riding, false) FROM public.daily_ride_status WHERE student_id = s.id AND ride_date = CURRENT_DATE
        )
    ) INTO v_data
    FROM public.students s
    WHERE s.qr_code_value = p_qr_code;

    RETURN v_data;
END;
$$;

-- 4. Triggers: Receipt Attempts (max 5) & Status Update
CREATE OR REPLACE FUNCTION public.handle_new_receipt_upload()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_last_attempt INT;
BEGIN
    SELECT COALESCE(MAX(attempt_number), 0) INTO v_last_attempt FROM public.receipts WHERE subscription_id = NEW.subscription_id;
    IF v_last_attempt >= 5 THEN RAISE EXCEPTION 'وصلت للحد الأقصى لرفع الإيصالات (5 محاولات).'; END IF;

    NEW.attempt_number := v_last_attempt + 1;
    NEW.status := 'pending';
    UPDATE public.subscriptions SET status = 'pending_review' WHERE id = NEW.subscription_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_new_receipt ON public.receipts;
CREATE TRIGGER trg_handle_new_receipt BEFORE INSERT ON public.receipts FOR EACH ROW EXECUTE FUNCTION public.handle_new_receipt_upload();

CREATE OR REPLACE FUNCTION public.handle_receipt_review()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_sub_type TEXT;
    v_start DATE := CURRENT_DATE;
    v_end DATE;
BEGIN
    IF NEW.status != OLD.status THEN
        NEW.reviewed_at := now();
        NEW.reviewed_by := auth.uid();
        IF NEW.status = 'approved' THEN
            SELECT type INTO v_sub_type FROM public.subscriptions WHERE id = NEW.subscription_id;
            IF v_sub_type = 'yearly' THEN v_end := v_start + INTERVAL '1 year';
            ELSIF v_sub_type = 'termly' THEN v_end := v_start + INTERVAL '4 months';
            ELSE v_end := v_start + INTERVAL '1 day'; END IF;

            UPDATE public.subscriptions SET status = 'active', start_date = v_start, end_date = v_end WHERE id = NEW.subscription_id;
        ELSIF NEW.status = 'rejected' THEN
            IF NEW.rejection_reason IS NULL OR length(trim(NEW.rejection_reason)) = 0 THEN
                RAISE EXCEPTION 'سبب الرفض إلزامي عند رفض الإيصال.';
            END IF;
            UPDATE public.subscriptions SET status = 'rejected' WHERE id = NEW.subscription_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_receipt_review ON public.receipts;
CREATE TRIGGER trg_handle_receipt_review BEFORE UPDATE ON public.receipts FOR EACH ROW EXECUTE FUNCTION public.handle_receipt_review();

-- Prevent Profile Edits on student table
CREATE OR REPLACE FUNCTION public.prevent_student_profile_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.phone != NEW.phone OR OLD.qr_code_value != NEW.qr_code_value OR OLD.university != NEW.university THEN
        RAISE EXCEPTION 'تعديل الملف الشخصي غير متاح. يجب حذف الحساب وإعادة التسجيل بالبيانات الجديدة.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_student_update ON public.students;
CREATE TRIGGER trg_prevent_student_update BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION public.prevent_student_profile_update();

-- ------------------------------------------------------------------------------
-- STEP 5: SEED DATA (Companies, Lines, Stations)
-- ------------------------------------------------------------------------------
INSERT INTO public.companies (id, name, is_active) VALUES 
    ('11111111-1111-1111-1111-111111111111', 'شركة النقل الجامعي السريع (FastUni Bus)', true),
    ('22222222-2222-2222-2222-222222222222', 'شركة باصات العاصمة (Capital Shuttles)', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.lines (id, company_id, name, price_termly, price_yearly, price_daily, is_active) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'خط مدينة نصر - التجمع - الجامعة', 3500.00, 6500.00, 50.00, true),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'خط المعادي - حلوان - الجامعة', 3800.00, 7000.00, 55.00, true),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'خط الجيزة - المهندسين - الجامعة', 4000.00, 7500.00, 60.00, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.stations (line_id, name, order_index, departure_time, return_time) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة سيتي ستارز - أول عباس', 1, '07:00:00', '16:00:00'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة مكرم عبيد - تقاطع النصر', 2, '07:15:00', '15:45:00'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة التجمع الأول - المحور', 3, '07:40:00', '15:20:00'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'محطة التجمع الخامس - التسعين الشمالي', 4, '08:00:00', '15:00:00'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'محطة مترو حلوان', 1, '06:45:00', '16:15:00'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'محطة المعادي - شارع النصر', 2, '07:15:00', '15:45:00'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'محطة ميدان لبنان - المهندسين', 1, '07:00:00', '16:00:00'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'محطة ميدان الجيزة - شارع الجامعة', 2, '07:25:00', '15:35:00')
ON CONFLICT DO NOTHING;
