-- Tenant isolation. Every tenant-owned row is reached through one rule,
-- can_manage_company(company_id) / has_company_access(company_id), and what a
-- company may do with a student follows from an active membership.
--
-- Closes:
--   * a company deleting a student it shares with another company
--   * a former company still reading a student's profile, photo, rides, complaints
--   * a company attaching a subscription to a student who is not its member
--   * a company without an active membership issuing a password-reset code
--   * supervisors reading other companies' lines, prices and stations
--   * staff of a suspended company keeping their access

-- ---------------------------------------------------------------------------
-- 1. Who is staff, and of what
-- ---------------------------------------------------------------------------
-- An admin of a suspended or archived company is not an admin until it is active again.
CREATE OR REPLACE FUNCTION public.current_admin_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.role FROM public.admins a
  WHERE a.id = auth.uid()
    AND (a.role = 'super_admin' OR public.company_is_active(a.company_id))
$$;

CREATE OR REPLACE FUNCTION public.is_supervisor() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.supervisors s
                 WHERE s.id = auth.uid() AND s.is_active AND public.company_is_active(s.company_id))
$$;

-- Policies compare a row's company with these, each read ONCE per statement
-- (as "(SELECT f())"), instead of calling a function for every row.
-- The company the caller manages as its admin, while it is active.
CREATE OR REPLACE FUNCTION public.managed_company_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.company_id FROM public.admins a
  WHERE a.id = auth.uid() AND a.role = 'company_admin' AND public.company_is_active(a.company_id)
$$;
-- The company the caller works for (as admin or supervisor), while it is active.
CREATE OR REPLACE FUNCTION public.staff_company_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.managed_company_id(),
    (SELECT s.company_id FROM public.supervisors s
     WHERE s.id = auth.uid() AND s.is_active AND public.company_is_active(s.company_id)))
$$;
CREATE OR REPLACE FUNCTION public.active_company_ids() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM public.companies WHERE status = 'active'
$$;
REVOKE ALL ON FUNCTION public.managed_company_id(), public.staff_company_id(), public.active_company_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.managed_company_id(), public.staff_company_id(), public.active_company_ids() TO authenticated, service_role;

