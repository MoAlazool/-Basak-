# BASAK (باصك) — Live Security Assessment Report
**Date:** 2026-10-12  
**Target:** BASAK student bus‑subscription platform — mobile app, admin web dashboard, and Supabase backend  
**Assessment type:** Grey‑box, **live testing against a running isolated environment** (not code‑review only)  
**Methodology references:** OWASP WSTG, OWASP ASVS, OWASP MASVS, OWASP Top 10, Supabase database linter (advisors)

> Companion file: `2026-10-12-SECURITY-ASSESSMENT-AR.md` (Arabic).

---

## 1. Executive summary

A full live security assessment was performed against an **isolated local replica** of the BASAK backend (a complete local Supabase stack: PostgreSQL 17, GoTrue Auth, PostgREST, Storage, Realtime, Kong gateway and the Edge Function runtime), plus static and configuration review of the web dashboard and the production project in **read‑only** mode.

**Overall result: the platform's security posture is strong.** The core authorization model — Postgres Row Level Security (RLS), server‑side triggers, and self‑verifying Edge Functions — held against every active attack attempted: cross‑tenant access, horizontal/vertical privilege escalation, IDOR, SQL injection, subscription/payment‑logic abuse, QR misuse, and unauthenticated access. No high or critical vulnerability was confirmed.

The findings are dominated by **one confirmed availability/integrity defect** (a duplicate migration version that breaks clean re‑provisioning), which has been **fixed and retested**, plus a set of **low‑severity hardening items** surfaced by the Supabase security advisors on the production project (most notably: leaked‑password protection is disabled in Auth).

| Severity | Count | Items |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 5 | F‑01 (fixed), F‑02, F‑03, F‑04, F‑05 |
| Informational | 3 | F‑06, F‑07, F‑08 |

---

## 2. Scope & testing environment

**In scope**
- Supabase backend: 89 migrations, RLS policies, triggers, SECURITY DEFINER functions, Storage policies, 19 Edge Functions.
- Admin web dashboard (`admin_web`, React 18 + Vite 5 + supabase‑js).
- Mobile app configuration (`mobile_app`) — static/config review.
- Business logic: subscriptions, receipts/payments, attendance/ride votes, QR boarding, multi‑company (tenant) separation, roles (Super Admin / Company Admin / Supervisor / Student).

**Isolated environment (where all active attacks ran)**
- A throwaway local Supabase stack started from a working copy of `supabase/` in a scratch directory.
- API: `http://127.0.0.1:54321` · DB: `127.0.0.1:54322` · Studio: `54323`.
- `linked_project: null` — **confirmed not connected to production**. All 89 migrations applied cleanly; services healthy.
- All attack data were synthetic test rows inside rolled‑back transactions; the local demo JWT keys were used (not production secrets).

**Production (read‑only only, as authorised)**
- Project `hnwpkkryxovhmsrokdsd` ("basy's Project", eu‑west‑1, Postgres 17.6, ACTIVE_HEALTHY).
- Only read‑only advisor/lint inspection was performed. **No writes, no active attacks, no data access against production.**

---

## 3. GitHub‑vs‑local synchronisation verification *(performed first, before any testing)*

| Item | Status | Detail |
|---|---|---|
| Active branch `claude/dreamy-faraday-av043h` | ✅ In sync | At `ccd9cb1`; tree **byte‑identical** to `origin/claude/dreamy-faraday-av043h` (0 ahead / 0 behind, empty diff). |
| Working tree | ✅ Clean | No uncommitted changes, no stashes at start. |
| Local‑only branch `sync/local-changes-2026-10-06` | ✅ No risk | Present locally only; fully contained in the active branch (ancestor of HEAD) → no unique work. |
| Local `main` (`40626b0`) | ⚠️ Note | 18 commits ahead of `origin/main` (`403c5cd`), 0 behind; these are local merge commits not yet pushed. **Zero commits unique to local** (all present on remote branches) → no data‑loss risk. |

