-- Live updates, scoped by the database.
--
-- A change to a watched table announces itself on private topics:
--   company:<id>   that company's staff (and the platform admin)
--   student:<id>   that student only
--   line:<id>      the line's company staff, and students with an open subscription on it
--   platform       the platform admin
-- The message says WHAT changed (table, operation, row id, company) and nothing
-- else: no names, phones or photos. Clients then re-read through the normal,
-- row-level-secured queries. Who may listen to a topic is decided here, by a
-- policy on realtime.messages, not by the client.

-- ---------------------------------------------------------------------------
-- 1. Who may join a topic
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_join_topic(p_topic text) RETURNS boolean
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
    WHEN 'line' THEN
      public.has_company_access((SELECT l.company_id FROM public.lines l WHERE l.id = v_id))
      OR EXISTS (SELECT 1 FROM public.subscriptions s
                 WHERE s.line_id = v_id AND s.student_id = auth.uid()
                   AND s.status IN ('pending_payment', 'pending_review', 'active'))
    ELSE false
  END, false);
END;
$$;
REVOKE ALL ON FUNCTION public.can_join_topic(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_join_topic(text) TO authenticated, service_role;

-- Clients only listen; nothing a client sends is relayed.
DROP POLICY IF EXISTS basak_topic_listen ON realtime.messages;
CREATE POLICY basak_topic_listen ON realtime.messages FOR SELECT TO authenticated
  USING (public.can_join_topic((SELECT realtime.topic())));

-- ---------------------------------------------------------------------------
-- 2. Announcing changes
-- ---------------------------------------------------------------------------
-- Never lets a delivery problem fail the write that caused it.
CREATE OR REPLACE FUNCTION public.announce(p_topic text, p_payload jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_topic IS NULL THEN RETURN; END IF;
  PERFORM realtime.send(p_payload, 'change', p_topic, true);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'announce(%) failed: %', p_topic, SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public.announce(text, jsonb) FROM PUBLIC, anon, authenticated;

-- TG_ARGV: which topics a table's changes go to, besides its company:
--   'student'  the row's student_id            'via_subscription'  the subscription's student
--   'line'     the row's line_id               'self_line'         the row is the line
--   'platform' also tell the platform admin    'self_company'      the row is the company
CREATE OR REPLACE FUNCTION public.announce_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row jsonb := to_jsonb(COALESCE(NEW, OLD));
  v_company uuid := CASE WHEN 'self_company' = ANY (TG_ARGV) THEN (v_row->>'id')::uuid ELSE (v_row->>'company_id')::uuid END;
  v_id text := COALESCE(v_row->>'id', v_row->>'student_id');
  v_payload jsonb := jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP, 'id', v_id, 'company_id', v_company);
  v_student uuid;
BEGIN
  PERFORM public.announce('company:' || v_company, v_payload);

  IF 'student' = ANY (TG_ARGV) THEN
    v_student := (v_row->>'student_id')::uuid;
  ELSIF 'via_subscription' = ANY (TG_ARGV) THEN
    SELECT s.student_id INTO v_student FROM public.subscriptions s WHERE s.id = (v_row->>'subscription_id')::uuid;
  END IF;
  PERFORM public.announce('student:' || v_student, v_payload);

  IF 'line' = ANY (TG_ARGV) THEN
    PERFORM public.announce('line:' || (v_row->>'line_id'), v_payload);
  ELSIF 'self_line' = ANY (TG_ARGV) THEN
    PERFORM public.announce('line:' || (v_row->>'id'), v_payload);
  END IF;

  IF 'platform' = ANY (TG_ARGV) THEN
    PERFORM public.announce('platform', v_payload);
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_change() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('receipts',                'via_subscription', 'platform'),
      ('subscriptions',           'student',          'platform'),
      ('company_students',        'student',          'platform'),
      ('daily_ride_status',       NULL,               NULL),
      ('supervisor_scan_events',  NULL,               NULL),
      ('complaints',              NULL,               NULL),
      ('lines',                   'self_line',        NULL),
      ('stations',                'line',             NULL),
      ('line_trips',              'line',             NULL),
      ('supervisors',             NULL,               NULL),
      ('supervisor_lines',        'line',             NULL),
      ('company_payment_methods', NULL,               NULL),
      ('company_terms',           NULL,               NULL),
      ('wallet_card_settings',    NULL,               NULL),
      ('companies',               'self_company',     'platform')) AS t(tbl, a1, a2)
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_announce_change ON public.%I', r.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_announce_change AFTER INSERT OR UPDATE OR DELETE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.announce_change(%s)',
      r.tbl, concat_ws(', ', quote_nullable(r.a1), quote_nullable(r.a2)));
  END LOOP;
END;
$$;

-- A password-reset request has no company of its own: tell every company the
-- student is an active member of, and the platform admin.
CREATE OR REPLACE FUNCTION public.announce_reset_request() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_student uuid := COALESCE(NEW.student_id, OLD.student_id);
  v_payload jsonb := jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP, 'id', COALESCE(NEW.id, OLD.id));
  m record;
BEGIN
  FOR m IN SELECT company_id FROM public.company_students WHERE student_id = v_student AND status = 'active' LOOP
    PERFORM public.announce('company:' || m.company_id, v_payload || jsonb_build_object('company_id', m.company_id));
  END LOOP;
  PERFORM public.announce('platform', v_payload);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_reset_request() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_announce_change ON public.password_reset_requests;
CREATE TRIGGER trg_announce_change AFTER INSERT OR UPDATE OF status ON public.password_reset_requests
  FOR EACH ROW EXECUTE FUNCTION public.announce_reset_request();
