# Basak admin web — how to draw a page

Everything is a Node script. `kit.mjs` holds the shared parts; you write one generator per batch that imports it and calls `board()` for each artboard. Staging only: nothing here is published or committed.

```
admin-canvas2/
  build2/kit.mjs            the kit (do not fork it; add to it if a part is missing and say so)
  build2/gen-foundation.mjs foundation boards (f-system, f-components, f-shell, f-today) — read f-today.mjs as the worked example
  build2/serve.mjs          static server + height report      node serve.mjs 8793   (background; stop it when done)
  build2/shot.mjs           measure / render with headless Edge
  build2/mont.py            python mont.py out.png A B C  → boards side by side
  project/                  <Name>.dc.html, boards*.json, renders/<Name>.png, support.js
```

## The loop

```
node gen-<batch>.mjs                     # writes project/*.dc.html + build2/measure/*.dc.html
node shot.mjs measure <batch>            # real heights → heights.<batch>.json
node gen-<batch>.mjs                     # again, now with the measured heights
node shot.mjs render <batch> [Name…]     # project/renders/<Name>.png — open every one
```

A generator:

```js
import { board, finish, shellDesktop, shellPhone, dataTable, recordList, recordCard, btn, status, cell2, ltr } from './kit.mjs';

board('AdmStudents', { row: 'D', w: 1440, title: 'Admin web · Students · Desktop', tab: 'لوحة الشركة · الطلاب',
  body: (size) => shellDesktop({ size, active: 'students', title: 'الطلاب', sub: '…', actions: btn('إضافة طالب', { icon: 'plus' }),
    body: dataTable({ … }) }) });
board('AdmStudentsPhone', { row: 'D', w: 390, title: 'Admin web · Students · Phone',
  body: (size) => shellPhone({ size, active: 'students', body: recordList({ … }), bottomBar: btn('إضافة طالب', { phone: true, full: true }) }) });

finish({ batch: 'people', rows: { D: 'Students', E: 'Receipts' } });   // → project/boards.people.json
```

- `body(size)` gets `"width:…px;height:…px"`; the shells put it on the `data-root` element. Height is measured unless you pass `h`; never below `min` (900 desktop, 1000 tablet, 844 phone).
- Overlays (`scrim(...)`) are absolutely placed and are not measured: give the board a `min` tall enough.
- Never write `{{` or `}}` in a board (the canvas runtime reads them as placeholders); `board()` throws if you do.
- Phone boards: 390 wide, no `radius`, no status bar, no tab bar. Desktop boards: 1440. Tablet (only where it differs): 834.
- Every board is `is_interactive: false` unless it has working controls.
- File prefix `Adm`. Phone form of a page = same name + `Phone`; a state = name + the state (`AdmStudentsEmpty`).

## Kit exports

| Part | Function |
|---|---|
| Shells | `shellDesktop({size, active, role, title, sub, breadcrumb, actions, meta, back, body, overlay, offline, badges, who})`, `shellTablet(o)`, `shellPhone({size, active, role, title, sub, actions, back, body, bottomBar, overlay, offline})`, `navDrawerPhone({active, role})`, `sidebar`, `rail`, `topbar`, `topbarPhone`, `workspaceBar`, `companySwitcher`, `searchBox`, `bottomBar`, `scrim(inner, 'end'\|'center'\|'bottom'\|'start')` |
| Page | `pageHeader({title, sub, actions, back, meta, phone})`, `sectionHead(title, {meta, end, phone})` |
| Numbers | `statCard({label, value, unit, hint, icon, bar, href, phone})` |
| Attention | `attentionRow({count\|icon, tone, title, sub, action, primary})`, `attentionList(rows, {phone})` |
| Data | `dataTable({columns, rows, toolbar, bulk, pagination, selectable, foot, empty, tablet})`, `tableToolbar`, `pager`, `chip`, `cell2`, `checkbox` |
| Data on a phone | `recordList({toolbar, cards, pagination, empty})`, `recordCard({title, sub, end, stats, fields, actions})` |
| One record | `sidePanel({title, sub, meta, body, footer})`, `infoRows([[label, value]])` |
| Confirming | `dialog({title, body, actions: [cancel, confirm], tone, icon, phone})` |
| Forms | `formSection({title, help, body, footer, phone})`, `fieldRow([…], {phone})`, `field({type, label, value, placeholder, help, error, optional, state, phone, options, on})` — types `text password tel search select date time money textarea toggle radio checkbox` |
| Steps | `stepper({steps: [{label, sub, state, body}], vertical, phone})` |
| Status | `status('active'\|'review'\|'unpaid'\|'rejected'\|'soon'\|'ended')`, `state('on'\|'off'\|'suspended'\|'archived'\|'open'\|'done'\|'cancelled'\|'failed'\|'scheduled'\|'sent', label?)`, `badge(text, tone)`, `countBadge(n)` |
| Buttons | `btn(label, {kind, icon, iconEnd, phone, sm, full, href, state})` kinds `primary secondary outline tonal danger dangerQuiet link`; `iconBtn(icon, label, {phone, sm, dot})` |
| Feedback | `toast({tone, text, action, phone})`, `note({tone, title, text, action})`, `emptyState({icon, title, text, action, phone, card})`, `errorState({title, text, phone, card})`, `skeleton('stat'\|'list'\|'table'\|'cards'\|'form'\|'text', {rows, cols})`, `offlineBar({phone})` |
| Small | `ico(name, size)` (`ICONS` lists the names), `ltr(s)`, `money(n)`, `time('7:30', 'ص')`, `receiptImg(w, h)`, tokens `C T R CARD SHADOW FONT FOCUS`, `NAV`, `navFor(role)`, `navItem(role, id)`, `WHO`, `BADGES` |

