# Basak capacity benchmark: storage and concurrency (October 2026)

All measurements were taken on the **real hosted Supabase project** (`hnwpkkryxovhmsrokdsd`, eu-west-1, **Free plan, Nano compute**, Postgres 17) on 11–12 October 2026, before launch. Every number is labelled:
- **MEASURED LIVE**: observed on the live project.
- **PROJECTED**: derived from measured numbers. The method is stated with each projected number.

Raw data is in `perf/live/results/2026-10-12-live-benchmark.json`: every checkpoint, every load stage with per-endpoint histograms, and the server snapshots. It contains no tokens and no personal data. The scripts are in `perf/live/`.

---

## 1. Clean pre-launch baseline (MEASURED LIVE)

| | |
|---|---|
| Database size | **22.8 MB** (22,817,939 bytes) |
| Postgres catalog (system) | 14.0 MB |
| Basak tables (`public`): heap / index / toast | 0.16 / 3.18 / 0.40 MB, 4.34 MB in total |
| Reference data kept | 0.39 MB: 7 universities, 27 governorates, 3 terms, 11 notification templates, app settings and versions, push/wallet runtime |
| Auth | 1 user (the platform admin), 1.6 MB of Auth schema |
| Object storage | 0 objects, 5 buckets kept |

**Before the cleanup** the database was 27.9 MB: 9 Auth users, 2 test companies and 43 test files. The cleanup checks were:
- The platform admin's `auth.users`, `auth.identities` and `public.admins` rows are hash-identical before and after.
- The schema fingerprint is identical in all 14 categories (`perf/live/fingerprint.sql`).
- The receipt-snapshot guard is enabled again (`O`).

---

## 2. Storage growth (MEASURED LIVE)

### Model
- **Companies:** real BENCH companies, each with:
  - admins, supervisors, lines, stations and trips
  - prices per term
  - payment methods and receipt counters
- **Students:** one real Auth account per student, created through the **Auth Admin API**. 4,792 accounts in all.
- **History:** one full academic year in three terms (First, Second, Summer) plus the current term up to today.
- **Turnover between terms:** 60% returning, 40% new.
  - So about 1.94 accounts per student active in a term.
  - Summer is about 35% of a regular term.
- **Usage mix:** 25% light, 55% normal and 20% heavy users.
- **Votes and scans:**
  - Daily votes follow the real Sun–Thu term calendar.
  - Departure and return scans follow the usage mix.
- **Payments:** receipts include rejected first attempts, and each has its immutable snapshot.
- **Notifications:** stored as the app keeps them. `notifications_purge` keeps 30 days of subscription notices and 7 days of everything else, so they do not pile up.

### Checkpoints

| Active students / term | Companies | Accounts | Database | Of 500 MB |
|---:|---:|---:|---:|---:|
| 0 (clean) | 0 | 1 | 22.8 MB | 4.6% |
| 100 | 1 | 1,029 * | 43.4 MB | 8.7% |
| 250 | 2 | 1,482 * | 67.3 MB | 13.5% |
| 500 | 3 | 2,029 * | 108.5 MB | 21.7% |
| 1,000 | 4 | 3,057 | 189.7 MB | 37.9% |
| 1,500 | 5 | 4,557 | 269.0 MB | 53.8% |
| 2,000 | 6 | 4,557 | 347.1 MB | 69.4% |
| 2,300 | 7 | 4,558 | 395.0 MB | 79.0% |
| **2,470** | **8** | **4,858** | **422.9 MB** | **84.6%** (stop target) |

\* Accounts are created ahead of use, so this count includes unused benchmark accounts.

**At the highest point:**

| | |
|---|---|
| Rows | 618,747 scans, 429,236 votes, 7,784 subscriptions, 8,612 receipts, 7,344 receipt snapshots, 34,510 notification recipients |
| Growth per student active in a term | **≈ 162 KB per academic year**: (422.9 − 22.8) MB / 2,470. Linear between checkpoints (157–165 KB); no step was seen. |

**Where the space goes, at 2,300 actives:**

