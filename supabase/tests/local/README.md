# Local end-to-end tests

Two layers, both run against a throw-away local Postgres — never a real project.

## 1. SQL (roles, RLS, triggers, storage policies, backfills)

```bash
PGHOST=/path/to/socket PGPORT=5432 PGUSER=postgres supabase/tests/local/run_local.sh
```

Creates `basak_test`, loads `supabase_stub.sql` (roles, `auth.uid()`, `storage.*`),
applies every migration in order (with `seed_before_<migration>.sql` fixtures that
simulate existing production data) and runs `e2e_full_flow.sql`, which acts as the
super admin, company admins, supervisors, students, anon and the service role.
Then `e2e_ride_choices.sql` builds its own line in a rolled-back transaction and
checks that supervisors see riders by the trip each one chose for the day (per
trip, station and university, and who has not confirmed yet), and
`e2e_notifications.sql` checks who receives each notification (company, line,
trip), reading, the dashboard counts, access, and supervisor photos.
`e2e_redesign_foundations.sql` covers what the app redesign added
(migrations 20261104000002 to 20261108000001): the student's specialisation, a
line's bus capacity, the app version settings, the term recap and the boarded
rides count, each as the student, the supervisor, the company admin, the
platform admin and a signed-out client.
`e2e_company_branding.sql` covers the company's logo and emblem (migration
20261109000001): who may add, list, overwrite and delete files of the artwork
bucket, `set_company_branding`, the logo of an issued receipt outliving its
replacement, and that every answer naming a company carries both paths.

## 2. HTTP (GoTrue + PostgREST + Edge Functions, through supabase-js)

1. Database: `CREATE DATABASE basak_http`, roles `supabase_auth_admin` (login) and
   `authenticator` (login, noinherit), `CREATE SCHEMA auth AUTHORIZATION supabase_auth_admin`.
2. GoTrue (github.com/supabase/auth release binary): `auth migrate`, then `auth serve`
   on :9999 with `GOTRUE_JWT_SECRET`, `GOTRUE_MAILER_AUTOCONFIRM=true`.
3. Load `supabase_stub.sql` and all migrations into `basak_http`;
   `GRANT anon, authenticated, service_role TO authenticator`.
4. PostgREST on :3000 (`db-anon-role = "anon"`, same JWT secret).
5. `node keys.mjs > keys.env` (anon + service-role JWTs for that secret).
6. Each Edge Function under Deno:
   `PORT=82xx FN_ENTRY=file://.../functions/<name>/index.ts SUPABASE_URL=http://127.0.0.1:8100 SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... deno run -A fnwrap.ts`
   (an import map can point `https://esm.sh/@supabase/supabase-js@2` at `npm:@supabase/supabase-js@2`).
7. `FN_PORTS='{"admin-create-supervisor":8201,...}' node gateway.mjs` (:8100 = the project URL).
8. `SUPABASE_URL=http://127.0.0.1:8100 ANON_KEY=... SERVICE_KEY=... node http_e2e.mjs`
   (uses `admin_web/node_modules/@supabase/supabase-js`; run `npm ci` in `admin_web` first).

## 3. Wallet cards (local Supabase stack + test doubles)

`wallet/http_e2e.mjs` runs the whole wallet feature against a local `supabase start`
stack (real Auth, PostgREST, Storage, `pg_net` and the Edge runtime). `wallet/fakes.mjs`
stands in for Apple's push service (HTTP/2 with a client certificate) and Google's
Wallet API, so nothing leaves the machine.

1. Copy `supabase/` to a scratch folder, add `seed_before_20261006000001_…sql` as a
   migration named `20261006000000_local_shim.sql`, and run `supabase start` there.
2. Make a throw-away CA, a server certificate for `host.docker.internal`, a "pass"
   certificate whose subject contains the pass type id, and an RSA key for Google.
3. `node wallet/fakes.mjs <cert dir>` (ports 8443 and 8444).
4. `supabase functions serve --env-file <env>` with `APPLE_*` pointing at the test
   certificates, `APPLE_APNS_HOST=host.docker.internal:8443`, `APPLE_APNS_CA_PEM`,
   `GOOGLE_WALLET_API_BASE=http://host.docker.internal:8444/walletobjects/v1`,
   `GOOGLE_OAUTH_TOKEN_URL=http://host.docker.internal:8444/token` and
   `WALLET_PUBLIC_URL=<the stack's API url>`.
5. `SUPABASE_URL=… ANON_KEY=… SERVICE_KEY=… DB_URL=… CA_PEM=… PHOTO=<any jpeg> node wallet/http_e2e.mjs`

## 4. Company workspaces (tenant isolation)

Everything under `tenancy/` runs against a local `supabase start` stack. Keep the
stack's folder somewhere Docker can read (under your home folder): the Edge
runtime mounts `supabase/functions` from it.

- `tenancy/isolation.sql`: builds two complete companies in one rolled-back
  transaction and checks, as each kind of user, that nothing crosses between them:
  every table that carries `company_id` (read, update, delete), membership,
  password resets, supervisors, per-company terms and report resets, the overview
  functions and a suspended company.
  `psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/local/tenancy/isolation.sql`
- `tenancy/subscription_options.sql`: what can be bought and at what price: every
  combination of the company's sale switches, the line's switches and prices, the
  advance switch and the calendar; that the catalog, the older picker and the
  insert check agree; "both" (first + second only) and the older "annual"/"yearly"
  spelling; trip times per station and university; and the receipt that cannot be edited, deleted or altered by
  later renames.
  `psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/local/tenancy/subscription_options.sql`
- `tenancy/http_e2e.mjs`: the same model through the real API: creating a company
  (and its rollback), the admin Edge Functions, a receipt arriving live for one
  company and not the other, removing a member, suspending a company, and the
  queries the mobile app makes.
  `SUPABASE_URL=… ANON_KEY=… SERVICE_KEY=… node supabase/tests/local/tenancy/http_e2e.mjs`
- `tenancy/rehearse.sh`: before a live rollout. Loads a data-only dump of the live
  `public` schema into the local stack, applies the pending migrations and fails
  if any count, subscription date or label, revenue figure or wallet card changed
  (`snapshot.sql`), then checks the new invariants (`verify.sql`). Take the dump
  without `wallet_runtime`, `wallet_passes` and `wallet_apple_*`, and keep it out
  of the repository: it holds personal data.

