-- ==============================================================================
-- Migration: 20261103000001_data_access.sql
-- Run AFTER 20261102000001. Safe to re-run. Additive: nothing the released app
-- or the deployed dashboard calls changes its name, arguments or answer.
--
-- Where one screen needs one coherent set of rows, it now asks for it once.
-- Measured on a local database with 100,000 students (supabase/tests/local/perf):
--
-- 1. get_company_students_page: the dashboard's Students page. It was a nested
--    select through the API that read every member's subscriptions before
--    cutting a page, plus a separate count; with 33,000 members it ran into the
--    statement timeout. Now: the page of members first, then only their rows.
-- 2. get_pending_receipts_page: the receipts review list in one answer instead
--    of five requests in three stages.
-- 3. review_receipt: approve or reject and get back what the admin's screen
--    needs (the company's numbers), so nothing is re-read afterwards.
-- 4. get_lines_rider_counts: a supervisor's lines in one call, not one per line.
-- 5. admin_subscription_report: optional limit / offset for the rows (default as
--    before), and rows_total.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Students page
-- ------------------------------------------------------------------------------
-- A company's active members, newest first, a page at a time, each with their
-- subscriptions in this company (newest first). p_search: part of a name, a
-- phone (digits in any script) or a university. total only when asked for.
CREATE OR REPLACE FUNCTION public.get_company_students_page(
  p_company_id uuid, p_search text DEFAULT NULL, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0,
  p_with_total boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
  -- A phone typed with Arabic digits or spaces is still that phone.
  v_digits text := NULLIF(regexp_replace(translate(COALESCE(p_search, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '\D', '', 'g'), '');
  v_rows jsonb;
  v_count integer;
  v_total integer;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك عرض طلاب هذه الشركة.' USING ERRCODE = '42501';
  END IF;

  WITH page AS (
    SELECT st.id, st.phone, st.full_name, st.university, st.college, st.profile_image_url, st.created_at
    FROM public.company_students m
    JOIN public.students st ON st.id = m.student_id
    WHERE m.company_id = p_company_id AND m.status = 'active'
      AND (v_search IS NULL
           OR st.full_name ILIKE '%' || v_search || '%'
           OR st.university ILIKE '%' || v_search || '%'
           OR (v_digits IS NOT NULL AND st.phone LIKE '%' || v_digits || '%'))
    ORDER BY st.created_at DESC, st.id
    LIMIT v_limit + 1 OFFSET v_offset
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', p.id, 'phone', p.phone, 'full_name', p.full_name, 'university', p.university, 'college', p.college,
           'profile_image_url', p.profile_image_url, 'created_at', p.created_at,
           'subscriptions', COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
                      'id', s.id, 'status', s.status, 'type', s.type, 'price', s.price, 'created_at', s.created_at,
                      'start_date', s.start_date, 'end_date', s.end_date,
                      'period_label', public.period_label(s), 'period_phase', public.period_phase(s),
                      'departure_time', s.departure_time, 'return_time', s.return_time,
                      'line_name', l.name, 'trip_label', t.label, 'trip_university', u.name)
                    ORDER BY s.created_at DESC)
             FROM public.subscriptions s
             LEFT JOIN public.lines l ON l.id = s.line_id
             LEFT JOIN public.line_trips t ON t.id = s.departure_trip_id
             LEFT JOIN public.universities u ON u.id = t.university_id
             WHERE s.student_id = p.id AND s.company_id = p_company_id), '[]'::jsonb))
           ORDER BY p.created_at DESC, p.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count FROM page p;

  IF COALESCE(p_with_total, false) THEN
    SELECT count(*) INTO v_total
    FROM public.company_students m
    JOIN public.students st ON st.id = m.student_id
    WHERE m.company_id = p_company_id AND m.status = 'active'
      AND (v_search IS NULL
           OR st.full_name ILIKE '%' || v_search || '%'
           OR st.university ILIKE '%' || v_search || '%'
           OR (v_digits IS NOT NULL AND st.phone LIKE '%' || v_digits || '%'));
  END IF;

  -- The extra row only says there is a next page.
  IF v_count > v_limit THEN v_rows := v_rows - v_limit; END IF;
  RETURN jsonb_build_object('rows', v_rows, 'has_next', v_count > v_limit, 'total', v_total);
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. Receipts waiting for review
-- ------------------------------------------------------------------------------
-- Oldest first, with the student, the line and the station each belongs to.
CREATE OR REPLACE FUNCTION public.get_pending_receipts_page(p_company_id uuid, p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_rows jsonb;
  v_count integer;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك عرض إيصالات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  WITH page AS (
    SELECT r.id, r.image_url, r.attempt_number, r.created_at, r.amount, r.subscription_id
    FROM public.receipts r
    WHERE r.company_id = p_company_id AND r.status = 'pending'
    ORDER BY r.created_at, r.id
    LIMIT v_limit + 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', p.id, 'image_url', p.image_url, 'attempt_number', p.attempt_number, 'created_at', p.created_at,
           'amount', p.amount, 'subscription_id', p.subscription_id, 'student_id', s.student_id,
           'student_name', st.full_name, 'student_phone', st.phone, 'university', st.university, 'college', st.college,
           'company_id', l.company_id, 'company_name', c.name, 'line_name', l.name, 'station_name', sn.name,
           'departure_time', s.departure_time, 'return_time', s.return_time, 'subscription_type', s.type,
           'period_label', public.period_label(s), 'period_start', s.start_date, 'period_end', s.end_date,
           'period_phase', public.period_phase(s), 'price', s.price)
           ORDER BY p.created_at, p.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count
  FROM page p
  LEFT JOIN public.subscriptions s ON s.id = p.subscription_id
  LEFT JOIN public.students st ON st.id = s.student_id
  LEFT JOIN public.lines l ON l.id = s.line_id
  LEFT JOIN public.companies c ON c.id = l.company_id
  LEFT JOIN public.stations sn ON sn.id = s.station_id;

  IF v_count > v_limit THEN v_rows := v_rows - v_limit; END IF;
  RETURN jsonb_build_object('rows', v_rows, 'has_more', v_count > v_limit,
    'total', (SELECT count(*) FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'pending'));
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. Approve or reject, and what the screen needs afterwards
-- ------------------------------------------------------------------------------
-- The decision itself is the same UPDATE as before, made as the caller: the row
-- policies and the review triggers decide who may and what follows. The answer
-- adds the company's numbers as they are after it, so the dashboard re-reads
-- nothing. {id, status, company_id, reviewed_at, overview}
CREATE OR REPLACE FUNCTION public.review_receipt(p_receipt_id uuid, p_decision text, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_at timestamptz;
BEGIN
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'قرار غير صحيح.' USING ERRCODE = '22023';
  END IF;
  IF p_decision = 'rejected' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'اكتب سبب الرفض.' USING ERRCODE = '22023';
  END IF;
  UPDATE public.receipts
  SET status = p_decision, rejection_reason = CASE WHEN p_decision = 'rejected' THEN btrim(p_reason) END
  WHERE id = p_receipt_id AND status = 'pending'
  RETURNING company_id, reviewed_at INTO v_company, v_at;
  IF NOT FOUND THEN
    -- Not theirs to see, already decided by someone else, or gone.
    RAISE EXCEPTION 'هذا الإيصال لم يعد قيد المراجعة.' USING ERRCODE = 'BR010';
  END IF;
  -- reviewed_at orders two answers that cross on their way back.
  RETURN jsonb_build_object('id', p_receipt_id, 'status', p_decision, 'company_id', v_company, 'reviewed_at', v_at,
                            'overview', public.company_overview(v_company));
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. Rider counts of several lines at once
-- ------------------------------------------------------------------------------
-- {"<line id>": [the rows get_line_rider_counts_with_returns gives for it], …}.
-- Each line passes that function's own check, so nothing is opened up; a line
-- with no riders has no key.
CREATE OR REPLACE FUNCTION public.get_lines_rider_counts(p_line_ids uuid[], p_ride_date date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT COALESCE(jsonb_object_agg(y.line_id, y.rows), '{}'::jsonb)
  FROM (
    SELECT x.line_id, jsonb_agg(to_jsonb(c)) AS rows
    FROM (SELECT DISTINCT l AS line_id FROM unnest((COALESCE(p_line_ids, '{}'::uuid[]))[1:50]) AS l WHERE l IS NOT NULL) x
    CROSS JOIN LATERAL public.get_line_rider_counts_with_returns(x.line_id, p_ride_date) c
    GROUP BY x.line_id
  ) y
$$;

REVOKE ALL ON FUNCTION public.get_company_students_page(uuid, text, integer, integer, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_pending_receipts_page(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_receipt(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_lines_rider_counts(uuid[], date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_company_students_page(uuid, text, integer, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_receipts_page(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_receipt(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lines_rider_counts(uuid[], date) TO authenticated;


-- ------------------------------------------------------------------------------
-- 5. Company overview at scale (as 20261102000001)
--    With 220 lines and 110,000 paid subscriptions it took over three seconds:
--    the subscribers of each line were counted by passing over all of them once
--    per line, and every payment ever made was read to total the revenue.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_overview_data(p_company_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH day AS (SELECT public.cairo_today() AS today, public.next_votable_ride_date(p_company_id) AS next_ride),
  since AS (SELECT public.report_baseline('financial', p_company_id) AS at),
  paid AS (
    -- One payment per subscription: the approved receipt amount, else the price.
    -- Only what was paid since the last reset is read (all of it when never reset).
    SELECT s.paid_at, COALESCE(a.amount, s.price) AS amount
    FROM public.subscriptions s CROSS JOIN since
    -- The company's approved receipts read once, not looked up per subscription.
    LEFT JOIN (SELECT DISTINCT ON (r.subscription_id) r.subscription_id, r.amount
               FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'approved'
               ORDER BY r.subscription_id, r.reviewed_at DESC NULLS LAST) a ON a.subscription_id = s.id
    WHERE s.company_id = p_company_id AND s.paid_at IS NOT NULL AND (since.at IS NULL OR s.paid_at > since.at)
  ),
  running AS (
    -- Valid today, so a term paid in advance is not counted before it starts.
    -- Counted per line once (it was one pass over all of them for every line).
    SELECT s.line_id, count(*) AS n FROM public.subscriptions s, day
    WHERE s.company_id = p_company_id AND s.status = 'active' AND s.paid_at IS NOT NULL
      AND (s.start_date IS NULL OR s.start_date <= day.today) AND (s.end_date IS NULL OR s.end_date >= day.today)
    GROUP BY s.line_id
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
    'active_subscriptions', (SELECT COALESCE(sum(n), 0) FROM running),
    'pending_receipts', (SELECT count(*) FROM public.receipts r WHERE r.company_id = p_company_id AND r.status = 'pending'),
    'revenue', COALESCE((SELECT sum(p.amount) FROM paid p), 0)
             + COALESCE((SELECT sum(a.amount) FROM public.deleted_student_revenue a, since
                         WHERE a.company_id = p_company_id AND (since.at IS NULL OR a.archived_at > since.at)), 0),
    'riders_today', (SELECT riders FROM week, day WHERE week.ride_date = day.today),
    -- Students confirm for the NEXT ride once its vote opens; that day's count is what moves.
    'next_ride_date', (SELECT next_ride FROM day),
    'riders_next', (SELECT COALESCE((SELECT w.riders FROM week w WHERE w.ride_date = day.next_ride),
                                    public.company_riders_on(p_company_id, day.next_ride)) FROM day),
    'vote_closes_at', (SELECT left(v.closes_at::text, 5) FROM public.vote_settings(p_company_id) v),
    'riders_week', (SELECT jsonb_agg(jsonb_build_object('date', ride_date, 'riders', riders) ORDER BY ride_date) FROM week),
    'lines', (SELECT count(*) FROM public.lines l WHERE l.company_id = p_company_id),
    'active_lines', (SELECT count(*) FROM public.lines l WHERE l.company_id = p_company_id AND l.is_active),
    'supervisors', (SELECT count(*) FROM public.supervisors s WHERE s.company_id = p_company_id AND s.is_active),
    'admins', (SELECT count(*) FROM public.admins a WHERE a.company_id = p_company_id),
    'top_lines', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'is_active', l.is_active, 'subscribers', n)
                       ORDER BY n DESC, l.name)
      -- The ten busiest (the screens show five; the platform picks its ten from these).
      FROM (SELECT l.id, l.name, l.is_active, COALESCE(r.n, 0) AS n
            FROM public.lines l LEFT JOIN running r ON r.line_id = l.id
            WHERE l.company_id = p_company_id
            ORDER BY COALESCE(r.n, 0) DESC, l.name LIMIT 10) l), '[]'::jsonb)
  )
$function$;

-- ------------------------------------------------------------------------------
-- 6. Inbox page (as 20261031000001), read from the user's own rows
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_notifications_page(p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 30, p_unread_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_items jsonb;
  v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('items', '[]'::jsonb, 'unread', 0, 'next_before', NULL);
  END IF;
  -- From the user's own rows outwards (it used to walk every notification sent
  -- on the platform, newest first, looking for the user's).
  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.at DESC), '[]'::jsonb), count(*) INTO v_items, v_count
  FROM (
    SELECT public.notification_item(m.n, m.is_read) AS item, (m.n).sent_at AS at
    FROM (
      SELECT n, r.read_at IS NOT NULL AS is_read
      FROM public.notification_recipients r
      JOIN public.notifications n ON n.id = r.notification_id
      WHERE r.user_id = auth.uid() AND n.status = 'sent'
        AND n.sent_at > now() - interval '90 days'
        AND (p_before IS NULL OR n.sent_at < p_before)
        AND (NOT COALESCE(p_unread_only, false) OR r.read_at IS NULL)
      UNION ALL
      -- What the user sent themselves (a supervisor), which they are not a recipient of.
      SELECT n, true
      FROM public.notifications n
      WHERE n.sender_id = auth.uid() AND n.status = 'sent' AND NOT COALESCE(p_unread_only, false)
        AND n.sent_at > now() - interval '90 days'
        AND (p_before IS NULL OR n.sent_at < p_before)
        AND NOT EXISTS (SELECT 1 FROM public.notification_recipients r
                        WHERE r.notification_id = n.id AND r.user_id = auth.uid())
    ) m
    ORDER BY (m.n).sent_at DESC
    LIMIT v_limit + 1
  ) x;
  IF v_count > v_limit THEN
    v_items := v_items - v_limit;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'unread', public.get_my_unread_count(),
    'next_before', CASE WHEN v_count > v_limit THEN (v_items->(v_limit - 1))->>'created_at' END);
END;
$function$;

-- ------------------------------------------------------------------------------
-- 7. Financial report (as 20261102000001): the rows a page at a time
--    p_filters may carry "limit" (1–2000, default 2000 as before) and "offset";
--    the answer adds rows_total. 2000 rows were 1.1 MB of JSON on every refresh.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_subscription_report(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_company uuid := NULLIF(p_filters->>'company_id', '')::uuid;
  v_university uuid := NULLIF(p_filters->>'university_id', '')::uuid;
  v_line uuid := NULLIF(p_filters->>'line_id', '')::uuid;
  v_year int := NULLIF(p_filters->>'academic_year', '')::int;
  -- first|second|both|summer|daily ('annual' is the older name of both)
  v_period text := NULLIF(replace(p_filters->>'period', 'annual', 'both'), '');
  v_payment text := NULLIF(p_filters->>'payment', '');      -- paid|unpaid
  v_phase text := NULLIF(p_filters->>'phase', '');          -- current|upcoming|expired
  v_search text := NULLIF(btrim(p_filters->>'search'), '');
  v_history boolean := COALESCE((p_filters->>'include_before_reset')::boolean, false);
  v_today date := public.cairo_today();
  -- How many rows to show and from where (the totals always cover everything).
  v_limit int := LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit', '')::int, 2000), 1), 2000);
  v_offset int := GREATEST(COALESCE(NULLIF(p_filters->>'offset', '')::int, 0), 0);
  v_data jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;
  IF public.is_company_admin() THEN v_company := public.current_admin_company_id(); END IF;
  IF v_company IS NOT NULL AND NOT public.can_manage_company(v_company) THEN
    RAISE EXCEPTION 'التقارير المالية متاحة للإدارة فقط.' USING ERRCODE = '42501';
  END IF;

  WITH baselines AS (
    -- Each company counts from its own last reset.
    SELECT c.id, c.name, public.report_baseline('financial', c.id) AS since FROM public.companies c
    WHERE v_company IS NULL OR c.id = v_company
  ),
  filtered AS (
    SELECT s.id, s.type, s.status, s.academic_year, s.period_code, s.price, s.paid_at, s.start_date, s.end_date,
      s.created_at, s.company_id, st.full_name, st.phone, st.university AS university_name,
      l.name AS line_name, b.name AS company_name,
      COALESCE(s.period_code, CASE s.type WHEN 'daily' THEN 'daily' WHEN 'yearly' THEN 'both' END) AS period_key,
      CASE WHEN s.status = 'expired' OR s.end_date < v_today THEN 'expired'
           WHEN s.start_date > v_today THEN 'upcoming' ELSE 'current' END AS phase,
      (s.paid_at IS NOT NULL) AS is_paid,
      -- One payment per subscription: the approved receipt amount, else the price.
      CASE WHEN s.paid_at IS NOT NULL THEN COALESCE(a.amount, s.price) END AS paid_amount
    FROM public.subscriptions s
    JOIN public.students st ON st.id = s.student_id
    JOIN public.lines l ON l.id = s.line_id
    JOIN baselines b ON b.id = l.company_id
    -- Approved receipts read once for the company (or the platform), not per subscription.
    LEFT JOIN (SELECT DISTINCT ON (r.subscription_id) r.subscription_id, r.amount
               FROM public.receipts r WHERE r.status = 'approved' AND (v_company IS NULL OR r.company_id = v_company)
               ORDER BY r.subscription_id, r.reviewed_at DESC NULLS LAST) a ON a.subscription_id = s.id
    WHERE (v_company IS NULL OR s.company_id = v_company)
      AND (v_university IS NULL OR st.university_id = v_university)
      AND (v_line IS NULL OR s.line_id = v_line)
      AND (v_year IS NULL OR s.academic_year = v_year)
      AND (v_search IS NULL OR st.full_name ILIKE '%' || v_search || '%' OR st.phone LIKE '%' || regexp_replace(v_search, '\D', '', 'g') || '%')
      AND (v_history OR b.since IS NULL OR COALESCE(s.paid_at, s.created_at) > b.since)
      AND (v_period IS NULL OR COALESCE(s.period_code, CASE s.type WHEN 'daily' THEN 'daily' WHEN 'yearly' THEN 'both' END) = v_period)
      AND (v_payment IS NULL OR (v_payment = 'paid') = (s.paid_at IS NOT NULL))
      AND (v_phase IS NULL OR v_phase = CASE WHEN s.status = 'expired' OR s.end_date < v_today THEN 'expired'
                                             WHEN s.start_date > v_today THEN 'upcoming' ELSE 'current' END)
  ),
  totals AS (
    SELECT count(*) AS n,
      count(*) FILTER (WHERE is_paid) AS paid,
      count(*) FILTER (WHERE NOT is_paid AND status IN ('pending_payment', 'pending_review', 'rejected')) AS unpaid,
      count(*) FILTER (WHERE phase = 'upcoming') AS upcoming,
      count(*) FILTER (WHERE phase = 'upcoming' AND is_paid) AS upcoming_paid,
      count(*) FILTER (WHERE phase = 'expired') AS expired,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid), 0) AS revenue,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'first'), 0) AS revenue_first,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'second'), 0) AS revenue_second,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'summer'), 0) AS revenue_summer,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'both'), 0) AS revenue_both,
      COALESCE(sum(paid_amount) FILTER (WHERE is_paid AND period_key = 'daily'), 0) AS revenue_daily
    FROM filtered
  ),
  shown AS (
    -- The newest 2000 (before, it was whichever 2000 came first).
    SELECT * FROM filtered ORDER BY paid_at DESC NULLS LAST, created_at DESC, id LIMIT v_limit OFFSET v_offset
  ),
  labels AS (
    -- The period names of each company and year on show, asked once each.
    SELECT k.company_id, k.academic_year, p.period_code, p.label
    FROM (SELECT DISTINCT company_id, academic_year FROM shown WHERE type <> 'daily') k
    CROSS JOIN LATERAL public.company_periods(k.company_id, k.academic_year) p
  )
  SELECT jsonb_build_object(
    'baseline', (SELECT max(since) FROM baselines),
    'rows_total', (SELECT n FROM totals),
    'totals', (SELECT jsonb_build_object(
      'count', n, 'paid', paid, 'unpaid', unpaid, 'upcoming', upcoming, 'upcoming_paid', upcoming_paid,
      'expired', expired, 'revenue', revenue, 'revenue_first', revenue_first, 'revenue_second', revenue_second,
      'revenue_summer', revenue_summer, 'revenue_both', revenue_both, 'revenue_annual', revenue_both,
      'revenue_daily', revenue_daily) FROM totals),
    'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', f.id, 'student_name', f.full_name, 'phone', f.phone, 'university', f.university_name,
        'company', f.company_name, 'line', f.line_name, 'type', f.type, 'period', f.period_key,
        'academic_year', f.academic_year,
        'label', CASE WHEN f.type = 'daily' THEN 'اشتراك يومي'
                      ELSE (SELECT lb.label FROM labels lb WHERE lb.company_id = f.company_id
                              AND lb.academic_year = f.academic_year AND lb.period_code = f.period_code) END,
        'status', f.status, 'phase', f.phase, 'paid', f.is_paid, 'amount', f.paid_amount, 'price', f.price,
        'paid_at', f.paid_at, 'start_date', f.start_date, 'end_date', f.end_date,
        'payment_method', (SELECT pm.display_name FROM public.receipts r
                           JOIN public.company_payment_methods pm ON pm.id = r.payment_method_id
                           WHERE r.subscription_id = f.id ORDER BY r.created_at DESC LIMIT 1),
        'receipt_no', x.receipt_no, 'receipt_code', x.receipt_code)
        ORDER BY f.paid_at DESC NULLS LAST, f.created_at DESC, f.id)
      FROM shown f LEFT JOIN public.subscription_receipts x ON x.subscription_id = f.id), '[]'::jsonb)
  ) INTO v_data;
  RETURN v_data;
