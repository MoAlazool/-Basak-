# Admin dashboard — performance pass results

Scope: `admin_web/` only. Numbers below come from `npm run build` and from reading
the code (a static request inventory). Nothing here was measured in a browser:
timings, real request counts and image bytes are the main agent's measurements.

N = pending receipts on screen. "Stage" = has to wait for the previous request.

## 1. Bundle (`npm run build`, vite 5.4.21)

### Before — one chunk

| File | Raw | gzip |
|---|---:|---:|
| `index-D8BjiOuS.js` | 770,699 B | 207,148 B |
| `index-BROXowyP.css` | 41,851 B | 7,924 B |

Every admin downloaded all 770,699 B (all 18 pages of both roles) before anything rendered.

### After — 41 JS chunks

| Chunk | Raw | gzip | Loaded |
|---|---:|---:|---|
| `supabase` | 226,706 | 58,631 | always (vendor, cacheable across releases) |
| `react` (react, react-dom, router) | 164,650 | 53,471 | always (vendor) |
| `query` (TanStack) | 46,769 | 13,828 | always (vendor) |
| `index` (entry: session check, skeletons, cache, route table) | 14,970 | 5,537 | always |
| `icons` (lucide, only the icons used) | 28,337 | 5,416 | with the first area/page |
| `sync` (shell, sidebar, realtime) | 11,448 | 4,261 | both areas |
| `Workspace` | 5,457 | 2,433 | company area |
| `PlatformArea` | 958 | 497 | platform area |
| `LinesPage` | 31,162 | 8,563 | on visit / nav hover |
| `StudentsPage` | 29,149 | 8,768 | on visit / nav hover |
| `History` (notification history, shared) | 24,662 | 7,021 | notifications pages |
| `SubscriptionSettingsPage` | 24,217 | 6,750 | on visit |
| `WalletCardDesignPage` | 19,638 | 6,427 | on visit |
| `PendingReceiptsTable` | 17,517 | 5,959 | overview + receipts |
| `ReportsPage` | 16,300 | 4,811 | on visit |
| `AllCompaniesPage` | 12,478 | 4,174 | platform only |
| `SupervisorsPage` | 12,159 | 4,138 | on visit |
| `notificationsData` | 10,642 | 4,290 | notifications pages |
| `PaymentMethodsPage` | 10,436 | 3,169 | on visit |
| `PlatformNotificationsPage` | 9,874 | 3,692 | platform only |
| `UniversitiesPage` | 9,694 | 3,080 | platform only |
| `CompanyAdminsPage` | 7,814 | 2,736 | platform only |
| `AllStudentsPage` | 7,710 | 2,822 | platform only |
| `NotificationsPage` | 6,288 | 2,649 | on visit |
| `LoginPage` | 5,844 | 2,283 | signed out only |
| `PlatformOverviewPage` | 5,512 | 2,124 | platform only |
| `PasswordResetRequests` | 5,409 | 2,023 | students pages |
| `TopLinesPanel` | 5,340 | 1,657 | overview pages |
| `TeamPage` | 4,878 | 1,988 | on visit |
| `ResetPasswordPage` | 3,973 | 1,672 | recovery link only |
| `OverviewPage` | 2,816 | 1,356 | on visit |
| 10 small shared chunks (`overview`, `reference`, `Topbar`, `StatsRow`, `signedUrls`, `ReceiptsPage`, `edgeFunctions`, `toasts`, `saleOptions`, `BasakLogo`) | 11,693 | 6,127 | as needed |
| **All JS** | **794,500** | **242,353** | never all at once |
| `index-CZiIXUnq.css` | 41,946 | 7,889 | always |

### What one visit downloads (entry + everything it imports statically)

| Landing | Before raw / gzip | After raw / gzip | Change |
|---|---|---|---|
| Session check + skeleton (first paint) | 770,699 / 207,148 | 453,095 / 131,467 | −41% / −37% |
| Sign-in page | 770,699 / 207,148 | 487,541 / 139,416 | −37% / −33% |
| Company admin → overview | 770,699 / 207,148 | 533,026 / 157,017 | −31% / −24% |
| Company admin → receipts | 770,699 / 207,148 | 524,728 / 154,019 | −32% / −26% |
| Company admin → students | 770,699 / 207,148 | 539,930 / 158,029 | −30% / −24% |
| Platform admin → platform overview | 770,699 / 207,148 | 515,981 / 150,413 | −33% / −27% |

438,125 B of that (supabase + react + query) is vendor code in its own files: unchanged by a
dashboard release, so a returning admin re-downloads only the small app chunks. The three vendor
files are `modulepreload`ed and download in parallel with the entry. The area chunk is requested
as soon as the admin's role is known (not after React renders), and a page's chunk on hover/focus
of its navigation entry.

Honest note: the sum of all chunks grew by 23.8 kB raw / 35.2 kB gzip (per-chunk overhead and
worse cross-file compression). Nobody downloads the sum.

