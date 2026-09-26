-- =====================================================
-- ADMIN DASHBOARD RLS FIX
-- Run this in Supabase SQL Editor
-- Grants anon role full access to all admin tables
-- (Dashboard has no login — uses anon key directly)
-- =====================================================

-- ─── COMPANIES ────────────────────────────────────────
DROP POLICY IF EXISTS "anon full access companies" ON public.companies;
CREATE POLICY "anon full access companies" ON public.companies
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── LINES ────────────────────────────────────────────
DROP POLICY IF EXISTS "anon full access lines" ON public.lines;
CREATE POLICY "anon full access lines" ON public.lines
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── STATIONS ─────────────────────────────────────────
DROP POLICY IF EXISTS "anon full access stations" ON public.stations;
CREATE POLICY "anon full access stations" ON public.stations
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── SUPERVISORS ──────────────────────────────────────
DROP POLICY IF EXISTS "anon full access supervisors" ON public.supervisors;
CREATE POLICY "anon full access supervisors" ON public.supervisors
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── STUDENTS ─────────────────────────────────────────
DROP POLICY IF EXISTS "anon full access students" ON public.students;
CREATE POLICY "anon full access students" ON public.students
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── SUBSCRIPTIONS ────────────────────────────────────
DROP POLICY IF EXISTS "anon full access subscriptions" ON public.subscriptions;
CREATE POLICY "anon full access subscriptions" ON public.subscriptions
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── RECEIPTS ─────────────────────────────────────────
DROP POLICY IF EXISTS "anon full access receipts" ON public.receipts;
CREATE POLICY "anon full access receipts" ON public.receipts
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── DAILY RIDE STATUS ────────────────────────────────
DROP POLICY IF EXISTS "anon full access daily_ride_status" ON public.daily_ride_status;
CREATE POLICY "anon full access daily_ride_status" ON public.daily_ride_status
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── LINE STATIONS (junction table) ───────────────────
DROP POLICY IF EXISTS "anon full access line_stations" ON public.line_stations;
CREATE POLICY "anon full access line_stations" ON public.line_stations
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─── PROFILES (if exists) ─────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'profiles') THEN
    DROP POLICY IF EXISTS "anon full access profiles" ON public.profiles;
    CREATE POLICY "anon full access profiles" ON public.profiles
      FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

SELECT 'Admin RLS policies applied successfully ✓' AS result;
