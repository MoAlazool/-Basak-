-- =============================================================================
-- Company identity: a logo and an emblem
--
-- A company already has a LOGO: companies.logo_path (20261009000001), a folder
-- "<company id>/logo/<stamp>" in the public "wallet-assets" bucket holding the
-- image as PNG files: master.png (the mark as uploaded, at most 1024 px on its
-- longer side: receipts, headers), google.png (660x660, the mark centred on a
-- transparent square) and the sizes Apple Wallet wants. It is what the Wallet
-- card, the receipt PDF and the catalog show.
--
-- What was missing is the EMBLEM: a square mark for avatars, list rows, the
-- notification sender and anywhere a wide logo does not fit. It is stored the
-- same way: companies.emblem_path, a folder "<company id>/emblem/<stamp>" with
-- master.png (512x512) and small.png (128x128).
--
-- Rules:
--   * A path is stored, never a URL. The bucket is public (brand images, shown
--     to students before they belong to the company; it never held personal
--     data), so the address is
--       <project url>/storage/v1/object/public/wallet-assets/<path>/<file>
--   * Files are never overwritten: every upload is a new folder, so an address
--     never changes what it shows and can be cached for good.
--   * A company's admins (and the platform) add files to that company's folder
--     only, PNG only, at most 2 MB each (the bucket's own limits, unchanged).
--   * A folder still in use (the company's logo, emblem or Wallet banner, or the
--     logo printed on a receipt that was issued) cannot be deleted.
--
-- Additive: nothing is renamed or removed and no existing row changes.
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The emblem
-- ---------------------------------------------------------------------------
ALTER TABLE public.companies
  -- Folder in the public "wallet-assets" bucket: "<company id>/emblem/<stamp>".
  ADD COLUMN IF NOT EXISTS emblem_path text;

ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_emblem_path_check;
ALTER TABLE public.companies ADD CONSTRAINT companies_emblem_path_check
  CHECK (emblem_path IS NULL OR emblem_path ~ ('^' || id::text || '/emblem/[A-Za-z0-9_-]{1,64}$'));

-- ---------------------------------------------------------------------------
-- 2. Which artwork folders are still shown somewhere
-- ---------------------------------------------------------------------------
-- A receipt keeps the logo it was issued with (20261027000001); finding the
-- receipts of a logo must not read every receipt.
CREATE INDEX IF NOT EXISTS idx_subscription_receipts_logo_path ON public.subscription_receipts (company_logo_path)
  WHERE company_logo_path IS NOT NULL;

-- p_folder is "<company id>/<kind>/<stamp>".
CREATE OR REPLACE FUNCTION public.company_artwork_in_use(p_folder text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_folder IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.companies c WHERE c.logo_path = p_folder OR c.emblem_path = p_folder)
    OR EXISTS (SELECT 1 FROM public.wallet_card_settings w WHERE w.banner_path = p_folder)
    OR EXISTS (SELECT 1 FROM public.subscription_receipts r WHERE r.company_logo_path = p_folder))
