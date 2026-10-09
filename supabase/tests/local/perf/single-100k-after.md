| Request | p50 ms | p95 ms | payload |
|---|---:|---:|---:|
| student: role (my_role) | 2.5 | 4.6 | 9 B |
| student: current subscription | 3.5 | 4.2 | 969 B |
| student: subscription history | 2.2 | 2.8 | 679 B |
| student: receipts of one subscription | 2.0 | 4.5 | 151 B |
| student: catalog | 79 | 98 | 570 KB |
| student: profile | 1.7 | 3.1 | 269 B |
| student: card (QR) data | 1.5 | 2.6 | 243 B |
| student: today's vote | 1.6 | 2.6 | 216 B |
| student: vote settings | 1.9 | 3.5 | 467 B |
| student: inbox page | 2.6 | 3.8 | 12 KB |
| student: unread count | 1.9 | 2.5 | 2 B |
| supervisor: dashboard | 164 | 258 | 214 KB |
| supervisor: trip manifest | 34 | 41 | 11 KB |
| supervisor: rider counts (one line) | 34 | 50 | 19 KB |
| supervisor: monthly summary | 56 | 65 | 3 KB |
| admin: company overview | 220 | 343 | 1877 B |
| admin: students page 1 (old: nested select) — HTTP 500 | 8011 | 8252 | 100 B |
| admin: students exact count (old) | 288 | 380 | 143 B |
| admin: students page 400 (old) — HTTP 500 | 8024 | 8161 | 100 B |
| admin: students search by name (old) | 386 | 481 | 49 KB |
| admin: students search by phone (old) | 101 | 130 | 2 KB |
| admin: pending receipts (old: 5 requests) | 30 | 32 | 56 KB |
| admin: financial report | 871 | 1098 | 1166 KB |
| admin: financial report, first 100 rows | 736 | 791 | 58 KB |
| admin: financial report, search | 1251 | 1458 | 1166 KB |
| admin: financial report, current phase | 377 | 461 | 1165 KB |
| admin: notifications history | 6.8 | 11 | 20 KB |
| admin: subscription settings | 196 | 227 | 297 KB |
| platform: overview | 953 | 1052 | 8 KB |
| platform: all students page | 79 | 89 | 10 KB |
| platform: all students search | 198 | 221 | 10 KB |
| platform: notifications history | 21 | 24 | 23 KB |
| platform: university counts | 24 | 27 | 383 B |
| admin: students page 1 (new RPC, with total) | 100 | 126 | 49 KB |
| admin: students page 1 (new RPC) | 66 | 84 | 49 KB |
| admin: students page 400 (new RPC) | 81 | 89 | 45 KB |
| admin: students search by name (new RPC, with total) | 399 | 471 | 43 KB |
| admin: students search by phone (new RPC) | 165 | 201 | 2 KB |
| admin: pending receipts (new RPC) | 18 | 20 | 45 KB |
| supervisor: rider counts (all lines, one call) | 144 | 185 | 56 KB |
