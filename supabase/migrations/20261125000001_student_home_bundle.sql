-- ==============================================================================
-- Migration: 20261125000001_student_home_bundle.sql
-- Run AFTER 20261124000001. Safe to re-run. Additive: one new function; nothing
-- existing is changed or removed.
--
-- Opening the student app (and bringing it back to the foreground) asked the
-- server ten-odd separate questions: the student's row, their subscriptions,
-- the current one, the vote settings, the week's votes, the inbox, the
-- invitations, the offers, the line's supervisors, the recap releases, the
-- receipts and the boarded rides. Each was one request through the API, and on
-- a small instance it is the number of requests, not the queries, that runs
-- out first (docs/audit/2026-10-CAPACITY.md). This answers all of them in one.
--
-- Every part is the same answer the app's own request gets, read the same way:
--   * table reads are SECURITY INVOKER, so row level security decides exactly
--     what the student may see, as it does for the API;
--   * the subscription is built with the app's select (SupabaseSubscriptionGateway)
--     and the same filters and order;
--   * everything else calls the very function the app calls.
-- The app uses an answer only for the read it stands for and asks on its own
-- for anything missing, so an older app, or a database without this function,
-- works as before. (supabase/tests/local/student_home_parity.mjs compares every
-- part with what the API answers for the separate requests.)
--
-- p_today: the phone's date, as the app filters the current subscription.
-- p_ride_from / p_ride_to: the days of votes the home screen reads (none when null).
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_student_home(
  p_today date,
  p_ride_from date DEFAULT NULL,
  p_ride_to date DEFAULT NULL,
  p_inbox_limit integer DEFAULT 30
) RETURNS json
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  WITH me AS (
    SELECT auth.uid() AS id
  ),
  -- The student's subscriptions, each as SupabaseSubscriptionGateway._select reads it.
  -- The row's own columns keep the select's order; embedded rows are jsonb, as
  -- the API builds them (same keys, same order).
  subs AS (
    SELECT x.status, x.start_date, x.end_date, x.created_at, x.id, x.company_id,
      json_build_object(
        'id', x.id, 'student_id', x.student_id, 'line_id', x.line_id, 'company_id', x.company_id,
        'station_id', x.station_id, 'type', x.type, 'status', x.status, 'start_date', x.start_date,
        'end_date', x.end_date, 'price', x.price, 'created_at', x.created_at,
        'departure_time', x.departure_time, 'return_time', x.return_time, 'period_code', x.period_code,
        'academic_year', x.academic_year, 'period_label', public.period_label(x),
        'period_phase', public.period_phase(x),
        'lines', (
          SELECT jsonb_build_object(
            'name', l.name,
            'companies', (SELECT jsonb_build_object('id', c.id, 'name', c.name, 'logo_path', c.logo_path,
                                                   'emblem_path', c.emblem_path)
                          FROM public.companies c WHERE c.id = l.company_id),
            'supervisors', (SELECT jsonb_build_object('full_name', sp.full_name, 'phone', sp.phone,
                                                     'profile_image_url', sp.profile_image_url)
                            FROM public.supervisors sp WHERE sp.id = l.supervisor_id),
            'line_trips', (SELECT COALESCE(jsonb_agg(jsonb_build_object('direction', t.direction,
                                                    'is_active', t.is_active, 'start_time', t.start_time)), '[]'::jsonb)
                           FROM public.line_trips t WHERE t.line_id = l.id))
          FROM public.lines l WHERE l.id = x.line_id),
        'student', (SELECT jsonb_build_object('university', st.university)
                    FROM public.students st WHERE st.id = x.student_id),
        'stations', (
          SELECT jsonb_build_object(
            'name', s.name, 'departure_times', s.departure_times, 'return_times', s.return_times,
            'line_trip_stops', (
              SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'stop_time', ts.stop_time,
                       'line_trips', (SELECT jsonb_build_object('direction', t.direction, 'is_active', t.is_active,
                                                               'start_time', t.start_time)
                                      FROM public.line_trips t WHERE t.id = ts.trip_id))), '[]'::jsonb)
              FROM public.line_trip_stops ts WHERE ts.station_id = s.id))
          FROM public.stations s WHERE s.id = x.station_id),
        'departure_trip', (
          SELECT jsonb_build_object('label', t.label, 'start_time', t.start_time,
                                   'universities', (SELECT jsonb_build_object('name', u.name)
                                                    FROM public.universities u WHERE u.id = t.university_id))
          FROM public.line_trips t WHERE t.id = x.departure_trip_id),
        'return_trip', (SELECT jsonb_build_object('start_time', t.start_time)
                        FROM public.line_trips t WHERE t.id = x.return_trip_id)
      ) AS j
    FROM public.subscriptions x, me
    WHERE x.student_id = me.id
  ),
  -- SubscriptionGateway.currentSubscription: the earliest one still to come or running.
  cur AS (
    SELECT s.id, s.company_id, s.j FROM subs s
    WHERE s.status IN ('pending_payment', 'pending_review', 'active', 'rejected')
      AND (s.end_date IS NULL OR s.end_date >= p_today)
    ORDER BY s.start_date ASC, s.created_at DESC
    LIMIT 1
  )
  SELECT json_build_object(
    'v', 1,
    'profile', (SELECT row_to_json(st) FROM public.students st, me WHERE st.id = me.id),
    'subscriptions', (SELECT COALESCE(json_agg(s.j ORDER BY s.start_date DESC NULLS LAST, s.created_at DESC), '[]'::json)
                      FROM subs s),
    'current', (SELECT cur.j FROM cur),
    'vote_company', (SELECT cur.company_id FROM cur),
    'vote_settings', public.get_vote_settings((SELECT cur.company_id FROM cur)),
    'ride_days', CASE WHEN p_ride_from IS NOT NULL AND p_ride_to IS NOT NULL THEN (
        SELECT COALESCE(json_agg(json_build_object('ride_date', d.ride_date, 'is_riding', d.is_riding,
                                                   'departure_time', d.departure_time, 'return_time', d.return_time,
                                                   'is_returning', d.is_returning)), '[]'::json)
        FROM public.daily_ride_status d, me
        WHERE d.student_id = me.id AND d.ride_date >= p_ride_from AND d.ride_date <= p_ride_to) END,
    'receipts', (SELECT COALESCE(json_agg(json_build_object(
                          'id', r.id, 'subscription_id', r.subscription_id, 'image_url', r.image_url,
                          'status', r.status, 'rejection_reason', r.rejection_reason,
                          'attempt_number', r.attempt_number, 'reviewed_by', r.reviewed_by,
                          'created_at', r.created_at, 'reviewed_at', r.reviewed_at,
                          'payment_method_id', r.payment_method_id) ORDER BY r.attempt_number DESC), '[]'::json)
                 FROM public.receipts r WHERE r.subscription_id = (SELECT cur.id FROM cur)),
    'receipts_of', (SELECT cur.id FROM cur),
    'inbox', public.get_my_notifications_page(NULL, p_inbox_limit, false),
    'invites', public.get_my_invites(),
    'offers', public.get_my_offers(),
    'line_supervisors', public.get_my_line_supervisors(),
    'recap_releases', (SELECT COALESCE(json_agg(json_build_object('academic_year', rr.academic_year,
                                                'period_code', rr.period_code, 'published_at', rr.published_at,
                                                'unpublished_at', rr.unpublished_at)), '[]'::json)
                       FROM public.term_recap_releases rr),
    'boarded_rides', public.get_my_boarded_rides_count()
  )
  FROM me
  WHERE me.id IS NOT NULL
$$;

REVOKE ALL ON FUNCTION public.get_student_home(date, date, date, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_student_home(date, date, date, integer) TO authenticated;

COMMIT;
