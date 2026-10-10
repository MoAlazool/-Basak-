import {
  board, shellPhone, topbarPhone, pageHeader, sectionHead, statCard, attentionList, dataTable, recordCard, recordList,
  sidePanel, infoRows, dialog, scrim, formSection, fieldRow, field, stepper, badge, status, state, countBadge, chip,
  btn, iconBtn, toast, note, emptyState, errorState, skeleton, offlineBar, bottomBar, cell2, ltr, money, time, ico, ICONS,
  receiptImg, C, T, R, FONT, CARD, STATUS, STATE,
} from './kit.mjs';
import { ATTN } from './f-today.mjs';

const H2 = 'margin:0;font-size:24px;line-height:32px;font-weight:600';
const NOTE = `margin:0;font-size:14px;line-height:22px;color:${C.ink2};max-width:900px`;
const TAG = `font-size:12px;line-height:18px;font-weight:600;color:${C.ink3};letter-spacing:.04em;text-transform:uppercase`;
const DW = 898; // desktop demo width; the phone demo is 390
/** One component: its desktop form and its phone form next to each other. */
const pair = (title, text, desk, phone, o = {}) => `<section style="display:flex;flex-direction:column;gap:16px">
<div style="display:flex;flex-direction:column;gap:4px"><h2 style="${H2}">${title}</h2><p style="${NOTE}">${text}</p></div>
<div style="display:grid;grid-template-columns:${DW}px 390px;gap:24px;align-items:start">
<div style="display:flex;flex-direction:column;gap:8px;min-width:0"><div style="${TAG}">${o.deskLabel ?? 'Desktop and tablet'}</div><div dir="rtl" style="background:${C.ground};border-radius:16px;${o.bare ? 'overflow:hidden' : 'padding:24px'};display:flex;flex-direction:column;gap:16px;color:${C.ink}">${desk}</div></div>
<div style="display:flex;flex-direction:column;gap:8px;min-width:0"><div style="${TAG}">${o.phoneLabel ?? 'Phone web · 390'}</div><div dir="rtl" style="background:${C.ground};border-radius:16px;${o.bare ? 'overflow:hidden' : 'padding:16px'};display:flex;flex-direction:column;gap:12px;color:${C.ink}">${phone}</div></div>
</div>
</section>`;
const cap = (s) => `<div dir="ltr" style="${TAG};font-weight:500;text-transform:none;letter-spacing:0;margin-top:4px">${s}</div>`;
const page = (title, lead, sections) => (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:64px">
<header style="display:flex;align-items:flex-end;justify-content:space-between;gap:40px;padding-bottom:28px;border-bottom:1px solid ${C.hair}">
<div style="display:flex;flex-direction:column;gap:8px"><div style="font-size:13px;line-height:20px;font-weight:500;color:${C.teal};letter-spacing:.08em;text-transform:uppercase">Basak · Admin web · 2026</div><h1 style="margin:0;font-size:44px;line-height:54px;font-weight:600">${title}</h1></div>
<p style="margin:0;max-width:560px;font-size:15px;line-height:24px;color:${C.ink2}">${lead}</p>
</header>
${sections.join('\n')}
</div>`;
const noRoot = (html) => html.replace('data-root ', '');

/* ── Data ───────────────────────────────────────────────────────── */
const STUDENTS = [
  ['منة الله إبراهيم عبد الرازق', '010 2345 6789', 'جامعة دمياط · التجارة', 'الزرقا · كوبري السرو', 'الفصل الأول', 'active'],
  ['عبد الرحمن محمد السيد الشربيني', '011 3456 7890', 'جامعة حورس · الصيدلة', 'دمياط الجديدة · موقف الحي الثالث', 'الفصلان معاً', 'review'],
  ['يوسف أحمد عبد الفتاح', '012 4567 8901', 'جامعة دمياط · الهندسة', 'الزرقا · شرباص', 'الفصل الأول', 'unpaid'],
  ['ملك حسام الدين مصطفى', '015 5678 9012', 'جامعة دمياط · الآداب', 'شربين · ميدان المحطة', 'الفصل الثاني', 'soon'],
  ['عمر خالد إسماعيل البنا', '010 6789 0123', 'جامعة حورس · طب الأسنان', 'دمياط الجديدة · كفر البطيخ', 'الفصل الأول', 'rejected'],
  ['سلمى طارق عبد الحميد', '011 7890 1234', 'جامعة دمياط · العلوم', 'الزرقا · السرو', 'الفصل الأول', 'ended'],
];
const more = iconBtn('dots', 'إجراءات أخرى', { sm: true });
const studentCols = [{ label: 'الطالب', sorted: 'asc' }, { label: 'الجامعة', w: 132, hideTablet: true }, { label: 'الخط والمحطة', w: 150 }, { label: 'الاشتراك', w: 116 }, { label: 'الحالة', w: 132 }, { label: '', w: 48, align: 'end' }];
const studentRow = (s, st) => ({ state: st, cells: [cell2(s[0], ltr(s[1])), cell2(s[2].split(' · ')[0], s[2].split(' · ')[1], { w: 400 }), cell2(s[3].split(' · ')[0], s[3].split(' · ')[1], { w: 400 }), s[4], status(s[5]), more] });
const FILTERS = [{ label: 'الكل', on: true, count: 442 }, { label: 'قيد المراجعة', count: 7 }, { label: 'بانتظار الدفع', count: 31 }, { label: 'إيصال مرفوض', count: 4 }];
const studentCard = (s, o = {}) => recordCard({ title: s[0], sub: ltr(s[1]), end: status(s[5]), fields: [['الجامعة', s[2]], ['الخط والمحطة', s[3]], ['الاشتراك', s[4]]], ...o });

/* ── Page header ────────────────────────────────────────────────── */
const headerPair = pair('Page header', 'pageHeader() — the page title equals its navigation label; one sentence under it; at most one primary action, last at the end side. On a phone the title lives in the sticky top bar and the primary action moves to the bottom bar.',
  `<div style="padding:24px;display:flex;flex-direction:column;gap:28px">${pageHeader({ title: 'الخطوط', meta: badge('8 خطوط', 'neutral'), sub: 'خطوط الشركة ومحطاتها ورحلاتها وأسعارها.', actions: `${btn('ترتيب الخطوط', { kind: 'outline', icon: 'sort' })}${btn('خط جديد', { icon: 'plus' })}` })}
${pageHeader({ title: 'منة الله إبراهيم عبد الرازق', back: 'الطلاب', meta: status('active'), sub: `${ltr('010 2345 6789')} · جامعة دمياط · التجارة` })}</div>`,
  `${noRoot(shellPhone({ size: 'width:390px;min-height:200px', active: 'lines', sub: 'خطوط الشركة ومحطاتها ورحلاتها وأسعارها.', body: `<div style="height:40px;border-radius:14px;border:1.500px dashed ${C.disabled}"></div>`, bottomBar: btn('خط جديد', { icon: 'plus', phone: true, full: true }) }))}
<div style="height:1px;background:${C.hair}"></div>
${topbarPhone({ title: 'منة الله إبراهيم عبد الرازق', back: 'الطلاب', search: false })}`, { bare: true });

/* ── Stat cards ─────────────────────────────────────────────────── */
const stats = (phone) => [
  statCard({ label: 'الذهاب', icon: 'aup', value: 512, unit: 'راكباً', hint: 'في 7 خطوط', phone }),
  statCard({ label: 'أكّدوا الركوب حتى الآن', icon: 'check', value: 512, unit: `من 718 · ${ltr('71%')}`, bar: 71, hint: `التأكيد مفتوح حتى ${time('6:00', 'ص')}`, phone }),
  statCard({ label: 'إيرادات هذا الفصل', icon: 'chart', value: '1,284,500', unit: 'ج.م', hint: 'من 286 اشتراكاً مدفوعاً', href: '#', state: phone ? undefined : 'hover', phone }),
];
const statPair = pair('Stat card', 'statCard() — one number, its unit and one sentence. Optional meter. A card that leads somewhere is a link with a chevron and a hover ring; otherwise it is not clickable. 0 is drawn as 0 with a sentence saying why, never a dash.',
  `<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px">${stats(false).join('')}</div>
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px">${statCard({ label: 'العودة', icon: 'adown', value: 0, unit: 'راكباً', hint: 'لم يؤكد أحد بعد' })}${skeleton('stat')}</div>${cap('zero · loading')}`,
  `<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px">${statCard({ label: 'الذهاب', icon: 'aup', value: 512, unit: 'راكباً', hint: 'في 7 خطوط', phone: true })}${statCard({ label: 'العودة', icon: 'adown', value: 486, unit: 'راكباً', hint: 'من الجامعات', phone: true })}</div>${stats(true)[1]}`);

