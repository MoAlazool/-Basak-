-- ==============================================================================
-- Migration: 20261121000001_governorates.sql
-- Run AFTER 20261120000001. Safe to re-run.
--
-- Governorates: a student picks theirs first, and sees only the companies that
-- serve it; a company may serve several.
--   * public.governorates: Egypt's 27, fixed, chosen from a list (never typed).
--   * public.company_governorates: which ones each company serves, set by the
--     platform admin or the company's own admins (set_company_governorates).
--   * get_subscription_catalog also answers each company's 'governorates'
--     (codes) and, at the top, the 'governorates' those companies serve
--     ({code, name}, in list order). A company that has set none is not tied
--     to any and the app shows it under every governorate. Otherwise as
--     20261109000001.
-- ==============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.governorates (
  code text PRIMARY KEY CHECK (code ~ '^[a-z_]{2,30}$'),
  name text NOT NULL UNIQUE,
  sort_order integer NOT NULL
);
-- Alphabetical as Arabic readers look for them (without the article).
INSERT INTO public.governorates (code, name, sort_order) VALUES
  ('alexandria', 'الإسكندرية', 1), ('ismailia', 'الإسماعيلية', 2), ('aswan', 'أسوان', 3), ('asyut', 'أسيوط', 4),
  ('luxor', 'الأقصر', 5), ('red_sea', 'البحر الأحمر', 6), ('beheira', 'البحيرة', 7), ('beni_suef', 'بني سويف', 8),
  ('port_said', 'بورسعيد', 9), ('south_sinai', 'جنوب سيناء', 10), ('giza', 'الجيزة', 11), ('dakahlia', 'الدقهلية', 12),
  ('damietta', 'دمياط', 13), ('sohag', 'سوهاج', 14), ('suez', 'السويس', 15), ('sharqia', 'الشرقية', 16),
  ('north_sinai', 'شمال سيناء', 17), ('gharbia', 'الغربية', 18), ('faiyum', 'الفيوم', 19), ('cairo', 'القاهرة', 20),
  ('qalyubia', 'القليوبية', 21), ('qena', 'قنا', 22), ('kafr_el_sheikh', 'كفر الشيخ', 23), ('matrouh', 'مطروح', 24),
  ('monufia', 'المنوفية', 25), ('minya', 'المنيا', 26), ('new_valley', 'الوادي الجديد', 27)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order;
ALTER TABLE public.governorates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.governorates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.governorates TO anon, authenticated;
DROP POLICY IF EXISTS governorates_read ON public.governorates;
CREATE POLICY governorates_read ON public.governorates FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.company_governorates (
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  governorate_code text NOT NULL REFERENCES public.governorates(code),
  PRIMARY KEY (company_id, governorate_code)
);
ALTER TABLE public.company_governorates ENABLE ROW LEVEL SECURITY;
-- Where a company works is no secret; it is written through set_company_governorates only.
REVOKE ALL ON public.company_governorates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.company_governorates TO authenticated;
DROP POLICY IF EXISTS company_governorates_read ON public.company_governorates;
CREATE POLICY company_governorates_read ON public.company_governorates FOR SELECT TO authenticated USING (true);

