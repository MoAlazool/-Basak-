
### 10 concurrent users, 30 s — 290 actions (9.7/s), errors 0, timeouts 0
all actions: p50 42 ms, p95 2795 ms, p99 3891 ms, max 4210 ms

| Action | count | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| student: catalog | 103 | 1293 | 3288 | 3931 |
| student: open app | 95 | 36 | 145 | 217 |
| student: unread count | 92 | 14 | 44 | 175 |

### 50 concurrent users, 30 s — 237 actions (7.9/s), errors 60, timeouts 1
all actions: p50 6130 ms, p95 10098 ms, p99 12702 ms, max 15004 ms

| Action | count | p50 ms | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| admin: overview | 1 | 12702 | 12702 | 12702 |
| admin: pending receipts | 1 | 10930 | 10930 | 10930 |
| admin: report | 1 | 10096 | 10096 | 10096 |
| admin: students page | 3 | 9910 | 15004 | 15004 |
| student: catalog | 74 | 7281 | 11139 | 13080 |
| student: open app | 63 | 9175 | 10091 | 10098 |
| student: unread count | 63 | 3636 | 9901 | 9930 |
| supervisor: dashboard | 13 | 6130 | 9892 | 9892 |
| supervisor: monthly summary | 18 | 5796 | 10096 | 10096 |
file:///Users/tank/Projects/Basak/supabase/tests/local/perf/bench.mjs:73
  const subIds = [...new Set(receipts.map((r) => r.subscription_id))];
                                      ^

TypeError: receipts.map is not a function
    at pendingReceiptsOld (file:///Users/tank/Projects/Basak/supabase/tests/local/perf/bench.mjs:73:39)
    at process.processTicksAndRejections (node:internal/process/task_queues:103:5)
    at async file:///Users/tank/Projects/Basak/supabase/tests/local/perf/bench.mjs:199:22
    at async Promise.all (index 99)
    at async runLoad (file:///Users/tank/Projects/Basak/supabase/tests/local/perf/bench.mjs:193:3)
    at async file:///Users/tank/Projects/Basak/supabase/tests/local/perf/bench.mjs:217:91

Node.js v22.23.3
