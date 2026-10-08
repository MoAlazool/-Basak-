-- A student's own profile: what they may add or change themselves.
--   * a contact email, their college and their birth date, all optional
--   * their photo: a new one replaces the old, and the old file is removed
-- The name, phone and university stay fixed (a correction request changes them).
-- Students still cannot UPDATE the students table directly; the two functions
-- below are the only way in, and each touches its own columns only.

ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS birth_date date;
ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_email_format;
ALTER TABLE public.students ADD CONSTRAINT students_email_format
  CHECK (email IS NULL OR (length(email) <= 120 AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'));
ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_birth_date_range;
ALTER TABLE public.students ADD CONSTRAINT students_birth_date_range
  CHECK (birth_date IS NULL OR birth_date BETWEEN DATE '1940-01-01' AND DATE '2020-12-31');

-- Empty values clear a field. Returns the profile as saved.
CREATE OR REPLACE FUNCTION public.update_my_profile(p_email text, p_college text, p_birth_date date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_email text := NULLIF(lower(btrim(COALESCE(p_email, ''))), '');
  v_college text := NULLIF(btrim(COALESCE(p_college, '')), '');
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.students WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'متاح للطلاب فقط.' USING ERRCODE = '42501';
  END IF;
  IF v_email IS NOT NULL AND (length(v_email) > 120 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') THEN
    RAISE EXCEPTION 'اكتب بريداً إلكترونياً صحيحاً.' USING ERRCODE = '23514';
  END IF;
  IF length(COALESCE(v_college, '')) > 80 THEN
    RAISE EXCEPTION 'اسم الكلية طويل جداً.' USING ERRCODE = '23514';
  END IF;
  IF p_birth_date IS NOT NULL AND (p_birth_date > public.cairo_today() - INTERVAL '12 years' OR p_birth_date < DATE '1940-01-01') THEN
    RAISE EXCEPTION 'تاريخ الميلاد غير صحيح.' USING ERRCODE = '23514';
  END IF;
  UPDATE public.students
  SET email = v_email, college = COALESCE(v_college, 'غير محدد'), birth_date = p_birth_date
  WHERE id = auth.uid();
  RETURN (SELECT jsonb_build_object('email', s.email, 'college', s.college, 'birth_date', s.birth_date)
          FROM public.students s WHERE s.id = auth.uid());
END;
$$;
REVOKE ALL ON FUNCTION public.update_my_profile(text, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_profile(text, text, date) TO authenticated;

-- Points the profile at a photo the student has just uploaded to their own
-- folder. Returns the path of the photo it replaces, for the app to remove.
CREATE OR REPLACE FUNCTION public.set_my_profile_photo(p_path text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, storage AS $$
DECLARE v_old text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'متاح للطلاب فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT profile_image_url INTO v_old FROM public.students WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'متاح للطلاب فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_path IS NULL OR split_part(p_path, '/', 1) <> auth.uid()::text
     OR NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'student-avatars' AND o.name = p_path) THEN
    RAISE EXCEPTION 'ارفع الصورة أولاً ثم أعد المحاولة.' USING ERRCODE = '23514';
  END IF;
  UPDATE public.students SET profile_image_url = p_path WHERE id = auth.uid();
  RETURN CASE WHEN v_old IS DISTINCT FROM p_path THEN v_old END;
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_profile_photo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_profile_photo(text) TO authenticated;

-- A student may remove files from their own photo folder, except the photo
-- their profile uses now: the old one goes, the current one cannot be lost.
DROP POLICY IF EXISTS "Students can delete own old profile images" ON storage.objects;
CREATE POLICY "Students can delete own old profile images" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'student-avatars'
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
         AND name IS DISTINCT FROM (SELECT s.profile_image_url FROM public.students s WHERE s.id = (SELECT auth.uid())));