**Conclusion:** the working branch is fully synchronised with GitHub and the tree is clean. The only discrepancy is unpushed merge commits on local `main` (a consequence of the "merge to main after push" workflow); no local work is at risk. No synchronisation action was required before testing.

---

## 4. Methodology & tools

- **Environment:** Docker Desktop + Supabase CLI (`supabase start`) for a full isolated stack.
- **RLS / trigger / policy testing:** direct SQL as each principal, impersonating users via `request.jwt.claims` + `SET ROLE authenticated|anon` exactly as PostgREST does, inside rolled‑back transactions (`psql` via `docker exec`).
- **Project test suites (run live):** `tenancy/isolation.sql` (two full companies, every role), `tenancy/subscription_options.sql` (purchase/price logic).
- **HTTP / API testing:** `curl` against REST, RPC, Auth, and Edge Function endpoints (unauthenticated, forged‑token, wrong‑role).
- **Resource/DoS resilience:** small controlled concurrency bursts (25 requests) — local only.
- **Production config:** Supabase advisors (`get_advisors` security + performance) — read‑only.
- **Static review:** backend shared auth helpers, Edge Functions, dashboard source (secret exposure, XSS sinks).

---

## 5. Tests performed and results

| # | Test | Technique | Status |
|---|---|---|---|
| T1 | Cross‑tenant read of `students` by an active supervisor | SQL as supervisor | ✅ Passed (0 rows leaked) |
| T2 | Student reads another student's profile/PII | SQL as student | ✅ Passed (own row only) |
| T3 | Anonymous read of `students` | SQL as anon | ✅ Passed (0 rows) |
| T4 | Tenant isolation across all `company_id` tables | `isolation.sql` | ✅ 282/285 real checks passed; 3 are test‑heuristic false positives (F‑07) |
| T5 | Subscription/purchase & price logic | `subscription_options.sql` | ✅ 95/95 passed |
| T6 | Student self‑activates a subscription (`status=active`, price 0) | SQL INSERT as student | ✅ Passed (rejected by trigger) |
| T7 | Student edits own subscription price / end_date | SQL UPDATE as student | ✅ Passed (UPDATE 0 — no policy) |
| T8 | Student reads another company's subscriptions | SQL as student | ✅ Passed (own only) |
| T9 | Company admin reads/updates another company's subscriptions | SQL as company admin | ✅ Passed (own company only; cross‑company UPDATE 0) |
| T10 | Privilege escalation — company admin promotes self to super_admin | SQL UPDATE as company admin | ✅ Passed (UPDATE 0) |
| T11 | Privilege escalation — company admin inserts a new super_admin | SQL INSERT as company admin | ✅ Passed (RLS policy violation) |
| T12 | Company admin reads/hijacks another company's admin row | SQL as company admin | ✅ Passed (self only; hijack UPDATE 0) |
| T13 | Edge Function auth: no token / forged / anon / service‑role token | `curl` POST admin‑create‑company | ✅ Passed (all 401, no company created) |
| T14 | SQL injection via PostgREST filter | `curl` crafted filter | ✅ Passed (treated as literal, `[]`) |
| T15 | SQL injection via RPC argument | `curl` RPC password‑reset | ✅ Passed (input validated, 400) |
| T16 | SQL injection via `order`/`;drop` param | `curl` | ✅ Passed (parameterised, ignored) |
| T17 | Storage IDOR — student reads another student's receipt image | SQL on `storage.objects` | ✅ Passed (own folder only) |
| T18 | Storage — anonymous read of receipts bucket | SQL as anon | ✅ Passed (0 objects) |
| T19 | QR misuse — anon / plain student calls `lookup_student_by_qr` | SQL + internal guard | ✅ Passed (Access denied) |
| T20 | Password‑reset abuse / account enumeration | `curl` + function review | ✅ Passed (idempotent, same answer regardless of existence) |
| T21 | DoS — 25 rapid password‑reset requests | concurrency burst | ⚠️ Inconclusive/Info (no app‑level limit, but idempotent & no amplification — F‑08) |
| T22 | Brute force — 25 rapid failed logins | concurrency burst | ⚠️ Inconclusive/Info (all 400; GoTrue rate‑limit is config‑dependent — F‑08) |
| T23 | Dashboard — service_role key exposure | source grep | ✅ Passed (only anon key client‑side) |
| T24 | Dashboard — XSS sinks (`dangerouslySetInnerHTML`, `innerHTML`, `eval`) | source grep | ✅ Passed (none found; React escaping) |
| T25 | Fresh provisioning / migration integrity | `supabase start` | ❌ Failed → **F‑01** (now fixed & retested ✅) |
| T26 | Production security advisors | `get_advisors` (read‑only) | ℹ️ 6 advisories → F‑02…F‑06 |

