-- lines.destination_university_id was added on the live project outside the
-- migrations. The next migration reads it, so a fresh database needs it here.
ALTER TABLE public.lines
  ADD COLUMN IF NOT EXISTS destination_university_id uuid REFERENCES public.universities(id) ON DELETE SET NULL;
