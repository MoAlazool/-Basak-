-- What must not change when the tenancy migrations are applied.
SELECT json_build_object(
  'counts', (SELECT json_object_agg(t, n) FROM (
      SELECT c.relname AS t,
             (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM public.%I', c.relname), false, true, '')))[1]::text::int AS n
      FROM pg_class c
      WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
        AND c.relname IN ('admins', 'companies', 'lines', 'stations', 'line_trips', 'line_trip_stops', 'line_universities',
                          'supervisors', 'supervisor_lines', 'students', 'subscriptions', 'receipts', 'daily_ride_status',
                          'supervisor_scan_events', 'complaints', 'chat_messages', 'company_payment_methods',
                          'deleted_student_revenue', 'universities', 'wallet_card_settings')) x),
  'subscriptions', (SELECT json_agg(json_build_object(
      'id', s.id, 'student', s.student_id, 'line', s.line_id, 'company', l.company_id, 'status', s.status, 'type', s.type,
      'start', s.start_date, 'end', s.end_date, 'period', s.period_code, 'year', s.academic_year,
      'label', public.period_label(s), 'phase', public.period_phase(s), 'price', s.price, 'paid_at', s.paid_at) ORDER BY s.id)
    FROM public.subscriptions s JOIN public.lines l ON l.id = s.line_id),
  -- The wallet card of every student: a change here would push an update to their phone.
  'wallet_cards', (SELECT json_object_agg(st.id, public.wallet_card_content(st.id)) FROM public.students st),
  'receipts', (SELECT json_agg(json_build_object('id', r.id, 'status', r.status, 'amount', r.amount) ORDER BY r.id) FROM public.receipts r),
  'paid_revenue_by_company', (SELECT json_object_agg(company_id, total) FROM (
      SELECT l.company_id, sum(COALESCE((SELECT r.amount FROM public.receipts r
                                         WHERE r.subscription_id = s.id AND r.status = 'approved'
                                         ORDER BY r.reviewed_at DESC NULLS LAST LIMIT 1), s.price)) AS total
      FROM public.subscriptions s JOIN public.lines l ON l.id = s.line_id
      WHERE s.paid_at IS NOT NULL GROUP BY l.company_id) x)
);
