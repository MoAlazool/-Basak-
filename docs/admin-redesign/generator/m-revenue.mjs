/** الإيرادات — /c/:companyId/reports  (+ /reports/reset) */
import {
  board, shellDesktop, shellPhone, sectionHead, statCard, dataTable, recordList, recordCard, dialog, scrim, field, btn, badge, status, state, note, chip,
  emptyState, errorState, skeleton, money, cell2, ltr, time, ico, C, T, R, CARD,
} from './kit.mjs';
import { card, grid, selectBtn, barList, statesBoard, mini, ticks, muted, LINES } from './m-common.mjs';

const ROW = 'F';
const BASE = 'يبدأ الحساب من 1 سبتمبر 2026';
const SUB = `ما دفعه الطلاب فعلاً: الإيصالات التي قبلتها والاشتراك اليومي النقدي. ${BASE}.`;
const head = { active: 'reports', title: 'الإيرادات', sub: SUB };

/* ── Data ───────────────────────────────────────────────────────── */
const BY_PERIOD = [['الفصلان معاً', 1440000, '180 اشتراكاً'], ['الفصل الأول', 1350000, '300 اشتراك'], ['الفصل الثاني', 108000, '24 مقدماً'], ['اليومي (نقداً)', 7620, '127 يوماً'], ['الفصل الصيفي', 0, 'لم يُفتح']];
const BY_LINE = [702400, 518900, 455300, 398720, 301500, 247800, 181000, 100000].map((v, i) => [LINES[i], v]);
const BY_METHOD = [['إنستاباي النورس', 1612000, '361 إيصالاً'], ['فودافون كاش', 786000, '171 إيصالاً'], ['البنك الأهلي المصري', 500000, '99 إيصالاً'], ['نقداً', 7620, '127 مرة']];
const FIRST = ['منة الله إبراهيم', 'عبد الرحمن محمد السيد', 'يوسف أحمد', 'ملك حسام الدين', 'عمر خالد إسماعيل', 'سلمى طارق', 'مريم عبد العزيز', 'أحمد محمود فتحي', 'نور الهدى سامي', 'كريم وائل', 'هاجر مصطفى كامل', 'زياد عماد الدين', 'روان أشرف'];
const LAST = ['عبد الرازق', 'الشربيني', 'عبد الفتاح', 'مصطفى', 'البنا', 'عبد الحميد', 'الدسوقي', 'عبد الغني', 'الشناوي', 'أبو العينين'];
const UNI = ['جامعة دمياط', 'جامعة حورس', 'المعهد العالي بدمياط الجديدة'];
const KIND = [['الفصلان معاً', 8000], ['الفصل الأول', 4500], ['الفصل الأول', 4500], ['الفصل الثاني', 4500], ['اليومي (نقداً)', 60]];
const METHOD = ['إنستاباي النورس', 'فودافون كاش', 'إنستاباي النورس', 'البنك الأهلي المصري'];
const ST = ['active', 'active', 'active', 'review', 'active', 'soon', 'active', 'unpaid', 'active', 'rejected', 'active', 'active'];
const ROWS = Array.from({ length: 25 }, (_, i) => {
  const k = KIND[(i * 3) % 5]; const st = k[0] === 'الفصل الثاني' ? 'soon' : ST[i % 12] === 'soon' ? 'active' : ST[i % 12];
  const paid = ['active', 'soon'].includes(st); const cash = k[1] === 60;
  return { name: `${FIRST[i % 13]} ${LAST[(i * 7) % 10]}`, phone: `01${i % 3} ${3456 + i * 37} ${7890 - i * 113}`, uni: UNI[i % 3], line: LINES[(i * 5) % 8], kind: k[0], price: k[1], st: cash ? 'ended' : st, paid: paid || cash,
    method: cash ? 'نقداً' : METHOD[i % 4], no: 1642 - i * 3, day: `${10 - Math.floor(i / 4)} أكتوبر`, until: cash ? `${10 - Math.floor(i / 4)} أكتوبر` : k[0] === 'الفصل الأول' ? '21 يناير 2027' : '3 يونيو 2027' };
});
const amount = (r) => (r.paid ? `<span style="font-weight:600">${money(r.price)}</span>` : cell2(`<span style="color:${C.ink3};font-weight:400">${money(r.price)}</span>`, 'لم يُدفع'));
const how = (r) => (r.paid ? cell2(r.method, r.method.startsWith('نقد') ? '' : `إيصال رقم ${ltr(r.no)}`, { w: 400 }) : muted('—'));

