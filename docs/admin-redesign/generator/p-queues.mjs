/** Platform batch · rows A–C: Today, data-correction requests, password requests. */
import {
  board, sectionHead, statCard, attentionList, dataTable, recordList, recordCard, sidePanel, infoRows, dialog, scrim, field,
  badge, btn, note, emptyState, errorState, skeleton, time, ltr, money, ico, cell2, state, toast, C, T, R, CARD,
} from './kit.mjs';
import {
  P, PP, ALL_STUDENTS, DATE, TOMORROW, COMPANIES, LIVE, num, personName, mobile, rnd, pick, sheetBoard, frame, mini, dlgTile, tiles,
  beforeAfter, codeBox, group, phonePage, emptyPhone, coState,
} from './p-common.mjs';

/* ════ A · Today ════ */
const sum = (k) => LIVE.reduce((a, c) => a + c[k], 0);
const noLine = COMPANIES.filter((c) => c.st === 'on' && c.lines[1] === 0);
const noPay = COMPANIES.filter((c) => c.st === 'on' && c.pay === 0);
const noSale = COMPANIES.filter((c) => c.st === 'on' && !c.sale && c.lines[1] > 0 && c.pay > 0);
const ATTN = [
  { count: 3, tone: 'warning', title: '3 طلبات تصحيح بيانات تنتظر قرارك', sub: 'أقدمها منذ يومين · من النورس للنقل والفيروز لنقل الطلاب', action: 'راجع الطلبات', primary: true },
  { count: 2, tone: 'teal', title: 'طالبان نسيا كلمة المرور', sub: 'أحدهما بلا شركة، ولا يستطيع أحد غيرك أن يعطيه رمزاً', action: 'افتح الطلبات' },
  { icon: 'route', tone: 'danger', title: `${noLine[0]?.name ?? 'الياسمين باص'} بلا أي خط`, sub: 'أُنشئت منذ 6 أيام ولا يراها الطلاب في التطبيق', action: 'اعرض الشركة' },
  { icon: 'card', tone: 'danger', title: `${noPay.length} شركات بلا وسيلة دفع`, sub: `${noPay.map((c) => c.name).join(' · ')} — لا يستطيع طلابها أن يدفعوا`, action: 'اعرض الشركات' },
  { icon: 'calendar', tone: 'warning', title: `${noSale[0]?.name ?? 'المدينة للرحلات الجامعية'} لا تعرض أي اشتراك للبيع`, sub: 'لها خطوط ووسيلة دفع، لكن كل الفصول موقوفة عن البيع', action: 'اعرض الشركة' },
  { icon: 'megaphone', tone: 'danger', title: '14 تنبيهاً لم تصل إلى الهواتف في آخر 24 ساعة', sub: 'الإشعارات نفسها ظهرت داخل التطبيق', action: 'افتح الإشعارات' },
];
const stats = (phone) => `<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:${phone ? 12 : 16}px">
${statCard({ label: 'الشركات', icon: 'building', value: COMPANIES.filter((c) => c.st !== 'archived').length, hint: `${LIVE.length} تعمل · 2 موقوفتان`, href: '#', phone })}
${statCard({ label: 'الطلاب', icon: 'users', value: num(ALL_STUDENTS), hint: 'حساباً على المنصة', href: '#', phone })}
${statCard({ label: 'اشتراكات نشطة', icon: 'check', value: num(sum('subs')), hint: 'في كل الشركات اليوم', phone })}
${statCard({ label: 'إيصالات تنتظر', icon: 'receipt', value: sum('rec'), hint: `عند ${LIVE.filter((c) => c.rec).length} شركة`, phone })}
</div>
${statCard({ label: `ركاب الغد · ${TOMORROW}`, icon: 'bus', value: num(sum('go')), unit: `راكباً من ${num(sum('subs'))} مشتركاً`, bar: Math.round(sum('go') / sum('subs') * 100), hint: `التأكيد مفتوح عند أغلب الشركات حتى ${time('6:00', 'ص')} · الأعداد تتغيّر`, phone })}`;
const versionCard = (phone) => `<div style="${CARD};padding:${phone ? '14px 16px' : '16px 20px'};display:flex;flex-direction:column;gap:8px">
<div style="display:flex;align-items:center;gap:8px"><span style="display:flex;color:${C.ink3}">${ico('smartphone', 16, 2)}</span><span style="${T.label};font-weight:500;color:${C.ink2};flex:1">إصدارات التطبيق</span>${btn('غيّرها', { kind: 'link', sm: true, iconEnd: 'fwd' })}</div>
<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px">${[['أندرويد', '2.5.0', '2.3.0'], ['آيفون', '2.5.0', '2.2.0']].map(([p, l, m]) => `<div style="background:${C.ground};border-radius:${R.control}px;padding:8px 12px"><div style="${T.cap};color:${C.ink3}">${p}</div><div style="${T.small};font-weight:600">آخر إصدار ${ltr(l)}</div><div style="${T.cap};color:${C.ink2}">أقل إصدار مسموح ${ltr(m)}</div></div>`).join('')}</div>
</div>`;
const TOP = [...LIVE].sort((a, b) => b.rec - a.rec || b.go - a.go).slice(0, 12);
const recCell = (c) => (c.rec ? `<span style="display:inline-flex;align-items:center;gap:8px"><b style="font-weight:600">${c.rec}</b>${c.rec >= 10 ? badge('متراكمة', 'warning') : ''}</span>` : `<span style="color:${C.disabled}">0</span>`);
const linesCell = (c) => (c.lines[1] ? `${c.lines[0]} <span style="color:${C.ink3};font-size:12px">من ${c.lines[1]}</span>` : badge('بلا خطوط', 'danger'));
const enter = (o = {}) => btn('ادخل', { kind: 'tonal', sm: true, iconEnd: 'fwd', ...o });
const companiesToday = (states = {}) => dataTable({
  caption: 'أرقام اليوم في كل شركة',
  toolbar: { count: `أعلى 12 شركة من ${LIVE.length} تعمل · اضغط شركة لتدخل لوحتها`, sort: 'الأكثر إيصالات منتظرة أولاً' },
  columns: [{ label: 'الشركة' }, { label: 'الطلاب', w: 96 }, { label: 'اشتراكات نشطة', w: 128 }, { label: 'ركاب الغد', w: 104 }, { label: 'إيصالات تنتظر', w: 150, sorted: 'desc' }, { label: 'خطوط تعمل', w: 120 }, { label: 'الإيرادات المسجّلة', w: 160 }, { label: '', w: 104, align: 'end' }],
  rows: TOP.map((c, i) => ({ state: states[i], cells: [cell2(c.name, c.pay ? '' : 'بلا وسيلة دفع', { w: 600 }), num(c.students), num(c.subs), `<b style="font-weight:600">${num(c.go)}</b>`, recCell(c), linesCell(c), money(c.rev), enter()] })),
  foot: ['إجمالي كل الشركات', num(ALL_STUDENTS), num(sum('subs')), num(sum('go')), `${sum('rec')}`, '', money(COMPANIES.reduce((a, c) => a + c.rev, 0)), ''],
});
const todayBody = (attn = ATTN) => `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج قرارك الآن', { meta: attn.length ? badge(`${attn.length} أمور`, 'neutral') : '' })}${attentionList(attn, { zeroTitle: 'لا شيء ينتظر قرارك', zeroSub: 'لا طلبات مفتوحة، وكل شركة تعمل لها خط ووسيلة دفع.' })}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('أرقام المنصة')}${stats(false)}${versionCard(false)}</section>
</div>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('اليوم في كل شركة', { end: btn(`كل الشركات`, { kind: 'link', iconEnd: 'fwd', sm: true }) })}${companiesToday({ 0: 'hover' })}</section>`;
const todayActions = btn('إرسال إشعار من المنصة', { kind: 'outline', icon: 'megaphone' });

