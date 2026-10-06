-- Student Wallet card (Apple Wallet / Google Wallet).
--
-- The card belongs to the STUDENT, not to a subscription: its serial number is
-- the student id and its barcode is students.qr_code_value, both permanent.
-- Whether a student may ride is still decided only by
-- supervisor_check_in_student() at scan time; nothing here touches that.
--
-- The card's look is ONE global theme (wallet_card_settings), edited by the
-- super admin from the dashboard. There is no per-student design.
-- Safe to re-run.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The single global theme
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_card_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  background_color text NOT NULL DEFAULT '#00658D' CHECK (background_color ~ '^#[0-9A-F]{6}$'),
  foreground_color text NOT NULL DEFAULT '#FFFFFF' CHECK (foreground_color ~ '^#[0-9A-F]{6}$'),
  label_color text NOT NULL DEFAULT '#D6EEF9' CHECK (label_color ~ '^#[0-9A-F]{6}$'),
  card_title text NOT NULL DEFAULT 'باصك | Basak' CHECK (char_length(btrim(card_title)) BETWEEN 1 AND 40),
  -- Folders in the public "wallet-assets" bucket (NULL = built-in Basak logo / no banner).
  logo_path text,
  banner_path text,
  -- Bumped on every save; a card whose synced_revision is lower still shows an older design.
  revision integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
