-- ╔══════════════════════════════════════════════════════════════════╗
-- ║          BASAK ADMIN — COMPLETE DATABASE RESET & FIX            ║
-- ║  Run this ONCE in Supabase SQL Editor                           ║
-- ║  Does 3 things:                                                  ║
-- ║   1. Cleans ALL fake/seed data                                  ║
-- ║   2. Fixes supervisors.id and stations nullable times            ║
-- ║   3. Sets correct RLS policies for every table                  ║
-- ╚══════════════════════════════════════════════════════════════════╝


-- ════════════════════════════════════════════════════════════════════
-- PART 1 — CLEAN ALL FAKE / SEED DATA
-- Order matters: delete child tables first (FK order)
-- ════════════════════════════════════════════════════════════════════

DELETE FROM public.daily_ride_status;
DELETE FROM public.receipts;
DELETE FROM public.subscriptions;
DELETE FROM public.students;
DELETE FROM public.stations;
DELETE FROM public.supervisors;
DELETE FROM public.lines;
DELETE FROM public.companies;

-- Reset sequences if any (UUIDs don't need it, but just in case)
-- (No sequences for UUID-based tables)


-- ════════════════════════════════════════════════════════════════════
-- PART 2 — SCHEMA FIXES
-- ════════════════════════════════════════════════════════════════════

-- 2a. Fix supervisors.id:
--     Currently: id UUID PRIMARY KEY REFERENCES auth.users(id)
--     Problem:   Admin can't insert supervisors from dashboard (no auth account)
--     Fix:       Remove the FK to auth.users, add DEFAULT gen_random_uuid()

ALTER TABLE public.supervisors
  DROP CONSTRAINT IF EXISTS supervisors_id_fkey;

ALTER TABLE public.supervisors
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 2b. Fix stations times:
--     Currently: departure_time TIME NOT NULL, return_time TIME NOT NULL
--     Problem:   Admin might add stations without times yet
--     Fix:       Make them nullable

ALTER TABLE public.stations
  ALTER COLUMN departure_time DROP NOT NULL,
  ALTER COLUMN return_time    DROP NOT NULL;


-- ════════════════════════════════════════════════════════════════════
-- PART 3 — RLS POLICIES: FULL AUDIT & REWRITE
-- The admin dashboard uses the anon key with no auth.
-- We grant anon role exactly the access it needs per table.
-- ════════════════════════════════════════════════════════════════════

-- ── 3.1 COMPANIES ─────────────────────────────────────────────────
-- Admin: SELECT, INSERT, UPDATE (toggle active)
-- App (students/supervisors): SELECT active companies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access companies"        ON public.companies;
DROP POLICY IF EXISTS "Public read companies"             ON public.companies;
DROP POLICY IF EXISTS "Admin write companies"             ON public.companies;
CREATE POLICY "anon_rw_companies" ON public.companies
  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "auth_r_companies" ON public.companies
  FOR SELECT TO authenticated USING (is_active = true);

-- ── 3.2 LINES ─────────────────────────────────────────────────────
-- Admin: SELECT, INSERT, UPDATE, DELETE
-- App: SELECT active lines
ALTER TABLE public.lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access lines"  ON public.lines;
DROP POLICY IF EXISTS "Public read lines"        ON public.lines;
DROP POLICY IF EXISTS "Admin write lines"        ON public.lines;
CREATE POLICY "anon_rw_lines" ON public.lines
  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "auth_r_lines" ON public.lines
  FOR SELECT TO authenticated USING (is_active = true);

-- ── 3.3 STATIONS ──────────────────────────────────────────────────
-- Admin: SELECT, INSERT, UPDATE, DELETE
-- App: SELECT all stations (for displaying line stops)
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access stations"  ON public.stations;
DROP POLICY IF EXISTS "Public read stations"        ON public.stations;
DROP POLICY IF EXISTS "Admin write stations"        ON public.stations;
CREATE POLICY "anon_rw_stations" ON public.stations
  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "auth_r_stations" ON public.stations
  FOR SELECT TO authenticated USING (true);

-- ── 3.4 SUPERVISORS ───────────────────────────────────────────────
-- Admin: SELECT, INSERT, UPDATE (toggle active), DELETE
-- App: supervisor reads own row only
ALTER TABLE public.supervisors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access supervisors"         ON public.supervisors;
DROP POLICY IF EXISTS "Supervisor own read"                  ON public.supervisors;
DROP POLICY IF EXISTS "Admin manage supervisors"             ON public.supervisors;
CREATE POLICY "anon_rw_supervisors" ON public.supervisors
  FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "auth_r_own_supervisor" ON public.supervisors
  FOR SELECT TO authenticated USING (id = auth.uid());

-- ── 3.5 STUDENTS ──────────────────────────────────────────────────
-- Admin: SELECT all (for receipt review panel)
-- App: student manages own row; supervisor reads all
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access students"   ON public.students;
DROP POLICY IF EXISTS "Student own read/write"       ON public.students;
DROP POLICY IF EXISTS "Supervisor read students"     ON public.students;
DROP POLICY IF EXISTS "Admin read students"          ON public.students;
CREATE POLICY "anon_r_students" ON public.students
  FOR SELECT TO anon USING (true);
-- Students can read/write their own row
CREATE POLICY "auth_own_student" ON public.students
  FOR ALL TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
-- Supervisors and admin can read all students
CREATE POLICY "auth_r_all_students" ON public.students
  FOR SELECT TO authenticated USING (true);

-- ── 3.6 SUBSCRIPTIONS ─────────────────────────────────────────────
-- Admin: SELECT all, UPDATE status (approve/reject via receipt)
-- App: student manages own; supervisor reads all on their line
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access subscriptions"  ON public.subscriptions;
DROP POLICY IF EXISTS "Student own subscription"         ON public.subscriptions;
DROP POLICY IF EXISTS "Admin manage subscriptions"       ON public.subscriptions;
CREATE POLICY "anon_r_subscriptions" ON public.subscriptions
  FOR SELECT TO anon USING (true);
CREATE POLICY "anon_u_subscriptions" ON public.subscriptions
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- Student owns their subscription
CREATE POLICY "auth_own_subscription" ON public.subscriptions
  FOR ALL TO authenticated USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());