/* ── Attention rows ─────────────────────────────────────────────── */
const attnPair = pair('Attention row', 'attentionRow() / attentionList() — one row per thing that needs the admin: a count or an icon, one sentence, one named button. Amber = waiting on you, red = broken for students, teal = a request. Only the first row\'s button is primary. With nothing waiting, one green row stays — the section never disappears.',
  `${attentionList(ATTN.slice(0, 3).map((a, i) => (i === 1 ? { ...a, state: 'hover' } : a)))}${cap('many')}${attentionList([ATTN[2]])}${cap('one')}${attentionList([])}${cap('none')}`,
  `${attentionList(ATTN.slice(0, 3), { phone: true })}${attentionList([], { phone: true })}`);

/* ── Table ↔ record cards ───────────────────────────────────────── */
const tablePair = pair('Data table ↔ record cards', 'dataTable() and recordList() / recordCard() draw the same records. Toolbar: search, filters as chips with counts, the count of what is shown, sort. Rows are 56 high; the whole row opens the record in a side panel; the ⋮ button holds the row\'s other actions. 25 rows a page (six drawn here). On a tablet the columns marked hideTablet go. On a phone each row is a card with the same fields in the same order, and the card opens the record\'s page.',
  `${dataTable({ caption: 'الطلاب', selectable: true, toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', searchW: 230, filters: FILTERS, count: '442 طالباً' }, columns: studentCols, rows: STUDENTS.map((s, i) => studentRow(s, { 1: 'hover' }[i])), pagination: { from: 1, to: 25, total: 442, page: 1, pages: 18 } })}
${cap('many · row 2 hovered')}
${dataTable({ selectable: true, bulk: { count: 3, label: 'تم تحديد 3 طلاب', actions: `${btn('إرسال إشعار لهم', { kind: 'outline', icon: 'megaphone', sm: true })}${btn('إزالة من الشركة', { kind: 'dangerQuiet', icon: 'trash', sm: true })}` }, columns: studentCols, rows: STUDENTS.slice(0, 4).map((s, i) => studentRow(s, i < 3 ? 'selected' : undefined)), pagination: { from: 26, to: 50, total: 442, page: 2, pages: 18 } })}
${cap('rows selected · the toolbar becomes the bulk bar · page 2 of 18')}
${dataTable({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', searchW: 230, searchValue: 'منة', filters: FILTERS.slice(0, 2).map((f) => ({ ...f, count: f.on ? 1 : 0 })), count: 'طالب واحد' }, columns: studentCols, rows: [studentRow(STUDENTS[0])] })}
${cap('one · no pagination under 26 rows')}
${dataTable({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', searchW: 230, searchValue: 'زياد منصور', filters: FILTERS.slice(0, 2).map((f) => ({ ...f, count: 0 })), count: 'لا نتائج' }, columns: studentCols, rows: [], empty: emptyState({ icon: 'search', title: 'لا يوجد طالب بهذا الاسم', text: 'جرّب جزءاً من الاسم أو آخر أربعة أرقام من الهاتف.', action: btn('مسح البحث', { kind: 'secondary' }) }) })}
${cap('none')}`,
  `${recordList({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', filters: FILTERS, count: '442 طالباً', sort: 'الاسم' }, cards: STUDENTS.slice(0, 3).map((s) => studentCard(s)), pagination: { from: 1, to: 25, total: 442, page: 1, pages: 18 } })}
<div style="height:1px;background:${C.hair};margin:8px 0"></div>
${recordList({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', searchValue: 'زياد منصور', count: 'لا نتائج' }, empty: emptyState({ card: true, phone: true, icon: 'search', title: 'لا يوجد طالب بهذا الاسم', text: 'جرّب جزءاً من الاسم أو آخر أربعة أرقام من الهاتف.', action: btn('مسح البحث', { kind: 'secondary', phone: true, full: true }) }) })}`);

