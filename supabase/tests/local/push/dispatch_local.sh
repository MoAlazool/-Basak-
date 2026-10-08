#!/usr/bin/env bash
# Runs the push dispatcher against the local stack with a fake FCM.
#   DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres \
#   SUPABASE_URL=http://127.0.0.1:54321 SERVICE_ROLE_KEY=… supabase/tests/local/push/dispatch_local.sh
# Uses one student who has a subscription; everything it adds is removed again.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
q() { psql "$db" -v ON_ERROR_STOP=1 -qAt "$@"; }

cleanup() {
  q -c "DELETE FROM public.notifications WHERE idempotency_key = 'push-local-test';
        DELETE FROM public.push_devices WHERE installation_id LIKE 'push-local-test-%';
        UPDATE public.push_runtime SET configured = NULL, checked_at = NULL WHERE id;" >/dev/null
}
trap cleanup EXIT
cleanup

if [ "$(q -c "SELECT count(*) FROM public.push_outbox WHERE status IN ('queued', 'sending')")" != "0" ]; then
  echo "the local outbox is not empty: clear it first" >&2; exit 1
fi
q >/dev/null <<'SQL'
DO $$
DECLARE s record;
BEGIN
  SELECT company_id, student_id, id INTO s FROM public.subscriptions ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'no subscription in the local database'; END IF;
  INSERT INTO public.push_devices(user_id, installation_id, platform, token, locale) VALUES
    (s.student_id, 'push-local-test-1', 'ios', 'arab' || repeat('1', 40), 'ar'),
    (s.student_id, 'push-local-test-2', 'android', 'engl' || repeat('2', 40), 'en-US'),
    (s.student_id, 'push-local-test-3', 'android', 'dead' || repeat('3', 40), 'ar');
  UPDATE public.notification_recipients SET read_at = now() WHERE user_id = s.student_id AND read_at IS NULL;
  PERFORM public.notify_student(s.company_id, s.student_id, 'subscription.approved',
                                jsonb_build_object('subscription_id', s.id), 'push-local-test');
END $$;
SQL

deno run -A "$here/dispatch_local.ts"

state="$(q -c "SELECT string_agg(left(d.token, 4) || ':' || o.status || ':' || (d.disabled_at IS NOT NULL), ',' ORDER BY d.token)
               FROM public.push_outbox o JOIN public.push_devices d ON d.id = o.device_id
               JOIN public.notifications n ON n.id = o.notification_id WHERE n.idempotency_key = 'push-local-test'")"
configured="$(q -c "SELECT configured FROM public.push_runtime WHERE id")"
if [ "$state" = "arab:accepted:false,dead:failed:true,engl:accepted:false" ] && [ "$configured" = "t" ]; then
  echo "PASS  the database records it: $state, configured"
else
  echo "FAIL  the database has: $state, configured=$configured"; exit 1
fi