/* ── Parts ──────────────────────────────────────────────────────── */
const stats = (phone, z) => `<div style="display:grid;grid-template-columns:repeat(${phone ? 2 : 4},minmax(0,1fr));gap:${phone ? 12 : 16}px">
${statCard({ label: 'إجمالي الإيرادات', icon: 'chart', value: z ? '0' : '2,905,620', unit: 'ج.م', hint: z ? 'منذ لحظة التصفير' : 'من 631 اشتراكاً مدفوعاً', phone })}
${statCard({ label: 'اشتراكات مدفوعة', icon: 'check', value: z ? '0' : '631', hint: z ? '—' : 'منها 127 يومياً نقداً', phone })}
${statCard({ label: 'لم تُدفع بعد', icon: 'clock', value: z ? '0' : '87', hint: z ? '—' : '7 إيصالات تنتظر مراجعتك', phone })}
${statCard({ label: 'مدفوعة مقدماً', icon: 'calendar', value: z ? '0' : '24', unit: z ? '' : 'من 31', hint: 'للفصل الثاني، ولم يبدأ بعد', phone })}
</div>`;
const breakdown = (phone) => {
  const cards = [card({ phone, title: 'حسب الاشتراك', help: 'اضغط سطراً لترى من دفعوه', body: barList(BY_PERIOD) }),
    card({ phone, title: 'حسب الخط', help: `${LINES.length} خطوط`, body: barList(phone ? BY_LINE.slice(0, 5) : BY_LINE, { gap: 10 }) + (phone ? btn('كل الخطوط', { kind: 'link', sm: true }) : '') }),
    card({ phone, title: 'حسب وسيلة الدفع', help: 'أين وصل المال', body: barList(BY_METHOD) })];
  return phone ? cards.join('\n') : grid('repeat(3,minmax(0,1fr))', cards.join(''));
};
const filterBar = (o = {}) => `<div role="group" aria-label="تصفية الاشتراكات" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
${selectBtn('الاشتراك', o.kind ?? 'الكل', { on: !!o.kind })}${selectBtn('الخط', o.line ?? 'كل الخطوط', { on: !!o.line })}${selectBtn('الجامعة', 'كل الجامعات')}${selectBtn('العام الدراسي', '2026/2027')}${selectBtn('السريان', 'الكل')}
${chip('يشمل ما قبل آخر تصفير', { icon: 'undo' })}
<span style="flex:1"></span>${o.kind || o.line ? btn('مسح التصفية', { kind: 'link', sm: true, icon: 'x' }) : ''}
</div>`;
const ledger = (rows = ROWS, o = {}) => dataTable({
  caption: 'الاشتراكات ومدفوعاتها',
  toolbar: { search: 'ابحث باسم الطالب أو رقم الهاتف', searchValue: o.q, filters: [{ label: 'الكل', count: 718, on: !o.q }, { label: 'مدفوع', count: 631 }, { label: 'لم يُدفع', count: 87 }], count: o.count ?? '718 اشتراكاً', sort: 'الأحدث دفعاً أولاً' },
  tablet: o.compact,
  columns: [{ label: 'الطالب' }, { label: 'الخط', w: 120, hideTablet: true }, { label: 'الاشتراك', w: 124 }, { label: 'المبلغ', w: 132 }, { label: 'وسيلة الدفع', w: 150 }, { label: 'تاريخ الدفع', w: 100, sorted: 'desc' }, { label: 'يسري حتى', w: 116, hideTablet: true }, { label: 'الحالة', w: 140 }],
  rows: rows.map((r, i) => ({ state: i === 2 && !o.plain ? 'hover' : undefined, cells: [cell2(r.name, `${ltr(r.phone)} · ${r.uni}`), r.line, cell2(r.kind, '2026/2027', { w: 400 }), amount(r), how(r), r.paid ? r.day : muted('—'), r.until, status(r.st)] })),
  pagination: o.pagination === null ? undefined : (o.pagination ?? { from: 1, to: 25, total: 718, page: 1, pages: 29 }),
  empty: o.empty,
});
const dangerRow = (phone) => `<section style="${CARD};padding:${phone ? 16 : '16px 20px'};display:flex;${phone ? 'flex-direction:column;align-items:stretch' : 'align-items:center'};gap:${phone ? 12 : 16}px">
<div style="display:flex;align-items:flex-start;gap:12px;flex:1;min-width:0"><span style="display:flex;color:${C.ink3};padding-top:2px">${ico('undo', 20)}</span><div style="flex:1;min-width:0"><div style="${T.small};font-weight:600">بداية فصل جديد؟ ابدأ الحساب من الصفر</div><div style="${T.label};color:${C.ink2}">«تصفير الأرقام» صفحة مستقلة. لا يُحذف فيها اشتراك ولا إيصال، ويمكن التراجع عنها. آخر تصفير: 1 سبتمبر 2026.</div></div></div>
${btn('صفحة تصفير الأرقام', { kind: 'outline', iconEnd: 'fwd', phone, full: phone })}
</section>`;
const body = (o = {}) => `${stats()}
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('من أين جاءت الإيرادات')}${breakdown()}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('الاشتراكات ومدفوعاتها', { meta: muted('اضغط صفاً لتفتح صفحة الطالب', T.label) })}${filterBar(o)}${ledger(o.rows ?? ROWS, o)}</section>
${dangerRow()}`;

