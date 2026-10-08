-- A line's name is where it runs from ("الزرقا"), never "الزرقا / الدلتا":
-- the same line takes students to several universities, and each student is
-- shown their own. A university typed into the name is therefore removed, when
-- the line is saved and once now for the names already stored.

-- The part of a typed name before a separator, when what follows the separator
-- names a university (by any distinctive word of any university's name).
CREATE OR REPLACE FUNCTION public.line_short_name(p_name text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_name text := btrim(COALESCE(p_name, ''));
  v_parts text[];
  v_tail text;
  v_head text;
BEGIN
  LOOP
    v_parts := regexp_match(v_name, '^(.*\S)\s*[/\\|←→–—-]\s*(\S.*)$');
    EXIT WHEN v_parts IS NULL;
    v_head := btrim(v_parts[1]);
    v_tail := btrim(v_parts[2]);
    EXIT WHEN v_head = '' OR NOT (
      v_tail ~ '(^|\s)(جامعة|جامعه|الجامعة|الجامعه|university)(\s|$)'
      OR EXISTS (
        SELECT 1 FROM public.universities u,
             regexp_split_to_table(regexp_replace(u.name, '[إأآ]', 'ا', 'g'), '\s+') w
        WHERE length(w) >= 4 AND w NOT IN ('جامعة', 'جامعه', 'للعلوم', 'والتكنولوجيا', 'الجديدة', 'الجديده', 'الاهلية', 'الاهليه')
          AND position(regexp_replace(w, '[ةه]$', '') IN regexp_replace(v_tail, '[إأآ]', 'ا', 'g')) > 0));
    v_name := v_head;
  END LOOP;
  RETURN v_name;
END;
$$;
REVOKE ALL ON FUNCTION public.line_short_name(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.line_short_name(text) TO authenticated, service_role;

UPDATE public.lines SET name = public.line_short_name(name)
WHERE public.line_short_name(name) <> name AND public.line_short_name(name) <> '';

CREATE OR REPLACE FUNCTION public.save_line(p_line jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_line_id uuid := NULLIF(p_line->>'id', '')::uuid;
  v_company uuid := NULLIF(p_line->>'company_id', '')::uuid;
  v_existing public.lines%ROWTYPE;
  v_name text := btrim(COALESCE(p_line->>'name', ''));
  v_origin text := btrim(COALESCE(p_line->>'origin_name', ''));
  v_dest uuid := NULLIF(p_line->>'destination_university_id', '')::uuid;
  -- Universities served by the line (shared route, stored once).
  v_unis uuid[] := ARRAY(SELECT DISTINCT x::uuid FROM jsonb_array_elements_text(COALESCE(p_line->'university_ids', '[]'::jsonb)) x
                         WHERE NULLIF(x, '') IS NOT NULL);
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
  -- A short name is enough to identify a line: by default, its first station.
  -- Where a student starts is the station they choose, and where they go is
  -- their own university, so neither is asked for here.
  -- The name is the area only: a university typed after it is dropped, since
  -- each student is shown their own.
  v_name := public.line_short_name(v_name);
  IF v_name = '' THEN v_name := btrim(COALESCE(v_stations->0->>'name', '')); END IF;
  IF v_name = '' THEN RAISE EXCEPTION 'اكتب اسم الخط.' USING ERRCODE = '23514'; END IF;
  IF v_name ~ '[←→]' OR length(v_name) > 40 THEN
    RAISE EXCEPTION 'اسم الخط يجب أن يكون قصيراً (مثل اسم المنطقة) وبدون أسماء الجامعات أو أسهم.' USING ERRCODE = '23514';
  END IF;
  IF v_origin = '' THEN v_origin := v_name; END IF;
  IF cardinality(v_unis) = 0 AND v_dest IS NOT NULL THEN v_unis := ARRAY[v_dest]; END IF;
  IF cardinality(v_unis) = 0 THEN
    RAISE EXCEPTION 'اختر جامعة واحدة على الأقل يخدمها الخط.' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_unis) u WHERE NOT EXISTS (SELECT 1 FROM public.universities x WHERE x.id = u)) THEN
    RAISE EXCEPTION 'إحدى الجامعات المختارة غير موجودة.' USING ERRCODE = '23514';
  END IF;
  -- The route's end label: the chosen destination when it is one of the
  -- line's universities, otherwise the first selected university.
  IF v_dest IS NULL OR NOT (v_dest = ANY (v_unis)) THEN v_dest := v_unis[1]; END IF;
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
       AND NOT ((v_trip->>'university_id')::uuid = ANY (v_unis)) THEN
      RAISE EXCEPTION 'جامعة إحدى الرحلات ليست من جامعات الخط المختارة.' USING ERRCODE = '23514';
    END IF;
    v_key := (v_trip->>'direction') || '|' || (v_trip->>'start_time')::time || '|' || COALESCE(v_trip->>'university_id', '');
    IF v_key = ANY (v_seen) THEN
      RAISE EXCEPTION 'رحلتان بنفس الاتجاه والموعد والجامعة. عدّل إحداهما.' USING ERRCODE = '23514';
    END IF;
    v_seen := v_seen || v_key;
    -- A return trip is only a time the bus leaves the university: it has no stops.
    IF v_trip->>'direction' = 'return' THEN
      CONTINUE;
    END IF;
    IF jsonb_array_length(COALESCE(v_trip->'stops', '[]'::jsonb)) = 0 THEN
      RAISE EXCEPTION 'رحلة % لا تمر بأي محطة. حدد موعد المرور على المحطات.', (v_trip->>'start_time')::time
        USING ERRCODE = '23514';
    END IF;
    -- Stop times follow the route and are never before the trip's start time.
    v_prev := (v_trip->>'start_time')::time;
    FOR v_stop IN
      SELECT s FROM jsonb_array_elements(v_trip->'stops') s
      ORDER BY (s->>'station_index')::int
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

  -- Every university of the line needs a departure trip that serves it,
  -- otherwise its students would never see the line.
  FOR v_idx IN 1 .. cardinality(v_unis) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_trips) t
      WHERE t->>'direction' = 'departure' AND COALESCE((t->>'is_active')::boolean, true)
        AND (NULLIF(t->>'university_id', '') IS NULL OR (t->>'university_id')::uuid = v_unis[v_idx])
    ) THEN
      RAISE EXCEPTION 'جامعة "%" ليس لها أي رحلة ذهاب. اجعل الرحلة لـ«كل جامعات الخط» أو أضف رحلة لهذه الجامعة.',
        (SELECT name FROM public.universities WHERE id = v_unis[v_idx]) USING ERRCODE = '23514';
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

  -- ---- universities served by the line --------------------------------------
  DELETE FROM public.line_universities WHERE line_id = v_line_id AND NOT (university_id = ANY (v_unis));
  INSERT INTO public.line_universities (line_id, university_id)
  SELECT v_line_id, u FROM unnest(v_unis) u ON CONFLICT DO NOTHING;

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
        start_time = (v_trip->>'start_time')::time,
        arrival_time = CASE WHEN v_trip->>'direction' = 'departure' THEN NULLIF(v_trip->>'arrival_time', '')::time END,
        university_id = NULLIF(v_trip->>'university_id', '')::uuid,
        is_active = COALESCE((v_trip->>'is_active')::boolean, true), updated_at = now()
      WHERE id = v_tid;
      DELETE FROM public.line_trip_stops WHERE trip_id = v_tid;
    ELSE
      INSERT INTO public.line_trips (line_id, direction, label, start_time, arrival_time, university_id, is_active)
      VALUES (v_line_id, v_trip->>'direction', btrim(COALESCE(v_trip->>'label', '')),
              (v_trip->>'start_time')::time,
              CASE WHEN v_trip->>'direction' = 'departure' THEN NULLIF(v_trip->>'arrival_time', '')::time END,
              NULLIF(v_trip->>'university_id', '')::uuid, COALESCE((v_trip->>'is_active')::boolean, true))
      RETURNING id INTO v_tid;
    END IF;
    v_kept_trips := v_kept_trips || v_tid;
    INSERT INTO public.line_trip_stops (trip_id, station_id, stop_time)
    SELECT v_tid, v_station_ids[(s->>'station_index')::int + 1], (s->>'time')::time
    FROM jsonb_array_elements(COALESCE(v_trip->'stops', '[]'::jsonb)) s
    WHERE v_trip->>'direction' = 'departure' AND NULLIF(s->>'time', '') IS NOT NULL;
  END LOOP;
  PERFORM public.sync_return_trip_stops(v_line_id);
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