/* ── Side panel ↔ full page ─────────────────────────────────────── */
const st = STUDENTS[1];
const panelBody = `${note({ tone: 'warning', title: 'إيصاله ينتظر مراجعتك', text: 'رفعه منذ ساعتين · المحاولة 2 من 5', action: btn('راجع الإيصال', { kind: 'tonal', sm: true }) })}
<div><div style="${T.label};font-weight:600;color:${C.ink2};margin-bottom:2px">الطالب</div>${infoRows([['رقم الهاتف', ltr(st[1])], ['الجامعة', st[2]], ['تاريخ التسجيل', '14 سبتمبر 2026']])}</div>
<div><div style="${T.label};font-weight:600;color:${C.ink2};margin-bottom:2px">الاشتراك</div>${infoRows([['النوع', 'الفصلان معاً'], ['الخط والمحطة', st[3]], ['الرحلات', `ذهاب ${time('7:30', 'ص')} · عودة ${time('3:00', 'م')}`], ['المبلغ', money(8000)], ['الحالة', status('review')]])}</div>`;
const panelFoot = `${btn('إزالة من الشركة', { kind: 'dangerQuiet', icon: 'trash' })}<span style="flex:1"></span>${btn('طلب تصحيح الاسم', { kind: 'secondary' })}`;
const panelPair = pair('Side panel ↔ full page', 'sidePanel() — one record, read or edited without leaving the list. 480 wide at the end side, full height, its own scroll, actions pinned at the bottom (destructive at the start side, the main one at the end). The row behind stays marked. Escape or the scrim closes it. On a phone the same content is a page: a back arrow in the top bar, the actions in the bottom bar.',
  `<div style="position:relative;height:660px;overflow:hidden"><div style="padding:24px">${dataTable({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', searchW: 230, filters: FILTERS.slice(0, 2), count: '442 طالباً' }, columns: studentCols, rows: STUDENTS.concat(STUDENTS.slice(0, 3)).map((s, i) => studentRow(s, i === 1 ? 'open' : undefined)) })}</div>${scrim(sidePanel({ title: st[0], meta: status('review'), sub: 'طالب في خط دمياط الجديدة', body: panelBody, footer: panelFoot }), 'end')}</div>`,
  noRoot(shellPhone({ size: 'width:390px;min-height:660px', active: 'students', title: st[0], back: 'الطلاب', gap: 16, body: `<div>${status('review')}</div>${note({ tone: 'warning', title: 'إيصاله ينتظر مراجعتك', text: 'رفعه منذ ساعتين · المحاولة 2 من 5' })}
<div style="${CARD};padding:4px 16px">${infoRows([['رقم الهاتف', ltr(st[1])], ['الجامعة', st[2]], ['النوع', 'الفصلان معاً'], ['الخط والمحطة', st[3]], ['المبلغ', money(8000)]], { labelW: 104 })}</div>
${btn('طلب تصحيح الاسم', { kind: 'outline', phone: true, full: true })}${btn('إزالة من الشركة', { kind: 'dangerQuiet', icon: 'trash', phone: true, full: true })}`, bottomBar: btn('راجع الإيصال', { phone: true, full: true }) })), { bare: true });

