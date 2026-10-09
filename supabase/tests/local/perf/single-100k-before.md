| Request | p50 ms | p95 ms | payload |
|---|---:|---:|---:|
| student: role (my_role) | 8.9 | 13 | 9 B |
| student: current subscription | 8.8 | 13 | 969 B |
| student: subscription history + receipts | 123 | 203 | 556 B |
| student: catalog | 642 | 771 | 570 KB |
| student: profile | 3.0 | 4.7 | 269 B |
| student: card (QR) data | 2.2 | 9.5 | 243 B |
| student: today's vote | 2.3 | 3.6 | 216 B |
| student: vote settings | 2.9 | 12 | 467 B |
| student: inbox page | 55 | 64 | 12 KB |
| student: unread count | 2.3 | 3.5 | 2 B |
| supervisor: dashboard | 294 | 369 | 214 KB |
| supervisor: trip manifest | 69 | 98 | 11 KB |
| supervisor: rider counts (one line) | 59 | 86 | 19 KB |
| supervisor: monthly summary | 62 | 69 | 3 KB |
| admin: company overview | 3417 | 7733 | 25 KB |
| admin: students page 1 (old: nested select) — HTTP 500 | 8044 | 8200 | 100 B |
| admin: students exact count (old) | 110 | 121 | 143 B |
| admin: students page 400 (old) — HTTP 500 | 8081 | 8183 | 100 B |
| admin: students search by name (old) | 311 | 362 | 49 KB |
| admin: students search by phone (old) | 102 | 129 | 2 KB |
| admin: pending receipts (old: 5 requests) | 32 | 43 | 56 KB |
| admin: financial report | 1244 | 2460 | 1165 KB |
| admin: financial report, search | 1643 | 2096 | 1165 KB |
| admin: financial report, current phase | 506 | 597 | 1165 KB |
| admin: notifications history | 7.0 | 11 | 20 KB |
| admin: subscription settings | 174 | 250 | 297 KB |
| platform: overview | 3094 | 5695 | 8 KB |
| platform: all students page | 77 | 95 | 10 KB |
| platform: all students search | 227 | 245 | 10 KB |
| platform: notifications history | 25 | 34 | 23 KB |
| platform: university counts | 4825 | 7977 | 383 B |