| Table | Size | Share | Per active student per year |
|---|---:|---:|---:|
| `supervisor_scan_events` | 231.6 MB | 63% | ≈ 100 KB |
| `daily_ride_status` | 104.1 MB | 28% | ≈ 45 KB |
| Auth (users + identities) | 9.1 MB | | ≈ 2 KB per account |
| Everything else together | | under 10% | |

"Everything else" covers receipts, receipt snapshots, subscriptions, students, push devices and notification recipients.

**Operational history (scans and votes) is about 90% of the growth.**

### Object storage
Projected from the real files the app had uploaded before the cleanup: receipts averaged about 130 KB and avatars about 159 KB. Per student per year that is about 0.45 MB (an avatar plus about 2 receipts).
- Free plan, 1 GB of storage: about 2,000 students. **PROJECTED.**
- Pro, 100 GB: about 200,000 students. **PROJECTED.**

### Storage capacity

**Free plan, 500 MB database, read-only above the limit.** Rows marked MEASURED match a checkpoint in the table above; the rest are linear from 162 KB per active student per year.

| Threshold | Active students / term, first year | |
|---|---:|---|
| 70% (350 MB) | ≈ 2,000 | MEASURED at 2,000 = 347 MB |
| 80% (400 MB) | ≈ 2,330 | |
| 90% (450 MB) | ≈ 2,640 | PROJECTED |

**Later years with no retention:** each year adds about 145 KB of scans and votes per active student. **PROJECTED:**
- After 2 years, the same space holds about half as many students: ≈ 1,100 at 80%.
- After 3 years: ≈ 750.

**Pro plan: 8 GB disk included, autoscaling (the spend cap must be off to grow).** All PROJECTED, linear from the measured 162 KB:

| | Active students / term |
|---|---|
| 1 year at 70% | ≈ 35,000 |
| 3 years | ≈ 12,000 |
| 3 years with 1-year retention | ≈ 30,000 |

### Retention (recommendation only; nothing was deleted)
Keep detailed scans and votes for the current and previous academic year. Before deleting anything older, keep per-day, per-line and per-student counts (a summary table of a few bytes per student per day).

| Option | Database per active student | Free 500 MB at 80% | Pro 8 GB at 70% |
|---|---|---|---|
| Keep everything | grows +145 KB / year | ≈ 750 after 3 years | ≈ 12,000 after 3 years |
| 2 years detailed + summaries | ≈ 310 KB steady state | ≈ 1,250 | ≈ 18,000 |
| 1 year detailed + summaries | ≈ 165 KB steady state | ≈ 2,300 | ≈ 34,000 |

The 1- and 2-year rows are PROJECTED. The first row's "after 3 years" figures are as in the storage capacity projections above.

---

## 3. Request and concurrency capacity (MEASURED LIVE)

### Method
- **Load generator:** a temporary Edge Function, `bench-load`, run in parallel and fired from the database. It calls the project's own API gateway (`/rest/v1`) exactly as the app does: the same PostgREST embeds, select strings and RPCs, taken from the app's code.
- **Real user sessions:**
  - 109 students, 27 supervisors and 16 company admins.
  - Signed in through the normal `/auth/v1/token` password grant.
  - Every request runs as `authenticated` with RLS on; the service key is never used for the measured traffic.
  - Each session serves several virtual users.
- **Rush-hour mix:** 90% students, 7% supervisors, 3% admins.
  - **A student's app open:** 7 calls in sequence:
    - the current-subscription embed
    - their profile
    - the week's votes
    - vote settings
    - the inbox
    - their line's supervisors
    - the receipt card
  - **Think time:** 3–8 s, then the next open.
- **Each stage:** ramp-up, a sustained hold (the measured window), then ramp-down. Timeout 10 s.
- **Database during the load:** the dataset of section 2 (2,470 actives, 423 MB).

### Results (hold window)

