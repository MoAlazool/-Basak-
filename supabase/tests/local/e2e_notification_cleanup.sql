-- Test of 20261122000001_notification_cleanup (delete_my_notifications, the
-- inbox page without what was removed, notifications_purge).
-- Plain SQL, one transaction, rolled back: run it after the migration. Nothing
-- persists. The last statement lists every check; all must say ok = true.
--
-- Fixture (triggers off while it is written): company A, students s1 and s2.
-- Five notifications sent to both: an announcement now, one 6 days old, one 8
-- days old; a subscription notice 20 days old and one 31 days old. One
-- scheduled announcement, created 40 days ago, not sent yet.
BEGIN;

CREATE SCHEMA nc;
GRANT USAGE ON SCHEMA nc TO authenticated, anon;
CREATE TABLE nc.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE FUNCTION nc.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO nc.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION nc.login(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION nc.ids(p_page jsonb) RETURNS text[] LANGUAGE sql AS $$
  SELECT COALESCE(array_agg(right(i->>'id', 2) ORDER BY i->>'id'), '{}') FROM jsonb_array_elements(p_page->'items') i $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA nc TO authenticated, anon;
GRANT INSERT, SELECT ON nc.results TO authenticated;
GRANT USAGE ON SEQUENCE nc.results_n_seq TO authenticated;

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, email)
SELECT ('7e000000-0000-4000-8000-0000000000' || x)::uuid, 'nc-' || x || '@example.invalid' FROM unnest(ARRAY['51', '52']) x;
INSERT INTO public.companies (id, name, status, is_active) VALUES
  ('7e000000-0000-4000-8000-00000000c00a', 'اختبار المسح', 'active', true);
INSERT INTO public.students (id, phone, full_name, university, college)
SELECT ('7e000000-0000-4000-8000-0000000000' || x)::uuid, '0109996000' || right(x, 1), 'طالب ' || x, 'جامعة', 'كلية'
FROM unnest(ARRAY['51', '52']) x;

INSERT INTO public.notifications (id, company_id, sender_role, sender_name, audience, title, body, type, category, status, created_at, sent_at, scheduled_at)
SELECT ('7e000000-0000-4000-8000-0000000000' || x.id)::uuid, '7e000000-0000-4000-8000-00000000c00a', 'admin', 'الإدارة', 'كل طلاب الشركة',
       'عنوان ' || x.id, 'نص ' || x.id, x.type, split_part(x.type, '.', 1), x.status,
       now() - x.age, CASE WHEN x.status = 'sent' THEN now() - x.age END,
       CASE WHEN x.status = 'scheduled' THEN now() + interval '1 day' END
FROM (VALUES ('a0', 'announcement.admin', 'sent', interval '1 minute'),
             ('a6', 'announcement.admin', 'sent', interval '6 days'),
             ('a8', 'transport.delay', 'sent', interval '8 days'),
             ('b2', 'subscription.approved', 'sent', interval '20 days'),
             ('b3', 'subscription.expired', 'sent', interval '31 days'),
             ('c0', 'announcement.admin', 'scheduled', interval '40 days')) AS x(id, type, status, age);
INSERT INTO public.notification_recipients (notification_id, user_id, is_student)
SELECT n.id, u.id, true FROM public.notifications n, auth.users u
WHERE n.company_id = '7e000000-0000-4000-8000-00000000c00a' AND n.status = 'sent' AND u.email LIKE 'nc-%';

SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;

-- s1 removes one notification.
SELECT nc.login('7e000000-0000-4000-8000-000000000051');
SELECT nc.ok('before: all five are in the inbox, unread',
             nc.ids(p) = ARRAY['a0', 'a6', 'a8', 'b2', 'b3'] AND (p->>'unread')::int = 5, p::text)
FROM public.get_my_notifications_page() p;
SELECT nc.ok('removing one says one was removed',
             public.delete_my_notifications(ARRAY['7e000000-0000-4000-8000-0000000000a6']::uuid[]) = 1);
SELECT nc.ok('it is gone from the inbox and no longer counted unread',
             nc.ids(p) = ARRAY['a0', 'a8', 'b2', 'b3'] AND (p->>'unread')::int = 4, p::text)
FROM public.get_my_notifications_page() p;
SELECT nc.ok('nor is it among the unread ones', nc.ids(p) = ARRAY['a0', 'a8', 'b2', 'b3'], p::text)
FROM public.get_my_notifications_page(NULL, 30, true) p;
SELECT nc.ok('removing it again changes nothing',
             public.delete_my_notifications(ARRAY['7e000000-0000-4000-8000-0000000000a6']::uuid[]) = 0);
SELECT nc.ok('the user''s other phones are told',
             (SELECT count(*) = 1 FROM realtime.messages m
              WHERE m.topic = 'user:7e000000-0000-4000-8000-000000000051' AND m.payload->>'op' = 'HIDE'));

-- s2 still has everything; then removes all of theirs.
SELECT nc.login('7e000000-0000-4000-8000-000000000052');
SELECT nc.ok('another user''s inbox is untouched',
             nc.ids(p) = ARRAY['a0', 'a6', 'a8', 'b2', 'b3'] AND (p->>'unread')::int = 5, p::text)
FROM public.get_my_notifications_page() p;
SELECT nc.ok('a user cannot remove from someone else''s inbox: only their own copy goes',
             public.delete_my_notifications(ARRAY['7e000000-0000-4000-8000-0000000000a0']::uuid[]) = 1);
SELECT nc.ok('removing everything', public.delete_my_notifications() = 4);
SELECT nc.ok('an empty inbox, nothing unread',
             nc.ids(p) = '{}' AND (p->>'unread')::int = 0, p::text)
FROM public.get_my_notifications_page() p;

SELECT nc.login('7e000000-0000-4000-8000-000000000051');
SELECT nc.ok('the first user still has theirs', nc.ids(p) = ARRAY['a0', 'a8', 'b2', 'b3'], p::text)
FROM public.get_my_notifications_page() p;

-- Signed out: refused. The clean-up itself is not callable from the app.
RESET ROLE;
SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
DO $$ BEGIN
  PERFORM public.delete_my_notifications();
  PERFORM nc.ok('signed out: refused', false);
EXCEPTION WHEN others THEN PERFORM nc.ok('signed out: refused', true, SQLSTATE); END $$;
RESET ROLE;
SELECT nc.ok('the clean-up cannot be called by a signed-in user',
             NOT has_function_privilege('authenticated', 'public.notifications_purge()', 'EXECUTE'));

-- The nightly clean-up.
SELECT nc.ok('the clean-up deletes what is past its time', public.notifications_purge() >= 2);
SELECT nc.ok('announcements and bus messages older than 7 days are deleted, newer ones stay; subscription notices stay 30 days; a scheduled one is never touched',
             (SELECT array_agg(right(id::text, 2) ORDER BY id) = ARRAY['a0', 'a6', 'b2', 'c0']
              FROM public.notifications WHERE company_id = '7e000000-0000-4000-8000-00000000c00a'),
             (SELECT string_agg(right(id::text, 2), ',' ORDER BY id)
              FROM public.notifications WHERE company_id = '7e000000-0000-4000-8000-00000000c00a'));
SELECT nc.ok('their recipients went with them',
             (SELECT count(*) = 0 FROM public.notification_recipients
              WHERE notification_id IN ('7e000000-0000-4000-8000-0000000000a8', '7e000000-0000-4000-8000-0000000000b3')));

SELECT n, step, ok, detail FROM nc.results ORDER BY n;
ROLLBACK;