### Fonts

Before: a render-blocking Google Fonts stylesheet, Cairo + Inter, five static weights each.
After: the same five weights (all are used: 400/500/600/700/800) as one variable-font request
per family (`wght@400..800`), stylesheet preloaded and applied without blocking first paint
(`media="print"` swap, `<noscript>` fallback, `display=swap`).

## 2. Request inventory (static)

| Where | Before | After |
|---|---|---|
| **Boot on reload (company admin), before the shell** | 5 requests in 3 stages: `admins` ×2 and `companies(name)` ×2 (two session checks ran), then `companies(id,name,status)` | **1**: `admins` with `companies(id,name,status)` embedded; the row is written into the workspace's cache. Two checks arriving together share that one request |
| Shell on every page | `company_overview` + full reset-request rows (for `.length`) | `company_overview` + a HEAD count of the same function (no rows) |
| Sign-in | 5 sequential REST after auth | 1 (the form and the session listener share it) |
| Tab regains focus (library re-announces the session) | `admins` + `companies(name)` | `admins` (1) |
| Platform admin opens a workspace | `companies(id,name,status)` + `companies(id,name)` uncached in `WorkspaceBar`, every time | 0 if the companies lookup is cached (5 min), else 1 + 1 cached |
| **Receipts page open** | 5 REST in 3 stages, no limit → N × `createSignedUrl` → N full images, all eager | 5 REST in 3 stages, capped at 50 (+«عرض المزيد») → **1** `createSignedUrls` → images lazy (only rows near the viewport download) |
| **Receipts list re-read** (focus after 30 s, any `receipts`/`subscriptions` event from someone else) | 5 + N signs + N full images again (new tokens = new URLs) | 5; **0 signs, 0 image downloads** (same links for 50 min; only a newly arrived receipt's path is signed, in 1 request) |
| Receipt preview click | 1 sign + 1 full image | **0 + 0** when the thumbnail has loaded (same URL, browser cache) |
| **Approve / reject** | 1 PATCH + 2 × (5 list REST + N signs + 1 `company_overview`) = **13 + 2N** requests, **2N** image downloads | **1 PATCH + 1 `company_overview`** (the echo of the subscription change, once); 0 list reads, 0 signs, 0 images. The list is re-read (5 REST) only when fewer than 10 loaded rows remain while more are waiting |
| Students page open | 9: students with `count: 'exact'`, avatar signing, universities + deep lines, then periods (waterfall), switches, reset requests, invites, corrections | 6: students (no count), 1 HEAD exact count, avatar signing (first time; reused 50 min), reset requests, invites, corrections |
| Students: typing in search / changing page | exact count with every query | rows only; exact count once, 700 ms after typing stops; page changes never recount |
| Students: add form | loaded with the page | universities + lines + switches on first focus/click in the form, then periods (0 if another page already cached them) |
| Avatars / supervisor photos on focus or revisit | re-signed (600 s links) → re-downloaded | reused: 0 requests |
| Lines page open | 5 (one combined key) | 5, each under its shared key (reused by Students form, Notifications, Supervisors) |
| Line form open | 2 RPCs to the network every time | 0 when cached (switches always are; settings 1 the first time) |
| Supervisors page | 4, lines and supervisors duplicated under their own keys | 4 cold; supervisors + assignments shared with the Lines page |
| Reports page | 4; undo/reset reloads awaited one after another | 4 cold, 2 when universities/line names are cached; reloads in parallel |
| Universities page | `select('*')`, **every student's university**, colleges | universities (column list, shared key), colleges, `university_student_counts()` |
| Payment methods | `select('*')`; reorder = 2 sequential updates | column list; 2 parallel updates |
| Wallet card page | 1 uncached read, empty body while loading, every visit | cached (`walletCard` key, live-refreshed); skeleton on first visit, instant afterwards |
| Ride confirmation / scan events on any page | `company_overview` re-read every time | re-read only while the overview page is open; otherwise marked out of date |
| Burst of realtime events | pure trailing 400 ms debounce (could be postponed without limit) | 400 ms trailing, at most 2 s after the first event (platform: 1 s / 5 s) |

Keys for the same data: universities 4 → 1 (`shared/universities`); lines 4 → 2
(`lines` deep, `lineNames` light); supervisors 2 → 1; assignments 2 → 1.

## 3. What could not be verified here

- Anything in a browser: time-to-content, the real request counts above, image bytes, lazy
  loading, hover prefetch, the no-sign-in-flash on reload, own-echo suppression against the local
  stack, and that the app renders (only `tsc` and `vite build` were run).
- Browser-cache reuse of receipt images relies on the storage endpoint sending cacheable headers
  for an unchanged signed URL.
- `rpc(..., { head: true, count: 'exact' })` on `admin_list_password_reset_requests` (a HEAD
  request to a STABLE function) was not exercised.
- `university_student_counts()` did not exist while this was written; the page falls back to «—».
