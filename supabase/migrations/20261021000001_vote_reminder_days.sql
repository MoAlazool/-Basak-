-- ==============================================================================
-- Migration: 20261021000001_vote_reminder_days.sql
-- Run AFTER 20261020000001. Safe to re-run.
--
-- Ride days without reminders: weekdays (e.g. Friday) and dates (official
-- holidays). They belong to the vote settings: the platform's, or a company's
-- own (a company overrides all its vote settings or none). Weekdays are ISO
-- (1 = Monday ... 7 = Sunday, as Dart's DateTime.weekday). A day is the RIDE
-- day: Friday off = no reminders for Friday's ride (sent on Thursday evening).
-- Voting itself stays open; only the app's reminders skip these days.
-- ==============================================================================
BEGIN;

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS vote_reminder_off_weekdays integer[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS vote_reminder_off_dates date[] NOT NULL DEFAULT '{}';
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS vote_reminder_off_weekdays integer[],
  ADD COLUMN IF NOT EXISTS vote_reminder_off_dates date[];

-- Companies that already have their own settings start with no days off.
UPDATE public.companies SET vote_reminder_off_weekdays = '{}', vote_reminder_off_dates = '{}'
WHERE vote_opens_at IS NOT NULL AND vote_reminder_off_weekdays IS NULL;

ALTER TABLE public.app_settings DROP CONSTRAINT IF EXISTS app_settings_vote_days_check;
ALTER TABLE public.app_settings ADD CONSTRAINT app_settings_vote_days_check CHECK (
  vote_reminder_off_weekdays <@ ARRAY[1, 2, 3, 4, 5, 6, 7]
  AND cardinality(vote_reminder_off_dates) <= 366);
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_vote_check;
ALTER TABLE public.companies ADD CONSTRAINT companies_vote_check CHECK (
  (vote_opens_at IS NULL AND vote_closes_at IS NULL AND vote_reminder_minutes IS NULL
   AND vote_reminder_off_weekdays IS NULL AND vote_reminder_off_dates IS NULL)
  OR (vote_opens_at IS NOT NULL AND vote_closes_at IS NOT NULL AND vote_reminder_minutes IS NOT NULL
      AND vote_reminder_off_weekdays IS NOT NULL AND vote_reminder_off_dates IS NOT NULL
      AND vote_opens_at <> vote_closes_at
      AND (vote_reminder_minutes = 0 OR vote_reminder_minutes BETWEEN 15 AND 1440)
      AND vote_reminder_off_weekdays <@ ARRAY[1, 2, 3, 4, 5, 6, 7]
      AND cardinality(vote_reminder_off_dates) <= 366));

-- The days off in force for a company (the platform's when it has none).
CREATE OR REPLACE FUNCTION public.vote_reminder_days(p_company_id uuid DEFAULT NULL)
RETURNS TABLE (off_weekdays integer[], off_dates date[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN c.vote_opens_at IS NOT NULL THEN c.vote_reminder_off_weekdays ELSE s.vote_reminder_off_weekdays END,
         CASE WHEN c.vote_opens_at IS NOT NULL THEN c.vote_reminder_off_dates ELSE s.vote_reminder_off_dates END
  FROM public.app_settings s
  LEFT JOIN public.companies c ON c.id = p_company_id
  WHERE s.id
$$;
REVOKE ALL ON FUNCTION public.vote_reminder_days(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.vote_reminder_days(uuid) TO authenticated, service_role;

-- Past dates are of no use to anyone.
CREATE OR REPLACE FUNCTION public.upcoming_dates(p_dates date[]) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(d ORDER BY d), '[]'::jsonb)
  FROM (SELECT DISTINCT d FROM unnest(p_dates) d WHERE d >= public.cairo_today()) x
$$;
REVOKE ALL ON FUNCTION public.upcoming_dates(date[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upcoming_dates(date[]) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_vote_settings(p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'company_id', p_company_id,
    'opens_at', left(v.opens_at::text, 5),
    'closes_at', left(v.closes_at::text, 5),
    'reminder_minutes', v.reminder_minutes,
    'off_weekdays', to_jsonb(d.off_weekdays),
    'off_dates', public.upcoming_dates(d.off_dates),
    'window_text', public.vote_window_text(p_company_id),
    -- The company has its own settings (otherwise it follows the platform).
    'custom', EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company_id AND c.vote_opens_at IS NOT NULL),
    'platform', (SELECT jsonb_build_object(
        'opens_at', left(s.vote_opens_at::text, 5),
        'closes_at', left(s.vote_closes_at::text, 5),
        'reminder_minutes', s.vote_reminder_minutes,
        'off_weekdays', to_jsonb(s.vote_reminder_off_weekdays),
        'off_dates', public.upcoming_dates(s.vote_reminder_off_dates))
      FROM public.app_settings s WHERE s.id),
    'can_edit_platform', public.is_super_admin())
  FROM public.vote_settings(p_company_id) v, public.vote_reminder_days(p_company_id) d
$$;

-- p_off_weekdays / p_off_dates NULL = keep the days off in force. For a
-- company, NULL times and reminders (all three) return it to the platform's.
DROP FUNCTION IF EXISTS public.set_vote_settings(uuid, time, time, integer);
CREATE OR REPLACE FUNCTION public.set_vote_settings(
  p_company_id uuid, p_opens_at time, p_closes_at time, p_reminder_minutes integer,
  p_off_weekdays integer[] DEFAULT NULL, p_off_dates date[] DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_opens time := left(p_opens_at::text, 5)::time;   -- whole minutes
  v_closes time := left(p_closes_at::text, 5)::time;
  v_days record;
  v_weekdays integer[];
  v_dates date[];
BEGIN
  IF p_company_id IS NULL THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'الإعداد العام متاح لمدير النظام فقط.' USING ERRCODE = '42501';
    END IF;
  ELSIF public.can_manage_company(p_company_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
  END IF;

  IF p_company_id IS NOT NULL AND p_opens_at IS NULL AND p_closes_at IS NULL AND p_reminder_minutes IS NULL THEN
    UPDATE public.companies SET vote_opens_at = NULL, vote_closes_at = NULL, vote_reminder_minutes = NULL,
      vote_reminder_off_weekdays = NULL, vote_reminder_off_dates = NULL
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

  SELECT * INTO v_days FROM public.vote_reminder_days(p_company_id);
  IF p_off_weekdays IS NOT NULL AND NOT (p_off_weekdays <@ ARRAY[1, 2, 3, 4, 5, 6, 7]) THEN
    RAISE EXCEPTION 'يوم أسبوع غير صالح.';
  END IF;
  SELECT COALESCE(array_agg(DISTINCT w ORDER BY w), '{}') INTO v_weekdays
  FROM unnest(COALESCE(p_off_weekdays, v_days.off_weekdays)) w;
  -- Only upcoming holidays are kept.
  SELECT COALESCE(array_agg(DISTINCT d ORDER BY d), '{}') INTO v_dates
  FROM unnest(COALESCE(p_off_dates, v_days.off_dates)) d WHERE d >= public.cairo_today();
  IF cardinality(v_dates) > 366 THEN
    RAISE EXCEPTION 'عدد أيام الإجازات كبير جداً.';
  END IF;

  IF p_company_id IS NULL THEN
    UPDATE public.app_settings SET vote_opens_at = v_opens, vote_closes_at = v_closes,
      vote_reminder_minutes = p_reminder_minutes, vote_reminder_off_weekdays = v_weekdays,
      vote_reminder_off_dates = v_dates, updated_at = now(), updated_by = auth.uid()
    WHERE id;
  ELSE
    UPDATE public.companies SET vote_opens_at = v_opens, vote_closes_at = v_closes,
      vote_reminder_minutes = p_reminder_minutes, vote_reminder_off_weekdays = v_weekdays,
      vote_reminder_off_dates = v_dates
    WHERE id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.'; END IF;
  END IF;
  RETURN public.get_vote_settings(p_company_id);
END;
$$;
REVOKE ALL ON FUNCTION public.set_vote_settings(uuid, time, time, integer, integer[], date[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_vote_settings(uuid, time, time, integer, integer[], date[]) TO authenticated;

COMMIT;
