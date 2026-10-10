-- ==============================================================================
-- Migration: 20261113000001_company_blocks_and_scan_flag.sql
-- Run AFTER 20261112000001. Safe to re-run.
--
-- 1. A company admin may block too: a student who is a member of their
--    company. The block is the same as the platform's (the number cannot be
--    registered, the account cannot sign in), so it is recorded with the
--    company that made it. A company lifts only its own blocks; the platform
--    admin lifts any. A company sees which of its students are blocked, and
--    the reason only for its own blocks.
--    block_student, unblock_phone and list_blocked_phones gain p_company_id
--    (NULL: as the platform admin, as before).
-- 2. Scanning a blocked student is not refused: the answer says 'blocked'
--    so the supervisor's app shows it (supervisor_check_in_student, otherwise
--    as 20261104000001).
-- ==============================================================================
BEGIN;

ALTER TABLE public.blocked_phones
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL;

-- The old signatures would make calls with fewer arguments ambiguous.
DROP FUNCTION IF EXISTS public.block_student(uuid, text);
DROP FUNCTION IF EXISTS public.unblock_phone(text);
DROP FUNCTION IF EXISTS public.list_blocked_phones();

-- p_company_id NULL: the platform admin's block. Otherwise that company's
-- admin (or the platform admin) blocks one of the company's students.
CREATE OR REPLACE FUNCTION public.block_student(p_student_id uuid, p_reason text DEFAULT NULL, p_company_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_student public.students%ROWTYPE;
  v_phone text;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF p_company_id IS NULL THEN
    IF public.is_super_admin() IS NOT TRUE THEN
      RAISE EXCEPTION 'الحظر على مستوى المنصة متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
    END IF;
  ELSIF public.can_manage_company(p_company_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'غير مسموح بإدارة طلاب هذه الشركة.' USING ERRCODE = '42501';
  ELSIF NOT EXISTS (SELECT 1 FROM public.company_students cs
                    WHERE cs.company_id = p_company_id AND cs.student_id = p_student_id AND cs.status = 'active') THEN
    RAISE EXCEPTION 'هذا الطالب غير مسجل في الشركة.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_student FROM public.students WHERE id = p_student_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الطالب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF length(v_reason) > 300 THEN
    RAISE EXCEPTION 'سبب الحظر طويل جداً (300 حرف على الأكثر).' USING ERRCODE = '23514';
  END IF;
  v_phone := public.normalize_egyptian_phone(v_student.phone);

  -- A number already blocked stays as it was blocked (and by whom).
  INSERT INTO public.blocked_phones (phone, student_id, full_name, reason, blocked_by, company_id)
  VALUES (v_phone, v_student.id, v_student.full_name, v_reason, auth.uid(), p_company_id)
  ON CONFLICT (phone) DO NOTHING;

  -- No sign-in from now on, and the sessions it has end.
  UPDATE auth.users SET banned_until = now() + interval '100 years' WHERE id = v_student.id;
  DELETE FROM auth.sessions WHERE user_id = v_student.id;

  RETURN jsonb_build_object('phone', v_phone, 'student_id', v_student.id, 'blocked', true);
END;
$$;
REVOKE ALL ON FUNCTION public.block_student(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.block_student(uuid, text, uuid) TO authenticated;

-- The platform admin lifts any block; a company admin only their company's.
CREATE OR REPLACE FUNCTION public.unblock_phone(p_phone text, p_company_id uuid DEFAULT NULL) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_phone text := public.normalize_egyptian_phone(COALESCE(p_phone, ''));
  v_block public.blocked_phones%ROWTYPE;
BEGIN
  IF p_company_id IS NULL THEN
    IF public.is_super_admin() IS NOT TRUE THEN
      RAISE EXCEPTION 'الحظر على مستوى المنصة متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
    END IF;
  ELSIF public.can_manage_company(p_company_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'غير مسموح بإدارة طلاب هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_block FROM public.blocked_phones WHERE phone = v_phone;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF public.is_super_admin() IS NOT TRUE AND v_block.company_id IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'هذا الحظر من إدارة المنصة أو من شركة أخرى، ولا ترفعه إلا إدارة المنصة.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.blocked_phones WHERE phone = v_phone;
  UPDATE auth.users SET banned_until = NULL
  WHERE id IN (SELECT s.id FROM public.students s WHERE public.normalize_egyptian_phone(s.phone) = v_phone);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.unblock_phone(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unblock_phone(text, uuid) TO authenticated;

-- p_company_id NULL: every block (the platform admin). Otherwise the blocks of
-- that company's students and the company's own, the reason only for its own.
-- [{"phone", "student_id", "full_name", "reason", "blocked_at", "has_account",
--   "company_id", "company_name", "can_unblock"}], newest first.
CREATE OR REPLACE FUNCTION public.list_blocked_phones(p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_platform boolean := public.is_super_admin() IS TRUE;
BEGIN
  IF p_company_id IS NULL THEN
    IF NOT v_platform THEN
      RAISE EXCEPTION 'الحظر على مستوى المنصة متاح لمدير المنصة فقط.' USING ERRCODE = '42501';
    END IF;
  ELSIF public.can_manage_company(p_company_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'غير مسموح بإدارة طلاب هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'phone', b.phone, 'student_id', b.student_id, 'full_name', b.full_name,
             'reason', CASE WHEN v_platform OR COALESCE(b.company_id = p_company_id, false) THEN b.reason END,
             'blocked_at', b.blocked_at, 'has_account', b.student_id IS NOT NULL,
             'company_id', b.company_id, 'company_name', c.name,
             'can_unblock', v_platform OR COALESCE(b.company_id = p_company_id, false))
           ORDER BY b.blocked_at DESC)
    FROM public.blocked_phones b
    LEFT JOIN public.companies c ON c.id = b.company_id
    WHERE p_company_id IS NULL
       OR b.company_id = p_company_id
       OR EXISTS (SELECT 1 FROM public.company_students cs
                  WHERE cs.company_id = p_company_id AND cs.student_id = b.student_id AND cs.status = 'active')
  ), '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.list_blocked_phones(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_blocked_phones(uuid) TO authenticated;

-- 2. Check-in: says whether the scanned student is blocked.
CREATE OR REPLACE FUNCTION public.supervisor_check_in_student(
  p_qr_code uuid, p_direction text DEFAULT 'departure', p_trip_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_today date := public.cairo_today();
  v_student public.students%ROWTYPE;
  v_sub record;
  v_trip uuid;
  v_result text;
  v_first record;
  v_details jsonb;
BEGIN
  IF NOT public.is_supervisor() THEN
    RAISE EXCEPTION 'هذه العملية متاحة لمشرفي الحافلات النشطين فقط.';
  END IF;
  IF p_direction NOT IN ('departure', 'return') THEN
    RAISE EXCEPTION 'اتجاه الرحلة غير صحيح.';
  END IF;

  SELECT * INTO v_student FROM public.students WHERE qr_code_value = p_qr_code;
  IF NOT FOUND THEN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result, trip_id)
    VALUES (v_me, v_today, p_direction, 'not_found', p_trip_id);
    RETURN jsonb_build_object('result', 'not_found', 'message', 'رمز QR غير مسجل لأي طالب.');
  END IF;

  -- Students outside the supervisor's lines: log, reveal nothing about them.
  IF NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student.id
      AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
  ) THEN
    INSERT INTO public.supervisor_scan_events(supervisor_id, ride_date, direction, result, trip_id)
    VALUES (v_me, v_today, p_direction, 'outside_assigned_lines', p_trip_id);
    RETURN jsonb_build_object('result', 'outside_assigned_lines',
      'message', 'هذا الطالب غير مشترك في الخطوط المسندة إليك.');
  END IF;

  SELECT sub.id, sub.line_id, sub.station_id, sub.schedule_id, sub.departure_trip_id, sub.return_trip_id INTO v_sub
  FROM public.subscriptions sub
  WHERE sub.student_id = v_student.id AND sub.status = 'active'
    AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)
    AND (sub.start_date IS NULL OR sub.start_date <= v_today)
    AND (sub.end_date IS NULL OR sub.end_date >= v_today)
  ORDER BY sub.created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    v_result := 'no_active_subscription';
    INSERT INTO public.supervisor_scan_events(supervisor_id, student_id, ride_date, direction, result, trip_id)
    VALUES (v_me, v_student.id, v_today, p_direction, v_result, p_trip_id);
  ELSE
    -- The trip being scanned (if it is a trip of this line and direction), else
    -- the student's own trip for this direction.
    SELECT t.id INTO v_trip FROM public.line_trips t
    WHERE t.id = p_trip_id AND t.line_id = v_sub.line_id AND t.direction = p_direction;
    v_trip := COALESCE(v_trip, CASE p_direction WHEN 'departure' THEN v_sub.departure_trip_id ELSE v_sub.return_trip_id END);
    BEGIN
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, trip_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_trip, v_today, p_direction, 'checked_in');
      v_result := 'checked_in';
    EXCEPTION WHEN unique_violation THEN
      -- uq_scan_checkin_once_per_direction: already checked in for this direction today.
      v_result := 'already_checked_in';
      INSERT INTO public.supervisor_scan_events(
        supervisor_id, student_id, subscription_id, line_id, station_id, schedule_id, trip_id, ride_date, direction, result)
      VALUES (v_me, v_student.id, v_sub.id, v_sub.line_id, v_sub.station_id, v_sub.schedule_id, v_trip, v_today, p_direction, v_result);
    END;
  END IF;

  SELECT e.scanned_at, e.direction INTO v_first FROM public.supervisor_scan_events e
  WHERE e.student_id = v_student.id AND e.ride_date = v_today AND e.direction = p_direction AND e.result = 'checked_in';

  -- The student's details as this supervisor may see them: lookup_student_by_qr
  -- shows a supervisor only students with an active subscription on their
  -- lines and refuses the rest, which used to fail the whole scan.
  BEGIN
    v_details := public.lookup_student_by_qr(p_qr_code);
  EXCEPTION WHEN raise_exception THEN
    v_details := NULL;
  END;

  RETURN jsonb_build_object(
    'result', v_result,
    'message', CASE v_result
      WHEN 'checked_in' THEN CASE p_direction WHEN 'return' THEN 'تم تسجيل الطالب في رحلة العودة.' ELSE 'تم تسجيل الطالب في رحلة الذهاب.' END
      WHEN 'already_checked_in' THEN CASE p_direction WHEN 'return' THEN 'تم تسجيل هذا الطالب في رحلة العودة اليوم بالفعل.' ELSE 'تم تسجيل هذا الطالب في رحلة الذهاب اليوم بالفعل.' END
      ELSE 'لا يوجد اشتراك ساري لهذا الطالب اليوم.' END,
    'direction', p_direction,
    'trip_id', v_trip,
    'ride_date', v_today,
    'checked_in_at', v_first.scanned_at,
    'confirmed_ride_today', (SELECT CASE p_direction WHEN 'return' THEN drs.is_riding AND drs.is_returning ELSE drs.is_riding END
                             FROM public.daily_ride_status drs
                             WHERE drs.student_id = v_student.id AND drs.ride_date = v_today),
    'ride_vote', (SELECT jsonb_build_object('is_riding', drs.is_riding, 'is_returning', drs.is_returning,
                                            'departure_time', drs.departure_time, 'return_time', drs.return_time)
                  FROM public.daily_ride_status drs
                  WHERE drs.student_id = v_student.id AND drs.ride_date = v_today),
    -- Blocked by the platform or a company: not refused, said to the supervisor.
    'blocked', public.is_phone_blocked(v_student.phone),
    'student', v_details
  );
END;
$$;

REVOKE ALL ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_check_in_student(uuid, text, uuid) TO authenticated;

COMMIT;
