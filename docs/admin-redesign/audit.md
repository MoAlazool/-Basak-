# Basak admin dashboard (`admin_web/`) — audit for the redesign

Read-only audit, 2026-10-10. All paths are relative to `admin_web/src/` unless they start with another folder.
`file:line` points at the line as it is on branch `claude/basak-mobile-redesign-77ca6a`.

**How each fact was established**

- **Read**: every file of the shell, `areas/`, every company-area page and component, and `lib/` (except the two notification libs and `appVersions.ts`) was read in full by me.
- **Read by a helper agent**: the seven platform pages, `PlatformComposer.tsx`, `lib/notifications.ts`, `lib/notificationsData.ts`, `lib/appVersions.ts` (section 10 and parts of 6–9). I did not re-read those lines myself.
- **Run**: `npx tsc --noEmit` (exit 0), `npx vitest run` (5 files, 95 tests, all pass), `vite build` into the scratchpad (not into the repo) and `scripts/check-bundle.mjs` against it. `git status` after: only the pre-existing untracked `.claude/`.
- **Counted** with grep over `src/**/*.tsx`; counts are of class-name occurrences, not rendered elements.
- **Not done**: nothing was opened in a browser. Every statement about what happens at 360 px is derived from the classes, not observed.

---

## 1. Roles and structure

### 1.1 How role and scope are decided

| Step | Fact | Where |
|---|---|---|
| Who is an admin | One row of table `admins` for the signed-in user id, with its company embedded: `id, email, full_name, role, company_id, companies(id, name, status)` | `lib/adminProfile.ts:31-32` |
| Roles | Exactly two: `'super_admin' \| 'company_admin'` | `lib/adminScope.tsx:7` |
| Not an admin | Sign-in is undone: `signOut()` + "هذا الحساب غير مسجل كمسؤول في النظام." | `pages/LoginPage.tsx:57-60`, `App.tsx:63-67` |
| Home | `super_admin` → `/platform`; `company_admin` → `/c/{company_id}`; any unknown URL redirects there | `App.tsx:113`, `App.tsx:125` |
| Platform routes | Only mounted for `super_admin` | `App.tsx:121-123` |
| Workspace guard | `allowed = super_admin \|\| companyId === admin.company_id`; otherwise redirect to own company | `areas/Workspace.tsx:25`, `:47` |
| Suspended / archived company | A company admin gets a full-page notice and only a sign-out button; a super admin still gets in | `areas/Workspace.tsx:58-64` |
| Company scope | `CompanyScopeProvider` keyed by company id; every workspace page reads `useCompany()` | `areas/Workspace.tsx:69`, `lib/adminScope.tsx:43-47` |
| Workspace switching | Super admin only: a bar with «العودة إلى المنصة» and a `<select>` of companies that keeps the current sub-page | `components/WorkspaceBar.tsx:20`, `:25-28`, `:36-45` |
| Memberships | There is no multi-company membership for an admin: one `company_id` per admin row (`lib/adminScope.tsx:8`). "Membership" in the code is student ↔ company (`company_students`, `company_invites`). | `components/MembershipRequests.tsx:26` |
| Finer permissions | None inside a company: every company admin sees all 11 pages. Two per-role differences inside shared pages: reset-password and delete-account icons are super-admin only (`pages/StudentsPage.tsx:587`, `:610`), and adding a team admin is super-admin only (`pages/TeamPage.tsx:19`). | |

### 1.2 Navigation — company admin (workspace), exactly as `lib/nav.ts:35-50`

Flat list, no grouping, no sections, in this order. Sidebar label = `name`; bottom-bar label = `short`.

| # | Sidebar label | Bottom-bar label | Route | Badge |
|---|---|---|---|---|
| 1 | نظرة عامة | الرئيسية | `/c/:id` | — |
| 2 | الطلاب | الطلاب | `/c/:id/students` | `requests` (open password-reset requests) |
| 3 | فحص الإيصالات | الإيصالات | `/c/:id/receipts` | `receipts` (pending receipts) |
| 4 | الخطوط والمحطات | الخطوط | `/c/:id/lines` | — |
| 5 | المشرفون | المشرفون | `/c/:id/supervisors` | — |
| 6 | الإشعارات | الإشعارات | `/c/:id/notifications` | — |
| 7 | التقارير المالية | التقارير | `/c/:id/reports` | — |
| 8 | وسائل الدفع | الدفع | `/c/:id/payment-methods` | — |
| 9 | بطاقة المحفظة | البطاقة | `/c/:id/wallet-card` | — |
| 10 | فريق الإدارة | الفريق | `/c/:id/team` | — |
| 11 | إعدادات الشركة | الإعدادات | `/c/:id/settings` | — |
| — | تسجيل الخروج | خروج | (button) | — |

A super admin inside a workspace sees the same 11 items plus the workspace bar (`areas/Workspace.tsx:122`).
The settings entry uses the calendar icon `CalendarRange`, not a gear (`lib/nav.ts:48`).

### 1.3 Navigation — super admin (platform), `lib/nav.ts:23-32`

| # | Sidebar label | Bottom-bar label | Route |
|---|---|---|---|
| 1 | نظرة عامة على المنصة | المنصة | `/platform` |
| 2 | كل الشركات | الشركات | `/platform/companies` |
| 3 | كل الطلاب | الطلاب | `/platform/students` |
| 4 | إشعارات المنصة | الإشعارات | `/platform/notifications` |
| 5 | مديرو الشركات | المديرون | `/platform/admins` |
| 6 | الجامعات والوجهات | الجامعات | `/platform/universities` |
| 7 | الإعدادات الافتراضية | الافتراضي | `/platform/defaults` |
| 8 | إصدارات التطبيق | الإصدارات | `/platform/app-versions` |

No badges are passed to the platform shell (`areas/PlatformArea.tsx:16`), although the platform overview hosts the reset-request queue (`pages/PlatformOverviewPage.tsx:55`).

### 1.4 First screen per role

- **Company admin**: `OverviewPage` — four stat cards, a 7-day bar chart, "top lines", then the pending-receipts table at the bottom (`pages/OverviewPage.tsx:30-69`).
- **Super admin**: `PlatformOverviewPage` (`areas/PlatformArea.tsx:20`).
- **Signed out**: `LoginPage` (email + password). **Recovery / invite link**: `ResetPasswordPage` (`App.tsx:21`, `:106`).

### 1.5 The shell