-- Has a staff account at all, whatever its state. Staff never get the public,
-- student-facing view of other companies.
CREATE OR REPLACE FUNCTION public.is_staff_account() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.supervisors WHERE id = auth.uid())
$$;
REVOKE ALL ON FUNCTION public.is_staff_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_staff_account() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_supervisor_assigned_line_ids() RETURNS TABLE(line_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT sl.line_id
  FROM public.supervisor_lines sl
  JOIN public.supervisors s ON s.id = sl.supervisor_id AND s.is_active
  JOIN public.lines l ON l.id = sl.line_id AND l.company_id = s.company_id
  WHERE sl.supervisor_id = auth.uid() AND public.company_is_active(s.company_id)
$$;

CREATE OR REPLACE FUNCTION public.can_manage_line_company(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.can_manage_company(p_company_id)
$$;

-- A company manages a student while that student is its active member.
CREATE OR REPLACE FUNCTION public.admin_can_manage_student(p_student_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin() OR (public.is_company_admin()
    AND public.is_company_member(public.current_admin_company_id(), p_student_id))
$$;

-- Open "forgot password" requests an admin may answer. A company sees those of
-- its active members; p_company_id narrows the platform admin's list to one company.
DROP FUNCTION IF EXISTS public.admin_list_password_reset_requests();
CREATE OR REPLACE FUNCTION public.admin_list_password_reset_requests(p_company_id uuid DEFAULT NULL)
RETURNS TABLE(id uuid, student_id uuid, student_name text, student_phone text, status text, requested_at timestamptz,
              code_issued_at timestamptz, code_expires_at timestamptz, failed_attempts integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'متاح للمسؤولين فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT r.id, r.student_id, s.full_name, s.phone,
         CASE WHEN r.status = 'code_issued' AND r.code_expires_at < now() THEN 'expired' ELSE r.status END,
         r.requested_at, r.code_issued_at, r.code_expires_at, r.failed_attempts
  FROM public.password_reset_requests r JOIN public.students s ON s.id = r.student_id
  WHERE r.requested_at > now() - INTERVAL '30 days'
    AND public.admin_can_manage_student(r.student_id)
    AND (p_company_id IS NULL OR public.is_company_member(p_company_id, r.student_id))
  ORDER BY (r.status IN ('pending', 'code_issued')) DESC, r.requested_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_password_reset_requests(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_password_reset_requests(uuid) TO authenticated, service_role;

-- An admin adds a subscription only for a student who is already a member.
-- New students are added from the Students page, which creates the membership.
CREATE OR REPLACE FUNCTION public.guard_subscription_student_scope() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Service role / SQL editor and the platform admin keep full control.
  IF auth.uid() IS NULL OR public.is_super_admin() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.student_id IS DISTINCT FROM OLD.student_id THEN
      RAISE EXCEPTION 'لا يمكن نقل الاشتراك إلى طالب آخر.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.student_id IS DISTINCT FROM auth.uid()
     AND NOT public.is_company_member(public.current_admin_company_id(), NEW.student_id) THEN
    RAISE EXCEPTION 'هذا الطالب غير مرتبط بشركتك. أضف الطلاب الجدد من صفحة الطلاب.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_annual_subscription(p_enabled boolean, p_company_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_enabled IS NULL THEN RAISE EXCEPTION 'قيمة غير صالحة.'; END IF;
  IF p_company_id IS NULL THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'الإعداد العام متاح لمدير النظام فقط.' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_settings SET annual_subscription_enabled = p_enabled, updated_at = now(), updated_by = auth.uid() WHERE id;
  ELSE
    IF NOT public.can_manage_company(p_company_id) THEN
      RAISE EXCEPTION 'لا يمكنك تعديل إعدادات هذه الشركة.' USING ERRCODE = '42501';
    END IF;
    UPDATE public.companies SET annual_subscription_enabled = p_enabled WHERE id = p_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'الشركة غير موجودة.'; END IF;
  END IF;
  RETURN jsonb_build_object('global', public.annual_subscription_enabled(NULL),
    'company_id', p_company_id,
    'effective', public.annual_subscription_enabled(p_company_id));
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. company_id is required
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscriptions             ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.stations                  ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.line_trips                ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.line_trip_stops           ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.line_universities         ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.line_university_schedules ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.supervisor_lines          ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.receipts                  ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.supervisor_scan_events    ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.chat_messages             ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.daily_ride_status         ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.deleted_student_revenue   ALTER COLUMN company_id SET NOT NULL;

-- The company of a child row is rewritten from its parent on every write
-- (trg_tenant_company), so a child cannot disagree with its parent. What is left
-- is the parent itself moving: a line or a supervisor never changes company.
-- (A second, composite foreign key would say the same, but it gives the API two
-- relationships between the same tables and breaks every nested query on them.)
CREATE OR REPLACE FUNCTION public.forbid_company_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    RAISE EXCEPTION 'لا يمكن نقل هذا السجل إلى شركة أخرى.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_forbid_company_change ON public.lines;
CREATE TRIGGER trg_forbid_company_change BEFORE UPDATE OF company_id ON public.lines
  FOR EACH ROW EXECUTE FUNCTION public.forbid_company_change();
DROP TRIGGER IF EXISTS trg_forbid_company_change ON public.supervisors;
CREATE TRIGGER trg_forbid_company_change BEFORE UPDATE OF company_id ON public.supervisors
  FOR EACH ROW EXECUTE FUNCTION public.forbid_company_change();

-- ---------------------------------------------------------------------------
-- 3. Policies
-- ---------------------------------------------------------------------------
-- companies: staff always see their own (also while suspended, to be told so);
-- everyone else sees the active ones.
DROP POLICY IF EXISTS companies_read_scope ON public.companies;
CREATE POLICY companies_read_scope ON public.companies FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin())
      OR id = (SELECT a.company_id FROM public.admins a WHERE a.id = (SELECT auth.uid()))
      OR id = (SELECT s.company_id FROM public.supervisors s WHERE s.id = (SELECT auth.uid()))
      OR (status = 'active' AND NOT (SELECT public.is_staff_account())));

-- admins: a company admin also sees the other admins of their company.
DROP POLICY IF EXISTS admins_read_self_or_super ON public.admins;
CREATE POLICY admins_read_scope ON public.admins FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) OR (SELECT public.is_super_admin())
      OR (company_id IS NOT NULL AND (SELECT public.is_company_admin()) AND ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))));

-- lines and what hangs off them
DROP POLICY IF EXISTS lines_company_manage ON public.lines;
DROP POLICY IF EXISTS lines_read_scope ON public.lines;
CREATE POLICY lines_company_manage ON public.lines FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY lines_read_scope ON public.lines FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()))
      OR (is_active AND company_id IN (SELECT public.active_company_ids()) AND NOT (SELECT public.is_staff_account())));

DROP POLICY IF EXISTS stations_company_manage ON public.stations;
DROP POLICY IF EXISTS stations_read_scope ON public.stations;
CREATE POLICY stations_company_manage ON public.stations FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY stations_read_scope ON public.stations FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()))
      OR EXISTS (SELECT 1 FROM public.lines l WHERE l.id = stations.line_id));

