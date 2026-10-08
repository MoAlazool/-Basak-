-- ==============================================================================
-- Migration: 20261020000001_vote_window_settings.sql
-- Run AFTER 20261020000000. Safe to re-run.
--
-- The daily ride vote no longer runs at fixed hours (4 PM -> 6 AM). The Super
-- Admin sets when it opens and closes, and how often the app reminds students
-- who have not voted yet, for the platform; a company may set its own (NULL on
-- the company = follow the platform). The defaults keep 16:00 -> 06:00 with
-- reminders off, so nothing changes until an admin edits them.
--
-- The vote for a ride day opens at opens_at on the day before and closes at the
-- first closes_at after that: on the ride day when closes_at <= opens_at
-- (16:00 -> 06:00), otherwise the same evening (12:00 -> 22:00).
-- ==============================================================================
BEGIN;

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS vote_opens_at time NOT NULL DEFAULT '16:00',
  ADD COLUMN IF NOT EXISTS vote_closes_at time NOT NULL DEFAULT '06:00',
  ADD COLUMN IF NOT EXISTS vote_reminder_minutes integer NOT NULL DEFAULT 0;
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS vote_opens_at time,
  ADD COLUMN IF NOT EXISTS vote_closes_at time,
  ADD COLUMN IF NOT EXISTS vote_reminder_minutes integer;

-- Reminders: 0 = off, otherwise every 15 minutes to 24 hours.
ALTER TABLE public.app_settings DROP CONSTRAINT IF EXISTS app_settings_vote_check;
ALTER TABLE public.app_settings ADD CONSTRAINT app_settings_vote_check CHECK (
  vote_opens_at <> vote_closes_at
  AND (vote_reminder_minutes = 0 OR vote_reminder_minutes BETWEEN 15 AND 1440));
-- A company overrides all three or none.
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_vote_check;
ALTER TABLE public.companies ADD CONSTRAINT companies_vote_check CHECK (
  (vote_opens_at IS NULL AND vote_closes_at IS NULL AND vote_reminder_minutes IS NULL)
  OR (vote_opens_at IS NOT NULL AND vote_closes_at IS NOT NULL AND vote_reminder_minutes IS NOT NULL
      AND vote_opens_at <> vote_closes_at
      AND (vote_reminder_minutes = 0 OR vote_reminder_minutes BETWEEN 15 AND 1440)));

