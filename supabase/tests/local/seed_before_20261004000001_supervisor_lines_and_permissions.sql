-- Production-like data on the schema BEFORE the 2026-10-04 migrations, so the
-- backfills of those migrations are exercised. Local test database only.
-- Companies 1111.. (lines aaaa, bbbb) and 2222.. (line cccc) come from the seed migration.

INSERT INTO auth.users (id, email) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'super@basak.test'),
  ('a0000000-0000-0000-0000-000000000002', 'admin1@basak.test'),
  ('a0000000-0000-0000-0000-000000000003', 'admin2@basak.test'),
  ('b0000000-0000-0000-0000-000000000001', '01000000001@busak.app'),
  ('b0000000-0000-0000-0000-000000000002', '01000000002@busak.app'),
  ('b0000000-0000-0000-0000-000000000003', '01000000003@busak.app'),
  ('c0000000-0000-0000-0000-000000000001', '01100000001@busak.app'),
  ('c0000000-0000-0000-0000-000000000002', '01100000002@busak.app'),
  ('c0000000-0000-0000-0000-000000000003', '01100000003@busak.app');

INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'super@basak.test', 'Super', 'super_admin', NULL, NULL);
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  ('a0000000-0000-0000-0000-000000000002', 'admin1@basak.test', 'Admin One', 'company_admin', '11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000003', 'admin2@basak.test', 'Admin Two', 'company_admin', '22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000001');

-- S1: directly assigned to line aaaa. S2: no direct line (old fallback = whole company). S3: company 2.
INSERT INTO public.supervisors (id, phone, full_name, company_id, created_at) VALUES
  ('b0000000-0000-0000-0000-000000000001', '01000000001', 'Supervisor One', '11111111-1111-1111-1111-111111111111', now() - interval '10 days'),
  ('b0000000-0000-0000-0000-000000000002', '01000000002', 'Supervisor Two', '11111111-1111-1111-1111-111111111111', now() - interval '20 days'),
  ('b0000000-0000-0000-0000-000000000003', '01000000003', 'Supervisor Three', '22222222-2222-2222-2222-222222222222', now() - interval '5 days');
UPDATE public.lines SET supervisor_id = 'b0000000-0000-0000-0000-000000000001'
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

INSERT INTO public.students (id, phone, full_name, university) VALUES
  ('c0000000-0000-0000-0000-000000000001', '01100000001', 'Student One A B', 'جامعة المنصورة'),
  ('c0000000-0000-0000-0000-000000000002', '01100000002', 'Student Two A B', 'جامعة المنصورة'),
  ('c0000000-0000-0000-0000-000000000003', '01100000003', 'Student Three A B', 'جامعة المنصورة');

-- ST1: active termly approved recently under the old "+4 months" rule (line aaaa).
-- ST2: unpaid legacy termly request, no dates (line bbbb).
-- ST3: active yearly on company 2 (line cccc).
INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price, departure_time, return_time)
SELECT 'd0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', st.line_id, st.id, 'termly', 'active',
       public.cairo_today() - 5, public.cairo_today() - 5 + interval '4 months', 3500, st.departure_times[1], st.return_times[1]
FROM public.stations st WHERE st.line_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND st.order_index = 1;
INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, price, departure_time, return_time)
SELECT 'd0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', st.line_id, st.id, 'termly', 'pending_payment',
       3800, st.departure_times[1], st.return_times[1]
FROM public.stations st WHERE st.line_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' AND st.order_index = 1;
INSERT INTO public.subscriptions (id, student_id, line_id, station_id, type, status, start_date, end_date, price, departure_time, return_time)
SELECT 'd0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000003', st.line_id, st.id, 'yearly', 'active',
       public.cairo_today() - 20, public.cairo_today() - 20 + interval '1 year', 7500, st.departure_times[1], st.return_times[1]
FROM public.stations st WHERE st.line_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' AND st.order_index = 1;

-- Old rule allowed a departure AND a return check-in on the same day.
INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, subscription_id, line_id, ride_date, direction, result, scanned_at) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.cairo_today() - 1, 'departure', 'checked_in', now() - interval '1 day 8 hours'),
  ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', public.cairo_today() - 1, 'return', 'checked_in', now() - interval '1 day 1 hour');

-- A profile photo reference with no stored object (the dashboard's 400 on sign).
UPDATE public.students SET profile_image_url = 'c0000000-0000-0000-0000-000000000002/avatar.jpg'
WHERE id = 'c0000000-0000-0000-0000-000000000002';
INSERT INTO storage.objects (bucket_id, name, owner) VALUES
  ('student-avatars', 'c0000000-0000-0000-0000-000000000001/avatar.jpg', 'c0000000-0000-0000-0000-000000000001');
UPDATE public.students SET profile_image_url = 'c0000000-0000-0000-0000-000000000001/avatar.jpg'
WHERE id = 'c0000000-0000-0000-0000-000000000001';
