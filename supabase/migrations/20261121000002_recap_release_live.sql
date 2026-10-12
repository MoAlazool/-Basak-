-- ==============================================================================
-- Migration: 20261121000001_recap_release_live.sql
-- Run AFTER 20261119000004. Safe to re-run. Additive: one trigger.
--
-- When the platform publishes a term's recap, or stops publishing it, the
-- students' phones are told at once, so the banner on Home appears or goes
-- without the app being reopened. (Stopping sent nothing at all: the banner
-- stayed until the app was next opened.)
--
-- The word goes out on the lines' topics, which is where students already
-- listen; it carries no data, only that the releases changed:
--   {"table": "term_recap_releases", "op": "UPDATE", "id": <release id>}
-- ==============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.announce_recap_release() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_payload jsonb := jsonb_build_object('table', 'term_recap_releases', 'op', TG_OP, 'id', NEW.id);
  v_line uuid;
BEGIN
  -- Only when what students see changes: published or not.
  IF TG_OP = 'UPDATE'
     AND (OLD.published_at IS NOT NULL AND OLD.unpublished_at IS NULL)
       = (NEW.published_at IS NOT NULL AND NEW.unpublished_at IS NULL) THEN
    RETURN NULL;
  END IF;
  FOR v_line IN SELECT l.id FROM public.lines l WHERE public.company_is_active(l.company_id) LOOP
    PERFORM public.announce('line:' || v_line, v_payload);
  END LOOP;
  PERFORM public.announce('platform', v_payload);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.announce_recap_release() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_announce_recap_release ON public.term_recap_releases;
CREATE TRIGGER trg_announce_recap_release AFTER INSERT OR UPDATE ON public.term_recap_releases
  FOR EACH ROW EXECUTE FUNCTION public.announce_recap_release();

COMMIT;
