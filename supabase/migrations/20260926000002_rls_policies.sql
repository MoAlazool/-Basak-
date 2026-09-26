-- ==============================================================================
-- Migration: 20260926000002_rls_policies.sql
-- Project: University Bus Subscription System (باصك - Basak)
-- Description: Row Level Security (RLS) policies for Student, Supervisor, and Admin
-- ==============================================================================

-- Enable Row Level Security on all tables
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

-- ------------------------------------------------------------------------------
-- HELPER FUNCTIONS FOR ROLE CHECKS (Security Definer for clean permission evaluation)
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.admins WHERE id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.is_supervisor()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.supervisors WHERE id = auth.uid() AND is_active = true
    );
$$;

CREATE OR REPLACE FUNCTION public.is_student()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.students WHERE id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.get_supervisor_assigned_line_ids()
RETURNS TABLE (line_id UUID)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT l.id 
    FROM public.lines l
    WHERE l.supervisor_id = auth.uid()
    UNION
    SELECT l.id
    FROM public.lines l
    INNER JOIN public.supervisors s ON s.company_id = l.company_id
    WHERE s.id = auth.uid() AND s.is_active = true;
$$;

-- ------------------------------------------------------------------------------
-- 1. COMPANIES POLICIES
-- ------------------------------------------------------------------------------
-- Anyone authenticated can view active companies
CREATE POLICY "Anyone can view active companies"
ON public.companies FOR SELECT
TO authenticated
USING (is_active = true OR public.is_admin());

-- Only Admins can insert/update/delete companies
CREATE POLICY "Admins full access on companies"
ON public.companies FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- 2. LINES POLICIES
-- ------------------------------------------------------------------------------
-- Anyone authenticated can view active lines
CREATE POLICY "Anyone can view active lines"
ON public.lines FOR SELECT
TO authenticated
USING (is_active = true OR public.is_admin() OR public.is_supervisor());

-- Only Admins can insert/update/delete lines
CREATE POLICY "Admins full access on lines"
ON public.lines FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- 3. STATIONS POLICIES
-- ------------------------------------------------------------------------------
-- Anyone authenticated can view stations
CREATE POLICY "Anyone can view stations"
ON public.stations FOR SELECT
TO authenticated
USING (true);

-- Only Admins can insert/update/delete stations
CREATE POLICY "Admins full access on stations"
ON public.stations FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- 4. SUPERVISORS POLICIES
-- ------------------------------------------------------------------------------
-- Supervisors can view themselves and peers in their company
CREATE POLICY "Supervisors can view their own profile"
ON public.supervisors FOR SELECT
TO authenticated
USING (id = auth.uid() OR public.is_admin());

-- Students with active subscriptions can view their line's supervisor contact
CREATE POLICY "Students can view supervisor of their active line"
ON public.supervisors FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.subscriptions sub
        INNER JOIN public.lines l ON l.id = sub.line_id
        WHERE sub.student_id = auth.uid()
          AND sub.status = 'active'
          AND (l.supervisor_id = public.supervisors.id)
    )
);

-- Only Admins can manage supervisors
CREATE POLICY "Admins full access on supervisors"
ON public.supervisors FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- 5. STUDENTS POLICIES
-- ------------------------------------------------------------------------------
-- Students can read their own profile
CREATE POLICY "Students can view own profile"
ON public.students FOR SELECT
TO authenticated
USING (id = auth.uid() OR public.is_admin() OR public.is_supervisor());

-- Students can insert their profile on registration
CREATE POLICY "Students can register own profile"
ON public.students FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

-- Delete-and-re-register only: Student can delete their own profile
CREATE POLICY "Students can delete own profile"
ON public.students FOR DELETE
TO authenticated
USING (id = auth.uid() OR public.is_admin());

-- Admins full access
CREATE POLICY "Admins full access on students"
ON public.students FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- 6. ADMINS POLICIES
-- ------------------------------------------------------------------------------
CREATE POLICY "Admins can view admins"
ON public.admins FOR SELECT
TO authenticated
USING (public.is_admin());

-- ------------------------------------------------------------------------------
-- 7. SUBSCRIPTIONS POLICIES
-- ------------------------------------------------------------------------------
-- Students can view their own subscriptions
CREATE POLICY "Students can view own subscriptions"
ON public.subscriptions FOR SELECT
TO authenticated
USING (student_id = auth.uid() OR public.is_admin());

-- Supervisors can view subscriptions on their assigned lines
CREATE POLICY "Supervisors can view subscriptions on assigned lines"
ON public.subscriptions FOR SELECT
TO authenticated
USING (
    line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
);

-- Students can insert a subscription for themselves
CREATE POLICY "Students can create subscriptions"
ON public.subscriptions FOR INSERT
TO authenticated
WITH CHECK (student_id = auth.uid());