END;
$function$;

-- ------------------------------------------------------------------------------
-- 8. Students per university (as 20261102000001), decided once who is asking
--    (the platform check ran for every student: 4.8 s with 100,000 of them).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.university_student_counts() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'متاح للإدارة فقط.' USING ERRCODE = '42501'; END IF;
  IF public.is_super_admin() THEN
    RETURN COALESCE((SELECT jsonb_object_agg(x.university, x.n) FROM (
      SELECT s.university, count(*) AS n FROM public.students s
      WHERE s.university IS NOT NULL GROUP BY s.university) x), '{}'::jsonb);
  END IF;
  v_company := public.current_admin_company_id();
  RETURN COALESCE((SELECT jsonb_object_agg(x.university, x.n) FROM (
    SELECT s.university, count(*) AS n
    FROM public.company_students m JOIN public.students s ON s.id = m.student_id
    WHERE m.company_id = v_company AND m.status = 'active' AND s.university IS NOT NULL
    GROUP BY s.university) x), '{}'::jsonb);
END;
$$;

-- ------------------------------------------------------------------------------
-- 9. A company's confirmed riders on a day, counted directly
--    A student cannot hold two open subscriptions over the same days
--    (subscriptions_no_overlap), so "their newest valid one" is simply "their
--    valid one": no need to line every rider's subscriptions up first.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_riders_on(p_company_id uuid, p_date date)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN p_date >= public.cairo_today()
    THEN (SELECT count(DISTINCT drs.student_id)
          FROM public.daily_ride_status drs
          JOIN public.subscriptions s ON s.student_id = drs.student_id AND s.status = 'active'
           AND s.company_id = p_company_id
           AND COALESCE(s.start_date, p_date) <= p_date AND COALESCE(s.end_date, p_date) >= p_date
          WHERE drs.ride_date = p_date AND drs.is_riding)
    ELSE (SELECT count(*) FROM public.daily_ride_status d
          WHERE d.company_id = p_company_id AND d.ride_date = p_date AND d.is_riding)
  END
