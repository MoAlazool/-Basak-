-- Test of 20261123000001_offers (merchants, offers, coupons, audiences, the
-- platform's numbers). Plain SQL, one transaction, rolled back: run it after
-- the migration. Nothing persists. The last statement lists every check; all
-- must say ok = true.
--
-- Fixture (triggers off while it is written): company A (active, in one
-- governorate) with line LA; universities U1, U2.
--   s1  U1, الهندسة, «مدني», running subscription on LA; said he would ride on
--       10 days and was scanned on all 10.
--   s2  U1, طب الأسنان, running subscription; said 10 days, scanned on 2.
--   s3  U2, الهندسة, a member of A with no subscription.
--   s4  U1, الهندسة, running subscription, has hidden offers.
-- A platform admin and a company admin of A.
BEGIN;

CREATE SCHEMA ot;
GRANT USAGE ON SCHEMA ot TO authenticated, anon;
CREATE TABLE ot.results (n serial PRIMARY KEY, step text, ok boolean, detail text);
CREATE FUNCTION ot.ok(p_step text, p_ok boolean, p_detail text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO ot.results(step, ok, detail) VALUES (p_step, COALESCE(p_ok, false), p_detail) $$;
CREATE FUNCTION ot.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN others THEN RETURN SQLSTATE || ' ' || SQLERRM; END $$;
CREATE TABLE ot.kept (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION ot.keep(p_k text, p_v jsonb) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
  INSERT INTO ot.kept VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $$;
CREATE FUNCTION ot.got(p_k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT v FROM ot.kept WHERE k = p_k $$;
CREATE FUNCTION ot.login(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true) $$;
-- The last two characters of each offer id a student sees.
CREATE FUNCTION ot.mine() RETURNS text[] LANGUAGE sql AS $$
  SELECT COALESCE(array_agg(right(o->>'id', 2) ORDER BY right(o->>'id', 2)), '{}')
  FROM jsonb_array_elements(public.get_my_offers()->'offers') o
  -- This fixture's offers only: the database may hold others.
  WHERE o->>'id' LIKE '7d000000-%' $$;
-- A live offer of the fixture's merchant with this audience.
CREATE FUNCTION ot.offer(p_tail text, p_audience jsonb, p_more jsonb DEFAULT '{}') RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid := ('7d000000-0000-4000-8000-0000000000' || p_tail)::uuid;
BEGIN
  PERFORM public.platform_save_offer(jsonb_build_object('id', v_id, 'merchant_id', '7d000000-0000-4000-8000-00000000e001',
    'title', 'عرض ' || p_tail, 'kind', 'percent', 'value_label', '20%', 'audience', p_audience) || p_more);
  PERFORM public.platform_set_offer_status(v_id, 'live');
END $$;
-- Read as the owner: the tables are closed to clients.
CREATE FUNCTION ot.pin_set(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT pin_hash IS NOT NULL AND pin_hash <> '4821' FROM public.offers WHERE id = p_id $$;
CREATE FUNCTION ot.special_notices() RETURNS TABLE (user_id uuid, body text, data jsonb) LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT r.user_id, n.body, n.data FROM public.notifications n
  JOIN public.notification_recipients r ON r.notification_id = n.id WHERE n.type = 'offer.special' $$;
CREATE FUNCTION ot.starts_later(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT starts_at > now() + interval '20 hours' FROM public.offers WHERE id = p_id $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ot TO authenticated, anon;
GRANT INSERT, SELECT, UPDATE ON ot.results, ot.kept TO authenticated;
GRANT USAGE ON SEQUENCE ot.results_n_seq TO authenticated;

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (id, email)
SELECT ('7d000000-0000-4000-8000-0000000000' || x)::uuid, 'ot-' || x || '@example.invalid'
FROM unnest(ARRAY['a5', 'aa', '51', '52', '53', '54']) x;
INSERT INTO public.companies (id, name, status, is_active) VALUES
  ('7d000000-0000-4000-8000-00000000c00a', 'اختبار العروض أ', 'active', true);
INSERT INTO public.company_governorates (company_id, governorate_code)
SELECT '7d000000-0000-4000-8000-00000000c00a', code FROM public.governorates ORDER BY sort_order LIMIT 1;
INSERT INTO public.admins (id, email, full_name, role, company_id, created_by_admin_id) VALUES
  ('7d000000-0000-4000-8000-0000000000a5', 'ot-a5@example.invalid', 'مدير المنصة', 'super_admin', NULL, NULL),
  ('7d000000-0000-4000-8000-0000000000aa', 'ot-aa@example.invalid', 'مدير أ', 'company_admin', '7d000000-0000-4000-8000-00000000c00a', '7d000000-0000-4000-8000-0000000000a5');
INSERT INTO public.universities (id, name, city, is_active) VALUES
  ('7d000000-0000-4000-8000-0000000000f1', 'جامعة اختبار العروض 1', 'دمياط', true),
  ('7d000000-0000-4000-8000-0000000000f2', 'جامعة اختبار العروض 2', 'دمياط', true);
INSERT INTO public.lines (id, company_id, name, origin_name, destination_university_id, price_termly, price_yearly, price_daily, is_active) VALUES
  ('7d000000-0000-4000-8000-00000000a001', '7d000000-0000-4000-8000-00000000c00a', 'خط العروض', 'البداية', '7d000000-0000-4000-8000-0000000000f1', 3500, 6500, 0, true);
INSERT INTO public.stations (id, line_id, name, order_index, company_id, is_active) VALUES
  ('7d000000-0000-4000-8000-00000000b001', '7d000000-0000-4000-8000-00000000a001', 'محطة العروض', 0, '7d000000-0000-4000-8000-00000000c00a', true);

INSERT INTO public.students (id, phone, full_name, university, college, university_id, specialisation, offers_hidden) VALUES
  ('7d000000-0000-4000-8000-000000000051', '01099950001', 'طالب ١', 'جامعة اختبار العروض 1', 'الهندسة', '7d000000-0000-4000-8000-0000000000f1', 'مدني', false),
  ('7d000000-0000-4000-8000-000000000052', '01099950002', 'طالب ٢', 'جامعة اختبار العروض 1', 'طب الأسنان', '7d000000-0000-4000-8000-0000000000f1', NULL, false),
  ('7d000000-0000-4000-8000-000000000053', '01099950003', 'طالب ٣', 'جامعة اختبار العروض 2', 'الهندسة', '7d000000-0000-4000-8000-0000000000f2', NULL, false),
  ('7d000000-0000-4000-8000-000000000054', '01099950004', 'طالب ٤', 'جامعة اختبار العروض 1', 'الهندسة', '7d000000-0000-4000-8000-0000000000f1', NULL, true);
INSERT INTO public.company_students (company_id, student_id, status)
SELECT '7d000000-0000-4000-8000-00000000c00a', ('7d000000-0000-4000-8000-0000000000' || x)::uuid, 'active' FROM unnest(ARRAY['51', '52', '53', '54']) x;
INSERT INTO public.subscriptions (id, student_id, company_id, line_id, station_id, type, status, start_date, end_date, price, created_at)
SELECT ('7d000000-0000-4000-8000-0000000005' || x)::uuid, ('7d000000-0000-4000-8000-0000000000' || x)::uuid,
       '7d000000-0000-4000-8000-00000000c00a', '7d000000-0000-4000-8000-00000000a001', '7d000000-0000-4000-8000-00000000b001',
       'termly', 'active', public.cairo_today() - 40, public.cairo_today() + 60, 3500, now() - interval '40 days'
FROM unnest(ARRAY['51', '52', '54']) x;

-- s1 and s2 said they would ride on the last 10 days; s1 was scanned on all, s2 on 2.
INSERT INTO public.daily_ride_status (student_id, ride_date, is_riding, company_id, subscription_id)
SELECT ('7d000000-0000-4000-8000-0000000000' || x)::uuid, public.cairo_today() - d, true,
       '7d000000-0000-4000-8000-00000000c00a', ('7d000000-0000-4000-8000-0000000005' || x)::uuid
FROM unnest(ARRAY['51', '52']) x, generate_series(1, 10) d;
INSERT INTO public.supervisor_scan_events (student_id, subscription_id, line_id, station_id, ride_date, direction, result, company_id)
SELECT ('7d000000-0000-4000-8000-0000000000' || x.s)::uuid, ('7d000000-0000-4000-8000-0000000005' || x.s)::uuid,
       '7d000000-0000-4000-8000-00000000a001', '7d000000-0000-4000-8000-00000000b001', public.cairo_today() - d, 'departure',
       'checked_in', '7d000000-0000-4000-8000-00000000c00a'
FROM (VALUES ('51', 10), ('52', 2)) AS x(s, days), generate_series(1, 10) d WHERE d <= x.days;

SET LOCAL session_replication_role = origin;
SET LOCAL ROLE authenticated;

-- ============================ The platform sets up ============================
SELECT ot.login('7d000000-0000-4000-8000-0000000000aa');
SELECT ot.ok('a company admin cannot add a merchant',
             ot.err($$SELECT public.platform_save_merchant('{"name": "x"}')$$) LIKE '42501%');
SELECT ot.ok('nor read the offers, their numbers or an audience',
             ot.err('SELECT public.platform_offers_overview()') LIKE '42501%'
             AND ot.err($$SELECT public.platform_preview_offer_audience('{}')$$) LIKE '42501%'
             AND ot.err($$SELECT public.platform_offer_stats('7d000000-0000-4000-8000-000000000001')$$) LIKE '42501%');

SELECT ot.login('7d000000-0000-4000-8000-0000000000a5');
SELECT ot.ok('the platform adds a merchant',
             public.platform_save_merchant('{"id": "7d000000-0000-4000-8000-00000000e001", "name": "كافيه الاختبار", "category": "food", "whatsapp": "01000000000", "link_url": "https://example.com/menu"}')->>'id'
             = '7d000000-0000-4000-8000-00000000e001');
SELECT ot.ok('a link that is not https is refused',
             ot.err($$SELECT public.platform_save_merchant('{"name": "x", "link_url": "javascript:alert(1)"}')$$) IS NOT NULL);
SELECT ot.ok('a picture outside the merchant''s own folder is refused',
             ot.err($$SELECT public.platform_save_merchant('{"id": "7d000000-0000-4000-8000-00000000e001", "name": "x", "logo_path": "merchants/7d000000-0000-4000-8000-00000000e002/a.png"}')$$) IS NOT NULL);
SELECT ot.ok('an audience with something that is not an id is refused',
             ot.err($$SELECT public.platform_preview_offer_audience('{"university_ids": ["x"]}')$$) IS NOT NULL);
RESET ROLE;
SELECT ot.ok('unknown keys of an audience are dropped, empty lists too',
             public.offer_audience_clean('{"colleges": [" الهندسة ", ""], "line_ids": [], "anything": 1, "subscription": "any"}')
             = '{"colleges": ["الهندسة"], "subscription": "any"}'::jsonb);
SET LOCAL ROLE authenticated;

-- Reach, before anything is saved (s4 hid offers and is never counted).
SELECT ot.ok('reach: every student with a running subscription', (public.platform_preview_offer_audience('{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}')->>'students')::int = 2);
SELECT ot.ok('reach: every student, subscribed or not', (public.platform_preview_offer_audience('{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"], "subscription": "any"}')->>'students')::int = 3);
SELECT ot.ok('reach: a college of a university', (public.platform_preview_offer_audience('{"university_ids": ["7d000000-0000-4000-8000-0000000000f1"], "colleges": ["الهندسة"]}')->>'students')::int = 1);
SELECT ot.ok('reach: committed riders (8 rides, 80%)', (public.platform_preview_offer_audience('{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"], "min_rides": 8, "min_attendance": 80}')->>'students')::int = 1);

-- Offers: 01 everyone subscribed in A · 02 engineering of U1 · 03 U2, any student ·
-- 04 committed · 05 the line · 06 a governorate A is not in · 07 a specialisation ·
-- 08 a draft · 09 not started yet · 0a ended yesterday · 0b an advert · 0c one in total · 0d with a PIN
SELECT ot.offer('01', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}');
SELECT ot.offer('02', '{"university_ids": ["7d000000-0000-4000-8000-0000000000f1"], "colleges": ["الهندسة"]}');
SELECT ot.offer('03', '{"university_ids": ["7d000000-0000-4000-8000-0000000000f2"], "subscription": "any"}');
SELECT ot.offer('04', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"], "min_rides": 8, "min_attendance": 80}', '{"special": true}');
SELECT ot.offer('05', '{"line_ids": ["7d000000-0000-4000-8000-00000000a001"]}');
SELECT ot.offer('06', jsonb_build_object('company_ids', '["7d000000-0000-4000-8000-00000000c00a"]'::jsonb, 'governorates',
                 (SELECT jsonb_agg(code) FROM (SELECT code FROM public.governorates ORDER BY sort_order OFFSET 1 LIMIT 1) g)));
SELECT ot.offer('07', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"], "specialisations": ["مدني"]}');
SELECT public.platform_save_offer('{"id": "7d000000-0000-4000-8000-000000000008", "merchant_id": "7d000000-0000-4000-8000-00000000e001", "title": "مسودة", "value_label": "5%", "audience": {"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}}') \gset skip_
SELECT ot.offer('09', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}', jsonb_build_object('starts_at', now() + interval '1 day'));
SELECT ot.offer('0a', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}', jsonb_build_object('starts_at', now() - interval '9 days', 'ends_at', now() + interval '1 second'));
RESET ROLE;
UPDATE public.offers SET ends_at = now() - interval '1 day', starts_at = now() - interval '9 days' WHERE id = '7d000000-0000-4000-8000-00000000000a';
SET LOCAL ROLE authenticated;
SELECT ot.offer('0b', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}', '{"kind": "info", "value_label": ""}');
SELECT ot.offer('0c', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}', '{"total_limit": 1}');
SELECT ot.offer('0d', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}', '{"pin": "4821"}');
SELECT ot.ok('a PIN that is not 4-6 digits is refused',
             ot.err($$SELECT public.platform_save_offer('{"merchant_id": "7d000000-0000-4000-8000-00000000e001", "title": "x", "pin": "12"}')$$) IS NOT NULL);
SELECT ot.ok('the PIN is stored hashed and never sent back',
             ot.pin_set('7d000000-0000-4000-8000-00000000000d')
             AND public.platform_offers_overview()::text NOT LIKE '%4821%' AND public.platform_offers_overview()::text NOT LIKE '%pin_hash%');
SELECT ot.ok('saving again without a PIN keeps it; an empty one removes it',
             (SELECT public.platform_save_offer('{"id": "7d000000-0000-4000-8000-00000000000d", "merchant_id": "7d000000-0000-4000-8000-00000000e001", "title": "عرض 0d", "value_label": "20%", "audience": {"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}}') IS NOT NULL)
             AND ot.pin_set('7d000000-0000-4000-8000-00000000000d'));
SELECT ot.ok('an offer with no value cannot go live',
             ot.err($$SELECT public.platform_save_offer('{"id": "7d000000-0000-4000-8000-0000000000ff", "merchant_id": "7d000000-0000-4000-8000-00000000e001", "title": "بلا قيمة"}'); SELECT public.platform_set_offer_status('7d000000-0000-4000-8000-0000000000ff', 'live')$$) IS NOT NULL);

-- The special offer told its audience, once: only s1 is committed.
SELECT ot.ok('a special offer notifies its audience when first published',
             (SELECT count(*) = 1 AND bool_and(user_id = '7d000000-0000-4000-8000-000000000051') FROM ot.special_notices()));
SELECT ot.ok('the notification names the merchant and the offer and leads to the offers',
             (SELECT body = 'كافيه الاختبار: عرض 04' AND data->>'route' = 'offers'
                     AND data->>'offer_id' = '7d000000-0000-4000-8000-000000000004' FROM ot.special_notices()),
             (SELECT string_agg(body || ' / ' || data::text, '; ') FROM ot.special_notices()));
SELECT ot.offer('0e', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"], "min_rides": 8}', '{"special": true}');
SELECT ot.ok('a second special offer in the same week tells nobody again',
             (SELECT count(*) = 1 FROM ot.special_notices()));
SELECT public.platform_set_offer_status('7d000000-0000-4000-8000-00000000000e', 'ended') \gset skip2_
SELECT ot.ok('a merchant with offers cannot be deleted; one with none can',
             ot.err($$SELECT public.platform_delete_merchant('7d000000-0000-4000-8000-00000000e001')$$) LIKE '%فلا يُحذف%'
             AND ot.err($$SELECT public.platform_save_merchant('{"id": "7d000000-0000-4000-8000-00000000e009", "name": "بلا عروض"}'); SELECT public.platform_delete_merchant('7d000000-0000-4000-8000-00000000e009')$$) IS NULL);
SELECT ot.ok('editing an offer without a start keeps the start it had',
             (SELECT public.platform_save_offer('{"id": "7d000000-0000-4000-8000-000000000009", "merchant_id": "7d000000-0000-4000-8000-00000000e001", "title": "عرض 09", "value_label": "20%", "audience": {"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}}') IS NOT NULL)
             AND ot.starts_later('7d000000-0000-4000-8000-000000000009'));

-- Published ahead of its start: told when the start comes, not before (s2 was
-- not told of a special offer this week; s1 was).
SELECT ot.offer('0f', '{"company_ids": ["7d000000-0000-4000-8000-00000000c00a"]}', jsonb_build_object('special', true, 'starts_at', now() + interval '1 hour'));
SELECT ot.ok('a special offer published before its start tells nobody yet', (SELECT count(*) = 1 FROM ot.special_notices()));
RESET ROLE;
UPDATE public.offers SET starts_at = now() - interval '1 minute' WHERE id = '7d000000-0000-4000-8000-00000000000f';
SELECT ot.ok('when it starts, those not told this week are told', public.offers_announce_due() = 1);
SELECT ot.ok('once only', public.offers_announce_due() = 0);
SELECT ot.ok('s2 was told; s1, told of another this week, was not',
             (SELECT count(*) = 2 AND count(*) FILTER (WHERE user_id = '7d000000-0000-4000-8000-000000000052') = 1 FROM ot.special_notices()));
UPDATE public.offers SET status = 'ended' WHERE id = '7d000000-0000-4000-8000-00000000000f';
SET LOCAL ROLE authenticated;

-- ============================ What each student sees ============================
SELECT ot.login('7d000000-0000-4000-8000-000000000051');
SELECT ot.ok('s1 (engineering, civil, committed, on the line) sees what is meant for him',
             ot.mine() = ARRAY['01', '02', '04', '05', '07', '0b', '0c', '0d'], array_to_string(ot.mine(), ','));
SELECT ot.ok('the special offer comes first',
             public.get_my_offers()->'offers'->0->>'id' = '7d000000-0000-4000-8000-000000000004');
SELECT ot.ok('nothing internal reaches the app',
             public.get_my_offers()::text NOT LIKE '%pin_hash%' AND public.get_my_offers()::text NOT LIKE '%internal_note%'
             AND public.get_my_offers()::text NOT LIKE '%price%' AND public.get_my_offers()::text NOT LIKE '%audience%');
SELECT ot.login('7d000000-0000-4000-8000-000000000052');
SELECT ot.ok('s2 (dentistry, rarely scanned) gets the general ones only',
             ot.mine() = ARRAY['01', '05', '0b', '0c', '0d'], array_to_string(ot.mine(), ','));
SELECT ot.login('7d000000-0000-4000-8000-000000000053');
SELECT ot.ok('s3 (no subscription) sees only the offer open to every student of his university',
             ot.mine() = ARRAY['03'], array_to_string(ot.mine(), ','));
SELECT ot.login('7d000000-0000-4000-8000-000000000054');
SELECT ot.ok('s4 hid offers: none, and told so',
             ot.mine() = '{}' AND (public.get_my_offers()->>'hidden')::boolean);
SELECT ot.ok('and shows them again', NOT public.set_offers_hidden(false) AND ot.mine() = ARRAY['01', '02', '05', '0b', '0c', '0d'],
             array_to_string(ot.mine(), ','));
SELECT public.set_offers_hidden(true) \gset skip3_
SELECT ot.login('7d000000-0000-4000-8000-0000000000aa');
SELECT ot.ok('someone who is not a student gets none', ot.mine() = '{}');
SELECT ot.ok('and cannot take a coupon', ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-000000000001')$$) LIKE '42501%');
SELECT ot.ok('the tables themselves are closed to clients',
             ot.err('SELECT 1 FROM public.offers') LIKE '42501%' AND ot.err('SELECT 1 FROM public.merchants') LIKE '42501%'
             AND ot.err('SELECT 1 FROM public.offer_redemptions') LIKE '42501%' AND ot.err('SELECT 1 FROM public.offer_impressions') LIKE '42501%');

-- ============================ Coupons ============================
SELECT ot.login('7d000000-0000-4000-8000-000000000051');
SELECT public.offer_seen(ARRAY['7d000000-0000-4000-8000-000000000001', '7d000000-0000-4000-8000-000000000002', '7d000000-0000-4000-8000-00000000000d']::uuid[]);
SELECT public.offer_seen(ARRAY['7d000000-0000-4000-8000-000000000001']::uuid[]);
SELECT public.offer_opened('7d000000-0000-4000-8000-000000000001');
SELECT ot.keep('c1', public.redeem_offer('7d000000-0000-4000-8000-000000000001')) \gset skip4_
SELECT ot.ok('an offer with no PIN is used at once: a 6-character code, valid for its minutes',
             (ot.got('c1')->>'code') ~ '^[A-Z2-9]{6}$' AND (ot.got('c1')->>'confirmed')::boolean AND NOT (ot.got('c1')->>'needs_pin')::boolean
             AND (ot.got('c1')->>'expires_at')::timestamptz BETWEEN now() + interval '9 minutes' AND now() + interval '11 minutes');
SELECT ot.ok('asking again while it runs gives the same coupon',
             public.redeem_offer('7d000000-0000-4000-8000-000000000001')->>'id' = ot.got('c1')->>'id');
SELECT ot.ok('the app is told it was used, and shows the coupon',
             (SELECT (o->>'used')::int = 1 AND o->'coupon'->>'code' = ot.got('c1')->>'code'
              FROM jsonb_array_elements(public.get_my_offers()->'offers') o WHERE o->>'id' = '7d000000-0000-4000-8000-000000000001'));
RESET ROLE;
UPDATE public.offer_redemptions SET expires_at = now() - interval '1 minute' WHERE id = (ot.got('c1')->>'id')::uuid;
SET LOCAL ROLE authenticated;
SELECT ot.ok('once it ran out, a second use is refused: once per student',
             ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-000000000001')$$) LIKE '%استخدمت هذا العرض%');
SELECT ot.ok('an advert has no coupon', ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-00000000000b')$$) IS NOT NULL);
SELECT ot.ok('an offer not meant for him, a draft, one not started and one that ended are refused',
             ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-000000000003')$$) LIKE '%غير متاح%'
             AND ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-000000000008')$$) LIKE '%غير متاح%'
             AND ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-000000000009')$$) LIKE '%غير متاح%'
             AND ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-00000000000a')$$) LIKE '%غير متاح%');

-- With a PIN: not used until the merchant types it.
SELECT ot.keep('c2', public.redeem_offer('7d000000-0000-4000-8000-00000000000d')) \gset skip5_
SELECT ot.ok('an offer with a PIN gives a coupon that is not used yet',
             (ot.got('c2')->>'needs_pin')::boolean AND NOT (ot.got('c2')->>'confirmed')::boolean);
SELECT ot.ok('a wrong PIN is refused and counted',
             public.confirm_offer_redemption((ot.got('c2')->>'id')::uuid, '0000') = '{"confirmed": false, "tries_left": 4}'::jsonb);
SELECT ot.ok('the right PIN confirms it',
             (public.confirm_offer_redemption((ot.got('c2')->>'id')::uuid, '4821')->>'confirmed')::boolean);
SELECT ot.ok('confirming again changes nothing',
             (public.confirm_offer_redemption((ot.got('c2')->>'id')::uuid, '9999')->>'confirmed')::boolean);
SELECT ot.login('7d000000-0000-4000-8000-000000000052');
SELECT ot.ok('a student cannot confirm someone else''s coupon',
             ot.err(format('SELECT public.confirm_offer_redemption(%L, %L)', ot.got('c2')->>'id', '4821')) LIKE '42501%');
SELECT ot.keep('c3', public.redeem_offer('7d000000-0000-4000-8000-00000000000d')) \gset skip6_
SELECT public.confirm_offer_redemption((ot.got('c3')->>'id')::uuid, '1111') FROM generate_series(1, 5) \gset skip7_
SELECT ot.ok('after five wrong tries the coupon is dead, even with the right PIN',
             ot.err(format('SELECT public.confirm_offer_redemption(%L, %L)', ot.got('c3')->>'id', '4821')) LIKE '%محاولات كثيرة%');
SELECT ot.keep('c4', public.redeem_offer('7d000000-0000-4000-8000-00000000000d')) \gset skip11_
SELECT ot.ok('a coupon whose tries ran out is closed and a new one given, counted by the server''s clock',
             ot.got('c4')->>'id' <> ot.got('c3')->>'id' AND (ot.got('c4')->>'seconds_left')::int = 600);
SELECT public.confirm_offer_redemption((ot.got('c4')->>'id')::uuid, '1111') FROM generate_series(1, 5) \gset skip12_
SELECT ot.keep('c5', public.redeem_offer('7d000000-0000-4000-8000-00000000000d')) \gset skip13_
SELECT public.confirm_offer_redemption((ot.got('c5')->>'id')::uuid, '1111') FROM generate_series(1, 5) \gset skip14_
SELECT ot.ok('after three such coupons in an hour no more are given: the PIN cannot be guessed',
             ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-00000000000d')$$) LIKE '%بعد ساعة%');
SELECT ot.ok('a coupon never confirmed does not count as a use',
             (SELECT (o->>'used')::int = 0 FROM jsonb_array_elements(public.get_my_offers()->'offers') o WHERE o->>'id' = '7d000000-0000-4000-8000-00000000000d'));

-- A total of one: s2 takes it, s1 finds none left.
SELECT ot.ok('s2 takes the only one of a limited offer',
             (public.redeem_offer('7d000000-0000-4000-8000-00000000000c')->>'confirmed')::boolean);
SELECT ot.ok('he still sees it, with nothing left',
             (SELECT (o->>'left')::int = 0 AND (o->>'used')::int = 1
              FROM jsonb_array_elements(public.get_my_offers()->'offers') o WHERE o->>'id' = '7d000000-0000-4000-8000-00000000000c'));
SELECT ot.login('7d000000-0000-4000-8000-000000000051');
SELECT ot.ok('for the others it is gone, and cannot be taken',
             NOT ('0c' = ANY (ot.mine())) AND ot.err($$SELECT public.redeem_offer('7d000000-0000-4000-8000-00000000000c')$$) IS NOT NULL);

-- ============================ The platform's numbers ============================
SELECT ot.login('7d000000-0000-4000-8000-0000000000a5');
SELECT ot.keep('s1', public.platform_offer_stats('7d000000-0000-4000-8000-000000000001')) \gset skip8_
SELECT ot.ok('an offer''s numbers: reach, seen once however often shown, opened, used',
             (ot.got('s1')->>'reach')::int = 2 AND (ot.got('s1')->>'seen')::int = 1 AND (ot.got('s1')->>'opened')::int = 1
             AND (ot.got('s1')->>'redeemed')::int = 1 AND (ot.got('s1')->>'coupons')::int = 1, ot.got('s1')::text);
SELECT ot.ok('a group of fewer than five is not shown by name',
             (SELECT bool_and(g->>'name' = 'أخرى') FROM jsonb_array_elements((ot.got('s1')->'by_university') || (ot.got('s1')->'by_college')) g),
             ((ot.got('s1')->'by_university') || (ot.got('s1')->'by_college'))::text);
SELECT ot.ok('no student is named anywhere in the numbers or the list',
             ot.got('s1')::text NOT LIKE '%طالب ١%' AND ot.got('s1')::text NOT LIKE '%7d000000-0000-4000-8000-000000000051%'
             AND public.platform_offers_overview()::text NOT LIKE '%0109995%');
SELECT ot.ok('the list carries each offer''s counts and whether it is running',
             (SELECT (o->>'seen')::int = 1 AND (o->>'redeemed')::int = 1 AND (o->>'running')::boolean
              FROM jsonb_array_elements(public.platform_offers_overview()->'offers') o WHERE o->>'id' = '7d000000-0000-4000-8000-000000000001')
             AND (SELECT NOT (o->>'running')::boolean FROM jsonb_array_elements(public.platform_offers_overview()->'offers') o
                  WHERE o->>'id' = '7d000000-0000-4000-8000-00000000000a'));
SELECT ot.ok('an offer that was used cannot be deleted, an unused one can',
             ot.err($$SELECT public.platform_delete_offer('7d000000-0000-4000-8000-000000000001')$$) LIKE '%فلا يُحذف%'
             AND ot.err($$SELECT public.platform_delete_offer('7d000000-0000-4000-8000-000000000008')$$) IS NULL);

-- Pausing takes it off the phones; a stopped merchant takes all of theirs off.
SELECT public.platform_set_offer_status('7d000000-0000-4000-8000-000000000002', 'paused') \gset skip9_
SELECT ot.login('7d000000-0000-4000-8000-000000000051');
SELECT ot.ok('a paused offer is gone from the app', NOT ('02' = ANY (ot.mine())));
SELECT ot.login('7d000000-0000-4000-8000-0000000000a5');
SELECT public.platform_save_merchant('{"id": "7d000000-0000-4000-8000-00000000e001", "name": "كافيه الاختبار", "category": "food", "is_active": false}') \gset skip10_
SELECT ot.ok('a stopped merchant''s offer cannot be published',
             ot.err($$SELECT public.platform_set_offer_status('7d000000-0000-4000-8000-000000000002', 'live')$$) LIKE '%التاجر موقوف%');
SELECT ot.login('7d000000-0000-4000-8000-000000000051');
SELECT ot.ok('and none of their offers show', ot.mine() = '{}');

RESET ROLE;
SELECT ot.ok('the phones and the dashboard were told of the changes',
             (SELECT count(*) > 0 FROM realtime.messages m WHERE m.payload->>'table' = 'offers' AND m.topic = 'line:7d000000-0000-4000-8000-00000000a001')
             AND (SELECT count(*) > 0 FROM realtime.messages m WHERE m.payload->>'table' = 'offers' AND m.topic = 'platform'));
SELECT ot.ok('signed out: nothing can be called',
             NOT has_function_privilege('anon', 'public.get_my_offers()', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.redeem_offer(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.platform_offers_overview()', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.offer_audience_matches(jsonb, uuid)', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.student_commitment(uuid, integer)', 'EXECUTE'));

\pset format unaligned
\pset tuples_only on
SELECT count(*) FILTER (WHERE ok) || ' of ' || count(*) || ' ok' FROM ot.results;
SELECT n || ' FAILED: ' || step || ' :: ' || left(COALESCE(detail, ''), 300) FROM ot.results WHERE NOT ok ORDER BY n;
ROLLBACK;
