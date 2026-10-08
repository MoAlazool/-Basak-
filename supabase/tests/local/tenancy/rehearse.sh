#!/usr/bin/env bash
# Rehearses the tenancy migrations on a local copy of the live data.
#
#   STACK=<scratch copy of supabase/ with `supabase start` running> \
#   LIVE_DATA=<data-only dump of the live public schema> \
#   supabase/tests/local/tenancy/rehearse.sh
#
# The dump must not contain wallet_runtime / wallet_passes / wallet_apple_*: with
# them a local change could wake the live wallet service.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
: "${STACK:?}" "${LIVE_DATA:?}"
DB="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
BASE="${BASE_VERSION:-20261011000001}"
out="${OUT:-$STACK/rehearsal}"
mkdir -p "$out"

rsync -a --delete "$root/migrations/" "$STACK/supabase/migrations/"
(cd "$STACK" && supabase db reset --version "$BASE" >/dev/null 2>&1)

q() { psql "$DB" -v ON_ERROR_STOP=1 -q "$@"; }

# The demo rows the first migrations seed are not part of the live data.
q -c "DO \$\$ DECLARE t text; BEGIN
        FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'subscription_receipts' LOOP
          EXECUTE format('TRUNCATE public.%I CASCADE', t);
        END LOOP; END \$\$;"
grep -v '^\\\(un\)\?restrict' "$LIVE_DATA" | q -f - >/dev/null
# Accounts exist on the live project only; local stand-ins keep the foreign keys valid.
q -c "INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at,
                              confirmation_token, recovery_token, email_change_token_new, email_change)
      SELECT id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', id || '@local.test', now(), now(),
             '', '', '', ''
      FROM (SELECT id FROM public.students UNION SELECT id FROM public.supervisors UNION SELECT id FROM public.admins) u
      ON CONFLICT (id) DO NOTHING;
      INSERT INTO public.wallet_runtime (id) VALUES (true) ON CONFLICT DO NOTHING;
      UPDATE public.wallet_runtime SET sync_url = NULL;"

snapshot() { psql "$DB" -v ON_ERROR_STOP=1 -At -f "$here/snapshot.sql" | python3 -m json.tool --sort-keys --no-ensure-ascii > "$1"; }
snapshot "$out/before.json"
(cd "$STACK" && supabase migration up --local 2>&1 | grep -E 'Applying|ERROR|error' || true)
snapshot "$out/after.json"

if diff -u "$out/before.json" "$out/after.json" > "$out/diff.txt"; then
  echo "OK: counts, subscriptions and revenue are identical before and after."
else
  echo "DIFFERENT: see $out/diff.txt"; head -60 "$out/diff.txt"; exit 1
fi
q -At -f "$here/verify.sql"
