-- ==============================================================================
-- Migration: 20261105000001_line_bus_capacity.sql
-- Run AFTER 20261104000002. Safe to re-run. Additive: one nullable column and
-- two new functions. save_line and get_supervisor_dashboard are not touched.
--
-- How many riders one bus of a line takes, set by the company in the dashboard
-- (one number per line, optional). The supervisor's Home uses it to say how
-- many buses a trip needs ("38 من 50", "يحتاج باصين").
--   * set_line_bus_capacity(line, capacity): whoever may edit the line.
--   * get_my_line_capacities(): the signed-in supervisor's own lines.
-- ==============================================================================
BEGIN;

-- As in 20261104000002: never queue the readers of lines behind this migration.
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.lines ADD COLUMN IF NOT EXISTS bus_capacity integer;
ALTER TABLE public.lines DROP CONSTRAINT IF EXISTS lines_bus_capacity_positive;
ALTER TABLE public.lines ADD CONSTRAINT lines_bus_capacity_positive
  CHECK (bus_capacity IS NULL OR bus_capacity > 0);

-- NULL clears it. Answers the capacity as saved.
CREATE OR REPLACE FUNCTION public.set_line_bus_capacity(p_line_id uuid, p_capacity integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM public.lines WHERE id = p_line_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الخط غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF public.can_manage_line_company(v_company) IS NOT TRUE THEN
    RAISE EXCEPTION 'غير مسموح بتعديل هذا الخط.' USING ERRCODE = '42501';
  END IF;
  IF p_capacity IS NOT NULL AND p_capacity NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'عدد مقاعد الباص من 1 إلى 500، أو اتركه فارغاً.' USING ERRCODE = '23514';
  END IF;
  UPDATE public.lines SET bus_capacity = p_capacity WHERE id = p_line_id;
  RETURN p_capacity;
END;
$$;
REVOKE ALL ON FUNCTION public.set_line_bus_capacity(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_line_bus_capacity(uuid, integer) TO authenticated;

-- [{"line_id": "<uuid>", "bus_capacity": 50 | null}, …] for the lines assigned
-- to the signed-in supervisor, by line name. Anyone else gets an empty list.
CREATE OR REPLACE FUNCTION public.get_my_line_capacities() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('line_id', l.id, 'bus_capacity', l.bus_capacity) ORDER BY l.name, l.id), '[]'::jsonb)
  FROM public.lines l
  WHERE l.id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
$$;
REVOKE ALL ON FUNCTION public.get_my_line_capacities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_line_capacities() TO authenticated;

COMMIT;