---

## 6. Confirmed vulnerabilities

### F‑01 — Duplicate migration version blocks clean provisioning *(Low–Medium, availability/integrity)* — **FIXED**
- **Component:** `supabase/migrations/`
- **Evidence:** Two migrations shared version `20261121000001`: `…_governorates.sql` and `…_recap_release_live.sql`. A fresh `supabase start` (and any `supabase db reset` / CLI branch deploy) fails:
  `MigrationApplyError: duplicate key value violates unique constraint "schema_migrations_pkey" … Key (version)=(20261121000001) already exists.`
- **Impact:** New environments (CI, preview branches, a rebuilt production, disaster recovery) cannot be provisioned from the migration history. Running production is unaffected (both statements already ran), so this is integrity/availability of the *deployment pipeline*, not a data‑exposure issue.
- **Reproduction:** run `supabase start` on a clean machine against the unfixed tree → apply stops at `20261121000001`.
- **Fix applied:** renamed the later file to `20261121000002_recap_release_live.sql` (both are additive and order‑independent; dependency "AFTER 20261119000004" still satisfied).
- **Retest:** the isolated stack with the rename applied **all 89 migrations cleanly** and all services came up healthy; `isolation.sql` (282/285) and `subscription_options.sql` (95/95) then passed on the fixed schema — no regression.
- **Production deployment note (manual):** on the next `supabase db push`, version `20261121000002` will be seen as new and `recap_release_live.sql` will re‑run. The file is explicitly "Safe to re‑run" (a single `CREATE OR REPLACE` trigger), so this is safe; confirm `schema_migrations` on production afterwards.

---

## 7. Potential risks that could not be confirmed as exploitable

### F‑05 — SECURITY DEFINER trigger/internal functions are EXECUTE‑able by `anon`/`authenticated` *(Low, defense‑in‑depth)*
- **Evidence:** advisors flag 43 functions anon‑executable and 204 authenticated‑executable. The list includes internal **trigger** functions (`enforce_subscription_insert`, `guard_subscription_update`, `handle_receipt_review`, `validate_*`, `set_subscription_company`, `sync_*`) and helpers (`is_admin`, `is_supervisor`, …).
- **Why not confirmed exploitable:** trigger‑returning functions are not callable as PostgREST RPCs and fail outside a trigger context; public‑facing RPCs enforce their own authorization. This was **proven** for `lookup_student_by_qr` — despite being anon‑executable, its first statement rejects non‑staff ("Access denied"), and it is further scoped to the caller's lines/company.
- **Recommendation:** as hardening, `REVOKE EXECUTE … FROM anon, authenticated` on trigger functions and internal helpers not intended as RPCs, keeping grants only on the deliberate RPCs.

### F‑08 — No application‑level rate limiting on the password‑reset RPC; no login lockout observed locally *(Info/Low)*
- **Evidence:** 25 rapid `request_student_password_reset` calls all returned 200; 25 rapid failed logins all returned 400 (no 429/lockout) in the local stack.
- **Why not confirmed exploitable:** the reset RPC is **idempotent** (`ON CONFLICT (student_id) WHERE status IN ('pending','code_issued') DO NOTHING`) and gives the **same answer whether or not the phone is registered** (no enumeration, no SMS amplification per call). GoTrue/Kong rate limits are platform‑configured and differ between local and production.
- **Recommendation:** confirm GoTrue auth rate‑limits and Kong/edge rate limits are enabled on production; consider a per‑phone/IP throttle on reset requests.

