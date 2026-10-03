-- ==============================================================================
-- Migration: 20261005000001_line_trips.sql
-- Run AFTER 20261004000003_student_password_reset.sql. Safe to re-run.
--
-- Line redesign: Line + Stations + Trips + Stop times.
--
--   lines            the route: origin → ordered stations → destination university
--   stations         ordered stops of the route (order_index)
--   line_trips       departure / return trips of a line: label, start time,
--                    arrival time, university (NULL = open to every university)
--   line_trip_stops  the time a trip passes each station
--
-- A line is created / edited as ONE atomic operation (save_line), disabled /
-- enabled with set_line_active, and deleted with delete_line (only when nothing
-- references it — otherwise it must be disabled so history is kept).
--
-- Compatibility: subscriptions keep departure_time / return_time (now the stop
-- time of the chosen trip at the student's station) plus departure_trip_id /
-- return_trip_id. stations.departure_times / return_times are kept in sync from
-- the trips for older app versions. line_university_schedules is migrated into
-- trips and frozen (kept for history).
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Schema
-- ------------------------------------------------------------------------------
ALTER TABLE public.lines ADD COLUMN IF NOT EXISTS origin_name text;
UPDATE public.lines SET origin_name = name WHERE origin_name IS NULL OR btrim(origin_name) = '';

CREATE TABLE IF NOT EXISTS public.line_trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id uuid NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('departure', 'return')),
  label text NOT NULL DEFAULT '',
  start_time time NOT NULL,
  arrival_time time,
  university_id uuid REFERENCES public.universities(id) ON DELETE RESTRICT,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_line_trips_line ON public.line_trips(line_id, direction, start_time);
CREATE INDEX IF NOT EXISTS idx_line_trips_university ON public.line_trips(university_id);

CREATE TABLE IF NOT EXISTS public.line_trip_stops (
  trip_id uuid NOT NULL REFERENCES public.line_trips(id) ON DELETE CASCADE,
  station_id uuid NOT NULL REFERENCES public.stations(id) ON DELETE CASCADE,
  stop_time time NOT NULL,
  PRIMARY KEY (trip_id, station_id)
);
CREATE INDEX IF NOT EXISTS idx_line_trip_stops_station ON public.line_trip_stops(station_id);

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS departure_trip_id uuid REFERENCES public.line_trips(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS return_trip_id uuid REFERENCES public.line_trips(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_subscriptions_departure_trip ON public.subscriptions(departure_trip_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_return_trip ON public.subscriptions(return_trip_id);

-- ------------------------------------------------------------------------------
-- 2. Data migration (only lines that have no trips yet)
-- ------------------------------------------------------------------------------
-- 2a. University schedules → one departure + one return trip per university.
INSERT INTO public.line_trips (line_id, direction, label, start_time, university_id, is_active)
SELECT sch.line_id, d.direction, '', CASE d.direction WHEN 'departure' THEN sch.departure_time ELSE sch.return_time END,
       sch.university_id, sch.is_active
FROM public.line_university_schedules sch
CROSS JOIN (VALUES ('departure'), ('return')) d(direction)
WHERE NOT EXISTS (SELECT 1 FROM public.line_trips t WHERE t.line_id = sch.line_id);

INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time)
SELECT t.id, st.id, t.start_time
FROM public.line_trips t JOIN public.stations st ON st.line_id = t.line_id
WHERE t.university_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.line_university_schedules s WHERE s.line_id = t.line_id)
ON CONFLICT DO NOTHING;

-- 2b. Station time lists → one trip per distinct time (open to every university);
--     a station is a stop of that trip when its list contains the time.
WITH legacy AS (
  SELECT st.line_id, 'departure'::text AS direction, x.t
  FROM public.stations st CROSS JOIN LATERAL unnest(st.departure_times) x(t)
  UNION
  SELECT st.line_id, 'return', x.t
  FROM public.stations st CROSS JOIN LATERAL unnest(st.return_times) x(t)
)
INSERT INTO public.line_trips (line_id, direction, label, start_time)
SELECT DISTINCT l.line_id, l.direction, '', l.t
FROM legacy l
WHERE NOT EXISTS (SELECT 1 FROM public.line_trips t WHERE t.line_id = l.line_id);

INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time)
SELECT t.id, st.id, t.start_time
FROM public.line_trips t
JOIN public.stations st ON st.line_id = t.line_id
WHERE t.university_id IS NULL
  AND t.start_time = ANY (CASE t.direction WHEN 'departure' THEN st.departure_times ELSE st.return_times END)
ON CONFLICT DO NOTHING;

-- 2c. Existing subscriptions → the trip whose stop at their station matches their time.
UPDATE public.subscriptions sub SET departure_trip_id = (
  SELECT t.id FROM public.line_trips t JOIN public.line_trip_stops s ON s.trip_id = t.id
  WHERE t.line_id = sub.line_id AND t.direction = 'departure' AND s.station_id = sub.station_id
    AND s.stop_time = sub.departure_time
  ORDER BY t.university_id NULLS LAST LIMIT 1)
WHERE sub.departure_trip_id IS NULL AND sub.departure_time IS NOT NULL;

UPDATE public.subscriptions sub SET return_trip_id = (
  SELECT t.id FROM public.line_trips t JOIN public.line_trip_stops s ON s.trip_id = t.id
  WHERE t.line_id = sub.line_id AND t.direction = 'return' AND s.station_id = sub.station_id
    AND s.stop_time = sub.return_time
  ORDER BY t.university_id NULLS LAST LIMIT 1)
