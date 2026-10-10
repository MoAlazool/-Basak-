/** Lines: the list, one line's page, states, confirmations — desktop then phone. */
import {
  board, shellDesktop, shellPhone, sectionHead, statCard, dataTable, recordList, recordCard, dialog, scrim, infoRows,
  badge, state, btn, iconBtn, note, toast, emptyState, errorState, skeleton, money, ico, cell2, C, T, R, CARD,
} from './kit.mjs';
import {
  col, row, card, h3, small, text, avatar, menu, seg, seatsMeter, statesBoard, dialogsBoard, back, FW, ELL,
  LINES, SUPS, UNI, uniShort, STATIONS, GO, BACK, at, stopAt, arrive, forUni, TOMORROW,
} from './lines-kit.mjs';

const SUB = 'كل خط له محطات صعود بالترتيب، ورحلات ذهاب إلى الجامعة، ومواعيد عودة منها.';
const newBtn = (o = {}) => btn('خط جديد', { icon: 'plus', ...o });

/* ── cells ──────────────────────────────────────────────────────── */
const vis = (l, o = {}) => {
  const pill = l.vis === 'on' ? state('on', 'يظهر للطلاب') : l.vis === 'off' ? state('off', 'متوقف') : state('suspended', 'لا يظهر للطلاب');
  return l.why && !o.bare ? `<div style="display:flex;flex-direction:column;gap:2px;align-items:flex-start">${pill}<span style="${T.cap};color:${C.ink2}">${l.why}</span></div>` : pill;
};
const supCell = (l) => (l.sup.length === 0 ? badge('بلا مشرف', 'danger') : l.sup.length === 1 ? `<div style="${ELL}">${l.sup[0]}</div>` : cell2(l.sup[0], `و${l.sup.length === 2 ? 'مشرف آخر' : `${l.sup.length - 1} آخرون`}`, { w: 400 }));
const seatsCell = (l) => (l.seats == null ? `<span style="color:${C.ink3}">لم يُحدد</span>` : l.over ? `<span style="display:inline-flex;align-items:center;gap:6px">${l.seats}${badge(`يزيد ${l.over}`, 'warning')}</span>` : `${l.seats}`);
const n = (v, unit) => `<span style="white-space:nowrap"><b style="font-weight:600;color:${v ? C.ink : C.disabled}">${v}</b> <span style="${T.cap};color:${C.ink3}">${unit}</span></span>`;
const ridersCell = (l) => (l.rgo + l.rback === 0 ? `<span style="color:${C.ink3}">لا أحد</span>` : `<span style="white-space:nowrap">${n(l.rgo, 'ذهاب')} · ${n(l.rback, 'عودة')}</span>`);
const tripsCell = (l) => cell2(`${l.st} محطات`, l.go ? `${l.go} ذهاب · ${l.ret} عودة` : `<span style="color:${C.bad}">بلا ذهاب</span> · ${l.ret} عودة`, { w: 400 });

const FILTERS = [
  { label: 'الكل', on: true, count: LINES.length }, { label: 'يظهر للطلاب', count: LINES.filter((l) => l.vis === 'on').length },
  { label: 'لا يظهر للطلاب', count: LINES.filter((l) => l.vis === 'hidden').length }, { label: 'متوقف', count: LINES.filter((l) => l.vis === 'off').length },
  { label: 'بلا مشرف', count: LINES.filter((l) => !l.sup.length).length },
];
const filtersOn = (i) => FILTERS.map((f, k) => ({ ...f, on: k === i }));
const linesTable = (o = {}) => dataTable({
  caption: 'خطوط الشركة',
  toolbar: { search: 'ابحث باسم الخط أو المحطة', searchW: 260, filters: o.filters ?? FILTERS, sort: 'الأكثر مشتركين أولاً', searchValue: o.searchValue },
  columns: [
    { label: 'الخط' }, { label: 'المحطات والرحلات', w: 136 }, { label: 'المشتركون', w: 96, sorted: 'desc' }, { label: `ركاب الغد`, w: 150 },
    { label: 'مقاعد الباص', w: 104, hideTablet: true }, { label: 'المشرف', w: 176 }, { label: 'للطلاب', w: 196 }, { label: '', w: 52, align: 'end' },
  ],
  tablet: o.compact,
  rows: (o.rows ?? LINES).map((l, i) => ({ state: o.states?.[i], muted: l.vis === 'off', cells: [
    cell2(l.name, uniShort(l), { w: 600 }), tripsCell(l), `${l.subs}`, ridersCell(l), seatsCell(l), supCell(l), vis(l), iconBtn('dots', `إجراءات خط ${l.name}`, { sm: true }),
  ] })),
  empty: o.empty,
});

