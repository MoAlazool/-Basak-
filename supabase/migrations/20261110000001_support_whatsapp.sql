-- ==============================================================================
-- Migration: 20261110000001_support_whatsapp.sql
-- Run AFTER 20261109000001. Safe to re-run. Additive: one nullable column and
-- two new functions.
--
-- The platform's WhatsApp number for students who forgot their password: the
-- app's "enter the code" screen offers a button that opens a chat with it,
-- until codes are sent by SMS. Set by the platform admin on the dashboard;
-- empty hides the button.
--   * get_support_whatsapp(): open to everyone, signed in or not, because the
--     forgot-password screen comes before sign-in. It answers the number only.
--   * save_support_whatsapp(p_phone): the platform admin only.
-- Kept as WhatsApp wants it: country code first, digits only (201012345678).
-- ==============================================================================
BEGIN;

ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS support_whatsapp text;
ALTER TABLE public.app_settings DROP CONSTRAINT IF EXISTS app_settings_support_whatsapp_check;
ALTER TABLE public.app_settings ADD CONSTRAINT app_settings_support_whatsapp_check
  CHECK (support_whatsapp IS NULL OR support_whatsapp ~ '^[1-9][0-9]{7,14}$');

-- The number or null.
CREATE OR REPLACE FUNCTION public.get_support_whatsapp() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.support_whatsapp FROM public.app_settings s WHERE s.id
$$;
REVOKE ALL ON FUNCTION public.get_support_whatsapp() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_support_whatsapp() TO anon, authenticated, service_role;

-- Saves the number and answers it as stored. Takes it as people write it:
-- Arabic or Latin digits, spaces, +20 / 0020, or an Egyptian mobile written
-- locally (010… or 10…, which gets Egypt's code). Empty clears it.
CREATE OR REPLACE FUNCTION public.save_support_whatsapp(p_phone text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_digits text := regexp_replace(translate(COALESCE(p_phone, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '[^0-9]', '', 'g');
BEGIN
  IF public.is_super_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'رقم واتساب الدعم متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF v_digits LIKE '00%' THEN v_digits := substr(v_digits, 3); END IF;
  IF v_digits ~ '^01[0125][0-9]{8}$' THEN v_digits := '2' || v_digits; END IF;
  IF v_digits ~ '^1[0125][0-9]{8}$' THEN v_digits := '20' || v_digits; END IF;  -- the same without its 0
  IF btrim(COALESCE(p_phone, '')) = '' THEN
    v_digits := NULL;
  ELSIF v_digits !~ '^[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'اكتب رقم واتساب صحيحاً، مثل 01012345678.' USING ERRCODE = '23514';
  END IF;

  UPDATE public.app_settings SET support_whatsapp = v_digits, updated_at = now(), updated_by = auth.uid() WHERE id;
  RETURN v_digits;
END;
$$;
REVOKE ALL ON FUNCTION public.save_support_whatsapp(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_support_whatsapp(text) TO authenticated;

COMMIT;