WHERE sub.return_trip_id IS NULL AND sub.return_time IS NOT NULL;

-- Schedules are now trips: stop the old propagation trigger (table kept for history).
DROP TRIGGER IF EXISTS trg_apply_line_university_schedule ON public.line_university_schedules;

-- ------------------------------------------------------------------------------
-- 3. Helpers
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_manage_line_company(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
      OR (public.is_company_admin() AND p_company_id = public.current_admin_company_id())
$$;

-- Trips a given student may ride: active, and open to every university or to theirs.
CREATE OR REPLACE FUNCTION public.trip_serves_student(p_trip public.line_trips, p_student_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_trip.is_active AND (
    p_trip.university_id IS NULL
    OR p_trip.university_id = (SELECT university_id FROM public.students WHERE id = p_student_id))
$$;

-- Keep the legacy station time lists equal to the trips' stop times.
CREATE OR REPLACE FUNCTION public.sync_station_times(p_line_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.stations st SET
    departure_times = COALESCE((SELECT array_agg(DISTINCT s.stop_time ORDER BY s.stop_time)
      FROM public.line_trip_stops s JOIN public.line_trips t ON t.id = s.trip_id
      WHERE s.station_id = st.id AND t.direction = 'departure' AND t.is_active), '{}'),
    return_times = COALESCE((SELECT array_agg(DISTINCT s.stop_time ORDER BY s.stop_time)
      FROM public.line_trip_stops s JOIN public.line_trips t ON t.id = s.trip_id
      WHERE s.station_id = st.id AND t.direction = 'return' AND t.is_active), '{}')
  WHERE st.line_id = p_line_id;
  UPDATE public.stations st SET departure_time = st.departure_times[1], return_time = st.return_times[1]
  WHERE st.line_id = p_line_id;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_station_times(uuid) FROM PUBLIC, anon, authenticated;
SELECT public.sync_station_times(id) FROM public.lines
WHERE EXISTS (SELECT 1 FROM public.line_trips t WHERE t.line_id = lines.id);

-- ------------------------------------------------------------------------------
-- 4. Save a complete line atomically
-- ------------------------------------------------------------------------------
-- p_line = {
--   id?, company_id, name, origin_name, destination_university_id?,
--   price_termly, price_yearly, price_daily, is_active?,
--   stations: [{ id?, name }]                                  -- route order
--   trips: [{ id?, direction, label?, start_time, arrival_time?,
--             university_id?, is_active?,
--             stops: [{ station_index, time }] }]               -- index into stations
-- }
CREATE OR REPLACE FUNCTION public.save_line(p_line jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line_id uuid := NULLIF(p_line->>'id', '')::uuid;
  v_company uuid := NULLIF(p_line->>'company_id', '')::uuid;
  v_existing public.lines%ROWTYPE;
  v_name text := btrim(COALESCE(p_line->>'name', ''));
  v_origin text := btrim(COALESCE(p_line->>'origin_name', ''));
  v_dest uuid := NULLIF(p_line->>'destination_university_id', '')::uuid;
  v_stations jsonb := COALESCE(p_line->'stations', '[]'::jsonb);
  v_trips jsonb := COALESCE(p_line->'trips', '[]'::jsonb);
  v_station_ids uuid[] := '{}';
  v_kept_trips uuid[] := '{}';
  v_station jsonb;
  v_trip jsonb;
  v_stop jsonb;
  v_sid uuid;
  v_tid uuid;
  v_idx int;
  v_prev time;
  v_time time;
  v_order int;
  v_seen text[] := '{}';
  v_key text;
BEGIN
  IF v_line_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.lines WHERE id = v_line_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.' USING ERRCODE = 'P0002'; END IF;
    IF NOT public.can_manage_line_company(v_existing.company_id) THEN
      RAISE EXCEPTION 'غير مسموح بتعديل هذا الخط.' USING ERRCODE = '42501';
    END IF;
    v_company := v_existing.company_id;  -- a line never changes company
  ELSE
    IF public.is_company_admin() THEN v_company := public.current_admin_company_id(); END IF;
    IF v_company IS NULL OR NOT public.can_manage_line_company(v_company) THEN
      RAISE EXCEPTION 'غير مسموح بإنشاء خط لهذه الشركة.' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ---- validation --------------------------------------------------------
  IF v_name = '' THEN RAISE EXCEPTION 'اكتب اسم الخط.' USING ERRCODE = '23514'; END IF;
  IF v_origin = '' THEN RAISE EXCEPTION 'حدد نقطة البداية.' USING ERRCODE = '23514'; END IF;
  IF v_dest IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.universities WHERE id = v_dest) THEN
    RAISE EXCEPTION 'الجامعة (الوجهة) غير موجودة.' USING ERRCODE = '23514';
  END IF;
  IF COALESCE((p_line->>'price_termly')::numeric, -1) < 0 OR COALESCE((p_line->>'price_yearly')::numeric, -1) < 0
     OR COALESCE((p_line->>'price_daily')::numeric, -1) < 0 THEN
    RAISE EXCEPTION 'الأسعار مطلوبة ولا يمكن أن تكون سالبة.' USING ERRCODE = '23514';
  END IF;
  IF jsonb_array_length(v_stations) = 0 THEN
    RAISE EXCEPTION 'أضف محطة واحدة على الأقل بين البداية والوجهة.' USING ERRCODE = '23514';
  END IF;
  FOR v_idx IN 0 .. jsonb_array_length(v_stations) - 1 LOOP
    IF btrim(COALESCE(v_stations->v_idx->>'name', '')) = '' THEN
      RAISE EXCEPTION 'اسم المحطة رقم % فارغ.', v_idx + 1 USING ERRCODE = '23514';
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_trips) t WHERE t->>'direction' = 'departure') THEN
    RAISE EXCEPTION 'أضف رحلة ذهاب واحدة على الأقل بموعد انطلاقها.' USING ERRCODE = '23514';
  END IF;

  FOR v_trip IN SELECT * FROM jsonb_array_elements(v_trips) LOOP
    IF v_trip->>'direction' NOT IN ('departure', 'return') THEN
      RAISE EXCEPTION 'نوع الرحلة غير صحيح.' USING ERRCODE = '23514';
    END IF;
    IF NULLIF(v_trip->>'start_time', '') IS NULL THEN
      RAISE EXCEPTION 'حدد موعد انطلاق كل رحلة.' USING ERRCODE = '23514';
    END IF;
    IF NULLIF(v_trip->>'university_id', '') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.universities WHERE id = (v_trip->>'university_id')::uuid) THEN
      RAISE EXCEPTION 'جامعة إحدى الرحلات غير موجودة.' USING ERRCODE = '23514';
    END IF;
    v_key := (v_trip->>'direction') || '|' || (v_trip->>'start_time')::time || '|' || COALESCE(v_trip->>'university_id', '');
    IF v_key = ANY (v_seen) THEN
      RAISE EXCEPTION 'رحلتان بنفس الاتجاه والموعد والجامعة. عدّل إحداهما.' USING ERRCODE = '23514';
    END IF;
    v_seen := v_seen || v_key;
    IF jsonb_array_length(COALESCE(v_trip->'stops', '[]'::jsonb)) = 0 THEN
      RAISE EXCEPTION 'رحلة % لا تمر بأي محطة. حدد موعد المرور على المحطات.', (v_trip->>'start_time')::time
        USING ERRCODE = '23514';
    END IF;
    -- Stop times follow the route: forward for departures, reversed for returns,
    -- and never before the trip's start time.
    v_prev := (v_trip->>'start_time')::time;
    FOR v_stop IN
      SELECT s FROM jsonb_array_elements(v_trip->'stops') s
      ORDER BY CASE WHEN v_trip->>'direction' = 'departure' THEN (s->>'station_index')::int
                    ELSE -(s->>'station_index')::int END
    LOOP
      v_idx := (v_stop->>'station_index')::int;
      IF v_idx IS NULL OR v_idx < 0 OR v_idx >= jsonb_array_length(v_stations) THEN
        RAISE EXCEPTION 'محطة غير معروفة في إحدى الرحلات.' USING ERRCODE = '23514';
      END IF;
      v_time := NULLIF(v_stop->>'time', '')::time;
      IF v_time IS NULL THEN CONTINUE; END IF;
      IF v_time < v_prev THEN
        RAISE EXCEPTION 'موعد محطة "%" (%) في رحلة % أسبق من المحطة التي قبلها. المواعيد يجب أن تكون بترتيب المسار.',
          v_stations->v_idx->>'name', v_time, (v_trip->>'start_time')::time USING ERRCODE = '23514';
      END IF;
      v_prev := v_time;
    END LOOP;
    IF NULLIF(v_trip->>'arrival_time', '') IS NOT NULL AND (v_trip->>'arrival_time')::time < v_prev THEN
      RAISE EXCEPTION 'موعد الوصول في رحلة % أسبق من آخر محطة.', (v_trip->>'start_time')::time USING ERRCODE = '23514';
    END IF;
  END LOOP;

  -- ---- line --------------------------------------------------------------
  IF v_line_id IS NULL THEN
    INSERT INTO public.lines (company_id, name, origin_name, destination_university_id,
                              price_termly, price_yearly, price_daily, is_active)
    VALUES (v_company, v_name, v_origin, v_dest, (p_line->>'price_termly')::numeric,
            (p_line->>'price_yearly')::numeric, (p_line->>'price_daily')::numeric,
            COALESCE((p_line->>'is_active')::boolean, true))
    RETURNING id INTO v_line_id;
  ELSE
    UPDATE public.lines SET name = v_name, origin_name = v_origin, destination_university_id = v_dest,
      price_termly = (p_line->>'price_termly')::numeric, price_yearly = (p_line->>'price_yearly')::numeric,
      price_daily = (p_line->>'price_daily')::numeric,
      is_active = COALESCE((p_line->>'is_active')::boolean, is_active)
    WHERE id = v_line_id;
  END IF;

  -- ---- stations (keep ids; move order out of the way of the unique index) ---
  UPDATE public.stations SET order_index = -1000 - order_index WHERE line_id = v_line_id;
  v_order := 0;
  FOR v_station IN SELECT * FROM jsonb_array_elements(v_stations) LOOP
    v_order := v_order + 1;
    v_sid := NULLIF(v_station->>'id', '')::uuid;
    IF v_sid IS NOT NULL AND EXISTS (SELECT 1 FROM public.stations WHERE id = v_sid AND line_id = v_line_id) THEN
      UPDATE public.stations SET name = btrim(v_station->>'name'), order_index = v_order, is_active = true
      WHERE id = v_sid;
    ELSE
      INSERT INTO public.stations (line_id, name, order_index, departure_times, return_times, is_active)
      VALUES (v_line_id, btrim(v_station->>'name'), v_order, '{}', '{}', true)
      RETURNING id INTO v_sid;
    END IF;
    v_station_ids := v_station_ids || v_sid;
  END LOOP;
  -- Removed stations: delete when unused, otherwise retire them (history kept).
  DELETE FROM public.stations st WHERE st.line_id = v_line_id AND NOT (st.id = ANY (v_station_ids))
    AND NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.station_id = st.id)
    AND NOT EXISTS (SELECT 1 FROM public.supervisor_scan_events e WHERE e.station_id = st.id);
  UPDATE public.stations st SET is_active = false, order_index = 10000 + abs(order_index)
  WHERE st.line_id = v_line_id AND NOT (st.id = ANY (v_station_ids));

  -- ---- trips + stop times ---------------------------------------------------
  FOR v_trip IN SELECT * FROM jsonb_array_elements(v_trips) LOOP
    v_tid := NULLIF(v_trip->>'id', '')::uuid;
    IF v_tid IS NOT NULL AND EXISTS (SELECT 1 FROM public.line_trips WHERE id = v_tid AND line_id = v_line_id) THEN
      UPDATE public.line_trips SET direction = v_trip->>'direction', label = btrim(COALESCE(v_trip->>'label', '')),
        start_time = (v_trip->>'start_time')::time, arrival_time = NULLIF(v_trip->>'arrival_time', '')::time,
        university_id = NULLIF(v_trip->>'university_id', '')::uuid,
        is_active = COALESCE((v_trip->>'is_active')::boolean, true), updated_at = now()
      WHERE id = v_tid;
      DELETE FROM public.line_trip_stops WHERE trip_id = v_tid;
    ELSE
      INSERT INTO public.line_trips (line_id, direction, label, start_time, arrival_time, university_id, is_active)
      VALUES (v_line_id, v_trip->>'direction', btrim(COALESCE(v_trip->>'label', '')),
              (v_trip->>'start_time')::time, NULLIF(v_trip->>'arrival_time', '')::time,
              NULLIF(v_trip->>'university_id', '')::uuid, COALESCE((v_trip->>'is_active')::boolean, true))
      RETURNING id INTO v_tid;
    END IF;
    v_kept_trips := v_kept_trips || v_tid;
    INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time)
    SELECT v_tid, v_station_ids[(s->>'station_index')::int + 1], (s->>'time')::time
    FROM jsonb_array_elements(v_trip->'stops') s
    WHERE NULLIF(s->>'time', '') IS NOT NULL;
  END LOOP;
  -- Removed trips: delete when unused, otherwise deactivate (history kept).
  DELETE FROM public.line_trips t WHERE t.line_id = v_line_id AND NOT (t.id = ANY (v_kept_trips))
    AND NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.departure_trip_id = t.id OR s.return_trip_id = t.id);
  UPDATE public.line_trips t SET is_active = false, updated_at = now()
  WHERE t.line_id = v_line_id AND NOT (t.id = ANY (v_kept_trips));

  -- Current subscribers follow their trip's new stop time.
  UPDATE public.subscriptions sub SET departure_time = s.stop_time
  FROM public.line_trip_stops s
  WHERE sub.line_id = v_line_id AND s.trip_id = sub.departure_trip_id AND s.station_id = sub.station_id
    AND sub.status IN ('pending_payment', 'pending_review', 'active') AND sub.departure_time IS DISTINCT FROM s.stop_time;
  UPDATE public.subscriptions sub SET return_time = s.stop_time
  FROM public.line_trip_stops s
  WHERE sub.line_id = v_line_id AND s.trip_id = sub.return_trip_id AND s.station_id = sub.station_id
    AND sub.status IN ('pending_payment', 'pending_review', 'active') AND sub.return_time IS DISTINCT FROM s.stop_time;

  PERFORM public.sync_station_times(v_line_id);
  RETURN v_line_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_line(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_line(jsonb) TO authenticated;

-- ------------------------------------------------------------------------------
-- 5. Enable / disable and delete
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_line_active(p_line_id uuid, p_active boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM public.lines WHERE id = p_line_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.can_manage_line_company(v_company) THEN
    RAISE EXCEPTION 'غير مسموح بتعديل هذا الخط.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.lines SET is_active = p_active WHERE id = p_line_id;
END;
$$;

-- Permanently deletes a line that has never been used. A line with any
-- subscription / scan history must be disabled instead.
CREATE OR REPLACE FUNCTION public.delete_line(p_line_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM public.lines WHERE id = p_line_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.can_manage_line_company(v_company) THEN
    RAISE EXCEPTION 'غير مسموح بحذف هذا الخط.' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.subscriptions WHERE line_id = p_line_id)
     OR EXISTS (SELECT 1 FROM public.supervisor_scan_events WHERE line_id = p_line_id)
     OR EXISTS (SELECT 1 FROM public.deleted_student_revenue WHERE line_id = p_line_id) THEN
    RAISE EXCEPTION 'لا يمكن حذف خط له اشتراكات أو سجلات سابقة. عطّل الخط بدلاً من حذفه للحفاظ على السجلات.'
      USING ERRCODE = '23503';
  END IF;
  DELETE FROM public.lines WHERE id = p_line_id;  -- cascades stations, trips, stops, assignments
END;
$$;
REVOKE ALL ON FUNCTION public.set_line_active(uuid, boolean), public.delete_line(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_line_active(uuid, boolean), public.delete_line(uuid) TO authenticated;

-- A disabled line takes no new supervisor assignments.
CREATE OR REPLACE FUNCTION public.validate_supervisor_line()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.supervisors s JOIN public.lines l ON l.company_id = s.company_id
    WHERE s.id = NEW.supervisor_id AND l.id = NEW.line_id
  ) THEN
    RAISE EXCEPTION 'الخط المختار لا يتبع شركة المشرف.' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' AND NOT EXISTS (SELECT 1 FROM public.lines WHERE id = NEW.line_id AND is_active) THEN
    RAISE EXCEPTION 'الخط معطّل ولا يمكن إسناده لمشرف جديد.' USING ERRCODE = '23514';
  END IF;
  NEW.assigned_by := COALESCE(NEW.assigned_by, auth.uid());
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. RLS: trips follow the line's tenant; students see only trips for them.
--    Writes go through save_line (SECURITY DEFINER) only.
-- ------------------------------------------------------------------------------
ALTER TABLE public.line_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.line_trip_stops ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.line_trips, public.line_trip_stops FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.line_trips, public.line_trip_stops FROM authenticated;
GRANT SELECT ON public.line_trips, public.line_trip_stops TO authenticated;
GRANT ALL ON public.line_trips, public.line_trip_stops TO service_role;

DROP POLICY IF EXISTS line_trips_read_scope ON public.line_trips;
CREATE POLICY line_trips_read_scope ON public.line_trips FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_trips.line_id AND l.company_id = public.current_admin_company_id()))
  OR (public.is_supervisor() AND line_trips.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a))
  OR (NOT public.is_admin() AND line_trips.is_active
      AND (line_trips.university_id IS NULL OR line_trips.university_id = public.current_student_university_id())
      AND EXISTS (SELECT 1 FROM public.lines l WHERE l.id = line_trips.line_id AND l.is_active))
  OR EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.student_id = auth.uid()
             AND (s.departure_trip_id = line_trips.id OR s.return_trip_id = line_trips.id))
);