-- ------------------------------------------------------------------------------
-- 1. The settings in force and the window they give a ride day.
-- ------------------------------------------------------------------------------
-- A company's settings, else the platform's (NULL company = the platform's).
CREATE OR REPLACE FUNCTION public.vote_settings(p_company_id uuid DEFAULT NULL)
RETURNS TABLE (opens_at time, closes_at time, reminder_minutes integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(c.vote_opens_at, s.vote_opens_at),
         COALESCE(c.vote_closes_at, s.vote_closes_at),
         COALESCE(c.vote_reminder_minutes, s.vote_reminder_minutes)
  FROM public.app_settings s
  LEFT JOIN public.companies c ON c.id = p_company_id
  WHERE s.id
$$;

-- When the vote for p_ride_date opens and closes, in Cairo wall-clock time.
CREATE OR REPLACE FUNCTION public.vote_window(p_ride_date date, p_company_id uuid DEFAULT NULL)
RETURNS TABLE (opens timestamp, closes timestamp)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (p_ride_date - 1) + v.opens_at,
         CASE WHEN v.closes_at <= v.opens_at THEN p_ride_date + v.closes_at
              ELSE (p_ride_date - 1) + v.closes_at END
  FROM public.vote_settings(p_company_id) v
$$;

-- "٤ مساءً", "٦:٣٠ صباحاً"
CREATE OR REPLACE FUNCTION public.ar_clock(p_time time) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT translate(((EXTRACT(hour FROM p_time)::int + 11) % 12 + 1)::text
           || CASE WHEN EXTRACT(minute FROM p_time)::int > 0
                   THEN ':' || lpad(EXTRACT(minute FROM p_time)::int::text, 2, '0') ELSE '' END,
           '0123456789', '٠١٢٣٤٥٦٧٨٩')
      || CASE WHEN p_time < TIME '12:00' THEN ' صباحاً'
              WHEN p_time < TIME '13:00' THEN ' ظهراً'
              ELSE ' مساءً' END
$$;

-- The window in words, for messages.
CREATE OR REPLACE FUNCTION public.vote_window_text(p_company_id uuid DEFAULT NULL) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN v.closes_at <= v.opens_at
    THEN 'يفتح التصويت ' || public.ar_clock(v.opens_at) || ' في اليوم السابق للرحلة ويُقفل '
         || public.ar_clock(v.closes_at) || ' يوم الرحلة.'
    ELSE 'يفتح التصويت ' || public.ar_clock(v.opens_at) || ' ويُقفل '
         || public.ar_clock(v.closes_at) || ' في اليوم السابق للرحلة.' END
  FROM public.vote_settings(p_company_id) v
$$;

-- The first ride day whose vote has not closed yet (a daily ticket bought now
-- is for that day). Callers without a company get the platform's window.
DROP FUNCTION IF EXISTS public.next_votable_ride_date();
CREATE OR REPLACE FUNCTION public.next_votable_ride_date(p_company_id uuid DEFAULT NULL) RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT d.day
  FROM (VALUES (public.cairo_today()), (public.cairo_today() + 1), (public.cairo_today() + 2)) AS d(day),
       LATERAL public.vote_window(d.day, p_company_id) w
  WHERE w.closes > (now() AT TIME ZONE 'Africa/Cairo')
  ORDER BY d.day
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION public.vote_settings(uuid), public.vote_window(date, uuid), public.ar_clock(time),
  public.vote_window_text(uuid), public.next_votable_ride_date(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.vote_settings(uuid), public.vote_window(date, uuid), public.ar_clock(time),
  public.vote_window_text(uuid), public.next_votable_ride_date(uuid) TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 2. Read and change them (dashboard; the apps read them too).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_vote_settings(p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'company_id', p_company_id,
    'opens_at', left(v.opens_at::text, 5),
    'closes_at', left(v.closes_at::text, 5),
    'reminder_minutes', v.reminder_minutes,
    'window_text', public.vote_window_text(p_company_id),
    -- The company has its own settings (otherwise it follows the platform).
    'custom', EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company_id AND c.vote_opens_at IS NOT NULL),
    'platform', (SELECT jsonb_build_object(
        'opens_at', left(s.vote_opens_at::text, 5),
        'closes_at', left(s.vote_closes_at::text, 5),
        'reminder_minutes', s.vote_reminder_minutes)
      FROM public.app_settings s WHERE s.id),
    'can_edit_platform', public.is_super_admin())
  FROM public.vote_settings(p_company_id) v
$$;
REVOKE ALL ON FUNCTION public.get_vote_settings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vote_settings(uuid) TO authenticated;

-- NULL company = the platform (Super Admin). For a company, three NULLs return
-- it to the platform's settings.
CREATE OR REPLACE FUNCTION public.set_vote_settings(
  p_company_id uuid, p_opens_at time, p_closes_at time, p_reminder_minutes integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_opens time := left(p_opens_at::text, 5)::time;   -- whole minutes
  v_closes time := left(p_closes_at::text, 5)::time;
BEGIN
  IF p_company_id IS NULL THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'الإعداد العام متاح لمدير النظام فقط.' USING ERRCODE = '42501';
    END IF;
  ELSIF public.can_manage_company(p_company_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
  END IF;

  IF p_company_id IS NOT NULL AND p_opens_at IS NULL AND p_closes_at IS NULL AND p_reminder_minutes IS NULL THEN
    UPDATE public.companies SET vote_opens_at = NULL, vote_closes_at = NULL, vote_reminder_minutes = NULL
    WHERE id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.'; END IF;
    RETURN public.get_vote_settings(p_company_id);
  END IF;

  IF v_opens IS NULL OR v_closes IS NULL OR p_reminder_minutes IS NULL THEN
    RAISE EXCEPTION 'أدخل موعد فتح التصويت وموعد قفله وتكرار التذكير.';
  END IF;
  IF v_opens = v_closes THEN
    RAISE EXCEPTION 'يجب أن يختلف موعد قفل التصويت عن موعد فتحه.';
  END IF;
  IF p_reminder_minutes <> 0 AND p_reminder_minutes NOT BETWEEN 15 AND 1440 THEN
    RAISE EXCEPTION 'تكرار التذكير من ١٥ دقيقة إلى ٢٤ ساعة، أو بدون تذكير.';
  END IF;

  IF p_company_id IS NULL THEN
    UPDATE public.app_settings SET vote_opens_at = v_opens, vote_closes_at = v_closes,
      vote_reminder_minutes = p_reminder_minutes, updated_at = now(), updated_by = auth.uid()
    WHERE id;
  ELSE
    UPDATE public.companies SET vote_opens_at = v_opens, vote_closes_at = v_closes,
      vote_reminder_minutes = p_reminder_minutes
    WHERE id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.'; END IF;
  END IF;
  RETURN public.get_vote_settings(p_company_id);
END;
$$;
REVOKE ALL ON FUNCTION public.set_vote_settings(uuid, time, time, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_vote_settings(uuid, time, time, integer) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. Voting follows the window of the subscription's company.
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
BEGIN
  IF v_student_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

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

  IF NOT EXISTS (SELECT 1 FROM public.vote_window(p_ride_date, v_sub.company_id) w
                 WHERE v_local_now >= w.opens AND v_local_now < w.closes) THEN
    -- Open, but for another day: the app is showing a stale date.
    IF EXISTS (SELECT 1 FROM (VALUES (v_local_now::date), (v_local_now::date + 1)) AS d(day),
                 LATERAL public.vote_window(d.day, v_sub.company_id) w
               WHERE v_local_now >= w.opens AND v_local_now < w.closes) THEN
      RAISE EXCEPTION 'اختر تاريخ الرحلة المتاح للتصويت.';
    END IF;
    RAISE EXCEPTION 'التصويت مغلق الآن. %', public.vote_window_text(v_sub.company_id);
  END IF;

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
-- 4. A daily ticket is for the next ride its company's vote is still open for.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_subscription_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_line record;
  v_ride_date date;
  v_period record;
  v_privileged boolean := auth.uid() IS NULL OR public.is_admin();
BEGIN
  PERFORM public.expire_finished_subscriptions(NEW.student_id);

  SELECT l.price_termly, l.price_yearly, l.price_daily, l.is_active, l.company_id, c.is_active AS company_active
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
    NEW.price := CASE NEW.type
      WHEN 'termly' THEN v_line.price_termly
      WHEN 'yearly' THEN v_line.price_yearly
      ELSE v_line.price_daily
    END;
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
    IF NEW.type = 'yearly' AND NOT public.annual_subscription_enabled(v_line.company_id) THEN
      RAISE EXCEPTION 'الاشتراك السنوي غير متاح حالياً.' USING ERRCODE = '23514';
    END IF;

    IF NEW.period_code IS NULL OR NEW.academic_year IS NULL THEN
      -- Older clients: the current period, otherwise the next one.
      SELECT * INTO v_period FROM public.get_purchasable_periods(NEW.line_id) p
      WHERE p.subscription_type = NEW.type ORDER BY p.start_date LIMIT 1;
    ELSE
      SELECT * INTO v_period FROM public.get_purchasable_periods(NEW.line_id) p
      WHERE p.subscription_type = NEW.type AND p.period_code = NEW.period_code
        AND p.academic_year = NEW.academic_year;
    END IF;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'فترة الاشتراك المختارة غير متاحة للدفع الآن.' USING ERRCODE = '23514';
    END IF;

    NEW.period_code := v_period.period_code;
    NEW.academic_year := v_period.academic_year;
    NEW.start_date := v_period.start_date;
    NEW.end_date := v_period.end_date;
    IF NOT v_privileged THEN
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
$$;

CREATE OR REPLACE FUNCTION public.guard_subscription_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_period record;
BEGIN
  IF pg_trigger_depth() <= 1 AND auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'تعديل الاشتراك متاح للإدارة فقط. اعتماد الدفع يتم من خلال الإيصال.';
  END IF;

  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
    NEW.paid_at := COALESCE(NEW.paid_at, now());
  ELSIF NEW.status IN ('pending_payment', 'pending_review') THEN
    NEW.paid_at := NULL;  -- e.g. an admin reverting an activation
  END IF;

  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' AND NEW.end_date IS NULL THEN
    IF NEW.type IN ('termly', 'yearly') THEN
      SELECT * INTO v_period
      FROM public.company_period_for_date(NEW.company_id, NEW.type, COALESCE(NEW.start_date, public.cairo_today()));
      NEW.period_code := v_period.period_code;
      NEW.academic_year := v_period.academic_year;
      NEW.start_date := v_period.start_date;
      NEW.end_date := v_period.end_date;
    ELSE
      NEW.start_date := COALESCE(NEW.start_date, public.next_votable_ride_date(NEW.company_id));
      NEW.end_date := NEW.start_date;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------------------------
-- 5. Overviews: the company's next ride and when its vote closes.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_overview_data(p_company_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH day AS (SELECT public.cairo_today() AS today),
  since AS (SELECT public.report_baseline('financial', p_company_id) AS at),
  paid AS (
    -- One payment per subscription: the approved receipt amount, else the price.
    SELECT s.id, s.line_id, s.status, s.start_date, s.end_date, s.paid_at,
           COALESCE((SELECT r.amount FROM public.receipts r
                     WHERE r.subscription_id = s.id AND r.status = 'approved'
                     ORDER BY r.reviewed_at DESC NULLS LAST LIMIT 1), s.price) AS amount
    FROM public.subscriptions s
    WHERE s.company_id = p_company_id AND s.paid_at IS NOT NULL
  ),
  running AS (
    -- Valid today, so a term paid in advance is not counted before it starts.
    SELECT p.* FROM paid p, day
    WHERE p.status = 'active' AND (p.start_date IS NULL OR p.start_date <= day.today)
      AND (p.end_date IS NULL OR p.end_date >= day.today)
  ),
  week AS (
    SELECT d::date AS ride_date, public.company_riders_on(p_company_id, d::date) AS riders
    FROM day, generate_series(day.today - 6, day.today, INTERVAL '1 day') d
  )
  SELECT jsonb_build_object(
    'company', (SELECT jsonb_build_object('id', c.id, 'name', c.name, 'status', c.status, 'created_at', c.created_at)
                FROM public.companies c WHERE c.id = p_company_id),
    'baseline', (SELECT at FROM since),
    'members', (SELECT count(*) FROM public.company_students m WHERE m.company_id = p_company_id AND m.status = 'active'),
    'active_subscriptions', (SELECT count(*) FROM running),
    'pending_receipts', (SELECT count(*) FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'pending'),
    'revenue', COALESCE((SELECT sum(p.amount) FROM paid p, since WHERE since.at IS NULL OR p.paid_at > since.at), 0)
             + COALESCE((SELECT sum(a.amount) FROM public.deleted_student_revenue a, since
                         WHERE a.company_id = p_company_id AND (since.at IS NULL OR a.archived_at > since.at)), 0),
    'riders_today', (SELECT riders FROM week, day WHERE week.ride_date = day.today),
    -- Students confirm for the NEXT ride once its vote opens; that day's count is what moves.
    'next_ride_date', public.next_votable_ride_date(p_company_id),
    'riders_next', public.company_riders_on(p_company_id, public.next_votable_ride_date(p_company_id)),
    'vote_closes_at', (SELECT left(v.closes_at::text, 5) FROM public.vote_settings(p_company_id) v),
    'riders_week', (SELECT jsonb_agg(jsonb_build_object('date', ride_date, 'riders', riders) ORDER BY ride_date) FROM week),
    'lines', (SELECT count(*) FROM public.lines l WHERE l.company_id = p_company_id),
    'active_lines', (SELECT count(*) FROM public.lines l WHERE l.company_id = p_company_id AND l.is_active),
    'supervisors', (SELECT count(*) FROM public.supervisors s WHERE s.company_id = p_company_id AND s.is_active),
    'admins', (SELECT count(*) FROM public.admins a WHERE a.company_id = p_company_id),
    'top_lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'is_active', l.is_active, 'subscribers', n)
                       ORDER BY n DESC, l.name)
      FROM (SELECT l.id, l.name, l.is_active,
                   (SELECT count(*) FROM running r WHERE r.line_id = l.id) AS n
            FROM public.lines l WHERE l.company_id = p_company_id) l), '[]'::jsonb)
  )
$$;

CREATE OR REPLACE FUNCTION public.platform_overview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rows jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(jsonb_agg(public.company_overview_data(c.id) ORDER BY c.name), '[]'::jsonb)
  INTO v_rows FROM public.companies c;

  RETURN jsonb_build_object(
    'companies', (SELECT jsonb_build_object(
        'total', count(*),
        'active', count(*) FILTER (WHERE status = 'active'),
        'suspended', count(*) FILTER (WHERE status = 'suspended'),
        'archived', count(*) FILTER (WHERE status = 'archived')) FROM public.companies),
    -- A person riding with two companies is one student.
    'students', (SELECT count(*) FROM public.students),
    'members', (SELECT COALESCE(sum((r->>'members')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'active_subscriptions', (SELECT COALESCE(sum((r->>'active_subscriptions')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'pending_receipts', (SELECT COALESCE(sum((r->>'pending_receipts')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'revenue', (SELECT COALESCE(sum((r->>'revenue')::numeric), 0) FROM jsonb_array_elements(v_rows) r),
    'riders_today', (SELECT COALESCE(sum((r->>'riders_today')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'next_ride_date', public.next_votable_ride_date(),
    'riders_next', (SELECT COALESCE(sum((r->>'riders_next')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'vote_closes_at', (SELECT left(v.closes_at::text, 5) FROM public.vote_settings(NULL) v),
    'riders_week', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('date', d, 'riders', n) ORDER BY d)
      FROM (SELECT w->>'date' AS d, sum((w->>'riders')::int) AS n
            FROM jsonb_array_elements(v_rows) r, jsonb_array_elements(r->'riders_week') w GROUP BY 1) x), '[]'::jsonb),
    'lines', (SELECT COALESCE(sum((r->>'lines')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'supervisors', (SELECT COALESCE(sum((r->>'supervisors')::int), 0) FROM jsonb_array_elements(v_rows) r),
    'top_lines', COALESCE((
      SELECT jsonb_agg(x.line ORDER BY (x.line->>'subscribers')::int DESC, x.line->>'name')
      FROM (SELECT l || jsonb_build_object('company', r->'company'->>'name') AS line
            FROM jsonb_array_elements(v_rows) r, jsonb_array_elements(r->'top_lines') l
            ORDER BY (l->>'subscribers')::int DESC LIMIT 10) x), '[]'::jsonb),
    'per_company', (SELECT COALESCE(jsonb_agg(r - 'top_lines' - 'riders_week'), '[]'::jsonb) FROM jsonb_array_elements(v_rows) r)
  );
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. Supervisor dashboard: tomorrow's confirmations exist only once its vote
--    opened, so today and tomorrow cover every window. The profile carries the
--    company's vote settings.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_supervisor_dashboard()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
        'assignment', CASE WHEN EXISTS (SELECT 1 FROM assigned) THEN 'direct' ELSE 'none' END,
        'vote', public.get_vote_settings(s.company_id))
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
          AND drs.ride_date IN (v_today, v_today + 1)
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
$$;

COMMIT;
