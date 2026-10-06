-- Three things that follow from "one account, many companies":
--   1. company_invites: a company asks an existing account to join; nothing about
--      the person is visible to the company until the student accepts in the app.
--   2. student_correction_requests: a company proposes a fix to a member's name or
--      university; only the platform admin can apply it, because the account may
--      belong to several companies.
--   3. platform_students(): the platform admin's list of every student with their memberships.

-- ---------------------------------------------------------------------------
-- 1. Invitations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  -- What the admin typed. The company sees this and the status, nothing else.
  phone text NOT NULL,
  -- The subscription offered with the invitation.
  line_id uuid NOT NULL REFERENCES public.lines(id) ON DELETE CASCADE,
  station_id uuid NOT NULL REFERENCES public.stations(id) ON DELETE CASCADE,
  subscription_type text NOT NULL CHECK (subscription_type IN ('termly', 'yearly', 'daily')),
  period_code text,
  academic_year integer,
  departure_trip_id uuid REFERENCES public.line_trips(id) ON DELETE SET NULL,
  return_trip_id uuid REFERENCES public.line_trips(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + INTERVAL '14 days',
  responded_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_company_invites_open ON public.company_invites (company_id, student_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_company_invites_student ON public.company_invites (student_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_company_invites_company ON public.company_invites (company_id, created_at DESC);

ALTER TABLE public.company_invites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_invites_read ON public.company_invites;
CREATE POLICY company_invites_read ON public.company_invites FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid())
      OR (SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()));
-- Created by the add-student function, answered and cancelled through the functions below.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.company_invites FROM anon, authenticated;

-- The student's open invitations, with just enough to decide.
CREATE OR REPLACE FUNCTION public.get_my_invites() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', i.id, 'company_id', i.company_id, 'company_name', c.name,
      'line_name', l.name, 'station_name', st.name, 'subscription_type', i.subscription_type,
      'price', CASE i.subscription_type WHEN 'termly' THEN l.price_termly WHEN 'yearly' THEN l.price_yearly ELSE l.price_daily END,
      'created_at', i.created_at, 'expires_at', i.expires_at) ORDER BY i.created_at DESC), '[]'::jsonb)
  FROM public.company_invites i
  JOIN public.companies c ON c.id = i.company_id AND c.status = 'active'
  JOIN public.lines l ON l.id = i.line_id
  JOIN public.stations st ON st.id = i.station_id
  WHERE i.student_id = auth.uid() AND i.status = 'pending' AND i.expires_at > now()
$$;