/* ── AdmLines ───────────────────────────────────────────────────── */
board('AdmLines', { row: 'L', w: 1440, title: 'Admin web · Lines · Desktop', tab: 'لوحة الشركة · الخطوط',
  body: (size) => shellDesktop({ size, active: 'lines', title: 'الخطوط', sub: SUB, actions: newBtn(), body: `
<div style="position:relative">${linesTable({ states: { 3: 'hover' } })}
<div style="position:absolute;inset-inline-end:44px;top:${60 + 44 + 56 * 3 + 44}px;z-index:2">${menu([
    { label: 'افتح الخط', icon: 'eye' }, { label: 'تعديل الخط', icon: 'pencil', hover: true }, { label: 'عيّن مشرفاً', icon: 'scan', sub: 'من صفحة المشرفون' }, '-',
    { label: 'إيقاف الخط', icon: 'power' }, { label: 'حذف الخط', icon: 'trash', danger: true }])}</div></div>
<p style="margin:0;${T.label};color:${C.ink2}">«ركاب الغد» هم من أكّدوا الركوب ليوم ${TOMORROW}. الخط الذي «لا يظهر للطلاب» مكتوب تحته ما ينقصه.</p>` }) });

/* ── One line: its page ─────────────────────────────────────────── */
const Z = LINES[1];
const PRICES = [['الفصل الأول', 3200, 'on'], ['الفصل الثاني', 3200, 'on'], ['الفصلان معاً', 6000, 'on'], ['الفصل الصيفي', null, 'off'], ['اليومي (نقداً)', 45, 'on']];
const tripHead = (t) => `<div style="display:flex;flex-direction:column;gap:2px"><span style="font-size:16px;line-height:24px;font-weight:600;color:${C.ink}">${at(t.start)}</span><span style="${T.cap};color:${C.ink3};font-weight:400;white-space:normal">${[t.label, t.uni != null ? UNI[t.uni] + ' فقط' : ''].filter(Boolean).join(' · ') || forUni(null)}</span></div>`;
const matrix = () => {
  const th = `padding:12px 12px;text-align:start;vertical-align:top;border-inline-start:1px solid ${C.hair}`;
  const td = `padding:0 12px;height:44px;font-size:14px;border-top:1px solid ${C.hair};border-inline-start:1px solid ${C.hair}`;
  return `<div style="${CARD};overflow:hidden"><table style="width:100%;border-collapse:collapse;table-layout:fixed"><caption style="position:absolute;width:1px;height:1px;overflow:hidden">مواعيد رحلات الذهاب على كل محطة</caption>
<thead><tr style="background:${C.ground}"><th scope="col" style="width:280px;padding:12px 16px;text-align:start;vertical-align:bottom;${T.label};font-weight:500;color:${C.ink2}">المحطة بترتيب المسار</th>${GO.map((t) => `<th scope="col" style="${th}">${tripHead(t)}</th>`).join('')}</tr></thead>
<tbody>
<tr><th scope="row" style="padding:12px 16px;text-align:start;border-top:1px solid ${C.hair};${T.small};font-weight:500"><div>ركاب الغد</div><div style="${T.cap};font-weight:400;color:${C.ink3}">من مقاعد الباص (${Z.seats})</div></th>${GO.map((t) => `<td style="${td};height:auto;padding:12px">${seatsMeter(t.riders, Z.seats)}</td>`).join('')}</tr>
${STATIONS.map((s, i) => `<tr><th scope="row" style="padding:0 16px;height:44px;text-align:start;border-top:1px solid ${C.hair};font-size:14px;font-weight:400"><span style="display:flex;align-items:center;gap:10px"><span aria-hidden="true" style="width:22px;height:22px;border-radius:11px;background:${C.sunken};color:${C.ink2};font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center;flex:none">${i + 1}</span><span style="${ELL}">${s}</span></span></th>${GO.map((t) => `<td style="${td}">${stopAt(t, i) == null ? `<span style="${T.label};color:${C.ink3}">لا تقف</span>` : at(stopAt(t, i))}</td>`).join('')}</tr>`).join('\n')}
<tr style="background:${C.ground}"><th scope="row" style="padding:0 16px;height:44px;text-align:start;border-top:1px solid ${C.hair};font-size:14px;font-weight:500"><span style="display:flex;align-items:center;gap:10px"><span style="display:flex;color:${C.teal}">${ico('school', 20)}</span>الوصول إلى الجامعة</span></th>${GO.map((t) => `<td style="${td};font-weight:500">${at(arrive(t))}</td>`).join('')}</tr>
</tbody></table></div>`;
};
const backList = (phone) => `<div style="${CARD};overflow:hidden">${BACK.map((t, i) => `<div style="display:flex;align-items:center;gap:16px;min-height:60px;padding:8px ${phone ? 16 : 20}px;${i ? `border-top:1px solid ${C.hair}` : ''}"><span style="width:${phone ? 76 : 96}px;flex:none;font-size:16px;font-weight:600">${at(t.start)}</span><span style="flex:1;min-width:0;${T.small};color:${C.ink2}">من ${forUni(t.uni)}</span><span style="width:${phone ? 84 : 120}px;flex:none">${seatsMeter(t.riders, Z.seats)}</span></div>`).join('')}</div>`;
const pricesCard = (phone) => card(`${h3('الأسعار على هذا الخط')}
${infoRows(PRICES.map(([k, p, s]) => [k, `<span style="display:flex;align-items:center;gap:8px;justify-content:space-between"><span style="font-weight:600">${p == null ? `<span style="font-weight:400;color:${C.ink3}">بلا سعر</span>` : money(p)}</span>${s === 'on' ? badge('يُباع', 'success') : badge(phone ? 'لا يُباع' : 'لا يُباع على هذا الخط', 'neutral')}</span>`]), { labelW: phone ? 124 : 150 })}
${small(`السعر يُكتب هنا. متى يُفتح كل اشتراك للبيع يُحدد في ${`<a href="#" style="font-weight:500">مواعيد الاشتراك</a>`}.`)}`);
const supsCard = (phone) => card(`${h3('مشرفو الخط', btn('تغيير المشرفين', { kind: 'link', sm: true, iconEnd: 'fwd' }))}
${[SUPS[1], SUPS[7]].map((s) => `<div style="display:flex;align-items:center;gap:12px;min-height:44px">${avatar(s.name, 40, { photo: s.photo })}<div style="flex:1;min-width:0"><div style="${T.small};font-weight:500;${ELL}">${s.name}</div><div style="${T.label};color:${C.ink2}"><span dir="ltr">${s.phone}</span></div></div>${s.on ? '' : state('off')}</div>`).join('')}
${small('المشرف يركب مع الباص ويسجّل صعود الطلاب. المتوقف لا يرى خطوطه ولا يسجّل الركوب.')}`);
const lineStats = (phone) => `<div style="display:grid;grid-template-columns:repeat(${phone ? 2 : 4},minmax(0,1fr));gap:${phone ? 12 : 16}px">
${statCard({ label: 'المشتركون', icon: 'users', value: Z.subs, unit: 'طالباً', hint: 'اشتراكات سارية', phone })}
${statCard({ label: 'ذهاب الغد', icon: 'aup', value: Z.rgo, unit: 'راكباً', hint: 'في 5 رحلات', phone })}
${statCard({ label: 'عودة الغد', icon: 'adown', value: Z.rback, unit: 'راكباً', hint: 'في 5 مواعيد', phone })}
${statCard({ label: 'مقاعد الباص', icon: 'bus', value: Z.seats, unit: 'مقعداً', hint: 'لكل رحلة', phone })}
</div>`;
const detailBody = `${lineStats(false)}
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('رحلات الذهاب', { meta: badge(`ركاب ${TOMORROW}`, 'teal'), end: `<span style="${T.label};color:${C.ink2}">8 محطات · 5 رحلات · التأكيد مفتوح، والأعداد تتغيّر</span>` })}
${matrix()}
</section>
<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('العودة من الجامعة', { end: `<span style="${T.label};color:${C.ink2}">يتحرك الباص من الجامعة ويعيد كل طالب إلى محطته</span>` })}
${backList(false)}
</section>
<div style="display:flex;flex-direction:column;gap:16px;padding-top:48px">${pricesCard()}${supsCard()}</div>
</div>`;
const detailActions = `${iconBtn('dots', 'إجراءات أخرى: حذف الخط')}${btn('إيقاف الخط', { kind: 'outline', icon: 'power' })}${btn('تعديل الخط', { icon: 'pencil' })}`;
const detailShell = (size, o = {}) => shellDesktop({ size, active: 'lines', breadcrumb: ['الخطوط', 'الزرقا'], title: 'خط الزرقا', back: 'الخطوط', meta: o.meta ?? state('on', 'يظهر للطلاب'),
  sub: 'يخدم جامعة دمياط وجامعة حورس', actions: o.actions ?? detailActions, body: o.body ?? detailBody, overlay: o.overlay });