-- Students can delete their subscription (part of account deletion)
CREATE POLICY "Students can delete own subscriptions"
ON public.subscriptions FOR DELETE
TO authenticated
USING (student_id = auth.uid() OR public.is_admin());

-- Supervisors can update subscription status (e.g. active upon receipt approval)
CREATE POLICY "Supervisors can update subscription status"
ON public.subscriptions FOR UPDATE
TO authenticated
USING (
    public.is_admin() OR line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
)
WITH CHECK (
    public.is_admin() OR line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
);

-- Admins full access
CREATE POLICY "Admins full access on subscriptions"
ON public.subscriptions FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ------------------------------------------------------------------------------
-- 8. RECEIPTS POLICIES
-- ------------------------------------------------------------------------------
-- Students can view receipts for their subscriptions
CREATE POLICY "Students can view own receipts"
ON public.receipts FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.subscriptions sub 
        WHERE sub.id = public.receipts.subscription_id AND sub.student_id = auth.uid()
    ) OR public.is_admin()
);

-- Supervisors can view receipts for subscriptions on their assigned lines
CREATE POLICY "Supervisors can view receipts on assigned lines"
ON public.receipts FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.subscriptions sub
        WHERE sub.id = public.receipts.subscription_id
          AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
    )
);

-- Students can insert a new receipt (up to 5 attempts, handled in trigger/app)
CREATE POLICY "Students can upload receipts"
ON public.receipts FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.subscriptions sub 
        WHERE sub.id = subscription_id AND sub.student_id = auth.uid()
    )
);

-- Supervisors can update receipts (approve/reject with reason)
CREATE POLICY "Supervisors can review receipts"
ON public.receipts FOR UPDATE
TO authenticated
USING (
    public.is_admin() OR EXISTS (
        SELECT 1 FROM public.subscriptions sub
        WHERE sub.id = public.receipts.subscription_id
          AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
    )
)
WITH CHECK (
    public.is_admin() OR EXISTS (
        SELECT 1 FROM public.subscriptions sub
        WHERE sub.id = subscription_id
          AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
    )
);

-- ------------------------------------------------------------------------------
-- 9. DAILY_RIDE_STATUS POLICIES (Nazel Bokra)
-- ------------------------------------------------------------------------------
-- Students can view and manage their own daily ride toggle
CREATE POLICY "Students can view own ride status"
ON public.daily_ride_status FOR SELECT
TO authenticated
USING (student_id = auth.uid() OR public.is_admin());

-- Supervisors can view ride status of students on their lines for rider counts
CREATE POLICY "Supervisors can view ride status on assigned lines"
ON public.daily_ride_status FOR SELECT
TO authenticated
USING (
    public.is_admin() OR EXISTS (
        SELECT 1 FROM public.subscriptions sub
        WHERE sub.student_id = public.daily_ride_status.student_id
          AND sub.status = 'active'
          AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
    )
);

-- Students can insert or update their own ride status
CREATE POLICY "Students can insert own ride status"
ON public.daily_ride_status FOR INSERT
TO authenticated
WITH CHECK (student_id = auth.uid());

CREATE POLICY "Students can update own ride status"
ON public.daily_ride_status FOR UPDATE
TO authenticated
USING (student_id = auth.uid() OR public.is_admin())
WITH CHECK (student_id = auth.uid() OR public.is_admin());

-- ------------------------------------------------------------------------------
-- 10. CHAT_MESSAGES POLICIES (Realtime)
-- ------------------------------------------------------------------------------
-- Participants can view messages in their conversation
CREATE POLICY "Participants can view chat messages"
ON public.chat_messages FOR SELECT
TO authenticated
USING (student_id = auth.uid() OR supervisor_id = auth.uid() OR public.is_admin());

-- Students and supervisors can send messages in their conversation
CREATE POLICY "Participants can send chat messages"
ON public.chat_messages FOR INSERT
TO authenticated
WITH CHECK (
    (sender_role = 'student' AND student_id = auth.uid()) OR
    (sender_role = 'supervisor' AND supervisor_id = auth.uid()) OR
    public.is_admin()
);

-- ------------------------------------------------------------------------------
-- 11. COMPLAINTS POLICIES
-- ------------------------------------------------------------------------------
-- Students can view their complaints
CREATE POLICY "Students can view own complaints"
ON public.complaints FOR SELECT
TO authenticated
USING (student_id = auth.uid() OR public.is_admin());

-- Students can submit complaints
CREATE POLICY "Students can submit complaints"
ON public.complaints FOR INSERT
TO authenticated
WITH CHECK (student_id = auth.uid());

-- Admins can view and update complaints
CREATE POLICY "Admins full access on complaints"
ON public.complaints FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());