/* ── Dialog ↔ bottom panel ──────────────────────────────────────── */
const dlg = (phone) => dialog({ phone, tone: 'danger', icon: 'power', title: 'إيقاف خط شربين؟',
  body: `<span>لن يستطيع طلاب جدد الاشتراك فيه، ولن يظهر في التطبيق.</span><span>المشتركون الحاليون (112 طالباً) يبقى اشتراكهم كما هو حتى نهايته. يمكنك تشغيل الخط مرة أخرى في أي وقت.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('إيقاف الخط', { kind: 'danger', phone, full: phone })] });
const dlg2 = dialog({ tone: 'success', icon: 'check', title: 'قبول إيصال منة الله إبراهيم؟', body: `<span>يصير اشتراكها في الفصل الأول ${'<b style="font-weight:600;color:' + C.ink + '">نشطاً</b>'} ويُضاف ${money(4500, { unit: 13 })} إلى الإيرادات. يصلها إشعار بذلك.</span>`, actions: [btn('رجوع', { kind: 'secondary' }), btn('قبول الإيصال', {})] });
const dialogPair = pair('Dialog ↔ bottom panel', 'dialog() — every destructive or money-affecting action is confirmed. The title is the question, the body says exactly what will and will not happen with the real numbers, the button repeats the verb; cancel is always «رجوع». Never a browser confirm or prompt. At most one field (a reason). On a phone it is a full-width panel anchored to the bottom with stacked buttons, the confirming one first.',
  `<div style="position:relative;height:620px;overflow:hidden">${scrim(`<div style="display:flex;flex-direction:column;gap:32px">${dlg(false)}${dlg2}</div>`, 'center')}</div>`,
  `<div style="position:relative;height:620px;overflow:hidden">${scrim(dlg(true), 'bottom')}</div>`, { bare: true });

/* ══ Board 2 ════════════════════════════════════════════════════════ */
const formFields = (phone) => `${fieldRow([field({ label: 'اسم الخط', value: 'شربين', phone }), field({ type: 'money', label: 'سعر الفصل الأول', value: '', placeholder: 'اكتب السعر', error: 'اكتب سعراً أكبر من صفر، أو أوقف هذا الاشتراك.', phone })], { phone })}
${fieldRow([field({ type: 'select', label: 'الجامعة', value: 'جامعة دمياط', phone }), field({ type: 'tel', label: 'هاتف للتواصل', value: '010 1234 5678', optional: true, help: 'يظهر للطلاب في صفحة الخط.', phone })], { phone })}
${fieldRow([field({ type: 'time', label: 'موعد أول رحلة ذهاب', value: time('6:45', 'ص'), state: 'focus', phone }), field({ type: 'date', label: 'يبدأ العمل به من', value: '11 أكتوبر 2026', ltr: false, phone })], { phone })}
${field({ type: 'radio', label: 'من يستطيع الاشتراك؟', cols: 2, phone, options: [{ label: 'كل الطلاب', sub: 'يظهر الخط لكل من يدرس في جامعاته', on: true }, { label: 'بدعوة فقط', sub: 'تضيف الطلاب بنفسك' }] })}
${field({ type: 'toggle', label: 'الاشتراك اليومي (نقداً في الباص)', help: 'يُحفظ مع باقي التغييرات عند الضغط على «حفظ».', on: true, phone })}
${field({ type: 'textarea', label: 'ملاحظة للطلاب', optional: true, placeholder: 'مثال: الباص ينتظر 5 دقائق فقط في كل محطة.', phone })}`;
const formPair = pair('Form section and fields', 'formSection() + field() + fieldRow(). A form is a column of sections, each one saved by its own named button (desktop: section footer; phone: the bottom bar). Labels above, help under, the error under the field that caused it in plain Arabic. No pre-filled prices. Optional fields say «اختياري»; required ones say nothing. Numbers, phones and times are typed left-to-right.',
  formSection({ title: 'بيانات الخط', help: 'الاسم الذي يراه الطلاب، وسعره، ومن يستطيع الاشتراك فيه.', body: formFields(false), footer: `<span style="${T.label};color:${C.bad};margin-inline-end:auto;display:inline-flex;align-items:center;gap:6px">${ico('alert', 14, 2)}حقل واحد يحتاج تصحيحاً</span>${btn('تراجع عن التغييرات', { kind: 'secondary' })}${btn('حفظ بيانات الخط', {})}` }),
  `${formSection({ title: 'بيانات الخط', help: 'الاسم الذي يراه الطلاب، وسعره، ومن يستطيع الاشتراك فيه.', body: formFields(true), phone: true })}
<div style="margin:0 -16px -16px">${bottomBar(btn('حفظ بيانات الخط', { phone: true, full: true }))}</div>`);

const fs = (phone) => [
  ['Default', field({ label: 'اسم المحطة', value: 'كوبري السرو', phone })],
  ['Empty · placeholder', field({ label: 'اسم المحطة', placeholder: 'مثال: موقف الحي الثالث', phone })],
  ['Hover', field({ label: 'اسم المحطة', value: 'كوبري السرو', state: 'hover', phone })],
  ['Focus', field({ label: 'اسم المحطة', value: 'كوبري السرو', state: 'focus', phone })],
  ['Error', field({ type: 'tel', label: 'رقم الهاتف', value: '010 2345', error: 'الرقم ناقص. اكتب 11 رقماً تبدأ بـ 01.', phone })],
  ['Help', field({ type: 'password', label: 'كلمة مرور المشرف', value: 'x', help: '8 أحرف أو أكثر. يستطيع تغييرها بعد الدخول.', phone })],
  ['Disabled', field({ type: 'select', label: 'الفصل', value: 'الفصل الثاني', state: 'disabled', help: 'يُفتح بعد انتهاء الفصل الأول.', phone })],
  ['Money', field({ type: 'money', label: 'سعر الفصلين معاً', value: '8,000', phone })],
  ['Search', field({ type: 'search', label: 'ابحث عن محطة', placeholder: 'اسم المحطة', phone })],
];
const statesPair = pair('Field states and kinds', 'Types: text, password, tel, search, select, date, time, money, textarea, toggle, radio cards, checkbox. 44 high on desktop, 48 on a phone; the label is 13 / 500, the value 14.',
  `<div style="${CARD};padding:24px;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px 16px;align-items:start">${fs(false).map(([c, f]) => `<div>${f}${cap(c)}</div>`).join('')}</div>
<div style="${CARD};padding:24px;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;align-items:start"><div>${field({ type: 'toggle', label: 'متاح للاشتراك', help: 'الفصل الأول', on: true })}${field({ type: 'toggle', label: 'متاح للاشتراك', help: 'الصيف', on: false })}${field({ type: 'toggle', label: 'الفصلان معاً', help: 'أوقفته المنصة', on: false, state: 'disabled' })}</div><div>${field({ type: 'checkbox', label: 'السبت', on: true })}${field({ type: 'checkbox', label: 'الأحد', on: true, state: 'focus' })}${field({ type: 'checkbox', label: 'الجمعة', on: false })}</div><div>${field({ type: 'radio', cols: 1, options: [{ label: 'إنستاباي', on: true }, { label: 'محفظة هاتف' }, { label: 'حساب بنكي' }] })}</div></div>${cap('toggle · checkbox · radio cards')}`,
  `<div style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px">${[fs(true)[0], fs(true)[3], fs(true)[4], fs(true)[7]].map(([, f]) => f).join('')}${field({ type: 'toggle', label: 'متاح للاشتراك', help: 'الفصل الأول', on: true, phone: true })}${field({ type: 'radio', phone: true, options: [{ label: 'إنستاباي', on: true }, { label: 'محفظة هاتف' }] })}</div>`);

const STEPS = [{ label: 'بيانات الخط', state: 'done' }, { label: 'المحطات', state: 'current' }, { label: 'الرحلات والمواعيد', state: 'todo' }, { label: 'الأسعار', state: 'todo' }, { label: 'مراجعة وحفظ', state: 'todo' }];
const stepPair = pair('Stepper', 'stepper() — for anything built in steps (a new line, first-run setup, a new company). Horizontal above the working step on desktop, a vertical list for setup checklists, and on a phone one line «الخطوة 2 من 5» with a segmented bar. Nothing is saved until the last step; the footer has «السابق» at the start and the next step named at the end.',
  `<div style="${CARD};padding:20px 24px;display:flex;flex-direction:column;gap:20px">${stepper({ steps: STEPS })}<div style="height:72px;border-radius:14px;border:1.500px dashed ${C.disabled};display:flex;align-items:center;justify-content:center;${T.label};color:${C.ink3}">الخطوة الحالية: حقولها هنا</div><div style="display:flex;gap:8px">${btn('السابق', { kind: 'secondary', icon: 'arrowBack' })}<span style="flex:1"></span>${btn('إلغاء', { kind: 'link' })}${btn('التالي: الرحلات والمواعيد', { iconEnd: 'arrowFwd' })}</div></div>
<div style="${CARD};padding:20px 24px;width:420px">${stepper({ vertical: true, steps: [{ label: 'أضف أول خط', sub: 'خط الزرقا · 8 محطات', state: 'done' }, { label: 'أضف وسيلة دفع', sub: 'الحساب الذي يحوّل عليه الطلاب', state: 'current' }, { label: 'أضف مشرفاً', sub: 'من يسجّل صعود الطلاب', state: 'todo' }] })}</div>${cap('vertical')}`,
  `<div style="${CARD};padding:16px">${stepper({ phone: true, steps: STEPS })}</div>
<div style="margin:0 -16px -16px">${bottomBar(`${btn('التالي: الرحلات والمواعيد', { phone: true, full: true, iconEnd: 'arrowFwd' })}${btn('السابق', { kind: 'secondary', phone: true, full: true })}`)}</div>`);

const KINDS = [['primary', 'حفظ'], ['secondary', 'إلغاء'], ['outline', 'إرسال إشعار'], ['tonal', 'راجع الإيصالات'], ['danger', 'إيقاف الخط'], ['dangerQuiet', 'إزالة'], ['link', 'كل الخطوط']];
const basicsPair = pair('Buttons, badges, statuses, chips', 'btn() kinds: primary (one per page), secondary (on cards), outline (on the page ground), tonal (row actions), danger (inside a confirmation only), dangerQuiet (opens a confirmation), link. status() draws the six subscription statuses, state() the things that run or stop, badge() plain tags, countBadge() the red navigation count, chip() a filter.',
  `<div style="${CARD};padding:24px;display:flex;flex-direction:column;gap:20px">
<div style="display:flex;flex-wrap:wrap;gap:12px;align-items:center">${KINDS.map(([k, l]) => btn(l, { kind: k })).join('')}${iconBtn('dots', 'إجراءات أخرى')}${iconBtn('x', 'إغلاق', { state: 'hover' })}</div>
<div style="display:flex;flex-wrap:wrap;gap:12px;align-items:center">${btn('خط جديد', { icon: 'plus' })}${btn('التالي', { iconEnd: 'arrowFwd' })}${btn('جارٍ الحفظ', { state: 'loading' })}${btn('حفظ', { state: 'disabled' })}${btn('قبول', { sm: true })}${btn('رفض', { sm: true, kind: 'dangerQuiet' })}${btn('عرض', { sm: true, kind: 'tonal' })}<span style="${T.cap};color:${C.ink3}" dir="ltr">sm = 36, table rows only</span></div>
<div style="height:1px;background:${C.hair}"></div>
<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">${Object.keys(STATUS).map((k) => status(k)).join('')}</div>
<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">${Object.keys(STATE).map((k) => state(k)).join('')}</div>
<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">${badge('8 خطوط')}${badge('آخر محاولة', 'danger')}${badge('المحاولة 2 من 5', 'warning')}${badge('الأحد 11 أكتوبر', 'teal')}${badge('لمدير المنصة فقط', 'neutral')}${badge('جديد', 'success')}${countBadge(7)}${countBadge(23)}</div>
<div style="display:flex;flex-wrap:wrap;gap:6px;align-items:center">${chip('الكل', { on: true, count: 442 })}${chip('قيد المراجعة', { count: 7 })}${chip('خط الزرقا', { icon: 'route' })}${chip('بانتظار الدفع', { count: 31, state: 'focus' })}</div>
</div>`,
  `<div style="${CARD};padding:16px;display:flex;flex-direction:column;gap:10px">${btn('حفظ', { phone: true, full: true })}${btn('إلغاء', { kind: 'secondary', phone: true, full: true })}${btn('إزالة من الشركة', { kind: 'dangerQuiet', icon: 'trash', phone: true, full: true })}<div style="display:flex;flex-wrap:wrap;gap:8px;padding-top:6px">${status('active')}${status('review')}${status('rejected')}${state('off')}</div><div style="display:flex;gap:6px;overflow:hidden">${chip('الكل', { on: true, count: 442, phone: true })}${chip('قيد المراجعة', { count: 7, phone: true })}${chip('بانتظار الدفع', { count: 31, phone: true })}</div></div>${cap('48 high, full width; chips 40 and scroll sideways')}`);

const toastPair = pair('Toast and inline note', 'toast() confirms what just happened — never an error of a form. Ink, bottom start corner on desktop, full width above the bottom bar on a phone, one at a time, 6 seconds; «تراجع» where undoing is cheap. note() is a message that stays in the page: a warning about the page\'s own subject, a hint, a result.',
  `<div style="display:flex;flex-direction:column;gap:10px;align-items:flex-start">${toast({ text: 'قُبل إيصال منة الله إبراهيم', action: 'تراجع' })}${toast({ tone: 'info', text: 'وصل إيصال جديد من يوسف أحمد', action: 'عرض' })}${toast({ tone: 'danger', text: 'لم يُحفظ التغيير. تحقق من الاتصال وحاول مرة أخرى.', w: 460 })}</div>
<div style="display:flex;flex-direction:column;gap:10px">${note({ tone: 'warning', title: 'لا يستطيع الطلاب الاشتراك بعد', text: 'لا توجد وسيلة يدفعون بها.', action: btn('أضف وسيلة دفع', { kind: 'tonal', sm: true }) })}${note({ tone: 'teal', text: 'تعمل الشركة الآن بمواعيد المنصة. أي تغيير هنا يخص شركتك فقط.' })}${note({ tone: 'danger', title: 'لم يُنشر التصميم على كل البطاقات', text: 'حُفظ التصميم، لكن 14 بطاقة لم تتحدث بعد.', action: btn('أكمل النشر', { kind: 'tonal', sm: true }) })}${note({ tone: 'success', title: 'الرمز المؤقت: ' + ltr('4 8 2 9 1 5'), text: 'أملِه على الطالب الآن. يبقى ظاهراً حتى تغلقه، وينتهي بعد 30 دقيقة.', action: btn('نسخ', { kind: 'tonal', sm: true, icon: 'copy' }) })}</div>`,
  `${toast({ text: 'قُبل إيصال منة الله إبراهيم', action: 'تراجع', phone: true })}${toast({ tone: 'danger', text: 'لم يُحفظ التغيير. حاول مرة أخرى.', phone: true })}${note({ tone: 'warning', title: 'لا يستطيع الطلاب الاشتراك بعد', text: 'لا توجد وسيلة يدفعون بها.' })}`);

const pageStates = pair('Empty, error, loading, offline', 'emptyState() says what will appear and offers the button that fills it. errorState() is plain Arabic with a retry — never the server\'s text. skeleton() takes the shape of what is loading (stat, list, table, cards, form). offlineBar() sits under the top bar on every page while there is no connection.',
  `<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">${emptyState({ card: true, icon: 'scan', title: 'لا مشرفين بعد', text: 'المشرف يركب مع الباص ويسجّل صعود الطلاب بهاتفه.', action: btn('أضف مشرفاً', { icon: 'plus' }) })}${errorState({ card: true, title: 'تعذّر تحميل المشرفين', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' })}</div>
<div style="margin:0 -24px">${offlineBar()}</div>
${skeleton('table', { rows: 3, cols: 5 })}
<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">${skeleton('list', { rows: 3 })}${skeleton('form', { rows: 2 })}</div>`,
  `<div style="margin:-16px -16px 0;border-radius:16px 16px 0 0;overflow:hidden">${offlineBar({ phone: true })}</div>${emptyState({ card: true, phone: true, icon: 'scan', title: 'لا مشرفين بعد', text: 'المشرف يركب مع الباص ويسجّل صعود الطلاب بهاتفه.', action: btn('أضف مشرفاً', { icon: 'plus', phone: true, full: true }) })}${errorState({ card: true, phone: true, title: 'تعذّر تحميل المشرفين', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' })}${skeleton('cards', { rows: 2 })}`);

const receiptRow = `<div style="${CARD};padding:16px;display:flex;gap:16px;align-items:center">${receiptImg(48, 64, { r: 8 })}${receiptImg(210, 280)}<div style="${T.label};color:${C.ink2}" dir="ltr">receiptImg(w, h) — a drawn stand-in for the photographed transfer; a thumbnail in lists, large and zoomable beside the decision.</div></div>`;
const iconsSec = `<section style="display:flex;flex-direction:column;gap:16px">
<div style="display:flex;flex-direction:column;gap:4px"><h2 style="${H2}">Icons and the receipt stand-in</h2><p style="${NOTE}">ico(name, size) — one stroke set, 1.75 px on a 24 grid; 18 in navigation and buttons, 20 in rows, 16 inside small controls. Direction icons are named by meaning: fwd / arrowFwd point the way of reading (left), back / arrowBack point right. An icon-only button always has an accessible name (iconBtn).</p></div>
<div style="display:grid;grid-template-columns:minmax(0,1fr) 520px;gap:24px;align-items:start">
<div style="background:${C.ground};border-radius:16px;padding:24px;display:grid;grid-template-columns:repeat(9,minmax(0,1fr));gap:16px 8px">${ICONS.map((n) => `<div style="display:flex;flex-direction:column;align-items:center;gap:6px;color:${C.ink}">${ico(n, 22)}<span style="font-size:11px;line-height:14px;color:${C.ink3}">${n}</span></div>`).join('')}</div>
<div dir="rtl" style="background:${C.ground};border-radius:16px;padding:24px">${receiptRow}</div>
</div></section>`;

const lead = 'Every part is a function in build2/kit.mjs, drawn in its desktop form and its phone form, with its 0, 1 and many where it holds data.';
board('AdmComponents', { row: 'A', w: 1440, lang: 'en', title: 'Admin web · Components 1 · Pages and data', tab: 'Basak admin web · Components 1',
  body: page('Components · pages and data', lead, [headerPair, statPair, attnPair, tablePair]) });
board('AdmComponents2', { row: 'A', w: 1440, lang: 'en', title: 'Admin web · Components 2 · Panels and forms', tab: 'Basak admin web · Components 2',
  body: page('Components · panels and forms', lead, [panelPair, dialogPair, formPair, statesPair]) });
board('AdmComponents3', { row: 'A', w: 1440, lang: 'en', title: 'Admin web · Components 3 · Feedback and states', tab: 'Basak admin web · Components 3',
  body: page('Components · feedback and states', lead, [stepPair, basicsPair, toastPair, pageStates, iconsSec]) });