board('AdmRevenue', { row: ROW, w: 1440, title: 'Admin web · Revenue · Desktop', tab: 'لوحة الشركة · الإيرادات',
  body: (size) => shellDesktop({ size, ...head, body: body() }) });

/* ── The separated danger area: /reports/reset ──────────────────── */
const ZERO = [['إجمالي الإيرادات وتوزيعها على الاشتراكات والخطوط ووسائل الدفع', false], ['عدد الاشتراكات المدفوعة وغير المدفوعة في هذه الصفحة', false]];
const ZERO_ALL = [...ZERO, ['أرقام صفحة «اليوم» التي تُحسب من الاشتراكات', false]];
const KEPT = [['كل الاشتراكات وحالاتها، ولا يتغيّر شيء عند أي طالب', true], ['الإيصالات وصورها وأرقامها', true], ['حسابات الطلاب والمشرفين، والخطوط، ووسائل الدفع', true], ['السجل القديم كله: تراه بزر «يشمل ما قبل آخر تصفير»', true]];
const LOG = [['الإيرادات فقط', '1 سبتمبر 2026', time('8:12', 'ص'), 'بداية العام الدراسي 2026/2027', 'أحمد سعيد النورس', false], ['الإيرادات وأرقام صفحة «اليوم»', '14 يونيو 2026', time('6:40', 'م'), 'تجربة قبل الفصل الصيفي', 'أحمد سعيد النورس', true], ['الإيرادات فقط', '7 فبراير 2026', time('9:05', 'ص'), 'بداية الفصل الثاني', 'أحمد سعيد النورس', false]];
const twoLists = (all, phone) => `<div style="display:grid;grid-template-columns:${phone ? 'minmax(0,1fr)' : 'repeat(2,minmax(0,1fr))'};gap:12px">
<div style="border-radius:${R.inner}px;background:${C.badBg};padding:14px 16px;display:flex;flex-direction:column;gap:8px"><div style="${T.small};font-weight:600;color:${C.bad}">يبدأ من الصفر</div>${ticks(all ? ZERO_ALL : ZERO)}</div>
<div style="border-radius:${R.inner}px;background:${C.okBg};padding:14px 16px;display:flex;flex-direction:column;gap:8px"><div style="${T.small};font-weight:600;color:${C.ok}">يبقى كما هو</div>${ticks(KEPT)}</div>
</div>`;
const resetForm = (phone) => card({ phone, title: 'ابدأ الحساب من جديد', help: 'تضع علامة «من هنا نبدأ العدّ». لا يُحذف شيء من النظام، وهذه العلامة لشركتك وحدها.',
  body: `${field({ type: 'radio', label: 'ماذا تريد أن يبدأ من الصفر؟', phone, cols: 2, options: [{ label: 'الإيرادات فقط', sub: 'أرقام هذه الصفحة', on: true }, { label: 'الإيرادات وأرقام «اليوم»', sub: 'هذه الصفحة وصفحة اليوم' }] })}
${twoLists(false, phone)}
${field({ label: 'سبب التصفير', optional: true, placeholder: 'مثال: بداية الفصل الثاني', help: 'يُكتب في السجل لتتذكره لاحقاً.', phone })}
${phone ? '' : `<div style="display:flex;justify-content:flex-end;border-top:1px solid ${C.hair};padding-top:16px">${btn('تصفير الأرقام', { kind: 'dangerQuiet', icon: 'undo' })}</div>`}` });
const logCard = (phone) => card({ phone, title: 'سجل التصفير', help: 'آخر 10 مرات. إلغاء التصفير يعيد العدّ ليشمل ما قبله.', pad: phone ? 16 : 24,
  body: `<div style="display:flex;flex-direction:column">${LOG.map(([what, day, t, why, who, undone], i) => `<div style="display:flex;align-items:flex-start;gap:12px;padding:12px 0;${i ? `border-top:1px solid ${C.hair}` : ''}"><div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;${T.small};font-weight:600;color:${undone ? C.ink3 : C.ink}">${day} · ${t}${undone ? state('cancelled', 'أُلغي') : i === 0 ? badge('الساري الآن', 'teal') : ''}</div><div style="${T.label};color:${C.ink2}">${what} · ${why}</div><div style="${T.cap};color:${C.ink3}">${who}</div></div>${undone ? '' : btn('إلغاء التصفير', { kind: 'outline', sm: true, extra: phone ? 'height:44px;' : '' })}</div>`).join('')}</div>` });
const resetHead = { active: 'reports', title: 'تصفير الأرقام', back: 'الإيرادات', breadcrumb: ['الإيرادات', 'تصفير الأرقام'], sub: 'عند بداية فصل أو عام جديد: اجعل أرقام الإيرادات تبدأ من الصفر، دون أن تفقد شيئاً.' };
const resetBody = `${note({ tone: 'warning', title: 'صفحة للاستخدام النادر', text: 'الأرقام التي تراها في «الإيرادات» ستبدأ من الصفر لكل مديري الشركة. يمكن إلغاء التصفير من السجل في أي وقت.' })}
${grid('minmax(0,7fr) minmax(0,5fr)', resetForm() + logCard())}`;
board('AdmRevenueReset', { row: ROW, w: 1440, title: 'Admin web · Revenue · Reset the figures (the separated danger area) · Desktop', tab: 'لوحة الشركة · الإيرادات · تصفير الأرقام',
  body: (size) => shellDesktop({ size, ...resetHead, body: resetBody }) });

const resetDialog = (phone) => dialog({ phone, w: 560, icon: 'alert', tone: 'danger', title: 'تصفير أرقام الإيرادات؟',
  body: `<span>من هذه اللحظة (السبت 10 أكتوبر 2026، ${time('9:41', 'ص')}) تُحسب الإيرادات مما يُدفع بعدها فقط. الإجمالي الحالي ${money(2905620)} يخرج من العدّ.</span>${twoLists(false, true)}<span>يمكنك إلغاء التصفير لاحقاً من «سجل التصفير».</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('صفّر الأرقام', { kind: 'danger', phone, full: phone })] });
const undoDialog = (phone) => dialog({ phone, icon: 'undo', tone: 'warning', title: 'إلغاء تصفير 1 سبتمبر 2026؟',
  body: `<span>تعود «الإيرادات» لتحسب كل ما دُفع منذ التصفير الذي قبله (7 فبراير 2026)، فترتفع الأرقام. لا يتغيّر شيء عند الطلاب.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('إلغاء التصفير', { phone, full: phone })] });
board('AdmRevenueResetConfirm', { row: ROW, w: 1440, h: 1160, title: 'Admin web · Revenue · Reset and undo-reset confirmations', tab: 'لوحة الشركة · الإيرادات · تأكيد التصفير',
  body: (size) => shellDesktop({ size, ...resetHead, body: resetBody,
    overlay: scrim(`<div style="display:flex;flex-direction:column;gap:24px;align-items:center">${resetDialog()}${undoDialog()}</div>`) }) });

/* ── States ─────────────────────────────────────────────────────── */
statesBoard('AdmRevenueStates', { row: ROW, title: 'Admin web · Revenue · States', frames: [
  ['Empty · first use', 'No paid subscription yet: the page says what will appear and where the money comes from.',
    mini(640, { ...head, sub: 'ما دفعه الطلاب فعلاً: الإيصالات التي قبلتها والاشتراك اليومي النقدي.', body: `${stats(false, true)}<div style="${CARD}">${emptyState({ icon: 'chart', title: 'لا إيرادات بعد', text: 'عندما تقبل أول إيصال في «الإيصالات»، أو يُسجَّل اشتراك يومي نقدي، يظهر المبلغ هنا موزّعاً على الخطوط ووسائل الدفع.', action: btn('افتح الإيصالات', { kind: 'secondary', iconEnd: 'fwd' }) })}</div>` })],
  ['Filtered · one match, and none', 'Filters in use are tinted and can be cleared in one press; the totals above always follow the filters. No pager under 26 rows.',
    mini(880, { ...head, body: `<section style="display:flex;flex-direction:column;gap:12px">${filterBar({ kind: 'الفصل الثاني', line: 'كفر سعد' })}${ledger(ROWS.filter((r) => r.kind === 'الفصل الثاني').slice(0, 1).map((r) => ({ ...r, line: 'كفر سعد' })), { plain: true, compact: true, count: 'اشتراك واحد', pagination: null })}${ledger([], { q: 'عبد الصمد', count: 'لا نتائج', empty: emptyState({ icon: 'search', title: 'لا اشتراك يطابق بحثك', text: 'لا طالب باسم «عبد الصمد» في خط كفر سعد للفصل الثاني. غيّر التصفية أو امسحها.', action: btn('مسح التصفية', { kind: 'secondary', icon: 'x' }) }) })}</section>` })],
  ['Just reset', 'Right after a reset: zeros, the new starting moment in the page sentence, and the way to see what was before.',
    mini(520, { ...head, sub: `ما دفعه الطلاب فعلاً. يبدأ الحساب من اليوم 10 أكتوبر 2026، ${'9:41'} ص.`, body: `${note({ tone: 'success', title: 'بدأ الحساب من الصفر', text: 'كل ما سبق محفوظ. لتراه اضغط «يشمل ما قبل آخر تصفير»، وللتراجع افتح صفحة تصفير الأرقام.', action: btn('إلغاء التصفير', { kind: 'outline', sm: true }) })}${stats(false, true)}${filterBar()}` })],
  ['Loading', 'Tiles, the three breakdown cards and the table are grey; the filters are real so they can be set while it loads.',
    mini(700, { ...head, body: `<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px">${skeleton('stat')}${skeleton('stat')}${skeleton('stat')}${skeleton('stat')}</div>${filterBar()}${skeleton('table', { rows: 5, cols: 7 })}` })],
  ['Error', 'Plain Arabic and a retry (today the page shows the server text and has no retry).',
    mini(520, { ...head, body: errorState({ card: true, title: 'تعذّر تحميل الإيرادات', text: 'لم نستطع جلب الأرقام. تأكد من اتصالك ثم حاول مرة أخرى.' }) })],
] });

/* ── Phone ──────────────────────────────────────────────────────── */
const rc = (r) => recordCard({ title: r.name, sub: `${ltr(r.phone)} · ${r.uni}`, end: status(r.st), fields: [['الخط', r.line], ['الاشتراك', `${r.kind} · 2026/2027`], ['المبلغ', amount(r)], ['وسيلة الدفع', r.paid ? `${r.method}${r.method.startsWith('نقد') ? '' : ` · إيصال ${ltr(r.no)}`}` : '—'], ['تاريخ الدفع', r.paid ? r.day : '—'], ['يسري حتى', r.until]] });
board('AdmRevenuePhone', { row: ROW, w: 390, title: 'Admin web · Revenue · Phone', tab: 'لوحة الشركة · الإيرادات · هاتف',
  body: (size) => shellPhone({ size, active: 'reports', sub: SUB, body: `${stats(true)}
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('من أين جاءت الإيرادات', { phone: true })}${breakdown(true)}</section>
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('الاشتراكات ومدفوعاتها', { phone: true })}
${recordList({ toolbar: { search: 'ابحث باسم الطالب أو رقم الهاتف', filters: [{ label: 'الكل', count: 718, on: true }, { label: 'مدفوع', count: 631 }, { label: 'لم يُدفع', count: 87 }, { label: 'تصفية أخرى', icon: 'filter' }], count: '718 اشتراكاً', sort: 'الأحدث دفعاً' }, cards: ROWS.slice(0, 5).map(rc), pagination: { from: 1, to: 25, total: 718, page: 1, pages: 29 } })}</section>
${dangerRow(true)}` }) });
board('AdmRevenueResetPhone', { row: ROW, w: 390, title: 'Admin web · Revenue · Reset the figures · Phone', tab: 'لوحة الشركة · تصفير الأرقام · هاتف',
  body: (size) => shellPhone({ size, active: 'reports', title: 'تصفير الأرقام', back: 'الإيرادات', sub: resetHead.sub, body: `${resetForm(true)}${logCard(true)}`, bottomBar: btn('تصفير الأرقام', { kind: 'dangerQuiet', icon: 'undo', phone: true, full: true }) }) });
board('AdmRevenueResetConfirmPhone', { row: ROW, w: 390, h: 900, title: 'Admin web · Revenue · Reset confirmation · Phone', tab: 'لوحة الشركة · تأكيد التصفير · هاتف',
  body: (size) => shellPhone({ size, active: 'reports', title: 'تصفير الأرقام', back: 'الإيرادات', sub: resetHead.sub, body: resetForm(true), overlay: scrim(resetDialog(true), 'bottom') }) });
board('AdmRevenueEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Revenue · Empty · Phone', tab: 'لوحة الشركة · الإيرادات · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'reports', sub: 'ما دفعه الطلاب فعلاً: الإيصالات التي قبلتها والاشتراك اليومي النقدي.', body: `${stats(true, true)}${emptyState({ card: true, phone: true, icon: 'chart', title: 'لا إيرادات بعد', text: 'عندما تقبل أول إيصال في «الإيصالات»، أو يُسجَّل اشتراك يومي نقدي، يظهر المبلغ هنا.', action: btn('افتح الإيصالات', { kind: 'secondary', iconEnd: 'fwd', phone: true, full: true }) })}` }) });