board('AdmPlatToday', { row: 'A', w: 1440, title: 'Admin web · Platform · Today · Desktop', tab: 'إدارة المنصة · اليوم',
  body: (size) => P({ size, active: 'p-today', title: 'اليوم', sub: DATE, actions: todayActions, body: todayBody() }) });
board('AdmPlatTodayPhone', { row: 'A', w: 390, title: 'Admin web · Platform · Today · Phone', tab: 'إدارة المنصة · اليوم · هاتف',
  body: (size) => PP({ size, active: 'p-today', sub: DATE, body: `
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('يحتاج قرارك الآن', { phone: true, meta: badge(`${ATTN.length} أمور`, 'neutral') })}${attentionList(ATTN, { phone: true })}</section>
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('أرقام المنصة', { phone: true })}${stats(true)}${versionCard(true)}</section>
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('اليوم في كل شركة', { phone: true, meta: `<span style="${T.label};color:${C.ink2}">أعلى 6 من ${LIVE.length}</span>` })}
${TOP.slice(0, 6).map((c) => recordCard({ title: c.name, sub: `${num(c.students)} طالباً · ${num(c.subs)} اشتراكاً نشطاً`, end: `<span style="display:flex;color:${C.ink3};padding-top:2px">${ico('fwd', 18)}</span>`,
    stats: [['ركاب الغد', num(c.go)], ['إيصالات تنتظر', c.rec]], fields: [['خطوط تعمل', linesCell(c)], ['الإيرادات المسجّلة', money(c.rev)]] })).join('\n')}
${btn(`كل الشركات (${COMPANIES.length})`, { kind: 'outline', phone: true, full: true, iconEnd: 'fwd' })}
</section>` }) });

