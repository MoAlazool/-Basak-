#!/usr/bin/env bash
# Prints a fingerprint of what each optimised function returns for fixed users on
# the LOCAL dataset, so "same answers before and after" can be checked:
#   ./outputs.sh > outputs-before.txt ; (apply the migration) ; ./outputs.sh | diff outputs-before.txt -
set -euo pipefail
db="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
q() { psql "$db" -v ON_ERROR_STOP=1 -qAt "$@"; }
company="$(q -c "SELECT id FROM companies WHERE name LIKE 'PERF %' ORDER BY name LIMIT 1")"
admin="$(q -c "SELECT id FROM admins WHERE company_id = '$company' LIMIT 1")"
super="$(q -c "SELECT id FROM admins WHERE role = 'super_admin' LIMIT 1")"
supervisor="$(q -c "SELECT id FROM supervisors WHERE company_id = '$company' LIMIT 1")"
line="$(q -c "SELECT line_id FROM supervisor_lines WHERE supervisor_id = '$supervisor' ORDER BY line_id LIMIT 1")"
trip="$(q -c "SELECT id FROM line_trips WHERE line_id = '$line' AND direction = 'departure' ORDER BY start_time LIMIT 1")"
students="$(q -c "SELECT string_agg(id::text, ' ') FROM (SELECT st.id FROM students st JOIN company_students cs ON cs.student_id = st.id WHERE cs.company_id = '$company' ORDER BY st.phone LIMIT 3) x")"

# as <user> <label> <jsonb expression>: md5 of the canonical jsonb text.
as() {
  printf '%s\t' "$2"
  q <<SQL | tail -1
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', '$1', 'role', 'authenticated')::text, true);
SELECT md5(($3)::text);
ROLLBACK;
SQL
}
as "$admin" "company_overview" "public.company_overview('$company')"
as "$super" "platform_overview" "public.platform_overview()"
as "$admin" "report totals (all)" "public.admin_subscription_report('{}'::jsonb) - 'rows'"
as "$admin" "report one line (rows too)" "public.admin_subscription_report(jsonb_build_object('line_id', '$line'))"
as "$admin" "report unpaid + search" "public.admin_subscription_report('{\"payment\": \"unpaid\", \"search\": \"1-2\"}'::jsonb)"
as "$admin" "report current phase, first term" "public.admin_subscription_report('{\"phase\": \"current\", \"period\": \"first\"}'::jsonb) - 'rows'"
as "$super" "report as platform (totals)" "public.admin_subscription_report('{}'::jsonb) - 'rows'"
as "$supervisor" "supervisor dashboard" "public.get_supervisor_dashboard()"
as "$supervisor" "trip manifest" "public.get_supervisor_trip_manifest('$line', 'departure', '$trip')"
as "$supervisor" "line rider counts" "public.get_line_rider_counts_with_returns('$line', public.cairo_today())"
for s in $students; do as "$s" "catalog for a student" "public.get_subscription_catalog()"; done
