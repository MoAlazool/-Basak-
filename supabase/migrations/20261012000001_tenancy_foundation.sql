-- Multi-tenant foundation (additive). Nothing that works today changes:
--   * companies get a status (active / suspended / archived)
--   * one access rule for every tenant-owned row: has_company_access(company_id)
--   * students become members of the companies they ride with (company_students)
--   * every tenant-owned table carries company_id, filled by the database
-- The policies that rely on these arrive in a later migration.

-- ---------------------------------------------------------------------------
-- 1. Company status
-- ---------------------------------------------------------------------------
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active'
    CONSTRAINT companies_status_check CHECK (status IN ('active', 'suspended', 'archived'));

UPDATE public.companies SET status = 'suspended' WHERE NOT is_active AND status = 'active';

-- is_active is what the rest of the schema reads; the two are kept identical.
CREATE OR REPLACE FUNCTION public.sync_company_status() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active' THEN NEW.is_active := false;
    ELSIF NOT NEW.is_active THEN NEW.status := 'suspended';
    END IF;
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.is_active := (NEW.status = 'active');
  ELSIF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
    NEW.status := CASE WHEN NEW.is_active THEN 'active' ELSE 'suspended' END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_company_status ON public.companies;
CREATE TRIGGER trg_sync_company_status BEFORE INSERT OR UPDATE OF status, is_active ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.sync_company_status();

-- Two companies with the same name cannot be told apart anywhere in the product.
CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_name ON public.companies (lower(btrim(name)));

-- ---------------------------------------------------------------------------
-- 2. The access rule
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_is_active(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT status = 'active' FROM public.companies WHERE id = p_company_id), false)
$$;

CREATE OR REPLACE FUNCTION public.current_supervisor_company_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT company_id FROM public.supervisors WHERE id = auth.uid() AND is_active
$$;

