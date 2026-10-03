#!/usr/bin/env bash
# Applies every migration to a fresh local Postgres database (with a minimal
# Supabase stub) and runs the SQL end-to-end tests. Requires psql access to a
# disposable server: PGHOST/PGPORT/PGUSER must point at it (user = superuser).
#   PGHOST=/tmp PGPORT=5432 PGUSER=postgres supabase/tests/local/run_local.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
db="${BASAK_TEST_DB:-basak_test}"

export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "DROP DATABASE IF EXISTS $db" -c "CREATE DATABASE $db"
psql -v ON_ERROR_STOP=1 -q -d "$db" -c "ALTER DATABASE $db SET search_path = \"\$user\", public, extensions"
psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$here/supabase_stub.sql"
for f in "$root"/migrations/*.sql; do
  # Optional fixture applied just before a migration (simulates existing data).
  seed="$here/seed_before_$(basename "$f")"
  if [ -f "$seed" ]; then
    echo "== seed $(basename "$seed")"
    psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$seed" >/dev/null
  fi
  echo "== $(basename "$f")"
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$f" >/dev/null
done
shopt -s nullglob
for t in "$here"/e2e_*.sql; do
  echo "== TEST $(basename "$t")"
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$t"
done
