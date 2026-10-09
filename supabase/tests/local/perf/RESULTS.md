# Measurements at 100,000 students

Local stack on this Mac (Docker: 4 CPUs and 6 GB shared by Postgres, the API, Storage
and Realtime), loaded with `dataset.sql`: 10 companies of very different sizes (the
largest 32,853 students), 670 lines, 352,797 subscriptions over three academic years,
346,844 receipts (3,959 waiting), 77,484 ride votes, 420,306 scans, 27,040
notifications with 4,097,800 recipients. Never run against the live project.

Requests go through the real API (`bench.mjs`): row security, grants and JSON size are
all included. p50 / p95 of 15 runs each, one at a time. No network delay: on a real
connection every request costs more, so request counts and payload sizes matter most.

## Each request alone: before → after (`20261103000001_data_access.sql`)

| Request | Before p50 | Before p95 | After p50 | After p95 | Payload |
|---|---:|---:|---:|---:|---:|
| Dashboard: students page | failed (8 s timeout) | — | 66 ms | 84 ms | 49 KB |
| Dashboard: students page 400 | failed (8 s timeout) | — | 81 ms | 89 ms | 45 KB |
| Dashboard: search students by name (with total) | 311 ms | 362 ms | 399 ms | 471 ms | 43 KB |
| Dashboard: search students by phone | 102 ms | 129 ms | 165 ms | 201 ms | 2 KB |
| Dashboard: receipts waiting (5 requests → 1) | 32 ms | 43 ms | 18 ms | 20 ms | 45 KB |
| Supervisor: rider counts (per line → all lines in one call) | 59 ms | 86 ms | 144 ms | 185 ms | 56 KB |
| student: role (my_role) | 8.9 ms | 13 ms | 2.5 ms | 4.6 ms | 9 B |
| student: current subscription | 8.8 ms | 13 ms | 3.5 ms | 4.2 ms | 969 B |
| student: subscription history | — | — | 2.2 ms | 2.8 ms | 679 B |
| student: receipts of one subscription | — | — | 2.0 ms | 4.5 ms | 151 B |
| student: catalog | 642 ms | 771 ms | 79 ms | 98 ms | 570 KB |
| student: profile | 3.0 ms | 4.7 ms | 1.7 ms | 3.1 ms | 269 B |
| student: card (QR) data | 2.2 ms | 9.5 ms | 1.5 ms | 2.6 ms | 243 B |
| student: today's vote | 2.3 ms | 3.6 ms | 1.6 ms | 2.6 ms | 216 B |
| student: vote settings | 2.9 ms | 12 ms | 1.9 ms | 3.5 ms | 467 B |
| student: inbox page | 55 ms | 64 ms | 2.6 ms | 3.8 ms | 12 KB |
| student: unread count | 2.3 ms | 3.5 ms | 1.9 ms | 2.5 ms | 2 B |
| supervisor: dashboard | 294 ms | 369 ms | 164 ms | 258 ms | 214 KB |
| supervisor: trip manifest | 69 ms | 98 ms | 34 ms | 41 ms | 11 KB |
| supervisor: monthly summary | 62 ms | 69 ms | 56 ms | 65 ms | 3 KB |
| admin: company overview | 3417 ms | 7733 ms | 220 ms | 343 ms | 1877 B |
| admin: financial report | 1244 ms | 2460 ms | 871 ms | 1098 ms | 1166 KB |
| admin: financial report, first 100 rows | — | — | 736 ms | 791 ms | 58 KB |
| admin: financial report, search | 1643 ms | 2096 ms | 1251 ms | 1458 ms | 1166 KB |
| admin: financial report, current phase | 506 ms | 597 ms | 377 ms | 461 ms | 1165 KB |
| admin: notifications history | 7.0 ms | 11 ms | 6.8 ms | 11 ms | 20 KB |
| admin: subscription settings | 174 ms | 250 ms | 196 ms | 227 ms | 297 KB |
| platform: overview | 3094 ms | 5695 ms | 953 ms | 1052 ms | 8 KB |
| platform: all students page | 77 ms | 95 ms | 79 ms | 89 ms | 10 KB |
| platform: all students search | 227 ms | 245 ms | 198 ms | 221 ms | 10 KB |
| platform: notifications history | 25 ms | 34 ms | 21 ms | 24 ms | 23 KB |
| platform: university counts | 4825 ms | 7977 ms | 24 ms | 27 ms | 383 B |

Notes
- The two search rows were measured again after the university trigram index was added
  (the main "after" run predates it): students by name with total 22 ms (p95 24), by phone
  4.1 ms, platform students search 4.8 ms.
- Before-numbers for the student rows were taken while other work was running on the
  machine; they were already in the 2–10 ms range and nothing in them was changed, except
  the inbox (55 → 2.6 ms) and the catalog (642 → 79 ms).
- `single-100k-before.md` and `single-100k-after.md` are the raw runs.

## Storage (`sign.mjs`)

| Call | Before | After |
|---|---:|---:|
| Admin signs 50 receipt images in one batch | 1981 ms | 101 ms |
| A student lists their own receipt folder | timed out (30 s) | 341 ms |

## Mixed traffic (`bench.mjs load`): 80% students, 15% supervisors, 5% admins

Each simulated user acts every 0.2–0.8 s (far busier than a person), for 30 s. A student
"open app" is five requests at once.

| Users | | Actions/s | p50 | p95 | p99 | Errors |
|---|---|---:|---:|---:|---:|---:|
| 10 | before | 9.7 | 42 ms | 2795 ms | 3891 ms | 0 |
| 10 | after | 18.8 | 7.3 ms | 167 ms | 322 ms | 0 |
| 50 | before | 7.9 | 6130 ms | 10098 ms | 12702 ms | 60 + 1 timeout |
| 50 | after | 40.3 | 564 ms | 2253 ms | 3512 ms | 0 |
| 100 | before | the run did not complete (requests failed faster than they were answered) | | | | |
| 100 | after | 38.5 | 1879 ms | 5331 ms | 7957 ms | 76 |

"Before" is the database as it was after `20261102000001`, with the old dashboard
queries and the catalog asked for by a third of student actions (the app then read it at
every start). "After" has the new functions and the catalog asked for by about a tenth
(the app now reads it only when the purchase screen is opened). Both changes are in the
after-row; they were not measured apart.

What this says and does not say
- The data size is handled: with 100,000 students no screen reads all of them, and every
  list is paged on the server.
- This machine tops out at about 40 actions a second (roughly 150 requests a second). Past
  that, everything queues, including 2 ms requests: the limit is the 4 shared CPUs and the
  API's connection pool, not one slow query. The heaviest requests left are the supervisor
  dashboard (164 ms, 214 KB), the catalog (79 ms, 570 KB at this scale) and the financial
  report (0.7–1.2 s).
- It does not say how many people the production project can serve at once: that depends on
  its plan and hardware and was not tested (no load was sent to production).

## Earlier pass (15,000 students)

Dashboard, one receipt approved: 311 requests → 3 → now 1. One realtime receipt event on
the receipts page: 156 requests → 6. First-page JavaScript 210 → 152 KB gzip. Financial
report 1063 → 106 ms at that size. App: receipt upload 15 requests → 2; details in
`mobile_app/test/perf/RESULTS.md`.

## Scripts

- `dataset.sql` / `dataset_drop.sql`: the data (marked, removable).
- `bench.mjs single|load`, `sign.mjs`: the measurements above.
- `measure.sh`, `outputs.sh`: statement timings as each kind of user, and fingerprints of
  what the rewritten functions return (to check "same answers").
