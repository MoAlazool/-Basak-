/** Platform batch · rows F–G: all students, platform notifications. */
import {
  board, sectionHead, statCard, dataTable, recordList, recordCard, sidePanel, infoRows, dialog, scrim, field, fieldRow, checkbox,
  badge, btn, note, emptyState, errorState, skeleton, time, ltr, ico, cell2, state, toast, C, T, R, CARD, FONT, SHADOW,
} from './kit.mjs';
import {
  P, PP, COMPANIES, LIVE, ALL_STUDENTS, UNIS, num, personName, mobile, rnd, pick, sheetBoard, frame, mini, dlgTile, tiles, group, codeBox, phonePage, emptyPhone, dropFilter, card,
} from './p-common.mjs';

/* ════ F · All students ════ */
const stSub = 'كل حساب طالب على المنصة والشركات التي ينتمي إليها. للقراءة والبحث؛ الاشتراكات والإيصالات تُدار من داخل كل شركة.';
const ST = Array.from({ length: 25 }, (_, i) => {
  const k = i === 4 || i === 15 ? 0 : i === 1 || i === 9 || i === 20 ? 2 : i === 12 ? 3 : 1;
  const mem = Array.from({ length: k }, (_, j) => ({ co: LIVE[(i * 5 + j * 7) % LIVE.length].name, on: !(j === 1 && i === 9) }));
  return { n: i === 1 ? 'عبد الرحمن محمد السيد الشربيني' : personName(), ph: i === 1 ? '011 3456 7890' : mobile(), uni: i === 1 ? 'جامعة حورس' : UNIS[(i * 3) % 9].name, mem, subs: mem.filter((m) => m.on).length ? (k > 1 && i !== 9 ? 2 : 1) - (i % 6 === 0 ? 1 : 0) : 0, at: `${rnd(1, 28)} ${['سبتمبر', 'أكتوبر', 'فبراير'][i % 3]} ${i % 4 ? 2026 : 2025}` };
});
const memChips = (s) => (s.mem.length ? `<span style="display:flex;flex-wrap:wrap;gap:4px">${s.mem.map((m) => (m.on ? badge(m.co, 'teal') : badge(`${m.co} · أُزيل`, 'neutral'))).join('')}</span>` : badge('بلا شركة', 'warning'));
const stChips = (on = 0) => [{ label: 'كل الحسابات', on: on === 0, count: num(ALL_STUDENTS) }, { label: 'بلا شركة', on: on === 1, count: 143 }, { label: 'في أكثر من شركة', on: on === 2, count: 212 }];
const stCols = [{ label: 'الطالب' }, { label: 'رقم الهاتف', w: 140 }, { label: 'الجامعة', w: 200 }, { label: 'شركاته', w: 270 }, { label: 'اشتراكات نشطة', w: 124 }, { label: 'سُجّل في', w: 132, sorted: 'desc' }];
const stRow = (s) => [`<span style="font-weight:500">${s.n}</span>`, ltr(s.ph), s.uni, memChips(s), s.subs ? `${s.subs}` : `<span style="color:${C.disabled}">0</span>`, s.at];
const stTable = (rows, states = {}, o = {}) => dataTable({ caption: 'كل الطلاب', rowH: 56,
  toolbar: { search: 'ابحث بالاسم أو الهاتف أو الجامعة', searchValue: o.q, filters: stChips(o.chip ?? 0), actions: dropFilter(o.co ?? 'كل الشركات', { icon: 'building', on: !!o.co }), sort: 'الأحدث تسجيلاً' },
  columns: stCols, rows: rows.map((s, i) => ({ state: states[i], cells: stRow(s) })), pagination: o.pag === null ? undefined : (o.pag ?? { from: 1, to: 25, total: ALL_STUDENTS, page: 1, pages: Math.ceil(ALL_STUDENTS / 25) }) });