-- Accepting makes the student a member and opens the offered subscription
-- (unpaid, like one they would have started themselves). Declining changes nothing.
CREATE OR REPLACE FUNCTION public.respond_company_invite(p_invite_id uuid, p_accept boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_invite public.company_invites%ROWTYPE;
  v_subscription uuid;
  v_note text;
BEGIN
  SELECT * INTO v_invite FROM public.company_invites
  WHERE id = p_invite_id AND student_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الدعوة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF v_invite.status <> 'pending' OR v_invite.expires_at <= now() THEN
    RAISE EXCEPTION 'هذه الدعوة لم تعد متاحة.' USING ERRCODE = '22023';
  END IF;

  IF NOT COALESCE(p_accept, false) THEN
    UPDATE public.company_invites SET status = 'declined', responded_at = now() WHERE id = p_invite_id;
    RETURN jsonb_build_object('accepted', false);
  END IF;
  IF NOT public.company_is_active(v_invite.company_id) THEN
    RAISE EXCEPTION 'هذه الشركة غير متاحة حالياً.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.company_students (company_id, student_id) VALUES (v_invite.company_id, v_invite.student_id)
  ON CONFLICT (company_id, student_id) DO UPDATE
    SET status = 'active', removed_at = NULL, removed_by = NULL, joined_at = now();
  UPDATE public.company_invites SET status = 'accepted', responded_at = now() WHERE id = p_invite_id;

  -- The subscription is the student's own choice to keep: if it cannot be opened
  -- (e.g. they already hold one for the same dates) they are still a member.
  BEGIN
    INSERT INTO public.subscriptions (student_id, line_id, station_id, type, period_code, academic_year,
                                      departure_trip_id, return_trip_id, status, price)
    VALUES (v_invite.student_id, v_invite.line_id, v_invite.station_id, v_invite.subscription_type,
            v_invite.period_code, v_invite.academic_year, v_invite.departure_trip_id, v_invite.return_trip_id,
            'pending_payment', 0)
    RETURNING id INTO v_subscription;
  EXCEPTION WHEN OTHERS THEN
    v_note := SQLERRM;
  END;
  RETURN jsonb_build_object('accepted', true, 'subscription_id', v_subscription, 'note', v_note);
END;
$$;

CREATE OR REPLACE FUNCTION public.company_cancel_invite(p_invite_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM public.company_invites WHERE id = p_invite_id AND status = 'pending';
  IF v_company IS NULL OR NOT public.can_manage_company(v_company) THEN
    RAISE EXCEPTION 'الدعوة غير موجودة أو خارج صلاحياتك.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.company_invites SET status = 'cancelled', responded_at = now() WHERE id = p_invite_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_invites(), public.respond_company_invite(uuid, boolean),
  public.company_cancel_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_invites(), public.respond_company_invite(uuid, boolean),
  public.company_cancel_invite(uuid) TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_announce_change ON public.company_invites;
CREATE TRIGGER trg_announce_change AFTER INSERT OR UPDATE OR DELETE ON public.company_invites
  FOR EACH ROW EXECUTE FUNCTION public.announce_change('student');

-- ---------------------------------------------------------------------------
-- 2. Identity correction requests
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_correction_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  field text NOT NULL CHECK (field IN ('full_name', 'university')),
  old_value text,
  new_value text NOT NULL CHECK (length(btrim(new_value)) > 0),
  note text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_note text
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_correction_open ON public.student_correction_requests (student_id, field) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_correction_company ON public.student_correction_requests (company_id, created_at DESC);

ALTER TABLE public.student_correction_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS correction_requests_read ON public.student_correction_requests;
CREATE POLICY correction_requests_read ON public.student_correction_requests FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.student_correction_requests FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.request_student_correction(
  p_company_id uuid, p_student_id uuid, p_field text, p_new_value text, p_note text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old text; v_new text := btrim(COALESCE(p_new_value, '')); v_id uuid;
BEGIN
  IF NOT public.can_manage_company(p_company_id) OR NOT public.is_company_member(p_company_id, p_student_id) THEN
    RAISE EXCEPTION 'هذا الطالب غير مسجل في شركتك.' USING ERRCODE = '42501';
  END IF;
  IF p_field NOT IN ('full_name', 'university') THEN
    RAISE EXCEPTION 'يمكن طلب تصحيح الاسم أو الجامعة فقط.' USING ERRCODE = '22023';
  END IF;
  IF p_field = 'full_name' AND array_length(regexp_split_to_array(v_new, '\s+'), 1) < 4 THEN
    RAISE EXCEPTION 'اكتب الاسم الرباعي كاملاً.' USING ERRCODE = '22023';
  END IF;
  IF p_field = 'university' AND NOT EXISTS (SELECT 1 FROM public.universities WHERE name = v_new AND is_active) THEN
    RAISE EXCEPTION 'اختر جامعة من القائمة.' USING ERRCODE = '22023';
  END IF;
  SELECT CASE p_field WHEN 'full_name' THEN full_name ELSE university END INTO v_old
  FROM public.students WHERE id = p_student_id;
  IF v_old = v_new THEN
    RAISE EXCEPTION 'القيمة الجديدة مطابقة للحالية.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.student_correction_requests (student_id, company_id, field, old_value, new_value, note, requested_by)
  VALUES (p_student_id, p_company_id, p_field, v_old, v_new, NULLIF(btrim(p_note), ''), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'يوجد طلب تصحيح مفتوح لهذا الحقل بالفعل.' USING ERRCODE = '23505';
END;
$$;

-- The university is fixed for everyone except the platform admin applying a correction.
CREATE OR REPLACE FUNCTION public.prevent_student_profile_update() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.phone IS DISTINCT FROM NEW.phone OR OLD.qr_code_value IS DISTINCT FROM NEW.qr_code_value
     OR (OLD.university IS DISTINCT FROM NEW.university AND pg_trigger_depth() <= 1
         AND NOT COALESCE(current_setting('basak.correction', true), '') = 'on') THEN
    RAISE EXCEPTION 'بيانات الهاتف والجامعة ورمز QR ثابتة. احذف الحساب وأعد التسجيل لتغييرها.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_student_correction(p_request_id uuid, p_approve boolean, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.student_correction_requests%ROWTYPE;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'اعتماد التصحيح متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO r FROM public.student_correction_requests WHERE id = p_request_id AND status = 'pending' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الطلب غير موجود أو تم البت فيه.' USING ERRCODE = 'P0002';
  END IF;
  IF COALESCE(p_approve, false) THEN
    IF r.field = 'full_name' THEN
      UPDATE public.students SET full_name = r.new_value WHERE id = r.student_id;
    ELSE
      PERFORM set_config('basak.correction', 'on', true);
      UPDATE public.students SET university = r.new_value, university_id = NULL WHERE id = r.student_id;
      PERFORM set_config('basak.correction', 'off', true);
    END IF;
  END IF;
  UPDATE public.student_correction_requests
  SET status = CASE WHEN COALESCE(p_approve, false) THEN 'approved' ELSE 'rejected' END,
      decided_by = auth.uid(), decided_at = now(), decision_note = NULLIF(btrim(p_note), '')
  WHERE id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_student_correction(uuid, uuid, text, text, text),
  public.decide_student_correction(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_student_correction(uuid, uuid, text, text, text),
  public.decide_student_correction(uuid, boolean, text) TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_announce_change ON public.student_correction_requests;
CREATE TRIGGER trg_announce_change AFTER INSERT OR UPDATE ON public.student_correction_requests
  FOR EACH ROW EXECUTE FUNCTION public.announce_change('platform');

-- A student is told when their own profile changes (an approved correction, a new photo).
DROP TRIGGER IF EXISTS trg_announce_profile ON public.students;
CREATE OR REPLACE FUNCTION public.announce_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.announce('student:' || NEW.id, jsonb_build_object('table', 'students', 'op', TG_OP, 'id', NEW.id, 'company_id', NULL));
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_profile() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_announce_profile AFTER UPDATE OF full_name, university, profile_image_url, must_change_password ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.announce_profile();

-- ---------------------------------------------------------------------------
-- 3. Every student on the platform (platform admin only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.platform_students(
  p_search text DEFAULT NULL, p_company_id uuid DEFAULT NULL, p_membership text DEFAULT NULL,
  p_limit integer DEFAULT 25, p_offset integer DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_search text := NULLIF(btrim(p_search), '');
  v_digits text := regexp_replace(COALESCE(p_search, ''), '\D', '', 'g');
  v_result jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
  END IF;
  WITH matched AS (
    SELECT s.* FROM public.students s
    WHERE (v_search IS NULL OR s.full_name ILIKE '%' || v_search || '%' OR s.university ILIKE '%' || v_search || '%'
           OR (v_digits <> '' AND s.phone LIKE '%' || v_digits || '%'))
      AND (p_company_id IS NULL OR EXISTS (SELECT 1 FROM public.company_students m
                                           WHERE m.student_id = s.id AND m.company_id = p_company_id AND m.status = 'active'))
      AND (p_membership IS NULL
           OR (p_membership = 'none' AND NOT EXISTS (SELECT 1 FROM public.company_students m WHERE m.student_id = s.id AND m.status = 'active'))
           OR (p_membership = 'multiple' AND (SELECT count(*) FROM public.company_students m WHERE m.student_id = s.id AND m.status = 'active') > 1))
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM matched),
    'rows', COALESCE((SELECT jsonb_agg(row ORDER BY created_at DESC) FROM (
      SELECT m.created_at, jsonb_build_object(
        'id', m.id, 'full_name', m.full_name, 'phone', m.phone, 'university', m.university, 'created_at', m.created_at,
        'memberships', COALESCE((SELECT jsonb_agg(jsonb_build_object('company_id', c.id, 'company', c.name, 'status', cs.status,
                                    'joined_at', cs.joined_at) ORDER BY cs.joined_at)
                                 FROM public.company_students cs JOIN public.companies c ON c.id = cs.company_id
                                 WHERE cs.student_id = m.id), '[]'::jsonb),
        'active_subscriptions', (SELECT count(*) FROM public.subscriptions sub
                                 WHERE sub.student_id = m.id AND sub.status = 'active'
                                   AND (sub.end_date IS NULL OR sub.end_date >= public.cairo_today()))) AS row
      FROM matched m ORDER BY m.created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100) OFFSET GREATEST(COALESCE(p_offset, 0), 0)) x), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.platform_students(text, uuid, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_students(text, uuid, text, integer, integer) TO authenticated, service_role;
