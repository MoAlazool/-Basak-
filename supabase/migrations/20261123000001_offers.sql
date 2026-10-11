-- ==============================================================================
-- Migration: 20261123000001_offers.sql
-- Run AFTER 20261122000001. Safe to re-run. Additive.
--
-- «عروض باصك»: offers from merchants (a café by the university, a shop selling
-- a faculty's tools), entered by the platform and shown to the students they are
-- meant for. A student uses one with a coupon inside the app.
--
--   merchants          who the offer is from.
--   offers             the offer, when it runs, its limits and its audience.
--   offer_redemptions  a coupon a student opened; counted once it is confirmed
--                      (at once, or by the merchant's PIN when the offer has one).
--   offer_impressions  that a student was shown an offer, and opened it. Once.
--   students.offers_hidden   the student's own switch.
--
-- Audience (offers.audience, every key optional, all of them must hold):
--   {"university_ids": [uuid], "colleges": [text], "specialisations": [text],
--    "company_ids": [uuid], "line_ids": [uuid], "governorates": [code],
--    "subscription": "active" | "any",           -- default "active"
--    "min_rides": n, "min_attendance": 0-100, "window_days": 7-120}  -- default 30
--   A ride = a day with a checked-in scan. Attendance = of the days the student
--   said they would ride (before today), the share they were scanned on.
--   A governorate is the student's companies' (students have none of their own).
--
-- Nothing here is readable or writable from a client except through the
-- functions below. A merchant is never given anything about a student: the
-- platform's numbers are counts, and a group of fewer than 5 is folded away.
--
-- Students:  get_my_offers(), offer_seen(uuid[]), offer_opened(uuid),
--            redeem_offer(uuid), confirm_offer_redemption(uuid, text),
--            set_offers_hidden(boolean)
-- Platform (super admin): platform_offers_overview(), platform_save_merchant(jsonb),
--            platform_save_offer(jsonb), platform_set_offer_status(uuid, text),
--            platform_delete_offer(uuid), platform_delete_merchant(uuid),
--            platform_preview_offer_audience(jsonb),
--            platform_offer_stats(uuid)
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Tables
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.merchants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
  category text NOT NULL DEFAULT 'other'
    CHECK (category IN ('food', 'study', 'services', 'health', 'shopping', 'other')),
  -- Object names in the offer-assets bucket, never URLs.
  logo_path text,
  phone text,
  whatsapp text,
  link_url text,
  address text,
  university_id uuid REFERENCES public.universities(id) ON DELETE SET NULL,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  description text NOT NULL DEFAULT '' CHECK (char_length(description) <= 600),
  terms text NOT NULL DEFAULT '' CHECK (char_length(terms) <= 600),
  image_path text,
  -- 'info' is an advert: no coupon, only the merchant's contact.
  kind text NOT NULL DEFAULT 'percent' CHECK (kind IN ('percent', 'amount', 'gift', 'info')),
  -- As shown on the card: «20%», «50 ج.م», «مشروب مجاني».
  value_label text NOT NULL DEFAULT '' CHECK (char_length(value_label) <= 24),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'live', 'paused', 'ended')),
  audience jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- «عرض خاص لك»: shown first, and told once with a notification.
  special boolean NOT NULL DEFAULT false,
  per_student_limit integer NOT NULL DEFAULT 1 CHECK (per_student_limit BETWEEN 1 AND 100),
  total_limit integer CHECK (total_limit IS NULL OR total_limit >= 1),
  coupon_minutes integer NOT NULL DEFAULT 10 CHECK (coupon_minutes BETWEEN 2 AND 60),
  -- The merchant's PIN (bcrypt), typed on the student's phone at the till.
  pin_hash text,
  sort integer NOT NULL DEFAULT 0,
  -- The platform's own bookkeeping; never sent to the app.
  price numeric(10, 2),
  internal_note text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  -- When a special offer's audience was told (once).
  announced_at timestamptz,
  CHECK (ends_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS idx_offers_live ON public.offers(status, starts_at) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS idx_offers_merchant ON public.offers(merchant_id);

CREATE TABLE IF NOT EXISTS public.offer_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id uuid NOT NULL REFERENCES public.offers(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  code text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  -- Used. Set at once when the offer has no PIN, else when the PIN is typed.
  confirmed_at timestamptz,
  pin_attempts integer NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_offer_redemptions_offer ON public.offer_redemptions(offer_id, confirmed_at);
CREATE INDEX IF NOT EXISTS idx_offer_redemptions_student ON public.offer_redemptions(student_id, offer_id);

CREATE TABLE IF NOT EXISTS public.offer_impressions (
  offer_id uuid NOT NULL REFERENCES public.offers(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  opened_at timestamptz,
  PRIMARY KEY (offer_id, student_id)
);

ALTER TABLE public.students ADD COLUMN IF NOT EXISTS offers_hidden boolean NOT NULL DEFAULT false;
ALTER TABLE public.offers ADD COLUMN IF NOT EXISTS announced_at timestamptz;

ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offer_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offer_impressions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.merchants, public.offers, public.offer_redemptions, public.offer_impressions
  FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 2. Pictures: a public bucket only the platform writes to
--    merchants/<merchant id>/<file>   offers/<offer id>/<file>
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('offer-assets', 'offer-assets', true, 3145728, ARRAY['image/png', 'image/jpeg', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = true, file_size_limit = 3145728, allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp'];

DROP POLICY IF EXISTS "Platform manages offer pictures" ON storage.objects;
CREATE POLICY "Platform manages offer pictures" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'offer-assets' AND (SELECT public.is_super_admin()))
  WITH CHECK (bucket_id = 'offer-assets' AND (SELECT public.is_super_admin())
              AND name ~ '^(offers|merchants)/[0-9a-f-]{36}/[A-Za-z0-9_.-]{1,80}\.(png|jpg|jpeg|webp)$');

CREATE OR REPLACE FUNCTION public.offer_picture_path(p_path text, p_folder text, p_id uuid)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v_path text := NULLIF(btrim(COALESCE(p_path, '')), '');
BEGIN
  IF v_path IS NULL THEN RETURN NULL; END IF;
  IF v_path !~ ('^' || p_folder || '/' || p_id || '/[A-Za-z0-9_.-]{1,80}\.(png|jpg|jpeg|webp)$') THEN
    RAISE EXCEPTION 'مسار الصورة غير صحيح.';
  END IF;
  RETURN v_path;
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. Audience
-- ------------------------------------------------------------------------------
-- The spec as it is stored: known keys only, each of the right shape.
CREATE OR REPLACE FUNCTION public.offer_audience_clean(p_spec jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_spec jsonb := COALESCE(p_spec, '{}'::jsonb);
  v_out jsonb := '{}'::jsonb;
  v_key text;
  v_list jsonb;
  v_n integer;
BEGIN
  IF jsonb_typeof(v_spec) <> 'object' THEN RAISE EXCEPTION 'الجمهور غير صحيح.'; END IF;
  FOREACH v_key IN ARRAY ARRAY['university_ids', 'company_ids', 'line_ids', 'colleges', 'specialisations', 'governorates'] LOOP
    v_list := v_spec->v_key;
    CONTINUE WHEN v_list IS NULL OR v_list = 'null'::jsonb;
    IF jsonb_typeof(v_list) <> 'array' OR jsonb_array_length(v_list) > 200
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) e WHERE jsonb_typeof(e) <> 'string') THEN
      RAISE EXCEPTION 'الجمهور غير صحيح.';
    END IF;
    IF v_key LIKE '%\_ids' THEN
      -- Raises on anything that is not an id.
      PERFORM e::uuid FROM jsonb_array_elements_text(v_list) e;
    END IF;
    SELECT COALESCE(jsonb_agg(DISTINCT btrim(e)), '[]'::jsonb) INTO v_list
    FROM jsonb_array_elements_text(v_list) e WHERE btrim(e) <> '';
    IF jsonb_array_length(v_list) > 0 THEN v_out := v_out || jsonb_build_object(v_key, v_list); END IF;
  END LOOP;
  IF v_spec->>'subscription' = 'any' THEN v_out := v_out || '{"subscription": "any"}'::jsonb; END IF;
  v_n := NULLIF(v_spec->>'min_rides', '')::integer;
  IF v_n IS NOT NULL AND v_n > 0 THEN
    IF v_n > 200 THEN RAISE EXCEPTION 'عدد الرحلات المطلوب كبير جداً.'; END IF;
    v_out := v_out || jsonb_build_object('min_rides', v_n);
  END IF;
  v_n := NULLIF(v_spec->>'min_attendance', '')::integer;
  IF v_n IS NOT NULL AND v_n > 0 THEN
    IF v_n > 100 THEN RAISE EXCEPTION 'نسبة الحضور من 0 إلى 100.'; END IF;
    v_out := v_out || jsonb_build_object('min_attendance', v_n);
  END IF;
  IF v_out ?| ARRAY['min_rides', 'min_attendance'] THEN
    v_n := COALESCE(NULLIF(v_spec->>'window_days', '')::integer, 30);
    IF v_n NOT BETWEEN 7 AND 120 THEN RAISE EXCEPTION 'مدة قياس الالتزام من 7 إلى 120 يوماً.'; END IF;
    v_out := v_out || jsonb_build_object('window_days', v_n);
  END IF;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.offer_audience_clean(jsonb) FROM PUBLIC, anon, authenticated;

-- How a student rode in the last p_days (up to yesterday): days scanned on
-- the bus, days they said they would ride, and of those the days scanned.
CREATE OR REPLACE FUNCTION public.student_commitment(p_student uuid, p_days integer DEFAULT 30)
RETURNS TABLE (rides integer, voted integer, attended integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH w AS (SELECT public.cairo_today() - GREATEST(COALESCE(p_days, 30), 1) AS since, public.cairo_today() AS today),
  boarded AS (
    SELECT DISTINCT e.ride_date FROM public.supervisor_scan_events e, w
    WHERE e.student_id = p_student AND e.result = 'checked_in' AND e.ride_date >= w.since AND e.ride_date < w.today
  ),
  said AS (
    SELECT d.ride_date FROM public.daily_ride_status d, w
    WHERE d.student_id = p_student AND d.is_riding AND d.ride_date >= w.since AND d.ride_date < w.today
  )
  SELECT (SELECT count(*) FROM boarded)::integer,
         (SELECT count(*) FROM said)::integer,
         (SELECT count(*) FROM said s JOIN boarded b USING (ride_date))::integer;
$$;
REVOKE ALL ON FUNCTION public.student_commitment(uuid, integer) FROM PUBLIC, anon, authenticated;

-- Whether p_student is in the audience p_spec (already cleaned).
CREATE OR REPLACE FUNCTION public.offer_audience_matches(p_spec jsonb, p_student uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_s public.students%ROWTYPE;
  v_today date := public.cairo_today();
  v_c record;
BEGIN
  SELECT * INTO v_s FROM public.students WHERE id = p_student;
  IF NOT FOUND THEN RETURN false; END IF;

  IF p_spec ? 'university_ids' AND NOT (v_s.university_id IS NOT NULL AND p_spec->'university_ids' ? v_s.university_id::text) THEN
    RETURN false;
  END IF;
  IF p_spec ? 'colleges' AND NOT (p_spec->'colleges' ? btrim(v_s.college)) THEN RETURN false; END IF;
  IF p_spec ? 'specialisations' AND NOT (v_s.specialisation IS NOT NULL AND p_spec->'specialisations' ? btrim(v_s.specialisation)) THEN
    RETURN false;
  END IF;

  -- A running subscription, unless the offer is for every student.
  IF COALESCE(p_spec->>'subscription', 'active') = 'active' AND NOT EXISTS (
       SELECT 1 FROM public.subscriptions s
       WHERE s.student_id = p_student AND s.status = 'active' AND (s.end_date IS NULL OR s.end_date >= v_today)) THEN
    RETURN false;
  END IF;
  IF p_spec ? 'line_ids' AND NOT EXISTS (
       SELECT 1 FROM public.subscriptions s
       WHERE s.student_id = p_student AND s.status = 'active' AND (s.end_date IS NULL OR s.end_date >= v_today)
         AND p_spec->'line_ids' ? s.line_id::text) THEN
    RETURN false;
  END IF;
  IF p_spec ? 'company_ids' AND NOT EXISTS (
       SELECT 1 FROM public.company_students cs
       WHERE cs.student_id = p_student AND cs.status = 'active' AND p_spec->'company_ids' ? cs.company_id::text) THEN
    RETURN false;
  END IF;
  IF p_spec ? 'governorates' AND NOT EXISTS (
       SELECT 1 FROM public.company_students cs
       JOIN public.company_governorates g ON g.company_id = cs.company_id
       WHERE cs.student_id = p_student AND cs.status = 'active' AND p_spec->'governorates' ? g.governorate_code) THEN
    RETURN false;
  END IF;

  IF p_spec ?| ARRAY['min_rides', 'min_attendance'] THEN
    SELECT * INTO v_c FROM public.student_commitment(p_student, COALESCE((p_spec->>'window_days')::integer, 30));
    IF v_c.rides < COALESCE((p_spec->>'min_rides')::integer, 0) THEN RETURN false; END IF;
    IF p_spec ? 'min_attendance'
       AND (v_c.voted = 0 OR v_c.attended * 100 < (p_spec->>'min_attendance')::integer * v_c.voted) THEN
      RETURN false;
    END IF;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.offer_audience_matches(jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- An offer students can see right now.
CREATE OR REPLACE FUNCTION public.offer_is_running(o public.offers)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT o.status = 'live' AND o.starts_at <= now() AND (o.ends_at IS NULL OR o.ends_at > now())
     AND EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = o.merchant_id AND m.is_active);
$$;
REVOKE ALL ON FUNCTION public.offer_is_running(public.offers) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 4. The student's side
-- ------------------------------------------------------------------------------
-- {hidden, offers: [{id, title, description, terms, image_path, kind, value_label,
--   ends_at, special, needs_pin, coupon_minutes, per_student_limit, used, left,
--   coupon: {id, code, expires_at, seconds_left, confirmed} | null,
--   merchant: {id, name, category, logo_path, phone, whatsapp, link_url, address}}]}
-- `used` = the student's own confirmed uses; `left` = what remains of the total
-- (null when unlimited). An offer that ran out stays only for who used it.
CREATE OR REPLACE FUNCTION public.get_my_offers()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_hidden boolean;
  v_offers jsonb;
BEGIN
  SELECT s.offers_hidden INTO v_hidden FROM public.students s WHERE s.id = v_me;
  IF NOT FOUND THEN RETURN jsonb_build_object('hidden', false, 'offers', '[]'::jsonb); END IF;
  IF v_hidden THEN RETURN jsonb_build_object('hidden', true, 'offers', '[]'::jsonb); END IF;

  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.special DESC, x.sort DESC, x.published_at DESC NULLS LAST), '[]'::jsonb)
  INTO v_offers
  FROM (
    SELECT o.special, o.sort, o.published_at,
           jsonb_build_object(
             'id', o.id, 'title', o.title, 'description', o.description, 'terms', o.terms,
             'image_path', o.image_path, 'kind', o.kind, 'value_label', o.value_label,
             'ends_at', o.ends_at, 'special', o.special, 'needs_pin', o.pin_hash IS NOT NULL,
             'coupon_minutes', o.coupon_minutes, 'per_student_limit', o.per_student_limit,
             'used', u.mine, 'left', CASE WHEN o.total_limit IS NULL THEN NULL ELSE GREATEST(o.total_limit - u.everyone, 0) END,
             'coupon', (SELECT jsonb_build_object('id', r.id, 'code', r.code, 'expires_at', r.expires_at,
                                                  'seconds_left', GREATEST(ceil(extract(epoch FROM r.expires_at - now())), 0)::integer,
                                                  'confirmed', r.confirmed_at IS NOT NULL)
                        FROM public.offer_redemptions r
                        WHERE r.offer_id = o.id AND r.student_id = v_me AND r.expires_at > now()
                        ORDER BY r.created_at DESC LIMIT 1),
             'merchant', jsonb_build_object('id', m.id, 'name', m.name, 'category', m.category,
                                            'logo_path', m.logo_path, 'phone', m.phone, 'whatsapp', m.whatsapp,
                                            'link_url', m.link_url, 'address', m.address)) AS item
    FROM public.offers o
    JOIN public.merchants m ON m.id = o.merchant_id
    CROSS JOIN LATERAL (
      SELECT count(*) FILTER (WHERE r.student_id = v_me)::integer AS mine, count(*)::integer AS everyone
      FROM public.offer_redemptions r WHERE r.offer_id = o.id AND r.confirmed_at IS NOT NULL
    ) u
    WHERE public.offer_is_running(o)
      AND public.offer_audience_matches(o.audience, v_me)
      AND (o.total_limit IS NULL OR u.everyone < o.total_limit OR u.mine > 0)
  ) x;
  RETURN jsonb_build_object('hidden', false, 'offers', v_offers);
END;
$$;

-- The offers were on the student's screen (once each, however often shown).
CREATE OR REPLACE FUNCTION public.offer_seen(p_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.students WHERE id = v_me) OR p_ids IS NULL OR cardinality(p_ids) > 100 THEN RETURN; END IF;
  INSERT INTO public.offer_impressions(offer_id, student_id)
  SELECT o.id, v_me FROM public.offers o WHERE o.id = ANY (p_ids) AND o.status = 'live'
  ON CONFLICT DO NOTHING;
END;
$$;

-- The student opened the offer's page.
CREATE OR REPLACE FUNCTION public.offer_opened(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.students WHERE id = v_me) THEN RETURN; END IF;
  INSERT INTO public.offer_impressions(offer_id, student_id, opened_at)
  SELECT o.id, v_me, now() FROM public.offers o WHERE o.id = p_id AND o.status = 'live'
  ON CONFLICT (offer_id, student_id) DO UPDATE SET opened_at = COALESCE(public.offer_impressions.opened_at, now());
END;
$$;

-- «استخدم العرض»: the coupon to show at the till.
-- {id, code, expires_at, seconds_left, needs_pin, confirmed}. `seconds_left`
-- is by the server's clock, so a phone with a wrong clock still counts right.
-- A coupon still running is given again rather than a second one made, unless
-- it was already used and the student may use the offer again, or its PIN
-- tries ran out (it is then closed; three such coupons an hour at most, so the
-- PIN cannot be guessed by asking for coupon after coupon).
CREATE OR REPLACE FUNCTION public.redeem_offer(p_offer uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_me uuid := auth.uid();
  v_o public.offers%ROWTYPE;
  v_r public.offer_redemptions%ROWTYPE;
  v_mine integer;
  v_all integer;
  v_code text := '';
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
BEGIN
  IF v_me IS NULL OR NOT EXISTS (SELECT 1 FROM public.students WHERE id = v_me) THEN
    RAISE EXCEPTION 'العروض للطلاب فقط.' USING ERRCODE = '42501';
  END IF;
  -- One at a time for the offer, so its total is never passed.
  SELECT * INTO v_o FROM public.offers WHERE id = p_offer FOR UPDATE;
  IF NOT FOUND OR NOT public.offer_is_running(v_o) OR NOT public.offer_audience_matches(v_o.audience, v_me) THEN
    RAISE EXCEPTION 'هذا العرض غير متاح الآن.';
  END IF;
  IF v_o.kind = 'info' THEN RAISE EXCEPTION 'هذا العرض لا يحتاج كوبوناً.'; END IF;

  SELECT count(*) FILTER (WHERE student_id = v_me), count(*) INTO v_mine, v_all
  FROM public.offer_redemptions WHERE offer_id = p_offer AND confirmed_at IS NOT NULL;

  SELECT * INTO v_r FROM public.offer_redemptions
  WHERE offer_id = p_offer AND student_id = v_me AND expires_at > now()
  ORDER BY created_at DESC LIMIT 1;
  IF FOUND AND v_r.confirmed_at IS NULL AND v_r.pin_attempts >= 5 THEN
    UPDATE public.offer_redemptions SET expires_at = now() WHERE id = v_r.id;
  ELSIF FOUND AND (v_r.confirmed_at IS NULL OR v_mine >= v_o.per_student_limit) THEN
    RETURN jsonb_build_object('id', v_r.id, 'code', v_r.code, 'expires_at', v_r.expires_at,
                              'seconds_left', GREATEST(ceil(extract(epoch FROM v_r.expires_at - now())), 0)::integer,
                              'needs_pin', v_o.pin_hash IS NOT NULL, 'confirmed', v_r.confirmed_at IS NOT NULL);
  END IF;

  IF v_mine >= v_o.per_student_limit THEN RAISE EXCEPTION 'استخدمت هذا العرض من قبل.'; END IF;
  IF v_o.total_limit IS NOT NULL AND v_all >= v_o.total_limit THEN RAISE EXCEPTION 'انتهت الكمية المتاحة من هذا العرض.'; END IF;
  IF (SELECT count(*) FROM public.offer_redemptions
      WHERE offer_id = p_offer AND student_id = v_me AND confirmed_at IS NULL AND pin_attempts >= 5
        AND created_at > now() - interval '1 hour') >= 3 THEN
    RAISE EXCEPTION 'محاولات كثيرة برمز غير صحيح. حاول مرة أخرى بعد ساعة.';
  END IF;

  v_bytes := gen_random_bytes(6);
  FOR i IN 0..5 LOOP
    v_code := v_code || substr(v_alphabet, get_byte(v_bytes, i) % length(v_alphabet) + 1, 1);
  END LOOP;
  INSERT INTO public.offer_redemptions(offer_id, student_id, code, expires_at, confirmed_at)
  VALUES (p_offer, v_me, v_code, now() + make_interval(mins => v_o.coupon_minutes),
          CASE WHEN v_o.pin_hash IS NULL THEN now() END)
  RETURNING * INTO v_r;
  RETURN jsonb_build_object('id', v_r.id, 'code', v_r.code, 'expires_at', v_r.expires_at,
                            'seconds_left', v_o.coupon_minutes * 60,
                            'needs_pin', v_o.pin_hash IS NOT NULL, 'confirmed', v_r.confirmed_at IS NOT NULL);
END;
$$;

-- The merchant types their PIN on the student's phone. Five tries a coupon.
CREATE OR REPLACE FUNCTION public.confirm_offer_redemption(p_redemption uuid, p_pin text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_me uuid := auth.uid();
  v_r public.offer_redemptions%ROWTYPE;
  v_o public.offers%ROWTYPE;
  v_all integer;
BEGIN
  SELECT * INTO v_r FROM public.offer_redemptions WHERE id = p_redemption AND student_id = v_me FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الكوبون غير موجود.' USING ERRCODE = '42501'; END IF;
  IF v_r.confirmed_at IS NOT NULL THEN RETURN jsonb_build_object('confirmed', true); END IF;
  IF v_r.expires_at <= now() THEN RAISE EXCEPTION 'انتهت مدة الكوبون. اطلب كوبوناً جديداً.'; END IF;
  IF v_r.pin_attempts >= 5 THEN RAISE EXCEPTION 'محاولات كثيرة. اطلب كوبوناً جديداً.'; END IF;
  SELECT * INTO v_o FROM public.offers WHERE id = v_r.offer_id FOR UPDATE;
  IF v_o.pin_hash IS NULL THEN
    UPDATE public.offer_redemptions SET confirmed_at = now() WHERE id = v_r.id;
    RETURN jsonb_build_object('confirmed', true);
  END IF;
  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4,6}$' OR crypt(p_pin, v_o.pin_hash) <> v_o.pin_hash THEN
    UPDATE public.offer_redemptions SET pin_attempts = pin_attempts + 1 WHERE id = v_r.id;
    RETURN jsonb_build_object('confirmed', false, 'tries_left', GREATEST(4 - v_r.pin_attempts, 0));
  END IF;
  SELECT count(*) INTO v_all FROM public.offer_redemptions WHERE offer_id = v_o.id AND confirmed_at IS NOT NULL;
  IF v_o.total_limit IS NOT NULL AND v_all >= v_o.total_limit THEN RAISE EXCEPTION 'انتهت الكمية المتاحة من هذا العرض.'; END IF;
  UPDATE public.offer_redemptions SET confirmed_at = now() WHERE id = v_r.id;
  RETURN jsonb_build_object('confirmed', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_offers_hidden(p_hidden boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.students SET offers_hidden = COALESCE(p_hidden, false) WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'العروض للطلاب فقط.' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE(p_hidden, false);
END;
$$;

-- ------------------------------------------------------------------------------
-- 5. The platform's side (super admin only)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.offers_require_platform()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.offers_require_platform() FROM PUBLIC, anon;

-- Students in an audience (those who hid offers are not counted).
CREATE OR REPLACE FUNCTION public.offer_audience_count(p_spec jsonb)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::integer FROM public.students s
  WHERE NOT s.offers_hidden AND public.offer_audience_matches(p_spec, s.id);
$$;
REVOKE ALL ON FUNCTION public.offer_audience_count(jsonb) FROM PUBLIC, anon, authenticated;

-- {students} an audience would reach today, before anything is saved.
CREATE OR REPLACE FUNCTION public.platform_preview_offer_audience(p_spec jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.offers_require_platform();
  RETURN jsonb_build_object('students', public.offer_audience_count(public.offer_audience_clean(p_spec)));
END;
$$;

-- {id, …}: adds a merchant, or changes the one with that id.
CREATE OR REPLACE FUNCTION public.platform_save_merchant(p_merchant jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid := COALESCE(NULLIF(p_merchant->>'id', '')::uuid, gen_random_uuid());
  v_link text := NULLIF(btrim(COALESCE(p_merchant->>'link_url', '')), '');
BEGIN
  PERFORM public.offers_require_platform();
  IF v_link IS NOT NULL AND v_link !~* '^https://[^\s]{3,250}$' THEN RAISE EXCEPTION 'الرابط يجب أن يبدأ بـ https://'; END IF;
  INSERT INTO public.merchants(id, name, category, logo_path, phone, whatsapp, link_url, address, university_id, notes, is_active)
  VALUES (v_id, btrim(p_merchant->>'name'), COALESCE(NULLIF(p_merchant->>'category', ''), 'other'),
          public.offer_picture_path(p_merchant->>'logo_path', 'merchants', v_id),
          NULLIF(btrim(COALESCE(p_merchant->>'phone', '')), ''), NULLIF(btrim(COALESCE(p_merchant->>'whatsapp', '')), ''),
          v_link, NULLIF(btrim(COALESCE(p_merchant->>'address', '')), ''),
          NULLIF(p_merchant->>'university_id', '')::uuid, NULLIF(btrim(COALESCE(p_merchant->>'notes', '')), ''),
          COALESCE((p_merchant->>'is_active')::boolean, true))
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, category = EXCLUDED.category, logo_path = EXCLUDED.logo_path, phone = EXCLUDED.phone,
    whatsapp = EXCLUDED.whatsapp, link_url = EXCLUDED.link_url, address = EXCLUDED.address,
    university_id = EXCLUDED.university_id, notes = EXCLUDED.notes, is_active = EXCLUDED.is_active, updated_at = now();
  RETURN jsonb_build_object('id', v_id);
END;
$$;

-- {id, merchant_id, title, …, audience, pin}: adds an offer (as a draft) or
-- changes it. "pin": absent keeps the PIN, "" removes it, 4-6 digits sets it.
-- Its status is changed with platform_set_offer_status only.
CREATE OR REPLACE FUNCTION public.platform_save_offer(p_offer jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_id uuid := COALESCE(NULLIF(p_offer->>'id', '')::uuid, gen_random_uuid());
  v_spec jsonb := public.offer_audience_clean(p_offer->'audience');
  v_pin text := p_offer->>'pin';
  v_kind text := COALESCE(NULLIF(p_offer->>'kind', ''), 'percent');
BEGIN
  PERFORM public.offers_require_platform();
  IF v_pin IS NOT NULL AND v_pin <> '' AND v_pin !~ '^[0-9]{4,6}$' THEN RAISE EXCEPTION 'رمز التاجر من 4 إلى 6 أرقام.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.merchants WHERE id = (p_offer->>'merchant_id')::uuid) THEN RAISE EXCEPTION 'اختر التاجر.'; END IF;
  INSERT INTO public.offers(id, merchant_id, title, description, terms, image_path, kind, value_label, starts_at, ends_at,
                            audience, special, per_student_limit, total_limit, coupon_minutes, pin_hash, sort, price,
                            internal_note, created_by)
  VALUES (v_id, (p_offer->>'merchant_id')::uuid, btrim(p_offer->>'title'), btrim(COALESCE(p_offer->>'description', '')),
          btrim(COALESCE(p_offer->>'terms', '')), public.offer_picture_path(p_offer->>'image_path', 'offers', v_id),
          v_kind, btrim(COALESCE(p_offer->>'value_label', '')),
          COALESCE(NULLIF(p_offer->>'starts_at', '')::timestamptz, now()), NULLIF(p_offer->>'ends_at', '')::timestamptz,
          v_spec, COALESCE((p_offer->>'special')::boolean, false),
          COALESCE(NULLIF(p_offer->>'per_student_limit', '')::integer, 1), NULLIF(p_offer->>'total_limit', '')::integer,
          COALESCE(NULLIF(p_offer->>'coupon_minutes', '')::integer, 10),
          CASE WHEN v_pin ~ '^[0-9]{4,6}$' AND v_kind <> 'info' THEN crypt(v_pin, gen_salt('bf', 8)) END,
          COALESCE(NULLIF(p_offer->>'sort', '')::integer, 0), NULLIF(p_offer->>'price', '')::numeric,
          NULLIF(btrim(COALESCE(p_offer->>'internal_note', '')), ''), auth.uid())
  ON CONFLICT (id) DO UPDATE SET
    merchant_id = EXCLUDED.merchant_id, title = EXCLUDED.title, description = EXCLUDED.description, terms = EXCLUDED.terms,
    image_path = EXCLUDED.image_path, kind = EXCLUDED.kind, value_label = EXCLUDED.value_label,
    starts_at = CASE WHEN NULLIF(p_offer->>'starts_at', '') IS NULL THEN public.offers.starts_at ELSE EXCLUDED.starts_at END,
    ends_at = EXCLUDED.ends_at, audience = EXCLUDED.audience, special = EXCLUDED.special,
    per_student_limit = EXCLUDED.per_student_limit, total_limit = EXCLUDED.total_limit,
    coupon_minutes = EXCLUDED.coupon_minutes,
    pin_hash = CASE WHEN EXCLUDED.kind = 'info' OR v_pin = '' THEN NULL
                    WHEN v_pin IS NULL THEN public.offers.pin_hash ELSE EXCLUDED.pin_hash END,
    sort = EXCLUDED.sort, price = EXCLUDED.price, internal_note = EXCLUDED.internal_note, updated_at = now();
  RETURN jsonb_build_object('id', v_id, 'students', public.offer_audience_count(v_spec));
END;
$$;

-- Tells the audience of every special offer that is running and has not been
-- announced yet; each offer once. No student is told of more than one special
-- offer in 7 days. Called when an offer is published, and every few minutes
-- for offers published ahead of their start. Returns how many were told.
CREATE OR REPLACE FUNCTION public.offers_announce_due()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_o public.offers%ROWTYPE;
  v_merchant text;
  v_student record;
  v_notified integer := 0;
BEGIN
  FOR v_o IN SELECT * FROM public.offers o
             WHERE o.special AND o.announced_at IS NULL AND public.offer_is_running(o) FOR UPDATE SKIP LOCKED LOOP
    UPDATE public.offers SET announced_at = now() WHERE id = v_o.id;
    SELECT m.name INTO v_merchant FROM public.merchants m WHERE m.id = v_o.merchant_id;
    FOR v_student IN
      SELECT s.id, (SELECT cs.company_id FROM public.company_students cs
                    WHERE cs.student_id = s.id AND cs.status = 'active' ORDER BY cs.joined_at DESC LIMIT 1) AS company_id
      FROM public.students s
      WHERE NOT s.offers_hidden AND public.offer_audience_matches(v_o.audience, s.id)
        AND NOT EXISTS (SELECT 1 FROM public.notification_recipients r
                        JOIN public.notifications n ON n.id = r.notification_id
                        WHERE r.user_id = s.id AND n.type = 'offer.special' AND n.created_at > now() - interval '7 days')
    LOOP
      CONTINUE WHEN v_student.company_id IS NULL;
      PERFORM public.notify_student(v_student.company_id, v_student.id, 'offer.special',
        jsonb_build_object('offer_id', v_o.id, 'merchant', v_merchant, 'offer', v_o.title),
        'offer:' || v_o.id || ':' || v_student.id);
      v_notified := v_notified + 1;
    END LOOP;
  END LOOP;
  RETURN v_notified;
END;
$$;
REVOKE ALL ON FUNCTION public.offers_announce_due() FROM PUBLIC, anon, authenticated;

-- Publishes, pauses or ends an offer. {status, notified}.
-- A special offer tells its audience once: now when it is already running,
-- else when it starts (offers_announce_due).
CREATE OR REPLACE FUNCTION public.platform_set_offer_status(p_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_o public.offers%ROWTYPE;
  v_m public.merchants%ROWTYPE;
BEGIN
  PERFORM public.offers_require_platform();
  IF p_status NOT IN ('draft', 'live', 'paused', 'ended') THEN RAISE EXCEPTION 'حالة غير معروفة.'; END IF;
  SELECT * INTO v_o FROM public.offers WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'العرض غير موجود.'; END IF;
  SELECT * INTO v_m FROM public.merchants WHERE id = v_o.merchant_id;
  IF p_status = 'live' THEN
    IF NOT v_m.is_active THEN RAISE EXCEPTION 'التاجر موقوف. فعّله أولاً.'; END IF;
    IF v_o.ends_at IS NOT NULL AND v_o.ends_at <= now() THEN RAISE EXCEPTION 'تاريخ انتهاء العرض مضى. عدّله أولاً.'; END IF;
    IF v_o.kind <> 'info' AND btrim(v_o.value_label) = '' THEN RAISE EXCEPTION 'اكتب قيمة العرض (مثل 20%%).'; END IF;
  END IF;
  UPDATE public.offers SET status = p_status, updated_at = now(),
         published_at = CASE WHEN p_status = 'live' THEN COALESCE(published_at, now()) ELSE published_at END
  WHERE id = p_id;
  RETURN jsonb_build_object('status', p_status,
                            'notified', CASE WHEN p_status = 'live' THEN public.offers_announce_due() ELSE 0 END);
END;
$$;

-- A merchant with no offers can be deleted; another is stopped instead.
CREATE OR REPLACE FUNCTION public.platform_delete_merchant(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.offers_require_platform();
  IF EXISTS (SELECT 1 FROM public.offers WHERE merchant_id = p_id) THEN
    RAISE EXCEPTION 'لهذا التاجر عروض، فلا يُحذف. أوقفه بدلاً من ذلك.';
  END IF;
  DELETE FROM public.merchants WHERE id = p_id;
END;
$$;

-- Only an offer nobody used can be deleted; another is ended instead.
CREATE OR REPLACE FUNCTION public.platform_delete_offer(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.offers_require_platform();
  IF EXISTS (SELECT 1 FROM public.offer_redemptions WHERE offer_id = p_id AND confirmed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'استُخدم هذا العرض، فلا يُحذف. أنهِه بدلاً من ذلك.';
  END IF;
  DELETE FROM public.offers WHERE id = p_id;
END;
$$;

-- Both pages of the dashboard in one read.
-- {merchants: [{id, name, category, logo_path, phone, whatsapp, link_url, address,
--    university_id, notes, is_active, offers}],
--  offers: [{id, merchant_id, merchant_name, title, description, terms, image_path,
--    kind, value_label, starts_at, ends_at, status, running, audience, special,
--    per_student_limit, total_limit, coupon_minutes, has_pin, sort, price,
--    internal_note, published_at, announced_at, seen, opened, redeemed}]}
CREATE OR REPLACE FUNCTION public.platform_offers_overview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.offers_require_platform();
  RETURN jsonb_build_object(
    'merchants', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'category', m.category, 'logo_path', m.logo_path, 'phone', m.phone,
        'whatsapp', m.whatsapp, 'link_url', m.link_url, 'address', m.address, 'university_id', m.university_id,
        'notes', m.notes, 'is_active', m.is_active,
        'offers', (SELECT count(*) FROM public.offers o WHERE o.merchant_id = m.id)) ORDER BY m.name), '[]'::jsonb)
      FROM public.merchants m),
    'offers', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', o.id, 'merchant_id', o.merchant_id, 'merchant_name', m.name, 'title', o.title,
        'description', o.description, 'terms', o.terms, 'image_path', o.image_path, 'kind', o.kind,
        'value_label', o.value_label, 'starts_at', o.starts_at, 'ends_at', o.ends_at, 'status', o.status,
        'running', public.offer_is_running(o), 'audience', o.audience, 'special', o.special,
        'per_student_limit', o.per_student_limit, 'total_limit', o.total_limit, 'coupon_minutes', o.coupon_minutes,
        'has_pin', o.pin_hash IS NOT NULL, 'sort', o.sort, 'price', o.price, 'internal_note', o.internal_note,
        'published_at', o.published_at, 'announced_at', o.announced_at,
        'seen', (SELECT count(*) FROM public.offer_impressions i WHERE i.offer_id = o.id),
        'opened', (SELECT count(*) FROM public.offer_impressions i WHERE i.offer_id = o.id AND i.opened_at IS NOT NULL),
        'redeemed', (SELECT count(*) FROM public.offer_redemptions r WHERE r.offer_id = o.id AND r.confirmed_at IS NOT NULL))
        ORDER BY o.created_at DESC), '[]'::jsonb)
      FROM public.offers o JOIN public.merchants m ON m.id = o.merchant_id));
END;
$$;

-- One offer's numbers. Counts only: no student is named, and a university or
-- college with fewer than 5 students who saw the offer is folded into «أخرى».
-- {reach, seen, opened, coupons, redeemed, students_redeemed,
--  by_university: [{name, seen, redeemed}], by_college: [{name, seen, redeemed}],
--  by_day: [{day, redeemed}]}
CREATE OR REPLACE FUNCTION public.platform_offer_stats(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_o public.offers%ROWTYPE;
BEGIN
  PERFORM public.offers_require_platform();
  SELECT * INTO v_o FROM public.offers WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'العرض غير موجود.'; END IF;
  RETURN (
    WITH seen AS (
      SELECT i.student_id, i.opened_at, COALESCE(NULLIF(btrim(s.university), ''), 'غير محدد') AS university,
             COALESCE(NULLIF(btrim(s.college), ''), 'غير محدد') AS college
      FROM public.offer_impressions i JOIN public.students s ON s.id = i.student_id WHERE i.offer_id = p_id
    ),
    used AS (
      SELECT r.student_id, r.confirmed_at FROM public.offer_redemptions r
      WHERE r.offer_id = p_id AND r.confirmed_at IS NOT NULL
    ),
    grouped AS (
      SELECT 'university' AS dim, s.university AS name, count(*) AS seen,
             (SELECT count(*) FROM used u JOIN seen s2 ON s2.student_id = u.student_id WHERE s2.university = s.university) AS redeemed
      FROM seen s GROUP BY s.university
      UNION ALL
      SELECT 'college', s.college, count(*),
             (SELECT count(*) FROM used u JOIN seen s2 ON s2.student_id = u.student_id WHERE s2.college = s.college)
      FROM seen s GROUP BY s.college
    ),
    folded AS (
      SELECT dim, CASE WHEN seen < 5 THEN 'أخرى' ELSE name END AS name, sum(seen) AS seen, sum(redeemed) AS redeemed
      FROM grouped GROUP BY 1, 2
    )
    SELECT jsonb_build_object(
      'reach', public.offer_audience_count(v_o.audience),
      'seen', (SELECT count(*) FROM seen),
      'opened', (SELECT count(*) FROM seen WHERE opened_at IS NOT NULL),
      'coupons', (SELECT count(*) FROM public.offer_redemptions r WHERE r.offer_id = p_id),
      'redeemed', (SELECT count(*) FROM used),
      'students_redeemed', (SELECT count(DISTINCT student_id) FROM used),
      'by_university', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'seen', seen, 'redeemed', redeemed)
                               ORDER BY (name = 'أخرى'), seen DESC), '[]'::jsonb) FROM folded WHERE dim = 'university'),
      'by_college', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'seen', seen, 'redeemed', redeemed)
                            ORDER BY (name = 'أخرى'), seen DESC), '[]'::jsonb) FROM folded WHERE dim = 'college'),
      'by_day', (SELECT COALESCE(jsonb_agg(jsonb_build_object('day', d.day, 'redeemed', d.n) ORDER BY d.day), '[]'::jsonb)
                 FROM (SELECT (confirmed_at AT TIME ZONE 'Africa/Cairo')::date AS day, count(*) AS n FROM used GROUP BY 1) d)));
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. Told to the phones and the dashboard when what students see changes
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.announce_offer_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_payload jsonb := jsonb_build_object('table', 'offers', 'op', TG_OP);
  v_line uuid;
  v_students boolean;
