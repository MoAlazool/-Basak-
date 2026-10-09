-- ==============================================================================
-- Migration: 20261106000001_app_versions.sql
-- Run AFTER 20261105000001. Safe to re-run. Additive: one new table and three
-- new functions.
--
-- What the app needs to know about its own releases, one row per platform:
-- the oldest version still allowed in (below it the app asks for an update
-- before anything else), the newest version in the store (below it the app
-- offers the update once), up to three lines of what is new, and the store link.
--   * get_app_version(platform): open to everyone, signed in or not, because
--     the update screen comes before sign-in. It answers that one row only.
--   * save_app_version(...): the platform admin only.
-- The table itself is readable by the platform admin alone and written by no
-- one directly. Both rows start at 0.0.0, which asks nobody to update.
-- ==============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.app_versions (
  platform text PRIMARY KEY CHECK (platform IN ('android', 'ios')),
  min_version text NOT NULL DEFAULT '0.0.0' CHECK (min_version ~ '^\d{1,4}(\.\d{1,4}){0,2}$'),
  latest_version text NOT NULL DEFAULT '0.0.0' CHECK (latest_version ~ '^\d{1,4}(\.\d{1,4}){0,2}$'),
  whats_new text[] NOT NULL DEFAULT '{}' CHECK (cardinality(whats_new) <= 3),
  store_url text CHECK (store_url IS NULL OR (store_url ~ '^https://' AND length(store_url) <= 300)),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
INSERT INTO public.app_versions (platform) VALUES ('android'), ('ios') ON CONFLICT (platform) DO NOTHING;

ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_versions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.app_versions TO authenticated;  -- rows: the platform admin only; writes: save_app_version()
DROP POLICY IF EXISTS app_versions_platform_read ON public.app_versions;
CREATE POLICY app_versions_platform_read ON public.app_versions FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin()));

-- '2.5' → {2,5,0}: versions compare number by number, not as text ('2.10' is after '2.9').
CREATE OR REPLACE FUNCTION public.app_version_parts(p_version text) RETURNS integer[]
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT ARRAY[COALESCE(NULLIF(split_part(p_version, '.', 1), '')::integer, 0),
               COALESCE(NULLIF(split_part(p_version, '.', 2), '')::integer, 0),
               COALESCE(NULLIF(split_part(p_version, '.', 3), '')::integer, 0)]
$$;
REVOKE ALL ON FUNCTION public.app_version_parts(text) FROM PUBLIC, anon, authenticated;

-- {"platform", "min_version", "latest_version", "whats_new": ["…"], "store_url"},
-- or null for a platform that has no row.
CREATE OR REPLACE FUNCTION public.get_app_version(p_platform text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'platform', v.platform, 'min_version', v.min_version, 'latest_version', v.latest_version,
    'whats_new', to_jsonb(v.whats_new), 'store_url', v.store_url)
  FROM public.app_versions v
  WHERE v.platform = lower(btrim(COALESCE(p_platform, '')))
$$;
REVOKE ALL ON FUNCTION public.get_app_version(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_version(text) TO anon, authenticated, service_role;

-- Saves one platform's row and answers it as get_app_version does. Empty
-- "what's new" lines are dropped; an empty store link clears it.
CREATE OR REPLACE FUNCTION public.save_app_version(
  p_platform text, p_min_version text, p_latest_version text, p_whats_new text[] DEFAULT '{}', p_store_url text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_platform text := lower(btrim(COALESCE(p_platform, '')));
  v_min text := btrim(COALESCE(p_min_version, ''));
  v_latest text := btrim(COALESCE(p_latest_version, ''));
  v_url text := NULLIF(btrim(COALESCE(p_store_url, '')), '');
  v_lines text[];
BEGIN
  IF public.is_super_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'إعدادات إصدار التطبيق متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF v_platform NOT IN ('android', 'ios') THEN
    RAISE EXCEPTION 'المنصة غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  IF v_min !~ '^\d{1,4}(\.\d{1,4}){0,2}$' OR v_latest !~ '^\d{1,4}(\.\d{1,4}){0,2}$' THEN
    RAISE EXCEPTION 'اكتب رقم الإصدار بالأرقام والنقاط فقط، مثل 2.5.0.' USING ERRCODE = '23514';
  END IF;
  IF public.app_version_parts(v_min) > public.app_version_parts(v_latest) THEN
    RAISE EXCEPTION 'أقل إصدار مسموح لا يمكن أن يكون أحدث من آخر إصدار.' USING ERRCODE = '23514';
  END IF;
  SELECT COALESCE(array_agg(btrim(x.line) ORDER BY x.n), '{}') INTO v_lines
  FROM unnest(COALESCE(p_whats_new, '{}'::text[])) WITH ORDINALITY AS x(line, n)
  WHERE btrim(COALESCE(x.line, '')) <> '';
  IF cardinality(v_lines) > 3 THEN
    RAISE EXCEPTION 'ثلاثة أسطر على الأكثر في «ما الجديد».' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_lines) l WHERE length(l) > 120) THEN
    RAISE EXCEPTION 'سطر «ما الجديد» طويل جداً (120 حرفاً على الأكثر).' USING ERRCODE = '23514';
  END IF;
  IF v_url IS NOT NULL AND (v_url !~ '^https://' OR length(v_url) > 300) THEN
    RAISE EXCEPTION 'رابط المتجر يجب أن يبدأ بـ https://' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.app_versions (platform, min_version, latest_version, whats_new, store_url, updated_at, updated_by)
  VALUES (v_platform, v_min, v_latest, v_lines, v_url, now(), auth.uid())
  ON CONFLICT (platform) DO UPDATE
    SET min_version = EXCLUDED.min_version, latest_version = EXCLUDED.latest_version, whats_new = EXCLUDED.whats_new,
        store_url = EXCLUDED.store_url, updated_at = EXCLUDED.updated_at, updated_by = EXCLUDED.updated_by;
  RETURN public.get_app_version(v_platform);
END;
$$;
REVOKE ALL ON FUNCTION public.save_app_version(text, text, text, text[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_app_version(text, text, text, text[], text) TO authenticated;

COMMIT;