-- Supervisor/admin can read all
CREATE POLICY "auth_r_all_subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated USING (true);

-- ── 3.7 RECEIPTS ──────────────────────────────────────────────────
-- Admin: SELECT pending, UPDATE (approve/reject with reason)
-- App: student inserts own receipts; can read own
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access receipts"   ON public.receipts;
DROP POLICY IF EXISTS "Student insert receipt"       ON public.receipts;
DROP POLICY IF EXISTS "Student read own receipt"     ON public.receipts;
DROP POLICY IF EXISTS "Admin manage receipts"        ON public.receipts;
-- Admin dashboard (anon): read all + update (approve/reject)
CREATE POLICY "anon_r_receipts" ON public.receipts
  FOR SELECT TO anon USING (true);
CREATE POLICY "anon_u_receipts" ON public.receipts
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- Students: insert their own receipt
CREATE POLICY "auth_insert_receipt" ON public.receipts
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.id = subscription_id AND s.student_id = auth.uid()
    )
  );
-- Students: read their own receipts
CREATE POLICY "auth_r_own_receipts" ON public.receipts
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.id = subscription_id AND s.student_id = auth.uid()
    )
  );
-- Supervisors/admin read all
CREATE POLICY "auth_r_all_receipts" ON public.receipts
  FOR SELECT TO authenticated USING (true);

-- ── 3.8 DAILY_RIDE_STATUS ─────────────────────────────────────────
-- Admin: SELECT all (for charts/overview)
-- App: student toggles own; supervisor reads all on their line
ALTER TABLE public.daily_ride_status ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon full access daily_ride_status"  ON public.daily_ride_status;
DROP POLICY IF EXISTS "Student toggle ride status"           ON public.daily_ride_status;
DROP POLICY IF EXISTS "Supervisor read ride status"          ON public.daily_ride_status;
CREATE POLICY "anon_r_daily_ride" ON public.daily_ride_status
  FOR SELECT TO anon USING (true);
-- Student manages own toggle
CREATE POLICY "auth_own_daily_ride" ON public.daily_ride_status
  FOR ALL TO authenticated
  USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());
-- Supervisor/admin read all
CREATE POLICY "auth_r_all_daily_ride" ON public.daily_ride_status
  FOR SELECT TO authenticated USING (true);

-- ── 3.9 LINE_STATIONS (junction, if exists) ───────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'line_stations') THEN
    EXECUTE 'ALTER TABLE public.line_stations ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "anon full access line_stations" ON public.line_stations';
    EXECUTE 'CREATE POLICY "anon_rw_line_stations" ON public.line_stations FOR ALL TO anon USING (true) WITH CHECK (true)';
    EXECUTE 'CREATE POLICY "auth_r_line_stations" ON public.line_stations FOR SELECT TO authenticated USING (true)';
  END IF;
END $$;

-- ── 3.10 CHAT_MESSAGES (if exists) ────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'chat_messages') THEN
    EXECUTE 'ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "anon full access chat_messages" ON public.chat_messages';
    EXECUTE 'CREATE POLICY "anon_r_chat" ON public.chat_messages FOR SELECT TO anon USING (true)';
    EXECUTE 'CREATE POLICY "auth_rw_chat" ON public.chat_messages FOR ALL TO authenticated USING (true) WITH CHECK (true)';
  END IF;
END $$;


-- ════════════════════════════════════════════════════════════════════
-- PART 4 — STORAGE BUCKET RLS (receipts bucket)
-- ════════════════════════════════════════════════════════════════════
-- Allow anon to read receipt images (for admin preview)
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Admin can view receipts" ON storage.objects;
DROP POLICY IF EXISTS "Students can upload receipts" ON storage.objects;
DROP POLICY IF EXISTS "anon read receipts storage" ON storage.objects;

CREATE POLICY "anon_r_receipts_storage" ON storage.objects
  FOR SELECT TO anon
  USING (bucket_id = 'receipts');

CREATE POLICY "auth_upload_receipts" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'receipts' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "auth_r_own_receipt_file" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'receipts');


-- ════════════════════════════════════════════════════════════════════
-- DONE
-- ════════════════════════════════════════════════════════════════════
SELECT
  'All done ✓' AS status,
  'Data cleared, schema fixed, RLS policies applied' AS details;
