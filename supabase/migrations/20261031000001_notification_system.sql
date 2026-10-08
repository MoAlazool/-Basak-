-- ==============================================================================
-- Migration: 20261031000001_notification_system.sql
-- Run AFTER 20261030000001. Safe to re-run. Additive: the released app keeps
-- working (get_my_notifications, send_notification, get_company_notifications).
--
-- 1. Notifications gain a type, a category, a priority, ids for the screen to
--    open (data), an English text, a status (scheduled / sent / cancelled /
--    failed), the audience as chosen (audience_spec) and an idempotency key.
-- 2. Who receives a notification is always worked out here from the audience;
--    clients never send recipients. One place does it (notification_deliver).
-- 3. Push: push_devices (one row per install and account; a token belongs to one
--    account only), notification_preferences (they silence push only, the inbox
--    keeps everything), push_outbox (one row per notification and device, sent
--    by the push-dispatch function, retried, never "delivered": queued, sending,
--    accepted by the provider, failed, skipped, expired).
-- 4. Automatic notifications for subscriptions (proof received, approved,
--    rejected, ending in 3 days, ended). They can never fail the action itself.
-- 5. Supervisors: ready-made operational messages for their own lines, with a
--    rate limit and an audit trail. Admins: preview, send now or schedule, edit
--    or cancel what is scheduled, history with true counts.
-- 6. Realtime: private topic user:<id> for personal notifications and for the
--    read state changing on another device.
-- 7. Every minute (pg_cron, where installed): scheduled sends, daily notices,
--    clean-up, and a wake-up for the dispatcher.
-- ==============================================================================
BEGIN;

-- ------------------------------------------------------------------------------
-- 1. Notifications: more columns
-- ------------------------------------------------------------------------------
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'announcement.admin',
  ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'announcement',
  ADD COLUMN IF NOT EXISTS priority text NOT NULL DEFAULT 'normal',
  -- Ids only (route, subscription_id, line_id, trip_id, ride_date): never names or phones.
  ADD COLUMN IF NOT EXISTS data jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS title_en text,
  ADD COLUMN IF NOT EXISTS body_en text,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'sent',
  ADD COLUMN IF NOT EXISTS status_note text,
  ADD COLUMN IF NOT EXISTS scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS sent_at timestamptz,
  -- {"kind": "company" | "line" | "trip" | "university" | "user", ...ids}
  ADD COLUMN IF NOT EXISTS audience_spec jsonb,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

UPDATE public.notifications SET sent_at = created_at WHERE sent_at IS NULL AND status = 'sent';
UPDATE public.notifications SET type = 'announcement.supervisor'
WHERE sender_role = 'supervisor' AND type = 'announcement.admin';
UPDATE public.notifications SET audience_spec = CASE
    WHEN trip_id IS NOT NULL THEN jsonb_build_object('kind', 'trip', 'line_id', line_id, 'trip_id', trip_id, 'ride_date', ride_date)
    WHEN line_id IS NOT NULL THEN jsonb_build_object('kind', 'line', 'line_id', line_id)
    ELSE jsonb_build_object('kind', 'company') END
WHERE audience_spec IS NULL;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_sender_role_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_sender_role_check
  CHECK (sender_role IN ('admin', 'supervisor', 'system'));
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_category_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_category_check
  CHECK (category IN ('subscription', 'transport', 'announcement'));
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_priority_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_priority_check
  CHECK (priority IN ('normal', 'high'));
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_status_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_status_check
  CHECK (status IN ('scheduled', 'sent', 'cancelled', 'failed')
         AND (status <> 'scheduled' OR scheduled_at IS NOT NULL)
         AND (status <> 'sent' OR sent_at IS NOT NULL));