DROP POLICY IF EXISTS line_trip_stops_read_scope ON public.line_trip_stops;
CREATE POLICY line_trip_stops_read_scope ON public.line_trip_stops FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.line_trips t WHERE t.id = line_trip_stops.trip_id));

-- ------------------------------------------------------------------------------
-- 7. Subscription validation: station + trips (departure required, return
--    required when the line has a return trip for the student).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_subscription_station_times()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line_id uuid;
  v_line_active boolean;
  v_trip record;
  v_has_returns boolean;
BEGIN
  -- Status/date changes (receipt review, expiry) and server-side time sync
  -- must not be re-validated against trips that may have changed since.
  IF TG_OP = 'UPDATE'
     AND NEW.station_id IS NOT DISTINCT FROM OLD.station_id
     AND NEW.line_id IS NOT DISTINCT FROM OLD.line_id
     AND NEW.departure_trip_id IS NOT DISTINCT FROM OLD.departure_trip_id
     AND NEW.return_trip_id IS NOT DISTINCT FROM OLD.return_trip_id
     AND (pg_trigger_depth() > 1 OR (
          NEW.departure_time IS NOT DISTINCT FROM OLD.departure_time
          AND NEW.return_time IS NOT DISTINCT FROM OLD.return_time)) THEN
    RETURN NEW;
  END IF;

  SELECT s.line_id, l.is_active INTO v_line_id, v_line_active
  FROM public.stations s JOIN public.lines l ON l.id = s.line_id
  WHERE s.id = NEW.station_id AND s.is_active = true;
  IF NOT FOUND OR NOT v_line_active OR v_line_id <> NEW.line_id THEN
    RAISE EXCEPTION 'المحطة المختارة غير متاحة على هذا الخط.';
  END IF;

  -- Departure trip: the one sent, else the one whose stop time matches (older apps).
  SELECT t.id, s.stop_time INTO v_trip
  FROM public.line_trips t JOIN public.line_trip_stops s ON s.trip_id = t.id AND s.station_id = NEW.station_id
  WHERE t.line_id = NEW.line_id AND t.direction = 'departure' AND public.trip_serves_student(t, NEW.student_id)
    AND (CASE WHEN NEW.departure_trip_id IS NOT NULL THEN t.id = NEW.departure_trip_id
              ELSE s.stop_time = NEW.departure_time END)
  ORDER BY t.university_id NULLS LAST, t.start_time LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'اختر رحلة ذهاب متاحة لجامعتك تمر بمحطتك.';
  END IF;
  NEW.departure_trip_id := v_trip.id;
  NEW.departure_time := v_trip.stop_time;

  SELECT EXISTS (
    SELECT 1 FROM public.line_trips t JOIN public.line_trip_stops s ON s.trip_id = t.id AND s.station_id = NEW.station_id
    WHERE t.line_id = NEW.line_id AND t.direction = 'return' AND public.trip_serves_student(t, NEW.student_id)
  ) INTO v_has_returns;

  IF NEW.return_trip_id IS NOT NULL OR NEW.return_time IS NOT NULL OR v_has_returns THEN
    SELECT t.id, s.stop_time INTO v_trip
    FROM public.line_trips t JOIN public.line_trip_stops s ON s.trip_id = t.id AND s.station_id = NEW.station_id
    WHERE t.line_id = NEW.line_id AND t.direction = 'return' AND public.trip_serves_student(t, NEW.student_id)
      AND (CASE WHEN NEW.return_trip_id IS NOT NULL THEN t.id = NEW.return_trip_id
                ELSE s.stop_time = NEW.return_time END)
    ORDER BY t.university_id NULLS LAST, t.start_time LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'اختر رحلة عودة متاحة لجامعتك تمر بمحطتك.';
    END IF;
    NEW.return_trip_id := v_trip.id;
    NEW.return_time := v_trip.stop_time;
  END IF;

  NEW.schedule_id := NULL;  -- university schedules are now trips
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. Older app versions: line list for the student (now derived from trips).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_student_line_options()
RETURNS TABLE (
  line_id uuid, uses_university_schedules boolean, schedule_id uuid,
  university_name text, departure_time time, return_time time
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT l.id, false, NULL::uuid, NULL::text, NULL::time, NULL::time
  FROM public.lines l
  JOIN public.companies c ON c.id = l.company_id AND c.is_active
  WHERE l.is_active AND auth.uid() IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.line_trips t
                WHERE t.line_id = l.id AND t.direction = 'departure'
                  AND public.trip_serves_student(t, auth.uid()))
