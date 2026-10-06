-- 1. One phone number, one account: enforced by the database, whatever the client sends.
-- 2. One definition of "confirmed riders", used by the dashboard and the apps.

-- ---------------------------------------------------------------------------
-- 1. Phone numbers
-- ---------------------------------------------------------------------------
-- The same number can be typed many ways (+20…, spaces, Arabic numerals).
CREATE OR REPLACE FUNCTION public.normalize_egyptian_phone(p_phone text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE d text := regexp_replace(translate(COALESCE(p_phone, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'), '\D', '', 'g');
BEGIN
  IF d LIKE '20%' AND length(d) >= 12 THEN d := substr(d, 3); END IF;
  IF length(d) = 10 AND d LIKE '1%' THEN d := '0' || d; END IF;
  RETURN d;
END;
$$;

-- Stored in one canonical form, so the unique index on phone means what it says;
-- a number belongs to a student or to a supervisor, never both; and an account
-- can only carry the number it signs in with.
CREATE OR REPLACE FUNCTION public.enforce_account_phone() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_login text;
BEGIN
  NEW.phone := public.normalize_egyptian_phone(NEW.phone);
  IF NEW.phone !~ '^01[0125][0-9]{8}$' THEN
    RAISE EXCEPTION 'رقم الهاتف غير صحيح. اكتب رقماً مصرياً من 11 رقماً.' USING ERRCODE = '23514';
  END IF;
  IF (TG_TABLE_NAME = 'students' AND EXISTS (SELECT 1 FROM public.supervisors s WHERE s.phone = NEW.phone AND s.id <> NEW.id))
     OR (TG_TABLE_NAME = 'supervisors' AND EXISTS (SELECT 1 FROM public.students s WHERE s.phone = NEW.phone AND s.id <> NEW.id)) THEN
    RAISE EXCEPTION 'رقم الهاتف مسجل بالفعل لحساب آخر.' USING ERRCODE = '23505';
  END IF;
  -- A student signs in as <phone>@busak.app, so the row can only carry that number:
  -- nobody can register a number they do not sign in with. (Supervisors may also
  -- sign in by e-mail, so only a phone login is compared for them.)
  SELECT u.email INTO v_login FROM auth.users u WHERE u.id = NEW.id;
  IF v_login IS NOT NULL
     AND (TG_TABLE_NAME = 'students' OR v_login LIKE '%@busak.app')
     AND v_login IS DISTINCT FROM NEW.phone || '@busak.app' THEN
    RAISE EXCEPTION 'رقم الهاتف لا يطابق رقم تسجيل الدخول لهذا الحساب.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.enforce_account_phone() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_a_enforce_account_phone ON public.students;
CREATE TRIGGER trg_a_enforce_account_phone BEFORE INSERT OR UPDATE OF phone ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.enforce_account_phone();
DROP TRIGGER IF EXISTS trg_a_enforce_account_phone ON public.supervisors;
CREATE TRIGGER trg_a_enforce_account_phone BEFORE INSERT OR UPDATE OF phone ON public.supervisors
  FOR EACH ROW EXECUTE FUNCTION public.enforce_account_phone();

-- A friendlier name for the unique violation the apps translate.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.students WHERE phone !~ '^01[0125][0-9]{8}$') THEN
    ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_phone_format;
    ALTER TABLE public.students ADD CONSTRAINT students_phone_format CHECK (phone ~ '^01[0125][0-9]{8}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.supervisors WHERE phone !~ '^01[0125][0-9]{8}$') THEN
    ALTER TABLE public.supervisors DROP CONSTRAINT IF EXISTS supervisors_phone_format;
    ALTER TABLE public.supervisors ADD CONSTRAINT supervisors_phone_format CHECK (phone ~ '^01[0125][0-9]{8}$');
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Confirmed riders
-- ---------------------------------------------------------------------------
-- Who is riding on a day: a student who confirmed AND holds an active
-- subscription valid that day. A confirmation left behind by a subscription
-- that has since ended, been rejected or removed does not count. One row per student.
CREATE OR REPLACE FUNCTION public.confirmed_riders(p_date date)
RETURNS TABLE(student_id uuid, company_id uuid, line_id uuid, station_id uuid, subscription_id uuid, is_returning boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT DISTINCT ON (drs.student_id)
         drs.student_id, s.company_id, s.line_id, s.station_id, s.id, drs.is_returning
  FROM public.daily_ride_status drs
  JOIN public.subscriptions s ON s.student_id = drs.student_id AND s.status = 'active'
   AND COALESCE(s.start_date, p_date) <= p_date AND COALESCE(s.end_date, p_date) >= p_date
  WHERE drs.ride_date = p_date AND drs.is_riding
  ORDER BY drs.student_id, s.created_at DESC
$$;
REVOKE ALL ON FUNCTION public.confirmed_riders(date) FROM PUBLIC, anon, authenticated;

-- Riders of one company on one day. Today and later: the live rule above. Past
-- days: what was recorded at the time (a term that ended since does not erase history).
CREATE OR REPLACE FUNCTION public.company_riders_on(p_company_id uuid, p_date date) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN p_date >= public.cairo_today()
    THEN (SELECT count(*) FROM public.confirmed_riders(p_date) r WHERE r.company_id = p_company_id)
    ELSE (SELECT count(*) FROM public.daily_ride_status d
          WHERE d.company_id = p_company_id AND d.ride_date = p_date AND d.is_riding)
  END
$$;
REVOKE ALL ON FUNCTION public.company_riders_on(uuid, date) FROM PUBLIC, anon, authenticated;

-- The overview counts riders with the same rule, and also reports the next ride day.
CREATE OR REPLACE FUNCTION public.company_overview_data(p_company_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
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
    -- Students confirm from 4 pm for the NEXT ride; that day's count is what moves in the evening.
    'next_ride_date', public.next_votable_ride_date(),
    'riders_next', public.company_riders_on(p_company_id, public.next_votable_ride_date()),
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
REVOKE ALL ON FUNCTION public.company_overview_data(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.platform_overview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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