| Stage | VUs | Requests | RPS | Error % | p50 | p95 | p99 | Timeouts | 429 / 5xx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| smoke (fresh) | 10 | 448 | 22.4 | **0** | 17 ms | 66 ms | 107 ms | 0 | 0 / 0 |
| A050 | 50 | 914 | 15.2 | **24.7** | 172 ms | >10 s | >10 s | 226 | 0 / 0 |
| A050b (repeat) | 50 | 399 | 6.7 | 43.6 | 9.4 s | >10 s | >10 s | 174 | 0 / 0 |
| R010 (right after) | 10 | 98 | 3.3 | 12.2 | 490 ms | >10 s | >10 s | 12 | 0 / 0 |
| P1 probe (+1.5 min) | 2 | 109 | 4.4 | 0 | 41 ms | 446 ms | 593 ms | 0 | 0 / 0 |
| P2 probe (+3 min) | 2 | 124 | 5.0 | 0 | 28 ms | 117 ms | 156 ms | 0 | 0 / 0 |
| A020 | 20 | 187 | 3.1 | 39.0 | 7.8 s | >10 s | >10 s | 73 | 0 / 0 |
| A020b | 20 | 580 | 11.6 | 8.6 | 31 ms | >10 s | >10 s | 50 | 0 / 0 |
| P3 probe | 2 | 106 | 5.3 | 0 | 26 ms | 117 ms | 142 ms | 0 | 0 / 0 |
| **Scan path** | 8 scanning + 2 reading | 261 | 6.5 | **0** | 37 ms | 129 ms | 539 ms | 0 | 0 / 0 |

**Detail of the first 50-VU run (A050).** It was healthy for its first 33 seconds:
- 1,477 requests, averaging 43 RPS.
- 51 RPS in seconds 20–33, with a peak second of 135 requests.
- Then, from second 35 to 85, almost every request timed out. It recovered only when the load stopped.

**Scan path.** At 10 VUs:
- 5.3 scans/s, p95 107 ms, 0 failures.
- A re-scan of the same student returned `already_checked_in` (36 times), as the unique (student, day, direction) index intends.
- The riders list read at the same time stayed at p95 156 ms.

**Auth sign-in burst.** Of 347 password sign-ins within 28 s, 128 succeeded; the rest got `429 over_request_rate_limit` from Supabase Auth. **MEASURED LIVE.**
- In normal use the app keeps its session, so this applies only to a mass re-login.
- A forced sign-out of all users would hit it.

### What fails, and where
- **Failure mode:** latency and timeouts. **No 429 or 5xx came from the API**, and no connection failures.
- **Where it fails:** in PostgREST, not in Postgres queries. During the stalls, all 10 PostgREST pool connections were `idle in transaction`, waiting 7–9 s for PostgREST (`ClientRead`), even right after `BEGIN`. Postgres had finished its work and was waiting for the API process.
  - When replayed directly in the database as the same users (`bench.workload`), the same queries take 1–60 ms (median), and up to 138 ms for platform analytics, even at 2,470 actives.
- **Pool:** PostgREST 14.5 with a pool of 10 database connections, out of max 60. Once requests stall, the pool fills and every later request queues behind it.
- **Recovery:** after the load stops, the API needs about **3–4 minutes** to get back to normal: p95 446 ms at +1.5 min, 117 ms at +3 min. Load during that window fails again at only 10 VUs.
- **Not observable here:** CPU, RAM and swap of the Nano instance are not exposed through the tools available. The evidence (the database waiting on the API, the slow recovery, a 423 MB database on a 0.5 GB-RAM shared instance) is consistent with the instance's compute or memory being exhausted. That cause is not measured.

### Result

| | Free plan, Nano, 423 MB dataset (MEASURED LIVE) |
|---|---|
| Healthy sustained concurrency | **≈ 10 active users** (≈ 20 RPS, p95 66 ms), on a fresh instance |
| Short-term peak before failing | 50 users, ≈ 45–50 RPS for ≈ 30 s |
| Degradation begins | 20 active users sustained (≈ 10 RPS); p95 jumps to over 10 s |
| First unacceptable point | 20 users sustained, or any 50-user burst lasting more than ≈ 30 s |
| First bottleneck | **The API/compute layer of the Nano instance (PostgREST starved)**, not query time, not rate limiting |
| Failure mode | Timeouts and request queueing, with no 429/5xx |
| Recovery after the load stops | 3–4 minutes |

