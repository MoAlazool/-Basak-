-- Invariants that must hold once the tenancy migrations are in.
DO $$
DECLARE r record; n bigint;
BEGIN
  SELECT count(*) INTO n FROM (SELECT DISTINCT l.company_id, s.student_id
                               FROM public.subscriptions s JOIN public.lines l ON l.id = s.line_id) x
  WHERE NOT EXISTS (SELECT 1 FROM public.company_students m
                    WHERE m.company_id = x.company_id AND m.student_id = x.student_id);
  IF n > 0 THEN RAISE EXCEPTION '% subscribed student(s) have no membership', n; END IF;

  FOR r IN SELECT c.table_name FROM information_schema.columns c
           JOIN information_schema.tables t USING (table_schema, table_name)
           WHERE c.table_schema = 'public' AND c.column_name = 'company_id' AND t.table_type = 'BASE TABLE'
             AND c.table_name NOT IN ('admins', 'complaints', 'wallet_passes', 'password_admin_resets', 'report_resets',
                                      'daily_ride_status', 'deleted_student_revenue')
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE company_id IS NULL', r.table_name) INTO n;
    IF n > 0 THEN RAISE EXCEPTION '% row(s) in % have no company', n, r.table_name; END IF;
  END LOOP;

  SELECT count(*) INTO n FROM public.daily_ride_status d
  WHERE d.company_id IS NULL AND EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.student_id = d.student_id);
  IF n > 0 THEN RAISE EXCEPTION '% ride vote(s) of subscribed students have no company', n; END IF;

  -- A child never points at another company's parent.
  SELECT (SELECT count(*) FROM public.stations x JOIN public.lines l ON l.id = x.line_id WHERE x.company_id <> l.company_id)
       + (SELECT count(*) FROM public.line_trips x JOIN public.lines l ON l.id = x.line_id WHERE x.company_id <> l.company_id)
       + (SELECT count(*) FROM public.line_trip_stops x JOIN public.line_trips t ON t.id = x.trip_id WHERE x.company_id <> t.company_id)
       + (SELECT count(*) FROM public.supervisor_lines x JOIN public.lines l ON l.id = x.line_id WHERE x.company_id <> l.company_id)
       + (SELECT count(*) FROM public.subscriptions x JOIN public.lines l ON l.id = x.line_id WHERE x.company_id <> l.company_id)
       + (SELECT count(*) FROM public.receipts x JOIN public.subscriptions s ON s.id = x.subscription_id WHERE x.company_id <> s.company_id)
  INTO n;
  IF n > 0 THEN RAISE EXCEPTION '% row(s) disagree with their parent about the company', n; END IF;
END;
$$;
SELECT 'verify: memberships=' || (SELECT count(*) FROM public.company_students)
    || ' rides_with_company=' || (SELECT count(*) FROM public.daily_ride_status WHERE company_id IS NOT NULL)
    || '/' || (SELECT count(*) FROM public.daily_ride_status)
    || ' scans_with_company=' || (SELECT count(*) FROM public.supervisor_scan_events WHERE company_id IS NOT NULL)
    || '/' || (SELECT count(*) FROM public.supervisor_scan_events);