-- Replaces the governorates a company serves; answers them as stored, in list order.
CREATE OR REPLACE FUNCTION public.set_company_governorates(p_company_id uuid, p_codes text[]) RETURNS text[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_codes text[] := ARRAY(SELECT DISTINCT btrim(c) FROM unnest(COALESCE(p_codes, '{}'::text[])) c WHERE btrim(COALESCE(c, '')) <> '');
  v_unknown text;
BEGIN
  IF p_company_id IS NULL OR public.can_manage_company(p_company_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'لا يمكنك تعديل بيانات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  SELECT c INTO v_unknown FROM unnest(v_codes) c WHERE NOT EXISTS (SELECT 1 FROM public.governorates g WHERE g.code = c) LIMIT 1;
  IF v_unknown IS NOT NULL THEN
    RAISE EXCEPTION 'محافظة غير معروفة: %', v_unknown USING ERRCODE = '23503';
  END IF;
  DELETE FROM public.company_governorates WHERE company_id = p_company_id AND NOT (governorate_code = ANY (v_codes));
  INSERT INTO public.company_governorates (company_id, governorate_code)
  SELECT p_company_id, c FROM unnest(v_codes) c
  ON CONFLICT DO NOTHING;
  RETURN ARRAY(SELECT cg.governorate_code FROM public.company_governorates cg JOIN public.governorates g ON g.code = cg.governorate_code
               WHERE cg.company_id = p_company_id ORDER BY g.sort_order);
END;
$$;
REVOKE ALL ON FUNCTION public.set_company_governorates(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_company_governorates(uuid, text[]) TO authenticated;

-- The catalog: each company's governorates.
CREATE OR REPLACE FUNCTION public.get_subscription_catalog()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH me AS (
    SELECT s.id, s.university_id, COALESCE(u.name, s.university) AS university
    FROM public.students s LEFT JOIN public.universities u ON u.id = s.university_id
    WHERE s.id = auth.uid()
  ),
  trips AS MATERIALIZED (
    SELECT t.id, t.line_id, t.direction, t.start_time, t.label
    FROM public.line_trips t, me WHERE public.trip_serves_student(t, me.id)
  ),
  per_line AS (
    SELECT t.line_id,
           min(t.start_time) FILTER (WHERE t.direction = 'departure') AS first_departure,
           max(t.start_time) FILTER (WHERE t.direction = 'return') AS last_return,
           -- The way back: when the bus leaves the student's university. No stations.
           jsonb_agg(jsonb_build_object('trip_id', t.id, 'time', t.start_time, 'label', t.label) ORDER BY t.start_time)
             FILTER (WHERE t.direction = 'return') AS returns
    FROM trips t GROUP BY t.line_id
  ),
  departures AS (
    SELECT t.line_id, x.station_id,
           jsonb_agg(jsonb_build_object('trip_id', t.id, 'time', x.stop_time, 'label', t.label) ORDER BY x.stop_time) AS list
    FROM trips t JOIN public.line_trip_stops x ON x.trip_id = t.id
    WHERE t.direction = 'departure'
    GROUP BY t.line_id, x.station_id
  ),
  line_stations AS (
    -- A station no departure trip stops at cannot be boarded from.
    SELECT st.line_id,
           jsonb_agg(jsonb_build_object('id', st.id, 'name', st.name, 'order_index', st.order_index, 'departures', d.list)
                     ORDER BY st.order_index, st.name) AS stations
    FROM public.stations st JOIN departures d ON d.line_id = st.line_id AND d.station_id = st.id
    WHERE st.is_active
    GROUP BY st.line_id
  ),
  my_lines AS (
    SELECT l.*, pl.first_departure, pl.last_return, pl.returns
    FROM public.lines l
    JOIN public.companies c ON c.id = l.company_id AND c.is_active AND c.status = 'active'
    JOIN per_line pl ON pl.line_id = l.id AND pl.first_departure IS NOT NULL
    WHERE l.is_active
  ),
  -- What each company sells now, asked once per company (it was once per line),
  -- with whether the student already holds something over those days.
  periods AS MATERIALIZED (
    SELECT c.company_id, p.*,
           EXISTS (SELECT 1 FROM public.subscriptions s
                   WHERE s.student_id = auth.uid() AND s.status IN ('pending_payment', 'pending_review', 'active')
                     AND (s.end_date IS NULL OR s.end_date >= public.cairo_today())
                     AND daterange(s.start_date, s.end_date, '[]') && daterange(p.start_date, p.end_date, '[]')) AS overlaps
    FROM (SELECT DISTINCT company_id FROM my_lines) c
    CROSS JOIN LATERAL public.company_sale_periods(c.company_id, NULL) p
  ),
  line_sale AS (
    -- The same rule as line_sale_options_for, for lines that are active.
    SELECT l.id AS line_id,
           jsonb_agg(jsonb_build_object('option', p.option, 'academic_year', p.academic_year, 'name', p.name,
             'label', p.label, 'type', p.subscription_type, 'start_date', p.start_date, 'end_date', p.end_date,
             'phase', p.phase, 'price', pr.price) ORDER BY p.start_date, p.subscription_type) AS options,
           min(pr.price) AS from_price
    FROM my_lines l
    JOIN periods p ON p.company_id = l.company_id
    LEFT JOIN public.line_period_prices pr ON pr.line_id = l.id AND pr.option = p.option
    WHERE p.reason IS NULL AND COALESCE(pr.is_enabled, false) AND COALESCE(pr.price, 0) > 0 AND NOT p.overlaps
    GROUP BY l.id
  ),
  line_json AS (
    SELECT l.company_id, l.name, jsonb_build_object(
      'id', l.id, 'name', l.name, 'origin_name', COALESCE(l.origin_name, l.name),
      'university', (SELECT university FROM me),
      'first_departure', l.first_departure,
      'last_return', l.last_return,
      'stations', COALESCE(ls.stations, '[]'::jsonb),
      'returns', COALESCE(l.returns, '[]'::jsonb),
      'options', COALESCE(sale.options, '[]'::jsonb),
      'from_price', sale.from_price,
      'daily', jsonb_build_object('enabled', public.daily_subscription_enabled(l.company_id), 'price', l.price_daily)
    ) AS j
    FROM my_lines l
    LEFT JOIN line_stations ls ON ls.line_id = l.id
    LEFT JOIN line_sale sale ON sale.line_id = l.id
  ),
  by_company AS (
    SELECT lj.company_id, jsonb_agg(lj.j ORDER BY lj.name) AS lines FROM line_json lj GROUP BY lj.company_id
  )
  SELECT jsonb_build_object(
    'university', (SELECT jsonb_build_object('id', university_id, 'name', university) FROM me),
    -- The governorates the companies below serve, for the student to pick from.
    'governorates', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name) ORDER BY g.sort_order)
      FROM public.governorates g
      WHERE EXISTS (SELECT 1 FROM public.company_governorates cg JOIN by_company b ON b.company_id = cg.company_id
                    WHERE cg.governorate_code = g.code)), '[]'::jsonb),
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path,
                                         'emblem_path', c.emblem_path, 'lines', b.lines,
                                         'governorates', COALESCE((
                                           SELECT jsonb_agg(cg.governorate_code ORDER BY g.sort_order)
                                           FROM public.company_governorates cg JOIN public.governorates g ON g.code = cg.governorate_code
                                           WHERE cg.company_id = c.id), '[]'::jsonb))
             ORDER BY c.name)
      FROM public.companies c JOIN by_company b ON b.company_id = c.id), '[]'::jsonb))
$$;

COMMIT;