const S1 = ST[1];
const memRow = (co, since, on, sub) => `<div style="display:flex;align-items:center;gap:12px;padding:10px 0;border-top:1px solid ${C.hair}"><div style="flex:1;min-width:0"><div style="${T.small};font-weight:500">${co}</div><div style="${T.label};color:${C.ink2}">${on ? `عضو منذ ${since}` : `أُزيل · كان عضواً منذ ${since}`}${sub ? ` · ${sub}` : ''}</div></div>${btn('افتحه في الشركة', { kind: 'link', sm: true, iconEnd: 'fwd' })}</div>`;
const stPanelBody = (phone) => `${note({ tone: 'warning', title: 'طلب تصحيح اسم ينتظر قرارك', text: 'من النورس للنقل، منذ يومين.', action: btn('راجع', { kind: 'outline', sm: true }) })}
${group('الحساب', infoRows([['رقم الهاتف', ltr(S1.ph)], ['الجامعة', 'جامعة حورس · الصيدلة'], ['سُجّل في', '14 سبتمبر 2026'], ['اشتراكات نشطة', '2']]))}
${group('شركاته', `<div style="display:flex;flex-direction:column;margin-top:-2px">${memRow('النورس للنقل', '14 سبتمبر 2026', true, 'اشتراك نشط')}${memRow('الفيروز لنقل الطلاب', '3 أكتوبر 2026', true, 'اشتراك نشط')}${memRow('باصات النيل', '20 فبراير 2026', false)}</div>`, badge('3', 'neutral'))}
${note({ tone: 'teal', text: 'لتغيير اشتراك أو مراجعة إيصال أو حذف الحساب افتح الطالب في شركته. الاسم والجامعة يتغيّران بطلب تصحيح.' })}`;
const resetDlg = (phone) => dialog({ phone, icon: 'key', tone: 'warning', title: `تعيين كلمة مرور مؤقتة لعبد الرحمن؟`, body: `<span>تتوقف كلمة مروره الحالية فوراً، ويُطلب منه تغيير المؤقتة عند أول دخول. استعمله لمن لا يستطيع انتظار الرمز.</span>
${field({ phone, type: 'radio', label: 'كلمة المرور المؤقتة', cols: 2, options: [{ label: 'ننشئها تلقائياً', on: true }, { label: 'أكتبها بنفسي' }] })}
${field({ phone, type: 'checkbox', label: `تأكدت من هويته بالاتصال على ${S1.ph}`, on: true })}`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('عيّن كلمة المرور', { icon: 'key', phone, full: phone })] });
const resetDone = dialog({ icon: 'check', tone: 'success', title: 'تم تغيير كلمة مرور عبد الرحمن', body: `${codeBox('Bus-7Q4m-Kx92', { size: 24, spacing: 2, copy: 'انسخ كلمة المرور' })}<span>سلّمها له بنفسك في مكالمة. تظهر هنا مرة واحدة فقط، وسيُطلب منه تغييرها عند أول دخول.</span>`, actions: [btn('أغلق، سلّمتها له')] });

board('AdmPlatStudents', { row: 'F', w: 1440, title: 'Admin web · Platform · All students · Desktop', tab: 'إدارة المنصة · كل الطلاب',
  body: (size) => P({ size, active: 'p-students', title: 'كل الطلاب', sub: stSub, body: stTable(ST, { 6: 'hover' }) }) });
board('AdmPlatStudentsPanel', { row: 'F', w: 1440, h: 1000, title: 'Admin web · Platform · All students · Student panel', tab: 'إدارة المنصة · طالب',
  body: (size) => P({ size, active: 'p-students', title: 'كل الطلاب', sub: stSub, body: stTable(ST, { 1: 'open' }),
    overlay: scrim(sidePanel({ w: 520, title: S1.n, sub: 'حساب طالب · في شركتين', body: stPanelBody(false), footer: `<span style="flex:1"></span>${btn('عيّن كلمة مرور مؤقتة', { kind: 'secondary', icon: 'key' })}` }), 'end') }) });
board('AdmPlatStudentsPhone', { row: 'F', w: 390, title: 'Admin web · Platform · All students · Phone', tab: 'إدارة المنصة · كل الطلاب · هاتف',
  body: (size) => PP({ size, active: 'p-students', sub: stSub, body: recordList({ toolbar: { search: 'ابحث بالاسم أو الهاتف أو الجامعة', filters: stChips(0), count: `${num(ALL_STUDENTS)} حساباً`, sort: 'كل الشركات' },
    cards: ST.slice(0, 6).map((s) => recordCard({ title: s.n, sub: ltr(s.ph), fields: [['الجامعة', s.uni], ['شركاته', `<span style="display:inline-flex;justify-content:flex-end">${memChips(s)}</span>`], ['اشتراكات نشطة', `${s.subs}`], ['سُجّل في', s.at]] })), pagination: { from: 1, to: 25, total: ALL_STUDENTS, page: 1, pages: 300 } }) }) });
board('AdmPlatStudentPhone', { row: 'F', w: 390, title: 'Admin web · Platform · Student · Phone page', tab: 'إدارة المنصة · طالب · هاتف',
  body: (size) => phonePage({ size, active: 'p-students', back: 'كل الطلاب', title: 'عبد الرحمن الشربيني', body: `<div><div style="${T.card}">${S1.n}</div><div style="${T.label};color:${C.ink2}">حساب طالب · في شركتين</div></div>${stPanelBody(true)}`, bottomBar: btn('عيّن كلمة مرور مؤقتة', { kind: 'secondary', icon: 'key', phone: true, full: true }) }) });