$$;

-- ------------------------------------------------------------------------------
-- 10. Catalog (as 20261102000001), worked out in sets
--     For every station of every line it passed over all the student's trips
--     again (228 lines and 1,700 stations: 0.65 s, and the request that held
--     everything else up under load). Now each table is read once and grouped.
--     The answer is the same.
-- ------------------------------------------------------------------------------
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
    'companies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path, 'lines', b.lines)
             ORDER BY c.name)
      FROM public.companies c JOIN by_company b ON b.company_id = c.id), '[]'::jsonb))
$$;

-- ------------------------------------------------------------------------------
-- 11. Search by name, phone or university together
--     Name and phone had trigram indexes, the university did not, so the three
--     searched together read every student (139 ms with 100,000; 2 ms with it).
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_students_university_trgm ON public.students USING gin (university gin_trgm_ops);

-- ------------------------------------------------------------------------------
-- 12. Receipt images: who may open one, found by the subscription's id
--     The rule matched the file to its subscription by comparing ids as text,
--     which no index can serve: every image checked every subscription. With
--     350,000 subscriptions, signing 50 images took 2 s and a student listing
--     their own folder ran into the timeout. The rule is the same: the file is
--     <student id>/<subscription id>_… and the caller manages that subscription's
--     company (or is the platform), or it is the student's own folder.
-- ------------------------------------------------------------------------------
-- The subscription a receipt image is named after, or NULL when the name is not of that form.
CREATE OR REPLACE FUNCTION public.receipt_object_subscription(p_name text) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN split_part(p_name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_'
              THEN left(split_part(p_name, '/', 2), 36)::uuid END
$$;

REVOKE ALL ON FUNCTION public.receipt_object_subscription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receipt_object_subscription(text) TO authenticated;

DROP POLICY IF EXISTS "Scoped receipt image access" ON storage.objects;
CREATE POLICY "Scoped receipt image access" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'receipts' AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR EXISTS (SELECT 1 FROM public.subscriptions sub
               WHERE sub.id = public.receipt_object_subscription(objects.name)
                 AND sub.student_id::text = (storage.foldername(objects.name))[1]
                 AND ((SELECT public.is_super_admin()) OR sub.company_id = (SELECT public.managed_company_id())))));
DROP POLICY IF EXISTS "Admins can manage scoped receipt objects" ON storage.objects;
CREATE POLICY "Admins can manage scoped receipt objects" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'receipts' AND EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.id = public.receipt_object_subscription(objects.name)
      AND sub.student_id::text = (storage.foldername(objects.name))[1]
      AND ((SELECT public.is_super_admin()) OR sub.company_id = (SELECT public.managed_company_id()))))
  WITH CHECK (bucket_id = 'receipts' AND EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.id = public.receipt_object_subscription(objects.name)
      AND sub.student_id::text = (storage.foldername(objects.name))[1]
      AND ((SELECT public.is_super_admin()) OR sub.company_id = (SELECT public.managed_company_id()))));
-- Contained in "Scoped receipt image access" (the student's own folder).
DROP POLICY IF EXISTS "Students can read their own receipts" ON storage.objects;

COMMIT;
