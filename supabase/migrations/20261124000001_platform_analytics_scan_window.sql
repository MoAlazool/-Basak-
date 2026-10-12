-- ==============================================================================
-- Migration: 20261124000001_platform_analytics_scan_window.sql
-- «تحليلات المنصة» (platform_analytics) took 13 s on the live capacity benchmark
-- (about 2,000 active students a term, 490,000 scan events): the boarded-per-day
-- figure joined supervisor_scan_events on `ride_date IN (the window's days)`,
-- which no index serves, so every scan ever made was read on each page open
-- (4.9 s of it on the Free compute). The scans are now read per company and only
-- for the window's dates, through idx_scan_events_company_date. Same answer;
-- only this one CTE changes. Safe to re-run.
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.platform_analytics(p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_grace constant int := 14;
  v_to date;
  v_lo date;
  v_prev_from date;
  v_prev_to date;
  v_subs int;
  v_subs_prev int;
  v_costs numeric;
  v_costs_prev numeric;
  v_active int;
  v_finance jsonb;
  v_companies jsonb;
  v_students jsonb;
  v_usage jsonb;
  v_insights jsonb;
  v_blank constant text[] := ARRAY['', '-', '--', '—', '.', '..', '?', '؟', 'n/a', 'na', 'none', 'null', 'لا يوجد', 'لا أعرف',
                                   'لا اعرف', 'غير محدد', 'غير محددة', 'غير معروف', 'غير معروفة', 'لم يحدد', 'لم تحدد'];
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'تحليلات المنصة متاحة لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from > p_to THEN
    RAISE EXCEPTION 'بداية الفترة بعد نهايتها.' USING ERRCODE = '22023';
  END IF;
  v_to := LEAST(COALESCE(p_to, v_today), v_today);
  v_lo := COALESCE(p_from, DATE '2000-01-01');
  IF p_from IS NOT NULL AND p_from <= v_to THEN
    v_prev_to := p_from - 1;
    v_prev_from := p_from - (v_to - p_from + 1);
  END IF;

  -- Platform subscribers on the period's last day (and the previous period's), students counted once.
  SELECT count(DISTINCT s.student_id) INTO v_subs FROM public.subscriptions s
  WHERE s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
    AND COALESCE(s.start_date, v_to) <= v_to AND COALESCE(s.end_date, v_to) >= v_to;
  IF v_prev_to IS NOT NULL THEN
    SELECT count(DISTINCT s.student_id) INTO v_subs_prev FROM public.subscriptions s
    WHERE s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
      AND COALESCE(s.start_date, v_prev_to) <= v_prev_to AND COALESCE(s.end_date, v_prev_to) >= v_prev_to;
    SELECT COALESCE(sum(e.amount), 0) INTO v_costs_prev FROM public.platform_expenses e
    WHERE e.month BETWEEN date_trunc('month', v_prev_from)::date AND v_prev_to;
  END IF;
  SELECT COALESCE(sum(e.amount), 0) INTO v_costs FROM public.platform_expenses e
  WHERE e.month BETWEEN date_trunc('month', v_lo)::date AND v_to;
  SELECT count(*) INTO v_active FROM public.companies c WHERE c.status = 'active';

  -- ----------------------------------------------------------------- finance
  WITH ch AS (SELECT * FROM public.platform_charges),
  co AS (SELECT id, name FROM public.companies),
  months AS (
    SELECT to_char(m, 'YYYY-MM') AS mo
    FROM generate_series(
      date_trunc('month', COALESCE(p_from, LEAST(
        (SELECT min(period_start) FROM ch), (SELECT min(month) FROM public.platform_expenses),
        (SELECT min((paid_at AT TIME ZONE 'Africa/Cairo')::date) FROM ch))))::date,
      date_trunc('month', v_to)::date, interval '1 month') m
  ),
  billed AS (SELECT to_char(period_start, 'YYYY-MM') AS mo, sum(amount) AS n FROM ch
             WHERE status <> 'waived' AND period_start BETWEEN v_lo AND v_to GROUP BY 1),
  collected AS (SELECT to_char(paid_at AT TIME ZONE 'Africa/Cairo', 'YYYY-MM') AS mo, sum(amount) AS n FROM ch
                WHERE status = 'paid' AND (paid_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to GROUP BY 1),
  costs AS (SELECT to_char(month, 'YYYY-MM') AS mo, sum(amount) AS n FROM public.platform_expenses
            WHERE month BETWEEN date_trunc('month', v_lo)::date AND v_to GROUP BY 1),
  overdue AS (
    SELECT ch.company_id, co.name, sum(ch.amount) AS amount, min(ch.period_start) AS oldest
    FROM ch JOIN co ON co.id = ch.company_id
    WHERE ch.status = 'due' AND ch.period_start + v_grace < v_today GROUP BY 1, 2
  ),
  totals AS (
    SELECT (SELECT COALESCE(sum(n), 0) FROM billed) AS billed, (SELECT COALESCE(sum(n), 0) FROM collected) AS collected
  )
  SELECT jsonb_build_object(
    'mrr', (SELECT COALESCE(round(sum(CASE p.cycle WHEN 'monthly' THEN p.fee_amount WHEN 'termly' THEN p.fee_amount / 4 ELSE p.fee_amount / 12 END), 2), 0)
            FROM public.company_plans p JOIN public.companies c ON c.id = p.company_id
            WHERE p.ends_on IS NULL AND p.starts_on <= v_today AND c.status <> 'archived'),
    'billed', t.billed,
    'collected', t.collected,
    'outstanding', (SELECT COALESCE(sum(amount), 0) FROM ch WHERE status = 'due' AND period_start <= v_today),
    'overdue', COALESCE((SELECT jsonb_agg(jsonb_build_object('company_id', o.company_id, 'name', o.name, 'amount', o.amount, 'oldest_due', o.oldest)
                                          ORDER BY o.oldest, o.amount DESC) FROM overdue o), '[]'::jsonb),
    'costs_total', v_costs,
    'costs_by_category', COALESCE((SELECT jsonb_agg(jsonb_build_object('category', category, 'amount', n) ORDER BY n DESC, category)
                                   FROM (SELECT category, sum(amount) AS n FROM public.platform_expenses
                                         WHERE month BETWEEN date_trunc('month', v_lo)::date AND v_to GROUP BY 1) x), '[]'::jsonb),
    'by_month', COALESCE((SELECT jsonb_agg(jsonb_build_object('month', m.mo, 'billed', COALESCE(b.n, 0), 'collected', COALESCE(k.n, 0),
                                                              'costs', COALESCE(x.n, 0), 'profit', COALESCE(k.n, 0) - COALESCE(x.n, 0)) ORDER BY m.mo)
                          FROM months m LEFT JOIN billed b ON b.mo = m.mo LEFT JOIN collected k ON k.mo = m.mo LEFT JOIN costs x ON x.mo = m.mo), '[]'::jsonb),
    'profit', t.collected - v_costs,
    'margin', CASE WHEN t.collected > 0 THEN round((t.collected - v_costs) / t.collected, 3) END,
    'cost_per_company', CASE WHEN v_active > 0 THEN round(v_costs / v_active, 2) END,
    'cost_per_student', CASE WHEN v_subs > 0 THEN round(v_costs / v_subs, 2) END,
    'cost_per_student_before', CASE WHEN v_subs_prev > 0 THEN round(v_costs_prev / v_subs_prev, 2) END,
    'subscribers', v_subs,
    'active_companies', v_active
  ) INTO v_finance FROM totals t;

  -- --------------------------------------------------------------- companies
  WITH mem AS (SELECT company_id, count(*) AS n FROM public.company_students WHERE status = 'active' GROUP BY 1),
  psubs AS (
    SELECT s.company_id, s.student_id, s.start_date, s.end_date FROM public.subscriptions s
    WHERE s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
      AND COALESCE(s.start_date, v_to) <= v_to AND COALESCE(s.end_date, v_lo) >= v_lo
  ),
  subs_now AS (
    SELECT company_id, count(DISTINCT student_id) AS n FROM psubs
    WHERE COALESCE(start_date, v_to) <= v_to AND COALESCE(end_date, v_to) >= v_to GROUP BY 1
  ),
  subs_prev AS (
    SELECT s.company_id, count(DISTINCT s.student_id) AS n FROM public.subscriptions s
    WHERE v_prev_to IS NOT NULL AND s.paid_at IS NOT NULL AND (s.status = 'active' OR (s.status = 'expired' AND s.end_date < v_today))
      AND COALESCE(s.start_date, v_prev_to) <= v_prev_to AND COALESCE(s.end_date, v_prev_to) >= v_prev_to
    GROUP BY 1
  ),
  ln AS (SELECT company_id, count(*) AS n, count(*) FILTER (WHERE is_active) AS a FROM public.lines GROUP BY 1),
  conf AS (
    SELECT d.company_id, d.ride_date AS d, count(*) AS n FROM public.daily_ride_status d
    WHERE d.is_riding AND d.ride_date BETWEEN v_lo AND v_to AND d.company_id IS NOT NULL GROUP BY 1, 2
  ),
  sub_groups AS (SELECT company_id, start_date, end_date, count(DISTINCT student_id) AS n FROM psubs GROUP BY 1, 2, 3),
  day_subs AS (
    SELECT c.company_id, c.d, sum(g.n) AS n FROM conf c
    JOIN sub_groups g ON g.company_id = c.company_id AND c.d BETWEEN COALESCE(g.start_date, c.d) AND COALESCE(g.end_date, c.d)
    GROUP BY 1, 2
  ),
  rides AS (
    SELECT c.company_id, count(*) AS days, sum(c.n) AS conf, sum(COALESCE(s.n, 0)) AS subs
    FROM conf c LEFT JOIN day_subs s ON s.company_id = c.company_id AND s.d = c.d GROUP BY 1
  ),
  rev AS (
    SELECT s.company_id, sum(COALESCE(a.amount, s.price)) AS amount
    FROM public.subscriptions s
    LEFT JOIN LATERAL (SELECT r.amount FROM public.receipts r WHERE r.subscription_id = s.id AND r.status = 'approved'
                       ORDER BY r.reviewed_at DESC NULLS LAST LIMIT 1) a ON true
    WHERE s.paid_at IS NOT NULL AND (s.paid_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to
    GROUP BY 1
  ),
  plan AS (SELECT company_id, fee_amount, cycle FROM public.company_plans WHERE ends_on IS NULL),
  dues AS (
    SELECT company_id, sum(amount) AS amount, COALESCE(sum(amount) FILTER (WHERE period_start + v_grace < v_today), 0) AS overdue
    FROM public.platform_charges WHERE status = 'due' AND period_start <= v_today GROUP BY 1
  ),
  seen AS (
    SELECT a.company_id, max(u.last_sign_in_at) AS at FROM public.admins a JOIN auth.users u ON u.id = a.id
    WHERE a.role = 'company_admin' AND a.company_id IS NOT NULL GROUP BY 1
  ),
  rv AS (
    SELECT r.company_id, count(*) AS n,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY GREATEST(extract(epoch FROM r.reviewed_at - r.created_at) / 3600.0, 0)) AS h
    FROM public.receipts r
    WHERE r.status IN ('approved', 'rejected') AND r.reviewed_at IS NOT NULL
      AND (r.reviewed_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to
    GROUP BY 1
  ),
  cr AS (
    SELECT c.id, c.name, c.status, c.created_at,
           COALESCE(m.n, 0) AS students, COALESCE(sn.n, 0) AS subscribers,
           CASE WHEN v_prev_to IS NOT NULL THEN COALESCE(sp.n, 0) END AS subscribers_before,
           COALESCE(l.n, 0) AS lines, COALESCE(l.a, 0) AS active_lines,
           COALESCE(r.days, 0) AS ride_days,
           CASE WHEN r.days > 0 THEN round(r.conf::numeric / r.days, 1) ELSE 0 END AS riders_avg,
           CASE WHEN r.subs > 0 THEN round(LEAST(r.conf::numeric / r.subs, 1), 3) END AS confirm_rate,
           COALESCE(rv2.amount, 0) AS company_revenue,
           p.fee_amount AS plan_fee, p.cycle AS plan_cycle,
           COALESCE(d.amount, 0) AS outstanding, COALESCE(d.overdue, 0) AS overdue,
           se.at AS last_admin_seen,
           round(q.h::numeric, 1) AS median_review_hours, COALESCE(q.n, 0) AS reviewed
    FROM public.companies c
    LEFT JOIN mem m ON m.company_id = c.id
    LEFT JOIN subs_now sn ON sn.company_id = c.id
    LEFT JOIN subs_prev sp ON sp.company_id = c.id
    LEFT JOIN ln l ON l.company_id = c.id
    LEFT JOIN rides r ON r.company_id = c.id
    LEFT JOIN rev rv2 ON rv2.company_id = c.id
    LEFT JOIN plan p ON p.company_id = c.id
    LEFT JOIN dues d ON d.company_id = c.id
    LEFT JOIN seen se ON se.company_id = c.id
    LEFT JOIN rv q ON q.company_id = c.id
  )
  SELECT jsonb_build_object(
    'counts', jsonb_build_object('total', count(*), 'active', count(*) FILTER (WHERE status = 'active'),
                                 'suspended', count(*) FILTER (WHERE status = 'suspended'), 'archived', count(*) FILTER (WHERE status = 'archived')),
    'list', COALESCE(jsonb_agg(jsonb_build_object(
      'id', id, 'name', name, 'status', status, 'created_at', created_at, 'students', students, 'subscribers', subscribers,
      'subscribers_before', subscribers_before, 'lines', lines, 'active_lines', active_lines, 'ride_days', ride_days,
      'riders_avg', riders_avg, 'confirm_rate', confirm_rate, 'company_revenue', company_revenue,
      'plan_fee', plan_fee, 'plan_cycle', plan_cycle, 'outstanding', outstanding, 'overdue', overdue,
      'last_admin_seen', last_admin_seen, 'median_review_hours', median_review_hours, 'reviewed', reviewed,
      'health', CASE WHEN status = 'active' THEN LEAST(100,
          CASE WHEN last_admin_seen > now() - interval '7 days' THEN 25 WHEN last_admin_seen > now() - interval '14 days' THEN 15
               WHEN last_admin_seen > now() - interval '30 days' THEN 5 ELSE 0 END
        + COALESCE(round(30 * confirm_rate), 0)
        + CASE WHEN overdue > 0 THEN 0 WHEN outstanding > 0 THEN 15 ELSE 25 END
        + CASE WHEN reviewed = 0 OR median_review_hours <= 24 THEN 20 WHEN median_review_hours <= 48 THEN 10 ELSE 0 END)::int END)
      ORDER BY status <> 'active', subscribers DESC, name), '[]'::jsonb)
  ) INTO v_companies FROM cr;

  -- ---------------------------------------------------------------- students
  WITH st AS (
    SELECT s.id, s.created_at, s.university_id,
           NULLIF(regexp_replace(btrim(COALESCE(s.college, '')), '\s+', ' ', 'g'), '') AS college,
           NULLIF(regexp_replace(btrim(COALESCE(s.specialisation, '')), '\s+', ' ', 'g'), '') AS spec
    FROM public.students s
  ),
  members AS (SELECT DISTINCT m.student_id, m.company_id FROM public.company_students m WHERE m.status = 'active'),
  col AS (SELECT college AS name, count(*) AS n FROM st WHERE lower(COALESCE(college, '')) <> ALL (v_blank) GROUP BY 1),
  spc AS (SELECT spec AS name, count(*) AS n FROM st WHERE lower(COALESCE(spec, '')) <> ALL (v_blank) GROUP BY 1),
  uni_students AS (SELECT university_id AS id, count(*) AS n FROM st GROUP BY 1),
  uni_companies AS (
    SELECT st.university_id AS id, count(DISTINCT mb.company_id) AS n
    FROM st JOIN members mb ON mb.student_id = st.id JOIN public.companies c ON c.id = mb.company_id AND c.status = 'active'
    GROUP BY 1
  ),
  uni_lines AS (
    SELECT x.university_id AS id, count(DISTINCT x.line_id) AS n
    FROM public.line_universities x JOIN public.lines l ON l.id = x.line_id AND l.is_active
    JOIN public.companies c ON c.id = l.company_id AND c.status = 'active'
    GROUP BY 1
  ),
  uni AS (
    SELECT u.id, u.name, COALESCE(s.n, 0) AS students, COALESCE(c.n, 0) AS companies, COALESCE(l.n, 0) AS lines
    FROM public.universities u
    LEFT JOIN uni_students s ON s.id = u.id LEFT JOIN uni_companies c ON c.id = u.id LEFT JOIN uni_lines l ON l.id = u.id
    WHERE u.is_active OR s.n > 0
    UNION ALL
    SELECT NULL, NULL, s.n, 0, 0 FROM uni_students s WHERE s.id IS NULL
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM st),
    'with_company', (SELECT count(DISTINCT student_id) FROM members),
    'without_company', (SELECT count(*) FROM st WHERE NOT EXISTS (SELECT 1 FROM members mb WHERE mb.student_id = st.id)),
    'subscribers', v_subs,
    'new_in_period', (SELECT count(*) FROM st WHERE (st.created_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to),
    'new_by_month', COALESCE((SELECT jsonb_agg(jsonb_build_object('month', mo, 'count', n) ORDER BY mo)
                              FROM (SELECT to_char(st.created_at AT TIME ZONE 'Africa/Cairo', 'YYYY-MM') AS mo, count(*) AS n FROM st
                                    WHERE (st.created_at AT TIME ZONE 'Africa/Cairo')::date BETWEEN v_lo AND v_to GROUP BY 1) x), '[]'::jsonb),
    'by_university', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'students', students, 'companies', companies, 'lines', lines)
                                                ORDER BY students DESC, name NULLS LAST) FROM uni), '[]'::jsonb),
    'by_college', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'count', n) ORDER BY n DESC, name)
                            FROM (SELECT name, n FROM col ORDER BY n DESC, name LIMIT 20) c1), '[]'::jsonb),
    'by_specialisation', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'count', n) ORDER BY n DESC, name)
                                   FROM (SELECT name, n FROM spc ORDER BY n DESC, name LIMIT 10) s1), '[]'::jsonb)
  ) INTO v_students;

  -- ------------------------------------------------------------------- usage
  WITH days AS (
    SELECT d.ride_date AS d, count(*) AS n FROM public.daily_ride_status d
    WHERE d.is_riding AND d.ride_date BETWEEN GREATEST(v_lo, v_to - 120) AND v_to
    GROUP BY 1 ORDER BY 1 DESC LIMIT 60
  ),
  -- Only the days of the window, read company by company through
  -- idx_scan_events_company_date; `ride_date IN (days)` read every scan ever made.
  board AS (
    SELECT e.ride_date AS d, count(DISTINCT e.student_id) AS n
    FROM public.companies c
    JOIN public.supervisor_scan_events e
      ON e.company_id = c.id AND e.ride_date BETWEEN GREATEST(v_lo, v_to - 120) AND v_to
    WHERE e.result = 'checked_in' AND e.ride_date IN (SELECT d FROM days) GROUP BY 1
  ),
  dev AS (SELECT platform, app_version FROM public.push_devices WHERE disabled_at IS NULL),
  outbox AS (
    SELECT count(*) FILTER (WHERE status = 'accepted') AS ok, count(*) FILTER (WHERE status = 'failed') AS bad
    FROM public.push_outbox WHERE updated_at > now() - interval '7 days' AND status IN ('accepted', 'failed')
  )
  SELECT jsonb_build_object(
    'daily', COALESCE((SELECT jsonb_agg(jsonb_build_object('date', d.d, 'confirmed', d.n, 'boarded', COALESCE(b.n, 0)) ORDER BY d.d)
                       FROM days d LEFT JOIN board b ON b.d = d.d), '[]'::jsonb),
    'devices', jsonb_build_object('ios', (SELECT count(*) FROM dev WHERE platform = 'ios'),
                                  'android', (SELECT count(*) FROM dev WHERE platform = 'android')),
    'app_versions', COALESCE((SELECT jsonb_agg(jsonb_build_object('platform', platform, 'version', version, 'devices', n)
                                               ORDER BY platform, CASE WHEN version ~ '^\d+(\.\d+){0,2}$' THEN public.app_version_parts(version) END DESC NULLS LAST, n DESC)
                              FROM (SELECT platform, COALESCE(NULLIF(btrim(app_version), ''), '?') AS version, count(*) AS n
                                    FROM dev GROUP BY 1, 2) x), '[]'::jsonb),
    'latest', (SELECT jsonb_object_agg(v.platform, v.latest_version) FROM public.app_versions v),
    'push_7d', (SELECT jsonb_build_object('accepted', ok, 'failed', bad,
                                          'failure_rate', CASE WHEN ok + bad > 0 THEN round(bad::numeric / (ok + bad), 3) END) FROM outbox)
  ) INTO v_usage;

  -- ---------------------------------------------------------------- insights
  -- Rule-based, from the numbers above; at most three cards per rule, 'act' first.
  WITH co AS (SELECT x FROM jsonb_array_elements(v_companies->'list') x),
  ver AS (
    SELECT d.platform, v.latest_version AS latest, count(*) AS total,
           count(*) FILTER (WHERE public.app_version_parts(d.app_version) < public.app_version_parts(v.latest_version)) AS old
    FROM public.push_devices d JOIN public.app_versions v ON v.platform = d.platform
    WHERE d.disabled_at IS NULL AND NULLIF(btrim(d.app_version), '') IS NOT NULL AND d.app_version ~ '^\d+(\.\d+){0,2}$'
    GROUP BY 1, 2
  ),
  cps AS (
    SELECT (v_finance->>'cost_per_student')::numeric AS now_v, (v_finance->>'cost_per_student_before')::numeric AS before_v
  ),
  cand(key, severity, weight, data) AS (
    SELECT 'company_overdue', 'act', (o->>'amount')::numeric,
           jsonb_build_object('company_id', o->'company_id', 'name', o->'name', 'amount', o->'amount', 'oldest_due', o->'oldest_due',
                              'days', v_today - (o->>'oldest_due')::date)
    FROM jsonb_array_elements(v_finance->'overdue') o
    UNION ALL
    SELECT 'no_plan', 'act', count(*)::numeric,
           jsonb_build_object('count', count(*), 'companies', jsonb_agg(jsonb_build_object('id', x->'id', 'name', x->'name') ORDER BY x->>'name'))
    FROM co WHERE x->>'status' = 'active' AND x->'plan_fee' = 'null'::jsonb
    HAVING count(*) > 0
    UNION ALL
    SELECT 'unprofitable', 'act', v_costs - (v_finance->>'collected')::numeric,
           jsonb_build_object('costs', v_costs, 'collected', v_finance->'collected', 'loss', v_costs - (v_finance->>'collected')::numeric)
    WHERE v_costs > 0 AND v_costs > (v_finance->>'collected')::numeric
    UNION ALL
    SELECT 'company_inactive', 'watch',
           COALESCE(v_today - ((x->>'last_admin_seen')::timestamptz AT TIME ZONE 'Africa/Cairo')::date, 9999)::numeric,
           jsonb_build_object('company_id', x->'id', 'name', x->'name', 'last_seen', x->'last_admin_seen',
                              'days', v_today - ((x->>'last_admin_seen')::timestamptz AT TIME ZONE 'Africa/Cairo')::date)
    FROM co WHERE x->>'status' = 'active'
      AND (x->'last_admin_seen' = 'null'::jsonb OR (x->>'last_admin_seen')::timestamptz < now() - interval '14 days')
      -- A company created in the last two weeks has not had the time.
      AND (x->>'created_at')::timestamptz < now() - interval '14 days'
    UNION ALL
    SELECT 'company_declining', 'watch', ((x->>'subscribers_before')::numeric - (x->>'subscribers')::numeric),
           jsonb_build_object('company_id', x->'id', 'name', x->'name', 'now', x->'subscribers', 'before', x->'subscribers_before',
                              'pct', round(100 * (1 - (x->>'subscribers')::numeric / NULLIF((x->>'subscribers_before')::numeric, 0))))
    FROM co WHERE x->>'status' = 'active' AND x->'subscribers_before' <> 'null'::jsonb
      AND (x->>'subscribers_before')::int >= 10 AND (x->>'subscribers')::numeric <= 0.8 * (x->>'subscribers_before')::numeric
    UNION ALL
    SELECT 'slow_reviews', 'watch', (x->>'median_review_hours')::numeric,
           jsonb_build_object('company_id', x->'id', 'name', x->'name', 'median_hours', x->'median_review_hours', 'reviewed', x->'reviewed')
    FROM co WHERE x->>'status' = 'active' AND (x->>'reviewed')::int >= 5 AND (x->>'median_review_hours')::numeric > 24
    UNION ALL
    SELECT 'old_app_versions', 'watch', round(100.0 * old / NULLIF(total, 0)),
           jsonb_build_object('platform', platform, 'latest', latest, 'old', old, 'total', total, 'pct', round(100.0 * old / NULLIF(total, 0)))
    FROM ver WHERE total >= 5 AND old >= 0.25 * total
    UNION ALL
    SELECT 'cost_per_student_rising', 'watch', round(100 * (now_v / NULLIF(before_v, 0) - 1)),
           jsonb_build_object('now', now_v, 'before', before_v, 'pct', round(100 * (now_v / NULLIF(before_v, 0) - 1)))
    FROM cps WHERE now_v IS NOT NULL AND before_v > 0 AND now_v >= 1.1 * before_v
    UNION ALL
    SELECT 'university_opportunity', 'good', (u->>'students')::numeric,
           jsonb_build_object('university_id', u->'id', 'name', u->'name', 'students', u->'students', 'lines', u->'lines', 'companies', u->'companies')
    FROM jsonb_array_elements(v_students->'by_university') u
    WHERE u->'id' <> 'null'::jsonb AND (u->>'students')::int >= 20 AND (u->>'lines')::int <= 1
  ),
  ranked AS (
    SELECT c.*, row_number() OVER (PARTITION BY c.key ORDER BY c.weight DESC NULLS LAST) AS k,
           CASE c.severity WHEN 'act' THEN 0 WHEN 'watch' THEN 1 ELSE 2 END AS sev
    FROM cand c
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('key', key, 'severity', severity, 'data', data) ORDER BY sev, key, weight DESC NULLS LAST), '[]'::jsonb)
  INTO v_insights FROM ranked WHERE k <= 3;

  RETURN jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', v_to, 'previous_from', v_prev_from, 'previous_to', v_prev_to),
    'finance', v_finance,
    'companies', v_companies,
    'students', v_students,
    'usage', v_usage,
    'insights', v_insights
  );
END;
$$;
REVOKE ALL ON FUNCTION public.platform_analytics(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_analytics(date, date) TO authenticated;
