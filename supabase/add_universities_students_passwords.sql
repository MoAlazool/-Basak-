-- ══════════════════════════════════════════════════════════════════
-- 1. UNIVERSITIES / DESTINATIONS TABLE (كاتيجوري الجامعات ووجهات الوصول)
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.universities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    city TEXT DEFAULT 'المنصورة',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS for universities
ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_rw_universities" ON public.universities;
DROP POLICY IF EXISTS "auth_r_universities" ON public.universities;

CREATE POLICY "anon_rw_universities" ON public.universities
    FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "auth_r_universities" ON public.universities
    FOR SELECT TO authenticated USING (true);

-- Insert common university destinations if empty
INSERT INTO public.universities (name, city) VALUES
    ('جامعة المنصورة', 'المنصورة'),
    ('جامعة المنصورة الأهلية', 'جمصة'),
    ('جامعة الدلتا للعلوم والتكنولوجيا', 'جمصة'),
    ('جامعة حورس', 'دمياط الجديدة'),
    ('جامعة السلاب', 'المنصورة'),
    ('جامعة دمياط', 'دمياط الجديدة')
ON CONFLICT (name) DO NOTHING;


-- ══════════════════════════════════════════════════════════════════
-- 2. SUPERVISORS PASSWORD & STANDALONE SUPPORT
-- ══════════════════════════════════════════════════════════════════

-- Add password column to supervisors table so admin can assign and view it
ALTER TABLE public.supervisors ADD COLUMN IF NOT EXISTS password TEXT DEFAULT '123456';

-- Make sure supervisors.id doesn't block on auth.users FK
ALTER TABLE public.supervisors DROP CONSTRAINT IF EXISTS supervisors_id_fkey;
ALTER TABLE public.supervisors ALTER COLUMN id SET DEFAULT gen_random_uuid();


-- ══════════════════════════════════════════════════════════════════
-- 3. STUDENTS STANDALONE SUPPORT & PASSWORD
-- ══════════════════════════════════════════════════════════════════

-- Add password column to students so admin can view/manage it
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS password TEXT DEFAULT '123456';

-- Drop foreign key to auth.users if it exists so admin can insert students freely
ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_id_fkey;
ALTER TABLE public.students ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Allow anon to INSERT and DELETE students in RLS
DROP POLICY IF EXISTS "anon_rw_students" ON public.students;
DROP POLICY IF EXISTS "anon_r_students" ON public.students;

CREATE POLICY "anon_rw_students" ON public.students
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Ensure lines can optionally reference destination university
ALTER TABLE public.lines ADD COLUMN IF NOT EXISTS destination_university_id UUID REFERENCES public.universities(id) ON DELETE SET NULL;

SELECT 'Universities, students, and supervisor passwords configured successfully ✓' AS result;
