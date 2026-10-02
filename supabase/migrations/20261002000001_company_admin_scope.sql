-- Company-scoped administrator roles. Company ownership is resolved from the
-- admins table inside SECURITY DEFINER helpers, never from client-supplied IDs.
BEGIN;

ALTER TABLE public.admins
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'super_admin',
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS created_by_admin_id uuid REFERENCES public.admins(id) ON DELETE RESTRICT;

ALTER TABLE public.admins DROP CONSTRAINT IF EXISTS admins_role_company_check;
ALTER TABLE public.admins ADD CONSTRAINT admins_role_company_check CHECK (
  (role = 'super_admin' AND company_id IS NULL)
  OR (role = 'company_admin' AND company_id IS NOT NULL AND created_by_admin_id IS NOT NULL)
);
ALTER TABLE public.admins DROP CONSTRAINT IF EXISTS admins_role_check;
ALTER TABLE public.admins ADD CONSTRAINT admins_role_check CHECK (role IN ('super_admin', 'company_admin'));

-- Preserve attribution for revenue archived after student deletion.
ALTER TABLE public.deleted_student_revenue
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE RESTRICT;
UPDATE public.deleted_student_revenue archive
SET company_id = lines.company_id
FROM public.lines
WHERE archive.company_id IS NULL AND archive.line_id = lines.id;
CREATE INDEX IF NOT EXISTS idx_deleted_student_revenue_company
  ON public.deleted_student_revenue(company_id);

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_ride_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supervisors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deleted_student_revenue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colleges ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_admin_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.admins WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.current_admin_company_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT company_id FROM public.admins WHERE id = auth.uid() AND role = 'company_admin'
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.current_admin_role() = 'super_admin', false)
$$;

CREATE OR REPLACE FUNCTION public.is_company_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.current_admin_role() = 'company_admin', false)
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(public.current_admin_role() IN ('super_admin', 'company_admin'), false)
$$;

GRANT EXECUTE ON FUNCTION public.current_admin_role(), public.current_admin_company_id(),
  public.is_super_admin(), public.is_company_admin(), public.is_admin() TO authenticated;
REVOKE ALL ON FUNCTION public.current_admin_role(), public.current_admin_company_id(),
  public.is_super_admin(), public.is_company_admin() FROM anon;

-- Remove legacy policies whose OR semantics would otherwise bypass the new
-- tenant scope, including the former anon-wide dashboard policies.
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'companies','lines','stations','students','admins','subscriptions','receipts',
        'daily_ride_status','supervisors','chat_messages','complaints',
        'deleted_student_revenue','universities','colleges'
      ])
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;

  -- The dashboard used to ship with anon-wide policies. There must be no
  -- anonymous path around authenticated company scoping.
  FOR p IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND 'anon' = ANY(roles)
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;
END $$;

CREATE POLICY companies_read_scope ON public.companies FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND companies.id = public.current_admin_company_id())
  OR (NOT public.is_admin() AND is_active)
);
CREATE POLICY companies_super_admin_manage ON public.companies FOR ALL TO authenticated
USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

CREATE POLICY lines_read_scope ON public.lines FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND company_id = public.current_admin_company_id())
  OR (NOT public.is_admin() AND (is_active OR public.is_supervisor()))
);
CREATE POLICY lines_company_manage ON public.lines FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND company_id = public.current_admin_company_id()))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND company_id = public.current_admin_company_id()));

CREATE POLICY stations_read_scope ON public.stations FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
  ))
  OR (NOT public.is_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.is_active
  ))
);
CREATE POLICY stations_company_manage ON public.stations FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
)))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
)));

CREATE POLICY supervisors_read_scope ON public.supervisors FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND company_id = public.current_admin_company_id())
  OR (NOT public.is_admin() AND supervisors.id = auth.uid())
  OR (NOT public.is_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = auth.uid() AND sub.status = 'active' AND l.supervisor_id = supervisors.id
  ))
);
CREATE POLICY supervisors_company_manage ON public.supervisors FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND company_id = public.current_admin_company_id()))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND company_id = public.current_admin_company_id()));

CREATE POLICY students_read_scope ON public.students FOR SELECT TO authenticated
USING (
  students.id = auth.uid()
  OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = students.id AND l.company_id = public.current_admin_company_id()
  ))
  OR (public.is_supervisor() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = students.id AND sub.status = 'active'
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ))
);
CREATE POLICY students_register_self ON public.students FOR INSERT TO authenticated WITH CHECK (students.id = auth.uid());
CREATE POLICY students_delete_scope ON public.students FOR DELETE TO authenticated
USING (
  students.id = auth.uid() OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = students.id AND l.company_id = public.current_admin_company_id()
  ))
);
CREATE POLICY students_company_manage ON public.students FOR UPDATE TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = students.id AND l.company_id = public.current_admin_company_id()
)))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = students.id AND l.company_id = public.current_admin_company_id()
)));