- `Shell` = sidebar (≥ `md`) + `main` + bottom bar (< `md`) + toasts (`components/Shell.tsx:19-45`).
- Sidebar is 72 px icons-only from `md` to `lg`, 230 px with labels from `lg` (`components/Sidebar.tsx:27`, `:60`).
- Two page-header styles coexist: `Topbar` (title, today's date, a bell button with no handler, an identity chip — `components/Topbar.tsx:34-36`) is used by Overview, Receipts, Settings, Team and five platform pages; the other pages draw their own `h1` (`pages/LinesPage.tsx:189`, `pages/StudentsPage.tsx:344`, `pages/SupervisorsPage.tsx:207`, `pages/PaymentMethodsPage.tsx:132`, `pages/WalletCardDesignPage.tsx:307`, `pages/ReportsPage.tsx:105`, `pages/NotificationsPage.tsx:26`).
- The tab title carries the waiting total: `(N) …` (`areas/Workspace.tsx:115-120`).

---

## 2. Page inventory (company area)

Sizes are `wc -l`.

### OverviewPage — 72 lines (+ StatsRow 48, WeeklyRidersChart 94, TopLinesPanel 76, PendingReceiptsTable 386)
- **Job**: the company at a glance. It also carries the whole receipt-review queue, so it does two jobs (`pages/OverviewPage.tsx:60-68`); the same table is the entire Receipts page.
- **Shows**: 4 cards — «الاشتراكات السارية اليوم» (hint: members), riders card (label switches between «نازلين اليوم (مؤكدين)» and «مؤكدون لرحلة {day}» — `lib/overview.ts:81-93`), «إيصالات بانتظار المراجعة», «إجمالي الإيرادات المسجلة» (`pages/OverviewPage.tsx:33-36`); bar chart «نشاط الركاب خلال الأسبوع»; list «الخطوط الأكثر اشتراكاً» (top 5).
- **Actions**: retry on error; everything in the receipts table. Nothing else is clickable: the stat cards are plain `div`s (`components/StatsRow.tsx:27-44`), and the footer «عرض كافة خطوط السير وتفاصيلها» is a `div` with `cursor-pointer` and no handler (`components/TopLinesPanel.tsx:70-73`).

### ReceiptsPage — 23 lines (+ PendingReceiptsTable 386)
- **Job**: decide pending receipts, oldest first.
- **Table columns** (`components/PendingReceiptsTable.tsx:170-175`): الطالب (thumbnail, name, phone, university • college • specialisation) · الشركة وخط السير (company chip, line, station, ذهاب/عودة times) · الاشتراك والمبلغ (type pill, period label, ISO dates, «دفع مقدم», amount) · المحاولة («N من 5») · وقت الرفع · الإجراءات (قبول / رفض).
- **Actions**: client-side search over loaded rows (`:50-55`); open image preview (`:78-84`); قبول — one click, no confirmation, no undo (`:89-98`); رفض → modal with a mandatory reason (`:101-121`); «عرض المزيد من الإيصالات» (50 at a time, `lib/pendingReceipts.ts:12`).
- **Dialogs**: reject-reason modal (`:302-339`); image preview modal with a fixed `h-80` image box and no approve/reject buttons inside it (`:342-383`).
- The company chip repeats the admin's own company on every row (`:224`).

### StudentsPage — 646 lines (+ PasswordResetRequests 172, MembershipRequests 81, ResetStudentPasswordDialog 96)
- **Does four unrelated jobs in this order** (`pages/StudentsPage.tsx:350-351`, `:354`, `:491`): (1) password-reset request queue, (2) outgoing invitations and correction requests, (3) a 9-field "add student" form, (4) the students list.
- **Table columns** (`:519-524`): اسم الطالب · رقم الهاتف · الجامعة / الكلية · الاشتراك وخط السير · تاريخ التسجيل · إجراءات. The subscription cell stacks, per subscription: phase chip, period label, line, times, price and a status `<select>` (`:553-573`).
- **Actions**: server search, debounced 300 ms (`:79-82`); paging 25 (`:24`, `:627-633`); add student → edge function `admin-create-student` (`:250`); change a subscription's status by picking from a `<select>` — saved at once, no confirmation (`:570`, `:324-333`); request a name correction through `window.prompt` (`:295`); remove student from company through `confirm` (`:278`); super admin only: reset password dialog (`:587-595`), delete account (`:610-618`).
- **Reset queue** (`components/PasswordResetRequests.tsx`): table الطالب · وقت الطلب · الحالة · إجراءات (`:129-132`); «إصدار رمز» → `confirm` → code shown once in a green box (`:63-71`, `:106-122`); «إلغاء» → `confirm` (`:74`). The card disappears entirely when there are no requests (`:87`).
- **MembershipRequests**: two read-mostly lists (last 10 each) — «دعوات لحسابات موجودة» with a cancel action (`:52-63`), «طلبات تصحيح البيانات» (`:68-76`).

### LinesPage — 757 lines
- **Job**: list lines; create/edit a whole line (details, universities, prices, stations, trips, stop times) in one full-screen editor.
- **List**: one card per line — name, نشط/معطّل chip, station chips, university chips, trip counts, prices sentence, supervisors (`pages/LinesPage.tsx:222-257`). Buttons per card: المواعيد (expand timetable), تعديل, تعطيل/تفعيل, حذف (`:259-271`).
- **Timetable** (read-only, tabs الذهاب / العودة, cards per trip): `:294-349`.
- **Editor** (`LineEditor`, `:359-757`): three numbered sections «١. بيانات الخط», «٢. محطات الصعود (بترتيب المسار)», «٣. الرحلات والمواعيد». Details in section 4.
- **Dialogs**: the editor (`:526`); native `confirm` for disable and delete (`:166`, `:175`).

### SupervisorsPage — 372 lines
- **Job**: add a supervisor (inline form at the top) and manage the list.
- **Table columns** (`pages/SupervisorsPage.tsx:271-275`): اسم المشرف (photo upload + name) · رقم الهاتف · الخطوط المسندة · الحالة · إجراءات.
- **Actions**: add (edge function `admin-create-supervisor`, `:139`); upload / remove photo (`:95-125`); edit assigned lines inline (`:163-184`); toggle active by clicking the status pill, no confirmation (`:186-190`, `:350-355`); delete with `confirm` (`:193`).
- **Missing actions**: no edit of name or phone, and no password reset for a supervisor — the page says the password "لا تظهر بعد الإنشاء" (`:209`); the only remaining route is delete and re-create.

### NotificationsPage — 46 lines (+ Composer 138, NotificationForm 98, AudiencePicker 97, History 244, EditScheduledDialog 78, NotificationDetails 75, PhonePreview 28, parts 77)
- **Job**: compose a notification and see the history. Two stacked jobs.
- **Composer**: audience pills (كل طلاب الشركة / طلاب خط / ركاب رحلة / طلاب جامعة — `lib/notifications.ts:155-158`), title (max 80), body (max 600), high-priority checkbox, now / later with a `datetime-local` in Cairo time, three ready-made messages (`components/notifications/Composer.tsx:15-19`), phone preview, server-counted audience card, confirm dialog before sending (`:118-135`).
- **History**: status filter pills, search over loaded rows, refresh, list rows with chips and read/push numbers, per-row details / edit / cancel / delete (`components/notifications/History.tsx:84-100`), «عرض المزيد».
- **Dialogs**: confirm send, details, edit scheduled, cancel, delete — all through one `Dialog` component (`components/notifications/parts.tsx:10-18`).
- A banner appears when push is not connected (`pages/NotificationsPage.tsx:32-40`).

### ReportsPage — 316 lines
- **Job**: revenue totals and the subscription ledger; also "reset the figures".
- **Shows**: 4 stat tiles (`:123-126`), 5 revenue tiles that act as filter shortcuts (`:129-133`), 7 filters + a "full history" checkbox (`:138-169`), a table, a reset log.
- **Table columns** (`:190`): الطالب · الشركة / الخط · الفترة · الدفع · المبلغ المدفوع · تاريخ الدفع · الصلاحية · الحالة.
- **Actions**: filter; «عرض المزيد» (100 rows, `lib/reports.ts:4`); «تصفير البيانات المالية» and «تصفير كل البيانات» open a dialog that requires typing an English phrase (`:273`, `:304-305`); undo a reset with `confirm` (`:95`). The two reset buttons are shown to every company admin with no role check (`:111-118`).
- No export (CSV/print) exists in the page.

### PaymentMethodsPage — 212 lines
- **Job**: the accounts students pay into.
- **List**: one row-card per method: icon, display name · type, the account detail, holder, مفعّلة/معطّلة chip, five icon buttons (up, down, edit, power, delete) (`pages/PaymentMethodsPage.tsx:149-166`).
- **Dialog**: add/edit form (`:170-209`); delete uses `confirm` (`:118`).

### WalletCardDesignPage — 435 lines
- **Job**: the company's Apple/Google Wallet card: logo, contact phone, three colours, alternative title, banner; saving also publishes to installed cards.
- **Shows**: two form cards, a "design status" card (last update, by whom, Apple cards, Google cards, pending cards — `:393-412`), two live previews (`:416-429`).
- **Actions**: pick/remove logo and banner; «حفظ ونشر على بطاقات الشركة» (`:378-381`); «تراجع عن التغييرات» (`:383-386`); «استكمال النشر» (`:407-410`).

### TeamPage — 114 lines
- **Job**: list the company's admin accounts. For a company admin it is read-only (`:19`, `:110`).
- **Table columns** (`:91`): المدير · البريد · تاريخ الإنشاء. Super admin also gets a 3-field "add admin" form (`:62-80`).

### SubscriptionSettingsPage (`CompanySettingsPage`) — 439 lines (+ VoteSettingsCard 279)
- **Does seven unrelated jobs on one scroll**, in this order: الفصول الدراسية (dates + on-sale toggles, `:229-297`) · الفصلان معاً (`:299-324`) · الاشتراك المسبق في الفترة القادمة (`:326-338`) · ما يراه الطلاب الآن (read-only preview per line, `:340-369`) · بيانات الشركة على الإيصال (`:371-403`) · الاشتراك اليومي (كاش) (`:405-432`) · مواعيد تأكيد الرحلة والتذكير (`:436`).
- **Terms table columns** (`:241`): الفصل · البداية · النهاية · معروض للبيع.
- The same file is the platform's «الإعدادات الافتراضية» with `companyId = null` (`:69`).

### LoginPage — 208 lines; ResetPasswordPage — 82 lines
- Login: email, password (show/hide), «نسيت كلمة المرور؟ أرسل رابط استعادة», submit (`pages/LoginPage.tsx:125-197`). Sign-in is by **email**, while students and supervisors sign in by phone (`pages/SupervisorsPage.tsx:209`).
- Reset: new password + confirmation, min 8 (`pages/ResetPasswordPage.tsx:20-27`).

---

## 3. The company admin's real tasks

Ordered by how often they must happen. "Steps" counts taps/clicks and typed fields on the shortest path, read from the code.

| # | Task | Starts at | Steps today | What is confusing or easy to get wrong |
|---|---|---|---|---|
| 1 | **Approve a receipt** | Nav 3 «فحص الإيصالات» (badge), or the bottom of Overview | Tap 40-px thumbnail → look at a 320-px-high image → close → tap «قبول». 3 taps. | «قبول» saves at once with no confirmation and no undo (`components/PendingReceiptsTable.tsx:89-98`, `:262-269`). The preview has no approve/reject buttons, so the decision is taken on the row after closing the image (`:342-383`). The table is `min-w-[920px]` (`:167`); in RTL the action column is the last one, so on a phone it is reached by scrolling the table sideways. The image box is fixed `h-80` with `object-contain` and no zoom (`:357`, `:371`). The amount to check against is in another column of the row, not beside the image except as small text in the modal header (`:351`). |
| 2 | **Reject a receipt** | same | «رفض» → type a reason → «تأكيد الرفض». 2 taps + typing. | Reason is free text every time; examples are only in the placeholder (`:318`). The modal disappears and the row leaves before the server answers (`:109-110`); a failure comes back as a toast. |
| 3 | **See who rides tomorrow** | Overview, second card | 0 taps, one number | Only one company-wide number exists (`riders_next`, `lib/overview.ts:16`, shown at `pages/OverviewPage.tsx:34`). No per-line, per-trip or per-station count anywhere in the dashboard, though the database functions exist (section 11). The label changes by time of day (`lib/overview.ts:84-92`). |
| 4 | **Answer a password-reset request** | Nav 2 «الطلاب» (badge) — top card | «إصدار رمز» → native `confirm` → read the code to the student by phone. 2 taps. | The code is shown once in a box above the table (`components/PasswordResetRequests.tsx:106-122`); leaving the page loses it. The copy and close buttons are bare 16-px icons (`:117-118`). The task lives under "Students", not under anything named for it; a company admin cannot set a password directly (`pages/StudentsPage.tsx:587`). |
| 5 | **Send a notification** | Nav 6 | Choose audience pill (+1–3 selects) → title → body → «إرسال الإشعار» → confirm. 2 fields, 2–3 taps. | Works as a guided flow with a server-counted audience and a confirmation (`components/notifications/Composer.tsx:118-135`). Jargon: «أولوية عالية», push health numbers such as «قبِلها مزوّد الإشعارات» (`lib/notifications.ts:271`). |
| 6 | **Fix a student's subscription** (status) | Nav 2 → find the student → status `<select>` inside the row | 1 select | All five statuses are offered for every subscription and the change saves on select with no confirmation (`pages/StudentsPage.tsx:570`, `:324-333`): one mis-tap sets «نشط» without a payment or «مرفوض» on a paid one. The cell is inside a table with no minimum width. |
| 7 | **Add a student by hand** | Nav 2, third block | 9 inputs: name, phone, university, line, station, departure trip, return trip, type, period, password (`pages/StudentsPage.tsx:359-487`) | Password is typed in a visible `type="text"` field (`:468`). Requires at least three names (`:231`). If the phone already has an account, an invitation is sent instead and the student is **not** added (`:256-259`). All errors are toasts in the top-left corner (`:231-243`), away from the field. |
| 8 | **Remove a student / ask for a name fix** | Row icons | 1 tap + native `confirm` / `prompt` | Icons are 16 px with `title` only (`:596-609`). The name fix is typed into `window.prompt` (`:295`) and goes to the platform admin; nothing on the row shows that a request is pending. |
| 9 | **Add / edit a line** | Nav 4 → «إنشاء خط جديد» | See 4.1. Minimum for 4 stations, 1 trip each way: 1 university tick + 4 station names + 1 «تعبئة تلقائية» + save ≈ 7 inputs; realistic (3 morning trips) ≈ 20+ time fields. | Default prices 3500 / 3500 / 6500 and daily 50 are pre-filled and will be saved if untouched (`pages/LinesPage.tsx:111-114`). The universities list comes from the platform; a company admin cannot add a missing university and nothing says who can (`:548-565`; the page is platform-only, `lib/nav.ts:29`). Two different places must both allow an option before students see it: the line's per-option switch (`:577`) and the company's «معروض للبيع» switch (`pages/SubscriptionSettingsPage.tsx:268`). |
| 10 | **Add a supervisor** | Nav 5, top form | 3 fields + ≥ 1 line chip + submit | A line must exist first (`pages/SupervisorsPage.tsx:28`, `:131`). The password is shown as plain text and can never be seen or reset again (`:239`, `:151`). Status is changed by tapping the status pill (`:350`). |
| 11 | **Set up / change payment methods** | Nav 8 → «إضافة وسيلة دفع» | type + 2–5 fields + save | No client-side validation; a bad or missing account number comes back as a database constraint (`pages/PaymentMethodsPage.tsx:85-87`). Without an active method students cannot pay; the page says so only in its empty state (`:147`). |
| 12 | **Open / close a subscription period** | Nav 11 «إعدادات الشركة», first card | Toggle «معروض للبيع» (saves at once) | In the same table, dates need «حفظ المواعيد» while the toggle saves immediately (`pages/SubscriptionSettingsPage.tsx:268` vs `:279-282`). Dates are day-number + month select with no year (`:246-256`); saving dates can move open subscriptions (`:189-190`) with no warning beforehand. Five related switches are spread over four cards (`:268`, `:312`, `:335`, `:419`) plus per-line switches in the line editor. |
| 13 | **Set vote / confirmation hours** | Nav 11, last card on the page | 2 time fields + 1 select + day chips + save | It is the seventh block of the settings page (`:436`). The card title says «تأكيد الرحلة», its fields say «التصويت» (`components/VoteSettingsCard.tsx:160`, `:172`). "Days without reminder" does not stop voting (`:197`). |
| 14 | **Design the wallet card** | Nav 9 | 0–8 inputs + 1 save | Colours are typed as HEX (`pages/WalletCardDesignPage.tsx:57-61`). One button both saves and pushes to every installed card (`:380`); there is no "save without publishing". |
| 15 | **Read reports** | Nav 7 | scroll | An 8-column table with no minimum width (`pages/ReportsPage.tsx:188`). Two destructive-looking reset buttons sit at the top of a read-mostly page (`:111-118`); the confirmation must be typed in English (`:273`). |
| 16 | **Receipt footer data** (phone, address, register, tax no.) | Nav 11, fifth card | 4 fields + save | Shares the page with term dates; the logo for the same receipt is set on another page (`pages/SubscriptionSettingsPage.tsx:375-376`). |

"Answer a membership request" does not exist as a company task in the code: a student joins by subscribing (toast «طالب جديد», `lib/sync.ts:89`), invitations are sent by the company and answered by the student (`components/MembershipRequests.tsx:13`), and corrections are decided by the platform admin (`:14`).

### 3.1 First-run path

What must exist before a student can subscribe, in the order the code forces:

1. **Platform admin** creates the company with its first admin and, optionally, a first payment method (edge function `admin-create-company`; `supabase/functions/admin-create-company/index.ts:35-49`). The company gets its own copy of the term dates and a default wallet card (same file `:46`; on-screen note `pages/AllCompaniesPage.tsx:229`). First and second terms start on sale, summer does not (`supabase/migrations/20261024000001_subscription_options.sql:18-22`).
2. **Platform admin** must have the destination universities in the catalogue; the company admin has no page for this (`lib/nav.ts:29`).
3. **Company admin signs in** (email + password, or an emailed invite link) and lands on Overview with zeros.
4. **A line**: at least one university (`pages/LinesPage.tsx:457`), a price above zero for each enabled option (`:458`), a start time on each return trip (`:462`), at least one stop time on each departure trip (`:464`), stop times in route order (`:470`).
5. **A payment method**, if none was added in step 1 (`pages/PaymentMethodsPage.tsx:147`).
6. **A supervisor** — needs the line from step 4 (`pages/SupervisorsPage.tsx:28`, `:131`). Not needed to subscribe, needed to ride.
7. Optional: term dates, switches, vote hours (follow the platform until edited — `components/VoteSettingsCard.tsx:166`), wallet card, receipt data.

**Guidance in the dashboard: none.** There is no checklist, progress or "next step". After a company is created the super admin is simply navigated into the empty workspace (`pages/AllCompaniesPage.tsx:189-190`). The only hints are sentences inside individual empty states: lines (`pages/LinesPage.tsx:211`), payment methods (`pages/PaymentMethodsPage.tsx:147`), "add a line first" in the supervisor form (`pages/SupervisorsPage.tsx:28`), "بدون مشرف (من صفحة المشرفين)" on a line card (`pages/LinesPage.tsx:255`), and a university with no departure trip (`pages/LinesPage.tsx:729-733`). The one screen that explains why an option is not visible to students («ما يراه الطلاب الآن») is the fourth card of the settings page (`pages/SubscriptionSettingsPage.tsx:340-369`).

---

## 4. Forms

### 4.1 Line editor (`pages/LinesPage.tsx:359-757`)

| | |
|---|---|
| Fields | name (1) + one checkbox per active university + 4 × (switch + price) + daily price + bus seats; one name per station; per departure trip: start, arrival, label, university + one time per station; per return trip: start, university, label; plus a "minutes between stations" helper. With 5 stations and 3 + 2 trips: 1 + U + 8 + 2 + 5 + 3×(4+5) + 2×3 = **49 + U inputs**. |
| Required | ≥ 1 university (`:457`); price > 0 for each enabled option (`:458`); return trip start time (`:462`); ≥ 1 stop time per departure trip (`:464`). Name is optional (server uses the first station, `:542`). |
| Optional | arrival time, trip label, trip university, bus seats, daily price. Station names are not checked on the client. |
| Defaults | prices 3500/3500/6500/0, first and second enabled, daily 50, one empty station, one departure 07:00 and one return 14:00 (`:108-117`); gap 10 minutes (`:362`). |
| Validation | On save only, one message at a time, in the dialog footer (`:745`). Timing problems also show live inside the trip card (`:708-710`). A soft warning for the two-terms price (`:410-414`, `:592`) and for universities with no departure trip (`:727-735`). No per-field error marking. |
| Partial failure | **Yes.** Three requests in sequence: `save_line` (`:503`), then an upsert of `line_period_prices` (`:505-507`), then `set_line_bus_capacity` (`:509-511`). If the second or third fails the line is already saved and the dialog stays open with «تم حفظ الخط لكن تعذر حفظ الأسعار» (`:517-518`). The draft's `id` is never set from the returned `lineId`, so for a **new** line a second press of «حفظ الخط» sends `id: null` again (`:479`) — read from the code, not run. |
| Losing work | Closing (X, «إلغاء») discards the draft with no warning (`:530`, `:747`). No Escape handler, no backdrop close. |

### 4.2 Add student (`pages/StudentsPage.tsx:359-487`)

| | |
|---|---|
| Fields | 10 controls in 8 labelled groups: name, phone, university, line + station, departure + return trip, first subscription type, period (hidden for daily), password. |
| Required | HTML `required` on all but the return trip (`:369`…`:473`); JS checks: three names (`:231`), phone ≥ 10 digits (`:234`), line + station (`:238`), trips (`:239`), password ≥ 8 (`:242`), a period (`:243`). |
| Defaults | First university, first serving line, first station, earliest trips (`:137-149`). The option lists are fetched only once the form is touched (`:130-132`), so the selects start empty. |
| Errors | Toasts only (`notifyError`, `:231-243`, `:268`). |
| Partial failure | One edge-function call; outcome can be "invited instead of created" (`:256-259`). |

### 4.3 Company settings (`pages/SubscriptionSettingsPage.tsx`)

| | |
|---|---|
| Fields | Terms: 3 rows × (name, start day, start month, end day, end month) = 15 + 3 on-sale toggles; 3 more toggles (two terms, advance, daily); 4 receipt fields. |
| Save model | Three models on one page: explicit «حفظ المواعيد» (`:279`), explicit «حفظ البيانات» (`:397`), and toggles that save on click (`:268`, `:312`, `:335`, `:419`). |
| Validation | None on the client for dates (day 1–31 with any month, `:248`); the server validates. Receipt fields are all optional with `maxLength` only (`:380-392`). |
| Errors | Toasts with the server's text (`:121`, `:138`, `:155`, `:163`, `:206`). |
| Partial failure | Company terms: one RPC. Platform defaults: one update per term in a loop (`:195-201`), so some may be saved before a failure (`:207-208`). |
| Unsaved edits | A background refresh overwrites the term drafts (`:89-96`). |

### 4.4 Vote settings (`components/VoteSettingsCard.tsx`)

| | |
|---|---|
| Fields | opens (time), closes (time), reminder (select of 9), 7 weekday chips, holiday dates (date + add). |
| Defaults | From the platform until the company saves its own (`:166`); «الرجوع لإعداد المنصة» resets (`:266-269`). |
| Validation | Opens ≠ closes (`:240`); a date must be today or later and not repeated (`:121`). Save is disabled until something changed (`:271`). |
| Errors | Toast (`:145`). A worked example sentence is shown live (`:243-251`). |
| Partial failure | No — one RPC. |

### 4.5 Supervisors (`pages/SupervisorsPage.tsx:223-258`)

| | |
|---|---|
| Fields | name, phone, password (visible text), line chips. All required; ≥ 1 line (`:131`). |
| Validation | Password ≥ 8 (`:130`); phone is not checked beyond non-empty (`:129`). |
| Errors | Toasts. |
| Partial failure | Creation is one all-or-nothing edge function (`:137-145`). Photo upload is upload → row update → delete old file, with a rollback of the upload on a failed update (`:101-111`). |

### 4.6 Payment method (`pages/PaymentMethodsPage.tsx:170-209`)

| | |
|---|---|
| Fields | type (3 buttons), display name (pre-filled with the type's label, `:33`, `:179`), account holder, then InstaPay address **or** wallet number **or** bank name + account + IBAN, instructions, active checkbox. 5–8 controls. |
| Required | Nothing is marked required. The database constraint `payment_method_fields` decides (`:85`). |
| Validation | None on the client. |
| Errors | Inline in the dialog (`:202`); one constraint is translated, any other error is the raw message (`:85-87`). |
| Partial failure | Save: no. Re-ordering: two parallel updates, either may fail alone; the list is re-read then (`:107-115`). |

### 4.7 Wallet card (`pages/WalletCardDesignPage.tsx`)

| | |
|---|---|
| Fields | logo, contact phone, phone label, background, text colour, small-heading colour, alternative title, banner. All optional except three valid HEX colours (`:290`). |
| Validation | Live: HEX format (`:50`, `:61`), phone pattern (`:37`, `:289`), image type and ≤ 5 MB (`lib/walletArtwork.ts:62-66`), lengths (`:291`). Save is disabled until valid and changed (`:378`). |
| Errors | Inline banner at the top of the page (`:314`). |
| Partial failure | **Yes**, multi-stage: upload logo files (8 files in sequence, `lib/walletArtwork.ts:75-79`), upload banner, save settings RPC (`:273-279`), then a loop of `wallet-sync` batches (`:242-249`). A failure after the RPC leaves the design saved but not on all cards; the page then shows «استكمال النشر» (`:404-411`). |

---

## 5. Responsive facts

### 5.1 Breakpoints in use

Counted occurrences in `*.tsx`: `sm:` 38 · `md:` 15 · `lg:` 40 · `xl:` 8 · `2xl:` 0. Nothing below `sm` (640 px) is distinguished, so a 360-px phone gets the same layout as a 639-px one.

Per file (count of breakpoint-prefixed classes): LinesPage 14 · Skeleton 10 · WalletCardDesignPage 8 · Sidebar 7 · ReportsPage 6 · SupervisorsPage 6 · PaymentMethodsPage 5 · UniversitiesPage 5 · StudentsPage 4 · Shell 4 · Overview 3 · PlatformOverview 3 · AppVersions 3 · AudiencePicker 3 · PlatformComposer 3 · AllCompanies 2 · CompanyAdmins 2 · Composer 2 · History 2 · StatsRow 2 · one each: Settings page, VoteSettingsCard, TeamPage, MembershipRequests, WeeklyRidersChart, NotificationDetails, PlatformNotifications.

**Zero responsive classes**: 5 of the 20 pages — `ReceiptsPage`, `NotificationsPage`, `LoginPage`, `ResetPasswordPage`, `AllStudentsPage` — and 11 components, including the two the company admin uses most: `PendingReceiptsTable` and `PasswordResetRequests` (also `Topbar`, `TopLinesPanel`, `WorkspaceBar`, `Toasts`, `ResetStudentPasswordDialog`, `NotificationForm`, `EditScheduledDialog`, `PhonePreview`, `parts`). The settings page (439 lines) has one.

### 5.2 Sidebar and top bar under `md`

- Sidebar is hidden (`components/Shell.tsx:21`); a small brand row replaces it (`:32-38`).
- Navigation becomes a fixed bottom bar holding **all** items plus sign-out in one row: 12 buttons for a company admin, `overflow-x-auto`, `justify-between` (`components/Sidebar.tsx:87`, `:96-111`). Each button is `px-2 py-1` around a 20-px icon and a 9.5-px label (`:97`, `:100`, `:102`): roughly 44–52 px wide and about 46 px high. On 360 px about seven fit; «وسائل الدفع», «بطاقة المحفظة», «فريق الإدارة», «إعدادات الشركة» and «خروج» are off-screen with no scroll hint (the scrollbar is styled to 6 px, `index.css:70-73`).
- The active item is not scrolled into view (no code does it).
- `main` reserves `pb-24` for the bar (`components/Shell.tsx:25`).
- `Topbar` wraps (`flex-wrap`, `components/Topbar.tsx:20`): title, then a row with the dead bell button and the identity chip. The date line is `text-[12.5px]`.
- Toasts are pinned `left-4 top-4`, 92 vw wide (`components/Toasts.tsx:18`), over the page header on a phone.

### 5.3 Every table at 360 px

| Table | Where | Wrapper | Min width | At 360 px |
|---|---|---|---|---|
| Pending receipts | `components/PendingReceiptsTable.tsx:167` | `overflow-x-auto` `:153` | **920 px** | Sideways scroll; ~2.5 screens wide; action column last |
| Password-reset requests | `components/PasswordResetRequests.tsx:126` | `overflow-x-auto` `:125` | 640 px | Sideways scroll |
| Students | `pages/StudentsPage.tsx:516` | `overflow-x-auto` `:515` | none | 6 columns shrink to content; the subscription cell wraps (`flex-wrap`, `:553`); scroll only if content cannot shrink |
| Supervisors | `pages/SupervisorsPage.tsx:268` | `overflow-x-auto` `:262` | 760 px | Sideways scroll; inline line editing happens inside a cell |
| Reports | `pages/ReportsPage.tsx:188` | `overflow-x-auto` `:187` | none | 8 columns, shrink then scroll |
| Terms | `pages/SubscriptionSettingsPage.tsx:239` | `overflow-x-auto` `:238` | 620 px | Sideways scroll; name input fixed `w-48` (`:262`) |
| Team | `pages/TeamPage.tsx:90` | `overflow-x-auto` `:89` | none | 3 columns, fits or scrolls |
| Platform: company comparison | `pages/PlatformOverviewPage.tsx:70` | yes | 760 px | Sideways scroll |
| Platform: all students | `pages/AllStudentsPage.tsx:142` | yes | 720 px | Sideways scroll |
| Platform: company admins | `pages/CompanyAdminsPage.tsx:122` | yes | none | shrink / scroll |
| Platform: universities | `pages/UniversitiesPage.tsx:201` | **`overflow-hidden`** (`:174`) | none | 5 columns with no scroll container: content that cannot shrink is clipped |

No table hides columns at any breakpoint and none has a card layout for small screens. 11 tables in all.

### 5.4 Fixed and minimum widths

- Search boxes: `min-w-[220px]` (`components/PendingReceiptsTable.tsx:145`), `min-w-[200px] max-w-md` (`pages/StudentsPage.tsx:493`).
- Stop-time inputs `w-28` beside a truncating station name (`pages/LinesPage.tsx:698-700`).
- Term name `w-48`, day `w-16` (`pages/SubscriptionSettingsPage.tsx:250`, `:262`).
- Wallet previews `max-w-[320px]` (`pages/WalletCardDesignPage.tsx:117`, `:156`) — fit 360 px minus padding only just (360 − 32 page − 40 card = 288 px available, so they shrink).
- Page container `max-w-[1400px]`, padding `p-4 sm:p-6` (`components/Shell.tsx:31`).

### 5.5 Dialogs on small screens

| Dialog | Sizing | Scrolls when taller than the screen? |
|---|---|---|
| Line editor | Full screen under `sm` (`p-0 sm:p-6`, `items-stretch`), header/body/footer with the body `overflow-y-auto` (`pages/LinesPage.tsx:526-533`) | Yes |
| Notification dialogs | `max-h-[92vh] overflow-y-auto`, `max-w-lg` / `max-w-3xl` (`components/notifications/parts.tsx:13`) | Yes |
| Payment method | `max-w-lg p-6`, centred, **no max-height, no overflow** (`pages/PaymentMethodsPage.tsx:171-172`) | No — the bank variant has 8 controls plus a 3-row textarea |
| Report reset | same pattern (`pages/ReportsPage.tsx:291-292`), three paragraphs + 3 controls | No |
| Reset student password | same (`components/ResetStudentPasswordDialog.tsx:47-48`) | No |
| Reject reason | `max-w-md` (`components/PendingReceiptsTable.tsx:303-304`) | No (short) |
| Receipt preview | `max-w-lg`, image `h-80` (`:347`, `:357`) | No (short) |
| Create company (platform) | `max-w-lg`, no max-height (`pages/AllCompaniesPage.tsx:206-207`) | No |

For the three "No" dialogs with long content, at 360×640 the centred box can exceed the viewport and the page behind is what scrolls — inferred from the classes.

Inside the line editor at 360 px: a station row is number (28) + pin (16) + input + three 28-px icon buttons (`pages/LinesPage.tsx:613-622`), leaving roughly 110 px for the station name; trip fields are forced into two columns (`grid-cols-2`, `:655`, `:677`) at any width.

### 5.6 Touch targets of row actions

| Control | Size | Where |
|---|---|---|
| Student row icons (correct, remove, reset, delete) | 16×16 px icon, no padding, 12 px apart | `pages/StudentsPage.tsx:588-617` |
| Supervisor "edit lines" pencil | 14×14 px | `pages/SupervisorsPage.tsx:342-345` |
| Supervisor delete | 16×16 px | `:358-361` |
| "Trip does not stop here" X | 14×14 px | `pages/LinesPage.tsx:702-703` |
| Reset-code copy / close | 16×16 px | `components/PasswordResetRequests.tsx:117-118` |
| Station up / down / delete | 28×28 px (`p-1.5`) | `pages/LinesPage.tsx:619-621` |
| Payment-method row icons ×5 | 28×28 px, 4 px apart | `pages/PaymentMethodsPage.tsx:160-164` |
| Notification row icons | 28×28 px | `components/notifications/History.tsx:85-99` |
| Toast close | 24×24 px | `components/Toasts.tsx:34-37` |
| Receipt «قبول» / «رفض» | about 28 px high (`py-1.5`, `text-xs`), 8 px apart, side by side | `components/PendingReceiptsTable.tsx:262-281` |
| Receipt thumbnail | 40×40 px | `:194` |
| Subscription status select | about 26 px high (`py-1 text-xs`) | `pages/StudentsPage.tsx:570` |

None reaches 44 px.

### 5.7 What clearly breaks at 360×640 (derived from classes)

1. Bottom bar: 5 of 12 destinations off-screen, including settings and sign-out (5.2).
2. Receipts: a 920-px table; the decision buttons are at the far end (5.3).
3. Settings: seven cards in one column; vote hours are at the very bottom (`pages/SubscriptionSettingsPage.tsx:436`).
4. Students: reset queue + invitations + a 9-field form are above the list (`pages/StudentsPage.tsx:350-354`).
5. Weekly chart: seven bars with full Arabic weekday names at `text-[12px]` in `flex-1` columns (`components/WeeklyRidersChart.tsx:55`, `:74`); the value appears only on hover (`:57`).
6. Hover-only information: chart tooltip, `title` on icon buttons, the subscription date range (`pages/StudentsPage.tsx:560`).
7. Payment-method, report-reset and reset-password dialogs have no internal scroll (5.5).

---

## 6. Visual language as coded

### 6.1 Palette

- **Tailwind config** (`admin_web/tailwind.config.js:9-18`): `blue.DEFAULT #7EC8E3`, `blue.light #D6EEF9`, `blue.deep #3E8FBF`, `ink.DEFAULT #1F2937`, `ink.soft #5B6B7A`. **None of these tokens is used**: 0 occurrences of `text-ink`, `bg-blue-deep` etc. in `src/`. The same values are also CSS variables (`index.css:5-12`) and are written as literals instead.
- **Hard-coded hex in `*.tsx`: 171 occurrences, 25 distinct values.** Top: `#5B6B7A` ×43, `#3E8FBF` ×31, `#1F2937` ×30, `#7EC8E3` ×16, `#D6EEF9` ×10. Others: `#2E9E5B`, `#DDF3E6`, `#DC2626`, `#B91C1C`, `#FFF1D6`, `#B8860B`, `#3580AC`, `#BFE3F3`, `#EAF7FD`, `#F3FAFD`, `#287D9A`, `#1F6F8B`, `#25854C`, `#A8D8F0`, `#00897B`, `#00658D` (the mobile teal appears once, as the wallet preview fallback, `pages/WalletCardDesignPage.tsx:299`). Plus 9 more in `index.css`.
- **Tailwind families** (class occurrences): slate 751 · rose 158 · blue 111 · emerald 79 · amber 64 · sky 21 · indigo 19 · purple 4.
- **Two visual dialects in one app.** "Glass": translucent panels, `backdrop-filter`, brand hex (`index.css:23-39`), used by Overview, Receipts table, Team, the workspace notice and three platform pages (18 uses of `glass-panel`). "Plain": `rounded-2xl border border-slate-100 bg-white shadow-sm` with `bg-blue-600` primary buttons (24 uses) — Lines, Students, Supervisors, Payment methods, Wallet card, Reports, Settings, Notifications. Team's button is a third blue, `bg-sky-700` (`pages/TeamPage.tsx:75`). So the primary action colour is `#2563EB` on most pages, a `#3E8FBF→#7EC8E3` gradient on login (`pages/LoginPage.tsx:184`), `#2E9E5B` for approve, `sky-700` on Team.
- Compared with the mobile tokens (ink `#17384A`, teal `#00658D`, ground `#F0F5F8`): the dashboard's ink is `#1F2937`, its brand blue `#3E8FBF`/`#7EC8E3`, its ground a radial gradient `#EAF7FD → #F3FAFD → #fff` (`components/Shell.tsx:27`). `theme-color` is `#3E8FBF` (`admin_web/index.html:9`).

### 6.2 Fonts and type

- Loaded from Google Fonts in `admin_web/index.html:17-21`: Cairo and Inter, variable 400–800, non-blocking. Stack is `Inter, Cairo` (`tailwind.config.js:20`, `index.css:16`), so Latin letters and Western digits render in Inter and Arabic in Cairo. The mobile app's Readex Pro is not loaded.
- **Sizes**: `text-xs` 231 · `text-sm` 208 · `text-base` 23 · `text-lg` 12 · `text-2xl` 12 · `text-xl` 4 · `text-3xl` 1, plus **13 arbitrary sizes, 130 occurrences**: `11px` ×73, `11.5px` ×15, `12px` ×10, `10px` ×5, `9px` ×4, `16px` ×4, `13px` ×4, `15px`, `13.5px`, `12.5px`, `10.5px` ×3 each, `9.5px` ×2, `28px` ×1. Most text in the app is 11–14 px.
- **Weights**: bold 295 · semibold 103 · extrabold 20 · normal 19 · medium 14 · `font-mono` 13 (phones, codes).

### 6.3 Radii, shadows, spacing

- Radii: `rounded-xl` 178 · `rounded-lg` 73 · `rounded-full` 61 · `rounded-2xl` 60 · `rounded-3xl` 13 · `rounded-md` 4; plus 22 px on `.glass-panel` (`index.css:29`) and `rounded-[28px]` on the phone preview. (Mobile: 10/14/16/20/28.)
- Shadows: `shadow-sm` 45 · `shadow-2xl` 9 · `shadow` 6 · `shadow-xl` 3 · `shadow-md` 3 · `shadow-lg` 2, plus coloured glows written inline (`components/Sidebar.tsx:33`, `components/WeeklyRidersChart.tsx:68`).
- Spacing: most used `gap-2` 130, `p-4` 101, `py-2`/`px-3` 91, `p-3` 81, `gap-3` 49, `px-4` 44; half-steps are common (`py-1.5` 40, `gap-1.5` 25, `py-2.5` 23, `py-0.5` 23, `px-3.5` 14, `px-2.5` 16). Page rhythm is `space-y-6`.
- Motion: stat cards reference a `fadeIn` keyframe that is defined nowhere (`components/StatsRow.tsx:30`; no match in `index.css` or `tailwind.config.js`), and lift on hover (`:29`).

### 6.4 Icons

`lucide-react`, 66 distinct icons, mostly at 14–20 px. The same idea has different icons: settings uses `CalendarRange` in the nav (`lib/nav.ts:48`); "disable" is `Power` on lines and payment methods (`pages/LinesPage.tsx:267`, `pages/PaymentMethodsPage.tsx:163`) but a tappable status pill on supervisors (`pages/SupervisorsPage.tsx:350`).

### 6.5 How status is shown

| Thing | Values as written | Colours | Where |
|---|---|---|---|
| Subscription status | بانتظار الدفع · قيد مراجعة الإيصال · نشط · مرفوض · منتهي | none — an editable `<select>` | `pages/StudentsPage.tsx:335-337`, `:570` |
| Subscription phase | الحالي · الفترة القادمة · منتهي | emerald / indigo / slate chips | `pages/StudentsPage.tsx:35-39` |
| Report payment | مدفوع · إيصال قيد المراجعة · إيصال مرفوض · غير مدفوع | emerald / rose (all three unpaid states are rose) | `pages/ReportsPage.tsx:198-200` |
| Report phase | ساري · قادم (مدفوع مقدماً) · منتهي | blue / purple / slate | `pages/ReportsPage.tsx:32`, `:210` |
| Receipt queue | «N إيصالات قيد الانتظار», «دفع مقدم», type pill | amber `.pill-pending`, indigo | `components/PendingReceiptsTable.tsx:138-140`, `:240` |
| Line | نشط · معطّل | emerald / slate | `pages/LinesPage.tsx:227-229` |
| Line (overview list) | نشط · متوقف | green / **red** `.pill-rejected` | `components/TopLinesPanel.tsx:60-62` |
| Line (supervisor chips) | «(موقوف)» suffix | — | `pages/SupervisorsPage.tsx:42` |
| Supervisor | نشط · معطل | emerald / rose | `pages/SupervisorsPage.tsx:352-354` |
| Payment method | مفعّلة · معطّلة | emerald / slate | `pages/PaymentMethodsPage.tsx:159` |
| Switches | مفعّل · معطّل | emerald / slate | `pages/SubscriptionSettingsPage.tsx:58` |
| Company | مفعّلة · موقوفة · مؤرشفة | amber for non-active | `lib/adminScope.tsx:49-53`, `components/WorkspaceBar.tsx:34` |
| Reset request | بانتظار التحقق · تم إصدار رمز · تم تغيير كلمة المرور · ملغي · انتهت صلاحية الرمز | amber (open) / slate | `components/PasswordResetRequests.tsx:23-29`, `:146` |
| Invitation | بانتظار موافقة الطالب · قُبلت · رفضها الطالب · أُلغيت · انتهت | plain text | `components/MembershipRequests.tsx:13` |
| Notification | أُرسل · مجدول · أُلغي · فشل الإرسال | emerald / amber / slate / rose | `lib/notifications.ts:214-219` |

**Against the mobile app's six** (نشط · قيد المراجعة · بانتظار الدفع · إيصال مرفوض · يبدأ قريباً · منتهٍ): the dashboard has «نشط» and «بانتظار الدفع» as written; «قيد المراجعة» appears as «قيد مراجعة الإيصال» and «إيصال قيد المراجعة»; «إيصال مرفوض» appears in Reports but as «مرفوض» in Students; «يبدأ قريباً» does not exist (the dashboard says «الفترة القادمة», «قادم (مدفوع مقدماً)», «دفع مقدم»); «منتهٍ» is spelled «منتهي». The same inactive line is grey on one page and red on another.

There is no shared badge component: the three `.pill-*` CSS classes (`index.css:42-67`) are used once each; every other chip is an ad-hoc class string.

### 6.6 Feedback

- **Toasts** (`lib/toasts.ts`, `components/Toasts.tsx`): top-left, 9–30 s, at most 4, three tones. 44 `notifyError` calls, 10 `notifyDone`. Many successful writes give no confirmation at all (toggling a line, saving a payment method, approving a receipt, saving vote hours) — the screen just changes.
- **Inline alerts**: red boxes (`role="alert"`), each page with its own classes.
- **Confirmations — native browser dialogs: 15 `confirm()` and 1 `prompt()`**, no `alert()`. Company area: `pages/LinesPage.tsx:166`, `:175`; `pages/StudentsPage.tsx:278`, `:295` (prompt), `:310`; `pages/SupervisorsPage.tsx:120`, `:193`; `pages/PaymentMethodsPage.tsx:118`; `pages/ReportsPage.tsx:95`; `components/PasswordResetRequests.tsx:64`, `:74`; `components/MembershipRequests.tsx:33`. Platform: `pages/AllCompaniesPage.tsx:40`, `pages/AllStudentsPage.tsx:67`, `pages/CompanyAdminsPage.tsx:66`, `pages/UniversitiesPage.tsx:112`.
- A proper `ConfirmDialog` component exists but is used only by notifications (`components/notifications/parts.tsx:32-48`).
- Live arrivals: a toast with «عرض الآن» for a new receipt, reset request or student (`lib/sync.ts:86-90`, `components/Toasts.tsx:32`).

---

## 7. States

### 7.1 Loading

Skeletons are the rule (`components/Skeleton.tsx`): shell, page, table, rows, cards, form. The one spinner is the login button (`pages/LoginPage.tsx:189`). Text-only loading remains in the weekly chart «جاري تحميل بيانات الركاب...» (`components/WeeklyRidersChart.tsx:41`), top lines (`components/TopLinesPanel.tsx:36`) and the receipt preview (`components/PendingReceiptsTable.tsx:378`). Background refresh is announced only on Students (`pages/StudentsPage.tsx:504`), History and the platform students page.

### 7.2 Per page

| Page | Loading | Empty | Error | Retry |
|---|---|---|---|---|
| Overview | skeleton cards; text in chart and list | chart «لا توجد بيانات متاحة لهذه الفترة.» (`WeeklyRidersChart.tsx:49`); lines «لا توجد اشتراكات نشطة بعد.» (`TopLinesPanel.tsx:38`). No "new company" state. | «تعذر تحميل الأرقام: {raw}» (`pages/OverviewPage.tsx:25`) | yes |
| Receipts | `SkeletonTable` | «لا توجد إيصالات معلقة حالياً» + a second line (`PendingReceiptsTable.tsx:161-162`); no-match text (`:165`) | «تعذر تحميل الإيصالات: {raw}» (`pages/ReceiptsPage.tsx:18`) | yes |
| Students | `SkeletonTable` | two texts (`pages/StudentsPage.tsx:513`) | «تعذر تحميل الطلاب: {raw}» (`:511`) | **no** |
| Reset requests | none (card absent until loaded) | card hidden (`PasswordResetRequests.tsx:87`) | «تعذر تحميل الطلبات: {raw}» (`:104`) | refresh icon |
| Invitations / corrections | none | hidden (`MembershipRequests.tsx:47`) | **not shown** | no |
| Lines | `SkeletonCards` | text with next step (`pages/LinesPage.tsx:211`) | «تعذر تحميل الخطوط: {raw}» (`:202`) | yes |
| Supervisors | `SkeletonRows` | «لا يوجد مشرفون مسجلون حالياً.» (`pages/SupervisorsPage.tsx:266`) | banner (`:215`) | yes |
| Notifications | `SkeletonRows`; skeleton in audience card | three texts (`History.tsx:194-195`) | banner (`:184`) | yes |
| Reports | `SkeletonTable`; tiles show «—» | «لا توجد اشتراكات مطابقة.» (`pages/ReportsPage.tsx:185`) | banner (`:172`) | **no** |
| Payment methods | `SkeletonRows` | dashed box with next step (`pages/PaymentMethodsPage.tsx:147`) | raw text (`:143`) | **no** |
| Wallet card | form skeleton + card skeleton | n/a (default design) | banner (`pages/WalletCardDesignPage.tsx:317`) | yes |
| Team | `SkeletonTable` | text (`pages/TeamPage.tsx:87`) | banner (`:83`) | **no** |
| Settings | 3 `SkeletonForm` | «لا توجد خطوط بعد.» in the preview (`pages/SubscriptionSettingsPage.tsx:348`) | «تعذر التحميل: {raw}» (`:224`) | **no** |
| Vote card | `SkeletonForm` | n/a | **none**: a failed load leaves the skeleton for ever (`components/VoteSettingsCard.tsx:114`) | no |

Empty states are one grey sentence; none has an action button.

### 7.3 Offline and permission

- **Offline**: no handling at all — 0 occurrences of `navigator.onLine` / `offline` in `src/`. The query client retries once and refetches on reconnect (`lib/query.ts:35-37`); the user sees each page's own raw error.
- **Permission denied**: handled only at the workspace door (wrong company → redirect, `areas/Workspace.tsx:47`; suspended company → notice, `:58-64`). Inside a page, a row-level-security refusal arrives as an empty list or as the server's message.
- **Session expired**: a message asking to refresh and sign in again, only for edge-function calls (`lib/edgeFunctions.ts:13`).

### 7.4 Raw backend text shown to the user

`.message` is read in 79 places in `src/`. The pattern «تعذر …: {error.message}» puts the PostgREST / Postgres / network text after an Arabic prefix. Examples: `areas/Workspace.tsx:52`, `pages/OverviewPage.tsx:25`, `pages/LinesPage.tsx:170`, `:179`, `:202`, `:504`, `pages/StudentsPage.tsx:268`, `:282`, `:330`, `pages/PaymentMethodsPage.tsx:87`, `pages/ReportsPage.tsx:286`, `pages/WalletCardDesignPage.tsx:283`. The design is deliberate for server functions that raise Arabic messages (`lib/rpc.ts:19-20`), but the same path carries English network and constraint errors ("Failed to fetch", "duplicate key value violates unique constraint …").

Two messages written in the dashboard itself expose engineering detail:
- `lib/edgeFunctions.ts:29` — «تعذر الاتصال بوظيفة الخادم "{name}". تأكد من نشرها على Supabase (supabase functions deploy {name} --no-verify-jwt)…» — a CLI command shown to a company admin whenever the request fails to connect.
- `lib/edgeFunctions.ts:25`, `:33` — «(HTTP 500)», «خطأ مؤقت في خادم Supabase».

Login maps errors to five fixed Arabic sentences and never shows raw text (`pages/LoginPage.tsx:62-85`).

---

## 8. Language and direction

- **Document**: `<html lang="ar" dir="rtl">` (`admin_web/index.html:2`). `dir="rtl"` is repeated on 15 elements in 14 files (e.g. `components/Shell.tsx:20`, every dialog). `dir="ltr"` is set 41 times on phones, codes, emails, dates and HEX inputs.
- **No language switch and no string catalogue**: every label is an Arabic literal in the component.
- **Physical vs logical CSS** (class occurrences in `*.tsx`): physical — `ml-`/`mr-` 24, `pl-`/`pr-` 14, `left-`/`right-` 18, `text-left`/`text-right` 30, `border-l`/`border-r` 3 → **89**. Logical (`ms-`, `me-`, `ps-`, `pe-`, `start-`, `end-`, `text-start`, `text-end`) → **0**. Inline styles also use `borderLeft` (`components/Sidebar.tsx:32`). The layout is correct only because it is always RTL: `text-left` is used to mean "end" (`pages/StudentsPage.tsx:524`), `mr-3` to mean "start gap" (`pages/OverviewPage.tsx:26`).
- **Numerals are mixed.** `toLocaleString('ar-EG')` (Arabic-Indic digits ٠-٩) is used 43 times, e.g. stat cards and money (`components/StatsRow.tsx:19-20`). Raw JS numbers (Western digits) are rendered beside them: subscriber counts (`components/TopLinesPanel.tsx:57`), «N إيصالات قيد الانتظار» and «N من 5» (`components/PendingReceiptsTable.tsx:139`, `:248`), line prices (`pages/LinesPage.tsx:252-253`), report counts (`pages/ReportsPage.tsx:124-126`), notification counts (`components/notifications/History.tsx:74`), section numbers written as literal «١. ٢. ٣.» (`pages/LinesPage.tsx:536`).
- **Two functions named `clockLabel` with different digits**: `lib/time.ts:13-18` gives «7:30 ص»; `lib/overview.ts:109-114` gives «٧:٣٠ ص». The vote card uses the second (`components/VoteSettingsCard.tsx:7`), the lines page the first (`pages/LinesPage.tsx:10`).
- **Time format is mixed**: 12-hour with ص/م on lines and vote settings; 24-hour `HH:MM` in the students table and the add-student selects (`pages/StudentsPage.tsx:429`, `:566`) and in the receipts table (`components/PendingReceiptsTable.tsx:228`).
- **Dates are mixed**: `toLocaleDateString('ar-EG')` (10 uses); Cairo-zoned long form in notifications (`lib/time.ts:73-81`); raw ISO `YYYY-MM-DD → YYYY-MM-DD` in receipts and settings (`components/PendingReceiptsTable.tsx:239`, `pages/SubscriptionSettingsPage.tsx:290`); the range arrow is «→» there and «←» in reports (`pages/ReportsPage.tsx:209`). Most `toLocale…` calls do not pin the Cairo time zone; only `lib/time.ts` does.
- **Money**: always «ج.م» after the number; digits vary as above.
- **English shown to users**: «Super Admin» (`components/Topbar.tsx:44`); «InstaPay», «Vodafone Cash» as type labels while the page text says «فودافون كاش» (`pages/PaymentMethodsPage.tsx:23-24` vs `:133`); «IBAN» (`:197`); «HEX» (`pages/WalletCardDesignPage.tsx:61`); «Apple Wallet / Google Wallet»; «(Push)» (`components/notifications/NotificationDetails.tsx:54`); «(Africa/Cairo)» (`components/notifications/NotificationForm.tsx:87`); «PDF» (`pages/SubscriptionSettingsPage.tsx:375`); «RESET ALL DATA» / «RESET FINANCIAL DATA» to be typed (`pages/ReportsPage.tsx:273`); «HTTP», «Supabase» in errors (`lib/edgeFunctions.ts:25-33`); placeholder `admin@example.com`.
- **Register is mixed**: formal throughout, with one colloquial sentence — «لو البريد مسجل، هيوصلك رابط استعادة» (`pages/LoginPage.tsx:37`).

### 8.1 One thing, several names

| Thing | Names used |
|---|---|
| Receipts review | فحص الإيصالات (`lib/nav.ts:40`) · فحص واعتماد الإيصالات (`pages/ReceiptsPage.tsx:16`) · طابور فحص الإيصالات المعلقة (`PendingReceiptsTable.tsx:132`) · إيصالات بانتظار المراجعة (`pages/OverviewPage.tsx:35`) · إيصالات قيد الانتظار (`PendingReceiptsTable.tsx:139`) |
| Approve | قبول (button, `:268`) · اعتماد (toast `:94`, page title) |
| Inactive | معطّل · معطل · متوقف · موقوف · معطّلة · موقوفة (6.5) |
| Line | الخطوط والمحطات · خطوط السير · خط السير · الخط |
| Riders / confirming | نازلين اليوم (مؤكدين) · مؤكدون لرحلة · تأكيدات الركوب · راكب · التصويت · تأكيد الرحلة (`lib/overview.ts:82-87`, `WeeklyRidersChart.tsx:29`, `VoteSettingsCard.tsx:160`, `:172`) |
| Term subscription | فصلي (ترم) (`PendingReceiptsTable.tsx:10`) · فصل دراسي (`pages/StudentsPage.tsx:444`) · الفصل الأول/الثاني (`lib/saleOptions.ts:7`) |
| Both terms | الفصلان معاً; internal names yearly / annual / both all surface in filters (`pages/ReportsPage.tsx:30`) |
| Daily | يومي · يومي (كاش) · سعر اليومي كاش · الاشتراك اليومي (كاش) |
| Paid ahead | دفع مقدم · مقدماً · مسبق · الاشتراك المسبق · قادم (مدفوع مقدماً) |
| Current | الحالي (`pages/StudentsPage.tsx:36`) · ساري (`pages/ReportsPage.tsx:32`) · السارية (`pages/OverviewPage.tsx:33`) |
| The system | المنظومة (`pages/StudentsPage.tsx:346`, `:357`) · النظام · المنصة · قاعدة البيانات (`WeeklyRidersChart.tsx:29`, `:90`) |
| The admin | مدير الشركة · المسؤول (`pages/LoginPage.tsx:128`) · الإدارة · فريق الإدارة |
| University | الجامعة · الجامعة / نقطة الوصول (`pages/StudentsPage.tsx:388`) · الوجهة (الجامعات) (`pages/LinesPage.tsx:239`) |

Page titles also differ from their nav labels: nav «الطلاب» → title «إدارة الطلاب والمشتركين»; «الخطوط والمحطات» → «إدارة خطوط السير»; «المشرفون» → «إدارة المشرفين»; «التقارير المالية» → «التقارير المالية والاشتراكات».

---

## 9. Accessibility basics

- **Labels**: no `htmlFor` anywhere (0 occurrences). Inputs wrapped in their `<label>` are labelled (Lines editor, Settings receipt fields, Payment dialog, Wallet, Notifications). Inputs whose `<label>` is a sibling are **not** programmatically labelled: the add-student form (`pages/StudentsPage.tsx:362-369`, `:375-383`, `:388-389`, `:466-467`), the add-supervisor form (`pages/SupervisorsPage.tsx:225-241`), login (`pages/LoginPage.tsx:127-138`). Unlabelled: every station-name input (placeholder only, `pages/LinesPage.tsx:616`), the term table's inputs (`pages/SubscriptionSettingsPage.tsx:248-262`), the reject-reason textarea (`PendingReceiptsTable.tsx:313`), the reset note (`pages/ReportsPage.tsx:303`), search boxes (placeholder only). `aria-label` is used 40 times in all.
- **Focus styles**: inputs replace the outline with a border colour — `focus:outline-none focus:border-blue-500` (e.g. `pages/LinesPage.tsx:523`). Buttons and links have no focus style of their own and `focus-visible` is used nowhere; they fall back to the browser default.
- **Dialogs**: `role="dialog" aria-modal="true"` only on the notifications `Dialog` (`components/notifications/parts.tsx:11`) and the platform's create-company wizard. The line editor, payment dialog, report reset, reset-password dialog, reject-reason and receipt preview have neither. **No dialog handles Escape and none traps focus** (0 occurrences of `Escape` / `onKeyDown` in `src/`); `autoFocus` appears only in the platform wizard. Backdrop click closes only the receipt preview (`PendingReceiptsTable.tsx:344`) and notification dialogs (`parts.tsx:12`). Focus is not returned to the trigger.
- **Keyboard reach**: row actions are real `<button>`s and reachable. Not reachable or not operable: the "show all lines" footer (`TopLinesPanel.tsx:70`), the chart values (hover only), the login show-password button (`tabIndex={-1}`, `pages/LoginPage.tsx:159`). Photo upload is a `<label>` around a hidden file input (`pages/SupervisorsPage.tsx:286-300`).
- **Icon-only buttons with no accessible name beyond `title`**: student row icons (`pages/StudentsPage.tsx:588-617`), station arrows and delete (`pages/LinesPage.tsx:619-621`), stop-clear X (`:702`), payment-method icons ×5 (`pages/PaymentMethodsPage.tsx:160-164`), reset-queue refresh/copy/close (`PasswordResetRequests.tsx:97`, `:117-118`), supervisor pencil and delete (`pages/SupervisorsPage.tsx:342`, `:358`). **No name at all**: the Topbar bell (`components/Topbar.tsx:34`), the login eye (`pages/LoginPage.tsx:155-162`).
- **Status by colour alone**: the report's three unpaid states share one rose chip and differ only by text; on/off line cards differ by `opacity-75` (`pages/LinesPage.tsx:222`).
- **Live regions**: toasts `aria-live="polite"` with `role="alert"` for errors (`components/Toasts.tsx:18`, `:23`); skeletons carry `aria-busy` (`components/Skeleton.tsx:29`).

### 9.1 Contrast (WCAG ratio, computed; 4.5 is the AA line for body text, 3.0 for large text and UI parts)

| Pair | Ratio | Used for |
|---|---|---|
| `#1F2937` on white / on `#F3FAFD` | 14.68 / 13.91 | main text |
| `#5B6B7A` on white / on `#F3FAFD` | 5.48 / 5.20 | secondary text |
| slate-500 `#64748B` on white | 4.76 | secondary text on plain pages |
| slate-400 `#94A3B8` on white | **2.56** | field hints at 11 px, bottom-bar labels at 9.5 px, dates, placeholders |
| slate-300 `#CBD5E1` on white | **1.48** | «لا يقف», toast close, stop-clear X |
| `#3E8FBF` on white | **3.57** | links, amounts, active nav text |
| `#3E8FBF` on `#D6EEF9` | **2.97** | active sidebar item |
| `.pill-active` `#2E9E5B` on `#DDF3E6` | **2.93** | status pill at 11.5 px |
| `.pill-pending` `#B8860B` on `#FFF1D6` | **2.91** | status pill |
| `.pill-rejected` `#DC2626` on `#FEE2E2` | **3.95** | status pill |
| white on `#2E9E5B` | **3.41** | «قبول» button, 12 px text |
| white on `#DC2626` | 4.83 | «رفض» button |
| white on blue-600 `#2563EB` | 5.17 | primary buttons |
| emerald-700 on emerald-50 | 5.21 | chips |
| amber-700 on amber-50 | 4.84 | chips |
| indigo-700 on indigo-50 | 7.07 | chips |
| slate-500 on slate-100 | **4.34** | inactive chips |
| rose-400 `#FB7185` on white | **2.69** | delete icons, bottom-bar «خروج» |
| amber-500 `#F59E0B` on white; white on amber-500 | **2.15** | key icon; reset-password button |
| white on amber-600 | **3.19** | «إصدار رمز» |
| white on rose-500 | **3.67** | nav badge number at 10 px |
| white on `#7EC8E3` / `#3E8FBF` | **1.87 / 3.57** | the two ends of the login button gradient |

---

## 10. Super admin (platform area)

Read by a helper agent; line numbers are theirs.

### 10.1 Inventory

| Page | Lines | Job(s) | Actions | Data |
|---|---|---|---|---|
| **PlatformOverviewPage** | 117 | Totals + company comparison; **also** the platform-wide password-reset queue (`:55`) | retry (`:26`); «دخول» into a company (`:107`) | 4 tiles (`:33-36`): شركات النقل, الطلاب على المنصة, riders, إجمالي الإيرادات المسجلة; chart; top lines; table «مقارنة الشركات»: الشركة · الطلاب · اشتراكات سارية · نازلين اليوم · إيصالات معلقة · الخطوط · الإيرادات (`:73-80`), `min-w-[760px]` |
| **AllCompaniesPage** | 279 | Company cards + status changes; **also** a 3-step create wizard (`:150-279`) | filter pills (`:65-70`); «شركة جديدة» (`:71`); إيقاف / أرشفة / تفعيل via `companies.update` with `window.confirm` (`:40-43`); «دخول» (`:130`) | cards with six mini-tiles (`:100-105`): الطلاب, اشتراكات سارية, نازلين اليوم, الخطوط, المشرفون, إيصالات معلقة; revenue; status chip |
| **AllStudentsPage** | 182 | Correction-request approval queue (`:88-113`) **and** a read-only directory | رفض / اعتماد → `decide_student_correction` with `window.confirm` (`:67-69`); search, company and membership filters → `platform_students` (`:50`); paging 25 | table الطالب · الهاتف · الجامعة · الشركات · اشتراكات سارية · تاريخ التسجيل (`:144`), `min-w-[720px]`. The correction rows do not show the student's name (`:98-103`) |
| **PlatformNotificationsPage** + PlatformComposer | 87 + 187 | Push health tiles, composer, all-company history | company filter; audience «كل الشركات المفعّلة» / «شركات محددة»; send / schedule → `platform_compose_notification`; delete / cancel | tiles (`:25-28`): أجهزة مسجّلة, في الانتظار الآن, قبِلها مزوّد الإشعارات, فشلت |
| **CompanyAdminsPage** | 144 | Create and list company-admin accounts | create → `admin-create-company-admin` (`:49`); delete → `admin-delete-company-admin` with `confirm` (`:66-71`) | table المدير · البريد · الشركة المخصصة · تاريخ الإنشاء (`:123`) |
| **UniversitiesPage** | 287 | Add university, universities table, colleges — three jobs | insert university (`:91`); toggle active by pill (`:106`, no confirm) or by X icon (`:112`, confirm) — two controls for one action; add college (`:70`); toggle college (`:81`) | table الجامعة / الوجهة · المدينة / المقر · الطلاب المسجلين · الحالة · إجراءات (`:204-208`); colleges as a flat card grid |
| **PlatformDefaultsPage** (= `SubscriptionSettingsPage` with no company) | 439 | Default term dates, platform switches for two-terms and daily, platform vote hours | save terms one by one (`pages/SubscriptionSettingsPage.tsx:195-201`); two toggles (`:320`, `:427`); vote card | same cards as the company page minus advance, preview and receipt data |
| **AppVersionsPage** | 126 | Minimum / latest version, "what's new", store link per store | «حفظ» per card → `save_app_version` (`:66`), no confirmation even when raising the forced minimum | two cards: أندرويد (Google Play), آيفون (App Store) |

Notable gaps in the platform area: a company admin can only be created or hard-deleted — no suspend, edit, resend invite or password reset (`pages/CompanyAdminsPage.tsx:66`); a university's name and city cannot be edited and the city defaults to a hard-coded «المنصورة» (`pages/UniversitiesPage.tsx:93`, `:223`); the universities table has no scroll wrapper (5.3); after creating a company there is no confirmation of whether an invite was sent, and no next step (`pages/AllCompaniesPage.tsx:189-190`).

### 10.2 Shared with the company area

- **Shell**: `Shell`, `Sidebar`/`MobileNav`, `Toasts`, `Topbar` (`areas/PlatformArea.tsx:16`).
- **Whole pages**: the settings page (`lib/routes.ts:32`, `:46`); every workspace page, which the super admin opens through «دخول» with the workspace bar on top.
- **Components**: `StatsRow`, `WeeklyRidersChart`, `TopLinesPanel` (overview); `PasswordResetRequests` with `companyId={null}`; `History`, `NotificationForm`, `PhonePreview`, `AudiencePreviewCard`, `ConfirmDialog`; `VoteSettingsCard`; all skeletons.
- **Super-admin-only controls inside company pages**: reset password and delete account on a student row (`pages/StudentsPage.tsx:587`, `:610`), add a team admin (`pages/TeamPage.tsx:61`).
- **Lookups**: `useUniversities`, `usePlatformCompanies` (`lib/reference.ts:30`, `:125`).

---

## 11. What the data layer offers

### 11.1 Fetched but not shown (company area)

`company_overview` returns these and the company pages ignore them (`lib/overview.ts:6-25`):

| Field | Shown? |
|---|---|
| `lines`, `active_lines` | No (only on the platform's cards) |
| `supervisors` | No |
| `admins` | No |
| `vote_closes_at` | Only inside the riders hint in one of its two states (`lib/overview.ts:103`) |
| `riders_week` values | Only as bar heights; numbers on hover |
| `top_lines[].subscribers` | Yes, top 5 only |
| `baseline` | Only as a hint under revenue |

Also fetched and under-used: `attempt_number` (shown as «N من 5» with no emphasis when it is the last attempt, `PendingReceiptsTable.tsx:248`); wallet `pending_cards` (shown only on the wallet page); `sale_preview` reasons (only at the bottom of settings); supervisor–line assignments (loaded on Lines, shown as a text suffix `pages/LinesPage.tsx:255`); push `devices` in the audience card.

### 11.2 Shown but of little use to a company owner

- Their own company name as a chip on every receipt row (`PendingReceiptsTable.tsx:224`) and a «الشركة / الخط» column in reports (`pages/ReportsPage.tsx:196`), and under each top line (`TopLinesPanel.tsx:51`).
- Engineering wording: «عدد تأكيدات الركوب المسجلة يوميًا في قاعدة البيانات», «بيانات قاعدة البيانات» (`WeeklyRidersChart.tsx:29`, `:90`); «نظام محمي ومشفر بالكامل» (`components/Sidebar.tsx:70`); «محدّثة لحظياً».
- Push delivery internals in every history row and in details: registered / waiting / accepted by provider / failed / not sent (`History.tsx:76-79`, `NotificationDetails.tsx:54-63`).
- Wallet: Apple-only and Google-only colour fields, HEX typing, per-store card counts (`pages/WalletCardDesignPage.tsx:366-368`, `:399-402`).
- Reports: "reset" machinery (two buttons, a log, a "full history" checkbox) on the page whose job is reading (`pages/ReportsPage.tsx:111-118`, `:164-167`, `:227-239`).
- Settings: the platform's own values and the "follows the platform" mechanics (`VoteSettingsCard.tsx:255-260`); "disabled at platform level" (`pages/SubscriptionSettingsPage.tsx:309`).
- A dead bell button and the role label on every Topbar page (`components/Topbar.tsx:34-45`).

### 11.3 "What needs my attention today" — does a query exist?

| Item | Exists in `admin_web/src/lib`? | Notes |
|---|---|---|
| Pending receipts (count) | **Yes** — `useCompanyOverview().pending_receipts` (`lib/overview.ts:47`) | Already drives the nav badge |
| Pending receipts (list) | **Yes** — `usePendingReceipts` / `get_pending_receipts_page` (`lib/pendingReceipts.ts:130`, `:190`) | |
| Receipts on their last attempt | Partly — `attemptNumber` is in each loaded row (`lib/pendingReceipts.ts:42`); no count | client-side over loaded rows only |
| Password-reset requests (count) | **Yes** — `countResetRequests` in `areas/Workspace.tsx:98-103` (not in `lib/`, not exported) | would need moving to `lib/` |
| Password-reset requests (list) | **Yes** — `admin_list_password_reset_requests`, called inside the component (`components/PasswordResetRequests.tsx:46-47`); no hook in `lib/` | |
| Tomorrow's riders, company total | **Yes** — `riders_next`, `next_ride_date`, `vote_closes_at` (`lib/overview.ts:14-18`) | |
| Tomorrow's riders per line / trip / station | **No query in `admin_web`.** The database has `get_lines_rider_counts(p_line_ids, p_ride_date)` and `get_line_rider_counts_with_returns(p_line_id, p_ride_date)`, which accept a company admin for their own lines (`supabase/migrations/20261103000001_data_access.sql:181`; `supabase/migrations/20261102000001_performance_2.sql:407-420`), and `get_supervisor_trip_manifest` (same file `:300-319`). | Needs a new `lib` hook only; I read the permission check, did not call the functions |
| Lines without a supervisor | **Derivable, no new request** — `useLines` + `useSupervisorLines` (`lib/reference.ts:65`, `:114`); the Lines page already computes it (`pages/LinesPage.tsx:137-141`, `:220`) | no count helper |
| Supervisors without lines / inactive | **Derivable** — `useSupervisors` + `useSupervisorLines` (`lib/reference.ts:108-116`) | |
| Lines with a university but no departure trip | **Derivable** from `useLines` (the editor computes it, `pages/LinesPage.tsx:729`) | |
| Lines with no enabled price / inactive lines | **Derivable** from `useLines` (`line_period_prices`, `is_active`) | |
| No active payment method | **Yes, but page-local** — the query lives in `pages/PaymentMethodsPage.tsx:48-50`; no shared hook | move to `lib/` |
| Nothing on sale / why an option is hidden | **Yes** — `get_subscription_settings` → `sale_preview`, `purchasable` (`pages/SubscriptionSettingsPage.tsx:80-81`, `:34`, `:39`); page-local types | |
| Invitations waiting on students | **Yes, page-local** (`components/MembershipRequests.tsx:25-27`) | |
| Corrections waiting on the platform | **Yes, page-local** (`:28-30`) | |
| Wallet cards not yet updated | **Yes, page-local** — `get_wallet_card_settings.pending_cards` (`pages/WalletCardDesignPage.tsx:192`, `:28`) | |
| Scheduled / failed notifications | **Yes** — `useNotificationHistory(companyId, 'scheduled' \| 'failed')` (`lib/notificationsData.ts:51`) | |
| Subscriptions expiring soon | **No** — the students page has `end_date` per row (`lib/students.ts:7`) but no filter or count; the report filters by phase only | new query |
| Students awaiting payment (`pending_payment`) | Partly — report `totals.unpaid` (`pages/ReportsPage.tsx:22`), which mixes all unpaid states | new or extended |
| New students today | **No** (only the live toast, `lib/sync.ts:89`) | new query |
| First-run / setup completeness | **No single query**; each part is derivable from the lookups above | a composed hook |

One round trip for all of this does not exist; `company_overview` is the only aggregate and it is already always mounted for the badges (`areas/Workspace.tsx:112`), so extending it is the cheap route — that is a database change, outside this audit.

---

## 12. Tests and constraints a redesign must respect

### 12.1 Tests (run: 5 files, 95 tests, all pass, 8 s)

`vitest`, environment `node`, `include: ['src/**/*.test.ts']` (`admin_web/vitest.config.ts:5-8`). **Library logic only — there is no component test, no jsdom, no browser test.** A redesign of the TSX is therefore unguarded by tests; equally, it cannot break them unless it changes `lib/`.

| File | Tests | Covers |
|---|---|---|
| `lib/cache.test.ts` | 19 | cache-key scoping, what is persisted, storage cap, signed-link reuse, the double-submit guard, the missing-function fallback |
| `lib/sync.test.ts` | 17 | which lists a live event refreshes, own-change suppression, flush timing |
| `lib/receipts.test.ts` | 22 | receipt row mapping, optimistic queue edits, order of overlapping decisions, student cache edits, report paging |
| `lib/notifications.test.ts` | 22 | audience payloads, validation, idempotency key, status labels, Cairo time |
| `lib/redesign.test.ts` | 15 | app-version rules, bus capacity parsing, `studyLine`, specialisation on a receipt |

`npx tsc --noEmit` exits 0.

### 12.2 Bundle budgets (`admin_web/scripts/check-bundle.mjs:22-25`)

| Screen | Budget raw / gzip | Built now (run) | Headroom |
|---|---|---|---|
| Sign-in page (`LoginPage`) | 540,000 / 155,700 B | 491,340 / 141,691 B, 8 files | 48.7 kB raw, 14.0 kB gzip |
| Company admin first page (`Workspace` + `OverviewPage`) | 590,000 / 174,800 B | 538,478 / 159,982 B, 18 files | 51.5 kB raw, 14.8 kB gzip |

- The script resolves chunks **by name**: it expects exactly one chunk called `LoginPage`, one `Workspace`, one `OverviewPage` (`:31-35`). Renaming or merging those modules fails the check.
- It counts JS only; CSS (41.9 kB, 7.9 kB gzip) and fonts are outside the budget.
- About 438 kB of each figure is the three vendor chunks (`admin_web/PERF_RESULTS.md:17`). A component library, a chart library or an animation library imported statically by the shell or the overview would land inside the 51 kB.
- Chunking rules: `react`, `supabase`, `query`, `icons`, and `kit` (six tiny helpers) (`admin_web/vite.config.ts:19-28`). All lucide icons share one chunk (28 kB now).
- Every page is a lazy chunk with `preload()` on hover/focus/touch of its nav entry (`lib/routes.ts:12-17`, `components/Sidebar.tsx:52-54`). A new navigation component must keep calling `preload`.
- What the first screen imports matters: today Overview pulls in the whole `PendingReceiptsTable` (16.5 kB).

### 12.3 The persisted query cache (`lib/query.ts`)

- One `QueryClient`; `staleTime` 30 s, `gcTime` 24 h, 1 retry (`:30-40`). Lookups 5 min (`:14`).
- Persisted to **sessionStorage** per tab under `basak.admin.cache`, capped at 1.5 M characters, busted by `adminId:CACHE_SHAPE` (`:69`, `:81`, `:100-107`). **Changing the shape stored under an existing key requires bumping `CACHE_SHAPE`** (`:105-106`).
- Not persisted: any key containing `receipts`, `signed`, `reports`, `audience`, `preview`, or an object part with a truthy value (search / filter / page variants) (`:68-78`). A new list's default view must use a key with no truthy object part or it will not be kept; a new filter must be an object part or it will be.
- Keys are scoped `['c', companyId, …]`, `['platform', …]`, `['shared', …]` (`:50-54`). Live events invalidate by the **third segment's name** (`lib/sync.ts:16-33`): a new query that should follow live changes must use one of those names (`overview`, `students`, `lines`, `lineNames`, `supervisors`, `supervisorLines`, `paymentMethods`, `settings`, `switches`, `periods`, `walletCard`, `resetRequests`, `invites`, `corrections`, `notifications`, `vote`, `company`, `receipts`, `reports`) or be added to the map.
- `overview` is re-read on ride events only while the path is exactly `/c/{id}` (`lib/sync.ts:145`). **Moving the overview to another route, or showing rider numbers on another page, silently changes when those numbers refresh.**

### 12.4 Fetch rules recorded in `PERF_RESULTS.md`

- Shell on every workspace page: `company_overview` + one HEAD count of reset requests — nothing more (`PERF_RESULTS.md:37`). A new always-visible "attention" strip adds to this on every page.
- Receipts: one request for the queue + one signing request; decisions are one request with no re-read; the list is 50 at a time and is topped up when fewer than 10 remain (`PERF_RESULTS.md:38-40`; `lib/pendingReceipts.ts:179-180`).
- Own writes must not be re-read: pages put the server's answer into the cache and call `rememberApplied` so the change's own announcement is ignored (`lib/recentChanges.ts`; pattern at `pages/PaymentMethodsPage.tsx:56-59`). New write paths must follow the pattern or every save costs extra reads.
- Every write goes through `useGuard` so a double tap sends once (`lib/guard.ts:9-21`).
- Students: one request per settled search; the total is counted 700 ms after typing stops and never on a page change (`PERF_RESULTS.md:42-43`; `pages/StudentsPage.tsx:107-119`). The add-student option lists load only when the form is first touched (`pages/StudentsPage.tsx:130-132`) — moving the form into a dialog keeps this; rendering it eagerly elsewhere would not.
- Reports: 100 rows per request, totals always cover all rows (`PERF_RESULTS.md:41`).
- Signed image links are reused for 50 minutes (`lib/signedUrls.ts:15`, `lib/query.ts:16`); thumbnails and the preview must use the same URL to avoid a second download (`components/PendingReceiptsTable.tsx:77`).
- Deploy order: three server functions may be missing and fall back to `lib/legacy.ts` (`lib/rpc.ts:23-36`; `PERF_RESULTS.md:53-61`). New UI must tolerate `specialisation`, `rows_total`, `reviewed_at`, `bus_capacity` being absent (`lib/pendingReceipts.ts:88`, `lib/reports.ts:17`, `pages/LinesPage.tsx:365-382`).
- `PERF_RESULTS.md:71-79` states that nothing was measured in a browser.

### 12.5 Other constraints

- Hosting is a static SPA with a catch-all rewrite and `X-Frame-Options: DENY` (`admin_web/vercel.json`). Routes are `/platform/*` and `/c/:companyId/*` (`App.tsx:122-125`); toasts and the workspace switcher build URLs from page slugs (`lib/sync.ts:157`, `components/WorkspaceBar.tsx:22`, `:40`), and the platform students page links to `/c/{id}/students`. Renaming a slug needs those updated.
- Fonts are loaded from Google Fonts at runtime (`admin_web/index.html:17-21`); switching to Readex Pro is an HTML + Tailwind config change, not a bundle one.
- `dist` and `node_modules` are git-ignored (`admin_web/.gitignore:2`, `:6`).

---

## Could not be determined from the code

- How anything actually renders at 360 px (nothing was run in a browser).
- How often each task really happens — the ordering in section 3 is my inference from badges, live toasts and the data model.
- What the server returns in its error messages (Arabic or English) for each RPC; only the client path was read.
- Whether `get_lines_rider_counts*` return what a "tomorrow by line" card needs; I read their signatures and permission checks only.
- Whether a failed price upsert really creates a duplicate line on a second save (4.1) — read from the code; it depends on how `save_line` treats `id: null` with an existing name.
- Whether a company admin can be invited without a password in the current environment (the UI says it needs SMTP, `pages/AllCompaniesPage.tsx:238`).
- Real data volumes per company (students, lines, receipts per day), which decide list density.