Roles: `'company'` (company admin), `'platform'` (super admin on the platform), `'workspace'` (super admin inside a company: same navigation as `company` plus the ink return bar with the switcher).

## Navigation — the single source (`NAV` in kit.mjs)

`active` is the `id`. The page title is the label, exactly.

**Company admin** — `/c/:companyId/<slug>`

| Group | Label | id = slug | Was |
|---|---|---|---|
| — | اليوم | `today` (slug empty) | نظرة عامة |
| كل يوم | الإيصالات (count) | `receipts` | فحص الإيصالات |
| | طلبات كلمة المرور (count) | `password-requests` | new page; a card on top of الطلاب |
| | الإشعارات | `notifications` | same |
| الطلاب والفريق | الطلاب | `students` | list, add student, invitations, name-fix requests |
| | المشرفون | `supervisors` | same |
| | مديرو الشركة | `team` | فريق الإدارة |
| الخطوط والرحلات | الخطوط | `lines` | الخطوط والمحطات |
| | تأكيد الركوب | `ride-confirmation` | new page; 7th card of إعدادات الشركة (vote hours, reminder, days off) |
| الاشتراكات والمدفوعات | مواعيد الاشتراك | `subscription-periods` | إعدادات الشركة cards 1–4 + the daily switch |
| | وسائل الدفع | `payment-methods` | same |
| | الإيرادات | `reports` | التقارير المالية |
| هوية الشركة | بطاقة الطالب | `wallet-card` | بطاقة المحفظة |
| | بيانات الإيصال | `receipt-details` | new page; 5th card of إعدادات الشركة |

**Super admin · platform** — `/platform/<slug>`

| Group | Label | id | slug | Was |
|---|---|---|---|---|
| — | اليوم | `p-today` | (empty) | نظرة عامة على المنصة |
| يحتاج قرارك | طلبات تصحيح البيانات (count) | `p-corrections` | `corrections` | new page; queue on top of كل الطلاب |
| | طلبات كلمة المرور (count) | `p-password-requests` | `password-requests` | new page; inside the overview |
| الشركات | الشركات | `p-companies` | `companies` | كل الشركات (+ «شركة جديدة» in steps) |
| | مديرو الشركات | `p-admins` | `admins` | same |
| الطلاب | كل الطلاب | `p-students` | `students` | read-only directory |
| | إشعارات المنصة | `p-notifications` | `notifications` | same |
| إعدادات المنصة | الجامعات والكليات | `p-universities` | `universities` | الجامعات والوجهات |
| | الإعدادات الافتراضية | `p-defaults` | `defaults` | same |
| | إصدارات التطبيق | `p-app-versions` | `app-versions` | same |

**Super admin inside a company** — `role: 'workspace'`: the company tree, plus the ink bar «العودة إلى المنصة» · «أنت الآن داخل شركة» · company switcher. Controls only the super admin sees get `badge('لمدير المنصة فقط')`.

## Rules every page follows

1. **Width behaviour.** Desktop 1440: sidebar 264 + top bar 64, content padding 32, 12 columns / 24 gutter, max 1200. Tablet: rail 72, padding 24, tables drop `hideTablet` columns. Phone 390: top bar 56, padding 16, one column.
2. **Spacing.** Steps 4 8 12 16 24 32 only. 24 between page sections, 12 between a `sectionHead` and its card, 16 between fields. Radii: 10 controls, 14 record cards / notes / toasts, 16 cards and tables, 20 dialogs.
3. **Tables.** Always `dataTable`: toolbar (search → filter chips with counts → count → sort), 56-px rows, first column is the record's name (`cell2` for a second line), status through `status()`/`state()`, at most one `sm` button + one `⋮` per row, 25 rows a page with `pagination` («1–25 من 442»); no pagination under 26 rows. Row click opens the side panel. Bulk actions only where they are real (students, receipts): `selectable` + `bulk`. Draw 25 rows on the main desktop board of each list page.
4. **Phone lists.** `recordList` + `recordCard` with the same fields in the same order as the columns; the card opens the record's page (`shellPhone({ back: 'الطلاب' })`).
5. **Panel vs dialog.** Read or edit one record → `sidePanel` (480, end side; a full page on a phone). A yes/no about one action → `dialog` (centred 480; bottom-anchored on a phone). Dialog: title is the question, body says exactly what will and will not happen with the real numbers, the confirm button repeats the verb, cancel is «رجوع», at most one field. Destructive or money-affecting actions always get one. Never `confirm()` / `prompt()`, never a typed phrase.
6. **Primary action.** One per page. Desktop/tablet: last at the end side of the page header; a form's save is in its `formSection` footer at the end side. Phone: `bottomBar`, full width, 48 high. In a side panel: footer, main action at the end, destructive at the start.
7. **Forms.** A column of `formSection`s, each saved by its own named button («حفظ بيانات الخط»). No switch or select that saves on touch when money, status or students are affected. No pre-filled prices. Errors under the field in plain Arabic (`error:`); never raw server text.
8. **Things built in steps** (new line, new company, first-run setup): `stepper`; nothing saved until the last step; closing asks first.
9. **States.** Every page board set includes: many (realistic heavy data), one, none (`emptyState` with the button that fills it), loading (`skeleton`), error (`errorState`), and offline where the page writes.
10. **Words.** Use the glossary on `AdmSystem`. Arabic only, Western digits, `time()` / `money()` / `ltr()` for times, money, phones and codes. One purpose per page: do not repeat a fact that another page owns.
11. **Data.** Draw only what the audit (`admin-audit.md`) says exists or is derivable; list anything needing a new query in your report.