-- Manage a company: the platform admin, or that company's own admin while the company is active.
CREATE OR REPLACE FUNCTION public.can_manage_company(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_super_admin()
      OR (p_company_id IS NOT NULL AND p_company_id = public.current_admin_company_id()
          AND public.company_is_active(p_company_id))
$$;

-- Work inside a company: whoever manages it, plus its own active supervisors.
CREATE OR REPLACE FUNCTION public.has_company_access(p_company_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.can_manage_company(p_company_id)
      OR (p_company_id IS NOT NULL AND p_company_id = public.current_supervisor_company_id()
          AND public.company_is_active(p_company_id))
$$;

REVOKE ALL ON FUNCTION public.company_is_active(uuid), public.current_supervisor_company_id(),
  public.can_manage_company(uuid), public.has_company_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_is_active(uuid), public.current_supervisor_company_id(),
  public.can_manage_company(uuid), public.has_company_access(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Student membership
-- ---------------------------------------------------------------------------
-- A student is one person with one account, QR and wallet card. What a company
-- may see or do with them follows from an active row here, not from history.
CREATE TABLE IF NOT EXISTS public.company_students (
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  removed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  PRIMARY KEY (company_id, student_id),
  CONSTRAINT company_students_removed_check CHECK ((status = 'removed') = (removed_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_company_students_student ON public.company_students (student_id);

ALTER TABLE public.company_students ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_students_read ON public.company_students;
CREATE POLICY company_students_read ON public.company_students FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid()) OR public.has_company_access(company_id));
-- Written only by the database (subscribing) and by the functions below.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.company_students FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id uuid, p_student_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.company_students
                 WHERE company_id = p_company_id AND student_id = p_student_id AND status = 'active')
$$;
REVOKE ALL ON FUNCTION public.is_company_member(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_company_member(uuid, uuid) TO authenticated, service_role;

-- Subscribing with a company makes the student its member (again, if they had been removed).
CREATE OR REPLACE FUNCTION public.link_subscription_member() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.company_id IS NOT NULL THEN
    INSERT INTO public.company_students (company_id, student_id) VALUES (NEW.company_id, NEW.student_id)
    ON CONFLICT (company_id, student_id) DO UPDATE
      SET status = 'active', removed_at = NULL, removed_by = NULL, joined_at = now()
      WHERE public.company_students.status = 'removed';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.link_subscription_member() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_link_subscription_member ON public.subscriptions;
CREATE TRIGGER trg_link_subscription_member AFTER INSERT ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.link_subscription_member();

INSERT INTO public.company_students (company_id, student_id, joined_at)
SELECT l.company_id, s.student_id, min(s.created_at)
FROM public.subscriptions s JOIN public.lines l ON l.id = s.line_id
GROUP BY l.company_id, s.student_id
ON CONFLICT DO NOTHING;

-- Removing a student from a company ends what is still open with that company
-- and nothing else: the account, QR, wallet card and other companies are untouched.
CREATE OR REPLACE FUNCTION public.company_remove_student(p_company_id uuid, p_student_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ended int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.can_manage_company(p_company_id) THEN
    RAISE EXCEPTION 'غير مسموح بإدارة طلاب هذه الشركة.' USING ERRCODE = '42501';
  END IF;
  UPDATE public.company_students
  SET status = 'removed', removed_at = now(), removed_by = auth.uid()
  WHERE company_id = p_company_id AND student_id = p_student_id AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'هذا الطالب غير مسجل في الشركة.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.receipts r SET status = 'rejected', rejection_reason = 'أُزيل الطالب من الشركة.'
  FROM public.subscriptions s
  WHERE s.id = r.subscription_id AND s.student_id = p_student_id AND s.company_id = p_company_id
    AND r.status = 'pending';
  UPDATE public.subscriptions SET status = 'expired'
  WHERE student_id = p_student_id AND company_id = p_company_id
    AND status IN ('pending_payment', 'pending_review', 'active');
  GET DIAGNOSTICS v_ended = ROW_COUNT;
  RETURN jsonb_build_object('removed', true, 'ended_subscriptions', v_ended);
END;
$$;
REVOKE ALL ON FUNCTION public.company_remove_student(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_remove_student(uuid, uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. company_id on every tenant-owned table
-- ---------------------------------------------------------------------------
ALTER TABLE public.stations                  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.line_trips                ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.line_trip_stops           ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.line_universities         ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.line_university_schedules ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.supervisor_lines          ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.receipts                  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.supervisor_scan_events    ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.chat_messages             ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.daily_ride_status         ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
ALTER TABLE public.daily_ride_status         ADD COLUMN IF NOT EXISTS subscription_id uuid REFERENCES public.subscriptions(id) ON DELETE SET NULL;
-- NULL = written by a student who rides with no company yet: the platform's to answer.
ALTER TABLE public.complaints                ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id);
-- Which company asked for a password to be reset (audit only).
ALTER TABLE public.password_admin_resets     ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL;

-- The company always comes from the parent row, never from the caller.
CREATE OR REPLACE FUNCTION public.tenant_company_from_parent() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  CASE TG_ARGV[0]
    WHEN 'line' THEN
      SELECT l.company_id INTO NEW.company_id FROM public.lines l WHERE l.id = NEW.line_id;
    WHEN 'trip' THEN
      SELECT l.company_id INTO NEW.company_id
      FROM public.line_trips t JOIN public.lines l ON l.id = t.line_id WHERE t.id = NEW.trip_id;
    WHEN 'subscription' THEN
      SELECT l.company_id INTO NEW.company_id
      FROM public.subscriptions s JOIN public.lines l ON l.id = s.line_id WHERE s.id = NEW.subscription_id;
    WHEN 'supervisor' THEN
      SELECT s.company_id INTO NEW.company_id FROM public.supervisors s WHERE s.id = NEW.supervisor_id;
  END CASE;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.tenant_company_from_parent() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('stations', 'line', 'line_id'), ('line_trips', 'line', 'line_id'),
      ('line_universities', 'line', 'line_id'), ('line_university_schedules', 'line', 'line_id'),
      ('supervisor_lines', 'line', 'line_id'), ('line_trip_stops', 'trip', 'trip_id'),
      ('receipts', 'subscription', 'subscription_id'),
      ('supervisor_scan_events', 'supervisor', 'supervisor_id'),
      ('chat_messages', 'supervisor', 'supervisor_id')) AS t(tbl, parent, col)
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_tenant_company ON public.%I', r.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_tenant_company BEFORE INSERT OR UPDATE OF %I, company_id ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.tenant_company_from_parent(%L)', r.col, r.tbl, r.parent);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (company_id)', 'idx_' || r.tbl || '_company', r.tbl);
  END LOOP;
END;
$$;
CREATE INDEX IF NOT EXISTS idx_subscriptions_company ON public.subscriptions (company_id);
CREATE INDEX IF NOT EXISTS idx_daily_ride_status_company ON public.daily_ride_status (company_id, ride_date);
CREATE INDEX IF NOT EXISTS idx_complaints_company ON public.complaints (company_id);

-- A ride vote belongs to the subscription it is cast under.
CREATE OR REPLACE FUNCTION public.tenant_company_for_ride() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sub record;
BEGIN
  SELECT s.id, l.company_id INTO v_sub
  FROM public.subscriptions s JOIN public.lines l ON l.id = s.line_id
  WHERE s.student_id = NEW.student_id AND s.status = 'active'
    AND (s.start_date IS NULL OR s.start_date <= NEW.ride_date)
    AND (s.end_date IS NULL OR s.end_date >= NEW.ride_date)
  ORDER BY s.created_at DESC LIMIT 1;
  IF FOUND THEN
    NEW.subscription_id := v_sub.id;
    NEW.company_id := v_sub.company_id;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.subscription_id := OLD.subscription_id;
    NEW.company_id := OLD.company_id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.tenant_company_for_ride() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_tenant_company ON public.daily_ride_status;
CREATE TRIGGER trg_tenant_company
  BEFORE INSERT OR UPDATE OF student_id, ride_date, is_riding, subscription_id, company_id ON public.daily_ride_status
  FOR EACH ROW EXECUTE FUNCTION public.tenant_company_for_ride();

-- A complaint goes to the company the student names (it must be one of theirs),
-- otherwise to the company they currently ride with.
CREATE OR REPLACE FUNCTION public.tenant_company_for_complaint() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.company_id := OLD.company_id;
    RETURN NEW;
  END IF;
  IF NEW.company_id IS NOT NULL AND NOT public.is_company_member(NEW.company_id, NEW.student_id) THEN
    NEW.company_id := NULL;
  END IF;
  IF NEW.company_id IS NULL THEN
    SELECT s.company_id INTO NEW.company_id
    FROM public.subscriptions s
    WHERE s.student_id = NEW.student_id AND public.is_company_member(s.company_id, s.student_id)
    ORDER BY (s.status = 'active') DESC, s.created_at DESC LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.tenant_company_for_complaint() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_tenant_company ON public.complaints;
CREATE TRIGGER trg_tenant_company BEFORE INSERT OR UPDATE OF company_id, student_id ON public.complaints
  FOR EACH ROW EXECUTE FUNCTION public.tenant_company_for_complaint();

-- Backfill ------------------------------------------------------------------
UPDATE public.subscriptions s SET company_id = l.company_id
FROM public.lines l WHERE l.id = s.line_id AND s.company_id IS DISTINCT FROM l.company_id;

UPDATE public.stations x                  SET company_id = l.company_id FROM public.lines l WHERE l.id = x.line_id AND x.company_id IS NULL;
UPDATE public.line_trips x                SET company_id = l.company_id FROM public.lines l WHERE l.id = x.line_id AND x.company_id IS NULL;
UPDATE public.line_universities x         SET company_id = l.company_id FROM public.lines l WHERE l.id = x.line_id AND x.company_id IS NULL;
UPDATE public.line_university_schedules x SET company_id = l.company_id FROM public.lines l WHERE l.id = x.line_id AND x.company_id IS NULL;
UPDATE public.supervisor_lines x          SET company_id = l.company_id FROM public.lines l WHERE l.id = x.line_id AND x.company_id IS NULL;
UPDATE public.line_trip_stops x           SET company_id = t.company_id FROM public.line_trips t WHERE t.id = x.trip_id AND x.company_id IS NULL;
UPDATE public.receipts x                  SET company_id = s.company_id FROM public.subscriptions s WHERE s.id = x.subscription_id AND x.company_id IS NULL;
UPDATE public.supervisor_scan_events x    SET company_id = s.company_id FROM public.supervisors s WHERE s.id = x.supervisor_id AND x.company_id IS NULL;
UPDATE public.chat_messages x             SET company_id = s.company_id FROM public.supervisors s WHERE s.id = x.supervisor_id AND x.company_id IS NULL;

-- Rides: the subscription that covered the day, else the student's nearest one.
UPDATE public.daily_ride_status d SET subscription_id = pick.id, company_id = pick.company_id
FROM public.daily_ride_status x
CROSS JOIN LATERAL (
  SELECT s.id, s.company_id FROM public.subscriptions s
  WHERE s.student_id = x.student_id
  ORDER BY (s.start_date <= x.ride_date AND s.end_date >= x.ride_date) DESC NULLS LAST,
           (s.status = 'active') DESC, s.created_at DESC
  LIMIT 1) pick
WHERE x.id = d.id AND d.company_id IS NULL;

UPDATE public.complaints c SET company_id = pick.company_id
FROM public.complaints x
CROSS JOIN LATERAL (
  SELECT s.company_id FROM public.subscriptions s
  WHERE s.student_id = x.student_id
  ORDER BY (s.created_at <= x.created_at) DESC, s.created_at DESC LIMIT 1) pick
WHERE x.id = c.id AND c.company_id IS NULL;

-- Every row that has a parent must now have its company.
DO $$
DECLARE r record; v_missing bigint;
BEGIN
  FOR r IN SELECT unnest(ARRAY['subscriptions', 'stations', 'line_trips', 'line_trip_stops', 'line_universities',
                               'line_university_schedules', 'supervisor_lines', 'receipts',
                               'supervisor_scan_events', 'chat_messages']) AS tbl
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE company_id IS NULL', r.tbl) INTO v_missing;
    IF v_missing > 0 THEN
      RAISE EXCEPTION 'tenancy backfill: % row(s) in % have no company', v_missing, r.tbl;
    END IF;
  END LOOP;
END;
$$;