CREATE POLICY admins_read_self_or_super ON public.admins FOR SELECT TO authenticated
USING (id = auth.uid() OR public.is_super_admin());

CREATE POLICY subscriptions_read_scope ON public.subscriptions FOR SELECT TO authenticated
USING (
  student_id = auth.uid()
  OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
  ))
  OR (public.is_supervisor() AND line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids()))
);
CREATE POLICY subscriptions_student_insert ON public.subscriptions FOR INSERT TO authenticated
WITH CHECK (student_id = auth.uid());
CREATE POLICY subscriptions_student_delete ON public.subscriptions FOR DELETE TO authenticated
USING (student_id = auth.uid() OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
  )));
CREATE POLICY subscriptions_company_manage ON public.subscriptions FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
)))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.lines l WHERE l.id = line_id AND l.company_id = public.current_admin_company_id()
)));
CREATE POLICY subscriptions_supervisor_update ON public.subscriptions FOR UPDATE TO authenticated
USING (public.is_supervisor() AND line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids()))
WITH CHECK (public.is_supervisor() AND line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids()));

CREATE POLICY receipts_read_scope ON public.receipts FOR SELECT TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.id = subscription_id AND l.company_id = public.current_admin_company_id()
  ))
  OR EXISTS (SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id AND sub.student_id = auth.uid())
  OR (public.is_supervisor() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ))
);
CREATE POLICY receipts_student_insert ON public.receipts FOR INSERT TO authenticated
WITH CHECK (EXISTS (
  SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id AND sub.student_id = auth.uid()
));
CREATE POLICY receipts_company_review ON public.receipts FOR UPDATE TO authenticated
USING (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.id = subscription_id AND l.company_id = public.current_admin_company_id()
  ))
  OR (public.is_supervisor() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ))
)
WITH CHECK (
  public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.id = subscription_id AND l.company_id = public.current_admin_company_id()
  ))
  OR (public.is_supervisor() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub WHERE sub.id = subscription_id
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ))
);

CREATE POLICY daily_rides_read_scope ON public.daily_ride_status FOR SELECT TO authenticated
USING (
  student_id = auth.uid() OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = daily_ride_status.student_id AND l.company_id = public.current_admin_company_id()
  ))
  OR (public.is_supervisor() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub WHERE sub.student_id = daily_ride_status.student_id AND sub.status = 'active'
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ))
);
CREATE POLICY daily_rides_student_insert ON public.daily_ride_status FOR INSERT TO authenticated
WITH CHECK (student_id = auth.uid());
CREATE POLICY daily_rides_student_update ON public.daily_ride_status FOR UPDATE TO authenticated
USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());
CREATE POLICY daily_rides_company_manage ON public.daily_ride_status FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = daily_ride_status.student_id AND l.company_id = public.current_admin_company_id()
)))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = daily_ride_status.student_id AND l.company_id = public.current_admin_company_id()
)));

CREATE POLICY chat_messages_read_scope ON public.chat_messages FOR SELECT TO authenticated
USING (
  student_id = auth.uid() OR supervisor_id = auth.uid() OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = chat_messages.student_id AND l.company_id = public.current_admin_company_id()
  ))
);
CREATE POLICY chat_messages_participant_insert ON public.chat_messages FOR INSERT TO authenticated
WITH CHECK ((sender_role = 'student' AND student_id = auth.uid()) OR (sender_role = 'supervisor' AND supervisor_id = auth.uid()));
CREATE POLICY chat_messages_super_manage ON public.chat_messages FOR ALL TO authenticated
USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

CREATE POLICY complaints_read_scope ON public.complaints FOR SELECT TO authenticated
USING (
  student_id = auth.uid() OR public.is_super_admin()
  OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = complaints.student_id AND l.company_id = public.current_admin_company_id()
  ))
);
CREATE POLICY complaints_student_insert ON public.complaints FOR INSERT TO authenticated
WITH CHECK (student_id = auth.uid());
CREATE POLICY complaints_company_manage ON public.complaints FOR ALL TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = complaints.student_id AND l.company_id = public.current_admin_company_id()
)))
WITH CHECK (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
  SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
  WHERE sub.student_id = complaints.student_id AND l.company_id = public.current_admin_company_id()
)));