---

## 8. Fixes implemented and retesting results

| ID | Fix | Where | Retest |
|---|---|---|---|
| F‑01 | Renamed `20261121000001_recap_release_live.sql` → `20261121000002_recap_release_live.sql` | repo (`supabase/migrations/`) | ✅ Full stack applied 89/89 migrations cleanly; isolation 282/285 & purchase 95/95 still pass; no duplicate versions remain. |

No other code changes were applied. All remaining items (Section 9) are either manual/dashboard actions or low‑severity hardening left for the owner's decision, to avoid unintended side effects on the live deployment.

---

## 9. Remaining items & recommended remediation

| ID | Severity | Finding | Remediation | Action type |
|---|---|---|---|---|
| F‑02 | Low | **Leaked‑password protection disabled** in Auth (no HaveIBeenPwned check). | Enable in Supabase → Authentication → Password settings. [docs](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) | Manual (dashboard) |
| F‑03 | Low | `function_search_path_mutable` on `offer_picture_path`. | `ALTER FUNCTION public.offer_picture_path(...) SET search_path = public;` [docs](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable) | Migration |
| F‑04 | Low/Info | Extension `pg_net` installed in `public` schema. | Relocate to a dedicated schema (e.g. `extensions`). [docs](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public) | Migration (plan carefully) |
| F‑05 | Low | SECURITY DEFINER trigger/internal functions EXECUTE‑able by anon/authenticated. | `REVOKE EXECUTE` on trigger functions & internal helpers; keep only intended RPCs. | Migration |
| F‑06 | Info | `rls_enabled_no_policy` on 20 server‑only tables (`notifications`, `push_*`, `wallet_*`, `offers`, `password_reset_requests`, …). | Fail‑closed and intended (accessed via SECURITY DEFINER RPCs/service role). Confirm each is meant to be client‑inaccessible; add an explicit deny/comment for clarity. | Review |
| F‑07 | Info | `tenancy/isolation.sql` reports 3 false positives (`company_plans`, `platform_charges`, `company_governorates`). | Update the test heuristic to recognise `is_super_admin()`‑only and public catalog tables so the suite is green. | Test maintenance |
| F‑08 | Info/Low | Rate limiting (see Section 7). | Verify production GoTrue/Kong rate limits; consider reset throttle. | Config |

---

## 10. Final assessment & limitations

**Final assessment:** BASAK demonstrates a **mature, defense‑in‑depth security design**. RLS is enabled on all client tables with correctly scoped, tenant‑aware policies; server‑side triggers own sensitive fields (subscription status, price, dates) so clients cannot forge them; Edge Functions self‑verify the caller from the validated JWT (never from the request body) and pin company admins to their own company; Storage is folder‑scoped per user; and public RPCs validate input and enforce their own authorization. Every active attack in Section 5 was repelled. The only confirmed defect (F‑01) was an operational migration‑numbering issue, now fixed and retested. Remaining items are low‑severity hardening.

**Limitations:**
- Active testing ran against an **isolated local replica**, not production; production behaviour can differ in platform‑level controls (rate limits, network, WAF/Kong config).
- Production was inspected **read‑only** (advisors only), per the agreed rules — no production data access or active attacks.
- Mobile app review was **static/configuration** only (no instrumented device/APK runtime, no TLS‑interception of a live device session).
- Wallet (Apple/Google) and push‑notification flows were not exercised end‑to‑end (they require external test doubles/certificates).
- Findings reflect the state of branch `claude/dreamy-faraday-av043h` at `ccd9cb1` on 2026‑10‑12.
- No destructive testing was performed; all database attacks ran inside rolled‑back transactions.