board('AdmLine', { row: 'L', w: 1440, title: 'Admin web · Lines · One line · Desktop', tab: 'لوحة الشركة · الخطوط · خط الزرقا',
  body: (size) => detailShell(size) });

/* Stopped line: what the page says and offers. */
board('AdmLineStopped', { row: 'L', w: 1440, title: 'Admin web · Lines · One line, stopped · Desktop', tab: 'لوحة الشركة · الخطوط · خط متوقف',
  body: (size) => shellDesktop({ size, active: 'lines', breadcrumb: ['الخطوط', 'رأس البر'], title: 'خط رأس البر', back: 'الخطوط', meta: state('off'),
    sub: 'يخدم جامعة دمياط والمعهد العالي للهندسة بدمياط الجديدة',
    actions: `${iconBtn('dots', 'إجراءات أخرى: حذف الخط')}${btn('تعديل الخط', { kind: 'outline', icon: 'pencil' })}${btn('تشغيل الخط', { icon: 'power' })}`,
    body: `${note({ tone: 'warning', title: 'الخط متوقف: لا يظهر للطلاب في التطبيق ولا يشترك فيه أحد جديد', text: 'مشتركوه الحاليون (12 طالباً) اشتراكهم كما هو ويؤكدون الركوب كالمعتاد. لا يمكن إسناده لمشرف جديد حتى تشغّله.', action: btn('تشغيل الخط', { kind: 'outline', sm: true }) })}
<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px">
${statCard({ label: 'المشتركون', icon: 'users', value: 12, unit: 'طالباً', hint: 'اشتراكات سارية' })}
${statCard({ label: 'ذهاب الغد', icon: 'aup', value: 9, unit: 'ركاب', hint: 'في 3 رحلات' })}
${statCard({ label: 'عودة الغد', icon: 'adown', value: 8, unit: 'ركاب', hint: 'في 3 مواعيد' })}
${statCard({ label: 'مقاعد الباص', icon: 'bus', value: 30, unit: 'مقعداً', hint: 'لكل رحلة' })}
</div>
${note({ tone: 'teal', title: 'خط «لا يظهر للطلاب» وهو غير متوقف', text: 'يُكتب السبب مكان هذه الرسالة مع زر يأخذك إليه: «تنقصه رحلة ذهاب إلى جامعة دمياط — أضف رحلة»، «لم يُكتب سعر لأي اشتراك — اكتب الأسعار»، «لم تُحدد له جامعة — اختر الجامعات».', icon: 'info' })}` }) });