CREATE POLICY deleted_revenue_read_scope ON public.deleted_student_revenue FOR SELECT TO authenticated
USING (public.is_super_admin() OR (public.is_company_admin() AND company_id = public.current_admin_company_id()));

-- Shared academic catalog remains available to students, but not manageable or
-- visible to tenant admins as a cross-company resource.
CREATE POLICY universities_student_read ON public.universities FOR SELECT TO authenticated
USING (public.is_super_admin() OR (NOT public.is_admin() AND is_active));
CREATE POLICY universities_super_manage ON public.universities FOR ALL TO authenticated
USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());
CREATE POLICY colleges_student_read ON public.colleges FOR SELECT TO authenticated
USING (public.is_super_admin() OR (NOT public.is_admin() AND is_active));
CREATE POLICY colleges_super_manage ON public.colleges FOR ALL TO authenticated
USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- Signed receipt image access follows the same company/line checks as receipt rows.
DROP POLICY IF EXISTS "Supervisors can view assigned line student receipts" ON storage.objects;
DROP POLICY IF EXISTS "Admins full access on receipts bucket" ON storage.objects;
CREATE POLICY "Admin and supervisor scoped receipt access" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'receipts' AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
      WHERE sub.student_id::text = (storage.foldername(name))[1]
        AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
        AND l.company_id = public.current_admin_company_id()
    ))
    OR (public.is_supervisor() AND EXISTS (
      SELECT 1 FROM public.subscriptions sub
      WHERE sub.student_id::text = (storage.foldername(name))[1]
        AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
    ))
  )
);
CREATE POLICY "Admins can manage scoped receipt objects" ON storage.objects FOR ALL TO authenticated
USING (
  bucket_id = 'receipts' AND (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id::text = (storage.foldername(name))[1]
      AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
      AND l.company_id = public.current_admin_company_id()
  )))
)
WITH CHECK (
  bucket_id = 'receipts' AND (public.is_super_admin() OR (public.is_company_admin() AND EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id::text = (storage.foldername(name))[1]
      AND left(split_part(name, '/', 2), length(sub.id::text) + 1) = sub.id::text || '_'
      AND l.company_id = public.current_admin_company_id()
  )))
);

DROP POLICY IF EXISTS "Students and admins can view profile images" ON storage.objects;
CREATE POLICY "Students and scoped admins can view profile images" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'student-avatars' AND (
    (storage.foldername(name))[1] = auth.uid()::text OR public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
      WHERE sub.student_id::text = (storage.foldername(name))[1]
        AND l.company_id = public.current_admin_company_id()
    ))
  )
);

CREATE OR REPLACE FUNCTION public.archive_student_revenue_before_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.deleted_student_revenue (
    source_subscription_id, line_id, line_name, company_name, company_id, amount, subscription_type
  )
  SELECT sub.id, sub.line_id, l.name, c.name, l.company_id, sub.price, sub.type
  FROM public.subscriptions sub
  LEFT JOIN public.lines l ON l.id = sub.line_id
  LEFT JOIN public.companies c ON c.id = l.company_id
  WHERE sub.student_id = OLD.id AND sub.status = 'active'
  ON CONFLICT (source_subscription_id) DO NOTHING;
  RETURN OLD;
END;
$$;

-- SECURITY DEFINER RPCs bypass RLS and therefore must enforce tenant scope themselves.
-- The older counts RPC is still used by the supervisor app. Check ownership
-- before running its SECURITY DEFINER query as well.
CREATE OR REPLACE FUNCTION public.get_line_rider_counts(p_line_id uuid, p_ride_date date)
RETURNS TABLE (
  station_id uuid, station_name text, order_index integer,
  departure_time time, return_time time, riding_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()
    ))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;

  RETURN QUERY
  SELECT st.id, st.name, st.order_index, st.departure_time, st.return_time,
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true)
  FROM public.stations st
  LEFT JOIN public.subscriptions sub ON sub.station_id = st.id AND sub.status = 'active'
  LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
  WHERE st.line_id = p_line_id
  GROUP BY st.id, st.name, st.order_index, st.departure_time, st.return_time
  ORDER BY st.order_index;
END;
$$;