The 100, 250 and higher levels were **not run**. The stop rule ended the test at 20 users, and pushing the shared instance further would only have prolonged the outage.

### Natural students (run R2, MEASURED LIVE)
The VUs above open the app every 3–8 s without pause, which is far heavier than a real student. R2 repeats the test with a **think time of 30–60 s** between app opens (same sessions, same 7-call open, same 423 MB dataset). Raw data: `perf/live/results/2026-10-12-live-natural.json`.

| Stage | Students | Ramp | Requests (hold) | RPS (hold) | Error % (hold) | p50 | p95 | p99 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| N050 | 50 | 30 s | 630 | 7.0 | **0** | 19 ms | 80 ms | 117 ms |
| N100 | 100 | 30 s | 592 | 6.6 | **94** | >10 s | >10 s | >10 s |
| P probe (after N100) | 2 | – | 77 | 3.9 | 0 | 45 ms | 1,272 ms | 2,479 ms |
| P2 probe (+ ~3 min) | 2 | – | 78 | 5.2 | 0 | 31 ms | 172 ms | 405 ms |
| N100s | 100 | 75 s | 415 | 8.3 | **88** | >10 s | >10 s | >10 s |

- **50 natural students** (≈ 7 RPS sustained): healthy for the whole 90 s hold.
- **100 natural students:** healthy at first. N100 ran at 15–44 RPS during its 30 s ramp and stalled after ≈ 25 s. N100s (slow 75 s ramp) ran ≈ 58 s at 9–18 RPS, then stalled the same way, and stayed stalled while any load continued. Again no 429 or 5xx, only timeouts.
- **Envelope on Free/Nano with this dataset:** ≈ 7 RPS can be held indefinitely; ≈ 10–15 RPS held for about a minute tips the instance over, and it needs 3–4 minutes without load to recover.
- **In app opens (PROJECTED from the above):** ≈ 1 app open per second (7 calls) ≈ 3,600 opens per hour. 1,000 students opening over an hour fit; 1,000 within 15 minutes (≈ 1.1 opens/s) is at the edge; tighter peaks fail.

### Clean database (run R3, MEASURED LIVE)
The 423 MB dataset was then removed:
- `perf/live/clean_bench.sql`, run by the owner in the SQL editor.
- All 4,856 benchmark accounts deleted through the Auth Admin API.
- `VACUUM FULL` on the emptied tables.

The database went back to **23 MB**. The schema fingerprint matched the pre-benchmark one in 13 of 14 categories. The 14th, functions, differs only by the `platform_analytics` fix in `20261124000001_platform_analytics_scan_window.sql`. The super admin, the other real accounts and «الريتاج» were hash-identical before and after.

**The test company:**
- One new company: 100 current students and 194 student accounts over the year, 2 lines, 3 supervisors and 2 admins.
- Every account is a real Auth user created through the Admin API.
- Current-term subscriptions, votes and scans, and notifications were added. Database: **27 MB**.
- 85 students, 2 supervisors and 2 admins signed in through the normal password grant. Supabase Auth allowed about 30 sign-ins per minute (`429 over_request_rate_limit` beyond that).

The same app-open mix and timeouts as R2 were used, with think time 30–60 s. Raw data: `perf/live/results/2026-10-12-live-clean.json`.

| Stage | Students | Ramp / hold | Requests (hold) | RPS (hold) | Error % (hold) | p50 | p95 | p99 |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| N050 (first, right after the cleanup) | 50 | 30 / 90 s | 588 | 6.5 | 4.6 | 88 ms | 9.4 s | >10 s |
| N050b | 50 | 30 / 90 s | 585 | 6.5 | **0.3** | 34 ms | 1.5 s | 7.8 s |
| N100 | 100 | 30 / 90 s | 786 | 8.7 | **27** | 653 ms | >10 s | >10 s |
| P probe (+3 min) | 2 | – | 101 | 5.1 | 0 | 28 ms | 129 ms | 142 ms |
| **N075** | 75 | 30 / 90 s | 1,008 | **11.2** | **0** | 28 ms | 539 ms | 1.9 s |
| N075L1 (right after) | 75 | 20 / 100 s | 987 | 9.9 | 0.6 | 26 ms | 1.9 s | 8.6 s |
| N075L2 (right after, 5 s ramp) | 75 | 5 / 110 s | 1,120 | 10.2 | 9.6 | 117 ms | >10 s | >10 s |

