# Admin dashboard — performance notes

Scope: `admin_web/` only. Sizes come from `npm run build`; request counts come from reading the
code (a static inventory). Nothing here was measured in a browser: timings, real request counts
and bytes on the wire are measured separately and recorded in the consolidated results file,
which supersedes this one where they differ.

## 1. Bundle (vite 5.4, 41 JS chunks)

| What one visit downloads (entry + static imports + the screen's lazy chunks) | Files | Raw | gzip |
|---|---:|---:|---:|
| Sign-in page | 8 | 491,146 B | 141,596 B |
| Company admin, first page (overview) | 17 | 536,395 B | 158,899 B |

Before lazy routes every admin downloaded one 770,699 B file (207,148 B gzip).

- 438 kB of each visit is three vendor files (`supabase`, `react`, `query`): unchanged by a
  dashboard release, `modulepreload`ed, downloaded in parallel with the entry.
- Every page is its own chunk, fetched when opened or when its navigation entry is pointed at.
  A company admin never downloads the platform's pages.
- `kit` (3 kB) groups six tiny helpers that many pages share, instead of six requests.
- `legacy` (4.6 kB) is downloaded only if a server function is missing (section 3).
- `npm run check:bundle` builds and fails when either row above grows about 10% past these
  numbers (`scripts/check-bundle.mjs` holds the budgets).

Fonts: Cairo and Inter as one variable-font request per family, loaded without blocking the
first paint.

## 2. Requests (static inventory)

N = pending receipts on screen.

| Where | Requests |
|---|---|
| Boot on reload | 1: `admins` with its company embedded |
| Shell, every workspace page | `company_overview` + a HEAD count of open password-reset requests |
| Receipts queue (overview and receipts pages) | 1 `get_pending_receipts_page` + 1 `createSignedUrls`; images lazy |
| Queue re-read (focus, someone else's receipt) | 1; 0 signing and 0 image downloads (links reused for 50 min) |
| Approve / reject | 1 `review_receipt`. Its answer carries the company's numbers; the change's own announcement reads nothing. Decisions taken close together are applied in the order they were saved (`reviewed_at`), with no extra read |
| Financial report | 100 rows per request (`limit` / `offset` in `p_filters`), «عرض المزيد» for the next 100; totals always cover every matching row. Was up to 2000 rows (1.1 MB at 100,000 students) on every refresh |
| Students page | 1 `get_company_students_page` (rows and total) + avatar signing + reset requests, invitations, corrections |
| Students: search / page change | 1 per settled search, the total once 700 ms after typing stops; a page change never recounts |
| Students: subscription status | 1 update; its answer goes into the row; the announcement refreshes the overview only |
| Lines / supervisors / payment methods | each lookup under one shared key; a write answers with the saved row, which is shown without a re-read |
| Settings | each save answers with what was saved; the company row's announcement re-reads only what is derived from it |
| Platform area | an announced change refreshes only the lists it concerns, not every platform query on screen |

A page opened again within 30 s asks for nothing (lookups: 5 min). A burst of live events is
handled once, 400 ms after the last one and at most 2 s after the first.

## 3. Deploy order

`get_pending_receipts_page`, `review_receipt` and `get_company_students_page` may be missing
from the database the dashboard talks to. On PostgREST's `PGRST202` the dashboard does the same
job the older way (`src/lib/legacy.ts`: five requests for the queue, a plain update for a
decision, a nested select plus a count for students) and asks for the function again five
minutes later. `university_student_counts()` missing shows «—» in place of the numbers.
An `admin_subscription_report` that does not page yet ignores `limit` / `offset` and answers
without `rows_total`: its rows (up to 2000) are taken as the whole report. A `review_receipt`
answer without `reviewed_at` falls back to one `company_overview` read after overlapping decisions.

## 4. Regression guards

`npm test` (vitest, pure logic only, no timers): cache keys and their scoping, what is persisted,
signed-link reuse, which lists a live event refreshes and which an own change skips, receipt and
student cache edits, the order overlapping decisions are applied in, report paging, the notification idempotency key, Cairo time, the double-submit guard and
the missing-function fallback.

## 5. Not verified here

- Anything in a browser: time to content, real request counts, image bytes, lazy loading, hover
  prefetch, own-echo suppression against a running database, and that the app renders
  (`tsc`, `vite build`, `vitest` and the bundle check were run; no dev server, no browser).
- The three server functions of section 3 were coded against their documented shapes and never
  called.
- Browser-cache reuse of receipt images relies on the storage endpoint sending cacheable headers
  for an unchanged signed URL.
- The HEAD count on `admin_list_password_reset_requests` with a `status` filter was not exercised.