DROP POLICY IF EXISTS line_trips_read_scope ON public.line_trips;
CREATE POLICY line_trips_read_scope ON public.line_trips FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()))
      OR (NOT (SELECT public.is_staff_account())
          AND public.trip_serves_student(line_trips.*, (SELECT auth.uid()))
          AND EXISTS (SELECT 1 FROM public.lines l WHERE l.id = line_trips.line_id AND l.is_active))
      OR EXISTS (SELECT 1 FROM public.subscriptions s
                 WHERE s.student_id = (SELECT auth.uid())
                   AND (s.departure_trip_id = line_trips.id OR s.return_trip_id = line_trips.id)));

DROP POLICY IF EXISTS line_trip_stops_read_scope ON public.line_trip_stops;
CREATE POLICY line_trip_stops_read_scope ON public.line_trip_stops FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()))
      OR EXISTS (SELECT 1 FROM public.line_trips t WHERE t.id = line_trip_stops.trip_id));

DROP POLICY IF EXISTS line_universities_read ON public.line_universities;
CREATE POLICY line_universities_read ON public.line_universities FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()))
      OR EXISTS (SELECT 1 FROM public.lines l WHERE l.id = line_universities.line_id));

DROP POLICY IF EXISTS line_schedules_company_manage ON public.line_university_schedules;
DROP POLICY IF EXISTS line_schedules_read_scope ON public.line_university_schedules;
CREATE POLICY line_schedules_company_manage ON public.line_university_schedules FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY line_schedules_read_scope ON public.line_university_schedules FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.staff_company_id()))
      OR (NOT (SELECT public.is_staff_account()) AND is_active
          AND university_id = (SELECT public.current_student_university_id()))
      OR EXISTS (SELECT 1 FROM public.subscriptions sub
                 WHERE sub.schedule_id = line_university_schedules.id AND sub.student_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS supervisor_lines_read_scope ON public.supervisor_lines;
CREATE POLICY supervisor_lines_read_scope ON public.supervisor_lines FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())) OR supervisor_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS supervisors_company_manage ON public.supervisors;
DROP POLICY IF EXISTS supervisors_read_scope ON public.supervisors;
CREATE POLICY supervisors_company_manage ON public.supervisors FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY supervisors_read_scope ON public.supervisors FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
      OR id = (SELECT auth.uid())
      OR (NOT (SELECT public.is_staff_account()) AND EXISTS (
            SELECT 1 FROM public.subscriptions sub JOIN public.supervisor_lines sl ON sl.line_id = sub.line_id
            WHERE sub.student_id = (SELECT auth.uid()) AND sub.status = 'active' AND sl.supervisor_id = supervisors.id)));

-- students: the person, the platform, the companies they are an active member of,
-- and the supervisors of a line they ride now.
DROP POLICY IF EXISTS students_read_scope ON public.students;
DROP POLICY IF EXISTS students_company_manage ON public.students;
DROP POLICY IF EXISTS students_delete_scope ON public.students;
CREATE POLICY students_read_scope ON public.students FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid())
      OR (SELECT public.is_super_admin())
      OR EXISTS (SELECT 1 FROM public.company_students m
                 WHERE m.student_id = students.id AND m.status = 'active'
                   AND m.company_id = (SELECT public.managed_company_id()))
      OR ((SELECT public.is_supervisor()) AND EXISTS (
            SELECT 1 FROM public.subscriptions sub
            WHERE sub.student_id = students.id AND sub.status = 'active'
              AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a))));
-- The account belongs to the person: a company removes a member, it does not
-- rewrite or delete the account.
CREATE POLICY students_platform_manage ON public.students FOR UPDATE TO authenticated
  USING ((SELECT public.is_super_admin())) WITH CHECK ((SELECT public.is_super_admin()));
CREATE POLICY students_delete_scope ON public.students FOR DELETE TO authenticated
  USING (id = (SELECT auth.uid()) OR (SELECT public.is_super_admin()));

-- subscriptions
DROP POLICY IF EXISTS subscriptions_company_manage ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_read_scope ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_student_delete ON public.subscriptions;
CREATE POLICY subscriptions_read_scope ON public.subscriptions FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid())
      OR ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
      OR ((SELECT public.is_supervisor()) AND line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a)));
CREATE POLICY subscriptions_company_insert ON public.subscriptions FOR INSERT TO authenticated
  WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
          AND ((SELECT public.is_super_admin()) OR public.is_company_member(company_id, student_id)));
CREATE POLICY subscriptions_company_update ON public.subscriptions FOR UPDATE TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY subscriptions_delete_scope ON public.subscriptions FOR DELETE TO authenticated
  USING (student_id = (SELECT auth.uid()) OR ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));

-- receipts
DROP POLICY IF EXISTS receipts_company_review ON public.receipts;
DROP POLICY IF EXISTS receipts_read_scope ON public.receipts;
CREATE POLICY receipts_company_review ON public.receipts FOR UPDATE TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY receipts_read_scope ON public.receipts FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
      OR EXISTS (SELECT 1 FROM public.subscriptions sub
                 WHERE sub.id = receipts.subscription_id AND sub.student_id = (SELECT auth.uid())));

