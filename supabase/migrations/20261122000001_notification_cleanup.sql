-- ==============================================================================
-- Migration: 20261122000001_notification_cleanup.sql
-- Run AFTER 20261119000006. Safe to re-run. Additive.
--
-- 1. A user removes notifications from their own inbox (one, several, or all).
--    The notification itself stays for everyone else it went to; only this
--    user's copy is hidden (and counted as read).
-- 2. Notifications do not pile up: what a company, a supervisor or the
--    platform sent (announcements, bus movement) is deleted 7 days after it
--    went out; the system's own notices about a subscription after 30 days.
--    Deleted for good: from every inbox and from the dashboards' history.
--    Scheduled notifications that have not gone out yet are never touched.
-- ==============================================================================
BEGIN;

ALTER TABLE public.notification_recipients ADD COLUMN IF NOT EXISTS hidden_at timestamptz;

-- ------------------------------------------------------------------------------
-- 1. Removing from the inbox. p_ids NULL = everything in it.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_my_notifications(p_ids uuid[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.notification_recipients
  SET hidden_at = now(), read_at = COALESCE(read_at, now())
  WHERE user_id = auth.uid() AND hidden_at IS NULL
    AND (p_ids IS NULL OR notification_id = ANY (p_ids));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    -- The user's other phones read their inbox again.
    PERFORM public.announce('user:' || auth.uid(), jsonb_build_object('table', 'notifications', 'op', 'HIDE'));
  END IF;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_my_notifications(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_notifications(uuid[]) TO authenticated;

-- The inbox page (as 20261103000001), without what the user removed.
CREATE OR REPLACE FUNCTION public.get_my_notifications_page(p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 30, p_unread_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    SELECT public.notification_item(m.n, m.is_read) AS item, (m.n).sent_at AS at
    FROM (
      SELECT n, r.read_at IS NOT NULL AS is_read
      FROM public.notification_recipients r
      JOIN public.notifications n ON n.id = r.notification_id
      WHERE r.user_id = auth.uid() AND n.status = 'sent' AND r.hidden_at IS NULL
        AND n.sent_at > now() - interval '90 days'
        AND (p_before IS NULL OR n.sent_at < p_before)
        AND (NOT COALESCE(p_unread_only, false) OR r.read_at IS NULL)
      UNION ALL
      -- What the user sent themselves (a supervisor), which they are not a recipient of.
      SELECT n, true
      FROM public.notifications n
      WHERE n.sender_id = auth.uid() AND n.status = 'sent' AND NOT COALESCE(p_unread_only, false)
        AND n.sent_at > now() - interval '90 days'
        AND (p_before IS NULL OR n.sent_at < p_before)
        AND NOT EXISTS (SELECT 1 FROM public.notification_recipients r
                        WHERE r.notification_id = n.id AND r.user_id = auth.uid())
    ) m
    ORDER BY (m.n).sent_at DESC
    LIMIT v_limit + 1
  ) x;
  IF v_count > v_limit THEN
    v_items := v_items - v_limit;
  END IF;
  RETURN jsonb_build_object('items', v_items, 'unread', public.get_my_unread_count(),
    'next_before', CASE WHEN v_count > v_limit THEN (v_items->(v_limit - 1))->>'created_at' END);
END;
$function$;

-- ------------------------------------------------------------------------------
-- 2. Old notifications are deleted (their recipients and pushes go with them).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notifications_purge()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  DELETE FROM public.notifications n
  WHERE n.status = 'sent'
    AND COALESCE(n.sent_at, n.created_at) < now() -
        CASE WHEN n.type LIKE 'subscription.%' THEN interval '30 days' ELSE interval '7 days' END;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.notifications_purge() FROM PUBLIC, anon, authenticated;

COMMIT;

-- Every night at 03:10 Cairo winter time (01:10 UTC), where pg_cron can be had.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'basak-notifications-purge';
    PERFORM cron.schedule('basak-notifications-purge', '10 1 * * *', 'SELECT public.notifications_purge()');
  ELSE
    RAISE NOTICE 'pg_cron is not installed: run public.notifications_purge() daily another way.';
  END IF;
END $$;
