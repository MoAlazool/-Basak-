-- The line decides what it sells. Each option of a line (first, second, both,
-- summer, daily) is switched on or off in the line wizard alone; the company's
-- switches in «مواعيد الاشتراك» (company_terms.is_on_sale,
-- companies.annual_subscription_enabled, companies.daily_subscription_enabled)
-- are now only what a new line starts with.
--
-- What still applies above the line: the platform's switches (app_settings),
-- the company being active, and the terms' dates (sale season, paying ahead).
--
--  * daily_subscription_enabled(company): the platform sells daily and one of
--    the company's lines has a daily price.
--  * annual_subscription_enabled(company): the platform sells «both» and one of
--    the company's lines sells it.
--  * company_sale_periods(company): a term is sold when one of the company's
--    lines sells it (switched on, with a price). The season clock follows.
--  * line_sale_options_for: the line's own reason (not offered, no price) comes
--    before the company-wide one.
--  * sync_line_prices_from_line: a new line's «both» starts from the company's
--    switch, not from what other lines sell.
--
-- The catalog and the subscription triggers are unchanged: they already ask the
-- functions above and the line's own switch and price. The other functions are
-- the live definitions with only the lines described changed; CREATE OR REPLACE
-- keeps their grants.

BEGIN;

CREATE OR REPLACE FUNCTION public.daily_subscription_enabled(p_company_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- The platform sells daily, and (for a company) one of its lines has a daily price.
  SELECT COALESCE((SELECT daily_subscription_enabled FROM public.app_settings WHERE id), false)
     AND (p_company_id IS NULL OR EXISTS (
       SELECT 1 FROM public.lines l WHERE l.company_id = p_company_id AND l.price_daily > 0))
$function$;

CREATE OR REPLACE FUNCTION public.annual_subscription_enabled(p_company_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- The platform sells «both», and (for a company) one of its lines sells it.
  SELECT COALESCE((SELECT annual_subscription_enabled FROM public.app_settings WHERE id), false)
     AND (p_company_id IS NULL OR EXISTS (
       SELECT 1 FROM public.line_period_prices pr
       WHERE pr.company_id = p_company_id AND pr.option = 'both' AND pr.is_enabled AND pr.price > 0))
$function$;

CREATE OR REPLACE FUNCTION public.company_sale_periods(p_company_id uuid, p_on date DEFAULT NULL::date)
 RETURNS TABLE(option text, academic_year integer, name text, label text, subscription_type text, start_date date, end_date date, phase text, available boolean, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  d date := COALESCE(p_on, public.cairo_today());
  y int := extract(year FROM COALESCE(p_on, public.cairo_today()))::int;
  v_company_ok boolean := p_company_id IS NULL OR EXISTS (
    SELECT 1 FROM public.companies c WHERE c.id = p_company_id AND c.is_active AND c.status = 'active');
  v_advance boolean := p_company_id IS NULL OR COALESCE(
    (SELECT c.advance_subscription_enabled FROM public.companies c WHERE c.id = p_company_id), false);
  v_both boolean := public.annual_subscription_enabled(p_company_id);
BEGIN
  RETURN QUERY
  WITH all_p AS (
    SELECT * FROM public.company_periods(p_company_id, y - 1)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, y)
    UNION ALL SELECT * FROM public.company_periods(p_company_id, y + 1)
  ),
  sale AS (
    -- A company sells a term when one of its lines does (switched on, with a
    -- price); its own on/off is only what a new line starts with. No company:
    -- the platform's defaults.
    SELECT t.code, EXISTS (SELECT 1 FROM public.line_period_prices pr
                           WHERE pr.company_id = p_company_id AND pr.option = t.code AND pr.is_enabled AND pr.price > 0) AS is_on_sale
    FROM public.academic_terms t WHERE p_company_id IS NOT NULL
    UNION ALL
    SELECT t.code, t.is_on_sale FROM public.academic_terms t WHERE p_company_id IS NULL
  ),
  terms AS (
    SELECT a.*, COALESCE((SELECT s.is_on_sale FROM sale s WHERE s.code = a.period_code), false) AS sells
    FROM all_p a WHERE a.subscription_type = 'termly'
  ),
  clock AS (
    -- Only periods the company sells count as "running" or "next".
    SELECT EXISTS (SELECT 1 FROM terms t WHERE t.sells AND t.start_date <= d AND t.end_date >= d) AS in_term,
           (SELECT min(t.start_date) FROM terms t WHERE t.sells AND t.start_date > d) AS next_start
  ),
  cand AS (
    (SELECT DISTINCT ON (t.period_code) t.period_code, t.academic_year, t.name, t.label, t.subscription_type,
            t.start_date, t.end_date, t.sort_order, t.sells
     FROM terms t WHERE t.end_date >= d ORDER BY t.period_code, t.start_date)
    UNION ALL
    (SELECT a.period_code, a.academic_year, a.name, a.label, a.subscription_type, a.start_date, a.end_date, a.sort_order,
            v_both AND (p_company_id IS NOT NULL
                        OR COALESCE((SELECT bool_and(s.is_on_sale) FROM sale s WHERE s.code IN ('first', 'second')), false))
     FROM all_p a
     WHERE a.period_code = 'both'
       AND (SELECT f.end_date FROM terms f WHERE f.period_code = 'first' AND f.academic_year = a.academic_year) >= d
     ORDER BY a.start_date LIMIT 1)
  ),
  judged AS (
    SELECT c.*, CASE
        WHEN NOT v_company_ok THEN 'company_inactive'
        WHEN NOT c.sells THEN 'company_not_selling'
        WHEN c.start_date <= d THEN NULL
        WHEN c.start_date = k.next_start AND (v_advance OR NOT k.in_term) THEN NULL
        WHEN c.start_date = k.next_start THEN 'advance_off'
        ELSE 'not_in_season' END AS why
    FROM cand c CROSS JOIN clock k
  )
  SELECT j.period_code, j.academic_year, j.name, j.label, j.subscription_type, j.start_date, j.end_date,
         CASE WHEN j.start_date <= d THEN 'current' ELSE 'upcoming' END, j.why IS NULL, j.why
  FROM judged j
  ORDER BY j.start_date, j.sort_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.line_sale_options_for(p_line_id uuid, p_on date, p_student_id uuid)
 RETURNS TABLE(option text, academic_year integer, name text, label text, subscription_type text, start_date date, end_date date, phase text, price numeric, available boolean, reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p.option, p.academic_year, p.name, p.label, p.subscription_type, p.start_date, p.end_date, p.phase,
         pr.price, w.why IS NULL, w.why
  FROM public.lines l
  CROSS JOIN LATERAL public.company_sale_periods(l.company_id, p_on) p
  LEFT JOIN public.line_period_prices pr ON pr.line_id = l.id AND pr.option = p.option
  CROSS JOIN LATERAL (SELECT CASE
      WHEN p.reason = 'company_inactive' THEN p.reason
      WHEN NOT l.is_active THEN 'line_inactive'
      WHEN NOT COALESCE(pr.is_enabled, false) THEN 'line_not_offering'
      WHEN COALESCE(pr.price, 0) <= 0 THEN 'no_price'
      WHEN p.reason = 'company_not_selling' THEN p.reason
      WHEN p.reason IS NOT NULL THEN p.reason
      WHEN p_student_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.subscriptions s
        WHERE s.student_id = p_student_id AND s.status IN ('pending_payment', 'pending_review', 'active')
          AND (s.end_date IS NULL OR s.end_date >= COALESCE(p_on, public.cairo_today()))
          AND daterange(s.start_date, s.end_date, '[]') && daterange(p.start_date, p.end_date, '[]')) THEN 'overlap'
    END AS why) w
  WHERE l.id = p_line_id
  ORDER BY p.start_date, p.subscription_type
$function$;

CREATE OR REPLACE FUNCTION public.sync_line_prices_from_line()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.line_period_prices (line_id, company_id, option, price, is_enabled)
    SELECT NEW.id, NEW.company_id, o.option,
           CASE o.option WHEN 'both' THEN NEW.price_yearly ELSE NEW.price_termly END,
           CASE o.option WHEN 'both' THEN public.annual_subscription_enabled(NULL)
                                          AND COALESCE((SELECT c.annual_subscription_enabled FROM public.companies c WHERE c.id = NEW.company_id), false)
                         WHEN 'summer' THEN false ELSE true END
    FROM (VALUES ('first'), ('second'), ('both'), ('summer')) o(option)
    ON CONFLICT (line_id, option) DO NOTHING;
  ELSIF pg_trigger_depth() = 1 THEN
    -- An older dashboard saved the line: carry its two prices over.
    IF NEW.price_termly IS DISTINCT FROM OLD.price_termly THEN
      UPDATE public.line_period_prices SET price = NEW.price_termly, updated_at = now()
      WHERE line_id = NEW.id AND option IN ('first', 'second');
    END IF;
    IF NEW.price_yearly IS DISTINCT FROM OLD.price_yearly THEN
      UPDATE public.line_period_prices SET price = NEW.price_yearly, updated_at = now()
      WHERE line_id = NEW.id AND option = 'both';
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;

COMMIT;
