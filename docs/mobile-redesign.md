# Basak student app — 2026 redesign: "The Route"

Design canvas (126 artboards — 100 student and system, 26 supervisor — Claude Design): https://claude.ai/artifact/NveQBomjGxfsYtg6W5LWdk

Scope: the student experience in `mobile_app/` (Flutter). Supervisor screens are untouched; they keep the current widgets until they get their own pass.

Status: **design only, awaiting approval.** No Flutter work has started. Every artboard has been rendered and inspected; the interactive ones were exercised (period tiles, payment methods, station and university pickers, ride times, photo step, inbox filter, receipt groups).

All names, prices, phone numbers and payment addresses on the canvas are sample content.

---

## 0. What is wrong today (from the code, not from taste)

| # | Problem | Where |
|---|---|---|
| 1 | **No single palette.** Three overlapping ones (`AppColors` navy + teal, `BasakUi` teal on `#EAF5FA`, glass baby blue) plus green for "selected", indigo for "upcoming", amber for notes. 156 distinct hex values, 419 colour literals across 42 files, and 10 files re-declare `_ink` / `_teal` privately. | `core/theme/app_colors.dart`, `core/widgets/basak_ui.dart`, every screen |
| 2 | **Home carries six blocks** and the daily action is the fourth one. The ride vote is a full form laid out inline: time tiles, chips, a checkbox, two buttons, a status box. The hero card's main field is "expected bus arrival", which usually reads "confirm to see the time". | `student_home_screen.dart` |
| 3 | **The purchase flow has four layers of chrome before the first option**: progress card (step x of 5, steps remaining, 5 dots, 5 labels) → "previous step" button → a fixed title → a subtitle → a numbered step title. It runs inside a tab with the nav bar still on screen, and earlier choices leave the screen once made. | `purchase_flow.dart` |
| 4 | **Line cards repeat and overflow.** "إلى {university}" is identical on every card (the catalog is already filtered by the student's university). Station names are joined with " · " and truncated at two lines. Two coloured pills per card. | `purchase_flow.dart` `_lineCard` |
| 5 | **One card shape for every subscription state.** "عرض التفاصيل" expands into payment methods + upload + notes, or into a receipt + two full-width buttons. An approved subscription still looks like the pending one. Notes come *after* the upload control. | `subscription_screen.dart` |
| 6 | **The card screen sizes itself with hand arithmetic** (`fixed = 24 + … + 34`). | `student_qr_screen.dart` |
| 7 | **Notification preferences still exist in the student path.** The gear is one flag away (`widget.preferences`), and the permission sheet promises "تختار ما يصلك … من إعدادات الإشعارات". | `notifications_page.dart`, `push_permission_sheet.dart` |
| 8 | **The floating nav collapses to one icon on scroll, and its labels are 9.5–10.5 px at under 3 : 1 contrast.** After a scroll the card needs two taps; `BackdropFilter` is expensive on low-end Android phones. | `floating_glass_nav_bar.dart` |
| 9 | **Entry is old-fashioned.** A 4-slide carousel with orbiting icons, then one 633-line sign-up form with three numbered sections. | `onboarding_screen.dart`, `signup_screen.dart` |
| 10 | **RTL is assumed, not designed.** 20 physical-direction usages (`TextAlign.right`, `left:`/`right:` insets), 1,057 hard-coded Arabic literals, `supportedLocales` lists `en` with no translations. Numerals are mixed: prices are Western, the vote-window clock converts to Arabic-Indic. | app-wide, `vote_settings.dart` |
| 11 | **Feedback is green and red snackbars**, a third colour system on top of the others. | app-wide |

---

## A. Design strategy

**Direction: "The Route".** Basak's own teal and petrol ink, matured: the same hues the app and its icon use today, on a calmer, lighter ground, with Readex Pro kept. Tone separates surfaces, colour is reserved for meaning, and one motif — a vertical route rail with a ring (boarding stop) and a dot (university) — carries the pass, the station list, the review and the receipt.

**Visual principles**

1. **One ink, one teal.** Ink `#17384A` is text, the pass and the card tab. Teal `#00658D` means "tappable or selected": the primary button, links, selection, progress.
2. **Status colour only for status.** Green, amber and red appear only for a subscription or receipt state, always with a dot/icon and a fixed label.
3. **Tone, not borders.** White cards on `#F0F5F8`, a 1-px shadow at most. Real elevation only for sheets and toasts.
4. **A station or a period is the headline; a route never is.** Long strings like "الزرقا ← المنصورة الجديدة" are replaced by two stacked stops on the rail, each on its own line.
5. **Western digits everywhere.** Prices, times, phones, receipt codes, IBAN.

**UX principles**

1. **One primary action per screen, pinned to the bottom**, inside thumb reach.
2. **Choose in sheets, read on pages.** Every pick (university, station, ride times, alert detail, confirm, help) is a bottom sheet.
3. **Never lose what was chosen.** Completed steps collapse to one line and stay on screen with "تغيير".
4. **Say it once.** The amount appears once per screen. The destination is said once per list. Instructions live in one block.
5. **Cache first.** Offline is a state of the strip, not of the screen. The card always opens.

**What changes structurally**

| Before | After |
|---|---|
| 4 tabs on a floating glass bar that collapses | The same 4 tabs (الرئيسية · اشتراكي · بطاقتي · حسابي) on the same floating pill, made solid and readable; on scroll the labels fold but every tab stays; the card is the one filled tab |
| Bell on home, inbox with search, filters, gear | Bell with unread count on home; a simple inbox page behind it |
| 5-screen wizard + review page inside a tab | One builder screen, a station sheet, a confirm sheet |
| Payment inside an expanding card | A dedicated pay screen: amount → method → details → notes → receipt |
| Ride vote as an inline form | One question on home, times in a sheet, a compact "confirmed" card |
| 4 onboarding slides of icons | 3 onboarding screens built from the real components (first launch only), then a plain entry screen |
| One long sign-up form, college left as "غير محدد" | Four short steps; university **and college** captured at sign-up |

### Decisions revised after rendering the canvas

| First draft | Now | Why |
|---|---|---|
| Navy `#0F2238` + blue `#1E4E8C` | Petrol ink `#17384A` + teal `#00658D` (both already in the app) | Side by side with the icon and today's screens, navy read as a different, colder brand. The teal family is recognisably Basak; what dated the app was the gradient, borders and three overlapping palettes, not the hue. |
| Ink primary button | Teal primary button | Teal is already the app's action colour. Ink stays for identity (the pass, the card tab); teal is for action. |
| 5 slots: home · subscription · [card] · alerts · account | 4 tabs + bell on home | Alerts arrive as push and deep-link to the right screen; the inbox is history, not a destination. Four tabs match what students already know and keep `_selectTab` / `NotificationDestination` routing as is. |
| Card as a full-screen sheet from a raised centre button | Card stays a real tab, drawn as the one filled item | Same one-tap reach, no modal to dismiss, no asymmetric raised button, existing routing and tests unchanged. |
| Offline strip in ink | Offline strip in amber | Ink sat directly on top of the ink pass and merged with it; amber is also what the current banner uses. |

### Entry screens stay plain-spoken

Sign-in, sign-up and password recovery sit on the app's light ground with no decorative header: a dark box with circles was tried there on 2026-10-09 and read as generic, so it was removed. On those screens "not basic" comes from structure — the logo lockup, fields grouped in one card, the route rail as the sign-up progress. This is about the entry screens only: the recap keeps its large shapes and the Home pass keeps the ring behind it.

### One purpose per screen

The same fact is not repeated across tabs. Each screen owns its facts; the others link to it.

| Screen | It is for | It deliberately does not show |
|---|---|---|
| Onboarding (3) | What the app does, once, on first launch | Buttons to sign in before the last page; anything after the first launch |
| Entry | Create account or sign in | The pitch (that is onboarding) |
| Sign-up 1–4 | One kind of data each: identity · studies · photo · password | Explanations of the subscription steps |
| **Home** | Is my pass valid, and am I riding tomorrow | Validity dates, amounts, the receipt, a "show card" button (the card is a tab) |
| **اشتراكي** | Time and money: period, validity, amount, receipt, next period, history | The route rail; line and station are one row |
| **بطاقتي** | What a supervisor reads off the student's phone: photo, name, college, QR, status and validity, line, stop, today's ride | Money, receipts, instructions |
| Subscribe builder | Choosing company, line + station, period | A running total (the selected tile carries the price) |
| Pay | Transferring and attaching the receipt | What happens after review (said once, on the result screen) |
| Result | "We received it" and what happens next | A summary of what was just entered |
| Home, under review | Where the request stands (3-node line) | Amount and method (those are on اشتراكي) |
| Alerts | History of what was sent | Settings, categories |
| Account | Who I am, app settings, help | Company and supervisor (they are on اشتراكي, Home and in Help) |

The sentence "the company reviews your receipt and you will be notified" used to appear in six places; it now appears once, on the result screen.

---

## B. Design system

Canvas boards: **Design system · Tokens**, **Components**, **Pass in every status**.

### Colour

| Token | Value | Use | Today |
|---|---|---|---|
| `ground` | `#F0F5F8` | every screen background | lighter, calmer than `#EAF5FA` |
| `surface` | `#FFFFFF` | cards, sheets, nav | same |
| `sunken` | `#E4ECF1` | inputs, segmented track, quiet buttons, locked rows | new |
| `hairline` | `#DCE6EC` | dividers inside a card | new |
| `ink` | `#17384A` | text, the pass, the card tab, toasts | **unchanged** (`BasakUi.ink`) |
| `ink2` | `#476273` | secondary text (6.4:1 on white) | darker than `muted #718695`, which failed contrast |
| `ink3` | `#58707F` | captions, inactive tabs (5.2:1 on white, 4.7:1 on ground) | new |
| `inkRaised` / `inkRule` | `#214B61` / `#34596D` | chips and rules on the pass | new |
| `onInk2` | `#A9BCC8` | secondary text on ink | new |
| `teal` / `tealTint` | `#00658D` / `#E5F3FA` | primary button, selection, links, progress / selected fill | **unchanged** (`AppColors.teal`, `BasakUi.softTeal`) |
| `sky` / `mint` | `#A8D8F0` / `#5BD4A0` | accent and active dot on ink | `babyBlueLight`, new |
| `success` | `#0A6B4A` on `#E3F4EC` | active, approved | darker for contrast |
| `warning` | `#8A5300` on `#FCF1DC` | under review, deadlines, offline, permission off | close to today's banner |
| `danger` | `#B3261E` on `#FCEBE9` | rejected, destructive | darker for contrast |
| `disabled` | `#9DB0BB` on `sunken` | disabled controls | new |

**Status language** (same six everywhere): نشط · قيد المراجعة · بانتظار الدفع · إيصال مرفوض · يبدأ قريباً · منتهٍ. The *Pass in every status* board draws all six.

### Type — Readex Pro (already bundled)

| Role | Size / line / weight | Example |
|---|---|---|
| Display | 28 / 38 / 600 | page titles |
| Title | 22 / 32 / 600 | sheet titles, questions, the name in the home header |
| Headline | 17 / 26 / 600 | card titles, section heads |
| Body | 15 / 24 / 400 | text |
| Label | 13 / 20 / 500 | field labels, meta |
| Caption | 12 / 18 / 400 | stamps, helper |
| Amount | 34 / 44 / 600 | the one amount on a pay/receipt screen |
| Tab | 11 / 16 / 400–600 | tab bar only |

Rules: titles are one line; body never below 13; the currency unit ("ج.م") is set smaller and in `ink3` and never separated from its number (non-breaking space); phone numbers, codes and addresses are `TextDirection.ltr` but aligned to the start edge; a list of times reads right to left, earliest first; free text that may wrap uses balanced wrapping so no single word is left on a line.

### Space, radius, elevation

- **Spacing:** 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40. Gutter 20. Card padding 18–20. 16 between cards, 28 between sections. Touch target ≥ 44; primary button 54.
- **Radius:** 10 tags · 14 small buttons · 16 buttons/inputs/rows · 20 cards · 28 pass and sheets · full for chips and avatars.
- **Elevation:** 0 sunken (tone) · 1 card (`0 1 2 rgba(23,56,74,.05)`) · 2 floating (`0 16 40 -12 rgba(23,56,74,.28)`) for sheets and toasts only.

### Icons

Lucide, as bundled. One stroke weight (1.75; 2 for the active tab). 22 in the tab bar, 20 in rows, 14–16 inline. No icon bubble per row; a tinted 40-px tile only where the icon *is* the category (inbox, help). Directional icons mirror.

### Components (→ proposed Flutter widget)

| Component | Notes | Replaces |
|---|---|---|
| `BasakButton` (primary teal / quiet / tonal / text / destructive, 54 and 44) | one primary per screen | per-screen `ElevatedButton.styleFrom` |
| `BasakField` | filled, borderless; focus and error = 2-px ring + label colour | `AuthStyles`, `_decoration` helpers |
| `BasakSegmented` | 2–3 views of one list | filter chips in the inbox |
| `BasakChip` / `BasakTag` | single choice (teal when selected) / read-only label | `BasakPill`, `ChoiceChip` |
| `StatusChip(status)` | the six states, one mapping | `_status()` record in `subscription_screen.dart`, inline pills |
| `PassCard` (ink when active, light otherwise) | status, period, `RouteRail`, perforation, footer slot | gradient hero, `_subscriptionCard` |
| `RouteRail` | ring + dot, vertical; dashed when a stop is not chosen yet; list variant for stations | `_stationRow`, route label strings |
| `InfoRows` | label start / value end, optional chevron | `BasakInfoRow`, `_summaryLine`, `_reviewRow`, `_detailRow` |
| `LineCard` | name, stop count, from-price, first/last time, ≤ 1 tag; unavailable variant | `_lineCard` |
| `ChoiceTile` | period tiles, departure tiles | `_optionCard`, time tiles |
| `BuilderRow` (chosen / open / locked) | the subscribe builder | `_progress`, `_stepTitle` |
| `StepLine` | 3 nodes: receipt sent → review → activation; also the upload phases | new |
| `BasakSheet` | grabber, title, body, ≤ 1 primary | ad-hoc `showModalBottomSheet`s |
| `ConnectionStrip` (offline amber / syncing teal / back online green) | floats under the header | `OfflineBanner` |
| `BasakToast` | ink, icon carries tone | green/red `SnackBar`s |
| `InlineError`, `EmptyState` | error stays in its section | `BasakMessageCard`, `_ErrorCard` |
| `BasakTabBar` | floating pill, solid white, 4 slots, card slot filled; compact on scroll | `FloatingGlassNavBar` (restyled in place) |
| `HomeHeader` | avatar + greeting at the start, bell + unread count at the end | `GreetingHeader` (restyled, logic kept) |
| `Bone` / `Skeleton` | **kept**, re-shaped to the new cards | — |

### Variable data — how each card scales

No card is designed around a fixed number of items. The canvas shows the heavier case wherever the count comes from company or line data.

| Data | Range in practice | Rule |
|---|---|---|
| Departure times at the student's stop (ride sheet) | 1 – many | 3-column grid, earliest first from the start edge. 1–2 times still use the grid. Beyond the sheet's max height (about 88% of the screen) the sheet scrolls and "تأكيد الركوب" stays pinned. |
| Return times from the university (ride sheet) | 0 – many | Same grid; "لن أعود بالباص" is always the last, full-width option. With no return trips only that option shows. |
| Pass times per station (station sheet) | 1 – many | Closed row: first time only. Selected row: all times on wrapping lines. |
| Stations on a line | 1 – 20+ | Scrolling rail list inside the sheet; search appears above 6. |
| Lines of a company | 1 – many | Scrolling list of line cards; a card always summarises trips as first departure / last return, whatever the trip count. Unavailable lines sink to the end. |
| Companies for a university | 1 – several | 1: preselected and collapsed. More: a list of rows. |
| Periods on sale | 1 – 4 (first, second, both, summer) | 1: one wide tile, preselected. 2: two columns. 3: one row. 4: 2 × 2. |
| Payment methods of a company | 0 – many | Chips wrap. 0: the details card is replaced by "تواصل مع الشركة لمعرفة بيانات التحويل". |
| Company invitations | 0 – several | One card at a time with "1 من 2" and dots; swipe for the next. |
| Past subscriptions | 0 – many | Latest two, then "عرض كل الاشتراكات السابقة · n". |
| Alerts | 0 – many | Grouped by day, paged with "عرض تنبيهات أقدم". |
| Names (station, line, company, university) | short – long | Wrap to two lines, then ellipsis; never shrink the type. |

---

## C. Screen by screen

### 1. Shell and navigation
- **Splash**: ink, icon, wordmark, a three-stop rail as the only motion.
- **Onboarding** (first launch only, reuses the existing `basak.onboarding.v1.completed` flag): four pages, each an ink panel holding the real components it talks about. **1 كل شركات النقل في مكان واحد** — three companies with their lines and prices under the student's university: what Basak is, before anything else. **2 اشترك وادفع من هاتفك** — a line card, the stop being picked, "وصل إيصالك · قيد المراجعة". **3 أكّد رحلتك، وتابع كل جديد** — the ride question, an alert from the supervisor and one from the company. **4 بطاقتك دائماً معك** — the card, "بدون إنترنت", "محفظة الهاتف". One title, one line, "التالي" and "تخطي"; the last page ends in "إنشاء حساب" / "لديّ حساب". The app already has four slides, so this is a restyle.
- **Entry** (returning users): mark, name, one line, two buttons, a quiet "دخول المشرفين" link.
- **Sign in**: on the app's own light ground. A logo lockup beside the back button, "أهلاً بعودتك" set large, then phone and password **grouped in one white card** (label above value, a hairline between them, the focused label in teal), "نسيت كلمة المرور؟", **دخول** with a square Face ID button beside it, and the links at the bottom. Its character comes from structure — the lockup, the grouped card, the type — and not from decoration. A dark header box with circles was tried and removed (see the rule below). Every entry screen shares this layout: supervisor sign-in, biometric sign-in, password recovery and the forced password change.
- **Sign up**: four steps, where **the progress is the route rail itself** — four stops (بياناتك · دراستك · صورتك · كلمة المرور), passed ones filled teal with a check, the current one a teal ring. Each step asks one question in its own words ("من أنت؟", "أين تدرس؟", "صورة واضحة لوجهك", "كلمة مرور") with one line of why, and its fields sit in one grouped card. **1** name and phone; **2** university and college, each a searchable sheet, and the university cannot be changed later; **3** photo — a dashed circle, camera or photos, then the crop screen; "التالي" unlocks once a photo is in; **4** password with a strength meter, confirmation and terms. `AuthRepository.signUp` already takes `college`; today the screen sends "غير محدد".
- **Tab bar**: الرئيسية · اشتراكي · بطاقتي · حسابي, in the app's own floating pill — 64 high (the height it has today), 16 from the sides, solid white with one soft shadow and no blur. Every slot is icon + label, 11 px, on the same baseline; only the card's icon sits in an ink pill. On scroll down the labels fold away and the pill drops to 52; all four tabs stay one tap away, and it grows back on scroll up or at the top. It occupies the same 84 px the earlier docked version did, so no screen changed its layout.

### 2. Home
Header: photo and greeting (first two names, `GreetingHeader.firstTwoNames` kept) at the start, bell with unread count at the end. Then pass → tomorrow's ride → supervisor.

- **Pass**: always a ticket, never a plain box. Above the tear line: the status chip, the period (which opens the subscription) and the route on its rail — boarding stop, then the university. Below it, a stub that repeats nothing: the line and company (moved down from under the destination) and one mint button that opens the card. A soft ring sits behind the top corner. When there is something to do, the stub carries that instead (pay, new receipt, renew). Dates and money stay on the subscription tab.
- **Ride, not confirmed**: the date, the deadline as a single amber pill, "هل ستركب غداً؟" and two buttons. "نعم" opens the sheet: departure times and return times as two 3-column grids that take any number of times (drawn with 5 and 6), and "لن أعود بالباص" as a full-width option of the return group, not a checkbox.
- **Ride, confirmed**: a green "مؤكدة" chip, two tiles (الذهاب / العودة), "التعديل متاح حتى 6:00 ص" and a quiet "تعديل". The 7-day strip sits under a hairline: filled = confirmed, ring = the day being asked.
- **Supervisor**: one row, two icon buttons (call, WhatsApp). Save-contact and copy stay in the existing contact sheet.
- **No subscription**: "ابدأ اشتراكك", the route with what is already known — the university as the destination, the boarding stop still dashed — and "اشترك الآن". The three steps are explained in onboarding, not here.
- **Company invitation**: an invite card (company, line · station, type, price, قبول / رفض, "1 من 2" when there are several) and a text link to choose a subscription instead; accepting opens a sheet that states exactly what is shared and what is opened before "موافق، انضم".
- **Under review**: a light pass with the 3-node progress line, and the ride card locked. What was submitted is on اشتراكي.
- **Live alert banner** (component board): appears above the pass only while a transport alert is live.

### 3. Subscribe (company → line + station → period → review)
One screen, **"اشتراك جديد — إلى جامعة …"**. The university is context, not a step: it was chosen at sign-up and the catalog is already filtered by it.

- Three `BuilderRow`s. The open one shows its options directly on the ground; chosen ones collapse to a line with "تغيير"; future ones are sunken and numbered.
- A company with one option is preselected and starts collapsed.
- **Line + station is one gesture**: tap a line card → the station sheet opens over it → tap a stop → both collapse into "الزرقا · كوبري السرو".
- **Station sheet**: "من أين تركب؟", search (shown above 6 stops), stops in route order on the rail. Each row shows only the first pass time ("من 6:15 ص"); the selected stop opens in place to list every pass time, so the row length does not depend on how many trips the line runs.
- **Period**: three tiles side by side — الفصل الأول · الفصل الثاني · الفصلان معاً — price under each, a "وفّر …" tag on the bundle, one caption line with the dates of the selected tile, and the cash day as a quiet row below.
- A dock appears only once a period is chosen, with one button: "مراجعة الاشتراك". The price is on the selected tile and again in the review, so the dock carries no total.
- **Review is a sheet**: rail, period, valid-until, amount, the one irreversible fact, then "تأكيد والانتقال للدفع".

Maps 1:1 onto `SubscriptionDraft` / `DraftStep` / `canOpen` / `reconciled` — no model change.

### 4. Line cards
Four facts in fixed positions so cards compare by eye: **name · stop count · from-price · first departure / last return**. At most one tag ("يومي متاح"). A line that is not on sale is a shorter, muted card with "غير متاح" and the reason on one line; it is not tappable. The destination is the page subtitle, not a row on every card.

### 5. Pay and upload
A page, not an expander. Top to bottom:

1. **Amount, once**, with the period as its caption.
2. **1 · حوّل المبلغ** — one chip per method the company has configured, labelled with its `displayName` and wrapping onto more rows as needed (drawn with five: InstaPay, two wallets, two banks); one details card: account holder + method, then only the copyable values, each with "نسخ".
3. **قبل التحويل** — what must be right *before* transferring, in one collapsible card: transfer the full amount in one operation, plus the company's own `instructions`. Nothing about review or notifications here.
4. **2 · ارفع الإيصال** — a dashed drop zone that states the one requirement ("صورة واضحة فيها رقم العملية والتاريخ") with الكاميرا / من الصور.
5. **Dock**: "إرسال للمراجعة", disabled until an image is attached.

The amount has a "نسخ المبلغ" button, because the student pastes it into the bank app. While sending: step 1 collapses to a row, the chosen image is shown large enough to recognise, with a real percentage and the three phases the code already reports (`ReceiptPhase.preparing / uploading / saving`). Result: icon, "استلمنا إيصالك", one sentence about review and notification — the only place that sentence appears — and two exits. Rejected: the same screen with the company's reason on top and the attempt count (shown only from attempt 2).

### 6. Subscription tab
- **No subscription**: the tab opens the builder directly (as today).
- **Awaiting payment**: one card — chip, period, amount, "ادفع الآن" — then line + station and company as rows.
- **Under review**: one card — chip, period, when the receipt was sent — then rows: line + station, company, amount, method. The progress line is on Home.
- **Active**: ink pass with period, days left and a validity bar; rows for line + station, company, and **الإيصال** as a navigating row; a tonal card for the next period when the catalog offers one; past subscriptions as quiet rows.
- **Expired**: a light card with منتهٍ and the date, a prefilled renewal (same line and station, next period, price), "جدّد الاشتراك" and "اختر خطاً أو محطة أخرى"; history below.
- **Rejected / upcoming**: drawn on the *Pass in every status* board; rejected leads to the pay screen.

### 7. My card
A tab on an ink ground, written for the person looking at the phone — the supervisor.

- **Face of the card**: the student's photo (60 px, with a ring in the status colour), name, college and university; the QR; the status chip with "حتى 14 يناير 2027"; then four facts in a fixed grid — الخط, محطة الصعود, الفترة, الشركة — and a strip for **today's ride** ("ذهاب 7:00 ص · عودة 3:30 م", or "لم يؤكّد رحلة اليوم"). Everything fits one screen, so the supervisor never has to touch the phone.
- **"كل التفاصيل"** opens a read-only sheet: a larger photo, then three groups — بيانات الطالب (university, college, phone), الاشتراك (line, stop, company, period and year, validity from–to), رحلة اليوم (going, return). It is the same list a supervisor gets after a scan, so both sides read the same facts.
- **Not active**: the card never looks valid when it is not. The chip and the photo ring take the status colour ("قيد المراجعة", "منتهٍ", "لا يوجد اشتراك"), "حتى …" becomes "غير مفعّل بعد", the ride strip becomes the receipt fact ("أُرسل اليوم 3:40 م"), and the wallet button is hidden.
- Nothing new is fetched: the card already builds itself from the student row and the current subscription (`studentQrProvider`), which carry the photo, college, phone, period, dates and company; today's ride comes from the `RideDays` the Home screen has loaded.
- Money, receipts and instructions stay off the card. "تعمل بدون إنترنت" and the wallet button remain; the tab bar stays, so leaving is one tap.

### 8. Receipt
- **In app**: paid chip + code, amount, date and method; three collapsible groups (الاشتراك open, الطالب, الشركة — name, phone, address); dock with تنزيل PDF, save-as-image and share.
- **PDF (A4)**: company logo and name with the receipt code, "issued to" and payment columns, a tinted band with the route rail and validity, one table row, a total box. The footer carries the company address and phone, "صدر إلكترونياً عبر Basak.app ولا يحتاج إلى توقيع أو ختم.", and a last line "جميع الحقوق محفوظة · © 2026 Basak.app" (the year is the issue year). **No commercial register and no tax number**, on the PDF or in the app — `receipt_pdf.dart` prints both today (`legal`), so the restyle drops that list; the two fields stay in the model, unused. 1-px rules, prints in greyscale.

### 9. Alerts
A page behind the Home bell. Back, title, "قراءة الكل", a 2-way segmented filter, groups by day (اليوم · أمس · date), unread = weight + teal dot. Tapping opens the screen the alert is about, or a detail sheet for free-text messages. No gear, no categories, no search. When OS permission is off, one card at the top says so and opens the phone's settings.

### 10. Account
Identity card with the photo control; **بياناتي** (university locked, college, email) with one "تعديل"; **التطبيق** (help, language, phone notifications → OS settings); sign out; "حذف الحساب" as a quiet text link next to the version. Company and supervisor are not repeated here.

**Help & support** is a sheet with two groups. "عن رحلتك واشتراكك" lists the people the app already knows — the bus supervisor and the transport company. "دعم التطبيق" is a list rendered from configuration: each entry is `{icon, title, subtitle, action}` and the canvas shows placeholders. Nothing about WhatsApp, phone or FAQ is hard-coded; with zero entries the group is hidden.

---

## D. Key flows

| Flow | Steps |
|---|---|
| First subscription | Onboarding 1–3 → sign up: 1 details → 2 university + college (sheets) → 3 photo → 4 password → Home (no subscription) → builder: company → line → station sheet → period → review sheet → pay → upload → submitted → Home (under review) → push "تم تفعيل اشتراكك" → Home (active) → بطاقتي → اشتراكي → الإيصال |
| Invited by a company | Home (invitation) → accept sheet → اشتراكي (awaiting payment) → pay → … |
| Change before paying | In the builder, tap "تغيير" on any chosen row; later choices that still apply are kept (`pickLine` already does this). After confirming, the line and station are fixed; the method can still change on the pay screen. |
| Receipt upload | Pay → choose method → copy value → transfer in the bank app → return → camera/photos → send → progress → submitted |
| Show the card | بطاقتي tab from anywhere (or "عرض البطاقة" on the pass) |
| Daily ride | Home → "نعم، سأركب" → sheet → confirm → Home (confirmed) → "تعديل" reopens the sheet |
| Check alerts | Bell on Home → inbox → tap → the relevant screen or a detail sheet |
| Expired | اشتراكي shows the next-period card before expiry; after it, the renewal card prefilled → review sheet → pay |
| Rejected receipt | Push → pay screen with the reason → new image → send |

On the canvas, Play on *Welcome* walks the first-subscription flow end to end.

---

## E. States

| State | Home | اشتراكي | بطاقتي | Pay |
|---|---|---|---|---|
| **Loading (nothing cached)** | skeleton in the shape of header + pass + ride card; tab bar is real | skeleton rows | skeleton card | skeleton method card |
| **Loading (cached)** | cached content, no spinner; syncing strip only if > 1 s | same | same | same |
| **Empty** | half-filled pass + 3 steps | opens the builder | "لا يوجد اشتراك نشط" | — |
| **Invited** | invitation card + accept sheet | — | — | — |
| **Awaiting payment** | light pass + "ادفع الآن" | light pass + "ادفع الآن" | inactive | the pay screen |
| **Pending review** | light pass, 3-node progress, summary, ride locked | same | "قيد المراجعة" chip | read-only "استلمنا إيصالك" |
| **Approved / active** | ink pass; ride question or ride confirmed | ink pass, rows, receipt | active chip + valid until | — |
| **Rejected** | light pass, red chip, "إيصال جديد" | same | inactive | reason card + new upload, attempt n of 5 |
| **Expired** | renewal prompt | renewal card + history | "منتهٍ" chip | — |
| **Offline** | amber strip "بدون إنترنت · بيانات 8:15 ص · إعادة المحاولة"; pass and card work; ride buttons disabled with one line why | cached, stamp on the pass | always opens, "تعمل بدون إنترنت" | send disabled, image kept |
| **Syncing / partial** | teal strip; a failed section shows `InlineError` in place, others stay | same | — | — |
| **Back online** | green strip for 2 s | — | — | — |
| **Error (nothing cached)** | full-screen "لا يوجد اتصال" + retry, tab bar present | same | same | inline error + retry |
| **Success** | ink toast with a mint check | — | — | centred "استلمنا إيصالك" |

Writes are never queued offline (matches `OfflineCache`): the ride vote and the receipt need a connection and say so in one line.

---

## F. Claude Design → Flutter

**Canvas layout.** Student app: 01 Foundations (7 boards) · 02 Entry & sign-up (18) · 03 Home & my card (10) · 04 Subscribe & pay (8) · 05 Subscription & receipts (6) · 06 Alerts & account (5) · 07 States (5) · 08 Term recap, one student (12) · 09 Term recap, the system (6) · 10 Rating & update (4) · 11 The rest, found in the app (19). Supervisor app, four rows below them: 12 Sign in, today & trips (7) · 13 Scan (4) · 14 Messages, summary & account (7) · 15 States (8). Every phone artboard is 390 wide, Arabic, RTL, and the tab bars and headers come from one definition each.

**Token structure.** One source in `lib/core/ui/tokens.dart`, exposed as `ThemeExtension`s so nothing reads a hex value directly:

```dart
context.colors.ink        // BasakColors
context.type.headline     // BasakType
BasakSpace.s16, BasakRadius.card, BasakShadow.card
```

`AppTheme.lightTheme` is rebuilt from these tokens (buttons, inputs, sheets, snackbars, page transitions), so even un-migrated Material widgets pick up the new look.

**Layout system.** `BasakPage(title, children, dock)` gives every screen the same gutter (20), top inset, 16-px rhythm and an optional bottom dock. `BasakSheet.show(context, title, child, primary)` gives every sheet the same grabber, radius and safe-area handling.

**Consistency rules** (enforceable in review and by a grep check in CI):

1. No `Color(0x…)`, `BorderRadius.circular(n)` or `TextStyle(` outside `core/ui/`.
2. No `EdgeInsets.only(left/right)`, `Alignment.centerLeft/Right`, `TextAlign.left/right` — use the directional forms.
3. A status is rendered only through `StatusChip(SubscriptionStatus)`.
4. Money only through `formatMoney`; time only through `BasakUi.time12`; both produce Western digits.
5. One `BasakButton.primary` per route.
6. Every user-facing string comes from `AppLocalizations` (see G, phase 6).

**Artboard → file map**

| Artboard | Flutter target |
|---|---|
| Main, HomeConfirmed, HomeNew, HomeInvite, HomePending | `features/student/home/presentation/student_home_screen.dart` (split into `pass_card.dart`, `ride_card.dart`); invite card from `features/student/invites/invites.dart` |
| HomeRide | new `ride_sheet.dart` |
| InviteSheet | `invites.dart` (replaces the `AlertDialog`) |
| Card, CardDetails, CardInactive | `features/student/qr/presentation/student_qr_screen.dart` (+ a details sheet built on `BasakSheet`) |
| FlowCompany … FlowConfirm | `features/student/subscription/presentation/purchase_flow.dart` (builder), new `station_sheet.dart`, `confirm_sheet.dart` |
| Pay, PayUpload, PayDone, StateRejected | new `pay_screen.dart` (extracted from `subscription_screen.dart`) |
| SubscriptionAwaiting, SubscriptionReview, Subscription, SubscriptionExpired | `subscription_screen.dart` (list only) |
| Receipt, Invoice | new `receipt_screen.dart`; `receipt_pdf.dart` restyled |
| Inbox, InboxDetail, InboxEmpty | `features/student/home/presentation/notifications_screen.dart` + `features/notifications/presentation/notifications_page.dart` |
| Profile, Help | `features/student/profile/presentation/profile_screen.dart`, `profile_editor.dart`, new `help_sheet.dart` |
| Splash, Onboarding1–3, Welcome, SignIn | `features/splash`, `features/onboarding` (screens rebuilt, `OnboardingController` kept), `features/auth/presentation/login_*` |
| SignUp, SignUpStudy, UniversitySheet, CollegeSheet, SignUpPhoto, SignUpPassword | `features/auth/presentation/signup_screen.dart` split into four step widgets; `university_picker_sheet.dart` restyled and reused for the college list |
| PassStates, State boards | `core/ui/pass_card.dart`, `core/ui/connection_strip.dart`, `core/widgets/skeleton.dart` |

---

## G. Implementation plan (not started — waits for design approval)

> The phase order, guardrails and defaults to build from are in `docs/mobile-redesign-implementation-plan.md`, written after the supervisor app, the recap and the coverage audit were added. Where the table below differs from it, that file wins.

**The one rule that keeps the backend safe:** only files under `presentation/` and `core/widgets|ui|theme` change. Providers, repositories, models, `core/sync` (SyncHub), `core/storage` (OfflineCache) and every Supabase call stay byte-identical. Each screen is rebuilt against the providers it already watches.

### Phases

| Phase | Work | Ships as |
|---|---|---|
| **0 · Foundation** | `core/ui/`: tokens, theme, `BasakButton`, `BasakField`, `InfoRows`, `StatusChip`, `BasakSheet`, `BasakToast`, `EmptyState`, `InlineError`, `BasakPage`. Rebuild `AppTheme` from tokens. Golden tests for each component in ar and en, at text scale 1.0 and 1.3. | Invisible except the theme refresh |
| **1 · Shell** | `BasakTabBar` on the same four tabs, `HomeHeader`, `ConnectionStrip` replacing `OfflineBanner`, toasts replacing snackbars. | First visible release |
| **2 · Home and card** | `PassCard`, `RouteRail`, ride card (ask / confirmed), `RideSheet`, supervisor row, invite card + sheet, the card tab. | |
| **3 · Subscribe** | Builder on `SubscriptionDraft`, `LineCard`, `StationSheet`, period tiles, `ConfirmSheet`. Opens as a full-screen route. | |
| **4 · Pay, subscription, receipt** | `PayScreen` on `paymentMethodsProvider` + `ReceiptSubmitter`; subscription states; `ReceiptScreen`; PDF restyle. | |
| **5 · Alerts, account, entry** | Inbox without preferences, permission card, profile, help sheet, onboarding, entry, sign in, 4-step sign-up with college, splash. | |
| **6 · Cleanup and English** | Delete student use of `glass_*`, `basak_ui.dart` leftovers and the preferences screen; add `flutter gen-l10n` with `app_ar.arb` / `app_en.arb`; replace the 20 physical-direction usages; one numeral policy. | |

Build first, in this order: tokens → `BasakButton` → `InfoRows` → `StatusChip` → `BasakSheet` → `PassCard` + `RouteRail` → `BasakTabBar`. These seven cover about 80% of every screen.

### Reuse, restyle, replace

| Keep as is | Restyle | Replace |
|---|---|---|
| All providers and repositories; `SubscriptionDraft`, `SubscriptionRequest`, `SaleCatalog`, `SubscriptionModel` helpers (`boardingTitle`, `periodName`, `returnShown`) | `skeleton.dart` shapes | `glass_scaffold.dart`, `glass_container.dart` (the nav bar itself is restyled, see J.3) |
| `OfflineCache`, `SyncHub`, `OwnChanges`, `SnapshotNotifier` | `receipt_pdf.dart`, `receipt_card.dart` | `basak_ui.dart` (`BasakPill`, `BasakInfoRow`, `BasakMessageCard`, `heroGradient`) |
| `ReceiptSubmitter`, `ReceiptPhase`, `ImageOptimizer`, pending-receipt reconciliation | `supervisor_contact_sheet.dart` | `onboarding_screen.dart` carousel |
| `VoteSettings`, `VoteReminders`, ride repository | `photo_adjust_screen.dart` | `notification_preferences_screen.dart` for students |
| Tab indices, `_selectTab`, `NotificationRouter` destinations | `push_permission_sheet.dart` (copy and style) | per-file `_ink` / `_teal` / `_canvas` constants |
| `GreetingHeader.firstTwoNames` / `greetingFor`, the ink and teal values, Readex Pro, Lucide, `formatMoney`, `BasakUi.time12` | `university_picker_sheet.dart` | `OfflineBanner` |

### Guardrails

- **Keep the widget `Key`s** the tests rely on (`flow-back`, `option-daily`, `next-period`, `subscribe-again`, `sub-card-*`, `receipt-pdf-*`, `payment-methods`, `payment-notes`, `student-qr`, `supervisor-*`, `profile-*`). Where a control disappears (`sub-toggle-*`, the review "تعديل" buttons), update the test in the same PR and say so in its description.
- **One screen per PR**, old screen deleted in that PR — no long-lived parallel UI.
- `flutter test` green before and after every PR; `subscription_flow_test.dart`, `receipt_upload_test.dart`, `offline_first_test.dart` and `student_experience_test.dart` are the safety net for phases 3–4.
- Check every screen at 360 × 640, at text scale 1.3, in Arabic and (from phase 6) English.
- `FloatingGlassNavBar` is restyled, not replaced: the same widget and the same `collapseOnScroll` rule serve both shells, with "collapsed" now meaning labels hidden rather than one circle. `glass_container.dart` and `glass_scaffold.dart` are deleted only when nothing imports them.

---

## H. Supervisor app

The same design system, drawn as its own section at the bottom of the canvas (rows 12–15, 26 artboards). Design only, like the student side: every screen below uses data the app already loads. Where something would need the backend, it is listed under "Ideas noted, not drawn" and is not on the canvas.

### H.0 What is wrong today (from the code)

- **Four overlapping views of "who rides when"**: Home's trip-times list and its sheet, Home's «رحلات الجامعات», the Trips manifest, and the Rider counts screen — each grouped differently.
- **The same numbers repeated**: registered students appear four times on Home and again in the profile; station count and confirmed-today twice each.
- **The main job is buried**: "scan" is the last tile of a long Home scroll, and the last item after every station on Trips.
- **A multi-line supervisor picks the line three times** (Home, Trips, the send sheet), and the choice is lost on every tab switch because tab state is not kept.
- **Scanner at the bus door**: one tap to dismiss the result for every rider; two unlabeled icon buttons with no on/off state; no trip shown in tab mode and a direction that flips silently at noon; a harmless repeat scan styled as a red error; the session counter resets when the tab changes.
- **Offline is not honest up front**: writes are never queued, so a scan made offline records nothing, but the screen only says so after the scan.
- **Vocabulary drifts**: boarding is «تسجيل الصعود» / «تسجيل حضور» / «صعد» / «سُجّل»; confirming is «أكد» / «صوّت»; counts read «4 طالب», «0 طالب».
- **Weak states**: the manifest error prints the raw exception, the Home error hides the bell, "no trips" tells the supervisor to use the admin dashboard, a suspended account is handled on Home only, Rider counts shows raw `HH:MM:SS` and has no retry.

### H.1 Structure

| Today | Redesign |
|---|---|
| 5 tabs on the floating glass bar: الرئيسية · الرحلات · مسح QR · الملخص · حسابي | 4 tabs on the same floating pill as the student: **الرئيسية · الرحلات · مسح · حسابي**. The scanner is the one filled item — the mirror of the student's card tab, which is what it reads |
| الملخص as a tab used once a month | A page under حسابي |
| Rider counts screen, `TripRidersSheet`, «رحلات الجامعات», «الطلاب حسب المحطة» | Folded into two places: **Home = the numbers** (how many go, how many return), **Trips = one trip** (who boarded) |
| Line chosen separately on Home, Trips and the send sheet | One line, chosen once from a sheet, shown on Home, applied to Trips, scan and messages |
| Tab scanner (no trip) and a second, trip-pinned scanner route | One scanner that always shows the trip it is boarding; the pill opens the trip sheet. Whether "each student's own trip" (today's tab behaviour, `p_trip_id` null) stays as a choice is an open decision |
| Bell on Home only | Bell on Home in every state, including errors |
| In-app notification category switches | "إشعارات الهاتف" → the phone's settings, as on the student side (confirm — see open decisions) |

**One purpose per screen**

| Screen | Its one job | What it no longer carries |
|---|---|---|
| الرئيسية | The numbers the buses are planned on: how many are going and how many are returning, per trip, today and tomorrow | The next-trip card and scan button, per-station bars, prices, the registered-students tiles |
| الرحلات | One trip: who boarded and who has not, stop by stop | A second scan button, the route chips, four stat tiles |
| مسح | Boarding | Explanatory cards over the camera |
| حسابي | Who I am, which company and lines, the app | Account metadata (creation date, last sign-in, account type), the stations list |
| ملخص الشهر | My scanning month | — |

### H.2 Screen by screen

- **Sign in** — the same screen as the student's with the supervisor's wording: phone or email, password, and the existing note «حسابات المشرفين ينشئها مسؤول النظام فقط.» plus where to go for a forgotten password. Reached from "دخول المشرفين" on the entry screen. The role still comes from the server; nothing about detection changes.
- **Home (the numbers)** — the screen a supervisor opens to size the buses. Greeting and bell; the **line row** (only with more than one line); then one ink card with the two numbers that matter, set large. **The day is changed by swiping that card** — there is no switch above it: the card names its day ("اليوم · الأحد 11 أكتوبر"), the other day's card peeks in from the side it will come from, and two dots under it show the position and are the tap alternative to the swipe. The lists below follow the card. It opens on tomorrow once tomorrow's confirmation has opened, as the counts screen does today. The numbers: **الذهاب 107 · العودة 105**, each with its number of trips. The line under the day says how firm they are, from the company's `VoteSettings`: "نهائي · أُغلق التأكيد 6:00 ص" or "التأكيد مفتوح · حتى 6:00 ص"; its bottom line says how much of the line that is — "سيركب 107 من 124 مشتركاً" with a bar. **مشاركة** sends the day's counts as text (`share_plus` is already bundled), because the supervisor passes them to the company and drivers. Below, two columns side by side — **الذهاب** and **العودة** — list every trip as time, count and a bar scaled to the busiest trip, so the peak is visible without reading; the next trip is tinted and marked, past times are dimmed (by the clock — the backend has no "trip started" state). Any trip opens its riders in الرحلات. Last, "إشعار للطلاب". Everything here comes from `supervisorDashboardProvider` (`tripTimes`, `line.registeredStudents`, `profile.vote`).
- **Line sheet** — the assigned lines as single-choice rows (university, subscriber count, «متوقف» when inactive), one sentence saying the choice applies everywhere, "تأكيد".
- **Trips (one trip)** — a card with the trip's time and direction, "تغيير" (opens the trip sheet), arrival time, and one progress line: "صعد 14 من 38 · بقي 24". Then the stops on a rail in route order, each with its stop time and a boarded / expected pill (green when complete, amber where someone is missing). A stop opens in place to its riders: boarded time, or «لم يصعد». A collapsed "لم يؤكّدوا اليوم · 5" group closes the list. There is no scan button here: the filled tab is one tap away and already knows the trip.
- **Trip sheet** — الذهاب / العودة with counts, then every trip as a row: time, how far away it is, riders. Scales to any number of trips.
- **Rider sheet** — name and boarding state, stop and stop time, today's confirmation, university, phone, and three actions: اتصال, واتساب, نسخ الرقم (the phone is already shown as text today; `url_launcher` is already used by the student's supervisor-contact sheet).
- **Scan** — a full camera with two pills on top: the trip ("ذهاب · 7:00 ص", tap to change) and the live count ("14 / 38"). One hint under the frame. At the bottom, the last boarding as a tappable row, and two labelled controls with a visible on state: الإضاءة, قلب الكاميرا.
- **Scan result** — a sheet over the live camera: a coloured badge, a title, one line, then the student block (name, university, stop, today's confirmation, phone). **A successful scan closes by itself after two seconds**; every other outcome waits for "مسح التالي". See H.3.
- **Message — who and what** — "يصل إلى": ركاب رحلة (with the trip row) or كل طلاب الخط. "الرسالة": the server's ready messages for that direction as rows, then "رسالة أخرى".
- **Message — confirm sheet** — the notification exactly as the student will see it, the minutes chips when the message needs them, "سيصل إلى 38 طالباً · ركاب ذهاب 7:00 ص اليوم", and «تأكيد الإرسال». A free-text message goes through this same sheet; today it is sent with no confirmation.
- **Message — free text** — title (80) and body (600) with live counters, the audience row, "متابعة".
- **Sent** — the ink toast "تم إرسال الإشعار إلى 38 طالباً." on the screen the supervisor came from.
- **Alerts** — the student inbox layout; what the supervisor sent sits in the same list marked "أرسلته أنت · {audience}", as the data already has it.
- **Account** — identity card with the status chip; **العمل** (company, lines → line sheet, monthly summary); **التطبيق** (help, language, phone notifications); one line saying the company manages the details and password; sign out.
- **Monthly summary** — month switcher; an ink hero with total boardings, the attendance rate and the going / return split; four counters; the daily chart with the value printed over every bar (today's are long-press tooltips only); scan results and the six busiest stops as labelled bars.

### H.3 Scan outcomes (one sheet, six results of `supervisor_check_in_student`)

| Outcome | Title | Tone | Behaviour |
|---|---|---|---|
| `checked_in` | تم تسجيل الصعود | success | Medium haptic; closes after 2 s, the camera never stops |
| `already_checked_in` | سبق تسجيله اليوم | info (teal) | A notice, not an error; stays until tapped |
| `no_active_subscription` | لا يوجد اشتراك ساري | danger | Heavy haptic; details shown so the supervisor can explain |
| `outside_assigned_lines` | الطالب ليس على خطك | danger | No student details (the server sends none) |
| `not_found` | رمز غير معروف | danger | Also any code that is not a Basak card |
| `offline_lookup` | بدون إنترنت · لم يُسجَّل | warning | Only for a student scanned before on this phone; says plainly that nothing was recorded |

The scan result has **no student photo**: `ScannedStudentDetails` does not carry one. The supervisor checks the face against the photo on the student's own card, which is why that card now shows it large (section C.7).

### H.4 States

| State | What the supervisor sees |
|---|---|
| Loading, nothing cached | A skeleton in the shape of Home |
| Offline, cached | The day as last saved, an amber strip with the time of the data and "المسح لا يسجّل الصعود الآن" |
| Scanner offline | The same sentence on the camera *before* scanning |
| Camera not allowed | What the camera is for, "فتح الإعدادات" and "إعادة المحاولة" |
| No trips in a direction | "لم تُضف الشركة رحلات عودة لخط الزرقا بعد" — no instruction to open the admin dashboard |
| No line assigned | Header and bell stay; one sentence and "تحديث" |
| Account suspended | One blocking screen for the whole app, with sign out |
| Nothing cached, load failed | Header and bell stay; plain message and retry — never the raw exception |

### H.5 Words

One word per thing, on every supervisor screen: **صعد / لم يصعد / تسجيل الصعود** for boarding, **أكّد** for the student's daily choice, **الرحلة** for a departure or return, counts with correct Arabic plurals ("38 طالباً", "9 طلاب"). The ready messages are server data and still say «الحافلة»; aligning them with «الباص» is a seed change, not an app change.

### H.6 Claude Design → Flutter

| Artboards | Flutter |
|---|---|
| SupSignIn | `features/auth/presentation/login_screen.dart` (supervisor mode) |
| SupHome, SupHomeTomorrow, SupHomeSent, SupLineSheet, SupState* | `features/supervisor/home/presentation/supervisor_home_screen.dart`; `trip_riders_sheet.dart` and `rider_counts_screen.dart` retire into it |
| SupTrip, SupTripSheet, SupRider, SupTripEmpty | `features/supervisor/trips/presentation/supervisor_trips_screen.dart` |
| SupScan, SupScanOk, SupScanStop, SupScanStates, SupScanOffline, SupScanPermission | `features/supervisor/qr_scanner/presentation/supervisor_qr_scanner_screen.dart` |
| SupSend, SupSendConfirm, SupSendCustom | `features/supervisor/notifications/supervisor_notifications_screen.dart` (`SendNotificationSheet`, `QuickNotificationSheet`) |
| SupInbox | `features/notifications/presentation/notifications_page.dart` (shared with the student) |
| SupProfile, SupMonthly | `features/supervisor/profile/…`, `features/supervisor/monthly/…` |

- The supervisor work is **one more phase after the student phases**, on the same `core/ui` widgets: `PassCard` + `RouteRail` (next-trip card, stops), `ChoiceTile` (trip tiles), `BasakSheet`, `InfoRows`, `StatusChip`, `BasakTabBar`.
- **Kept as is**: `supervisorDashboardProvider`, `tripManifestProvider` / `ManifestKey`, `riderCountsRepoProvider`, every RPC and `OfflineCache` key, `CheckInOutcome`, the send limits and their messages.
- **New, presentation only**: one provider holding the chosen line and trip (today each tab keeps its own and loses it on switch); the 2-second timer on a successful scan; a client-side "past" look on trip tiles.
- **Tests**: no supervisor screen has a widget `Key` today, so nothing breaks structurally. Text finders that change wording must be updated in the same PR — `student_notifications_test.dart` (send sheet strings such as «إرسال الإشعار», «سيصل إلى: …», «المدة بالدقائق», «تأكيد الإرسال»), `floating_nav_bar_test.dart` («الرحلات», «مسح QR»), `notification_center_test.dart` («غير المقروءة (2)»). Where the canvas keeps the existing string («تأكيد الإرسال», «المدة بالدقائق», the sign-in note) it is kept on purpose.

---

## I. Recap, rating and update (student)

Three additions asked for after the main design. They are drawn on the canvas (rows 08–10, 22 artboards) so they can be judged, but unlike the rest of this document **two of them need more than the presentation layer** — each says what.

### I.1 Term recap ("ملخّص الترم")

A story the student taps through at the end of a term and shares — the one place in the app that is allowed to be funny. It is **assembled from rules, not written once**, so it holds for the student who rode twice and the one who never missed a day, and it sounds like *their* college, stop and line. Canvas: row 08 is one student start to finish (Sara, Engineering, 62 ride days — a banner and eleven pages); row 09 is the system behind it (nine students' posters, a line for every specialisation, the titles bank, how a recap is built, the short version, and the days page for a three-day week).

**Pages, and when each appears**

| Page | Shown when | Sample (Sara) |
|---|---|---|
| Cover | Always | "الفصل الأول · 2026 / 2027" — "ترمك في الباص" |
| Hours | Trip length known and total ≥ 3 h | "109 ساعة في الباص" — "يعني 4 أيام ونص من عمرك جنب الشباك." + the college's line |
| Days and weekdays | From 8 ride days | "62 يوم ركبت الباص", six weekday bars — "الأحد يومك. والخميس؟ واضح إن عندك ظروف." |
| Shape of the term | From 8 ride days | One dot per study day of the term — "والفراغ اللي في النص؟ ميدتيرم… مصدّقينك." |
| Longest run | Longest run ≥ 4 study days; longest absence joins from 5 | "14 يوم ورا بعض" — "حتى المنبّه اتفاجئ." |
| Favourite time | From 5 rides; another version when only one time was ever used | "7:23 ص · ركبته 41 مرة" — "الباص بقى عارفك." |
| Return | Always, in four versions: nearly always, mixed, rarely, never | "55 مرة رجعت بالباص" — "و7 مرات قلت «هرجع لوحدي»…" |
| Stop and line | Always; the most-used stop if it changed | The line drawn as its rail with "كوبري السرو" called out — "الرصيف حفظ مكانك." |
| College | College matches a family; otherwise the university page | "يا هندسة" — "109 ساعة = 36 محاضرة استاتيكا. اختار اللي يوجع أقل." |
| Title | Always | "لقبك الترم ده: عمدة كوبري السرو" and why |
| Share card | Always | A 9:16 poster: title, the specialisation's line, the term as a pattern, three numbers, first name, line, `Basak.app` |

**Their week, not the calendar's.** Many students only come some days of the week — three, say — and a recap that counted against all six study days would call a student who never misses "half the term" and tease them about days they have no classes. So everything is measured against the student's **own days**:

- A weekday is one of theirs when they rode it in at least a third of the weeks since their first ride. Official holidays in the company's settings (`VoteSettings.offDates`) are left out.
- **Attendance** = rides on their days ÷ those days in the term. Sunday–Tuesday–Thursday with 41 rides out of 45 is 91%.
- **Tiers and titles** use that share. "عمدة {المحطة}" needs a week of four days or more; a week of three or fewer with 80% ridden gets its own title, "جدول على المقاس".
- **The weekday joke** is only about the weakest of their own days, and only when it is well below the best — never about a day they do not come. With a three-day week the joke is about the schedule itself: "3 أيام في الأسبوع؟ ده جدول يتحسد عليه."
- **Runs and gaps** are counted in their days: three weeks of Sunday, Tuesday, Thursday is a run of 9. A day off is not an absence.
- A ride outside their days is a bonus line ("ويومين زيادة من عندك"), not a broken pattern.

The days page for such a student is on the canvas (`RecapDays3`): three solid bars, three blank slots, and "وحضرت 41 من 45 في أيامك. الباقي إجازة رسمي، مش غياب."

**How much they rode changes the whole recap**

| Share of their own days | Recap |
|---|---|
| 0 rides | None, and no banner |
| 1 to 7 rides | Short version — cover, one number, share; title "ضيف شرف"; kind about it ("إحنا مش زعلانين… إحنا بس مستغربين.") |
| 8 rides to 30% | Full, with light-rider jokes |
| 30% to 60% | Full, the standard voice |
| 60% and more | Full, with the regular's jokes |

**The poster.** A 9:16 card that uses its whole height — nothing is parked at the top as a label and nothing is crammed at the bottom. Top to bottom, evenly spaced: "ملخّص الترم" and the term; the title, large, with one line saying why; **the specialisation's own line**, set off by a coloured rule; **the term as a pattern** — 17 weeks across, the student's study days down, one dot per ride — so no two posters look alike and a three-day week or a mid-term start is visible at a glance; three numbers; first name, line and `Basak.app`. Five colour themes. The type is the app's own Readex Pro, with nothing on the poster under 12 px at phone size (about 41 px in the shared image) and weight 500 or more on coloured grounds.

**Titles — 66 of them, in 16 patterns.** A pattern is a habit read from the student's own rides; each pattern has several titles and the student's is picked by a fixed draw, so they always see the same one but two friends with the same habit rarely share it. When more than one pattern fits, the rarer wins.

| Pattern | Titles |
|---|---|
| Rides most of their own days | عمدة {المحطة} · المحطة باسمي · عضوية ذهبية · ركن أساسي · من أهل الباص · الكرسي محجوز |
| Mostly the first trip of the day | ديك الفجر · قبل الشمس بشوية · أول الطابور · لجنة فتح البوابة · وردية الصبح |
| Mostly the last trip going | على آخر لحظة · 5 دقايق كمان · آخر باص الصبح · لحقته بالعافية |
| Same time nearly every day | ساعة سويسرية · ع الدقيقة · منبّه بشري · معاد ثابت |
| Many different times | على حسب المزاج · مفاجأة اليوم · خط سير حر · كل يوم بحال |
| Mostly the last trip home | آخر باص · الكلية بتقفل ورايا · وردية المسا · أمن المدرج · آخر نور في الكلية |
| Mostly the first trip home | خروج مبكر · أول باص راجع · محاضرة واحدة وكفاية · الغدا في البيت |
| Rarely returns by bus | تذكرة ذهاب بس · ذهاب بلا عودة · رجوع حر · الرجوع على الله |
| A week of three days or fewer | جدول على المقاس · دوام 3 أيام · ويك إند 4 أيام · أسبوع مضغوط |
| A long run without a miss | حضور كامل · ولا يوم · سلسلة دهب · مفيش غياب |
| One weekday far above the rest | {اليوم} بتاعي · بداية نار · يوم الحضور الرسمي |
| Thursdays far below the rest | ويك إند طويل · الخميس إجازة · أسبوع 5 أيام |
| Very many hours on the road | ساكن في الباص · الباص بيتي التاني · إقامة كاملة · عنواني: خط {الخط} |
| Subscribed mid-term | نص ترم · الموسم التاني · وصول متأخر… بس وصول · انضمام رسمي |
| One to seven rides | ضيف شرف · ظهور خاص · زيارة خاطفة · كل سنة مرة |
| Nothing above matched | عِشرة عُمر · من الدفعة · ركوب محترم · على الخط |

**A line for every specialisation.** The college is not printed as a label; it speaks through a joke of its own, on the poster and on the hours and college pages. The canvas has a first bank of 39 — one each for هندسة (and مدنية، معمارية، كهرباء، ميكانيكا), حاسبات، نظم معلومات، ذكاء اصطناعي، طب بشري، أسنان، صيدلة، علاج طبيعي، تمريض، بيطري، تجارة، محاسبة، إدارة، اقتصاد، حقوق، آداب (and إنجليزي، تاريخ، جغرافيا، علم نفس), إعلام، ألسن، علوم (and كيمياء، فيزياء، رياضيات), تربية، رياض أطفال، تربية رياضية، زراعة، فنون، سياحة وفنادق، آثار، خدمة اجتماعية, and a fallback. Three samples: محاسبة "الأصول: مكان جنب الشباك. الخصوم: المنبّه." · طب أسنان "{ي} يوم ركوب، ولسه الناس بتقول: «بص على ضرسي كده»." · فيزياء "سرعة الباص ثابتة. سرعتك للمحطة هي اللي بتتغيّر."

- The rule for every line: the joke is about the road, sleep or the alarm clock *seen through that subject*; never about how hard, easy, prestigious or crowded the college is, and never about another college.
- **They are first drafts.** I searched for Egyptian student humour to build on and found almost nothing usable — that material lives on Facebook, TikTok and Instagram pages, which a web search does not reach — so these come from knowing the subjects' clichés, not from tested jokes. They need to be read aloud by students from those colleges before any ships, and each row should grow to three or four lines so classmates do not all get the same one.
- The college is free text at sign-up and is matched by keyword. A **department** (مدنية، محاسبة، فيزياء…) is not stored today, so the department rows need that field first (open decision 18).

**Numbers never break the sentence.** Every count has four forms — 1 "يوم واحد", 2 "يومين", 3–10 "{n} أيام", 11+ "{n} يوم" (the same for ساعة and مرة) — and the hours comparison is picked by range, from "يعني فيلمين وخلاص." under 10 hours to "ده مش باص، ده سكن." over six days.

**When the data is thin or odd**: no college → university voice; never returned by bus → the return page becomes "تذكرة ذهاب بس" and no zero is shown as a failure; one time all term → "معاد واحد طول الترم"; subscribed mid-term → percentages count from the first ride; changed stop or line → the most-used one, called "أكتر محطة"; hours unavailable → the hours page and every hours line drop out and the recap still stands; ties → the earlier one, and the copy never says "the only"; very long names wrap and the title shrinks one step.

**The voice**: laughs with the student, never at them; about the road, sleep and the alarm clock — never grades, money, a rejected receipt, the company, the driver or other students; gender-neutral in every line; only their own data, so no ranking and no "top rider"; hours marked approximate; nothing is posted by the app, and the poster carries only first name, line and `Basak.app`.

- **Form**: full-bleed pages in the brand's own colours (ink, teal, sky, mint, and one light page), one idea each, segmented progress on top, tap to advance, close at any time. The poster has **شارك** (system share sheet) and **حفظ الصورة**; its colour theme varies so two friends' posters do not look the same. The app already renders a receipt to an image and has `share_plus` and `gal`.
- **Where the numbers come from**: days, weekdays, the shape of the term, runs, favourite times and returns are all in the student's own ride confirmations, readable today for a date range (`DailyRideRepository.getRides`); stop, line, university and college come from the subscription and the profile. **Hours are an estimate** — confirmed rides × the timetable's trip length — and the page says so. The trip's arrival time is not in what the student app reads today, so hours need one more column in an existing read or, cleaner, one small RPC returning the whole recap: a data-layer change, **not** part of the presentation-only plan.
- **Confirmed vs. boarded**: the recap counts what the student confirmed in the app. Counting actual scans would be truer but students cannot read scan events today.
- **Where the copy lives**: about 150 short lines once every page, tier, title and college is written. Shipping them inside the app is simplest; keeping them on the server lets you add a joke or a college without a release. Either way they are content to write and approve, not screens.

### I.2 Rating

One sheet, shown at a good moment (after the recap, or some days after an activation — never during payment or after a rejection, and not more than once per term). It says where the rating goes and why it helps, with one button: **"قيّم على App Store"** on iPhone, **"قيّم على Google Play"** on Android, and "ليس الآن".

- The button should hand over to the **store's own review dialog**, so the student rates without leaving the app. That needs the `in_app_review` package (not in `pubspec.yaml` today); without it the button opens the store page with `url_launcher`, which is already bundled.
- **No stars and no "do you like the app?" question of our own.** Apple's review guidelines disallow custom review prompts and Google Play's in-app review rules forbid asking an opinion before showing the rating card; filtering unhappy users away from the store is the thing both are written against. The sheet is drawn to stay on the right side of that — worth checking against the current store rules before release.
- A permanent **"قيّم التطبيق"** row under حسابي → التطبيق is always allowed and should exist either way.

### I.3 Update

| State | What the student sees |
|---|---|
| Optional update | A sheet over Home: "تحديث جديد متاح", the version, up to three lines of what is new, "تحديث الآن" and "لاحقاً". Shown once per version |
| Required update | A full screen: "حدّث التطبيق للمتابعة", why, "إصدارك 2.3.1 · المطلوب 2.5.0", and "تحديث من App Store / Google Play". **The card stays reachable** — "عرض بطاقتي" — because it works offline and a student must never be stranded at the bus door by an update |

- The installed version is known (`package_info_plus`) and the store can be opened (`url_launcher`). What does not exist is **where the minimum and latest versions, and the "what's new" lines, come from** — a small settings row or RPC on the server. Until that exists neither screen can appear.
- The same two states apply to the supervisor app; a required update there has no card to fall back on.

---

## J. Design system, second edition

After the card, the supervisor app and the recap were drawn, the screens used more than the first system boards described. Three boards were added to row 01 and this section is their text.

### J.1 What was missing

- **29 of the 49 colours on the canvas** were not on the tokens board. Nine are core values that were simply never listed (pressed teal `#004F6E`, track `#D5E0E7`, grabber `#C3D1DA`, disabled `#9DB0BB`, avatar tint `#D6EBF5`, photo fill `#8DBFD6`, outline on ink `#3E6478`, badge `#C8372D`, QR ink `#102A3A`). Four are status accents (mint `#5BD4A0`, pending ring `#E0B25A`, open dot `#F2C46B`, refused frame `#F2867E`). Four belong to the scanner's dark surface. Eight form an **expressive palette used by the recap only** — kept out of the working screens, where teal means an action and ink means the pass.
- **Eight type roles**: poster numeral 144/150·700, story title 68/78·700, total 48/56·600, poster title 40/48·700, sheet title 20/30·600, row title 16/26·600, body small 14/22·400, tab label 11/16·400–600. Weight 700 appears only in the recap; Regular, 500, 600 and 700 are the four Readex Pro files the app already bundles (300 is not, and is not used).
- **Motion and touch** had no numbers: press 120 ms; fades 200 ms; sheets 280 in / 200 out; pages, pager and tabs 350 ms `easeInOutCubic` (the app's current value); boarded result closes after 2 s; toast 3 s; recap advances on tap only. Haptics: selection for tabs and chips, medium for boarded, light for a repeat scan, heavy for refused.
- **Layout**: 20 at the sides, 16 between sections, 18–20 inside cards; 48 × 48 minimum tap target; text scale honoured from 1.0 to 1.3; nothing clips at 360 × 640.
- **Components** (board "Components, second set", each a widget in `core/ui`): `PhotoRing`, `FactGrid`, `InfoStrip`, `RadioCard`, `ProgressLine`, `ChipChoice`, `CountsHero`, `PagerDots`, `BarRow`, `StatTile`, `Meter`, `StopRow`, `ScanChrome`, `ResultHeader`, `StoryScaffold`, `TermPattern`, plus `RecapPoster`.

### J.2 Flutter mapping

| `core/theme` today | After |
|---|---|
| `AppColors.primary` #1E3A8A (navy), `secondary` #0D9488 | Removed — neither is in the product. `ink` and `teal` are |
| `babyBlue`, `babyBlueLight`, `babyBlueUltraLight`, `babyBlueDark` | Removed with the glass bar; `sky` stays for the pass |
| `textPrimary` #1E293B, `textSecondary`, `textMuted` | `ink` #17384A, `ink2`, `ink3` |
| `success` #10B981, `warning` #F59E0B, `error` #EF4444 | Text-safe tones with a tint each: #0A6B4A, #8A5300, #B3261E |
| 6 text styles | 15 roles in one `BasakText`; Flutter `height` = line ÷ size (28/38 → 1.357) |
| `ElevatedButton` theme: navy, radius 12, height 50 | `BasakButton`: teal, radius 16, height 54 |
| Input theme: white fill, 1 px border | Sunken fill, no border, 2 px teal ring on focus |
| 156 colour literals across screens | None; screens read the theme only |

- Tokens live in one `ThemeExtension<BasakColors>` plus `BasakSpace`, `BasakRadius`, `BasakMotion` constants; the Dart name of every colour is printed beside its swatch on the board.
- **Direction**: `EdgeInsetsDirectional`, `AlignmentDirectional`, `TextAlign.start` — no left or right. Times, phone numbers and codes are wrapped in an LTR `Directionality`.
- **No `BackdropFilter`** in lists or bars: it is the most expensive effect on mid-range Android and the reason option C below drops the blur.
- **Two shadows only**: card (0 1 2 at 5%) and floating (0 12 32 at 20–45%).
- **Icons**: Lucide through `app_icons.dart`; the new glyphs (megaphone, send, scan, share, download, star, sparkles, flashlight, flip camera, calendar, history, ban, copy) are added to the tree-shaken font.
- **Checks**: a golden test per component at 360 and 390 wide, text scale 1.0 and 1.3.

### J.3 The tab bar — decided: C

**Decided on 2026-10-09: option C.** The bar in the app (`FloatingGlassNavBar`) and the bar first drawn on the canvas were different, and the canvas version had been chosen before yours was measured properly. Board "Tab bar options" puts three on the same screen; every screen on the canvas now carries C.

| | A · In the app today | B · On the canvas so far | C · Proposed |
|---|---|---|---|
| Shape | Floating pill, 64 high, 20 from the edges, 82% white + 18-sigma blur | Docked edge to edge, 84 high | Your floating pill kept at its 64 height, 16 from the edges, solid white, one soft shadow |
| Selected tab | Icon #7EC8E3 on #E0F2FE = 1.6 : 1; label 10.5 px = 2.7 : 1 | Ink, 11 px, weight 600 = 12 : 1 | As B; the card keeps its ink pill |
| Other tabs | Label 9.5 px at 70% = 2.7 : 1 | 11 px = 5.2 : 1 | 11 px = 5.2 : 1 |
| On scroll | Collapses to one circle; the other tabs need two taps | Nothing | Labels fold away, pill drops to 52; all tabs stay one tap away |
| Cost | `BackdropFilter` over a scrolling list; baby-blue is outside the brand set | None; loses the floating look | No blur; `collapseOnScroll` is reused as is |

**Why C.** It keeps what is recognisably yours — a floating pill that reacts to scrolling — and fixes the three things the numbers show: contrast, label size, and the card disappearing behind a collapsed circle exactly when a student scrolls and then needs it at the bus door. In Flutter this is a restyle of the existing widget: drop the `BackdropFilter`, swap the baby-blue values for `ink` and `teal`, raise the labels to 11 px, and change the collapsed state from a circle to the label-less pill. `floating_nav_bar_test.dart` needs its expectations for the collapsed state and for the labels «الاشتراك» → «اشتراكي» and «مسح QR» → «مسح» updated in the same PR.

---

## K. Sign in with Face ID or fingerprint

Five artboards at the end of row 02, plus a switch on both account screens. The app has no biometric support today — no `local_auth` in `pubspec.yaml`, no Face ID usage text in `Info.plist`, no biometric permission in the Android manifest — so this is designed here and built later; it touches the auth layer and is **not** part of the presentation-only plan.

| Screen | What it is |
|---|---|
| Returning sign-in · iPhone | The student's photo, "أهلاً بعودتك، سارة", their phone number with the middle hidden, one large Face ID glyph, **الدخول بـ Face ID**, and "الدخول بكلمة المرور" always visible under it. "حساب آخر" at the top |
| Returning sign-in · Android | The same screen with the fingerprint glyph and **الدخول بالبصمة**, and one line: "أو بالوجه، حسب ما فعّلته في إعدادات هاتفك." |
| The phone's own prompt | The app draws nothing at this moment. iPhone shows Face ID, Android shows its biometric sheet; the board only marks where it sits |
| Not recognised | The glyph and the sentence turn amber: "لم يتعرّف الهاتف عليك. حاول مرة أخرى، أو ادخل بكلمة المرور." Two buttons: حاول مرة أخرى, الدخول بكلمة المرور |
| Offer after first sign-in | A sheet, once, after the first sign-in with a password: "دخول أسرع بـ Face ID؟" — what it does, that the face or fingerprint never leaves the phone, **تفعيل** and "ليس الآن" |
| Account | A switch under التطبيق, "الدخول بـ Face ID" (named after whatever the phone has), to turn it off again |

- **Naming follows the phone.** iPhone: "Face ID" or "Touch ID" by model. Android: "البصمة" when only a fingerprint is enrolled, "البصمة أو الوجه" otherwise — Android reports how strong a method is, not always which one, so the copy does not promise more than it knows.
- **The password is never hidden.** It is on the screen before, during and after a failed attempt; after the system locks biometrics out (too many tries) the screen falls back to the ordinary sign-in.
- **If the phone's biometrics change** (a new face or finger is added), the stored sign-in is dropped and the student signs in once with the password to turn it back on. Said in one line on the sign-in screen.
- **Where it applies — a decision.** Today the app keeps the student signed in, so a sign-in screen is rare. I have drawn biometrics as a faster **sign-in** (after signing out or an expired session) and **not** as a lock on every launch: the card must open instantly at the bus door, and a lock in front of it would cost seconds there. If you do want a lock on launch, the card should stay outside it.
- **Supervisors** get the same screen; their sign-in has no self-service password reset, so the fallback line reads "ادخل بكلمة المرور، أو تواصل مع شركتك."
- **Build notes for later**: `local_auth` for the prompt; the session or refresh token kept in `flutter_secure_storage` (already bundled) and released only after a successful check; `NSFaceIDUsageDescription` on iOS; `USE_BIOMETRIC` and a `FlutterFragmentActivity` on Android. Devices with no biometrics enrolled never see the offer.

---

## L. iPhone and Android

One Flutter codebase, one set of boards drawn at 390 wide. Board "iPhone and Android" (row 01) shows the two phones' top and bottom edges with the floating tab bar, and lists seventeen points where the platforms differ with the rule the design follows on each. The ones that change code:

- **Safe areas**: one `SafeArea` per screen; the tab bar adds the bottom inset itself, as `FloatingGlassNavBar` already does (`bottomPadding + 8`).
- **Back**: every pushed page keeps its round back button; system back closes a sheet first. Today only the purchase flow has a `PopScope` — the receipt upload needs one too.
- **Permissions, asked at the moment of use**: camera, photos, notifications, contacts (saving the supervisor's number), and biometrics later. The app explains in its own sheet before the phone asks. Today students get the phone's bare notification question three seconds after their first Home; supervisors already get the explainer.
- **Info.plist** says the camera is "لمسح بطاقة الطالب"; it is also used for receipts and the profile photo, and App Store review reads that string. There is no Face ID usage text yet.
- **Wallet**: Apple's own `PKAddPassButton` on iPhone (already used), Google's official button on Android (today a hand-drawn pill).
- **Rotation and tablets**: the app is not locked to portrait and runs on iPad. The canvas is portrait; on wider screens the content column stops at 480 and centres. Locking phones to portrait is a one-line decision that needs your yes.
- **Targets**: iOS 15.5, Android minSdk 24. Light theme only, locale fixed to Arabic.
- **Smallest screens**: 360 × 640 and iPhone SE; grids keep three columns, the card's QR shrinks last.

## M. Coverage — what the app has that the canvas did not

The app's code was read screen by screen against the boards (2026-10-09). Row 11 of the canvas holds what was missing; board "Coverage" lists every remaining state and message with its exact words.

**Drawn now (18)**: password recovery in two steps (the code comes from the company's admin, valid 30 minutes — not by SMS), the forced password change after an admin reset, the "account not for this app" screen, the photo source sheet and the crop-in-a-circle screen, the ride question when confirmation has not opened and when it has closed, the in-app push banner, the push explainer sheet, the supervisor contact sheet (call, WhatsApp, save contact, copy), an empty catalogue for the university, the one-day cash subscription, a payment screen with no transfer details, the five-attempts-used screen, "تعديل بياناتي" (college, email, birth date), the delete-account dialog, and an unavailable card.

**Specified on the Coverage board, carried by existing components**: inline field errors (phone already registered, wrong credentials), picker empties, the ride card's two blocked sentences, line and period unavailability, "انتهى دون دفع", the unreadable-image error, the remaining-attempts line, alert search and "older" paging, eight supervisor states (no confirmations, stopped line, skipped stop, no camera, failed check, disabled send, empty month, sign-out question) and thirty-odd result toasts.

**New on the canvas — to be built, not restyled**: the separate entry screen and supervisor sign-in; four-step sign-up with a college sheet; biometric sign-in; confirming a ride in a sheet; the card's details sheet and today's ride; the station and review sheets; the alert detail sheet; help & support, language, the phone-notifications row, links to terms and privacy; the supervisor's line and trip sheets and rider actions; recap, rating and update.

**In the app today, different on the canvas — each needs a yes or no**: "تذكّر رقمي" removed; supervisor notification categories replaced by the phone's setting; the explainer before the push question for students too; portrait only; the camera usage text; one rule for the sign-out question (students are not asked today, supervisors are).

---

## Still open — needs a product decision

1. **College list.** Sign-up now asks for the college through a searchable sheet with "كلية أخرى". The value is still saved as text, so nothing changes in the backend — but where does the list come from: a fixed list in the app, or one list per university managed from the dashboard? And is the college required?
2. **Help & support channels.** The sheet is drawn for a configurable list. What goes in it, and who owns each entry — the platform, or each transport company?
3. **Supervisor entry.** The sign-in screen no longer has طالب / مشرف tabs; supervisors enter from "دخول المشرفين" on the welcome screen. Confirm, or keep the switch on the sign-in screen.
4. **"تذكّر رقمي".** The checkbox is gone and the phone number is remembered by default. Confirm, or keep it as an explicit choice.
5. **Reminder-days explainer.** Today's alerts screen has a card explaining which days get a ride reminder. It is not in the new inbox; the week strip on Home covers the same days. Drop it, or keep it as a line in the ride sheet?
6. **Wallet button.** Drawn generically; the build must use the official Apple / Google Wallet badges. No decision needed unless you want the button removed.
7. **Supervisor tabs.** Four instead of five: الملخص becomes a page under حسابي. Confirm, or keep it as a fifth tab.
8. **Scan auto-return.** A successful scan closes by itself after two seconds so the supervisor does not tap once per rider. Confirm the idea and the delay.
9. **Supervisor notification switches.** Drawn like the student side — no in-app categories, only the phone's own setting. The student rule was explicit; for supervisors it is my assumption.
10. **Calling a rider.** The manifest already shows phone numbers; the rider sheet adds اتصال / واتساب / نسخ. Confirm this is wanted from a privacy point of view.
11. **Details on the student card.** The phone number is in "كل التفاصيل", not on the face. Say if the supervisor should see it without a tap, or not at all.
12. **What a scan is attributed to.** Today the scanner tab sends no trip (each scan goes to the student's own trip) and the Trips button pins one. The canvas draws one scanner pinned to the chosen trip. Confirm, or keep each student's own trip as the default.
13. **Bus capacity.** Home shows riders per trip; it does not say how many buses that needs, because the backend has no capacity. If you want "38 من 50" or "يحتاج باصين", say where the capacity comes from: one number per company, per line, or typed by the supervisor on the phone.
14. **Recap data.** Hours need the trip length, which the student app does not read today. Approve one small RPC for the recap (or one more column in an existing read), or drop the hours page and keep the rest.
15. **Recap copy.** Every joke, title and college line on the canvas is my sample. They need your approval and probably your rewrite — and a decision on where they live: inside the app, or on the server so they can change without a release.
16. **Rating.** Add `in_app_review` for the store's own dialog, or only open the store page? And when should the sheet appear?
17. **Update.** Where do the minimum version, the latest version and the "what's new" lines live — a settings row in the dashboard?
18. **Specialisation.** You asked for the recap to follow the student's major. Only university and college are stored. Add an optional "التخصص" at sign-up or in the profile (a backend field), or stay with the college?
19. ~~**Tab bar.**~~ Decided: C, the floating pill (J.3).
20. **Biometrics: sign-in only, or a lock on every launch?** Drawn as sign-in only, so the card is never behind a lock. Confirm — and confirm it is wanted for supervisors too. It needs `local_auth` and a change in the auth layer.
21. **Portrait only?** The app rotates and runs on iPad today; the canvas is portrait. Lock phones to portrait, or design landscape and tablet layouts?
22. **The six differences in section M.** "تذكّر رقمي", supervisor notification categories, the push explainer for students, the camera usage text, the sign-out question — each needs a yes or no.
23. **One-day cash subscription.** Drawn as a third period tile, as the app offers it today. Confirm it stays.

### Ideas noted, not drawn

- **Expiring soon.** A slim row under the Home pass in the last two weeks ("ينتهي اشتراكك بعد 9 أيام · جدّد"), from the existing `endDate`.
- **Open the bank app.** A button next to the InstaPay address that opens InstaPay directly, if a reliable link exists on both platforms.
- **Live clock on the card.** A ticking time on the student card, so a screenshot cannot pass a visual check. Presentation only.
- **Student photo in the scan result.** Needs the photo path in `lookup_student_by_qr`; until then the supervisor compares with the photo on the student's phone.
- **Manual boarding and undo.** Marking a rider as boarded from the manifest when a phone is dead, and undoing a wrong scan. Needs a new RPC.
- **Queue offline scans.** Record a scan made offline and send it when the connection returns. Needs a write queue the app deliberately does not have today.
- **Ready-message wording.** «الحافلة» → «الباص» and "نحو 10 دقيقة" → correct plurals, in the server's template seed.