-- The same request sent twice (double tap, retry after a lost answer) is one notification.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_idempotency
  ON public.notifications(company_id, sender_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL AND sender_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_idempotency_system
  ON public.notifications(company_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL AND sender_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_due ON public.notifications(scheduled_at) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_notifications_sent ON public.notifications(sent_at DESC) WHERE status = 'sent';
CREATE INDEX IF NOT EXISTS idx_notifications_sender ON public.notifications(sender_id, sent_at DESC);

-- A tap on the push or the banner (opened), apart from read in the list.
ALTER TABLE public.notification_recipients ADD COLUMN IF NOT EXISTS opened_at timestamptz;
CREATE INDEX IF NOT EXISTS idx_notification_recipients_unread
  ON public.notification_recipients(user_id) WHERE read_at IS NULL;

-- ------------------------------------------------------------------------------
-- 2. Texts written once: Arabic and English, used by the database only
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_templates (
  key text PRIMARY KEY,
  category text NOT NULL CHECK (category IN ('subscription', 'transport', 'announcement')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('normal', 'high')),
  title_ar text NOT NULL,
  body_ar text NOT NULL,
  title_en text,
  body_en text,
  route text NOT NULL DEFAULT 'notifications',
  -- Offered to supervisors as a ready-made message.
  supervisor_quick boolean NOT NULL DEFAULT false,
  needs_minutes boolean NOT NULL DEFAULT false,
  direction text CHECK (direction IN ('departure', 'return')),
  sort integer NOT NULL DEFAULT 0
);
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_templates FROM PUBLIC, anon, authenticated;

INSERT INTO public.notification_templates
  (key, category, priority, title_ar, body_ar, title_en, body_en, route, supervisor_quick, needs_minutes, direction, sort)
VALUES
  ('subscription.payment_received', 'subscription', 'normal',
   'استلمنا إثبات الدفع', 'طلب اشتراكك قيد المراجعة الآن، وسنبلغك فور اعتماده.',
   'Payment proof received', 'Your subscription request is under review. We will let you know once it is approved.',
   'subscription', false, false, NULL, 10),
  ('subscription.approved', 'subscription', 'high',
   'تم تفعيل اشتراكك', 'اشتراكك أصبح فعّالاً، وبطاقتك جاهزة للاستخدام.',
   'Your subscription is active', 'Your subscription is now active and your card is ready to use.',
   'subscription', false, false, NULL, 11),
  ('subscription.rejected', 'subscription', 'high',
   'لم يُعتمد طلب الاشتراك', 'تعذّر اعتماد طلبك. افتح الاشتراك لمعرفة التفاصيل.',
   'Subscription request not approved', 'Your request could not be approved. Open the subscription for details.',
   'subscription', false, false, NULL, 12),
  ('subscription.expiring', 'subscription', 'normal',
   'اشتراكك ينتهي قريباً', 'ينتهي اشتراكك خلال 3 أيام. جدّده حتى لا تنقطع الخدمة.',
   'Your subscription ends soon', 'Your subscription ends in 3 days. Renew it to keep riding.',
   'subscription', false, false, NULL, 13),
  ('subscription.expired', 'subscription', 'normal',
   'انتهى اشتراكك', 'انتهت مدة اشتراكك. يمكنك الاشتراك من جديد من التطبيق.',
   'Your subscription has ended', 'Your subscription period is over. You can subscribe again from the app.',
   'subscription', false, false, NULL, 14),
  ('transport.delay', 'transport', 'high',
   'تأخير في موعد الحافلة', 'ستتأخر الحافلة نحو {minutes} دقيقة. نعتذر عن التأخير.',
   'Bus delayed', 'The bus is running about {minutes} minutes late. Sorry for the delay.',
   'home', true, true, NULL, 20),
  ('transport.departed', 'transport', 'high',
   'الحافلة تحركت', 'بدأت رحلة الذهاب والحافلة في طريقها. كن في محطتك في الموعد.',
   'The bus is on its way', 'The trip has started and the bus is on its way. Be at your station on time.',
   'home', true, false, 'departure', 21),
  ('transport.arrived', 'transport', 'normal',
   'وصلت الحافلة إلى الجامعة', 'وصلت رحلة الذهاب إلى الجامعة.',
   'The bus reached the university', 'The trip has arrived at the university.',
   'home', true, false, 'departure', 22),
  ('transport.return_departing', 'transport', 'high',
   'رحلة العودة تتحرك قريباً', 'تتحرك حافلة العودة من الجامعة خلال {minutes} دقيقة. توجّه إلى الحافلة.',
   'Return trip leaving soon', 'The return bus leaves from the university in {minutes} minutes. Head to the bus.',
   'home', true, true, 'return', 23),
  ('transport.cancelled', 'transport', 'high',
   'إلغاء الرحلة', 'أُلغيت هذه الرحلة اليوم. تابع الإشعارات لمعرفة البديل.',
   'Trip cancelled', 'This trip is cancelled today. Watch your notifications for the alternative.',
   'home', true, false, NULL, 24)
ON CONFLICT (key) DO UPDATE SET
  category = EXCLUDED.category, priority = EXCLUDED.priority, title_ar = EXCLUDED.title_ar,
  body_ar = EXCLUDED.body_ar, title_en = EXCLUDED.title_en, body_en = EXCLUDED.body_en,
  route = EXCLUDED.route, supervisor_quick = EXCLUDED.supervisor_quick,
  needs_minutes = EXCLUDED.needs_minutes, direction = EXCLUDED.direction, sort = EXCLUDED.sort;

-- ------------------------------------------------------------------------------
-- 3. Devices, preferences, outbox, audit, runtime
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.push_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Made once by the app on the device; survives sign-out.
  installation_id text NOT NULL CHECK (char_length(installation_id) BETWEEN 8 AND 100),
  platform text NOT NULL CHECK (platform IN ('ios', 'android')),
  token text NOT NULL CHECK (char_length(token) BETWEEN 20 AND 4096),
  locale text NOT NULL DEFAULT 'ar',
  app_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  -- Set when the provider says the token is no longer valid.
  disabled_at timestamptz,
  disabled_reason text,
  UNIQUE (user_id, installation_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_push_devices_token ON public.push_devices(token);
ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_devices FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  push_enabled boolean NOT NULL DEFAULT true,
  -- {"subscription": false, ...}; a missing category is on.
  categories jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_preferences FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.push_outbox (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES public.push_devices(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sending', 'accepted', 'failed', 'skipped', 'expired')),
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  provider_message_id text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (notification_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_push_outbox_due ON public.push_outbox(next_attempt_at) WHERE status = 'queued';
CREATE INDEX IF NOT EXISTS idx_push_outbox_sending ON public.push_outbox(claimed_at) WHERE status = 'sending';
ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_outbox FROM PUBLIC, anon, authenticated;

-- Who sent, scheduled, changed, cancelled or deleted what. Kept when the
-- notification itself is deleted.
CREATE TABLE IF NOT EXISTS public.notification_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT clock_timestamp(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  actor_id uuid,
  actor_role text NOT NULL,
  action text NOT NULL,
  notification_id uuid,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_notification_audit_actor ON public.notification_audit(actor_id, at DESC);
CREATE INDEX IF NOT EXISTS idx_notification_audit_company ON public.notification_audit(company_id, at DESC);
ALTER TABLE public.notification_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_audit FROM PUBLIC, anon, authenticated;

-- Where the dispatcher is and whether it has the provider's credentials.
-- dispatch_url and dispatch_secret are set by hand once (as wallet_runtime).
CREATE TABLE IF NOT EXISTS public.push_runtime (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  dispatch_url text,
  dispatch_secret text,
  configured boolean,
  checked_at timestamptz,
  last_daily date
);
INSERT INTO public.push_runtime (id) VALUES (true) ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.push_runtime ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_runtime FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.push_devices, public.notification_preferences, public.push_outbox,
             public.notification_audit, public.push_runtime, public.notification_templates TO service_role;

-- ------------------------------------------------------------------------------
-- 4. Realtime: user:<id>, and announcing a notification to those it concerns
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_join_topic(p_topic text)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_kind text := split_part(p_topic, ':', 1);
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF p_topic = 'platform' THEN RETURN public.is_super_admin(); END IF;
  BEGIN
    v_id := split_part(p_topic, ':', 2)::uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  -- Unknown is refused: always true or false, never NULL.
  RETURN COALESCE(CASE v_kind
    WHEN 'company' THEN public.has_company_access(v_id)
    WHEN 'student' THEN v_id = auth.uid()
    WHEN 'user' THEN v_id = auth.uid()
    WHEN 'line' THEN
      public.has_company_access((SELECT l.company_id FROM public.lines l WHERE l.id = v_id))
      OR EXISTS (SELECT 1 FROM public.subscriptions s
                 WHERE s.line_id = v_id AND s.student_id = auth.uid()
                   AND s.status IN ('pending_payment', 'pending_review', 'active'))
    ELSE false
  END, false);
END;
$$;

-- The company's staff always; once it is sent, the lines it concerns or the one
-- person it is for. A scheduled notification is only the staff's business.
CREATE OR REPLACE FUNCTION public.announce_notification() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.notifications := COALESCE(NEW, OLD);
  v_payload jsonb := jsonb_build_object('table', 'notifications', 'op', TG_OP, 'id', v_row.id,
                                        'company_id', v_row.company_id);
  v_kind text := COALESCE(v_row.audience_spec->>'kind', CASE WHEN v_row.line_id IS NULL THEN 'company' ELSE 'line' END);
  v_line uuid;
BEGIN
  PERFORM public.announce('company:' || v_row.company_id, v_payload);
  IF v_row.status <> 'sent' THEN RETURN NULL; END IF;
  -- Sent before and still sent: only the staff's counts changed.
  IF TG_OP = 'UPDATE' AND OLD.status = 'sent' THEN RETURN NULL; END IF;
  -- To the people receiving it, a scheduled notification going out is a new one.
  v_payload := jsonb_set(v_payload, '{op}', to_jsonb(CASE TG_OP WHEN 'DELETE' THEN 'DELETE' ELSE 'INSERT' END));
  IF v_kind = 'user' THEN
    PERFORM public.announce('user:' || (v_row.audience_spec->>'user_id'), v_payload);
    RETURN NULL;
  END IF;
  FOR v_line IN SELECT l.id FROM public.lines l
                WHERE l.company_id = v_row.company_id
                  AND (v_kind NOT IN ('line', 'trip') OR l.id = v_row.line_id) LOOP
    PERFORM public.announce('line:' || v_line, v_payload);
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_notification() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_announce_notification ON public.notifications;
CREATE TRIGGER trg_announce_notification AFTER INSERT OR DELETE OR UPDATE OF status, title, body, scheduled_at
  ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.announce_notification();

-- ------------------------------------------------------------------------------
-- 5. The audience: checked, named and resolved here only
-- ------------------------------------------------------------------------------
-- Checks an audience chosen for p_company and returns it clean, with its label:
-- {kind, line_id, trip_id, ride_date, university_id, user_id, label}.
-- p_on: the day it will be sent (a trip's riders: that day or the next).
CREATE OR REPLACE FUNCTION public.notification_audience_resolve(p_company uuid, p_spec jsonb, p_on date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_kind text := COALESCE(p_spec->>'kind', '');
  v_line public.lines%ROWTYPE;
  v_trip public.line_trips%ROWTYPE;
  v_date date;
  v_university text;
  v_id uuid;
BEGIN
  IF v_kind = 'company' THEN
    RETURN jsonb_build_object('kind', 'company', 'label', 'كل طلاب الشركة');
  ELSIF v_kind IN ('line', 'trip') THEN
    BEGIN v_id := (p_spec->>'line_id')::uuid; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
    SELECT * INTO v_line FROM public.lines WHERE id = v_id AND company_id = p_company;
    IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.'; END IF;
    IF v_kind = 'line' THEN
      RETURN jsonb_build_object('kind', 'line', 'line_id', v_line.id, 'label', v_line.name);
    END IF;
    BEGIN v_id := (p_spec->>'trip_id')::uuid; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
    SELECT * INTO v_trip FROM public.line_trips t WHERE t.id = v_id AND t.line_id = v_line.id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الرحلة غير موجودة على هذا الخط.'; END IF;
    BEGIN v_date := COALESCE((p_spec->>'ride_date')::date, p_on);
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'تاريخ الرحلة غير صحيح.'; END;
    IF v_date NOT BETWEEN p_on AND p_on + 1 THEN
      RAISE EXCEPTION 'يمكن مراسلة ركاب رحلة اليوم أو الغد فقط.';
    END IF;
    RETURN jsonb_build_object('kind', 'trip', 'line_id', v_line.id, 'trip_id', v_trip.id, 'ride_date', v_date,
      'label', format('%s · %s %s · %s', v_line.name,
        CASE v_trip.direction WHEN 'return' THEN 'عودة' ELSE 'ذهاب' END,
        to_char(v_trip.start_time, 'FMHH12:MI') || CASE WHEN v_trip.start_time < '12:00' THEN ' ص' ELSE ' م' END,
        -- "8 أكتوبر": a numeric date would flip around in right-to-left text.
        extract(day FROM v_date)::int || ' ' || (ARRAY['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو',
          'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'])[extract(month FROM v_date)::int]));
  ELSIF v_kind = 'university' THEN
    BEGIN v_id := (p_spec->>'university_id')::uuid; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
    SELECT u.name INTO v_university FROM public.universities u WHERE u.id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الجامعة غير موجودة.'; END IF;
    RETURN jsonb_build_object('kind', 'university', 'university_id', v_id, 'label', 'طلاب ' || v_university);
  ELSIF v_kind = 'user' THEN
    BEGIN v_id := (p_spec->>'user_id')::uuid; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
    IF v_id IS NULL THEN RAISE EXCEPTION 'المستلم غير محدد.'; END IF;
    RETURN jsonb_build_object('kind', 'user', 'user_id', v_id, 'label', 'إشعار شخصي');
  END IF;
  RAISE EXCEPTION 'اختر من يصلهم الإشعار.';
END;
$$;

-- Who a (resolved) audience is right now: the trip's riders for that day, one
-- person, or the students with an open subscription that has not ended; and the
-- supervisors of the lines concerned.
CREATE OR REPLACE FUNCTION public.notification_audience_users(p_company uuid, p_spec jsonb, p_except uuid)
RETURNS TABLE(user_id uuid, is_student boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH spec AS (
    SELECT p_spec->>'kind' AS kind, (p_spec->>'line_id')::uuid AS line_id, (p_spec->>'trip_id')::uuid AS trip_id,
           (p_spec->>'ride_date')::date AS ride_date, (p_spec->>'university_id')::uuid AS university_id,
           (p_spec->>'user_id')::uuid AS one_user
  ), students AS (
    SELECT c.student_id FROM spec, public.rider_trip_choices(spec.ride_date) c
    WHERE spec.kind = 'trip' AND c.trip_id = spec.trip_id
    UNION
    SELECT st.id FROM spec JOIN public.students st ON st.id = spec.one_user WHERE spec.kind = 'user'
    UNION
    SELECT s.student_id FROM spec, public.subscriptions s
    WHERE spec.kind IN ('company', 'line', 'university') AND s.company_id = p_company
      AND (spec.kind <> 'line' OR s.line_id = spec.line_id)
      AND (spec.kind <> 'university' OR EXISTS (
            SELECT 1 FROM public.students st WHERE st.id = s.student_id AND st.university_id = spec.university_id))
      AND s.status IN ('pending_payment', 'pending_review', 'active')
      AND (s.end_date IS NULL OR s.end_date >= public.cairo_today())
  )
  SELECT x.student_id, true FROM students x WHERE x.student_id IS DISTINCT FROM p_except
  UNION ALL
  SELECT DISTINCT sl.supervisor_id, false
  FROM spec, public.supervisor_lines sl
  JOIN public.supervisors sv ON sv.id = sl.supervisor_id AND sv.is_active
  JOIN public.lines l ON l.id = sl.line_id
  WHERE spec.kind IN ('company', 'line', 'trip') AND l.company_id = p_company
    AND (spec.kind = 'company' OR sl.line_id = spec.line_id)
    AND sl.supervisor_id IS DISTINCT FROM p_except
    AND sl.supervisor_id NOT IN (SELECT student_id FROM students)
$$;
REVOKE ALL ON FUNCTION public.notification_audience_resolve(uuid, jsonb, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notification_audience_users(uuid, jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 6. Sending
-- ------------------------------------------------------------------------------
-- Wakes the dispatcher once per transaction; the request leaves after commit.
CREATE OR REPLACE FUNCTION public.push_kick()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_runtime public.push_runtime%ROWTYPE;
BEGIN
  IF to_regnamespace('net') IS NULL OR current_setting('push.kicked', true) = txid_current()::text THEN RETURN; END IF;
  SELECT * INTO v_runtime FROM public.push_runtime WHERE id AND dispatch_url IS NOT NULL;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM set_config('push.kicked', txid_current()::text, true);
  EXECUTE 'SELECT net.http_post(url := $1, body := $2, headers := $3)'
    USING v_runtime.dispatch_url, '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_runtime.dispatch_secret);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'push wake-up failed: %', SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public.push_kick() FROM PUBLIC, anon, authenticated;

-- Sends a stored notification now: fixes its recipients, marks it sent and
-- queues a push for each of their devices (skipped where they turned push off).
-- Returns how many students receive it; 0 changes nothing.
CREATE OR REPLACE FUNCTION public.notification_deliver(p_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n public.notifications%ROWTYPE;
  v_students integer;
  v_queued integer;
BEGIN
  SELECT * INTO v_n FROM public.notifications WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 0; END IF;

  SELECT count(*) INTO v_students
  FROM public.notification_audience_users(v_n.company_id, v_n.audience_spec, v_n.sender_id) u WHERE u.is_student;
  IF v_students = 0 THEN RETURN 0; END IF;

  INSERT INTO public.notification_recipients(notification_id, user_id, is_student)
  SELECT v_n.id, u.user_id, u.is_student
  FROM public.notification_audience_users(v_n.company_id, v_n.audience_spec, v_n.sender_id) u
  ON CONFLICT DO NOTHING;

  UPDATE public.notifications SET status = 'sent', sent_at = clock_timestamp(), status_note = NULL WHERE id = v_n.id;

  INSERT INTO public.push_outbox(notification_id, user_id, device_id, status)
  SELECT v_n.id, d.user_id, d.id,
         CASE WHEN COALESCE(p.push_enabled, true)
                   AND COALESCE((p.categories->>v_n.category)::boolean, true) THEN 'queued' ELSE 'skipped' END
  FROM public.notification_recipients r
  JOIN public.push_devices d ON d.user_id = r.user_id AND d.disabled_at IS NULL
  LEFT JOIN public.notification_preferences p ON p.user_id = r.user_id
  WHERE r.notification_id = v_n.id
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_queued = ROW_COUNT;
  IF v_queued > 0 THEN PERFORM public.push_kick(); END IF;
  RETURN v_students;
END;
$$;
REVOKE ALL ON FUNCTION public.notification_deliver(uuid) FROM PUBLIC, anon, authenticated;

-- Stores a notification (not yet sent). An idempotency key seen before for this
-- sender returns that notification instead: (id, true).
CREATE OR REPLACE FUNCTION public.notification_create(
  p_company uuid, p_sender uuid, p_sender_role text, p_sender_name text, p_type text, p_category text,
  p_priority text, p_title text, p_body text, p_title_en text, p_body_en text, p_spec jsonb, p_data jsonb,
  p_scheduled_at timestamptz, p_idempotency_key text, OUT o_id uuid, OUT o_duplicate boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_key text := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');
BEGIN
  o_duplicate := false;
  IF v_key IS NOT NULL THEN
    IF char_length(v_key) > 120 THEN RAISE EXCEPTION 'Invalid idempotency key'; END IF;
    SELECT n.id INTO o_id FROM public.notifications n
    WHERE n.company_id = p_company AND n.sender_id IS NOT DISTINCT FROM p_sender AND n.idempotency_key = v_key;
    IF FOUND THEN o_duplicate := true; RETURN; END IF;
  END IF;
  BEGIN
    INSERT INTO public.notifications(company_id, sender_id, sender_role, sender_name, line_id, trip_id, ride_date,
                                     audience, title, body, title_en, body_en, type, category, priority, data,
                                     status, scheduled_at, audience_spec, idempotency_key)
    VALUES (p_company, p_sender, p_sender_role, COALESCE(NULLIF(btrim(p_sender_name), ''), 'الإدارة'),
            (p_spec->>'line_id')::uuid, (p_spec->>'trip_id')::uuid, (p_spec->>'ride_date')::date,
            p_spec->>'label', btrim(p_title), btrim(p_body), p_title_en, p_body_en, p_type, p_category,
            COALESCE(p_priority, 'normal'), COALESCE(p_data, '{}'::jsonb),
            -- Not shown to anyone until notification_deliver says so.
            CASE WHEN p_scheduled_at IS NULL THEN 'failed' ELSE 'scheduled' END, p_scheduled_at,
            p_spec - 'label', v_key)
    RETURNING id INTO o_id;
  EXCEPTION WHEN unique_violation THEN
    -- The same request arrived twice at once: the first one stands.
    SELECT n.id INTO o_id FROM public.notifications n
    WHERE n.company_id = p_company AND n.sender_id IS NOT DISTINCT FROM p_sender AND n.idempotency_key = v_key;
    o_duplicate := true;
  END;
END;
$$;
REVOKE ALL ON FUNCTION public.notification_create(uuid, uuid, text, text, text, text, text, text, text, text, text,
                                                  jsonb, jsonb, timestamptz, text) FROM PUBLIC, anon, authenticated;

-- Not more than p_limit sends an hour from one account.
CREATE OR REPLACE FUNCTION public.notification_rate_check(p_actor uuid, p_limit integer)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (SELECT count(*) FROM public.notification_audit a
      WHERE a.actor_id = p_actor AND a.action IN ('send', 'schedule') AND a.at > now() - interval '1 hour') >= p_limit THEN
    RAISE EXCEPTION 'أرسلت إشعارات كثيرة خلال الساعة الأخيرة. حاول مرة أخرى بعد قليل.';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.notification_rate_check(uuid, integer) FROM PUBLIC, anon, authenticated;

-- An automatic notification to one student. Never raises: what the student or
-- the admin was doing must not fail because of a notification.
CREATE OR REPLACE FUNCTION public.notify_student(
  p_company uuid, p_student uuid, p_template text, p_data jsonb, p_idempotency_key text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t public.notification_templates%ROWTYPE;
  v_id uuid;
  v_duplicate boolean;
BEGIN
  SELECT * INTO v_t FROM public.notification_templates WHERE key = p_template;
  IF NOT FOUND OR p_company IS NULL OR p_student IS NULL THEN RETURN; END IF;
  SELECT o_id, o_duplicate INTO v_id, v_duplicate FROM public.notification_create(
    p_company, NULL, 'system', (SELECT c.name FROM public.companies c WHERE c.id = p_company),
    v_t.key, v_t.category, v_t.priority, v_t.title_ar, v_t.body_ar, v_t.title_en, v_t.body_en,
    jsonb_build_object('kind', 'user', 'user_id', p_student, 'label', 'إشعار شخصي'),
    jsonb_build_object('route', v_t.route) || COALESCE(p_data, '{}'::jsonb), NULL, p_idempotency_key);
  IF v_duplicate THEN RETURN; END IF;
  IF public.notification_deliver(v_id) = 0 THEN
    DELETE FROM public.notifications WHERE id = v_id;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_student(%) failed: %', p_template, SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_student(uuid, uuid, text, jsonb, text) FROM PUBLIC, anon, authenticated;

-- A subscription changing state tells its student. (One created already active,
-- by an admin for a student, says nothing: there was no request to answer.)
CREATE OR REPLACE FUNCTION public.notify_subscription_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_template text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NULL; END IF;
  v_template := CASE NEW.status
    WHEN 'pending_review' THEN 'subscription.payment_received'
    WHEN 'active' THEN 'subscription.approved'
    WHEN 'rejected' THEN 'subscription.rejected'
    WHEN 'expired' THEN 'subscription.expired'
  END;
  IF v_template IS NULL THEN RETURN NULL; END IF;
  PERFORM public.notify_student(NEW.company_id, NEW.student_id, v_template,
    jsonb_build_object('subscription_id', NEW.id),
    -- The ending is told once, whether the status changes or the day passes first.
    CASE WHEN v_template = 'subscription.expired' THEN 'expired:' || NEW.id END);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_subscription_change failed: %', SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_subscription_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_notify_subscription_change ON public.subscriptions;
CREATE TRIGGER trg_notify_subscription_change AFTER UPDATE OF status ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.notify_subscription_change();

-- ------------------------------------------------------------------------------
-- 7. Admins and supervisors write
-- ------------------------------------------------------------------------------
-- Free text, as before (20261023000001), now through the shared path, with a
-- rate limit and an optional idempotency key. Returns {id, students, duplicate}.
DROP FUNCTION IF EXISTS public.send_notification(text, text, uuid, uuid, uuid, date);
CREATE OR REPLACE FUNCTION public.send_notification(
  p_title text, p_body text, p_company_id uuid DEFAULT NULL, p_line_id uuid DEFAULT NULL,
  p_trip_id uuid DEFAULT NULL, p_ride_date date DEFAULT NULL, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_supervisor boolean := public.is_supervisor();
  v_company uuid;
  v_sender text;
  v_spec jsonb;
  v_id uuid;
  v_duplicate boolean;
  v_students integer;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF char_length(btrim(COALESCE(p_title, ''))) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'اكتب عنواناً للإشعار (حتى 80 حرفاً).';
  END IF;
  IF char_length(btrim(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 600 THEN
    RAISE EXCEPTION 'اكتب نص الإشعار (حتى 600 حرف).';
  END IF;
  IF p_line_id IS NOT NULL THEN
    SELECT l.company_id INTO v_company FROM public.lines l WHERE l.id = p_line_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الخط غير موجود.'; END IF;
  END IF;

  IF v_supervisor THEN
    IF p_line_id IS NULL OR NOT EXISTS (
         SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id) THEN
      RAISE EXCEPTION 'اختر خطاً من الخطوط المسندة إليك.';
    END IF;
    SELECT s.full_name INTO v_sender FROM public.supervisors s WHERE s.id = v_me;
  ELSE
    IF COALESCE(v_company, p_company_id) IS NULL
       OR COALESCE(v_company, p_company_id) IS DISTINCT FROM COALESCE(p_company_id, v_company)
       OR NOT public.can_manage_company(COALESCE(v_company, p_company_id)) THEN
      RAISE EXCEPTION 'لا يمكنك إرسال إشعارات لهذه الشركة.';
    END IF;
    v_company := COALESCE(v_company, p_company_id);
    SELECT a.full_name INTO v_sender FROM public.admins a WHERE a.id = v_me;
  END IF;
  IF p_trip_id IS NULL AND p_ride_date IS NOT NULL THEN RAISE EXCEPTION 'اختر الرحلة.'; END IF;

  v_spec := public.notification_audience_resolve(v_company, CASE
    WHEN p_trip_id IS NOT NULL THEN jsonb_build_object('kind', 'trip', 'line_id', p_line_id, 'trip_id', p_trip_id,
                                                       'ride_date', p_ride_date)
    WHEN p_line_id IS NOT NULL THEN jsonb_build_object('kind', 'line', 'line_id', p_line_id)
    ELSE jsonb_build_object('kind', 'company') END, public.cairo_today());

  SELECT o_id, o_duplicate INTO v_id, v_duplicate FROM public.notification_create(
    v_company, v_me, CASE WHEN v_supervisor THEN 'supervisor' ELSE 'admin' END, v_sender,
    CASE WHEN v_supervisor THEN 'announcement.supervisor' ELSE 'announcement.admin' END, 'announcement', 'normal',
    p_title, p_body, NULL, NULL, v_spec, jsonb_build_object('route', 'notifications'), NULL, p_idempotency_key);
  IF v_duplicate THEN
    RETURN jsonb_build_object('id', v_id, 'duplicate', true, 'students',
      (SELECT count(*) FROM public.notification_recipients r WHERE r.notification_id = v_id AND r.is_student));
  END IF;
  PERFORM public.notification_rate_check(v_me, CASE WHEN v_supervisor THEN 12 ELSE 60 END);
  v_students := public.notification_deliver(v_id);
  IF v_students = 0 THEN RAISE EXCEPTION 'لا يوجد طلاب يصلهم هذا الإشعار.'; END IF;
  INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id, detail)
  VALUES (v_company, v_me, CASE WHEN v_supervisor THEN 'supervisor' ELSE 'admin' END, 'send', v_id,
          jsonb_build_object('audience', v_spec - 'label', 'students', v_students));
  RETURN jsonb_build_object('id', v_id, 'students', v_students, 'duplicate', false);
END;
$$;

-- The ready-made messages a supervisor may send.
CREATE OR REPLACE FUNCTION public.get_quick_notification_templates()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('key', t.key, 'title', t.title_ar, 'body', t.body_ar,
           'needs_minutes', t.needs_minutes, 'direction', t.direction) ORDER BY t.sort), '[]'::jsonb)
  FROM public.notification_templates t
  WHERE t.supervisor_quick AND public.is_supervisor()
$$;

-- A supervisor sends one of them to a line of their own, or to the riders of one
-- of its trips today or tomorrow. The text is the template's: nothing is typed.
CREATE OR REPLACE FUNCTION public.send_quick_notification(
  p_template_key text, p_line_id uuid, p_trip_id uuid DEFAULT NULL, p_ride_date date DEFAULT NULL,
  p_minutes integer DEFAULT NULL, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_t public.notification_templates%ROWTYPE;
  v_company uuid;
  v_spec jsonb;
  v_direction text;
  v_id uuid;
  v_duplicate boolean;
  v_students integer;
BEGIN
  IF NOT public.is_supervisor() THEN
    RAISE EXCEPTION 'هذه العملية متاحة لمشرفي الحافلات النشطين فقط.';
  END IF;
  SELECT * INTO v_t FROM public.notification_templates WHERE key = p_template_key AND supervisor_quick;
  IF NOT FOUND THEN RAISE EXCEPTION 'هذا الإشعار غير متاح.'; END IF;
  IF p_line_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id) THEN
    RAISE EXCEPTION 'اختر خطاً من الخطوط المسندة إليك.';
  END IF;
  SELECT l.company_id INTO v_company FROM public.lines l WHERE l.id = p_line_id;
  IF v_t.needs_minutes AND (p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 180) THEN
    RAISE EXCEPTION 'اكتب عدد الدقائق (من 1 إلى 180).';
  END IF;
  IF p_trip_id IS NULL AND p_ride_date IS NOT NULL THEN RAISE EXCEPTION 'اختر الرحلة.'; END IF;

  v_spec := public.notification_audience_resolve(v_company, CASE
    WHEN p_trip_id IS NOT NULL THEN jsonb_build_object('kind', 'trip', 'line_id', p_line_id, 'trip_id', p_trip_id,
                                                       'ride_date', p_ride_date)
    ELSE jsonb_build_object('kind', 'line', 'line_id', p_line_id) END, public.cairo_today());
  IF p_trip_id IS NOT NULL AND v_t.direction IS NOT NULL THEN
    SELECT t.direction INTO v_direction FROM public.line_trips t WHERE t.id = p_trip_id;
    IF v_direction IS DISTINCT FROM v_t.direction THEN
      RAISE EXCEPTION 'هذا الإشعار لا يناسب اتجاه الرحلة المختارة.';
    END IF;
  END IF;

  SELECT o_id, o_duplicate INTO v_id, v_duplicate FROM public.notification_create(
    v_company, v_me, 'supervisor', (SELECT s.full_name FROM public.supervisors s WHERE s.id = v_me),
    v_t.key, v_t.category, v_t.priority, v_t.title_ar,
    replace(v_t.body_ar, '{minutes}', COALESCE(p_minutes, 0)::text), v_t.title_en,
    replace(v_t.body_en, '{minutes}', COALESCE(p_minutes, 0)::text), v_spec,
    jsonb_strip_nulls(jsonb_build_object('route', v_t.route, 'line_id', p_line_id, 'trip_id', p_trip_id,
                                         'ride_date', v_spec->>'ride_date')),
    NULL, p_idempotency_key);
  IF v_duplicate THEN
    RETURN jsonb_build_object('id', v_id, 'duplicate', true, 'students',
      (SELECT count(*) FROM public.notification_recipients r WHERE r.notification_id = v_id AND r.is_student));
  END IF;

  PERFORM public.notification_rate_check(v_me, 12);
  -- The same message to the same riders twice in a row is a slip of the finger.
  IF EXISTS (SELECT 1 FROM public.notifications n
             WHERE n.sender_id = v_me AND n.id <> v_id AND n.type = v_t.key AND n.status = 'sent'
               AND n.line_id = p_line_id AND n.trip_id IS NOT DISTINCT FROM p_trip_id
               AND n.sent_at > now() - interval '2 minutes') THEN
    RAISE EXCEPTION 'أرسلت هذا الإشعار قبل قليل. انتظر دقيقتين قبل إرساله مرة أخرى.';
  END IF;
  v_students := public.notification_deliver(v_id);
  IF v_students = 0 THEN RAISE EXCEPTION 'لا يوجد طلاب يصلهم هذا الإشعار.'; END IF;
  INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id, detail)
  VALUES (v_company, v_me, 'supervisor', 'send', v_id,
          jsonb_build_object('template', v_t.key, 'audience', v_spec - 'label', 'minutes', p_minutes,
                             'students', v_students));
  RETURN jsonb_build_object('id', v_id, 'students', v_students, 'duplicate', false);
END;
$$;

-- Dashboard: who an audience is right now, before anything is sent.
CREATE OR REPLACE FUNCTION public.preview_notification_audience(p_company_id uuid, p_audience jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_spec jsonb;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك إرسال إشعارات لهذه الشركة.';
  END IF;
  IF COALESCE(p_audience->>'kind', '') = 'user' THEN RAISE EXCEPTION 'اختر من يصلهم الإشعار.'; END IF;
  v_spec := public.notification_audience_resolve(p_company_id, p_audience, public.cairo_today());
  RETURN (
    SELECT jsonb_build_object('label', v_spec->>'label',
      'students', count(*) FILTER (WHERE u.is_student),
      'supervisors', count(*) FILTER (WHERE NOT u.is_student),
      'devices', (SELECT count(*) FROM public.push_devices d
                  WHERE d.disabled_at IS NULL AND d.user_id IN (
                    SELECT x.user_id FROM public.notification_audience_users(p_company_id, v_spec, auth.uid()) x)))
    FROM public.notification_audience_users(p_company_id, v_spec, auth.uid()) u);
END;
$$;

-- Dashboard: send now, or at p_scheduled_at. Returns {id, status, students, duplicate}.
CREATE OR REPLACE FUNCTION public.compose_notification(
  p_company_id uuid, p_title text, p_body text, p_audience jsonb, p_scheduled_at timestamptz DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL, p_priority text DEFAULT 'normal')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_spec jsonb;
  v_id uuid;
  v_duplicate boolean;
  v_students integer;
  v_status text;
BEGIN
  IF v_me IS NULL OR NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك إرسال إشعارات لهذه الشركة.';
  END IF;
  IF char_length(btrim(COALESCE(p_title, ''))) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'اكتب عنواناً للإشعار (حتى 80 حرفاً).';
  END IF;
  IF char_length(btrim(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 600 THEN
    RAISE EXCEPTION 'اكتب نص الإشعار (حتى 600 حرف).';
  END IF;
  IF COALESCE(p_priority, 'normal') NOT IN ('normal', 'high') THEN RAISE EXCEPTION 'أولوية غير صحيحة.'; END IF;
  IF COALESCE(p_audience->>'kind', '') = 'user' THEN RAISE EXCEPTION 'اختر من يصلهم الإشعار.'; END IF;
  IF p_scheduled_at IS NOT NULL AND p_scheduled_at NOT BETWEEN now() + interval '1 minute' AND now() + interval '60 days' THEN
    RAISE EXCEPTION 'اختر موعداً قادماً خلال 60 يوماً.';
  END IF;
  v_spec := public.notification_audience_resolve(p_company_id, p_audience,
    COALESCE((p_scheduled_at AT TIME ZONE 'Africa/Cairo')::date, public.cairo_today()));

  SELECT o_id, o_duplicate INTO v_id, v_duplicate FROM public.notification_create(
    p_company_id, v_me, 'admin', (SELECT a.full_name FROM public.admins a WHERE a.id = v_me),
    'announcement.admin', 'announcement', COALESCE(p_priority, 'normal'), p_title, p_body, NULL, NULL, v_spec,
    jsonb_build_object('route', 'notifications'), p_scheduled_at, p_idempotency_key);
  IF v_duplicate THEN
    SELECT n.status INTO v_status FROM public.notifications n WHERE n.id = v_id;
    RETURN jsonb_build_object('id', v_id, 'status', v_status, 'duplicate', true, 'students',
      (SELECT count(*) FROM public.notification_recipients r WHERE r.notification_id = v_id AND r.is_student));
  END IF;
  PERFORM public.notification_rate_check(v_me, 60);

  IF p_scheduled_at IS NULL THEN
    v_students := public.notification_deliver(v_id);
    IF v_students = 0 THEN RAISE EXCEPTION 'لا يوجد طلاب يصلهم هذا الإشعار.'; END IF;
  ELSE
    SELECT count(*) INTO v_students
    FROM public.notification_audience_users(p_company_id, v_spec, v_me) u WHERE u.is_student;
  END IF;
  INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id, detail)
  VALUES (p_company_id, v_me, 'admin', CASE WHEN p_scheduled_at IS NULL THEN 'send' ELSE 'schedule' END, v_id,
          jsonb_build_object('audience', v_spec - 'label', 'students', v_students, 'scheduled_at', p_scheduled_at));
  RETURN jsonb_build_object('id', v_id, 'status', CASE WHEN p_scheduled_at IS NULL THEN 'sent' ELSE 'scheduled' END,
                            'students', v_students, 'duplicate', false);
END;
$$;

-- Dashboard: change what is still waiting to be sent.
CREATE OR REPLACE FUNCTION public.update_scheduled_notification(
  p_id uuid, p_title text, p_body text, p_audience jsonb, p_scheduled_at timestamptz)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n public.notifications%ROWTYPE;
  v_spec jsonb;
BEGIN
  SELECT * INTO v_n FROM public.notifications WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR NOT public.can_manage_company(v_n.company_id) THEN
    RAISE EXCEPTION 'لا يمكنك تعديل هذا الإشعار.';
  END IF;
  IF v_n.status <> 'scheduled' THEN RAISE EXCEPTION 'لا يمكن تعديل إشعار بعد إرساله أو إلغائه.'; END IF;
  IF char_length(btrim(COALESCE(p_title, ''))) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'اكتب عنواناً للإشعار (حتى 80 حرفاً).';
  END IF;
  IF char_length(btrim(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 600 THEN
    RAISE EXCEPTION 'اكتب نص الإشعار (حتى 600 حرف).';
  END IF;
  IF COALESCE(p_audience->>'kind', '') = 'user' THEN RAISE EXCEPTION 'اختر من يصلهم الإشعار.'; END IF;
  IF p_scheduled_at IS NULL OR p_scheduled_at NOT BETWEEN now() + interval '1 minute' AND now() + interval '60 days' THEN
    RAISE EXCEPTION 'اختر موعداً قادماً خلال 60 يوماً.';
  END IF;
  v_spec := public.notification_audience_resolve(v_n.company_id, p_audience,
                                                 (p_scheduled_at AT TIME ZONE 'Africa/Cairo')::date);
  UPDATE public.notifications SET
    title = btrim(p_title), body = btrim(p_body), scheduled_at = p_scheduled_at, audience = v_spec->>'label',
    audience_spec = v_spec - 'label', line_id = (v_spec->>'line_id')::uuid, trip_id = (v_spec->>'trip_id')::uuid,
    ride_date = (v_spec->>'ride_date')::date
  WHERE id = p_id;
  INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id, detail)
  VALUES (v_n.company_id, auth.uid(), 'admin', 'reschedule', p_id,
          jsonb_build_object('audience', v_spec - 'label', 'scheduled_at', p_scheduled_at));
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_scheduled_notification(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n public.notifications%ROWTYPE;
BEGIN
  SELECT * INTO v_n FROM public.notifications WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR NOT public.can_manage_company(v_n.company_id) THEN
    RAISE EXCEPTION 'لا يمكنك إلغاء هذا الإشعار.';
  END IF;
  IF v_n.status <> 'scheduled' THEN RAISE EXCEPTION 'هذا الإشعار أُرسل أو أُلغي من قبل.'; END IF;
  UPDATE public.notifications SET status = 'cancelled' WHERE id = p_id;
  INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id)
  VALUES (v_n.company_id, auth.uid(), 'admin', 'cancel', p_id);
END;
$$;

-- As before, and it leaves a trace.
CREATE OR REPLACE FUNCTION public.delete_notification(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_n public.notifications%ROWTYPE;
BEGIN
  SELECT * INTO v_n FROM public.notifications WHERE id = p_id;
  IF NOT FOUND OR NOT public.can_manage_company(v_n.company_id) THEN
    RAISE EXCEPTION 'لا يمكنك حذف هذا الإشعار.';
  END IF;
  DELETE FROM public.notifications WHERE id = p_id;
  INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id, detail)
  VALUES (v_n.company_id, auth.uid(), 'admin', 'delete', p_id,
          jsonb_build_object('type', v_n.type, 'title', v_n.title, 'sender_id', v_n.sender_id, 'sent_at', v_n.sent_at));
END;
$$;

-- Dashboard history, newest first, a page at a time, with true counts.
CREATE OR REPLACE FUNCTION public.get_company_notifications_page(
  p_company_id uuid, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 30, p_status text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_items jsonb;
  v_count integer;
BEGIN
  IF NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'لا يمكنك عرض إشعارات هذه الشركة.';
  END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb), count(*) INTO v_items, v_count
  FROM (
    SELECT n.id, n.type, n.category, n.priority, n.title, n.body, n.created_at, n.scheduled_at, n.sent_at,
           n.status, n.status_note, n.sender_role, n.sender_name, n.audience, n.audience_spec, n.line_id,
           (SELECT count(*) FROM public.notification_recipients r
            WHERE r.notification_id = n.id AND r.is_student) AS students,
           (SELECT count(*) FROM public.notification_recipients r
            WHERE r.notification_id = n.id AND r.is_student AND r.read_at IS NOT NULL) AS read,
           (SELECT count(*) FROM public.notification_recipients r
            WHERE r.notification_id = n.id AND r.is_student AND r.opened_at IS NOT NULL) AS opened,
           (SELECT jsonb_build_object(
              'devices', count(*),
              'queued', count(*) FILTER (WHERE o.status IN ('queued', 'sending')),
              'accepted', count(*) FILTER (WHERE o.status = 'accepted'),
              'failed', count(*) FILTER (WHERE o.status IN ('failed', 'expired')),
              'skipped', count(*) FILTER (WHERE o.status = 'skipped'))
            FROM public.push_outbox o WHERE o.notification_id = n.id) AS push
    FROM public.notifications n
    WHERE n.company_id = p_company_id
      AND (p_before IS NULL OR n.created_at < p_before)
      AND (p_status IS NULL OR n.status = p_status)
      -- Never sent and not scheduled: a send that found nobody and was rolled forward.
      AND NOT (n.status = 'failed' AND n.scheduled_at IS NULL)
    ORDER BY n.created_at DESC
    LIMIT v_limit + 1
  ) x;
  IF v_count > v_limit THEN
    -- The extra row only says there is more.
    v_items := v_items - v_limit;
  END IF;
  RETURN jsonb_build_object('items', v_items,
    'next_before', CASE WHEN v_count > v_limit THEN (v_items->(v_limit - 1))->>'created_at' END,
    'push_configured', (SELECT r.configured FROM public.push_runtime r WHERE r.id));
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. The app reads
-- ------------------------------------------------------------------------------
-- One notification as the app shows it. created_at is when it reached people.
CREATE OR REPLACE FUNCTION public.notification_item(n public.notifications, p_read boolean)
RETURNS jsonb
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT jsonb_build_object('id', n.id, 'type', n.type, 'category', n.category, 'priority', n.priority,
    'title', n.title, 'body', n.body, 'title_en', n.title_en, 'body_en', n.body_en,
    'created_at', COALESCE(n.sent_at, n.created_at), 'sender_role', n.sender_role, 'sender_name', n.sender_name,
    'audience', n.audience, 'read', p_read, 'mine', n.sender_id IS NOT DISTINCT FROM auth.uid(), 'data', n.data)
$$;
REVOKE ALL ON FUNCTION public.notification_item(public.notifications, boolean) FROM PUBLIC, anon, authenticated;

-- As before (60 days, newest first), only what was really sent, with the new fields.
CREATE OR REPLACE FUNCTION public.get_my_notifications(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.at DESC), '[]'::jsonb)
  FROM (
    SELECT public.notification_item(n, r.user_id IS NULL OR r.read_at IS NOT NULL) AS item, n.sent_at AS at
    FROM public.notifications n
    LEFT JOIN public.notification_recipients r ON r.notification_id = n.id AND r.user_id = auth.uid()
    WHERE auth.uid() IS NOT NULL AND n.status = 'sent'
      AND (r.user_id IS NOT NULL OR n.sender_id = auth.uid())
      AND n.sent_at > now() - interval '60 days'
    ORDER BY n.sent_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200)
  ) x
$$;

CREATE OR REPLACE FUNCTION public.get_my_unread_count()
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::integer
  FROM public.notification_recipients r
  JOIN public.notifications n ON n.id = r.notification_id
  WHERE r.user_id = auth.uid() AND r.read_at IS NULL AND n.status = 'sent'
    AND n.sent_at > now() - interval '90 days'
$$;

-- The signed-in user's notifications of the last 90 days, a page at a time:
-- {items, unread, next_before}. Pass next_before back for the next page.
CREATE OR REPLACE FUNCTION public.get_my_notifications_page(
  p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 30, p_unread_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_items jsonb;
  v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('items', '[]'::jsonb, 'unread', 0, 'next_before', NULL);
  END IF;
  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.at DESC), '[]'::jsonb), count(*) INTO v_items, v_count
  FROM (
    SELECT public.notification_item(n, r.user_id IS NULL OR r.read_at IS NOT NULL) AS item, n.sent_at AS at
    FROM public.notifications n
    LEFT JOIN public.notification_recipients r ON r.notification_id = n.id AND r.user_id = auth.uid()
    WHERE n.status = 'sent'
      AND (r.user_id IS NOT NULL OR n.sender_id = auth.uid())
      AND n.sent_at > now() - interval '90 days'
      AND (p_before IS NULL OR n.sent_at < p_before)
      AND (NOT COALESCE(p_unread_only, false) OR (r.user_id IS NOT NULL AND r.read_at IS NULL))
    ORDER BY n.sent_at DESC
    LIMIT v_limit + 1
  ) x;
  IF v_count > v_limit THEN
    v_items := v_items - v_limit;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'unread', public.get_my_unread_count(),
    'next_before', CASE WHEN v_count > v_limit THEN (v_items->(v_limit - 1))->>'created_at' END);
END;
$$;

-- Marks the signed-in user's notifications read (those in p_ids, or all) and
-- tells their other devices.
CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids uuid[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  UPDATE public.notification_recipients
  SET read_at = now()
  WHERE user_id = auth.uid() AND read_at IS NULL
    AND (p_ids IS NULL OR notification_id = ANY (p_ids));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    PERFORM public.announce('user:' || auth.uid(), jsonb_build_object('table', 'notifications', 'op', 'READ'));
  END IF;
  RETURN v_count;
END;
$$;

-- The user tapped the push or the banner: opened, and so read.
CREATE OR REPLACE FUNCTION public.notification_opened(p_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_was_unread boolean;
BEGIN
  SELECT r.read_at IS NULL INTO v_was_unread FROM public.notification_recipients r
  WHERE r.notification_id = p_id AND r.user_id = auth.uid();
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE public.notification_recipients
  SET opened_at = COALESCE(opened_at, now()), read_at = COALESCE(read_at, now())
  WHERE notification_id = p_id AND user_id = auth.uid();
  IF v_was_unread THEN
    PERFORM public.announce('user:' || auth.uid(), jsonb_build_object('table', 'notifications', 'op', 'READ'));
  END IF;
END;
$$;

-- ------------------------------------------------------------------------------
-- 9. Devices and preferences
-- ------------------------------------------------------------------------------
-- This install's push token now belongs to the signed-in account, and to no other.
CREATE OR REPLACE FUNCTION public.register_push_device(
  p_installation_id text, p_platform text, p_token text, p_locale text DEFAULT 'ar', p_app_version text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_platform NOT IN ('ios', 'android') OR char_length(COALESCE(p_installation_id, '')) NOT BETWEEN 8 AND 100
     OR char_length(COALESCE(p_token, '')) NOT BETWEEN 20 AND 4096 THEN
    RAISE EXCEPTION 'Invalid device';
  END IF;
  -- The device or the token under any other account, or the token under another
  -- install of this account (a reinstall).
  DELETE FROM public.push_devices d
  WHERE (d.user_id <> v_me AND (d.token = p_token OR d.installation_id = p_installation_id))
     OR (d.user_id = v_me AND d.token = p_token AND d.installation_id <> p_installation_id);
  INSERT INTO public.push_devices(user_id, installation_id, platform, token, locale, app_version)
  VALUES (v_me, p_installation_id, p_platform, p_token,
          COALESCE(NULLIF(left(btrim(p_locale), 10), ''), 'ar'), left(p_app_version, 40))
  ON CONFLICT (user_id, installation_id) DO UPDATE SET
    platform = EXCLUDED.platform, token = EXCLUDED.token, locale = EXCLUDED.locale,
    app_version = EXCLUDED.app_version, last_seen_at = now(),
    -- A new token is a fresh start; the same one stays as the provider judged it.
    disabled_at = CASE WHEN public.push_devices.token = EXCLUDED.token THEN public.push_devices.disabled_at END,
    disabled_reason = CASE WHEN public.push_devices.token = EXCLUDED.token THEN public.push_devices.disabled_reason END;
  -- Ten devices an account are plenty: the ones unseen longest go.
  DELETE FROM public.push_devices d
  WHERE d.user_id = v_me AND d.id IN (
    SELECT x.id FROM public.push_devices x WHERE x.user_id = v_me ORDER BY x.last_seen_at DESC OFFSET 10);
END;
$$;

-- Signing out on this device: no more push for this account here.
CREATE OR REPLACE FUNCTION public.unregister_push_device(p_installation_id text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.push_devices WHERE user_id = auth.uid() AND installation_id = p_installation_id
$$;

CREATE OR REPLACE FUNCTION public.get_notification_preferences()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'push_enabled', COALESCE((SELECT p.push_enabled FROM public.notification_preferences p WHERE p.user_id = auth.uid()), true),
    'categories', (
      SELECT jsonb_object_agg(c, COALESCE(
        ((SELECT p.categories FROM public.notification_preferences p WHERE p.user_id = auth.uid())->>c)::boolean, true))
      FROM unnest(ARRAY['subscription', 'transport', 'announcement', 'reminder']) c))
$$;

-- These silence push only: the inbox always receives everything.
CREATE OR REPLACE FUNCTION public.set_notification_preferences(p_push_enabled boolean, p_categories jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_categories jsonb;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- Known categories with true/false only.
  SELECT COALESCE(jsonb_object_agg(e.key, e.value), '{}'::jsonb) INTO v_categories
  FROM jsonb_each(CASE WHEN jsonb_typeof(p_categories) = 'object' THEN p_categories ELSE '{}'::jsonb END) e
  WHERE e.key IN ('subscription', 'transport', 'announcement', 'reminder') AND jsonb_typeof(e.value) = 'boolean';
  INSERT INTO public.notification_preferences(user_id, push_enabled, categories)
  VALUES (v_me, COALESCE(p_push_enabled, true), v_categories)
  ON CONFLICT (user_id) DO UPDATE SET
    push_enabled = COALESCE(p_push_enabled, public.notification_preferences.push_enabled),
    categories = public.notification_preferences.categories || EXCLUDED.categories, updated_at = now();
  RETURN public.get_notification_preferences();
END;
$$;

-- ------------------------------------------------------------------------------
-- 10. The dispatcher's side (service role only)
-- ------------------------------------------------------------------------------
-- Hands out due pushes and marks them as being sent. Ones stuck in sending go
-- back to the queue; ones a day old are given up.
CREATE OR REPLACE FUNCTION public.claim_push_outbox(p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rows jsonb;
BEGIN
  UPDATE public.push_outbox SET status = 'queued', updated_at = now()
  WHERE status = 'sending' AND claimed_at < now() - interval '5 minutes';
  UPDATE public.push_outbox SET status = 'expired', updated_at = now()
  WHERE status = 'queued' AND created_at < now() - interval '24 hours';

  WITH due AS (
    SELECT o.id FROM public.push_outbox o
    WHERE o.status = 'queued' AND o.next_attempt_at <= now()
    ORDER BY o.id
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500)
    FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.push_outbox o SET status = 'sending', attempts = o.attempts + 1, claimed_at = now(), updated_at = now()
    FROM due WHERE o.id = due.id
    RETURNING o.id, o.notification_id, o.user_id, o.device_id, o.attempts
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', c.id, 'notification_id', c.notification_id, 'token', d.token, 'platform', d.platform,
      'locale', d.locale, 'type', n.type, 'title', n.title, 'body', n.body, 'title_en', n.title_en,
      'body_en', n.body_en, 'data', n.data, 'category', n.category, 'priority', n.priority, 'attempts', c.attempts,
      'badge', (SELECT count(*) FROM public.notification_recipients r
                JOIN public.notifications x ON x.id = r.notification_id AND x.status = 'sent'
                WHERE r.user_id = c.user_id AND r.read_at IS NULL)) ORDER BY c.id), '[]'::jsonb)
  INTO v_rows
  FROM claimed c
  JOIN public.push_devices d ON d.id = c.device_id
  JOIN public.notifications n ON n.id = c.notification_id;
  RETURN v_rows;
END;
$$;

-- What became of them: [{id, status: accepted | failed | retry | invalid_token, message_id?, error?}].
CREATE OR REPLACE FUNCTION public.complete_push_outbox(p_results jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_r jsonb;
  v_row public.push_outbox%ROWTYPE;
  v_status text;
BEGIN
  FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_results, '[]'::jsonb)) LOOP
    SELECT * INTO v_row FROM public.push_outbox WHERE id = (v_r->>'id')::bigint AND status = 'sending' FOR UPDATE;
    CONTINUE WHEN NOT FOUND;
    v_status := v_r->>'status';
    IF v_status = 'accepted' THEN
      UPDATE public.push_outbox SET status = 'accepted', provider_message_id = left(v_r->>'message_id', 300),
             last_error = NULL, updated_at = now() WHERE id = v_row.id;
    ELSIF v_status = 'retry' AND (v_r->>'error') ~ '^(auth:|not_sent:)' THEN
      -- Never reached the provider (our credentials, or out of time): not an attempt.
      UPDATE public.push_outbox SET status = 'queued', attempts = GREATEST(v_row.attempts - 1, 0),
             last_error = left(v_r->>'error', 300), next_attempt_at = now() + interval '2 minutes', updated_at = now()
      WHERE id = v_row.id;
    ELSIF v_status = 'retry' AND v_row.attempts < 5 THEN
      UPDATE public.push_outbox SET status = 'queued', last_error = left(v_r->>'error', 300), updated_at = now(),
             next_attempt_at = now() + (ARRAY['1 minute', '5 minutes', '15 minutes', '1 hour'])[v_row.attempts]::interval
      WHERE id = v_row.id;
    ELSE
      UPDATE public.push_outbox SET status = 'failed', last_error = left(COALESCE(v_r->>'error', v_status), 300),
             updated_at = now() WHERE id = v_row.id;
      IF v_status = 'invalid_token' THEN
        UPDATE public.push_devices SET disabled_at = now(), disabled_reason = left(COALESCE(v_r->>'error', 'invalid_token'), 200)
        WHERE id = v_row.device_id;
      END IF;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_push_configured(p_configured boolean)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.push_runtime SET configured = p_configured, checked_at = now() WHERE id
$$;

-- ------------------------------------------------------------------------------
-- 11. Every minute
-- ------------------------------------------------------------------------------
-- The day's work: tells students whose subscription ends in 3 days or ended
-- yesterday (once each, however often it runs) and clears what is old.
CREATE OR REPLACE FUNCTION public.notifications_daily()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_sub record;
BEGIN
  FOR v_sub IN SELECT s.id, s.company_id, s.student_id, s.end_date FROM public.subscriptions s
               WHERE s.status = 'active' AND s.end_date IN (v_today + 3, v_today - 1) LOOP
    PERFORM public.notify_student(v_sub.company_id, v_sub.student_id,
      CASE WHEN v_sub.end_date > v_today THEN 'subscription.expiring' ELSE 'subscription.expired' END,
      jsonb_build_object('subscription_id', v_sub.id),
      CASE WHEN v_sub.end_date > v_today THEN 'expiring:' ELSE 'expired:' END || v_sub.id);
  END LOOP;
  -- The app shows 90 days; the dashboard keeps half a year.
  DELETE FROM public.notifications
  WHERE status <> 'scheduled' AND COALESCE(sent_at, created_at) < now() - interval '180 days';
  DELETE FROM public.push_outbox WHERE created_at < now() - interval '30 days';
  DELETE FROM public.push_devices WHERE last_seen_at < now() - interval '180 days';
  DELETE FROM public.notification_audit WHERE at < now() - interval '2 years';
END;
$$;
REVOKE ALL ON FUNCTION public.notifications_daily() FROM PUBLIC, anon, authenticated;

-- Sends what is due, does the day's work once (from 9 in the morning, Cairo),
-- and wakes the dispatcher while pushes are waiting. Safe to call at any time.
CREATE OR REPLACE FUNCTION public.notifications_tick()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today date := public.cairo_today();
  v_id uuid;
BEGIN
  FOR v_id IN SELECT n.id FROM public.notifications n
              WHERE n.status = 'scheduled' AND n.scheduled_at <= now() ORDER BY n.scheduled_at LOOP
    BEGIN
      IF public.notification_deliver(v_id) = 0 THEN
        UPDATE public.notifications SET status = 'failed', status_note = 'لم يكن هناك طلاب يصلهم الإشعار وقت الإرسال.'
        WHERE id = v_id AND status = 'scheduled';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'scheduled notification % failed: %', v_id, SQLERRM;
      UPDATE public.notifications SET status = 'failed', status_note = 'تعذّر الإرسال.' WHERE id = v_id AND status = 'scheduled';
    END;
  END LOOP;

  IF (SELECT r.last_daily IS DISTINCT FROM v_today FROM public.push_runtime r WHERE r.id)
     AND (now() AT TIME ZONE 'Africa/Cairo')::time >= '09:00' THEN
    UPDATE public.push_runtime SET last_daily = v_today WHERE id;
    PERFORM public.notifications_daily();
  END IF;

  IF EXISTS (SELECT 1 FROM public.push_outbox o WHERE o.status = 'queued' AND o.next_attempt_at <= now()) THEN
    PERFORM public.push_kick();
  END IF;
END;
$$;

-- ------------------------------------------------------------------------------
-- 12. Who may call what
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.send_notification(text, text, uuid, uuid, uuid, date, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_quick_notification_templates() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_quick_notification(text, uuid, uuid, date, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.preview_notification_audience(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.compose_notification(uuid, text, text, jsonb, timestamptz, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_scheduled_notification(uuid, text, text, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_scheduled_notification(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_company_notifications_page(uuid, timestamptz, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_unread_count() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_notifications_page(timestamptz, integer, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.notification_opened(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_push_device(text, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_push_device(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_notification_preferences() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_notification_preferences(boolean, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_notification(text, text, uuid, uuid, uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_quick_notification_templates() TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_quick_notification(text, uuid, uuid, date, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_notification_audience(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compose_notification(uuid, text, text, jsonb, timestamptz, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_scheduled_notification(uuid, text, text, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_scheduled_notification(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_notifications_page(uuid, timestamptz, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_unread_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_notifications_page(timestamptz, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notification_opened(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_device(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_preferences() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_notification_preferences(boolean, jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.claim_push_outbox(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_push_outbox(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_push_configured(boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notifications_tick() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_push_outbox(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_push_outbox(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_push_configured(boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.notifications_tick() TO service_role;

COMMIT;

-- The minute tick, where pg_cron can be had (outside the transaction above: a
-- database without it keeps everything else; the tick can then be called from
-- anywhere with the service role).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'basak-notifications-tick';
    PERFORM cron.schedule('basak-notifications-tick', '* * * * *', 'SELECT public.notifications_tick()');
  ELSE
    RAISE NOTICE 'pg_cron is not available: schedule public.notifications_tick() another way.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'could not schedule the notifications tick: %', SQLERRM;
END;
$$;