$$;

-- ------------------------------------------------------------------------------
-- 9. Ride confirmation: the times of the trips that serve the student's station.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.toggle_student_daily_ride(
  p_ride_date date, p_is_riding boolean, p_departure_time time, p_return_time time, p_is_returning boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_student_id uuid := auth.uid();
  v_sub record;
  v_departure_times time[];
  v_return_times time[];
  v_local_now timestamp := now() AT TIME ZONE 'Africa/Cairo';
  v_expected_ride_date date;
BEGIN
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_local_now::time >= TIME '16:00' THEN v_expected_ride_date := v_local_now::date + 1;
  ELSE v_expected_ride_date := v_local_now::date; END IF;
  IF v_local_now::time >= TIME '06:00' AND v_local_now::time < TIME '16:00' THEN
    RAISE EXCEPTION 'التصويت مغلق. يفتح يومياً من الساعة ٤ مساءً حتى ٦ صباحاً.';
  END IF;
  IF p_ride_date <> v_expected_ride_date THEN RAISE EXCEPTION 'اختر تاريخ الرحلة المتاح للتصويت.'; END IF;

  SELECT sub.* INTO v_sub
  FROM public.subscriptions sub
  JOIN public.stations st ON st.id = sub.station_id
  JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = v_student_id AND sub.status = 'active'
    AND (sub.start_date IS NULL OR sub.start_date <= p_ride_date)
    AND (sub.end_date IS NULL OR sub.end_date >= p_ride_date)
    AND st.is_active = true AND l.is_active = true
  ORDER BY sub.created_at DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'لا يوجد اشتراك نشط لهذا التاريخ.'; END IF;

  SELECT array_agg(DISTINCT s.stop_time) FILTER (WHERE t.direction = 'departure'),
         array_agg(DISTINCT s.stop_time) FILTER (WHERE t.direction = 'return')
  INTO v_departure_times, v_return_times
  FROM public.line_trips t JOIN public.line_trip_stops s ON s.trip_id = t.id AND s.station_id = v_sub.station_id
  WHERE t.line_id = v_sub.line_id AND public.trip_serves_student(t, v_student_id);
  -- The subscribed trip times always remain valid.
  v_departure_times := COALESCE(v_departure_times, '{}') || v_sub.departure_time;
  v_return_times := COALESCE(v_return_times, '{}') || v_sub.return_time;

  IF p_is_riding THEN
    IF p_departure_time IS NULL OR NOT (p_departure_time = ANY(v_departure_times)) THEN
      RAISE EXCEPTION 'اختر موعد ذهاب متاحاً.';
    END IF;
    IF p_is_returning AND (p_return_time IS NULL OR NOT (p_return_time = ANY(v_return_times))) THEN
      RAISE EXCEPTION 'اختر موعد عودة متاحاً أو ألغِ رحلة العودة.';
    END IF;
  END IF;

  INSERT INTO public.daily_ride_status(student_id, ride_date, is_riding, departure_time, return_time, is_returning, toggled_at)
  VALUES (v_student_id, p_ride_date, p_is_riding, p_departure_time,
          CASE WHEN p_is_returning THEN p_return_time ELSE NULL END, p_is_returning, now())
  ON CONFLICT (student_id, ride_date) DO UPDATE SET is_riding = EXCLUDED.is_riding,
    departure_time = EXCLUDED.departure_time, return_time = EXCLUDED.return_time,
    is_returning = EXCLUDED.is_returning, toggled_at = now();

  RETURN jsonb_build_object('success', true, 'student_id', v_student_id, 'ride_date', p_ride_date,
    'is_riding', p_is_riding, 'departure_time', p_departure_time,
    'return_time', CASE WHEN p_is_returning THEN p_return_time ELSE NULL END,
    'is_returning', p_is_returning, 'toggled_at', now());