/* ── States ─────────────────────────────────────────────────────── */
const firstUse = (phone) => emptyState({ card: true, phone, icon: 'route', title: 'لا خطوط بعد',
  text: 'الخط هو مسار الباص: محطات يركب منها الطلاب، ورحلات ذهاب بمواعيدها، ومواعيد العودة من الجامعة، وسعر الاشتراك. بدون خط لا يجد الطلاب ما يشتركون فيه.',
  action: btn('أضف أول خط', { icon: 'plus', phone, full: phone }) });
statesBoard('AdmLinesStates', { row: 'L', title: 'Admin web · Lines · Loading, first use, no match, error, offline' }, [
  ['Loading', 'The table\'s shape in grey; the shell, the title and «خط جديد» are real from the first frame.',
    shellDesktop({ size: `width:${FW}px;height:560px`, active: 'lines', title: 'الخطوط', sub: SUB, actions: newBtn(), body: skeleton('table', { rows: 5, cols: 7 }) })],
  ['First use', 'No line yet: one sentence on what a line is and why it matters, and the button that starts the steps. No toolbar over nothing.',
    shellDesktop({ size: `width:${FW}px;height:600px`, active: 'lines', badges: {}, title: 'الخطوط', sub: SUB, body: firstUse(false) })],
  ['One line · search with no match', 'A single row keeps the full table. A search that finds nothing says so in the table and offers to clear it.',
    shellDesktop({ size: `width:${FW}px;height:780px`, active: 'lines', title: 'الخطوط', sub: SUB, actions: newBtn(), body: `${dataTable({
      toolbar: { search: 'ابحث باسم الخط أو المحطة', searchW: 260, filters: [{ label: 'الكل', on: true, count: 1 }] },
      columns: [{ label: 'الخط' }, { label: 'المحطات والرحلات', w: 136 }, { label: 'المشتركون', w: 96 }, { label: 'ركاب الغد', w: 150 }, { label: 'المشرف', w: 176 }, { label: 'للطلاب', w: 196 }, { label: '', w: 52 }],
      rows: [LINES[1]].map((l) => ({ cells: [cell2(l.name, uniShort(l), { w: 600 }), tripsCell(l), `${l.subs}`, ridersCell(l), supCell(l), vis(l), iconBtn('dots', 'إجراءات', { sm: true })] })) })}
${linesTable({ compact: true, searchValue: 'المنزلة', filters: filtersOn(0), empty: emptyState({ icon: 'search', title: 'لا خط ولا محطة باسم «المنزلة»', text: 'جرّب اسماً أقصر، أو امسح البحث لترى كل الخطوط.', action: btn('امسح البحث', { kind: 'secondary' }) }) })}` })],
  ['Error', 'Plain Arabic, a retry, never the server\'s text (today: «تعذر تحميل الخطوط: {raw message}»).',
    shellDesktop({ size: `width:${FW}px;height:540px`, active: 'lines', title: 'الخطوط', sub: SUB, body: errorState({ card: true, title: 'تعذّر تحميل الخطوط', text: 'لم نستطع جلب خطوطك. تأكد من اتصالك ثم حاول مرة أخرى.' }) })],
  ['Offline', 'The last loaded list stays readable. «خط جديد», stop, delete and every save are held back until the connection returns.',
    shellDesktop({ size: `width:${FW}px;height:600px`, active: 'lines', offline: true, title: 'الخطوط', sub: SUB, actions: newBtn({ state: 'disabled' }), body: linesTable({ compact: true, rows: LINES.slice(0, 5) }) })],
]);