BEGIN
  PERFORM public.announce('platform', v_payload);
  IF TG_TABLE_NAME = 'merchants' THEN
    v_students := EXISTS (SELECT 1 FROM public.offers o WHERE o.merchant_id = COALESCE(NEW.id, OLD.id) AND o.status = 'live');
  ELSE
    v_students := (TG_OP <> 'INSERT' AND OLD.status = 'live') OR (TG_OP <> 'DELETE' AND NEW.status = 'live');
  END IF;
  IF v_students THEN
    FOR v_line IN SELECT l.id FROM public.lines l WHERE public.company_is_active(l.company_id) LOOP
      PERFORM public.announce('line:' || v_line, v_payload);
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_offer_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_announce_offer_change ON public.offers;
CREATE TRIGGER trg_announce_offer_change AFTER INSERT OR UPDATE OR DELETE ON public.offers
  FOR EACH ROW EXECUTE FUNCTION public.announce_offer_change();
DROP TRIGGER IF EXISTS trg_announce_merchant_change ON public.merchants;
CREATE TRIGGER trg_announce_merchant_change AFTER INSERT OR UPDATE OR DELETE ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.announce_offer_change();

-- ------------------------------------------------------------------------------
-- 7. The notification of a special offer
-- ------------------------------------------------------------------------------
INSERT INTO public.notification_templates
  (key, category, priority, title_ar, body_ar, title_en, body_en, route, supervisor_quick, needs_minutes, direction, sort)
