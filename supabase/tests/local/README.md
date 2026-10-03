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
