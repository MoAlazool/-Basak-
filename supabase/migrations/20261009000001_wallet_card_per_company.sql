-- Student Wallet card, version 2: a transport-company credential.
--
--  * The card still belongs to the STUDENT: serial number = students.id,
--    barcode = students.qr_code_value. Neither changes, ever.
--  * What it LOOKS like belongs to the company the student rides with: each
--    company has its own design (wallet_card_settings), its own logo and its
--    own contact number (companies). There is no per-student design.
--  * What it SHOWS is decided in one place, wallet_card_content(): identity,
--    photo, and - only for an APPROVED subscription - the line and pickup
--    station.
--  * Installed cards follow changes by themselves: database triggers mark the
--    affected cards and one Edge Function (wallet-sync) delivers them. Nothing
--    runs on a timer.
--
-- Whether a student may ride is still decided only by
-- supervisor_check_in_student() at scan time. Nothing here touches that.
-- Safe to re-run.
BEGIN;

-- Lets a trigger notify the wallet-sync function (same extension Supabase's
-- Database Webhooks use). Absent on a bare local Postgres: cards are then
-- still marked and get delivered by the next sync call.
DO $$ BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_net;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_net is not available here: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Company identity (shared with the rest of the product, not wallet-only)
-- ---------------------------------------------------------------------------
ALTER TABLE public.companies
  -- Folder in the public "wallet-assets" bucket: "<company id>/logo/<stamp>".
  ADD COLUMN IF NOT EXISTS logo_path text,
  -- The number the company wants riders to call, and what to call it.
  ADD COLUMN IF NOT EXISTS contact_phone text,
  ADD COLUMN IF NOT EXISTS contact_label text;

