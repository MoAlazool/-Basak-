
### 10 concurrent users, 30 s — 564 actions (18.8/s), errors 0, timeouts 0
all actions: p50 7.3 ms, p95 167 ms, p99 322 ms, max 551 ms

| Action | count | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| student: catalog (purchase screen) | 68 | 124 | 324 | 551 |
| student: open app | 319 | 7.9 | 76 | 206 |
| student: unread count | 177 | 4.4 | 35 | 161 |

### 50 concurrent users, 30 s — 1210 actions (40.3/s), errors 0, timeouts 0
all actions: p50 564 ms, p95 2253 ms, p99 3512 ms, max 6199 ms

| Action | count | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| admin: overview | 6 | 2796 | 6199 | 6199 |
| admin: pending receipts | 10 | 513 | 890 | 890 |
| admin: report | 5 | 3550 | 3962 | 3962 |
| admin: students page | 9 | 896 | 2010 | 2010 |
| student: catalog (purchase screen) | 130 | 947 | 2385 | 3512 |
| student: open app | 598 | 602 | 1828 | 3115 |
| student: unread count | 363 | 174 | 1487 | 2466 |
| supervisor: dashboard | 47 | 2026 | 3975 | 4635 |
| supervisor: monthly summary | 42 | 797 | 2178 | 2509 |

### 100 concurrent users, 30 s — 1154 actions (38.5/s), errors 76, timeouts 0
all actions: p50 1879 ms, p95 5331 ms, p99 7957 ms, max 10572 ms

| Action | count | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| admin: overview | 14 | 2277 | 5721 | 5721 |
| admin: pending receipts | 9 | 1038 | 4493 | 4493 |
| admin: report | 15 | 3352 | 5494 | 5494 |
| admin: students page | 17 | 1451 | 6682 | 6682 |
| student: catalog (purchase screen) | 117 | 1419 | 4406 | 6567 |
| student: open app | 514 | 2590 | 6006 | 8244 |
| student: unread count | 289 | 812 | 3300 | 4114 |
| supervisor: dashboard | 85 | 2343 | 5834 | 10572 |
| supervisor: monthly summary | 94 | 1196 | 4094 | 9986 |
