-- ==============================================================================
-- Migration: 20260926000001_initial_schema.sql
-- Project: University Bus Subscription System (باصك - Basak)
-- Description: Core tables, foreign keys, unique constraints, and check constraints
-- ==============================================================================

-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 1. COMPANIES TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 2. SUPERVISORS TABLE (Accounts created by Admin only)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.supervisors (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    created_by_admin_id UUID REFERENCES auth.users(id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 3. LINES TABLE
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 4. STATIONS TABLE
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 5. STUDENTS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    university TEXT NOT NULL,
    qr_code_value UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index on phone for fast lookups
CREATE INDEX IF NOT EXISTS idx_students_phone ON public.students(phone);
CREATE INDEX IF NOT EXISTS idx_students_qr ON public.students(qr_code_value);

-- ------------------------------------------------------------------------------
-- 6. ADMINS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admins (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 7. SUBSCRIPTIONS TABLE
-- ------------------------------------------------------------------------------
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

-- Hard constraint: A student can have ONLY ONE active/pending subscription at any time.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_sub_per_student 
ON public.subscriptions (student_id) 
WHERE status IN ('pending_payment', 'pending_review', 'active');

CREATE INDEX IF NOT EXISTS idx_subscriptions_student ON public.subscriptions(student_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_line ON public.subscriptions(line_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_station ON public.subscriptions(station_id);

-- ------------------------------------------------------------------------------
-- 8. RECEIPTS TABLE (Payment review for termly / yearly)
-- ------------------------------------------------------------------------------
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
    -- Hard constraint: When status is rejected, a written rejection reason is mandatory!
    CONSTRAINT check_mandatory_rejection_reason CHECK (
        status != 'rejected' OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0)
    ),
    -- Each attempt number for a subscription must be unique
    CONSTRAINT unique_sub_attempt UNIQUE (subscription_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS idx_receipts_subscription ON public.receipts(subscription_id);
CREATE INDEX IF NOT EXISTS idx_receipts_status ON public.receipts(status);

-- ------------------------------------------------------------------------------
-- 9. DAILY_RIDE_STATUS TABLE (Nazel Bokra - Daily attendance toggle)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.daily_ride_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    ride_date DATE NOT NULL,
    is_riding BOOLEAN NOT NULL DEFAULT false,
    toggled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_student_ride_date UNIQUE (student_id, ride_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_ride_date ON public.daily_ride_status(ride_date, is_riding);
CREATE INDEX IF NOT EXISTS idx_daily_ride_student ON public.daily_ride_status(student_id);

-- ------------------------------------------------------------------------------
-- 10. CHAT_MESSAGES TABLE (Realtime chat between Student & Line Supervisor)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    supervisor_id UUID NOT NULL REFERENCES public.supervisors(id) ON DELETE CASCADE,
    sender_role TEXT NOT NULL CHECK (sender_role IN ('student', 'supervisor')),
    message TEXT NOT NULL CHECK (length(trim(message)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_convo ON public.chat_messages(student_id, supervisor_id, created_at);

-- ------------------------------------------------------------------------------
-- 11. COMPLAINTS TABLE (Student feedback/issues to Admin)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_complaints_student ON public.complaints(student_id);
CREATE INDEX IF NOT EXISTS idx_complaints_status ON public.complaints(status);
