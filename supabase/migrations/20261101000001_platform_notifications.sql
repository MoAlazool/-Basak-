-- ==============================================================================
-- Migration: 20261101000001_platform_notifications.sql
-- Run AFTER 20261031000001. Safe to re-run.
--
-- The platform (super admin) writes to the students of every company, or of the
-- companies it picks, and sees what every company sent. A notification still
-- belongs to one company: a platform send is one notification per company, so
-- each company's admins see it in their own history and nothing crosses tenants.
-- ==============================================================================
BEGIN;

-- As 20261031000001, and the platform's dashboard hears of every notification.
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
  PERFORM public.announce('platform', v_payload);
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

-- The companies a platform send goes to: the active ones, or those picked.
CREATE OR REPLACE FUNCTION public.platform_notification_companies(p_company_ids uuid[])
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c.id FROM public.companies c
  WHERE public.company_is_active(c.id) AND (p_company_ids IS NULL OR c.id = ANY (p_company_ids))
$$;
REVOKE ALL ON FUNCTION public.platform_notification_companies(uuid[]) FROM PUBLIC, anon, authenticated;

-- Who a platform send would reach right now.
CREATE OR REPLACE FUNCTION public.platform_preview_notification(p_company_ids uuid[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'هذه الصفحة لإدارة المنصة فقط.'; END IF;
  RETURN (
    WITH reached AS (
      SELECT c.id AS company_id, u.user_id, u.is_student
      FROM public.platform_notification_companies(p_company_ids) c(id),
           LATERAL public.notification_audience_users(c.id, '{"kind": "company"}'::jsonb, auth.uid()) u
    )
    SELECT jsonb_build_object(
      'companies', (SELECT count(DISTINCT r.company_id) FROM reached r WHERE r.is_student),
      'students', (SELECT count(DISTINCT r.user_id) FROM reached r WHERE r.is_student),
      'supervisors', (SELECT count(DISTINCT r.user_id) FROM reached r WHERE NOT r.is_student),
      'devices', (SELECT count(*) FROM public.push_devices d
                  WHERE d.disabled_at IS NULL AND d.user_id IN (SELECT r.user_id FROM reached r))));
END;
$$;

-- Sends now, or at p_scheduled_at, to every student of those companies: one
-- notification per company that has somebody to receive it.
-- Returns {status, companies, students, duplicate}.
CREATE OR REPLACE FUNCTION public.platform_compose_notification(
  p_title text, p_body text, p_company_ids uuid[] DEFAULT NULL, p_scheduled_at timestamptz DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL, p_priority text DEFAULT 'normal')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_company uuid;
  v_spec jsonb;
  v_id uuid;
  v_duplicate boolean;
  v_count integer;
  v_companies integer := 0;
  v_students integer := 0;
  v_any_duplicate boolean := false;
BEGIN
  IF v_me IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'هذه الصفحة لإدارة المنصة فقط.'; END IF;
  IF char_length(btrim(COALESCE(p_title, ''))) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'اكتب عنواناً للإشعار (حتى 80 حرفاً).';
  END IF;
  IF char_length(btrim(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 600 THEN
    RAISE EXCEPTION 'اكتب نص الإشعار (حتى 600 حرف).';
  END IF;
  IF COALESCE(p_priority, 'normal') NOT IN ('normal', 'high') THEN RAISE EXCEPTION 'أولوية غير صحيحة.'; END IF;
  IF p_scheduled_at IS NOT NULL AND p_scheduled_at NOT BETWEEN now() + interval '1 minute' AND now() + interval '60 days' THEN
    RAISE EXCEPTION 'اختر موعداً قادماً خلال 60 يوماً.';
  END IF;

  FOR v_company IN SELECT c FROM public.platform_notification_companies(p_company_ids) c LOOP
    SELECT count(*) INTO v_count
    FROM public.notification_audience_users(v_company, '{"kind": "company"}'::jsonb, v_me) u WHERE u.is_student;
    CONTINUE WHEN v_count = 0;
    v_spec := public.notification_audience_resolve(v_company, '{"kind": "company"}'::jsonb, public.cairo_today());
    SELECT o_id, o_duplicate INTO v_id, v_duplicate FROM public.notification_create(
      v_company, v_me, 'admin', 'منصة باصك', 'announcement.platform', 'announcement', COALESCE(p_priority, 'normal'),
      p_title, p_body, NULL, NULL, v_spec, jsonb_build_object('route', 'notifications'), p_scheduled_at, p_idempotency_key);
    v_companies := v_companies + 1;
    v_students := v_students + v_count;
    IF v_duplicate THEN v_any_duplicate := true; CONTINUE; END IF;
    IF p_scheduled_at IS NULL THEN PERFORM public.notification_deliver(v_id); END IF;
    INSERT INTO public.notification_audit(company_id, actor_id, actor_role, action, notification_id, detail)
    VALUES (v_company, v_me, 'platform', CASE WHEN p_scheduled_at IS NULL THEN 'send' ELSE 'schedule' END, v_id,
            jsonb_build_object('students', v_count, 'scheduled_at', p_scheduled_at));
  END LOOP;
  IF v_companies = 0 THEN RAISE EXCEPTION 'لا يوجد طلاب يصلهم هذا الإشعار.'; END IF;
  RETURN jsonb_build_object('status', CASE WHEN p_scheduled_at IS NULL THEN 'sent' ELSE 'scheduled' END,
                            'companies', v_companies, 'students', v_students, 'duplicate', v_any_duplicate);
END;
$$;

-- Everything sent in every company (or one), newest first, with the state of push.
CREATE OR REPLACE FUNCTION public.get_platform_notifications_page(
  p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 30, p_status text DEFAULT NULL, p_company_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_items jsonb;
  v_count integer;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'هذه الصفحة لإدارة المنصة فقط.'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb), count(*) INTO v_items, v_count
  FROM (
    SELECT n.id, n.company_id, c.name AS company_name, n.type, n.category, n.priority, n.title, n.body, n.created_at,
           n.scheduled_at, n.sent_at, n.status, n.status_note, n.sender_role, n.sender_name, n.audience,
           n.audience_spec, n.line_id,
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
    JOIN public.companies c ON c.id = n.company_id
    WHERE (p_company_id IS NULL OR n.company_id = p_company_id)
      AND (p_before IS NULL OR n.created_at < p_before)
      AND (p_status IS NULL OR n.status = p_status)
      AND NOT (n.status = 'failed' AND n.scheduled_at IS NULL)
    ORDER BY n.created_at DESC
    LIMIT v_limit + 1
  ) x;
  IF v_count > v_limit THEN v_items := v_items - v_limit; END IF;
  RETURN jsonb_build_object('items', v_items,
    'next_before', CASE WHEN v_count > v_limit THEN (v_items->(v_limit - 1))->>'created_at' END,
    'push', (SELECT jsonb_build_object(
        'configured', (SELECT r.configured FROM public.push_runtime r WHERE r.id),
        'devices', (SELECT count(*) FROM public.push_devices d WHERE d.disabled_at IS NULL),
        'ios', (SELECT count(*) FROM public.push_devices d WHERE d.disabled_at IS NULL AND d.platform = 'ios'),
        'android', (SELECT count(*) FROM public.push_devices d WHERE d.disabled_at IS NULL AND d.platform = 'android'),
        'queued', (SELECT count(*) FROM public.push_outbox o WHERE o.status IN ('queued', 'sending')),
        'accepted_24h', (SELECT count(*) FROM public.push_outbox o
                         WHERE o.status = 'accepted' AND o.updated_at > now() - interval '24 hours'),
        'failed_24h', (SELECT count(*) FROM public.push_outbox o
                       WHERE o.status IN ('failed', 'expired') AND o.updated_at > now() - interval '24 hours'))));
END;
$$;

REVOKE ALL ON FUNCTION public.platform_preview_notification(uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_compose_notification(text, text, uuid[], timestamptz, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_platform_notifications_page(timestamptz, integer, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_preview_notification(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_compose_notification(text, text, uuid[], timestamptz, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_platform_notifications_page(timestamptz, integer, text, uuid) TO authenticated;

COMMIT;
