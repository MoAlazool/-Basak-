#!/usr/bin/env bash
# Times the statements behind the slow screens on the LOCAL database loaded with
# dataset.sql. Each case runs 5 times as the user who would run it (role + JWT
# claims, so RLS and triggers are included); the median execution time is kept.
#   supabase/tests/local/perf/measure.sh > before.tsv
set -euo pipefail
db="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
q() { psql "$db" -v ON_ERROR_STOP=1 -qAt "$@"; }

student="$(q -c "SELECT s.student_id FROM subscriptions s JOIN students st ON st.id = s.student_id
                 WHERE st.phone LIKE '0159%' AND s.status = 'active' ORDER BY st.phone LIMIT 1")"
company="$(q -c "SELECT company_id FROM subscriptions WHERE student_id = '$student' AND status = 'active'")"
admin="$(q -c "SELECT id FROM admins WHERE company_id = '$company' LIMIT 1")"
super="$(q -c "SELECT id FROM admins WHERE role = 'super_admin' LIMIT 1")"
supervisor="$(q -c "SELECT id FROM supervisors WHERE company_id = '$company' LIMIT 1")"
sub="$(q -c "SELECT id FROM subscriptions WHERE student_id = '$student' AND status = 'active'")"
pending="$(q -c "SELECT id FROM receipts WHERE company_id = '$company' AND status = 'pending' ORDER BY created_at LIMIT 1")"
image="$(q -c "SELECT image_url FROM receipts WHERE id = '$pending'")"

# case <name> <user id> <setup run as postgres or ''> <statement>
case_() {
  local name="$1" user="$2" setup="$3" stmt="$4" times=()
  for _ in 1 2 3 4 5; do
    t="$(q <<SQL | grep -E '^Execution Time' | tail -1 | sed 's/[^0-9.]//g'
BEGIN;
$setup
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', '$user', 'role', 'authenticated')::text, true);
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) $stmt;
ROLLBACK;
SQL
)"
    times+=("$t")
  done
  printf '%s\t%s\n' "$name" "$(printf '%s\n' "${times[@]}" | sort -n | sed -n 3p)"
}

printf 'case\tms\n'
case_ "receipt insert (student)" "$student" \
  "SET LOCAL session_replication_role = replica; UPDATE subscriptions SET status = 'pending_payment', paid_at = NULL WHERE id = '$sub'; DELETE FROM receipts WHERE subscription_id = '$sub'; SET LOCAL session_replication_role = origin;" \
  "INSERT INTO receipts (subscription_id, image_url) VALUES ('$sub', '$student/${sub}_1.jpg')"
case_ "receipt approve (admin)" "$admin" "" \
  "UPDATE receipts SET status = 'approved' WHERE id = '$pending'"
case_ "receipt image access check (admin, 1 image)" "$admin" "" \
  "SELECT id FROM storage.objects WHERE bucket_id = 'receipts' AND name = '$image'"
case_ "pending receipts list (admin)" "$admin" "" \
  "SELECT id, image_url, attempt_number, created_at, subscription_id, amount FROM receipts WHERE status = 'pending' ORDER BY created_at"
case_ "company_overview (admin)" "$admin" "" "SELECT public.company_overview('$company')"
case_ "platform_overview (super admin)" "$super" "" "SELECT public.platform_overview()"
case_ "admin_subscription_report (admin)" "$admin" "" "SELECT public.admin_subscription_report('{}'::jsonb)"
case_ "get_subscription_settings (admin)" "$admin" "" "SELECT public.get_subscription_settings('$company')"
case_ "get_company_notifications_page (admin)" "$admin" "" "SELECT public.get_company_notifications_page('$company')"
case_ "get_subscription_catalog (student)" "$student" "" "SELECT public.get_subscription_catalog()"
case_ "get_my_notifications_page (student)" "$student" "" "SELECT public.get_my_notifications_page()"
case_ "get_my_unread_count (student)" "$student" "" "SELECT public.get_my_unread_count()"
case_ "current subscription with trips (student)" "$student" "" \
  "SELECT s.*, (SELECT count(*) FROM line_trip_stops ts WHERE ts.trip_id IN (s.departure_trip_id, s.return_trip_id)) FROM subscriptions s WHERE s.student_id = '$student'"
case_ "line trip stops visible (student)" "$student" "" "SELECT count(*) FROM line_trip_stops"
case_ "payment methods (student)" "$student" "" "SELECT count(*) FROM company_payment_methods"
case_ "get_supervisor_dashboard (supervisor)" "$supervisor" "" "SELECT public.get_supervisor_dashboard()"
case_ "students page 1 (admin)" "$admin" "" \
  "SELECT st.id, st.full_name FROM students st JOIN company_students cs ON cs.student_id = st.id AND cs.company_id = '$company' ORDER BY st.created_at DESC LIMIT 25"
