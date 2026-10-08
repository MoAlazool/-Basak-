# Performance pass — measurements

All on this Mac against the local stack with `dataset.sql` loaded (5 companies,
15,000 students, 30,000 subscriptions and receipts, 107,250 scans, 750,000
notification recipients). Local numbers have no network latency: on a phone or a
real connection every request costs far more, so request counts matter most.

## Database (`measure.sh`, median of 5, as the user who runs it, RLS and triggers included)

| Statement | Before ms | After ms |
|---|---:|---:|
| receipt insert (student) | 9.812 | 8.337 |
| receipt approve (admin) | 8.768 | 8.522 |
| receipt image access check (admin, 1 image) | 1.791 | 1.674 |
| pending receipts list (admin) | 1.188 | 1.216 |
| company_overview (admin) | 41.714 | 25.985 |
| platform_overview (super admin) | 240.939 | 117.238 |
| admin_subscription_report (admin) | 1063.074 | 105.625 |
| get_subscription_settings (admin) | 13.196 | 13.323 |
| get_company_notifications_page (admin) | 7.241 | 5.859 |
| get_subscription_catalog (student) | 47.465 | 29.576 |
| get_my_notifications_page (student) | 4.637 | 4.805 |
| get_my_unread_count (student) | 1.435 | 1.392 |
| current subscription with trips (student) | 2.562 | 1.892 |
| line trip stops visible (student) | 3.313 | 2.925 |
| payment methods (student) | 3.454 | 1.931 |
| get_supervisor_dashboard (supervisor) | 91.888 | 57.423 |
| students page 1 (admin) | 8.251 | 6.984 |

`outputs.sh` fingerprints what the changed functions return for fixed users: 11 of
13 identical before/after; the other two are report row lists whose totals are
identical and whose rows are the same set (ties now have a fixed order).

## Dashboard, old build (frozen copy, production build served locally), company with 150 pending receipts

| Scenario | Requests | Settled after |
|---|---:|---:|
| One realtime `receipts` event while the receipts page is open | 156 (6 REST + 150 image signings) | 1290 ms |
| Approve one receipt | 311 (13 REST + 298 image signings) | 1520 ms |
| Open overview (full reload) | 8 REST/auth + 236+ image signings | 1034 ms+ |
| Open students (full reload) | 11 | 1544 ms |
| JS downloaded (gzip) | 210 KB, one chunk | |

Every signing produced a new link, so each of these also re-downloads every
receipt image at full size (150 × ~180 KB ≈ 27 MB per refresh; computed, not
measured — the test browser tab does not load images while hidden).

## Dashboard, new build (same data, same method)

| Scenario | Before | After |
|---|---:|---:|
| Approve one receipt | 311 requests, 1520 ms | 3 requests, 622 ms |
| One realtime `receipts` event on the receipts page | 156 requests, 1290 ms | 6 requests, 578 ms |
| Open receipts page (full reload) | 150 image signings + all 150 rows | 1 batched signing, first 50 rows, 728 ms |
| Open overview (full reload) | 8 + 236 signings, 1034 ms | 7 + 1 signing, 538 ms |
| Open students (full reload) | 11 requests, 1544 ms | 7 requests, 1494 ms |
| JS downloaded for the first page (gzip) | 210 KB | 152 KB |

Image links are now reused across refreshes, so thumbnails are not downloaded
again (not measurable here: the test browser tab does not load images while hidden).