const loadBody = `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج قرارك الآن')}${skeleton('list', { rows: 4 })}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('أرقام المنصة')}<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px">${skeleton('stat')}${skeleton('stat')}${skeleton('stat')}${skeleton('stat')}</div></section></div>`;
const firstBody = `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج قرارك الآن')}${attentionList([{ icon: 'school', tone: 'teal', title: 'أضف الجامعات أولاً', sub: 'لا تستطيع أي شركة أن تنشئ خطاً قبل أن توجد جامعته هنا', action: 'افتح الجامعات', primary: true }, { icon: 'building', tone: 'teal', title: 'ثم أنشئ أول شركة', sub: 'باسمها ومديرها الأول، وهو يكمل الخطوط ووسائل الدفع', action: 'شركة جديدة' }])}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('أرقام المنصة')}${emptyState({ card: true, icon: 'chart', title: 'لا أرقام بعد', text: 'عندما تعمل أول شركة ويشترك طلابها، ترى هنا عدد الطلاب والاشتراكات وركاب الغد في كل الشركات.' })}</section></div>`;
sheetBoard('AdmPlatTodayStates', 'A', 'Today · States', [
  frame('Loading', 'The shell and the section titles are real from the first frame; only the numbers are grey.', mini(560, { active: 'p-today', title: 'اليوم', sub: DATE, actions: todayActions, body: loadBody })),
  frame('Nothing waits', 'The attention card never disappears: with nothing open it says so in one green row. The numbers and the table stay.', mini(520, { active: 'p-today', title: 'اليوم', sub: DATE, actions: todayActions, badges: {}, body: todayBody([]) })),
  frame('First use · no company yet', 'A new platform: the two things to do, in order, instead of a page of zeros.', mini(540, { active: 'p-today', title: 'اليوم', sub: DATE, badges: {}, body: firstBody })),
  frame('Offline', 'The amber bar, the last loaded numbers, and writing buttons held back.', mini(520, { active: 'p-today', title: 'اليوم', sub: DATE, offline: true, actions: btn('إرسال إشعار من المنصة', { kind: 'outline', icon: 'megaphone', state: 'disabled' }), body: todayBody(ATTN.slice(0, 3).map((a) => ({ ...a, primary: false }))) })),
  frame('Error', 'Plain Arabic and a retry. Navigation keeps working.', mini(520, { active: 'p-today', title: 'اليوم', sub: DATE, body: errorState({ card: true, title: 'تعذّر تحميل أرقام المنصة', text: 'لم نستطع جلب الطلبات وأرقام الشركات. تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
emptyPhone('AdmPlatTodayEmptyPhone', 'A', 'Today', 'p-today', { sub: DATE, empty: { icon: 'building', title: 'لا شركات بعد', text: 'أضف الجامعات، ثم أنشئ أول شركة باسمها ومديرها الأول. بعدها ترى هنا ما يحتاج قرارك وأرقام كل شركة.', action: btn('شركة جديدة', { icon: 'plus', phone: true, full: true }) + btn('افتح الجامعات', { kind: 'secondary', phone: true, full: true }) } });

/* ════ B · Data-correction requests ════ */
const CORR = [
  { who: 'عبد الرحمن محمد السيد الشربيني', ph: '011 3456 7890', f: 'الاسم', old: 'عبد الرحمن محمد الشربينى', neu: 'عبد الرحمن محمد السيد الشربيني', co: 'النورس للنقل', by: 'أحمد سعيد النورس', ago: 'منذ يومين', note: 'الاسم في البطاقة الجامعية رباعي، والطالب كتبه ثلاثياً وبخطأ في الياء.', mem: ['النورس للنقل', 'الفيروز لنقل الطلاب'] },
  { who: 'ملك حسام الدين منصور', ph: '015 5678 9012', f: 'الجامعة', old: 'جامعة دمياط', neu: 'جامعة حورس', co: 'الفيروز لنقل الطلاب', by: 'سامح فتحي البنا', ago: 'منذ يوم', note: 'حوّلت من جامعة دمياط هذا العام.', mem: ['الفيروز لنقل الطلاب'] },
  { who: 'يوسف أحمد عبد الفتاح', ph: '012 4567 8901', f: 'الاسم', old: 'يوسف احمد', neu: 'يوسف أحمد عبد الفتاح', co: 'النورس للنقل', by: 'أحمد سعيد النورس', ago: 'منذ 5 ساعات', note: '', mem: ['النورس للنقل'] },
  ...Array.from({ length: 6 }, (_, i) => { const n = personName(); return { who: n, ph: mobile(), f: i % 3 ? 'الاسم' : 'الجامعة', old: i % 3 ? n.split(' ').slice(0, 2).join(' ') : 'جامعة المنصورة', neu: i % 3 ? n : 'جامعة المنصورة الجديدة', co: pick(LIVE).name, by: personName(), ago: `منذ ${rnd(1, 4)} ساعات`, note: '', mem: [] }; }),
];
const corrSub = 'تقترحها الشركات عندما يكون اسم طالب أو جامعته خطأ. اعتمادك يغيّر بيانات الحساب عند كل الشركات التي ينتمي إليها.';
const corrTable = (rows, states = {}) => dataTable({
  caption: 'طلبات تصحيح البيانات',
  toolbar: { search: 'ابحث باسم الطالب أو الشركة', count: `${rows.length} طلبات تنتظر قرارك`, sort: 'الأقدم أولاً' },
  columns: [{ label: 'الطالب', w: 250 }, { label: 'يُطلب تغيير', w: 112 }, { label: 'من' }, { label: 'إلى' }, { label: 'الشركة الطالبة', w: 180 }, { label: 'منذ', w: 110, sorted: 'asc' }, { label: '', w: 96, align: 'end' }],
  rows: rows.map((r, i) => ({ state: states[i], cells: [cell2(r.who, ltr(r.ph)), badge(r.f, 'neutral'), `<span style="color:${C.ink2}">${r.old}</span>`, `<b style="font-weight:600">${r.neu}</b>`, r.co, r.ago, btn('راجع', { kind: 'tonal', sm: true })] })),
});
const corrDetail = (r, phone) => `${beforeAfter(r.f, r.old, r.neu, { phone })}
${group('من طلب التغيير', infoRows([['الشركة', r.co], ['كتبه', r.by], ['متى', `${r.ago} · الخميس 8 أكتوبر ${time('4:20', 'م')}`], ['ملاحظة الشركة', r.note || `<span style="color:${C.ink3}">لم تكتب الشركة ملاحظة</span>`]]))}
${group('الطالب', infoRows([['رقم الهاتف', ltr(r.ph)], ['شركاته', r.mem.map((m) => badge(m, 'teal')).join(' ')], ['اشتراكات نشطة', '1']]))}
${note({ tone: 'teal', title: `يتغيّر ${r.f} عند ${r.mem.length === 1 ? 'شركة واحدة' : `${r.mem.length} شركات`}`, text: `سيظهر ${r.f} الجديد في بطاقة الطالب وفي إيصالاته القادمة وفي قوائم ${r.mem.join(' و')}. الإيصالات القديمة لا تتغيّر.` })}`;
const corrFooter = (phone) => `${btn('ارفض الطلب', { kind: 'dangerQuiet', phone, full: phone })}${phone ? '' : '<span style="flex:1"></span>'}${btn('اعتمد التغيير', { icon: 'check', phone, full: phone })}`;
const rejectDlg = (phone) => dialog({ phone, icon: 'x', tone: 'danger', title: 'رفض طلب تصحيح الاسم؟', body: `<span>يبقى اسم الطالب كما هو: «${CORR[0].old}». تعرف ${CORR[0].co} أن الطلب رُفض وترى السبب الذي تكتبه.</span>${field({ type: 'textarea', label: 'سبب الرفض', rows: 2, phone, value: 'الاسم المقترح لا يطابق البطاقة التي أرسلها الطالب.' })}`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('ارفض الطلب', { kind: 'danger', phone, full: phone })] });

board('AdmPlatCorrections', { row: 'B', w: 1440, title: 'Admin web · Platform · Correction requests · Desktop', tab: 'إدارة المنصة · طلبات تصحيح البيانات',
  body: (size) => P({ size, active: 'p-corrections', title: 'طلبات تصحيح البيانات', sub: corrSub, badges: { corrections: 9, requests: 2 }, body: corrTable(CORR, { 1: 'hover' }) }) });
board('AdmPlatCorrectionsPanel', { row: 'B', w: 1440, min: 980, title: 'Admin web · Platform · Correction requests · Decision panel', tab: 'إدارة المنصة · قرار طلب تصحيح',
  body: (size) => P({ size, active: 'p-corrections', title: 'طلبات تصحيح البيانات', sub: corrSub, badges: { corrections: 9, requests: 2 }, body: corrTable(CORR, { 0: 'open' }),
    overlay: scrim(sidePanel({ w: 560, title: CORR[0].who, sub: 'طلب تصحيح الاسم · الأول من 9', meta: state('open', 'ينتظر قرارك'), body: corrDetail(CORR[0]), footer: corrFooter(false) }), 'end') }) });
board('AdmPlatCorrectionsPhone', { row: 'B', w: 390, title: 'Admin web · Platform · Correction requests · Phone', tab: 'إدارة المنصة · طلبات تصحيح البيانات · هاتف',
  body: (size) => PP({ size, active: 'p-corrections', sub: corrSub, body: recordList({ toolbar: { search: 'ابحث باسم الطالب أو الشركة', count: '9 طلبات تنتظر قرارك', sort: 'الأقدم أولاً' },
    cards: CORR.slice(0, 5).map((r) => recordCard({ title: r.who, sub: ltr(r.ph), end: badge(r.f, 'neutral'), fields: [['من', `<span style="color:${C.ink2}">${r.old}</span>`], ['إلى', `<b style="font-weight:600">${r.neu}</b>`], ['الشركة الطالبة', r.co], ['منذ', r.ago]] })) }) }) });
board('AdmPlatCorrectionsDetailPhone', { row: 'B', w: 390, title: 'Admin web · Platform · Correction request · Decision · Phone', tab: 'إدارة المنصة · قرار طلب تصحيح · هاتف',
  body: (size) => phonePage({ size, active: 'p-corrections', back: 'طلبات تصحيح البيانات', title: 'طلب تصحيح الاسم', body: `<div><div style="${T.card}">${CORR[0].who}</div><div style="margin-top:6px">${state('open', 'ينتظر قرارك')}</div></div>${corrDetail(CORR[0], true)}`, bottomBar: `${btn('اعتمد التغيير', { icon: 'check', phone: true, full: true })}${btn('ارفض الطلب', { kind: 'dangerQuiet', phone: true, full: true })}` }) });
sheetBoard('AdmPlatCorrectionsStates', 'B', 'Correction requests · Dialogs and states', [
  tiles([
    dlgTile('Reject · desktop', 'The one field is the reason; the company sees it. Approving needs no second question: the panel already says exactly what changes.', rejectDlg(false), { h: 380 }),
    dlgTile('After approving', 'The row leaves, the panel moves to the next request, and a toast confirms.', `<div style="display:flex;flex-direction:column;gap:12px">${toast({ text: 'تم تغيير اسم عبد الرحمن عند شركتين.' })}${toast({ tone: 'danger', text: 'تعذّر حفظ القرار. الطلب ما زال في القائمة.', action: 'حاول مرة أخرى' })}</div>`, { w: 520, h: 380 }),
    dlgTile('Reject · phone', 'Bottom-anchored, confirm first.', rejectDlg(true), { phone: true, h: 520 }),
  ]),
  frame('Empty', 'Says what the page is for and where requests come from. There is nothing to create here, so no button.', mini(480, { active: 'p-corrections', title: 'طلبات تصحيح البيانات', sub: corrSub, badges: { requests: 2 }, body: emptyState({ card: true, icon: 'pencil', title: 'لا طلبات تصحيح الآن', text: 'عندما تجد شركة خطأ في اسم طالب أو جامعته، ترسل الطلب من صفحة طلابها ويظهر هنا لتقرر.' }) })),
  frame('One request', 'One row keeps the same table.', mini(360, { active: 'p-corrections', title: 'طلبات تصحيح البيانات', sub: corrSub, badges: { corrections: 1, requests: 2 }, body: dataTable({ columns: [{ label: 'الطالب', w: 250 }, { label: 'يُطلب تغيير', w: 112 }, { label: 'من' }, { label: 'إلى' }, { label: 'الشركة الطالبة', w: 180 }, { label: 'منذ', w: 110 }, { label: '', w: 96, align: 'end' }], toolbar: { count: 'طلب واحد ينتظر قرارك' }, rows: [{ cells: [cell2(CORR[1].who, ltr(CORR[1].ph)), badge(CORR[1].f), CORR[1].old, `<b style="font-weight:600">${CORR[1].neu}</b>`, CORR[1].co, CORR[1].ago, btn('راجع', { kind: 'tonal', sm: true })] }] }) })),
  frame('Loading', '', mini(420, { active: 'p-corrections', title: 'طلبات تصحيح البيانات', sub: corrSub, body: skeleton('table', { rows: 4, cols: 6 }) })),
  frame('Error', '', mini(460, { active: 'p-corrections', title: 'طلبات تصحيح البيانات', sub: corrSub, body: errorState({ card: true, title: 'تعذّر تحميل الطلبات', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
emptyPhone('AdmPlatCorrectionsEmptyPhone', 'B', 'Correction requests', 'p-corrections', { sub: corrSub, empty: { icon: 'pencil', title: 'لا طلبات تصحيح الآن', text: 'عندما تجد شركة خطأ في اسم طالب أو جامعته، ترسل الطلب من صفحة طلابها ويظهر هنا لتقرر.' } });

/* ════ C · Password requests ════ */
const PST = { pending: state('open', 'ينتظر التحقق'), issued: badge(`رمز صالح حتى ${'10:42'} ص`, 'teal'), done: state('done', 'غيّر كلمة المرور'), cancelled: state('cancelled', 'أُلغي'), expired: badge('انتهت صلاحية الرمز', 'neutral') };
const PW = [
  { who: 'سلمى طارق عبد الحميد', ph: '011 7890 1234', co: null, at: `اليوم ${'9:05'} ص`, st: 'pending' },
  { who: 'عمر خالد إسماعيل البنا', ph: '010 6789 0123', co: 'النورس للنقل', at: `اليوم ${'8:40'} ص`, st: 'pending' },
  { who: 'مريم عبد الله الدسوقي', ph: '012 2210 4478', co: 'باصات النيل', at: `اليوم ${'10:12'} ص`, st: 'issued' },
  ...Array.from({ length: 11 }, (_, i) => ({ who: personName(), ph: mobile(), co: i % 4 === 0 ? null : pick(LIVE).name, at: `${rnd(3, 9)} أكتوبر ${rnd(1, 11)}:${pick(['05', '18', '32', '47'])} ${pick(['ص', 'م'])}`, st: pick(['done', 'done', 'done', 'cancelled', 'expired']) })),
];
const pwSub = 'طلاب كل الشركات، ومعهم من لا شركة له. اتصل بالطالب لتتأكد أنه هو، ثم أعطه رمزاً يدخل به مرة واحدة ويختار كلمة مرور جديدة.';
const coCell = (c) => c ?? badge('بلا شركة', 'warning');
const pwAct = (r) => (r.st === 'pending' ? btn('أصدر رمزاً', { sm: true, icon: 'key' }) : r.st === 'issued' ? btn('رمز جديد', { kind: 'tonal', sm: true }) : '');
const pwTable = (rows, states = {}, f = 0) => dataTable({
  caption: 'طلبات كلمة المرور',
  toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', filters: [{ label: 'مفتوحة', on: f === 0, count: 3 }, { label: 'كل الطلبات', on: f === 1, count: 14 }], count: f ? '14 طلباً في آخر 30 يوماً' : '', sort: 'الأحدث أولاً' },
  columns: [{ label: 'الطالب' }, { label: 'شركته', w: 220 }, { label: 'وقت الطلب', w: 180, sorted: 'desc' }, { label: 'الحالة', w: 210 }, { label: '', w: 150, align: 'end' }, { label: '', w: 56, align: 'end' }],
  rows: rows.map((r, i) => ({ state: states[i], muted: !['pending', 'issued'].includes(r.st), cells: [cell2(r.who, ltr(r.ph)), coCell(r.co), r.at, PST[r.st], pwAct(r), ['pending', 'issued'].includes(r.st) ? `<button type="button" aria-label="إلغاء طلب ${r.who}" title="إلغاء الطلب" style="width:36px;height:36px;border-radius:10px;color:${C.ink2};display:inline-flex;align-items:center;justify-content:center">${ico('x', 18)}</button>` : ''] })),
});
const issueDlg = (phone) => dialog({ phone, icon: 'phone', title: 'هل تأكدت أنه سلمى طارق؟', body: `<span>اتصل بها أولاً على ${ltr('011 7890 1234')} واسألها عن جامعتها وخطها. من يأخذ الرمز يدخل الحساب.</span><span>بعد التأكد نُصدر رمزاً من 6 أرقام صالحاً 30 دقيقة، ويظهر لك <b style="font-weight:600;color:${C.ink}">مرة واحدة فقط</b>.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('أصدر الرمز', { icon: 'key', phone, full: phone })] });
const codeDlg = (phone) => dialog({ phone, icon: 'check', tone: 'success', title: 'رمز سلمى طارق عبد الحميد', body: `${codeBox('482 915', { spacing: 6 })}<span>أملِه عليها في المكالمة على ${ltr('011 7890 1234')}. تكتبه في التطبيق مع كلمة مرور جديدة. صالح حتى ${time('9:41', 'ص')}، ولن يظهر مرة أخرى بعد إغلاق هذه النافذة.</span>`,
  actions: [btn('أغلق، أبلغتها بالرمز', { phone, full: phone })] });
const cancelDlg = (phone) => dialog({ phone, icon: 'x', tone: 'danger', title: 'إلغاء طلب عمر خالد؟', body: `<span>يُغلق الطلب ولا يصدر له رمز. تبقى كلمة مروره الحالية كما هي، ويستطيع أن يطلب من جديد من التطبيق.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('ألغِ الطلب', { kind: 'danger', phone, full: phone })] });

board('AdmPlatPassword', { row: 'C', w: 1440, title: 'Admin web · Platform · Password requests · Desktop', tab: 'إدارة المنصة · طلبات كلمة المرور',
  body: (size) => P({ size, active: 'p-password-requests', title: 'طلبات كلمة المرور', sub: pwSub, badges: { corrections: 3, requests: 3 }, body: pwTable(PW, {}, 1) }) });
board('AdmPlatPasswordIssue', { row: 'C', w: 1440, title: 'Admin web · Platform · Password requests · Verify, then issue', tab: 'إدارة المنصة · إصدار رمز',
  body: (size) => P({ size, active: 'p-password-requests', title: 'طلبات كلمة المرور', sub: pwSub, badges: { corrections: 3, requests: 3 }, body: pwTable(PW.slice(0, 3), { 0: 'selected' }), overlay: scrim(issueDlg(false)) }) });
board('AdmPlatPasswordCode', { row: 'C', w: 1440, title: 'Admin web · Platform · Password requests · The code, shown once', tab: 'إدارة المنصة · الرمز',
  body: (size) => P({ size, active: 'p-password-requests', title: 'طلبات كلمة المرور', sub: pwSub, badges: { corrections: 3, requests: 3 }, body: pwTable(PW.slice(0, 3), { 0: 'selected' }), overlay: scrim(codeDlg(false)) }) });
const pwCard = (r) => recordCard({ title: r.who, sub: ltr(r.ph), end: PST[r.st], fields: [['شركته', coCell(r.co)], ['وقت الطلب', r.at]],
  actions: r.st === 'pending' ? `${btn('أصدر رمزاً', { sm: true, icon: 'key', extra: 'height:44px;flex:1;' })}${btn('ألغِ الطلب', { kind: 'secondary', sm: true, extra: 'height:44px;' })}` : r.st === 'issued' ? btn('رمز جديد', { kind: 'tonal', sm: true, extra: 'height:44px;flex:1;' }) : '' });
board('AdmPlatPasswordPhone', { row: 'C', w: 390, title: 'Admin web · Platform · Password requests · Phone', tab: 'إدارة المنصة · طلبات كلمة المرور · هاتف',
  body: (size) => PP({ size, active: 'p-password-requests', sub: pwSub, body: recordList({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', filters: [{ label: 'مفتوحة', on: true, count: 3 }, { label: 'كل الطلبات', count: 14 }] }, cards: PW.slice(0, 3).map(pwCard) }) }) });
board('AdmPlatPasswordCodePhone', { row: 'C', w: 390, min: 844, title: 'Admin web · Platform · Password requests · The code · Phone', tab: 'إدارة المنصة · الرمز · هاتف',
  body: (size) => PP({ size, active: 'p-password-requests', sub: pwSub, body: recordList({ toolbar: { search: 'ابحث بالاسم أو رقم الهاتف' }, cards: PW.slice(0, 2).map(pwCard) }), overlay: scrim(codeDlg(true), 'bottom') }) });
sheetBoard('AdmPlatPasswordStates', 'C', 'Password requests · Dialogs and states', [
  tiles([
    dlgTile('Cancel a request', 'The X at the end of an open row.', cancelDlg(false)),
    dlgTile('Verify · phone', 'Same two steps on a phone: verify, then the code.', issueDlg(true), { phone: true, h: 480 }),
    dlgTile('Failure', 'If the code cannot be issued the row stays open.', toast({ tone: 'danger', text: 'تعذّر إصدار الرمز. لم يتغيّر شيء في حساب الطالب.', action: 'حاول مرة أخرى' }), { w: 520, h: 200 }),
  ]),
  frame('Empty · no open request', 'The page stays in the navigation with no badge. The filter «كل الطلبات» still shows the last 30 days.', mini(480, { active: 'p-password-requests', title: 'طلبات كلمة المرور', sub: pwSub, badges: { corrections: 3 }, body: dataTable({ columns: [], rows: [], toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', filters: [{ label: 'مفتوحة', on: true, count: 0 }, { label: 'كل الطلبات', count: 11 }] }, empty: emptyState({ icon: 'key', title: 'لا أحد ينتظر رمزاً', text: 'عندما يضغط طالب «نسيت كلمة المرور» في التطبيق يظهر طلبه هنا، وعند مدير شركته إن كانت له شركة.' }) }) })),
  frame('Loading', '', mini(400, { active: 'p-password-requests', title: 'طلبات كلمة المرور', sub: pwSub, body: skeleton('table', { rows: 4, cols: 5 }) })),
  frame('Error', '', mini(460, { active: 'p-password-requests', title: 'طلبات كلمة المرور', sub: pwSub, body: errorState({ card: true, title: 'تعذّر تحميل الطلبات', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
emptyPhone('AdmPlatPasswordEmptyPhone', 'C', 'Password requests', 'p-password-requests', { sub: pwSub, empty: { icon: 'key', title: 'لا أحد ينتظر رمزاً', text: 'عندما يضغط طالب «نسيت كلمة المرور» في التطبيق يظهر طلبه هنا، وعند مدير شركته إن كانت له شركة.' } });