sheetBoard('AdmPlatStudentsStates', 'F', 'All students · Dialogs and states', [
  tiles([
    dlgTile('Temporary password', 'The one write the platform has on a student. The existing dialog keeps its choice (generate or type) and its identity tick.', resetDlg(false), { h: 440 }),
    dlgTile('Shown once', 'The same «shown once» box as the reset code.', resetDone, { h: 440 }),
    dlgTile('Temporary password · phone', '', resetDlg(true), { phone: true, h: 620 }),
  ]),
  frame('Search with no match', 'Says what was searched and offers the way back.', mini(460, { active: 'p-students', title: 'كل الطلاب', sub: stSub, body: dataTable({ columns: [], rows: [], toolbar: { search: 'ابحث', searchValue: '0109 555', filters: stChips(0), actions: dropFilter('النورس للنقل', { icon: 'building', on: true }) }, empty: emptyState({ icon: 'search', title: 'لا حساب يطابق «0109 555» في النورس للنقل', text: 'جرّب الاسم، أو ابحث في كل الشركات.', action: btn('ابحث في كل الشركات', { kind: 'secondary' }) }) }) })),
  frame('Filter · no company, one row', 'Accounts with no company are the ones only the platform can help.', mini(470, { active: 'p-students', title: 'كل الطلاب', sub: stSub, body: stTable([ST[4]], {}, { chip: 1, pag: null }) })),
  frame('Empty · first use', 'Students create their own accounts in the app; nothing to add here.', mini(460, { active: 'p-students', title: 'كل الطلاب', sub: stSub, badges: {}, body: emptyState({ card: true, icon: 'users', title: 'لا طلاب بعد', text: 'يظهر الطالب هنا عندما ينشئ حسابه في التطبيق أو تضيفه شركة من صفحة طلابها.' }) })),
  frame('Loading', 'A later page or a new search keeps the old rows, dimmed, until the new ones arrive.', mini(420, { active: 'p-students', title: 'كل الطلاب', sub: stSub, body: skeleton('table', { rows: 4, cols: 6 }) })),
  frame('Error', '', mini(460, { active: 'p-students', title: 'كل الطلاب', sub: stSub, body: errorState({ card: true, title: 'تعذّر تحميل الطلاب', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
emptyPhone('AdmPlatStudentsEmptyPhone', 'F', 'All students', 'p-students', { sub: stSub, empty: { icon: 'users', title: 'لا طلاب بعد', text: 'يظهر الطالب هنا عندما ينشئ حسابه في التطبيق أو تضيفه شركة من صفحة طلابها.' } });

/* ════ G · Platform notifications ════ */
const ntSub = 'ما أرسلته المنصة وما أرسلته كل شركة لطلابها. الإشعار يظهر داخل التطبيق دائماً، وكتنبيه على الهاتف إن كانت التنبيهات مفعّلة.';
const newNt = (o = {}) => btn('إشعار جديد', { icon: 'plus', ...o });
const pushStrip = (phone, o = {}) => `<section style="display:flex;flex-direction:column;gap:${phone ? 10 : 12}px">${sectionHead('التنبيهات على الهواتف', { phone, meta: o.off ? state('failed', 'غير مربوطة') : state('done', 'تعمل') })}
${o.off ? note({ tone: 'warning', title: 'خدمة التنبيهات غير مربوطة', text: 'الإشعارات تصل داخل التطبيق فقط ولا تظهر كتنبيه على الهاتف.' }) : ''}
<div style="display:grid;grid-template-columns:repeat(${phone ? 2 : 4},minmax(0,1fr));gap:${phone ? 12 : 16}px">
${statCard({ phone, label: 'هواتف مسجّلة', icon: 'smartphone', value: num(5120), hint: `آيفون ${num(1840)} · أندرويد ${num(3280)}` })}
${statCard({ phone, label: 'تنتظر الإرسال الآن', icon: 'clock', value: 36 })}
${statCard({ phone, label: 'سُلّمت لخدمة التنبيهات', icon: 'check', value: num(8412), hint: 'آخر 24 ساعة' })}
${statCard({ phone, label: 'فشلت', icon: 'alert', tone: 'danger', value: 14, hint: 'آخر 24 ساعة' })}
</div>
<p style="margin:0;${T.label};color:${C.ink3}">«سُلّمت» تعني أن خدمة التنبيهات استلمتها لتوصلها، لا أنها ظهرت على كل هاتف.</p></section>`;
const NT = [
  { t: 'إجازة 6 أكتوبر', b: 'لا رحلات يوم الثلاثاء 6 أكتوبر. تعود الرحلات الأربعاء في مواعيدها.', by: 'المنصة · 26 شركة', st: 'sent', at: `5 أكتوبر ${'6:00'} م`, to: 6102, read: 4318 },
  { t: 'تحديث جديد للتطبيق', b: 'حدّث التطبيق لتأكيد الركوب بضغطة واحدة من الإشعار.', by: 'المنصة · 26 شركة', st: 'scheduled', at: `غداً ${'9:00'} ص`, to: null, read: null },
  { t: 'تأخير رحلة 7:15 ص', b: 'رحلة فارسكور تتأخر 20 دقيقة اليوم بسبب عطل. نعتذر.', by: 'النورس للنقل', st: 'sent', at: `اليوم ${'6:40'} ص`, to: 71, read: 64 },
  { t: 'موعد تجديد الفصل الثاني', b: 'باب الاشتراك في الفصل الثاني مفتوح حتى 7 فبراير.', by: 'باصات النيل', st: 'failed', at: `أمس ${'8:12'} م`, to: 0, read: 0 },
  { t: 'تغيير موقف المحطة الثالثة', b: 'موقف الحي الثالث انتقل أمام الصيدلية بداية من الأحد.', by: 'الفيروز لنقل الطلاب', st: 'cancelled', at: `8 أكتوبر ${'7:00'} ص`, to: null, read: null },
  ...Array.from({ length: 20 }, (_, i) => ({ ...(([t, b]) => ({ t, b }))([['تذكير بتأكيد الركوب', 'أكّد ركوبك قبل 6:00 ص حتى نحجز لك مقعداً.'], ['تعديل موعد رحلة العودة', 'رحلة العودة 3:00 م تتحرك 3:30 م هذا الأسبوع فقط.'], ['إجازة رسمية', 'لا رحلات يوم الخميس. تعود الرحلات السبت في مواعيدها.'], ['خط جديد إلى جامعة حورس', 'بدأ خط جديد إلى جامعة حورس. اشترك من صفحة الخطوط.'], ['آخر موعد لرفع الإيصال', 'ارفع إيصال الدفع قبل نهاية الأسبوع ليبقى اشتراكك نشطاً.'], ['تغيير رقم التواصل', 'رقم خدمة العملاء تغيّر. تجده في بطاقتك.']][i % 6]), by: pick(LIVE).name, st: i % 9 === 4 ? 'scheduled' : 'sent', at: `${9 - Math.floor(i / 3)} أكتوبر ${rnd(5, 9)}:${pick(['00', '15', '30', '45'])} ${pick(['ص', 'م'])}`, to: rnd(30, 520), read: 0 })).map((n) => ({ ...n, read: n.st === 'sent' ? Math.round(n.to * rnd(55, 93) / 100) : null, to: n.st === 'sent' ? n.to : null })),
];
const ntChips = (on = 0) => [{ label: 'الكل', on: on === 0, count: 312 }, { label: 'أُرسل', on: on === 1, count: 287 }, { label: 'مجدول', on: on === 2, count: 9 }, { label: 'فشل الإرسال', on: on === 3, count: 4 }, { label: 'أُلغي', on: on === 4, count: 12 }];
const dash = `<span style="color:${C.disabled}">—</span>`;
const ntCols = [{ label: 'الإشعار' }, { label: 'المرسل', w: 200 }, { label: 'الحالة', w: 136 }, { label: 'الموعد', w: 170, sorted: 'desc' }, { label: 'المستلمون', w: 100 }, { label: 'قرأه', w: 84 }, { label: '', w: 100, align: 'end' }];
const ntRow = (n) => [cell2(n.t, n.b, { w: 600 }), n.by, state(n.st), n.at, n.to == null ? dash : num(n.to), n.read == null ? dash : num(n.read), btn('التفاصيل', { kind: 'outline', sm: true })];
const ntTable = (rows, states = {}, o = {}) => dataTable({ caption: 'سجل الإشعارات', toolbar: { search: 'ابحث في العنوان أو النص', filters: ntChips(o.chip ?? 0), actions: dropFilter('كل الشركات', { icon: 'building' }), sort: 'الأحدث أولاً' }, columns: ntCols,
  rows: rows.map((n, i) => ({ state: states[i], muted: n.st === 'cancelled', cells: ntRow(n) })), pagination: o.pag === null ? undefined : { from: 1, to: 25, total: 312, page: 1, pages: 13 } });
const ntBody = (states) => `${pushStrip(false)}<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('سجل الإشعارات')}${ntTable(NT, states)}</section>`;

board('AdmPlatNotifications', { row: 'G', w: 1440, title: 'Admin web · Platform · Notifications · History · Desktop', tab: 'إدارة المنصة · إشعارات المنصة',
  body: (size) => P({ size, active: 'p-notifications', title: 'إشعارات المنصة', sub: ntSub, actions: newNt(), body: ntBody({ 2: 'hover' }) }) });

/* — Composer — */
const pickList = COMPANIES.filter((c) => c.st === 'on').slice(0, 12);
const picked = [0, 2, 3, 5, 8, 10];
const companyPicker = (phone) => `<div style="border-radius:${R.control}px;box-shadow:inset 0 0 0 1px ${C.disabled};overflow:hidden">
<div style="display:flex;align-items:center;gap:12px;padding:8px 12px;border-bottom:1px solid ${C.hair};background:${C.ground}"><span style="${T.label};font-weight:500;flex:1">${picked.length} من ${LIVE.length} شركة تعمل</span>${btn('حدد الكل', { kind: 'link', sm: true })}${btn('امسح', { kind: 'link', sm: true })}</div>
<div style="display:grid;grid-template-columns:repeat(${phone ? 1 : 2},minmax(0,1fr));gap:0 16px;padding:4px 12px;max-height:${phone ? 264 : 268}px;overflow:hidden">
${pickList.slice(0, phone ? 6 : 12).map((c, i) => `<label style="display:flex;align-items:center;gap:10px;min-height:44px;${T.small}">${checkbox(picked.includes(i), { label: c.name })}<span style="flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${c.name}</span><span style="${T.cap};color:${C.ink3}">${num(c.students)}</span></label>`).join('')}
</div>
<div style="padding:6px 12px;border-top:1px solid ${C.hair};${T.cap};color:${C.ink3}">مرّر لترى باقي الشركات · الرقم عدد الطلاب</div></div>`;
const counter = (n, max) => `<span style="${T.cap};color:${C.ink3}">${ltr(`${n}/${max}`)}</span>`;
const lab = (t, end = '') => `<div style="display:flex;align-items:baseline;gap:8px;${T.label};font-weight:500"><span style="flex:1">${t}</span>${end}</div>`;
const composerForm = (phone, o = {}) => `
${field({ phone, type: 'radio', label: 'يصل إلى', cols: 2, options: [{ label: 'طلاب كل الشركات التي تعمل', sub: `${LIVE.length} شركة`, on: !!o.all }, { label: 'شركات أختارها', sub: o.all ? undefined : `${picked.length} شركات`, on: !o.all }] })}
${o.all ? '' : companyPicker(phone)}
<div style="display:flex;flex-direction:column;gap:6px">${lab('العنوان', counter(14, 80))}${field({ phone, value: 'إجازة 6 أكتوبر', placeholder: 'مثال: إجازة رسمية' })}</div>
<div style="display:flex;flex-direction:column;gap:6px">${lab('نص الإشعار', counter(62, 600))}${field({ phone, type: 'textarea', rows: 4, value: 'لا رحلات يوم الثلاثاء 6 أكتوبر. تعود الرحلات الأربعاء في مواعيدها.', placeholder: 'اكتب ما تريد أن يعرفه الطلاب' })}</div>
${field({ phone, type: 'toggle', label: 'أولوية عالية', help: 'للأمور العاجلة فقط، مثل تغيير يخص رحلة اليوم.', on: false })}
${field({ phone, type: 'radio', label: 'موعد الإرسال', cols: 2, options: [{ label: 'الآن', on: !o.later }, { label: 'في موعد لاحق', on: !!o.later }] })}
${o.later ? `${fieldRow([field({ phone, type: 'date', label: 'اليوم', value: 'الاثنين 5 أكتوبر 2026' }), field({ phone, type: 'time', label: 'الساعة', value: time('6:00', 'م'), help: 'بتوقيت القاهرة' })], { phone })}` : ''}`;
const lockPreview = (phone) => `<div style="border-radius:${R.card}px;background:${C.ink};padding:16px;display:flex;flex-direction:column;gap:10px">
<div style="${T.cap};color:#C9D8E1">كما يظهر على هاتف الطالب</div>
<div style="background:rgba(255,255,255,.94);border-radius:${R.inner}px;padding:12px 14px;display:flex;gap:10px;align-items:flex-start;color:${C.ink}"><span aria-hidden="true" style="width:32px;height:32px;border-radius:8px;background:${C.teal};color:#FFFFFF;display:flex;align-items:center;justify-content:center;flex:none">${ico('bus', 16)}</span><div style="flex:1;min-width:0"><div style="display:flex;gap:8px;align-items:baseline"><span style="${T.small};font-weight:600;flex:1">إجازة 6 أكتوبر</span><span style="${T.cap};color:${C.ink3}">الآن</span></div><div style="${T.label};color:${C.ink2}">لا رحلات يوم الثلاثاء 6 أكتوبر. تعود الرحلات الأربعاء في مواعيدها.</div></div></div></div>`;
const audienceCard = (phone, o = {}) => `<div style="${CARD};padding:${phone ? 16 : 20}px;display:flex;flex-direction:column;gap:10px">
<div style="${T.label};font-weight:500;color:${C.ink2}">من سيصله</div>
${o.loading ? skeleton('text', { rows: 3 }) : `<div style="display:flex;align-items:baseline;gap:8px"><span style="${phone ? 'font-size:26px;line-height:34px;font-weight:600' : T.num}">${num(1874)}</span><span style="${T.label};color:${C.ink3}">طالباً في 6 شركات</span></div>
${infoRows([['مشرفون', '14'], ['هواتف مسجّلة', `${num(1620)} — يظهر عليها كتنبيه`], ['شركة بلا مستلمين', 'تُتخطى تلقائياً']], { labelW: 124 })}
<p style="margin:0;${T.cap};color:${C.ink3}">يُنشأ إشعار مستقل لكل شركة، ويظهر في سجلّها.</p>`}</div>`;
const sendDlg = (phone, later) => dialog({ phone, icon: 'megaphone', title: later ? 'جدولة الإشعار؟' : `إرسال الإشعار إلى ${num(1874)} طالباً؟`, body: `<span>${later ? `يُرسل يوم الاثنين 5 أكتوبر ${'6:00'} م بتوقيت القاهرة إلى` : 'يُرسل الآن إلى'} <b style="font-weight:600;color:${C.ink}">${num(1874)} طالباً و14 مشرفاً</b> في 6 شركات اخترتها. ${later ? 'تستطيع إلغاءه من السجل قبل موعده.' : 'لا يمكن استرجاعه بعد الإرسال.'}</span>
<div style="border-radius:${R.inner}px;background:${C.ground};padding:12px 14px;color:${C.ink}"><div style="font-weight:600">إجازة 6 أكتوبر</div><div style="${T.label};color:${C.ink2}">لا رحلات يوم الثلاثاء 6 أكتوبر. تعود الرحلات الأربعاء في مواعيدها.</div></div>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn(later ? 'جدول الإشعار' : 'أرسل الإشعار', { icon: later ? 'clock' : 'megaphone', phone, full: phone })] });
const composerPage = (size, o = {}) => P({ size, active: 'p-notifications', breadcrumb: ['إشعارات المنصة', 'إشعار جديد'], title: 'إشعار جديد', back: 'إشعارات المنصة', sub: 'رسالة من المنصة إلى طلاب كل الشركات أو شركات تختارها. نعدّ من سيصله قبل أن يُرسل شيء.', overlay: o.overlay, body: `
<div style="display:grid;grid-template-columns:minmax(0,8fr) minmax(0,4fr);gap:24px;align-items:start">
<section style="${CARD};display:flex;flex-direction:column"><div style="padding:24px;display:flex;flex-direction:column;gap:16px">${composerForm(false, o)}</div>
<div style="display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:12px 24px;border-top:1px solid ${C.hair}">${btn('إلغاء', { kind: 'secondary' })}${btn(o.later ? 'جدول الإشعار' : 'أرسل الإشعار', { icon: o.later ? 'clock' : 'megaphone' })}</div></section>
<div style="display:flex;flex-direction:column;gap:16px">${lockPreview(false)}${audienceCard(false)}</div>
</div>` });
board('AdmPlatNotifyNew', { row: 'G', w: 1440, title: 'Admin web · Platform · Notifications · New · chosen companies', tab: 'إدارة المنصة · إشعار جديد',
  body: (size) => composerPage(size, { later: true }) });
board('AdmPlatNotifySend', { row: 'G', w: 1440, title: 'Admin web · Platform · Notifications · Confirm sending', tab: 'إدارة المنصة · تأكيد الإرسال',
  body: (size) => composerPage(size, { overlay: scrim(sendDlg(false, false)) }) });
const N0 = NT[0];
const detailBody = (phone) => `<div style="border-radius:${R.inner}px;background:${C.ground};padding:12px 14px"><div style="${T.small};font-weight:600">${N0.t}</div><div style="${T.label};color:${C.ink2}">${N0.b}</div></div>
${group('الإرسال', infoRows([['المرسل', 'المنصة · محمد عادل'], ['إلى', 'طلاب 26 شركة تعمل'], ['الموعد', `الاثنين 5 أكتوبر ${'6:00'} م`], ['النوع', 'عادي']]))}
${group('ماذا حدث', infoRows([['المستلمون', `${num(6102)} طالباً · 61 مشرفاً`], ['قرأه في التطبيق', `${num(4318)} (${ltr('71%')})`], ['فتحه من التنبيه', num(2240)], ['سُلّم لخدمة التنبيهات', num(4986)], ['فشل', '14 هاتفاً'], ['لم يُرسل له تنبيه', `${num(1102)} — بلا هاتف مسجّل`]], { labelW: 150 }))}
${group('في كل شركة', `<div style="display:flex;flex-direction:column">${LIVE.filter((c) => c.subs).slice(0, 4).map((c, i) => `<div style="display:flex;gap:12px;padding:8px 0;${i ? `border-top:1px solid ${C.hair};` : ''}${T.small}"><span style="flex:1;min-width:0">${c.name}</span><span style="color:${C.ink3}">${num(c.subs)} مستلماً</span></div>`).join('')}<div style="${T.label};color:${C.teal};padding-top:6px">و22 شركة أخرى</div></div>`)}`;
board('AdmPlatNotifyDetails', { row: 'G', w: 1440, h: 1040, title: 'Admin web · Platform · Notifications · Details panel', tab: 'إدارة المنصة · تفاصيل إشعار',
  body: (size) => P({ size, active: 'p-notifications', title: 'إشعارات المنصة', sub: ntSub, actions: newNt(), body: ntBody({ 0: 'open' }),
    overlay: scrim(sidePanel({ w: 520, title: 'تفاصيل الإشعار', meta: state('sent'), sub: 'أرسلته المنصة', body: detailBody(false), footer: `${btn('احذف من السجل', { kind: 'dangerQuiet', icon: 'trash' })}<span style="flex:1"></span>${btn('إغلاق', { kind: 'secondary' })}` }), 'end') }) });
const cancelNt = (phone) => dialog({ phone, icon: 'x', tone: 'danger', title: 'إلغاء إرسال «تحديث جديد للتطبيق»؟', body: `<span>كان سيُرسل غداً ${'9:00'} ص إلى طلاب 26 شركة. بعد الإلغاء لا يصل لأحد، ويبقى في السجل بحالة «أُلغي».</span>`, actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('ألغِ الإرسال', { kind: 'danger', phone, full: phone })] });
const deleteNt = dialog({ icon: 'trash', tone: 'danger', title: 'حذف «إجازة 6 أكتوبر» من السجل؟', body: `<span>يختفي من سجل المنصة ومن قائمة الإشعارات عند ${num(6102)} طالباً داخل التطبيق. التنبيه الذي وصل الهواتف لا يُسترجع.</span>`, actions: [btn('رجوع', { kind: 'secondary' }), btn('احذف الإشعار', { kind: 'danger' })] });
sheetBoard('AdmPlatNotifyStates', 'G', 'Notifications · Dialogs and states', [
  tiles([
    dlgTile('Schedule', 'The same confirmation with the day and the Cairo time.', sendDlg(false, true), { h: 400 }),
    dlgTile('Cancel a scheduled one', 'From its details panel. The platform history has no edit (as today): cancel and write again.', cancelNt(false), { h: 400 }),
    dlgTile('Delete from the history', 'Sent, failed or cancelled notifications.', deleteNt),
    dlgTile('After sending', '', `<div style="display:flex;flex-direction:column;gap:12px">${toast({ text: `أُرسل إلى ${num(1874)} طالباً في 6 شركات.`, w: 440 })}${toast({ text: 'جُدول الإشعار. يُرسل في موعده.', w: 440 })}${toast({ tone: 'danger', text: 'تعذّر الإرسال. لم يصل لأحد؛ النص ما زال في الصفحة.', action: 'حاول مرة أخرى', w: 440 })}</div>`, { w: 560 }),
  ]),
  frame('Composer · problems', 'The count card explains why sending is held back; errors sit under their fields.', `<div dir="rtl" style="background:${C.ground};padding:24px;display:grid;grid-template-columns:minmax(0,8fr) minmax(0,4fr);gap:24px;align-items:start;${FONT};color:${C.ink}">
<div style="${CARD};padding:24px;display:flex;flex-direction:column;gap:16px">${field({ type: 'radio', label: 'يصل إلى', cols: 2, options: [{ label: 'طلاب كل الشركات التي تعمل' }, { label: 'شركات أختارها', sub: 'لم تختر شركة', on: true }] })}${note({ tone: 'danger', text: 'اختر شركة واحدة على الأقل.' })}${field({ label: 'العنوان', value: '', placeholder: 'مثال: إجازة رسمية', error: 'اكتب عنواناً للإشعار.' })}${fieldRow([field({ type: 'date', label: 'اليوم', value: 'السبت 10 أكتوبر 2026' }), field({ type: 'time', label: 'الساعة', value: time('8:00', 'ص'), error: 'هذا الموعد مضى. اختر وقتاً بعد الآن.' })])}</div>
<div style="display:flex;flex-direction:column;gap:16px">${card(`<div style="${T.label};font-weight:500;color:${C.ink2}">من سيصله</div><div style="${T.small};color:${C.ink2}">اختر شركة لنعدّ طلابها.</div>`)}${audienceCard(false, { loading: true })}${btn('أرسل الإشعار', { icon: 'megaphone', state: 'disabled', full: true })}</div></div>`),
  frame('Empty history · alerts not connected', 'First use: what the page is for and the first action. The warning replaces the four numbers when the alert service is not connected.', mini(620, { active: 'p-notifications', title: 'إشعارات المنصة', sub: ntSub, actions: newNt(), body: `${pushStrip(false, { off: true }).split('<div style="display:grid')[0]}</section><section style="display:flex;flex-direction:column;gap:12px">${sectionHead('سجل الإشعارات')}${emptyState({ card: true, icon: 'megaphone', title: 'لم يُرسل أي إشعار بعد', text: 'هنا يظهر كل ما ترسله المنصة وما ترسله كل شركة لطلابها، ومن قرأه.', action: newNt() })}</section>` })),
  frame('Loading', '', mini(480, { active: 'p-notifications', title: 'إشعارات المنصة', sub: ntSub, actions: newNt(), body: `<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px">${skeleton('stat')}${skeleton('stat')}${skeleton('stat')}${skeleton('stat')}</div>${skeleton('table', { rows: 3, cols: 6 })}` })),
  frame('Error', '', mini(460, { active: 'p-notifications', title: 'إشعارات المنصة', sub: ntSub, body: errorState({ card: true, title: 'تعذّر تحميل الإشعارات', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
board('AdmPlatNotificationsPhone', { row: 'G', w: 390, title: 'Admin web · Platform · Notifications · History · Phone', tab: 'إدارة المنصة · إشعارات المنصة · هاتف',
  body: (size) => PP({ size, active: 'p-notifications', sub: ntSub, body: `${pushStrip(true)}<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('سجل الإشعارات', { phone: true })}${recordList({ toolbar: { search: 'ابحث في العنوان أو النص', filters: ntChips(0), count: '312 إشعاراً', sort: 'كل الشركات' },
    cards: NT.slice(0, 5).map((n) => recordCard({ title: n.t, sub: n.b, end: state(n.st), fields: [['المرسل', n.by], ['الموعد', n.at], ...(n.to != null ? [['المستلمون', num(n.to)], ['قرأه', num(n.read)]] : [])] })), pagination: { from: 1, to: 25, total: 312, page: 1, pages: 13 } })}</section>`, bottomBar: newNt({ phone: true, full: true }) }) });
board('AdmPlatNotifyNewPhone', { row: 'G', w: 390, title: 'Admin web · Platform · Notifications · New · Phone', tab: 'إدارة المنصة · إشعار جديد · هاتف',
  body: (size) => phonePage({ size, active: 'p-notifications', back: 'إشعارات المنصة', title: 'إشعار جديد', body: `<div style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px">${composerForm(true, {})}</div>${lockPreview(true)}${audienceCard(true)}`, bottomBar: btn(`أرسل إلى ${num(1874)} طالباً`, { icon: 'megaphone', phone: true, full: true }) }) });
board('AdmPlatNotifySendPhone', { row: 'G', w: 390, min: 844, title: 'Admin web · Platform · Notifications · Confirm · Phone', tab: 'إدارة المنصة · تأكيد الإرسال · هاتف',
  body: (size) => phonePage({ size, active: 'p-notifications', back: 'إشعارات المنصة', title: 'إشعار جديد', body: `${lockPreview(true)}${audienceCard(true)}`, overlay: scrim(sendDlg(true, false), 'bottom') }) });
emptyPhone('AdmPlatNotificationsEmptyPhone', 'G', 'Notifications', 'p-notifications', { sub: ntSub, empty: { icon: 'megaphone', title: 'لم يُرسل أي إشعار بعد', text: 'هنا يظهر كل ما ترسله المنصة وما ترسله كل شركة لطلابها، ومن قرأه.' }, bottom: newNt({ phone: true, full: true }) });