END;
$$;

-- ------------------------------------------------------------------------------
-- 10. Rider counts per station and departure trip.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_line_rider_counts_with_returns(p_line_id uuid, p_ride_date date)
RETURNS TABLE (
  line_id uuid, line_name text, station_id uuid, station_name text, order_index integer,
  departure_time time, return_time time, riding_count bigint, returning_count bigint,
  schedule_id uuid, university_name text
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;

  RETURN QUERY
  WITH valid_subs AS (
    SELECT s.* FROM public.subscriptions s
    WHERE s.line_id = p_line_id AND s.status = 'active'
      AND COALESCE(s.start_date, p_ride_date) <= p_ride_date AND COALESCE(s.end_date, p_ride_date) >= p_ride_date
  )
  SELECT l.id, l.name, st.id, st.name, st.order_index,
    ts.stop_time,
    MIN(sub.return_time),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true AND drs.is_returning = true),
    t.id,
    NULLIF(concat_ws(' · ', NULLIF(t.label, ''), u.name), '')
  FROM public.line_trips t
  JOIN public.line_trip_stops ts ON ts.trip_id = t.id
  JOIN public.stations st ON st.id = ts.station_id AND st.is_active
  JOIN public.lines l ON l.id = t.line_id
  LEFT JOIN public.universities u ON u.id = t.university_id
  LEFT JOIN valid_subs sub ON sub.station_id = st.id AND sub.departure_trip_id = t.id
  LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
  WHERE t.line_id = p_line_id AND t.direction = 'departure' AND l.is_active
    AND (t.is_active OR EXISTS (SELECT 1 FROM valid_subs v WHERE v.departure_trip_id = t.id))
  GROUP BY l.id, l.name, st.id, st.name, st.order_index, ts.stop_time, t.id, t.label, t.start_time, u.name
  ORDER BY t.start_time, st.order_index;
