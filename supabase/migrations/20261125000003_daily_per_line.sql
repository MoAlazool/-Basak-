-- Daily per line: a line sells the daily cash ride only when it has a daily
-- price. The admin wizard now has a switch for daily like the term options;
-- switching it off saves the line's daily price as 0.
--
--  1. get_subscription_catalog: daily.enabled also needs price_daily > 0, so a
--     line without a daily price no longer offers a free daily ride.
--  2. enforce_subscription_insert: a student's own daily subscription is refused
--     when the company does not sell daily or the line has no daily price.
--     Admins (privileged) are unchanged.
--
-- Both functions are the live definitions with only these lines changed.
-- CREATE OR REPLACE keeps their grants.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_subscription_catalog()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- Daily is sold on a line while its company sells it and the line has a daily price.
      'daily', jsonb_build_object('enabled', public.daily_subscription_enabled(l.company_id) AND l.price_daily > 0, 'price', l.price_daily)
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
$function$;

CREATE OR REPLACE FUNCTION public.enforce_subscription_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_line record;
  v_ride_date date;
  v_opt record;
  v_code text;
  v_reason text;
  v_privileged boolean := auth.uid() IS NULL OR public.is_admin();
BEGIN
  PERFORM public.expire_finished_subscriptions(NEW.student_id);

  SELECT l.price_daily, l.is_active, l.company_id, c.is_active AS company_active
  INTO v_line
  FROM public.lines l JOIN public.companies c ON c.id = l.company_id
  WHERE l.id = NEW.line_id;

  IF NOT v_privileged THEN
    IF NEW.student_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'لا يمكن إنشاء اشتراك لحساب آخر.';
    END IF;
    IF NOT FOUND OR NOT v_line.is_active OR NOT v_line.company_active THEN
      RAISE EXCEPTION 'هذا الخط غير متاح للاشتراك حالياً.';
    END IF;
    IF NEW.type = 'daily' THEN
      -- The same rule as the catalog: the company sells daily and the line has a price.
      IF NOT public.daily_subscription_enabled(v_line.company_id) OR COALESCE(v_line.price_daily, 0) <= 0 THEN
        RAISE EXCEPTION 'الاشتراك اليومي غير متاح على هذا الخط.' USING ERRCODE = '23514';
      END IF;
      NEW.price := v_line.price_daily;
    END IF;
    NEW.created_at := now();
  END IF;

  IF NEW.type = 'daily' THEN
    NEW.period_code := NULL;
    NEW.academic_year := NULL;
    IF NOT v_privileged OR NEW.start_date IS NULL THEN
      -- Cash on the bus: active immediately, valid for the next votable ride.
      v_ride_date := public.next_votable_ride_date(v_line.company_id);
      NEW.status := 'active';
      NEW.start_date := v_ride_date;
      NEW.end_date := v_ride_date;
    END IF;
  ELSE
    -- Older clients say 'annual', or send a type with no period.
    v_code := CASE WHEN NEW.period_code = 'annual' OR (NEW.period_code IS NULL AND NEW.type = 'yearly')
                   THEN 'both' ELSE NEW.period_code END;

    -- The administration may register a student on a line that is switched off
    -- or has no price yet, and ahead of time; never for a period the company
    -- does not sell or that is out of season.
    SELECT * INTO v_opt FROM public.line_sale_options_for(NEW.line_id, NULL, NULL) o
    WHERE (CASE WHEN v_code IS NULL THEN o.subscription_type = 'termly' ELSE o.option = v_code END)
      AND (v_code IS NULL OR NEW.academic_year IS NULL OR o.academic_year = NEW.academic_year)
      AND (o.available OR (v_privileged AND o.reason IN
            ('company_inactive', 'line_inactive', 'line_not_offering', 'no_price', 'advance_off')))
    ORDER BY o.available DESC, o.start_date LIMIT 1;

    IF NOT FOUND THEN
      SELECT o.reason INTO v_reason FROM public.line_sale_options_for(NEW.line_id, NULL, NULL) o
      WHERE o.option = v_code ORDER BY o.start_date LIMIT 1;
      RAISE EXCEPTION '%', CASE
        WHEN v_code = 'both' AND v_reason = 'company_not_selling' THEN 'الاشتراك في الفصلين معاً غير متاح حالياً.'
        WHEN v_reason IN ('company_not_selling', 'line_not_offering', 'no_price') THEN 'هذه الفترة غير متاحة للاشتراك على هذا الخط.'
        WHEN v_reason = 'advance_off' THEN 'الاشتراك المسبق في الفترة القادمة غير متاح حالياً.'
        ELSE 'فترة الاشتراك المختارة غير متاحة للدفع الآن.' END USING ERRCODE = '23514';
    END IF;

    NEW.type := v_opt.subscription_type;
    NEW.period_code := v_opt.option;
    NEW.academic_year := v_opt.academic_year;
    NEW.start_date := v_opt.start_date;
    NEW.end_date := v_opt.end_date;
    IF NOT v_privileged THEN
      -- What was shown is what is charged.
      NEW.price := v_opt.price;
      NEW.status := 'pending_payment';
    END IF;
  END IF;

  NEW.paid_at := CASE WHEN NEW.status = 'active' THEN COALESCE(NEW.paid_at, now()) END;

  IF NEW.status IN ('pending_payment', 'pending_review', 'active') AND EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.student_id = NEW.student_id AND s.status IN ('pending_payment', 'pending_review', 'active')
      AND daterange(s.start_date, s.end_date, '[]') && daterange(NEW.start_date, NEW.end_date, '[]')
  ) THEN
    RAISE EXCEPTION 'لديك اشتراك يغطي هذه الفترة بالفعل.' USING ERRCODE = '23P01';
  END IF;

  RETURN NEW;
END;
$function$;

COMMIT;