/* ── Confirmations ──────────────────────────────────────────────── */
const D = {
  stop: (phone) => dialog({ phone, tone: 'danger', icon: 'power', title: 'إيقاف خط الزرقا؟', body: `<span>لن يظهر الخط للطلاب في التطبيق، ولن يشترك فيه أحد جديد، ولا يمكن إسناده لمشرف جديد.</span><span>المشتركون الحاليون (<b style="color:${C.ink}">124 طالباً</b>) يبقى اشتراكهم كما هو، وتبقى محطاته ورحلاته وسجلاته. يمكنك تشغيله مرة أخرى في أي وقت.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('إيقاف الخط', { kind: 'danger', phone, full: phone })] }),
  start: (phone) => dialog({ phone, tone: 'teal', icon: 'power', title: 'تشغيل خط رأس البر؟', body: '<span>يعود الخط للظهور في التطبيق لطلاب جامعة دمياط والمعهد العالي للهندسة، بالاشتراكات المعروضة للبيع الآن. محطاته ورحلاته وأسعاره كما تركتها.</span>',
    actions: [back('رجوع', { phone, full: phone }), btn('تشغيل الخط', { phone, full: phone })] }),
  del: (phone) => dialog({ phone, tone: 'danger', icon: 'trash', title: 'حذف خط عزبة البرج نهائياً؟', body: `<span>يُحذف الخط مع محطاته الخمس ورحلاته الأربع. لا يمكن التراجع.</span><span>لم يشترك فيه أحد، فلن يتأثر أي طالب.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('حذف الخط', { kind: 'danger', phone, full: phone })] }),
  delBlocked: (phone) => dialog({ phone, tone: 'warning', icon: 'alert', title: 'لا يمكن حذف خط الزرقا', body: `<span>للخط اشتراكات وسجلات ركوب سابقة (124 اشتراكاً سارياً)، وحذفه يضيّعها.</span><span>إن أردت ألا يراه الطلاب فأوقفه: يختفي من التطبيق وتبقى سجلاته.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('إيقاف الخط بدلاً من حذفه', { kind: 'outline', phone, full: phone })] }),
};
dialogsBoard('AdmLineDialogs', { row: 'L', title: 'Admin web · Lines · Confirmations', heading: 'Lines · every confirmation' }, [
  ['Stop a line', 'Today: a browser confirm(). The body keeps the code\'s three facts: hidden from students, no new supervisor, data and subscriptions kept. Real subscriber count.', D.stop()],
  ['Reactivate a line', 'Today: one click, no confirmation. Asked because it puts the line on sale again.', D.start()],
  ['Delete a line nobody used', 'Allowed only when the line has no subscriptions, no boarding records and no archived revenue (delete_line). Stations, trips and supervisor assignments go with it.', D.del()],
  ['Delete refused', 'The same server rule, shown before the request when the subscriber count is known and as the answer when the server refuses. Offers what the code suggests: stop it.', D.delBlocked()],
]);

/* ── Phone ──────────────────────────────────────────────────────── */
const lineCard = (l) => recordCard({
  title: l.name, sub: uniShort(l), end: `<span style="display:flex;color:${C.ink3};padding-top:2px">${ico('fwd', 18)}</span>`,
  stats: [['المشتركون', `${l.subs}`], ['ذهاب الغد', `<span style="color:${l.rgo ? C.ink : C.disabled}">${l.rgo}</span>`], ['عودة الغد', `<span style="color:${l.rback ? C.ink : C.disabled}">${l.rback}</span>`]],
  fields: [['المحطات والرحلات', `${l.st} محطات · ${l.go ? `${l.go} ذهاب` : `<span style="color:${C.bad}">بلا ذهاب</span>`} · ${l.ret} عودة`], ['مقاعد الباص', seatsCell(l)], ['المشرف', l.sup.length ? `${l.sup[0]}${l.sup.length > 1 ? ' +1' : ''}` : badge('بلا مشرف', 'danger')],
    ['للطلاب', `<div style="display:flex;flex-direction:column;align-items:flex-end;gap:2px">${vis(l, { bare: true })}${l.why ? `<span style="${T.cap};color:${C.ink2}">${l.why}</span>` : ''}</div>`]],
});
board('AdmLinesPhone', { row: 'L', w: 390, title: 'Admin web · Lines · Phone', tab: 'لوحة الشركة · الخطوط · هاتف',
  body: (size) => shellPhone({ size, active: 'lines', body: recordList({
    toolbar: { search: 'ابحث باسم الخط أو المحطة', filters: FILTERS, count: `${LINES.length} خطوط`, sort: 'الأكثر مشتركين' },
    cards: LINES.map(lineCard) }), bottomBar: newBtn({ phone: true, full: true }) }) });

const tripCardPhone = (t, open) => `<div style="background:${C.surface};border-radius:${R.inner}px;box-shadow:0 1px 2px rgba(23,56,74,.05);overflow:hidden">
<button type="button" aria-expanded="${!!open}" style="display:flex;align-items:center;gap:12px;width:100%;min-height:64px;padding:10px 16px;text-align:start"><span style="flex:1;min-width:0"><span style="display:block;font-size:17px;line-height:24px;font-weight:600">${at(t.start)}</span><span style="display:block;${T.cap};color:${C.ink3}">${[t.label, t.uni != null ? UNI[t.uni] + ' فقط' : forUni(null)].filter(Boolean).join(' · ')}</span></span><span style="width:84px;flex:none">${seatsMeter(t.riders, Z.seats)}</span><span style="display:flex;color:${C.ink3}">${ico(open ? 'up' : 'down', 18)}</span></button>
${open ? `<ol style="margin:0;padding:4px 16px 12px;list-style:none;border-top:1px solid ${C.hair}">${STATIONS.map((s, i) => `<li style="display:flex;align-items:center;gap:10px;min-height:40px;${i ? `border-top:1px solid ${C.hair}` : ''}"><span aria-hidden="true" style="width:22px;height:22px;border-radius:11px;background:${C.sunken};color:${C.ink2};font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center;flex:none">${i + 1}</span><span style="flex:1;min-width:0;${T.small}">${s}</span><span style="${T.small};font-weight:500">${stopAt(t, i) == null ? `<span style="font-weight:400;color:${C.ink3}">لا تقف</span>` : at(stopAt(t, i))}</span></li>`).join('')}<li style="display:flex;align-items:center;gap:10px;min-height:40px;border-top:1px solid ${C.hair}"><span style="display:flex;color:${C.teal}">${ico('school', 20)}</span><span style="flex:1;${T.small};font-weight:500">الوصول إلى الجامعة</span><span style="${T.small};font-weight:600">${at(arrive(t))}</span></li></ol>` : ''}
</div>`;
const detailPhoneBody = `<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">${state('on', 'يظهر للطلاب')}<span style="${T.label};color:${C.ink2}">جامعة دمياط · جامعة حورس</span></div>
${lineStats(true)}
<section style="display:flex;flex-direction:column;gap:10px">
${sectionHead('الرحلات', { phone: true, meta: badge(`ركاب ${TOMORROW}`, 'teal') })}
${seg([{ label: 'الذهاب', count: 5, on: true }, { label: 'العودة', count: 5 }], { full: true, phone: true })}
${GO.map((t, i) => tripCardPhone(t, i === 2)).join('\n')}
</section>
${pricesCard(true)}
${supsCard(true)}
<div style="display:flex;flex-direction:column;gap:8px">${btn('إيقاف الخط', { kind: 'outline', icon: 'power', phone: true, full: true })}${btn('حذف الخط', { kind: 'link', phone: true, full: true, extra: `color:${C.bad};` })}</div>`;
board('AdmLinePhone', { row: 'L', w: 390, title: 'Admin web · Lines · One line · Phone', tab: 'لوحة الشركة · الخطوط · خط الزرقا · هاتف',
  body: (size) => shellPhone({ size, active: 'lines', title: 'خط الزرقا', back: 'الخطوط', body: detailPhoneBody, bottomBar: btn('تعديل الخط', { icon: 'pencil', phone: true, full: true }) }) });

board('AdmLinesEmptyPhone', { row: 'L', w: 390, title: 'Admin web · Lines · First use · Phone', tab: 'لوحة الشركة · الخطوط · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'lines', dot: false, body: firstUse(true) }) });

board('AdmLineStopPhone', { row: 'L', w: 390, min: 844, title: 'Admin web · Lines · Stop a line · Phone', tab: 'لوحة الشركة · الخطوط · إيقاف خط · هاتف',
  body: (size) => shellPhone({ size: size.replace(/height:\d+px/, 'height:844px'), active: 'lines', title: 'خط الزرقا', back: 'الخطوط', body: `<div style="display:flex;align-items:center;gap:8px">${state('on', 'يظهر للطلاب')}</div>${lineStats(true)}`, overlay: scrim(D.stop(true), 'bottom') }) , h: 844 });

export { D as LINE_DIALOGS, detailShell, toast };
