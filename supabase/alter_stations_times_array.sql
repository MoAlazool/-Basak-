-- ════════════════════════════════════════════════════════
-- Change stations: single time → arrays of times
-- departure_time TIME  → departure_times TIME[]
-- return_time    TIME  → return_times    TIME[]
-- ════════════════════════════════════════════════════════

ALTER TABLE public.stations
  DROP COLUMN IF EXISTS departure_time,
  DROP COLUMN IF EXISTS return_time,
  ADD COLUMN departure_times TIME[] NOT NULL DEFAULT '{}',
  ADD COLUMN return_times    TIME[] NOT NULL DEFAULT '{}';

SELECT 'Stations times updated to arrays ✓' AS result;