$$;
REVOKE ALL ON FUNCTION public.company_artwork_in_use(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_artwork_in_use(text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Saving the identity
-- ---------------------------------------------------------------------------
-- Sets the company's logo and emblem to exactly what is given (NULL or '' = none).
-- A path must be a folder of this company, and a newly chosen one must already
-- hold its master.png. Answers with what is saved and with the folders that
-- are no longer shown anywhere ("stale"): the caller removes their files
-- through the Storage API, the only supported way to delete an object.
CREATE OR REPLACE FUNCTION public.set_company_branding(p_company_id uuid, p_logo_path text, p_emblem_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_logo text := NULLIF(btrim(COALESCE(p_logo_path, '')), '');
  v_emblem text := NULLIF(btrim(COALESCE(p_emblem_path, '')), '');
  v_old public.companies%ROWTYPE;
BEGIN
  IF p_company_id IS NULL OR NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك تعديل هوية هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_old FROM public.companies WHERE id = p_company_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الشركة غير موجودة.';
  END IF;
  -- Artwork must live in this company's own folder.
  IF v_logo !~ ('^' || p_company_id::text || '/logo/[A-Za-z0-9_-]{1,64}$')
     OR v_emblem !~ ('^' || p_company_id::text || '/emblem/[A-Za-z0-9_-]{1,64}$') THEN
    RAISE EXCEPTION 'مسار الصورة غير صالح.' USING ERRCODE = '22023';
  END IF;
  -- A newly chosen image must have been uploaded.
  IF (v_logo IS DISTINCT FROM v_old.logo_path AND v_logo IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'wallet-assets' AND o.name = v_logo || '/master.png'))
     OR (v_emblem IS DISTINCT FROM v_old.emblem_path AND v_emblem IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'wallet-assets' AND o.name = v_emblem || '/master.png')) THEN
    RAISE EXCEPTION 'لم يكتمل رفع الصورة. حاول مرة أخرى.' USING ERRCODE = '22023';
  END IF;

  -- Each column only when it changes: the logo is on the Wallet cards, and
  -- writing it marks every installed card of the company for delivery.
  IF v_logo IS DISTINCT FROM v_old.logo_path THEN
    UPDATE public.companies SET logo_path = v_logo WHERE id = p_company_id;
  END IF;
  IF v_emblem IS DISTINCT FROM v_old.emblem_path THEN
    UPDATE public.companies SET emblem_path = v_emblem WHERE id = p_company_id;
  END IF;

  RETURN jsonb_build_object(
    'company_id', p_company_id, 'name', v_old.name, 'logo_path', v_logo, 'emblem_path', v_emblem,
    'stale', COALESCE((
      SELECT jsonb_agg(DISTINCT f) FROM unnest(ARRAY[v_old.logo_path, v_old.emblem_path]) f
      WHERE f IS NOT NULL AND NOT public.company_artwork_in_use(f)), '[]'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.set_company_branding(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_company_branding(uuid, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. The bucket: add and read in the company's own folder, never overwrite,
--    delete only what is no longer shown
--    (was one rule for everything, 20261009000001: a company's admin could
--    overwrite a file in place or delete the logo of an issued receipt.)
-- ---------------------------------------------------------------------------
-- The company an object belongs to (its first folder), when the caller manages it.
CREATE OR REPLACE FUNCTION public.can_manage_artwork_object(p_name text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.companies c
                 WHERE c.id::text = split_part(p_name, '/', 1) AND public.can_manage_company(c.id))
$$;
REVOKE ALL ON FUNCTION public.can_manage_artwork_object(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_artwork_object(text) TO authenticated, service_role;

DROP POLICY IF EXISTS "Company manages its wallet artwork" ON storage.objects;
DROP POLICY IF EXISTS "Company lists its artwork" ON storage.objects;
DROP POLICY IF EXISTS "Company adds its artwork" ON storage.objects;
DROP POLICY IF EXISTS "Company removes its unused artwork" ON storage.objects;
-- Reading a file needs no rule (the bucket is public); this one is for listing a folder.
CREATE POLICY "Company lists its artwork" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'wallet-assets' AND public.can_manage_artwork_object(name));
CREATE POLICY "Company adds its artwork" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'wallet-assets' AND public.can_manage_artwork_object(name)
    AND name ~ '^[0-9a-f-]{36}/(logo|banner|emblem)/[A-Za-z0-9_-]{1,64}/[A-Za-z0-9@_-]{1,40}\.png$');
CREATE POLICY "Company removes its unused artwork" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'wallet-assets' AND public.can_manage_artwork_object(name)
    AND NOT public.company_artwork_in_use(array_to_string((string_to_array(name, '/'))[1:3], '/')));
-- No UPDATE rule on purpose: a file is never replaced in place.

-- ---------------------------------------------------------------------------
-- 5. Everywhere a company is read, both marks come with it
-- ---------------------------------------------------------------------------
-- 5a. The dashboard's numbers (as 20261103000001): "company" also carries
--     logo_path and emblem_path. company_overview and platform_overview are
--     built from this, so every company card gets them.
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
    'company', (SELECT jsonb_build_object('id', c.id, 'name', c.name, 'status', c.status, 'created_at', c.created_at,
                                               'logo_path', c.logo_path, 'emblem_path', c.emblem_path)
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

-- 5b. The app's catalog (as 20261103000001): each company also carries emblem_path.
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
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path,
                                         'emblem_path', c.emblem_path, 'lines', b.lines)
             ORDER BY c.name)
      FROM public.companies c JOIN by_company b ON b.company_id = c.id), '[]'::jsonb))
$$;

-- 5c. One notification as the app shows it (as 20261031000001), with the company
--     it comes from: {id, name, logo_path, emblem_path}.
CREATE OR REPLACE FUNCTION public.notification_item(n public.notifications, p_read boolean)
RETURNS jsonb
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT jsonb_build_object('id', n.id, 'type', n.type, 'category', n.category, 'priority', n.priority,
    'title', n.title, 'body', n.body, 'title_en', n.title_en, 'body_en', n.body_en,
    'created_at', COALESCE(n.sent_at, n.created_at), 'sender_role', n.sender_role, 'sender_name', n.sender_name,
    'audience', n.audience, 'read', p_read, 'mine', n.sender_id IS NOT DISTINCT FROM auth.uid(), 'data', n.data,
    'company', (SELECT jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path, 'emblem_path', c.emblem_path)
                FROM public.companies c WHERE c.id = n.company_id))
$$;
REVOKE ALL ON FUNCTION public.notification_item(public.notifications, boolean) FROM PUBLIC, anon, authenticated;

COMMIT;