END;
$$;

-- ------------------------------------------------------------------------------
-- 11. Supervisor dashboard: per-line trips instead of university schedules.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.line_trips_summary(p_line_id uuid, p_today date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', t.id, 'direction', t.direction, 'label', t.label,
      'university', COALESCE(u.name, 'كل الجامعات'),
      'departure_time', t.start_time, 'return_time', NULL, 'arrival_time', t.arrival_time,
      'registered_students', (SELECT count(*) FROM public.subscriptions s
        WHERE s.status = 'active' AND (s.departure_trip_id = t.id OR s.return_trip_id = t.id)
          AND COALESCE(s.start_date, p_today) <= p_today AND COALESCE(s.end_date, p_today) >= p_today))
    ORDER BY t.direction, t.start_time), '[]'::jsonb)
  FROM public.line_trips t LEFT JOIN public.universities u ON u.id = t.university_id
  WHERE t.line_id = p_line_id AND t.is_active
$$;
REVOKE ALL ON FUNCTION public.line_trips_summary(uuid, date) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_supervisor_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE

  v_me uuid := auth.uid();

  v_today date := public.cairo_today();

  v_data jsonb;

BEGIN

  IF NOT EXISTS (SELECT 1 FROM public.supervisors WHERE id = v_me) THEN

    RAISE EXCEPTION 'هذا الحساب ليس حساب مشرف.';

  END IF;



  WITH assigned AS (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a),

  active_subs AS (

    SELECT sub.* FROM public.subscriptions sub

    WHERE sub.status = 'active' AND sub.line_id IN (SELECT line_id FROM assigned)

      AND (sub.start_date IS NULL OR sub.start_date <= v_today)

      AND (sub.end_date IS NULL OR sub.end_date >= v_today)

  )

  SELECT jsonb_build_object(

    'today', v_today,

    'profile', (

      SELECT jsonb_build_object(

        'id', s.id, 'full_name', s.full_name, 'phone', s.phone, 'is_active', s.is_active,

        'created_at', s.created_at, 'company_id', s.company_id, 'company_name', c.name,

        'company_active', c.is_active,

        'assignment', CASE WHEN EXISTS (SELECT 1 FROM assigned) THEN 'direct' ELSE 'none' END)

      FROM public.supervisors s LEFT JOIN public.companies c ON c.id = s.company_id

      WHERE s.id = v_me),

    'totals', jsonb_build_object(

      'lines', (SELECT count(*) FROM assigned),

      'registered_students', (SELECT count(DISTINCT student_id) FROM active_subs),

      'stations', (SELECT count(*) FROM public.stations st WHERE st.is_active AND st.line_id IN (SELECT line_id FROM assigned)),

      'confirmed_today', (SELECT count(*) FROM public.daily_ride_status drs

                          WHERE drs.ride_date = v_today AND drs.is_riding

                            AND drs.student_id IN (SELECT student_id FROM active_subs)),

      'checked_in_today', (SELECT count(*) FROM public.supervisor_scan_events e

                           WHERE e.supervisor_id = v_me AND e.ride_date = v_today AND e.result = 'checked_in')),

    -- Students per trip time on the supervisor's lines, from the students' ride

    -- confirmations: today and, once tomorrow's vote has opened, the next ride day.

    'trip_times', COALESCE((

      SELECT jsonb_agg(jsonb_build_object(

          'ride_date', t.ride_date, 'line_id', t.line_id, 'line_name', t.line_name,

          'direction', t.direction, 'time', t.trip_time, 'students', t.students)

        ORDER BY t.ride_date, t.direction, t.trip_time, t.line_name)

      FROM (

        SELECT drs.ride_date, l.id AS line_id, l.name AS line_name, x.direction, x.trip_time,

               count(DISTINCT drs.student_id) AS students

        FROM public.daily_ride_status drs

        JOIN public.subscriptions sub ON sub.student_id = drs.student_id AND sub.status = 'active'

          AND sub.line_id IN (SELECT line_id FROM assigned)

          AND COALESCE(sub.start_date, drs.ride_date) <= drs.ride_date

          AND COALESCE(sub.end_date, drs.ride_date) >= drs.ride_date

        JOIN public.lines l ON l.id = sub.line_id

        CROSS JOIN LATERAL (VALUES

          ('departure', COALESCE(drs.departure_time, sub.departure_time)),

          ('return', CASE WHEN drs.is_returning THEN COALESCE(drs.return_time, sub.return_time) END)

        ) AS x(direction, trip_time)

        WHERE drs.is_riding AND x.trip_time IS NOT NULL

          AND drs.ride_date IN (v_today, public.next_votable_ride_date())

        GROUP BY drs.ride_date, l.id, l.name, x.direction, x.trip_time

      ) t), '[]'::jsonb),

    'lines', COALESCE((

      SELECT jsonb_agg(jsonb_build_object(

        'id', l.id, 'name', l.name, 'is_active', l.is_active,

        'directly_assigned', true,

        'price_termly', l.price_termly, 'price_yearly', l.price_yearly, 'price_daily', l.price_daily,

        'registered_students', (SELECT count(*) FROM active_subs a WHERE a.line_id = l.id),

        'confirmed_today', (SELECT count(*) FROM active_subs a JOIN public.daily_ride_status drs

                              ON drs.student_id = a.student_id AND drs.ride_date = v_today AND drs.is_riding

                            WHERE a.line_id = l.id),

        -- Departure trips (university, start time, riders) for the Home screen;
        -- 'trips' carries both directions.
        'schedules', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
                      FROM jsonb_array_elements(public.line_trips_summary(l.id, v_today)) x
                      WHERE x->>'direction' = 'departure'),
        'trips', public.line_trips_summary(l.id, v_today),
        'origin_name', l.origin_name,
        'destination', (SELECT name FROM public.universities WHERE id = l.destination_university_id),
        'stations', COALESCE((

          SELECT jsonb_agg(jsonb_build_object(

            'id', st.id, 'name', st.name, 'order_index', st.order_index,

            'departure_times', st.departure_times, 'return_times', st.return_times,

            'registered_students', (SELECT count(*) FROM active_subs a WHERE a.station_id = st.id),

            'confirmed_today', (SELECT count(*) FROM active_subs a JOIN public.daily_ride_status drs

                                  ON drs.student_id = a.student_id AND drs.ride_date = v_today AND drs.is_riding

                                WHERE a.station_id = st.id),

            'checked_in_today', (SELECT count(*) FROM public.supervisor_scan_events e

                                 WHERE e.station_id = st.id AND e.ride_date = v_today AND e.result = 'checked_in'))

            ORDER BY st.order_index)

          FROM public.stations st WHERE st.line_id = l.id AND st.is_active), '[]'::jsonb))

        ORDER BY l.name)

      FROM public.lines l WHERE l.id IN (SELECT line_id FROM assigned)), '[]'::jsonb)

  ) INTO v_data;



  RETURN v_data;