INSERT INTO public.wallet_card_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.wallet_card_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_card_settings FROM anon, authenticated;  -- via the RPCs below
GRANT ALL ON public.wallet_card_settings TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Issued cards and Apple's update registrations
--    (Apple's model: devices, passes, and a many-to-many "registrations" link.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_passes (
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  platform text NOT NULL CHECK (platform IN ('apple', 'google')),
  -- Apple only: the pass's authenticationToken (shared secret for its web-service calls).
  auth_token text,
  -- Apple's "last-update tag": when the content of this card last changed.
  content_updated_at timestamptz NOT NULL DEFAULT now(),
  synced_revision integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (student_id, platform),
  CONSTRAINT wallet_passes_apple_token CHECK (platform <> 'apple' OR auth_token IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_wallet_passes_pending ON public.wallet_passes (synced_revision);

CREATE TABLE IF NOT EXISTS public.wallet_apple_devices (
  device_library_id text PRIMARY KEY,
  push_token text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.wallet_apple_registrations (
  device_library_id text NOT NULL REFERENCES public.wallet_apple_devices(device_library_id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_library_id, student_id)
);
CREATE INDEX IF NOT EXISTS idx_wallet_apple_registrations_student
  ON public.wallet_apple_registrations (student_id);

-- Only the Edge Functions (service role) touch these.
ALTER TABLE public.wallet_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_apple_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_apple_registrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_passes, public.wallet_apple_devices, public.wallet_apple_registrations
  FROM anon, authenticated;
GRANT ALL ON public.wallet_passes, public.wallet_apple_devices, public.wallet_apple_registrations
  TO service_role;

-- A device with no cards left is forgotten (Apple: "delete the device entry if
-- the registration table has no more entries for that device"). This also
-- covers registrations removed by a student-account deletion cascade.
CREATE OR REPLACE FUNCTION public.wallet_apple_drop_orphan_device()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.wallet_apple_devices d
  WHERE d.device_library_id = OLD.device_library_id
    AND NOT EXISTS (SELECT 1 FROM public.wallet_apple_registrations r
                    WHERE r.device_library_id = OLD.device_library_id);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_wallet_apple_drop_orphan_device ON public.wallet_apple_registrations;
CREATE TRIGGER trg_wallet_apple_drop_orphan_device
AFTER DELETE ON public.wallet_apple_registrations
FOR EACH ROW EXECUTE FUNCTION public.wallet_apple_drop_orphan_device();

-- Register a device for a card. Returns true when the registration is new
-- (HTTP 201) and false when it already existed (HTTP 200). The push token is a
-- property of the device, so it is refreshed for all of that device's cards.
CREATE OR REPLACE FUNCTION public.wallet_apple_register(
  p_device_library_id text, p_push_token text, p_student_id uuid
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_created boolean;
BEGIN
  IF coalesce(btrim(p_device_library_id), '') = '' OR coalesce(btrim(p_push_token), '') = '' THEN
    RAISE EXCEPTION 'invalid registration';
  END IF;
  INSERT INTO public.wallet_apple_devices (device_library_id, push_token)
  VALUES (p_device_library_id, p_push_token)
  ON CONFLICT (device_library_id)
  DO UPDATE SET push_token = EXCLUDED.push_token, updated_at = now();

  INSERT INTO public.wallet_apple_registrations (device_library_id, student_id)
  VALUES (p_device_library_id, p_student_id)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_created = ROW_COUNT;
  RETURN v_created;
END;
$$;

-- The cards on one device whose content changed after p_since (an opaque tag:
-- microseconds since the epoch, NULL = everything). Returns the new tag too.
CREATE OR REPLACE FUNCTION public.wallet_apple_updated_serials(
  p_device_library_id text, p_since bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH changed AS (
    SELECT p.student_id, (extract(epoch FROM p.content_updated_at) * 1000000)::bigint AS tag
    FROM public.wallet_apple_registrations r
    JOIN public.wallet_passes p ON p.student_id = r.student_id AND p.platform = 'apple'
    WHERE r.device_library_id = p_device_library_id
  )
  SELECT jsonb_build_object(
    'serialNumbers', coalesce(jsonb_agg(student_id::text ORDER BY tag), '[]'::jsonb),
    'lastUpdated', max(tag)::text
  )
  FROM changed
  WHERE p_since IS NULL OR tag > p_since
$$;

-- One page of cards that still show an older design, for the rollout after a
-- theme change. Keyset-paged so a card that keeps failing never blocks the rest.
CREATE OR REPLACE FUNCTION public.wallet_pending_passes(
  p_after_student uuid DEFAULT NULL, p_after_platform text DEFAULT NULL, p_limit integer DEFAULT 25
) RETURNS SETOF public.wallet_passes LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.*
  FROM public.wallet_passes p
  WHERE p.synced_revision < (SELECT revision FROM public.wallet_card_settings WHERE id)
    AND (p_after_student IS NULL OR (p.student_id, p.platform) > (p_after_student, coalesce(p_after_platform, '')))
  ORDER BY p.student_id, p.platform
  LIMIT greatest(1, least(coalesce(p_limit, 25), 100))
$$;

REVOKE ALL ON FUNCTION public.wallet_apple_drop_orphan_device() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_apple_register(text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_apple_updated_serials(text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_apple_register(text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_apple_updated_serials(text, bigint) TO service_role;
REVOKE ALL ON FUNCTION public.wallet_pending_passes(uuid, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_pending_passes(uuid, text, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Dashboard RPCs (super admin only: the design is global to every company)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_wallet_card_settings()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_settings public.wallet_card_settings%ROWTYPE;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تصميم بطاقة المحفظة متاح لمدير النظام فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_settings FROM public.wallet_card_settings WHERE id;
  RETURN jsonb_build_object(
    'background_color', v_settings.background_color,
    'foreground_color', v_settings.foreground_color,
    'label_color', v_settings.label_color,
    'card_title', v_settings.card_title,
    'logo_path', v_settings.logo_path,
    'banner_path', v_settings.banner_path,
    'revision', v_settings.revision,
    'updated_at', v_settings.updated_at,
    'updated_by_name', (SELECT a.full_name FROM public.admins a WHERE a.id = v_settings.updated_by),
    'apple_cards', (SELECT count(*) FROM public.wallet_passes WHERE platform = 'apple'),
    'google_cards', (SELECT count(*) FROM public.wallet_passes WHERE platform = 'google'),
    'pending_cards', (SELECT count(*) FROM public.wallet_passes WHERE synced_revision < v_settings.revision)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_wallet_card_settings(
  p_background_color text,
  p_foreground_color text,
  p_label_color text,
  p_card_title text,
  p_logo_path text DEFAULT NULL,
  p_banner_path text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_background text := upper(btrim(coalesce(p_background_color, '')));
  v_foreground text := upper(btrim(coalesce(p_foreground_color, '')));
  v_label text := upper(btrim(coalesce(p_label_color, '')));
  v_title text := btrim(coalesce(p_card_title, ''));
  v_logo text := nullif(btrim(coalesce(p_logo_path, '')), '');
  v_banner text := nullif(btrim(coalesce(p_banner_path, '')), '');
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تصميم بطاقة المحفظة متاح لمدير النظام فقط.' USING ERRCODE = '42501';
  END IF;
  IF v_background !~ '^#[0-9A-F]{6}$' OR v_foreground !~ '^#[0-9A-F]{6}$' OR v_label !~ '^#[0-9A-F]{6}$' THEN
    RAISE EXCEPTION 'اكتب اللون بصيغة HEX مثل #00897B.';
  END IF;
  IF char_length(v_title) NOT BETWEEN 1 AND 40 THEN
    RAISE EXCEPTION 'عنوان البطاقة مطلوب ولا يزيد عن 40 حرفاً.';
  END IF;
  -- Asset folders are written by the dashboard as "logo/<stamp>" / "banner/<stamp>".
  IF v_logo !~ '^logo/[A-Za-z0-9_-]{1,64}$' OR v_banner !~ '^banner/[A-Za-z0-9_-]{1,64}$' THEN
    RAISE EXCEPTION 'مسار الصورة غير صالح.';
  END IF;

  UPDATE public.wallet_card_settings SET
    background_color = v_background,
    foreground_color = v_foreground,
    label_color = v_label,
    card_title = v_title,
    logo_path = v_logo,
    banner_path = v_banner,
    revision = revision + 1,
    updated_at = now(),
    updated_by = auth.uid()
  WHERE id;
  RETURN public.get_wallet_card_settings();
END;
$$;

REVOKE ALL ON FUNCTION public.get_wallet_card_settings() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_wallet_card_settings(text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_wallet_card_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_wallet_card_settings(text, text, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Card artwork. Public because Google Wallet fetches the logo by URL; it
--    holds only the organisation's logo/banner, never student data.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('wallet-assets', 'wallet-assets', true, 2097152, ARRAY['image/png'])
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/png'];

DROP POLICY IF EXISTS "Super admin manages wallet artwork" ON storage.objects;
CREATE POLICY "Super admin manages wallet artwork" ON storage.objects FOR ALL TO authenticated
USING (bucket_id = 'wallet-assets' AND public.is_super_admin())
WITH CHECK (bucket_id = 'wallet-assets' AND public.is_super_admin());

COMMIT;