**What changed with the clean database:**
- **75 natural students:** **≈ 11 RPS for 90 s with no errors**. Continuing at that level for another 100 s stayed under 1% errors, though p95 crept up to about 2 s.
- **100 natural students:** still fails, but later and milder than on the 423 MB dataset:
  - It stayed healthy for ≈ 65–75 s, against ≈ 25 s before.
  - Hold errors were 27%, against 94% before.
  - It again recovered within about 3 minutes.
- **N075L2 ramped all 75 students in within 5 s:** ≈ 75 app opens at once. Every error came in the first ≈ 20 s, and the rest of the stage was clean. A synchronised burst does more harm than the same average load spread out.
- **N050 right after the cleanup:** it stalled for ≈ 30 s while the instance was still settling after the large delete and `VACUUM FULL`. The repeat (N050b) was clean.
- **Where the time goes:**
  - The database answered from memory throughout (`blks_read` rose by under 40 blocks over all of R3).
  - The slowest call was again the current-subscription embed (`subscriptions.current`).
  - The stalls look the same as in R1: timeouts with no 429 or 5xx.
- **Conclusion:** the limit is the compute behind the API on the Free/Nano instance, not the size of the data. A clean database moves the sustained ceiling from ≈ 7–10 RPS up to ≈ 10–12 RPS.
- **In app opens (PROJECTED):** ≈ 1.5 app opens per second sustained, ≈ 5,000 per hour, with short bursts of a few dozen simultaneous opens tolerated.

### Scenarios
"Active" means having the app open in the same minute. Each open fires 7 calls.

| Registered | Active now | Fits the measured Free envelope (≈ 10 sustained)? |
|---|---:|---|
| 1,000 | 10% = 100 | **No**: 10× over the measured healthy level |
| 5,000 | 10% = 500 | No |
| 10,000 | 10% = 1,000 | No |
| 25,000 | 5% = 1,250 | No |
| 50,000 | 5% = 2,500 | No |

Paid compute (Micro 1 GB, Small 2 GB, Medium 4 GB) was **not measured**. No user count is claimed for it. The test would have to be re-run after an upgrade (`perf/live/bench-load`, `bench.load_fire`).

### Caveats
- **Where the load came from.** The generator ran on Supabase Edge in the same region. That is a different runtime from the database, but it shares the project's network path. The 10-VU smoke stage and the healthy first 33 s at 50 VUs show the generator could produce at least 135 RPS.
- **Dataset size.** The 423 MB dataset is close to the instance's memory. On the clean launch database (23 MB) the same instance may hold more. That is not measured.
- **Other traffic.** For part of the session, the owner's own dashboard traffic also reached the project.

---

## 4. Verdict

**C) Not ready on the current tier for real rush-hour concurrency.**
- The data model, indexes and RLS queries are sound. Queries take milliseconds at 2,470 active students, with tenant isolation and no slowdown for a 500-student company as the platform grows.
- Storage holds about 2,000–2,600 actives for one year on Free.
- But the Free Nano instance's API layer saturated at about 10–20 simultaneously active users and needed minutes to recover. With natural students (an app open every 30–60 s) that is ≈ 50 students at once, or ≈ 1 app open per second sustained, on the 423 MB dataset. On the clean database it is ≈ 75 students at once (≈ 1.5 opens per second); 100 still fails within about a minute.

**Before launch:**
1. Upgrade to Pro with at least Small compute.
2. Repeat this load test on that compute, against the clean database.
3. Consider merging the student home's 7 calls into one RPC. That would cut requests per app open from 7 to about 2.

Long term:
1. Plan the retention described in section 2 for scans and votes.
2. Avoid forcing every user to sign in again at once.
