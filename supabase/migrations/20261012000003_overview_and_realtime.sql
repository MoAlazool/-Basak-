-- One agreed set of numbers, computed by the database:
--   company_overview(company)  for a company workspace
--   platform_overview()        for the platform admin: totals plus one row per company
-- and live change feeds for the tables the dashboards watch.

-- The numbers of one company. Internal: callers go through the two functions below.
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
    SELECT d::date AS ride_date,
           (SELECT count(*) FROM public.daily_ride_status r
            WHERE r.company_id = p_company_id AND r.ride_date = d::date AND r.is_riding) AS riders
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

CREATE OR REPLACE FUNCTION public.company_overview(p_company_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_company_id IS NULL OR NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'غير مسموح بعرض بيانات هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.companies WHERE id = p_company_id) THEN
    RAISE EXCEPTION 'الشركة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  RETURN public.company_overview_data(p_company_id);
END;
$$;

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

REVOKE ALL ON FUNCTION public.company_overview(uuid), public.platform_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_overview(uuid), public.platform_overview() TO authenticated, service_role;

-- Live change feeds. Row-level security applies to them as well, so a client
-- only ever receives rows it could have read.
DO $$
DECLARE t text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
  FOREACH t IN ARRAY ARRAY['receipts', 'subscriptions', 'company_students', 'daily_ride_status',
                           'supervisor_scan_events', 'companies'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END;
$$;
