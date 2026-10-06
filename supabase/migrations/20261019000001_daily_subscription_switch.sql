-- ==============================================================================
-- Migration: 20261019000001_daily_subscription_switch.sql
-- Run AFTER 20261018000001. Safe to re-run.
--
-- The daily (cash) subscription can now be switched off like the annual one:
-- platform-wide by the Super Admin and per company by that company; it is
-- offered only when both are on. When off, the app hides the daily option,
-- the dashboard locks the daily price, and no daily subscription can be created.
-- get_subscription_switches() returns both switches in one call.
-- ==============================================================================
BEGIN;

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS daily_subscription_enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS daily_subscription_enabled boolean NOT NULL DEFAULT true;

-- Effective switch: global AND company (NULL company = global only).
CREATE OR REPLACE FUNCTION public.daily_subscription_enabled(p_company_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT daily_subscription_enabled FROM public.app_settings WHERE id), false)
     AND (p_company_id IS NULL OR COALESCE(
       (SELECT c.daily_subscription_enabled FROM public.companies c WHERE c.id = p_company_id), false))
$$;
REVOKE ALL ON FUNCTION public.daily_subscription_enabled(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.daily_subscription_enabled(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_daily_subscription(p_enabled boolean, p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_enabled IS NULL THEN RAISE EXCEPTION 'قيمة غير صالحة.'; END IF;
  IF p_company_id IS NULL THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'الإعداد العام متاح لمدير النظام فقط.' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_settings SET daily_subscription_enabled = p_enabled, updated_at = now(), updated_by = auth.uid() WHERE id;
  ELSE
    IF NOT public.can_manage_company(p_company_id) THEN
      RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
    END IF;
    UPDATE public.companies SET daily_subscription_enabled = p_enabled WHERE id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.'; END IF;
  END IF;
  RETURN jsonb_build_object('global', public.daily_subscription_enabled(NULL),
    'company_id', p_company_id,
    'effective', public.daily_subscription_enabled(p_company_id));
END;
$$;
REVOKE ALL ON FUNCTION public.set_daily_subscription(boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_daily_subscription(boolean, uuid) TO authenticated;

-- Annual and daily switches of a company (or of the platform when NULL).
CREATE OR REPLACE FUNCTION public.get_subscription_switches(p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'annual_global', public.annual_subscription_enabled(NULL),
    'annual_company', (SELECT c.annual_subscription_enabled FROM public.companies c WHERE c.id = p_company_id),
    'annual_effective', public.annual_subscription_enabled(p_company_id),
    'daily_global', public.daily_subscription_enabled(NULL),
    'daily_company', (SELECT c.daily_subscription_enabled FROM public.companies c WHERE c.id = p_company_id),
    'daily_effective', public.daily_subscription_enabled(p_company_id))
$$;
REVOKE ALL ON FUNCTION public.get_subscription_switches(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_switches(uuid) TO authenticated;

-- No new daily subscription while it is switched off (same rule as yearly).
CREATE OR REPLACE FUNCTION public.guard_daily_subscription() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.type = 'daily' AND (TG_OP = 'INSERT' OR OLD.type IS DISTINCT FROM 'daily')
     AND NOT public.daily_subscription_enabled((SELECT l.company_id FROM public.lines l WHERE l.id = NEW.line_id)) THEN
    RAISE EXCEPTION 'الاشتراك اليومي غير متاح حالياً.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_daily_subscription() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_daily_subscription ON public.subscriptions;
CREATE TRIGGER trg_guard_daily_subscription BEFORE INSERT OR UPDATE OF type ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.guard_daily_subscription();

COMMIT;