-- ---------------------------------------------------------------------------
-- 2. One wallet design per company (replaces the single global design)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_wallet_card_settings();
DROP FUNCTION IF EXISTS public.set_wallet_card_settings(text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.wallet_pending_passes(uuid, text, integer);
DO $$ BEGIN
  -- Version 1 kept a single row keyed by a boolean; it held only defaults.
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'wallet_card_settings' AND column_name = 'id') THEN
    DROP TABLE public.wallet_card_settings;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.wallet_card_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  background_color text NOT NULL DEFAULT '#00658D' CHECK (background_color ~ '^#[0-9A-F]{6}$'),
  -- Apple Wallet only: Google chooses its own text colour.
  foreground_color text NOT NULL DEFAULT '#FFFFFF' CHECK (foreground_color ~ '^#[0-9A-F]{6}$'),
  label_color text NOT NULL DEFAULT '#D6EEF9' CHECK (label_color ~ '^#[0-9A-F]{6}$'),
  -- Shown instead of the company name when set.
  card_title text CHECK (card_title IS NULL OR char_length(btrim(card_title)) BETWEEN 1 AND 40),
  -- Google Wallet only (Apple's ID-style pass has no banner): "<company id>/banner/<stamp>".
  banner_path text,
  revision integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.wallet_card_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_card_settings FROM anon, authenticated;  -- via the RPCs below
GRANT ALL ON public.wallet_card_settings TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Issued cards: what they last showed, and the delivery queue
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_wallet_passes_pending;
ALTER TABLE public.wallet_passes
  DROP COLUMN IF EXISTS synced_revision,
  -- The company whose branding the card carries (for company-scoped rollouts).
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  -- md5 of wallet_card_content() as last delivered to the wallet.
  ADD COLUMN IF NOT EXISTS content_hash text,
  -- Not null = the installed card is out of date and waits for wallet-sync.
  ADD COLUMN IF NOT EXISTS dirty_at timestamptz,
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_error text,
  -- Google only: the unguessable part of the student's photo link, and the
  -- photo version it was issued for (a new photo gets a new link).
  ADD COLUMN IF NOT EXISTS photo_token text,
  ADD COLUMN IF NOT EXISTS photo_version text;
CREATE INDEX IF NOT EXISTS idx_wallet_passes_company ON public.wallet_passes (company_id);
CREATE INDEX IF NOT EXISTS idx_wallet_passes_dirty ON public.wallet_passes (dirty_at) WHERE dirty_at IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_wallet_passes_photo_token ON public.wallet_passes (photo_token) WHERE photo_token IS NOT NULL;

-- Where and how a trigger reaches wallet-sync. The secret never leaves the
-- database and the function; the URL is filled in by the function itself.
CREATE TABLE IF NOT EXISTS public.wallet_runtime (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  sync_secret text NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  sync_url text
);
INSERT INTO public.wallet_runtime (id) VALUES (true) ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.wallet_runtime ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_runtime FROM anon, authenticated;
GRANT ALL ON public.wallet_runtime TO service_role;

-- ---------------------------------------------------------------------------
-- 4. THE definition of what a student's card shows
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wallet_card_content(p_student_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_student public.students%ROWTYPE;
  v_route record;
  v_company_id uuid;
  v_company public.companies%ROWTYPE;
  v_theme public.wallet_card_settings%ROWTYPE;
  v_photo jsonb;
BEGIN
  SELECT * INTO v_student FROM public.students WHERE id = p_student_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Route: only from an APPROVED subscription - the one valid today, else one
  -- approved in advance. A line the student merely selected (pending payment
  -- or review, rejected) is never shown.
  SELECT sub.company_id, l.name AS line_name, st.name AS station_name
  INTO v_route
  FROM public.subscriptions sub
  JOIN public.lines l ON l.id = sub.line_id
  JOIN public.stations st ON st.id = sub.station_id
  WHERE sub.student_id = p_student_id AND sub.status = 'active'
    AND (sub.end_date IS NULL OR sub.end_date >= v_today)
  ORDER BY (COALESCE(sub.start_date, v_today) <= v_today) DESC,
           CASE WHEN COALESCE(sub.start_date, v_today) <= v_today THEN NULL ELSE sub.start_date END ASC NULLS FIRST,
           sub.created_at DESC
  LIMIT 1;

  -- Branding: that subscription's company, else the company of the last
  -- subscription that was ever approved, so the card keeps its look between
  -- semesters. A pending subscription with another company changes nothing.
  IF v_route.company_id IS NOT NULL THEN
    v_company_id := v_route.company_id;
  ELSE
    SELECT sub.company_id INTO v_company_id
    FROM public.subscriptions sub
    WHERE sub.student_id = p_student_id AND sub.status IN ('active', 'expired') AND sub.company_id IS NOT NULL
    ORDER BY COALESCE(sub.end_date, sub.start_date) DESC NULLS LAST, sub.created_at DESC
    LIMIT 1;
  END IF;
  IF v_company_id IS NOT NULL THEN
    SELECT * INTO v_company FROM public.companies WHERE id = v_company_id;
    SELECT * INTO v_theme FROM public.wallet_card_settings WHERE company_id = v_company_id;
  END IF;

  -- The photo's version changes when the file is replaced, even at the same path.
  IF NULLIF(btrim(COALESCE(v_student.profile_image_url, '')), '') IS NOT NULL THEN
    SELECT jsonb_build_object('path', v_student.profile_image_url,
                              'version', COALESCE(max(to_jsonb(o) ->> 'updated_at'), max(o.created_at::text), ''))
    INTO v_photo
    FROM storage.objects o
    WHERE o.bucket_id = 'student-avatars' AND o.name = v_student.profile_image_url
    HAVING count(*) > 0;
  END IF;

  RETURN jsonb_build_object(
    'student', jsonb_build_object(
      'id', v_student.id,
      'full_name', btrim(v_student.full_name),
      'qr_code_value', v_student.qr_code_value,
      'university', NULLIF(NULLIF(btrim(COALESCE(v_student.university, '')), ''), 'غير محدد'),
      -- "غير محدد" is the column default, i.e. missing: never print it.
      'college', NULLIF(NULLIF(btrim(COALESCE(v_student.college, '')), ''), 'غير محدد')),
    'photo', v_photo,
    'company', CASE WHEN v_company.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_company.id,
      'name', btrim(v_company.name),
      'logo_path', v_company.logo_path,
      'contact_phone', NULLIF(btrim(COALESCE(v_company.contact_phone, '')), ''),
      'contact_label', NULLIF(btrim(COALESCE(v_company.contact_label, '')), '')) END,
    'theme', jsonb_build_object(
      'background_color', COALESCE(v_theme.background_color, '#00658D'),
      'foreground_color', COALESCE(v_theme.foreground_color, '#FFFFFF'),
      'label_color', COALESCE(v_theme.label_color, '#D6EEF9'),
      'card_title', NULLIF(btrim(COALESCE(v_theme.card_title, '')), ''),
      'banner_path', v_theme.banner_path,
      'revision', COALESCE(v_theme.revision, 0)),
    'route', CASE WHEN v_route.line_name IS NULL THEN NULL ELSE jsonb_build_object(
      'line', NULLIF(btrim(v_route.line_name), ''),
      'station', NULLIF(btrim(COALESCE(v_route.station_name, '')), '')) END
  );
END;
$$;

-- The content together with its fingerprint, read in one go so the two always
-- belong together. wallet-sync stores the fingerprint of what it delivered.
CREATE OR REPLACE FUNCTION public.wallet_card_payload(p_student_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN c.content IS NULL THEN NULL
              ELSE jsonb_build_object('content', c.content, 'hash', md5(c.content::text)) END
  FROM (SELECT public.wallet_card_content(p_student_id) AS content) c
$$;
REVOKE ALL ON FUNCTION public.wallet_card_payload(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_card_payload(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Marking cards whose content changed, and waking the delivery function
-- ---------------------------------------------------------------------------
-- One wake-up per transaction is enough: a bulk update marks many cards, and
-- wallet-sync drains the whole queue. The request leaves only after commit,
-- so the function always sees the committed marks.
CREATE OR REPLACE FUNCTION public.wallet_kick_sync()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_runtime public.wallet_runtime%ROWTYPE;
BEGIN
  IF to_regnamespace('net') IS NULL OR current_setting('wallet.kicked', true) = txid_current()::text THEN RETURN; END IF;
  SELECT * INTO v_runtime FROM public.wallet_runtime WHERE id AND sync_url IS NOT NULL;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM set_config('wallet.kicked', txid_current()::text, true);
  EXECUTE 'SELECT net.http_post(url := $1, body := $2, headers := $3)'
    USING v_runtime.sync_url, '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-wallet-sync-secret', v_runtime.sync_secret);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'wallet sync wake-up failed: %', SQLERRM;
END;
$$;

-- Marks the cards of these students that no longer match what they should
-- show. Students without a card, and cards that are already right, cost one
-- cheap lookup and nothing else. Returns how many cards were marked.
CREATE OR REPLACE FUNCTION public.wallet_touch_students(p_student_ids uuid[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_marked integer := 0;
BEGIN
  IF p_student_ids IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.wallet_passes WHERE student_id = ANY (p_student_ids)) THEN
    RETURN 0;
  END IF;
  WITH current_content AS (
    SELECT s.id AS student_id, public.wallet_card_content(s.id) AS content
    FROM (SELECT DISTINCT student_id AS id FROM public.wallet_passes WHERE student_id = ANY (p_student_ids)) s
  )
  UPDATE public.wallet_passes p SET
    dirty_at = now(),
    claimed_at = NULL,
    company_id = NULLIF(c.content #>> '{company,id}', '')::uuid
  FROM current_content c
  WHERE p.student_id = c.student_id AND c.content IS NOT NULL
    AND md5(c.content::text) IS DISTINCT FROM p.content_hash;
  GET DIAGNOSTICS v_marked = ROW_COUNT;
  IF v_marked > 0 THEN PERFORM public.wallet_kick_sync(); END IF;
  RETURN v_marked;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_touch_company(p_company_id uuid)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.wallet_touch_students(ARRAY(
    SELECT DISTINCT student_id FROM public.wallet_passes WHERE company_id = p_company_id))
$$;

-- One batch of out-of-date cards for wallet-sync. A claimed card is left
-- alone for two minutes, so a card that keeps failing never blocks the rest
-- and two callers never deliver the same card at once.
CREATE OR REPLACE FUNCTION public.wallet_claim_dirty(p_company_id uuid DEFAULT NULL, p_limit integer DEFAULT 20)
RETURNS SETOF public.wallet_passes LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.wallet_passes p SET claimed_at = now()
  WHERE (p.student_id, p.platform) IN (
    SELECT q.student_id, q.platform FROM public.wallet_passes q
    WHERE q.dirty_at IS NOT NULL
      AND (p_company_id IS NULL OR q.company_id = p_company_id)
      AND (q.claimed_at IS NULL OR q.claimed_at < now() - interval '2 minutes')
    ORDER BY q.dirty_at
    LIMIT greatest(1, least(COALESCE(p_limit, 20), 50))
    FOR UPDATE SKIP LOCKED)
  RETURNING p.*
$$;

REVOKE ALL ON FUNCTION public.wallet_card_content(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_kick_sync() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_touch_students(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_touch_company(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_claim_dirty(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_card_content(uuid), public.wallet_touch_students(uuid[]),
  public.wallet_touch_company(uuid), public.wallet_claim_dirty(uuid, integer) TO service_role;

-- The student's own app asks "is my card still right?" when the QR screen
-- opens. This is what catches a subscription starting or ending by date.
CREATE OR REPLACE FUNCTION public.wallet_refresh_my_card()
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.wallet_touch_students(ARRAY[auth.uid()])
$$;
REVOKE ALL ON FUNCTION public.wallet_refresh_my_card() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wallet_refresh_my_card() TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Event hooks. Each one only marks cards; a wallet problem must never make
--    the original write (a subscription, a receipt review, a line edit) fail.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wallet_on_student_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row jsonb;
  v_student uuid;
BEGIN
  BEGIN
    v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    v_student := NULLIF(v_row ->> CASE WHEN TG_TABLE_NAME = 'students' THEN 'id' ELSE 'student_id' END, '')::uuid;
    IF v_student IS NOT NULL THEN PERFORM public.wallet_touch_students(ARRAY[v_student]); END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'wallet card refresh skipped: %', SQLERRM;
  END;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_on_route_rename()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    PERFORM public.wallet_touch_students(ARRAY(
      SELECT DISTINCT sub.student_id FROM public.subscriptions sub
      WHERE CASE WHEN TG_TABLE_NAME = 'lines' THEN sub.line_id = NEW.id ELSE sub.station_id = NEW.id END));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'wallet card refresh skipped: %', SQLERRM;
  END;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_on_company_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    PERFORM public.wallet_touch_company(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'wallet card refresh skipped: %', SQLERRM;
  END;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_on_student_event(), public.wallet_on_route_rename(),
  public.wallet_on_company_change() FROM PUBLIC, anon, authenticated;

-- A subscription is created, approved, rejected, expired, moved or removed.
DROP TRIGGER IF EXISTS trg_wallet_subscription_change ON public.subscriptions;
CREATE TRIGGER trg_wallet_subscription_change
AFTER INSERT OR DELETE OR UPDATE OF status, line_id, station_id, company_id, start_date, end_date
ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION public.wallet_on_student_event();

-- The student's name, university, college or photo is corrected.
DROP TRIGGER IF EXISTS trg_wallet_student_change ON public.students;
CREATE TRIGGER trg_wallet_student_change
AFTER UPDATE OF full_name, university, college, profile_image_url
ON public.students FOR EACH ROW EXECUTE FUNCTION public.wallet_on_student_event();

-- A supervisor scans the student: the moment the card is looked at, so the
-- moment to notice that a subscription started or ended by date.
DROP TRIGGER IF EXISTS trg_wallet_scan ON public.supervisor_scan_events;
CREATE TRIGGER trg_wallet_scan
AFTER INSERT ON public.supervisor_scan_events FOR EACH ROW EXECUTE FUNCTION public.wallet_on_student_event();

DROP TRIGGER IF EXISTS trg_wallet_line_rename ON public.lines;
CREATE TRIGGER trg_wallet_line_rename
AFTER UPDATE OF name ON public.lines FOR EACH ROW
WHEN (OLD.name IS DISTINCT FROM NEW.name) EXECUTE FUNCTION public.wallet_on_route_rename();

-- save_line rewrites every station's order on each save; only a real rename counts.
DROP TRIGGER IF EXISTS trg_wallet_station_rename ON public.stations;
CREATE TRIGGER trg_wallet_station_rename
AFTER UPDATE OF name ON public.stations FOR EACH ROW
WHEN (OLD.name IS DISTINCT FROM NEW.name) EXECUTE FUNCTION public.wallet_on_route_rename();

DROP TRIGGER IF EXISTS trg_wallet_company_change ON public.companies;
CREATE TRIGGER trg_wallet_company_change
AFTER UPDATE OF name, logo_path, contact_phone, contact_label ON public.companies FOR EACH ROW
EXECUTE FUNCTION public.wallet_on_company_change();

-- ---------------------------------------------------------------------------
-- 7. Dashboard RPCs: a company admin for their own company, the super admin
--    for any company (same rule as lines and payment methods).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.wallet_admin_company(p_company_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid := CASE WHEN public.is_company_admin() THEN COALESCE(p_company_id, public.current_admin_company_id())
                         ELSE p_company_id END;
BEGIN
  IF v_company IS NULL OR NOT public.can_manage_line_company(v_company) THEN
    RAISE EXCEPTION 'لا يمكنك إدارة بطاقة المحفظة لهذه الشركة.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.companies WHERE id = v_company) THEN
    RAISE EXCEPTION 'الشركة غير موجودة.';
  END IF;
  RETURN v_company;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_wallet_card_settings(p_company_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id uuid := public.wallet_admin_company(p_company_id);
  v_company public.companies%ROWTYPE;
  v_theme public.wallet_card_settings%ROWTYPE;
BEGIN
  SELECT * INTO v_company FROM public.companies WHERE id = v_company_id;
  SELECT * INTO v_theme FROM public.wallet_card_settings WHERE company_id = v_company_id;
  RETURN jsonb_build_object(
    'company_id', v_company.id,
    'company_name', v_company.name,
    'logo_path', v_company.logo_path,
    'contact_phone', v_company.contact_phone,
    'contact_label', v_company.contact_label,
    'background_color', COALESCE(v_theme.background_color, '#00658D'),
    'foreground_color', COALESCE(v_theme.foreground_color, '#FFFFFF'),
    'label_color', COALESCE(v_theme.label_color, '#D6EEF9'),
    'card_title', v_theme.card_title,
    'banner_path', v_theme.banner_path,
    'revision', COALESCE(v_theme.revision, 0),
    'updated_at', v_theme.updated_at,
    'updated_by_name', (SELECT a.full_name FROM public.admins a WHERE a.id = v_theme.updated_by),
    'apple_cards', (SELECT count(*) FROM public.wallet_passes WHERE company_id = v_company_id AND platform = 'apple'),
    'google_cards', (SELECT count(*) FROM public.wallet_passes WHERE company_id = v_company_id AND platform = 'google'),
    'pending_cards', (SELECT count(*) FROM public.wallet_passes WHERE company_id = v_company_id AND dirty_at IS NOT NULL)
  );
END;
$$;

-- Saves the company's design AND identity in one step, then marks only that
-- company's installed cards for update.
CREATE OR REPLACE FUNCTION public.set_wallet_card_settings(
  p_company_id uuid,
  p_background_color text,
  p_foreground_color text,
  p_label_color text,
  p_card_title text DEFAULT NULL,
  p_banner_path text DEFAULT NULL,
  p_logo_path text DEFAULT NULL,
  p_contact_phone text DEFAULT NULL,
  p_contact_label text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id uuid := public.wallet_admin_company(p_company_id);
  v_background text := upper(btrim(COALESCE(p_background_color, '')));
  v_foreground text := upper(btrim(COALESCE(p_foreground_color, '')));
  v_label text := upper(btrim(COALESCE(p_label_color, '')));
  v_title text := NULLIF(btrim(COALESCE(p_card_title, '')), '');
  v_banner text := NULLIF(btrim(COALESCE(p_banner_path, '')), '');
  v_logo text := NULLIF(btrim(COALESCE(p_logo_path, '')), '');
  v_phone text := NULLIF(btrim(COALESCE(p_contact_phone, '')), '');
  v_contact_label text := NULLIF(btrim(COALESCE(p_contact_label, '')), '');
BEGIN
  IF v_background !~ '^#[0-9A-F]{6}$' OR v_foreground !~ '^#[0-9A-F]{6}$' OR v_label !~ '^#[0-9A-F]{6}$' THEN
    RAISE EXCEPTION 'اكتب اللون بصيغة HEX مثل #00897B.';
  END IF;
  IF char_length(v_title) > 40 THEN
    RAISE EXCEPTION 'عنوان البطاقة لا يزيد عن 40 حرفاً.';
  END IF;
  -- Artwork must live in this company's own folder.
  IF v_logo !~ ('^' || v_company_id::text || '/logo/[A-Za-z0-9_-]{1,64}$')
     OR v_banner !~ ('^' || v_company_id::text || '/banner/[A-Za-z0-9_-]{1,64}$') THEN
    RAISE EXCEPTION 'مسار الصورة غير صالح.';
  END IF;
  IF v_phone !~ '^[0-9+][0-9 ()+-]{4,24}$' THEN
    RAISE EXCEPTION 'رقم التواصل غير صالح.';
  END IF;
  IF char_length(v_contact_label) > 30 THEN
    RAISE EXCEPTION 'وصف رقم التواصل لا يزيد عن 30 حرفاً.';
  END IF;

  INSERT INTO public.wallet_card_settings AS w
    (company_id, background_color, foreground_color, label_color, card_title, banner_path, updated_by)
  VALUES (v_company_id, v_background, v_foreground, v_label, v_title, v_banner, auth.uid())
  ON CONFLICT (company_id) DO UPDATE SET
    background_color = EXCLUDED.background_color,
    foreground_color = EXCLUDED.foreground_color,
    label_color = EXCLUDED.label_color,
    card_title = EXCLUDED.card_title,
    banner_path = EXCLUDED.banner_path,
    revision = w.revision + 1,
    updated_at = now(),
    updated_by = auth.uid();

  -- Its own trigger marks the cards when the identity changed; the explicit
  -- call below covers a design-only change.
  UPDATE public.companies SET logo_path = v_logo, contact_phone = v_phone, contact_label = v_contact_label
  WHERE id = v_company_id;
  PERFORM public.wallet_touch_company(v_company_id);
  RETURN public.get_wallet_card_settings(v_company_id);
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_admin_company(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_wallet_card_settings(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_wallet_card_settings(uuid, text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_wallet_card_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_wallet_card_settings(uuid, text, text, text, text, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. Artwork: each company writes only inside its own folder
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Super admin manages wallet artwork" ON storage.objects;
DROP POLICY IF EXISTS "Company manages its wallet artwork" ON storage.objects;
CREATE POLICY "Company manages its wallet artwork" ON storage.objects FOR ALL TO authenticated
USING (bucket_id = 'wallet-assets' AND EXISTS (
  SELECT 1 FROM public.companies c
  WHERE c.id::text = (storage.foldername(objects.name))[1] AND public.can_manage_line_company(c.id)))
WITH CHECK (bucket_id = 'wallet-assets' AND EXISTS (
  SELECT 1 FROM public.companies c
  WHERE c.id::text = (storage.foldername(objects.name))[1] AND public.can_manage_line_company(c.id)));

-- Cards issued before this migration: record their company and queue them, so
-- they pick up the new layout the first time wallet-sync runs.
UPDATE public.wallet_passes p SET
  company_id = NULLIF(public.wallet_card_content(p.student_id) #>> '{company,id}', '')::uuid,
  dirty_at = COALESCE(p.dirty_at, now())
WHERE p.content_hash IS NULL;

COMMIT;