END;

$function$;

-- ------------------------------------------------------------------------------
-- 12. QR lookup reports the student's trip (label · university).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(p_qr_code uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_student_id uuid;
  v_today date := public.cairo_today();
  v_data jsonb;
BEGIN
  IF NOT (public.is_supervisor() OR public.is_admin()) THEN
    RAISE EXCEPTION 'Access denied. Only supervisors and admins can perform QR lookups.';
  END IF;

  SELECT s.id INTO v_student_id FROM public.students s WHERE s.qr_code_value = p_qr_code;
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Student not found with the provided QR code.';
  END IF;

  IF public.is_company_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = v_student_id AND l.company_id = public.current_admin_company_id()
  ) THEN
    RAISE EXCEPTION 'Student is outside your company.';
  END IF;

  IF public.is_supervisor() AND NOT public.is_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student_id AND sub.status = 'active'
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ) THEN
    RAISE EXCEPTION 'Student is outside your assigned lines.';
  END IF;

  SELECT jsonb_build_object(
    'id', s.id, 'full_name', s.full_name, 'phone', s.phone, 'university', s.university,
    'subscription', (
      SELECT jsonb_build_object(
        'id', sub.id, 'type', sub.type, 'status', sub.status,
        'start_date', sub.start_date, 'end_date', sub.end_date,
        'line_name', l.name, 'station_name', st.name,
        'university_schedule', NULLIF(concat_ws(' · ', NULLIF(dt.label, ''), u.name), ''),
        'departure_time', COALESCE(sub.departure_time, st.departure_time),
        'return_time', COALESCE(sub.return_time, st.return_time),
        'payment_date', CASE WHEN public.is_admin() THEN (
          SELECT r.reviewed_at FROM public.receipts r
          WHERE r.subscription_id = sub.id AND r.status = 'approved'
          ORDER BY r.reviewed_at DESC LIMIT 1) END
      )
      FROM public.subscriptions sub
      JOIN public.lines l ON l.id = sub.line_id
      JOIN public.stations st ON st.id = sub.station_id
      LEFT JOIN public.line_trips dt ON dt.id = sub.departure_trip_id
      LEFT JOIN public.universities u ON u.id = dt.university_id
      WHERE sub.student_id = s.id AND sub.status IN ('active', 'pending_review', 'pending_payment')
        AND (NOT public.is_company_admin() OR l.company_id = public.current_admin_company_id())
        AND (NOT public.is_supervisor() OR public.is_admin() OR sub.line_id IN (
          SELECT line_id FROM public.get_supervisor_assigned_line_ids()))
      -- The subscription valid today first, then the newest one.
      ORDER BY (sub.status = 'active' AND COALESCE(sub.start_date, v_today) <= v_today
                AND COALESCE(sub.end_date, v_today) >= v_today) DESC,
               sub.created_at DESC
      LIMIT 1
    ),
    'today_ride_status', (SELECT COALESCE(drs.is_riding, false)
      FROM public.daily_ride_status drs WHERE drs.student_id = s.id AND drs.ride_date = v_today)
  ) INTO v_data FROM public.students s WHERE s.id = v_student_id;

  RETURN v_data;
END;
$$;

COMMIT;
