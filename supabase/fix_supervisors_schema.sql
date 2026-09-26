-- =====================================================
-- Fix supervisors.id - Remove auth.users dependency only
-- Keeps PRIMARY KEY intact (other tables reference it)
-- =====================================================

-- Step 1: Drop ONLY the foreign key to auth.users
--         (NOT the primary key itself)
ALTER TABLE public.supervisors
  DROP CONSTRAINT IF EXISTS supervisors_id_fkey;

-- Step 2: Add default UUID generation to the column
ALTER TABLE public.supervisors
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Step 3: Make stations times optional (nullable)
ALTER TABLE public.stations
  ALTER COLUMN departure_time DROP NOT NULL,
  ALTER COLUMN return_time    DROP NOT NULL;

SELECT 'Schema fixed successfully ✓' AS result;