VALUES
  ('offer.special', 'announcement', 'normal',
   'عرض خاص لك', '{merchant}: {offer}',
   'A special offer for you', '{merchant}: {offer}',
   'offers', false, false, NULL, 40)
ON CONFLICT (key) DO UPDATE SET
  category = EXCLUDED.category, priority = EXCLUDED.priority, title_ar = EXCLUDED.title_ar, body_ar = EXCLUDED.body_ar,
  title_en = EXCLUDED.title_en, body_en = EXCLUDED.body_en, route = EXCLUDED.route, sort = EXCLUDED.sort;

-- ------------------------------------------------------------------------------
-- 8. Who may call what
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_my_offers() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.offer_seen(uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.offer_opened(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_offer(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_offer_redemption(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_offers_hidden(boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_preview_offer_audience(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_save_merchant(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_save_offer(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_set_offer_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_delete_offer(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_delete_merchant(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_offers_overview() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_offer_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_offers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.offer_seen(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.offer_opened(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_offer_redemption(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_offers_hidden(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_preview_offer_audience(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_save_merchant(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_save_offer(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_offer_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_delete_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_delete_merchant(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_offers_overview() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_offer_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.offers_require_platform() TO authenticated;

COMMIT;

-- Special offers published ahead of their start are announced when it comes.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'basak-offers-announce';
    PERFORM cron.schedule('basak-offers-announce', '*/5 * * * *', 'SELECT public.offers_announce_due()');
  ELSE
    RAISE NOTICE 'pg_cron is not installed: run public.offers_announce_due() every few minutes another way.';
  END IF;
END $$;