-- QR lookup is another SECURITY DEFINER path. First resolve the QR to a
-- student and require a subscription on the caller's company line.
CREATE OR REPLACE FUNCTION public.lookup_student_by_qr(p_qr_code uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_student_id uuid;
  v_data jsonb;
BEGIN
  IF NOT (public.is_supervisor() OR public.is_admin()) THEN
    RAISE EXCEPTION 'Access denied. Only supervisors and admins can perform QR lookups.';
  END IF;

  SELECT s.id INTO v_student_id FROM public.students s WHERE s.qr_code_value = p_qr_code;
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Student not found with the provided QR code.';
  END IF;

  IF public.is_company_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub JOIN public.lines l ON l.id = sub.line_id
    WHERE sub.student_id = v_student_id AND l.company_id = public.current_admin_company_id()
  ) THEN
    RAISE EXCEPTION 'Student is outside your company.';
  END IF;

  IF public.is_supervisor() AND NOT public.is_admin() AND NOT EXISTS (
    SELECT 1 FROM public.subscriptions sub
    WHERE sub.student_id = v_student_id AND sub.status = 'active'
      AND sub.line_id IN (SELECT line_id FROM public.get_supervisor_assigned_line_ids())
  ) THEN
    RAISE EXCEPTION 'Student is outside your assigned lines.';
  END IF;

  SELECT jsonb_build_object(
    'id', s.id, 'full_name', s.full_name, 'phone', s.phone, 'university', s.university,
    'subscription', (
      SELECT jsonb_build_object(
        'id', sub.id, 'type', sub.type, 'status', sub.status,
        'start_date', sub.start_date, 'end_date', sub.end_date,
        'line_name', l.name, 'station_name', st.name,
        'departure_time', COALESCE(sub.departure_time, st.departure_time),
        'return_time', COALESCE(sub.return_time, st.return_time),
        'payment_date', (SELECT r.reviewed_at FROM public.receipts r
          WHERE r.subscription_id = sub.id AND r.status = 'approved'
          ORDER BY r.reviewed_at DESC LIMIT 1)
      )
      FROM public.subscriptions sub
      JOIN public.lines l ON l.id = sub.line_id
      JOIN public.stations st ON st.id = sub.station_id
      WHERE sub.student_id = s.id AND sub.status IN ('active', 'pending_review', 'pending_payment')
        AND (NOT public.is_company_admin() OR l.company_id = public.current_admin_company_id())
        AND (NOT public.is_supervisor() OR public.is_admin() OR sub.line_id IN (
          SELECT line_id FROM public.get_supervisor_assigned_line_ids()))
      ORDER BY sub.created_at DESC LIMIT 1
    ),
    'today_ride_status', (SELECT COALESCE(drs.is_riding, false)
      FROM public.daily_ride_status drs WHERE drs.student_id = s.id AND drs.ride_date = CURRENT_DATE)
  ) INTO v_data FROM public.students s WHERE s.id = v_student_id;

  RETURN v_data;
END;
$$;

-- Ensure older projects have the scheduled reset function before restricting
-- execution. This remains scheduler-only, never an authenticated admin API.
CREATE OR REPLACE FUNCTION public.reset_daily_rides_at_1pm()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.daily_ride_status
  SET is_riding = false
  WHERE ride_date = (CURRENT_DATE + 1)
    AND toggled_at < (CURRENT_DATE || ' 13:00:00')::timestamptz;
END;
$$;

REVOKE ALL ON FUNCTION public.reset_daily_rides_at_1pm() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_line_rider_counts_with_returns(p_line_id uuid, p_ride_date date)
RETURNS TABLE (
  line_id uuid, line_name text, station_id uuid, station_name text, order_index integer,
  departure_time time, return_time time, riding_count bigint, returning_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.is_company_admin() AND EXISTS (
      SELECT 1 FROM public.lines l WHERE l.id = p_line_id AND l.company_id = public.current_admin_company_id()
    ))
    OR EXISTS (SELECT 1 FROM public.get_supervisor_assigned_line_ids() a WHERE a.line_id = p_line_id)
  ) THEN
    RAISE EXCEPTION 'هذا الخط غير مسند إلى حسابك.';
  END IF;

  RETURN QUERY
  SELECT l.id, l.name, st.id, st.name, st.order_index,
    COALESCE(st.departure_time, st.departure_times[1]),
    COALESCE(st.return_time, st.return_times[1]),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true),
    COUNT(drs.id) FILTER (WHERE drs.is_riding = true AND drs.is_returning = true)
  FROM public.stations st
  JOIN public.lines l ON l.id = st.line_id
  LEFT JOIN public.subscriptions sub ON sub.station_id = st.id AND sub.status = 'active'
  LEFT JOIN public.daily_ride_status drs ON drs.student_id = sub.student_id AND drs.ride_date = p_ride_date
  WHERE st.line_id = p_line_id AND st.is_active = true AND l.is_active = true
  GROUP BY l.id, l.name, st.id, st.name, st.order_index, st.departure_time,
    st.departure_times, st.return_time, st.return_times
  ORDER BY st.order_index;
END;
$$;

COMMIT;