-- rides: each vote belongs to the company whose subscription it was cast under
DROP POLICY IF EXISTS daily_rides_company_manage ON public.daily_ride_status;
DROP POLICY IF EXISTS daily_rides_read_scope ON public.daily_ride_status;
CREATE POLICY daily_rides_company_manage ON public.daily_ride_status FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY daily_rides_read_scope ON public.daily_ride_status FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid())
      OR ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
      OR ((SELECT public.is_supervisor()) AND EXISTS (
            SELECT 1 FROM public.subscriptions sub
            WHERE sub.student_id = daily_ride_status.student_id AND sub.status = 'active'
              AND sub.line_id IN (SELECT a.line_id FROM public.get_supervisor_assigned_line_ids() a))));

-- complaints: to one company, or (no company) to the platform
DROP POLICY IF EXISTS complaints_company_manage ON public.complaints;
DROP POLICY IF EXISTS complaints_read_scope ON public.complaints;
CREATE POLICY complaints_company_manage ON public.complaints FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
CREATE POLICY complaints_read_scope ON public.complaints FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid()) OR ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));

DROP POLICY IF EXISTS chat_messages_read_scope ON public.chat_messages;
CREATE POLICY chat_messages_read_scope ON public.chat_messages FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid()) OR supervisor_id = (SELECT auth.uid())
      OR ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));

DROP POLICY IF EXISTS scan_events_read_scope ON public.supervisor_scan_events;
CREATE POLICY scan_events_read_scope ON public.supervisor_scan_events FOR SELECT TO authenticated
  USING (supervisor_id = (SELECT auth.uid()) OR ((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));

DROP POLICY IF EXISTS deleted_revenue_read_scope ON public.deleted_student_revenue;
CREATE POLICY deleted_revenue_read_scope ON public.deleted_student_revenue FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));

DROP POLICY IF EXISTS payment_methods_manage ON public.company_payment_methods;
DROP POLICY IF EXISTS payment_methods_read ON public.company_payment_methods;
CREATE POLICY payment_methods_manage ON public.company_payment_methods FOR ALL TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))) WITH CHECK (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id())));
-- A student sees how to pay a company they subscribed with, or one that serves them.
CREATE POLICY payment_methods_read ON public.company_payment_methods FOR SELECT TO authenticated
  USING (((SELECT public.is_super_admin()) OR company_id = (SELECT public.managed_company_id()))
      OR (is_active AND company_id IN (SELECT public.active_company_ids()) AND NOT (SELECT public.is_staff_account())
          AND (EXISTS (SELECT 1 FROM public.subscriptions s
                       WHERE s.student_id = (SELECT auth.uid()) AND s.company_id = company_payment_methods.company_id)
            OR EXISTS (SELECT 1 FROM public.lines l
                       WHERE l.company_id = company_payment_methods.company_id AND l.is_active
                         AND EXISTS (SELECT 1 FROM public.line_trips t
                                     WHERE t.line_id = l.id AND t.direction = 'departure'
                                       AND public.trip_serves_student(t.*, (SELECT auth.uid())))))));

-- ---------------------------------------------------------------------------
-- 4. Files
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can manage scoped receipt objects" ON storage.objects;
CREATE POLICY "Admins can manage scoped receipt objects" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'receipts' AND EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id::text = (storage.foldername(name))[1]
      AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
      AND ((SELECT public.is_super_admin()) OR sub.company_id = (SELECT public.managed_company_id()))))
  WITH CHECK (bucket_id = 'receipts' AND EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id::text = (storage.foldername(name))[1]
      AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
      AND ((SELECT public.is_super_admin()) OR sub.company_id = (SELECT public.managed_company_id()))));

DROP POLICY IF EXISTS "Scoped receipt image access" ON storage.objects;
CREATE POLICY "Scoped receipt image access" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'receipts' AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR EXISTS (
      SELECT 1 FROM public.subscriptions sub
      WHERE sub.student_id::text = (storage.foldername(name))[1]
        AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
        AND ((SELECT public.is_super_admin()) OR sub.company_id = (SELECT public.managed_company_id())))));

-- A student's photo: the student, the platform, and companies they are an active member of.
DROP POLICY IF EXISTS "Students and scoped admins can view profile images" ON storage.objects;
CREATE POLICY "Students and scoped admins can view profile images" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'student-avatars' AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR (SELECT public.is_super_admin())
    OR ((SELECT public.is_company_admin()) AND EXISTS (
          SELECT 1 FROM public.company_students m
          WHERE m.student_id::text = (storage.foldername(name))[1] AND m.status = 'active'
            AND m.company_id = (SELECT public.current_admin_company_id())))));
