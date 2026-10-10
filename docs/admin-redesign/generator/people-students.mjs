import {
  board, shellDesktop, shellPhone, scrim, dialog, dataTable, recordList, recordCard, sidePanel, infoRows, formSection, fieldRow, field,
  stepper, status, state, badge, btn, iconBtn, chip, searchBox, toast, note, emptyState, errorState, skeleton, money, time, ltr, ico, cell2,
  pager, C, T, R, CARD,
} from './kit.mjs';
import { tabs, avatar, person, filterSelect, block, innerCard, frame, sheet, spec, W, ELL, STUDENTS, STOPS, study, goTime } from './people-local.mjs';

const ROW = 'PS';
const SUB = 'كل من يركب مع شركتك: بياناته، اشتراكه وحالته.';
const TOTAL = 442;
const addBtn = btn('إضافة طالب', { icon: 'plus' });
const PLATFORM = badge('لمدير المنصة فقط', 'neutral');

/* ── The list ───────────────────────────────────────────────────── */
const TABS = (on = 0, o = {}) => tabs([{ label: 'الطلاب', count: o.total ?? TOTAL, on: on === 0 }, { label: 'الدعوات', count: o.inv ?? 2, on: on === 1 }, { label: o.phone ? 'تصحيح الاسم' : 'طلبات تصحيح الاسم', count: o.cor ?? 1, on: on === 2 }], o);
const stCell = (s) => (s.st === 'none' ? badge('بلا اشتراك', 'neutral') : status(s.st));
const subCell = (s) => (s.st === 'none' ? `<span style="color:${C.ink3}">—</span>` : cell2(s.period, `${money(s.price, { unit: 11 })}${s.extra ? ' · واشتراك آخر' : ''}`, { w: 400 }));
const lineCell = (s) => (s.st === 'none' ? `<span style="color:${C.ink3}">—</span>` : cell2(s.line, `ذهاب ${goTime(s)}`, { w: 400 }));
const chev = `<span style="display:inline-flex;color:${C.ink3}">${ico('fwd', 16, 2)}</span>`;
const COLS = [{ label: 'الطالب' }, { label: 'الجامعة والكلية', w: 214, hideTablet: true }, { label: 'الخط', w: 140 }, { label: 'الاشتراك', w: 188 }, { label: 'الحالة', w: 146 }, { label: 'سُجّل', w: 96, sorted: 'desc', hideTablet: true }, { label: '', w: 40, align: 'end' }];
const row = (s, st) => ({ state: st, cells: [person(s.name, ltr(s.phone)), cell2(s.uni[0], study(s.uni), { w: 400 }), lineCell(s), subCell(s), stCell(s), `<span style="color:${C.ink2};font-size:13px">${s.joined}</span>`, chev] });
const STATUSES = [['الكل', TOTAL], ['نشط', 371], ['قيد المراجعة', 7], ['بانتظار الدفع', 31], ['إيصال مرفوض', 4], ['يبدأ قريباً', 12], ['منتهٍ', 9], ['بلا اشتراك', 8]];
const toolbar = (o = {}) => `<div style="display:flex;flex-direction:column;border-bottom:1px solid ${C.hair}">
<div style="display:flex;align-items:center;gap:12px;min-height:60px;padding:8px 16px">${searchBox({ w: 300, placeholder: 'ابحث بالاسم أو الهاتف أو الجامعة', value: o.search })}${filterSelect('الخط', o.line ?? 'كل الخطوط', { on: !!o.line })}${filterSelect('الجامعة', o.uni ?? 'كل الجامعات', { on: !!o.uni })}<span style="flex:1"></span><span style="${T.label};color:${C.ink2};white-space:nowrap">${o.count ?? `${TOTAL} طالباً`}</span><button type="button" aria-haspopup="listbox" style="display:inline-flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:${R.control}px;font-size:13px;line-height:20px;color:${C.ink};box-shadow:inset 0 0 0 1px ${C.hair};white-space:nowrap">${ico('sort', 14, 2)}<span>الأحدث تسجيلاً</span>${ico('down', 14, 2)}</button></div>
<div role="group" aria-label="حالة الاشتراك" style="display:flex;align-items:center;gap:6px;padding:0 16px 12px;flex-wrap:wrap">${STATUSES.map(([l, n], i) => chip(l, { on: i === (o.status ?? 0), count: o.noCounts ? undefined : n })).join('')}</div>
</div>`;
const withToolbar = (html, o) => html.replace(/^(<div[^>]*>)/, `$1\n${toolbar(o)}`);
const table = (o = {}) => withToolbar(dataTable({ caption: 'طلاب الشركة', tablet: o.tablet, columns: COLS, rows: (o.rows ?? STUDENTS.slice(0, 25)).map((s, i) => row(s, o.states?.[i])), empty: o.empty,
  pagination: o.pagination === null ? undefined : (o.pagination ?? { from: 1, to: 25, total: TOTAL, page: 1, pages: 18 }) }), o);
const page = (size, o = {}) => shellDesktop({ size, active: 'students', role: o.role, title: 'الطلاب', sub: SUB, actions: addBtn, overlay: o.overlay, offline: o.offline,
  body: `${TABS(o.tab ?? 0)}${o.body ?? table(o)}` });

/* ── One student ────────────────────────────────────────────────── */
const SUBINFO = (s, o = {}) => infoRows([
  ['الخط', `${s.line}`], ['الرحلات', `ذهاب ${goTime(s)} · عودة ${time('3:00', 'م')}<div style="${T.label};color:${C.ink2}">إلى ${s.uni[0]}</div>`],
  ['المدة', s.st === 'soon' ? 'من 6 فبراير 2027 إلى 10 يونيو 2027' : 'من 19 سبتمبر 2026 إلى 14 يناير 2027'], ['السعر', money(s.price)],
], { labelW: o.phone ? 84 : 96 });
/** The named actions a subscription offers in each status (the raw status select is gone). */
const subActions = (s, o = {}) => {
  const b = (l, x = {}) => btn(l, { sm: !o.phone, phone: o.phone, full: o.phone, ...x });
  return { unpaid: [b('تفعيل بعد دفع نقدي', { icon: 'check' }), b('إلغاء الاشتراك', { kind: 'secondary' })],
    review: [b('راجع الإيصال', { iconEnd: 'fwd', href: '#' })],
    rejected: [b('تفعيل بعد دفع نقدي', { icon: 'check' }), b('إلغاء الاشتراك', { kind: 'secondary' })],
    active: [b('إنهاء الاشتراك', { kind: 'secondary' }), b('فُعّل بالخطأ؟ أعده إلى بانتظار الدفع', { kind: 'link' })],
    soon: [b('إنهاء الاشتراك', { kind: 'secondary' }), b('فُعّل بالخطأ؟ أعده إلى بانتظار الدفع', { kind: 'link' })],
    ended: [b('إعادة التفعيل', { kind: 'secondary', icon: 'refresh' })] }[s.st] ?? [];
};
const SUBNOTE = { unpaid: 'لم يدفع بعد. يدفع من التطبيق ويرسل إيصالاً، أو يدفع لك نقداً فتفعّله أنت.', review: 'أرسل إيصالاً وينتظر مراجعتك في صفحة «الإيصالات».', rejected: 'رُفض إيصاله الأخير. يستطيع أن يرسل إيصالاً جديداً من التطبيق.', active: '', soon: 'مدفوع مقدماً. يبدأ مع بداية الفصل الثاني.', ended: '' };
const subCard = (s, o = {}) => innerCard(`<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><span style="flex:1;min-width:0;${T.small};font-weight:600">${s.period}</span>${status(s.st)}</div>
${SUBNOTE[s.st] ? `<div style="${T.label};color:${C.ink2};margin-top:-6px">${SUBNOTE[s.st]}</div>` : ''}
${SUBINFO(s, o)}
<div style="display:flex;gap:8px;flex-wrap:wrap;${o.phone ? 'flex-direction:column;' : ''}align-items:${o.phone ? 'stretch' : 'center'}">${subActions(s, o).join('')}</div>`);
const past = (rows) => `<div style="border-radius:${R.inner}px;box-shadow:inset 0 0 0 1px ${C.hair};display:flex;flex-direction:column">${rows.map(([p, l, n, k], i) => `<div style="display:flex;align-items:center;gap:12px;padding:10px 16px;${i ? `border-top:1px solid ${C.hair}` : ''}"><div style="flex:1;min-width:0"><div style="${T.small};font-weight:500">${p}</div><div style="${T.label};color:${C.ink2}">${l} · ${money(n, { unit: 11 })}</div></div>${status(k)}</div>`).join('')}</div>`;
const idBlock = (s, o = {}) => `<div style="display:flex;align-items:center;gap:14px">${avatar(s.name, o.phone ? 56 : 64)}<div style="flex:1;min-width:0"><div style="${T.small};font-weight:600">${s.uni[0]}</div><div style="${T.label};color:${C.ink2}">${study(s.uni) || 'الكلية غير محددة'}</div><div style="${T.label};color:${C.ink3}">سُجّل ${s.joined} 2026</div></div></div>`;
const pwBlock = (s, o = {}) => (o.role === 'workspace'
  ? innerCard(`<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><span style="flex:1;${T.small};font-weight:500">تعيين كلمة مرور مؤقتة</span>${PLATFORM}</div><div style="${T.label};color:${C.ink2};margin-top:-6px">تتوقف كلمته الحالية، ويُطلب منه تغيير المؤقتة عند أول دخول.</div><div style="display:flex">${btn('إعادة تعيين كلمة المرور', { kind: 'secondary', icon: 'key', sm: true })}</div>`)
  : o.request
    ? note({ tone: 'warning', icon: 'key', title: 'طلب المساعدة في كلمة المرور منذ 10 دقائق', text: 'اتصل به لتتأكد أنه هو ثم أعطه رمزاً.', action: btn('افتح الطلب', { kind: 'tonal', sm: true, href: '#' }) })
    : `<div style="${T.label};color:${C.ink2}">لا تظهر كلمة المرور لأحد. إن نسيها يضغط «نسيت كلمة المرور» في التطبيق، فيصلك طلبه في صفحة «طلبات كلمة المرور».</div>`);
const panelBody = (s, o = {}) => `${idBlock(s, o)}
${o.correction ? note({ tone: 'teal', icon: 'pencil', title: 'طلب تصحيح الاسم عند إدارة المنصة', text: `الاسم المقترح: «${o.correction}». يتغيّر الاسم بعد أن تعتمده.` }) : ''}
${block(s.extra || o.two ? 'الاشتراكات الحالية' : 'الاشتراك الحالي', s.st === 'none' ? `<div style="border-radius:${R.inner}px;background:${C.ground};padding:14px 16px;${T.small};color:${C.ink2}">لا اشتراك له الآن. يشترك من التطبيق، ويصلك إيصاله لتراجعه.</div>` : `${subCard(s, o)}${o.two ? subCard({ ...s, st: 'soon', period: 'الفصل الثاني 2026/2027' }, o) : ''}`)}
${o.past === false ? '' : block('اشتراكات سابقة', past([['الفصل الثاني 2025/2026', s.line, 3900, 'ended'], ['الفصل الأول 2025/2026', s.line, 3900, 'ended']]))}
${block('كلمة المرور', pwBlock(s, o))}
${o.role === 'workspace' ? block('حذف الحساب', innerCard(`<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><span style="flex:1;${T.small};font-weight:500">حذف الحساب نهائياً من المنصة</span>${PLATFORM}</div><div style="${T.label};color:${C.ink2};margin-top:-6px">يُحذف حسابه واشتراكاته لدى كل الشركات. غير الإزالة من هذه الشركة.</div><div style="display:flex">${btn('حذف الحساب', { kind: 'dangerQuiet', icon: 'trash', sm: true })}</div>`)) : ''}`;
const panelFooter = (o = {}) => `${btn('إزالة من الشركة', { kind: 'dangerQuiet', icon: 'trash', phone: o.phone, full: o.phone })}<span style="flex:1"></span>${btn('طلب تصحيح الاسم', { kind: 'outline', icon: 'pencil', phone: o.phone, full: o.phone })}`;
const panel = (s, o = {}) => sidePanel({ title: s.name, meta: stCell(s), sub: ltr(s.phone), body: panelBody(s, o), footer: panelFooter() });
const S1 = STUDENTS[1]; // عبد الرحمن — بانتظار الدفع
const S3 = STUDENTS[3]; // ملك — نشط

/* ── Dialogs ────────────────────────────────────────────────────── */
const back = (o) => btn('رجوع', { kind: 'secondary', phone: o.phone, full: o.phone });
const go = (l, o, x = {}) => btn(l, { phone: o.phone, full: o.phone, ...x });
const D = {
  activate: (s, o = {}) => dialog({ phone: o.phone, icon: 'check', tone: 'success', title: `تفعيل اشتراك ${s.short} بعد دفع نقدي؟`,
    body: `<span>يصير اشتراكه في ${s.period} على خط ${s.line} <b style="font-weight:600;color:${C.ink}">نشطاً</b> الآن، ويركب به من الغد.</span><span>يُحسب ${money(s.price)} ضمن إيرادات الشركة كأنه دُفع، ولا يُطلب منه إيصال. تأكد أنك استلمت المبلغ.</span>`,
    actions: [back(o), go('تفعيل الاشتراك', o)] }),
  cancel: (s, o = {}) => dialog({ phone: o.phone, icon: 'x', tone: 'danger', title: `إلغاء اشتراك ${s.short}؟`,
    body: `<span>اشتراكه في ${s.period} لم يُدفع بعد. بعد الإلغاء يصير «منتهٍ» ولا يستطيع أن يدفعه. يبقى الطالب في شركتك ويستطيع أن يشترك من جديد.</span>`,
    actions: [back(o), go('إلغاء الاشتراك', o, { kind: 'danger' })] }),
  end: (s, o = {}) => dialog({ phone: o.phone, icon: 'power', tone: 'danger', title: `إنهاء اشتراك ${s.short}؟`,
    body: `<span>يتوقف اشتراكه في ${s.period} على خط ${s.line} اليوم، ولا يركب به بعد الآن.</span><span>لا يُردّ المبلغ من هنا، ويبقى ما دفعه (${money(s.price)}) في الإيرادات. يستطيع أن يشترك من جديد.</span>`,
    actions: [back(o), go('إنهاء الاشتراك', o, { kind: 'danger' })] }),
  unpay: (s, o = {}) => dialog({ phone: o.phone, icon: 'undo', tone: 'warning', title: `إعادة اشتراك ${s.short} إلى «بانتظار الدفع»؟`,
    body: `<span>استعمل هذا إن فُعّل الاشتراك بالخطأ. يتوقف عن الركوب به حتى يدفع، ويخرج ${money(s.price)} من الإيرادات.</span>`,
    actions: [back(o), go('إعادة إلى بانتظار الدفع', o)] }),
  reactivate: (s, o = {}) => dialog({ phone: o.phone, icon: 'refresh', tone: 'teal', title: `إعادة تفعيل اشتراك ${s.short}؟`,
    body: `<span>يعود اشتراكه في ${s.period} نشطاً بالمدة نفسها، ويُحسب ${money(s.price)} ضمن الإيرادات. استعمل هذا إن أُنهي بالخطأ.</span>`,
    actions: [back(o), go('إعادة التفعيل', o)] }),
  remove: (s, o = {}) => dialog({ phone: o.phone, icon: 'trash', tone: 'danger', title: `إزالة ${s.short} من النورس للنقل؟`,
    body: `<span>تنتهي اشتراكاته المفتوحة مع الشركة ولا يظهر في قوائمها.</span><span>يبقى حسابه في التطبيق كما هو، وتبقى الإيرادات المسجلة في تقارير الشركة. إن أردت إعادته فأضفه من جديد وسيصله طلب انضمام.</span>`,
    actions: [back(o), go('إزالة من الشركة', o, { kind: 'danger' })] }),
  rename: (s, o = {}) => dialog({ phone: o.phone, icon: 'pencil', tone: 'teal', title: `طلب تصحيح اسم ${s.short}`,
    body: `<span>الاسم يخص حساب الطالب وقد تشاركه شركات أخرى، لذلك تعتمده إدارة المنصة. لا يتغيّر شيء قبل أن توافق.</span>
${field({ label: 'الاسم الصحيح (رباعي)', value: o.error ? s.name : s.name.replace('الشربيني', 'الشربينى').replace('السيد', 'السعيد'), help: `الاسم الحالي: ${s.name}`, error: o.error ? 'اكتب اسماً مختلفاً عن الاسم الحالي.' : undefined, state: o.error ? undefined : 'focus', phone: o.phone })}`,
    actions: [back(o), go('إرسال الطلب', o, { state: o.error ? 'disabled' : undefined })] }),
  uninvite: (o = {}) => dialog({ phone: o.phone, icon: 'x', tone: 'danger', title: 'إلغاء الدعوة المرسلة إلى ⁦010 4418 2207⁩؟',
    body: '<span>لن يستطيع صاحب الرقم قبولها من التطبيق. يمكنك دعوته مرة أخرى بإضافته من «إضافة طالب».</span>',
    actions: [back(o), go('إلغاء الدعوة', o, { kind: 'danger' })] }),
  del: (s, o = {}) => dialog({ phone: o.phone, icon: 'trash', tone: 'danger', title: `حذف حساب ${s.short} نهائياً من المنصة؟`,
    body: `<span>يُحذف حسابه وبياناته واشتراكاته لدى كل الشركات، لا لدى النورس للنقل فقط. تبقى مبالغ الإيرادات في السجل المالي.</span><span style="color:${C.bad};font-weight:500">لا يمكن التراجع.</span>`,
    actions: [back(o), go('حذف الحساب', o, { kind: 'danger' })] }),
  leave: (o = {}) => dialog({ phone: o.phone, icon: 'alert', tone: 'warning', title: 'الخروج بدون تسجيل الطالب؟',
    body: '<span>لم يُحفظ شيء بعد. ما كتبته في الخطوات الثلاث سيُمسح.</span>',
    actions: [btn('أكمل التسجيل', { kind: 'secondary', phone: o.phone, full: o.phone }), go('خروج بدون تسجيل', o, { kind: 'danger' })] }),
};

/* ── Desktop: list, panel ───────────────────────────────────────── */
board('AdmStudents', { row: ROW, w: 1440, title: 'Admin web · Students · Desktop', tab: 'لوحة الشركة · الطلاب',
  body: (size) => page(size, { states: { 2: 'hover' } }) });
board('AdmStudentPanel', { row: ROW, w: 1440, title: 'Admin web · Students · Side panel (awaiting payment)', tab: 'لوحة الشركة · الطلاب · طالب',
  body: (size) => page(size, { states: { 1: 'open' }, overlay: scrim(panel(S1, { request: true }), 'end') }) });
board('AdmStudentPanelActive', { row: ROW, w: 1440, title: 'Admin web · Students · Side panel (two subscriptions, name fix pending)', tab: 'لوحة الشركة · الطلاب · طالب نشط',
  body: (size) => page(size, { states: { 3: 'open' }, overlay: scrim(panel(S3, { two: true, correction: 'ملك حسام الدين مصطفى الغنّام' }), 'end') }) });
board('AdmStudentActivate', { row: ROW, w: 1440, min: 1100, title: 'Admin web · Students · Activate after cash payment', tab: 'لوحة الشركة · الطلاب · تفعيل',
  body: (size) => page(size, { states: { 1: 'open' }, overlay: `${scrim(panel(S1, { request: true }), 'end')}${scrim(D.activate(S1), 'center', { extra: 'z-index:11;align-items:flex-start;padding-top:260px;' })}` }) });

const acts = (k) => `<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">${subActions({ st: k }).join('')}</div>`;
const actRows = [['unpaid', 'تفعيل → نشط · إلغاء → منتهٍ'], ['review', 'القرار في صفحة الإيصالات فقط'], ['rejected', 'تفعيل → نشط · إلغاء → منتهٍ'], ['active', 'إنهاء → منتهٍ · إعادة → بانتظار الدفع'], ['soon', 'مثل النشط'], ['ended', 'إعادة التفعيل → نشط']];
const actTable = `<div dir="rtl" style="${CARD};box-shadow:inset 0 0 0 1px ${C.hair};overflow:hidden">${actRows.map(([k, t], i) => `<div style="display:grid;grid-template-columns:160px minmax(0,1fr) 300px;gap:16px;align-items:center;min-height:60px;padding:8px 20px;${i ? `border-top:1px solid ${C.hair}` : ''}"><div>${status(k)}</div>${acts(k)}<div style="${T.label};color:${C.ink2}">${t}</div></div>`).join('')}</div>`;
const grid = (cells) => `<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:32px 24px">${cells.join('')}</div>`;
board('AdmStudentDialogs', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Students · Subscription actions and every confirmation', tab: 'Basak admin web · Students · confirmations',
  body: (size) => sheet(size, `<section style="display:flex;flex-direction:column;gap:12px"><div dir="ltr"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600">Subscription actions by status</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2};max-width:980px">Replaces the status select that saved on change. Each status offers only the moves that make sense, each named for what it does and each behind a confirmation. «قيد المراجعة» and «إيصال مرفوض» can no longer be set by hand: they come only from a receipt.</p></div>${actTable}</section>
${grid([
    spec('Activate after cash payment', 'From «بانتظار الدفع» or «إيصال مرفوض». Money-affecting: says the amount.', D.activate(S1)),
    spec('Cancel an unpaid subscription', 'From «بانتظار الدفع» or «إيصال مرفوض».', D.cancel(S1)),
    spec('End an active subscription', 'From «نشط» or «يبدأ قريباً».', D.end(S3)),
    spec('Back to awaiting payment', 'The undo of a wrong activation.', D.unpay(S3)),
    spec('Re-activate an ended subscription', 'From «منتهٍ».', D.reactivate(STUDENTS[15])),
    spec('Remove from the company', 'Today a native confirm with the same facts.', D.remove(S1)),
    spec('Ask for a name correction', 'Today a native prompt. One field; goes to the platform admin.', D.rename(S1)),
    spec('Name correction · nothing changed', 'The send button waits for a different name.', D.rename(S1, { error: true })),
    spec('Cancel an invitation', 'From the «الدعوات» tab.', D.uninvite()),
    spec('Delete the account · platform admin only', 'Shown only to a super admin inside the company.', D.del(S1)),
    spec('Leave the add-student steps', 'Closing or going back with something typed asks first.', D.leave()),
  ])}`, { title: 'Students · actions and confirmations', sub: 'Every dialog the students page can open, at its desktop size. On a phone each is the same text anchored to the bottom with stacked buttons (see AdmStudentActivatePhone).' }) });

/* ── Invitations and corrections ────────────────────────────────── */
const INV = [
  ['010 4418 2207', 'الزرقا', 'اليوم', 'بعد 14 يوماً', ['open', 'ينتظر موافقة الطالب'], true],
  ['012 7730 9154', 'دمياط الجديدة', '6 أكتوبر', 'بعد 10 أيام', ['open', 'ينتظر موافقة الطالب'], true],
  ['011 5502 6618', 'شربين', '2 أكتوبر', '—', ['done', 'قبلها · صار في قائمتك']],
  ['015 2096 4471', 'فارسكور', '28 سبتمبر', '—', ['failed', 'رفضها الطالب']],
  ['010 8843 1120', 'الزرقا', '21 سبتمبر', '—', ['cancelled', 'ألغيتها']],
  ['012 3317 5586', 'كفر سعد', '12 سبتمبر', 'انتهت 26 سبتمبر', ['archived', 'انتهت بلا رد']],
];
const invTable = (rows = INV, o = {}) => dataTable({ caption: 'الدعوات',
  toolbar: o.count === '' ? undefined : { count: o.count ?? 'آخر 10 دعوات · الأحدث أولاً' },
  columns: [{ label: 'رقم الهاتف' }, { label: 'الخط', w: 170 }, { label: 'أُرسلت', w: 130 }, { label: 'تنتهي', w: 160 }, { label: 'النتيجة', w: 230 }, { label: '', w: 140, align: 'end' }],
  rows: rows.map((r) => ({ cells: [`<span style="font-weight:500">${ltr(r[0])}</span>`, r[1], r[2], `<span style="color:${C.ink2}">${r[3]}</span>`, state(...r[4]), r[5] ? btn('إلغاء الدعوة', { kind: 'outline', sm: true }) : ''] })), empty: o.empty });
const invNote = note({ tone: 'teal', title: 'متى تُرسل دعوة؟', text: 'عندما تضيف طالباً ولرقمه حساب في باصك من قبل. لا يُنشأ له حساب جديد: يوافق من التطبيق بحسابه الحالي ثم يظهر في قائمتك. تنتهي الدعوة بعد 14 يوماً.' });
board('AdmStudentsInvites', { row: ROW, w: 1440, title: 'Admin web · Students · Invitations tab', tab: 'لوحة الشركة · الطلاب · الدعوات',
  body: (size) => page(size, { tab: 1, body: `${invNote}${invTable()}` }) });
const COR = [
  ['ملك حسام الدين مصطفى الغنام', 'ملك حسام الدين مصطفى الغنّام', 'اليوم', ['open', 'عند إدارة المنصة'], ''],
  ['عمر خالد اسماعيل البنا', 'عمر خالد إسماعيل البنا', '3 أكتوبر', ['done', 'اعتُمد · تغيّر الاسم'], ''],
  ['يوسف احمد عبد الفتاح', 'يوسف أحمد عبد الفتاح البنا', '27 سبتمبر', ['done', 'اعتُمد · تغيّر الاسم'], ''],
  ['سلمى طارق عبد الحميد سالم', 'سلمى طارق سالم', '19 سبتمبر', ['failed', 'رُفض'], 'الاسم المقترح أقل من ثلاثة أسماء.'],
];
const corTable = (rows = COR, o = {}) => dataTable({ caption: 'طلبات تصحيح الاسم', rowH: 64,
  toolbar: o.empty ? undefined : { count: 'آخر 10 طلبات · الأحدث أولاً' },
  columns: [{ label: 'الاسم الحالي' }, { label: 'الاسم المقترح' }, { label: 'أُرسل', w: 120 }, { label: 'النتيجة', w: 220 }, { label: 'ملاحظة إدارة المنصة', w: 250 }],
  rows: rows.map((r) => ({ cells: [`<span style="color:${C.ink2};text-decoration:line-through">${r[0]}</span>`, `<span style="font-weight:500">${r[1]}</span>`, r[2], state(...r[3]), r[4] ? `<span style="color:${C.ink2};font-size:13px;line-height:20px">${r[4]}</span>` : `<span style="color:${C.ink3}">—</span>`] })), empty: o.empty });
const corNote = note({ tone: 'teal', title: 'من يعتمد التصحيح؟', text: 'اسم الطالب يخص حسابه في باصك كله، فتعتمده إدارة المنصة. تطلب التصحيح من صفحة الطالب («طلب تصحيح الاسم»)، وترى النتيجة هنا.' });
board('AdmStudentsCorrections', { row: ROW, w: 1440, title: 'Admin web · Students · Name corrections tab', tab: 'لوحة الشركة · الطلاب · طلبات تصحيح الاسم',
  body: (size) => page(size, { tab: 2, body: `${corNote}${corTable()}` }) });

/* ── Add a student: three steps ─────────────────────────────────── */
const STEPS = (n) => ['الطالب', 'الخط والرحلات', 'الاشتراك'].map((label, i) => ({ label, state: i < n ? 'done' : i === n ? 'current' : 'todo' }));
const NEW = { name: 'كريم وائل السعيد أبو النجا', phone: '011 1234 5679', uni: 'جامعة دمياط', line: 'فارسكور', stop: 'موقف فارسكور القديم' };
const trip = (t, ap, label, on) => ({ label: `<span style="display:inline-flex;gap:8px;align-items:baseline">${time(t, ap)}${label ? `<span style="font-weight:400;color:${C.ink2};font-size:13px">${label}</span>` : ''}</span>`, on });
const step1 = (o = {}) => [formSection({ phone: o.phone, title: 'بيانات الطالب', help: 'اكتب الاسم كما في بطاقته. يدخل الطالب التطبيق برقم هاتفه.',
  body: `${field({ label: 'الاسم بالكامل', value: o.err ? 'كريم وائل' : NEW.name, placeholder: 'مثال: أحمد محمد علي إبراهيم', help: 'ثلاثة أسماء على الأقل.', error: o.err ? 'اكتب الاسم ثلاثياً على الأقل.' : undefined, phone: o.phone })}
${fieldRow([field({ type: 'tel', label: 'رقم الهاتف', value: o.err ? '011 1234' : o.member ? '010 2345 6780' : NEW.phone, placeholder: '01X XXXX XXXX', help: 'رقم واحد لكل طالب.', error: o.member ? 'هذا الرقم لطالب في شركتك بالفعل، أو أُرسلت له دعوة. ابحث عنه في قائمة الطلاب أو في «الدعوات».' : o.err ? 'الرقم ناقص. اكتب 11 رقماً تبدأ بـ 01.' : undefined, phone: o.phone }),
    field({ type: 'select', label: 'الجامعة', value: NEW.uni, help: 'تحدد الخطوط والرحلات التي تظهر في الخطوة التالية.', phone: o.phone })], { phone: o.phone })}` }),
formSection({ phone: o.phone, title: 'كلمة مرور التطبيق', help: 'تكتبها أنت الآن وتعطيها للطالب. لا تظهر بعد التسجيل.',
  body: field({ label: 'كلمة المرور', ltr: true, value: o.err ? 'kareem' : 'Kareem#4471', help: '8 أحرف على الأقل. تبقى ظاهرة هنا لتقرأها له.', error: o.err ? 'كلمة المرور أقصر من 8 أحرف.' : undefined, phone: o.phone, w: o.phone ? undefined : 320 }) })].join('\n');
const step2 = (o = {}) => [formSection({ phone: o.phone, title: 'من أين يركب؟', help: `تظهر الخطوط التي لها رحلة إلى ${NEW.uni} فقط.`,
  body: fieldRow([field({ type: 'select', label: 'الخط', value: NEW.line, phone: o.phone }), field({ type: 'select', label: 'المحطة', value: o.none ? 'عزبة البرج' : NEW.stop, help: 'محطات الخط بترتيب المسار.', phone: o.phone })], { phone: o.phone }) }),
formSection({ phone: o.phone, title: 'في أي رحلة؟', help: 'الوقت هو وقت مرور الباص على محطته. يستطيع الطالب تغيير رحلته لاحقاً من التطبيق.',
  body: o.none ? note({ tone: 'warning', title: 'لا رحلة ذهاب تمر على هذه المحطة', text: 'اختر محطة أخرى، أو أضف وقت المحطة إلى رحلة من صفحة «الخطوط».', action: btn('افتح الخطوط', { kind: 'tonal', sm: true, href: '#' }) })
    : `${field({ type: 'radio', label: 'رحلة الذهاب', phone: o.phone, cols: 3, options: [trip('6:40', 'ص', ''), trip('7:15', 'ص', 'الرحلة الأساسية', true), trip('8:45', 'ص', 'محاضرات متأخرة')] })}
${field({ type: 'radio', label: 'رحلة العودة', phone: o.phone, cols: 3, options: [trip('1:30', 'م', ''), trip('3:15', 'م', '', true), trip('5:00', 'م', '')] })}` })].join('\n');
const sumRows = infoRows([['الطالب', `<div style="font-weight:500">${NEW.name}</div><div style="${T.label};color:${C.ink2}">${ltr(NEW.phone)} · ${NEW.uni}</div>`], ['الخط والمحطة', `${NEW.line} · ${NEW.stop}`], ['الرحلات', `ذهاب ${time('7:15', 'ص')} · عودة ${time('3:15', 'م')}`], ['الاشتراك', `الفصل الأول 2026/2027 · ${money(4200)}`]], { labelW: 104 });
const step3 = (o = {}) => [formSection({ phone: o.phone, title: 'أول اشتراك له', help: 'الأسعار هي أسعار الخط الذي اخترته. ما لا تبيعه الشركة الآن يظهر مقفلاً.',
  body: `${field({ type: 'radio', label: 'نوع الاشتراك', phone: o.phone, cols: 3, options: [{ label: 'فصل دراسي', on: true }, { label: 'الفصلان معاً', sub: 'غير متاح الآن' }, { label: 'يومي', sub: `${money(50, { unit: 11 })} نقداً في الباص` }] })}
${field({ type: 'radio', label: 'فترة الاشتراك', phone: o.phone, cols: 2, options: [{ label: 'الفصل الأول 2026/2027', sub: money(4200, { unit: 11 }), on: true }, { label: 'الفصل الثاني 2026/2027', sub: `${money(4200, { unit: 11 })} · دفع مقدم` }] })}` }),
formSection({ phone: o.phone, title: 'راجع قبل التسجيل', help: 'لا يُحفظ شيء قبل أن تضغط «تسجيل الطالب».',
  body: `${sumRows}${note({ tone: 'teal', title: 'يُسجَّل اشتراكه «بانتظار الدفع»', text: 'يدفع من التطبيق ويرسل إيصالاً تراجعه، أو يدفع لك نقداً فتفعّله من صفحته.' })}` })].join('\n');
const wizFoot = (n, o = {}) => `<div style="display:flex;align-items:center;gap:8px">${btn('إلغاء', { kind: 'link' })}<span style="flex:1"></span>${n ? btn('السابق', { kind: 'secondary', icon: 'back' }) : ''}${n === 2 ? btn('تسجيل الطالب', { icon: 'check', state: o.loading ? 'loading' : undefined }) : btn('التالي', { iconEnd: 'fwd', state: o.block ? 'disabled' : undefined })}</div>`;
const wizard = (size, n, body, o = {}) => shellDesktop({ size, active: 'students', breadcrumb: ['الطلاب', 'إضافة طالب'], title: 'إضافة طالب', back: 'الطلاب', sub: 'ثلاث خطوات. لا يُحفظ شيء قبل الخطوة الأخيرة.', overlay: o.overlay,
  body: `<div style="max-width:920px;display:flex;flex-direction:column;gap:16px"><div style="${CARD};padding:16px 24px">${stepper({ steps: STEPS(n) })}</div>${body}${wizFoot(n, o)}</div>` });
board('AdmStudentAdd1', { row: ROW, w: 1440, title: 'Admin web · Add student · Step 1 · The student', tab: 'لوحة الشركة · إضافة طالب · 1',
  body: (size) => wizard(size, 0, step1()) });
board('AdmStudentAdd2', { row: ROW, w: 1440, title: 'Admin web · Add student · Step 2 · Line and trips', tab: 'لوحة الشركة · إضافة طالب · 2',
  body: (size) => wizard(size, 1, step2()) });
board('AdmStudentAdd3', { row: ROW, w: 1440, title: 'Admin web · Add student · Step 3 · Subscription and review', tab: 'لوحة الشركة · إضافة طالب · 3',
  body: (size) => wizard(size, 2, step3()) });

const okDialog = (o = {}) => dialog({ phone: o.phone, w: 520, icon: 'check', tone: 'success', title: 'سُجّل كريم وائل في شركتك',
  body: `<span>اشتراكه في الفصل الأول 2026/2027 على خط فارسكور «بانتظار الدفع».</span>${innerCard(`<div style="${T.label};color:${C.ink2}">أبلغه الآن. يدخل التطبيق بـ:</div>${infoRows([['رقم الهاتف', ltr(NEW.phone)], ['كلمة المرور', `<span style="display:inline-flex;align-items:center;gap:8px">${ltr('Kareem#4471', 'font-weight:600')}${btn('نسخ', { kind: 'outline', icon: 'copy', sm: true })}</span>`]], { labelW: 104 })}`, { bg: C.ground, gap: 4 })}<span>لن تظهر كلمة المرور مرة أخرى بعد إغلاق هذه النافذة.</span>`,
  actions: [btn('إضافة طالب آخر', { kind: 'secondary', phone: o.phone, full: o.phone }), btn('افتح صفحة الطالب', { phone: o.phone, full: o.phone })] });
const invitedDialog = (o = {}) => dialog({ phone: o.phone, w: 520, icon: 'mail', tone: 'teal', title: 'لهذا الرقم حساب في باصك، فأرسلنا له دعوة',
  body: `<span><b style="font-weight:600;color:${C.ink}">لم يُضف الطالب بعد.</b> صاحب الرقم ${ltr(NEW.phone)} يرى الدعوة في التطبيق ويوافق بحسابه وكلمة مروره الحاليين، ثم يظهر في قائمتك.</span><span>كلمة المرور التي كتبتها لم تُستعمل. تنتهي الدعوة بعد 14 يوماً، وتتابعها في تبويب «الدعوات».</span>`,
  actions: [btn('تم', { kind: 'secondary', phone: o.phone, full: o.phone }), btn('عرض الدعوات', { phone: o.phone, full: o.phone })] });
const mini = (n, body, o = {}) => `<div style="width:100%;display:flex;flex-direction:column;gap:16px">${body}${wizFoot(n, o)}</div>`;
board('AdmStudentAddOutcomes', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Add student · Outcomes and errors', tab: 'Basak admin web · Add student · outcomes',
  body: (size) => sheet(size, `${grid([
    spec('Outcome A · created', 'A new account. The typed password is shown one last time so it can be handed over.', okDialog()),
    spec('Outcome B · invited instead', 'The phone already has a Basak account: nothing is created, an invitation is sent. Today this is a toast that is easy to miss.', invitedDialog()),
  ])}
${frame('Step 1 · errors under the fields', 'Checked when «التالي» is pressed; today they are toasts in the corner. Same rules as today: three names, at least 10 digits, password of 8.', wizard(`width:${W}px;min-height:400px`, 0, step1({ err: true })))}
${frame('Step 1 · already a member', 'The server refuses a phone that is already an active member or already invited; the sentence goes under the phone field.', wizard(`width:${W}px;min-height:400px`, 0, step1({ member: true })))}
${frame('Step 2 · no trip from the chosen stop', '«التالي» is held back and the way out is named.', wizard(`width:${W}px;min-height:400px`, 1, step2({ none: true }), { block: true }))}
${frame('Step 3 · could not save', 'The steps stay filled; a toast says so. A second press cannot create the account twice.', wizard(`width:${W}px;min-height:400px`, 2, step3(), { overlay: `<div style="position:absolute;inset-inline-start:296px;bottom:32px;z-index:5">${toast({ tone: 'danger', w: 480, text: 'لم يُسجَّل الطالب. تأكد من اتصالك ثم حاول مرة أخرى.', action: 'إعادة المحاولة' })}</div>` }))}`, { title: 'Add student · outcomes and errors' }) });

/* ── States ─────────────────────────────────────────────────────── */
const st = (h, o) => shellDesktop({ size: `width:${W}px;min-height:${h}px`, active: 'students', breadcrumb: ['الطلاب'], title: 'الطلاب', sub: SUB, actions: addBtn, ...o });
const firstS = (phone) => emptyState({ phone, card: phone, icon: 'users', title: 'لا طلاب في شركتك بعد', text: 'يظهر الطالب هنا عندما يشترك في أحد خطوطك من التطبيق، أو عندما تضيفه أنت بنفسك.', action: btn('إضافة طالب', { icon: 'plus', phone, full: phone }) });
board('AdmStudentsStates', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Students · States', tab: 'Basak admin web · Students · states',
  body: (size) => sheet(size, [
    frame('Loading', 'Tabs and toolbar are real; rows are grey.', st(520, { body: `${TABS(0, { total: '…', inv: '…', cor: '…' })}${skeleton('table', { rows: 5, cols: 6 })}` })),
    frame('First use', 'No students yet: how they arrive, and the button that adds the first.', st(520, { badges: {}, body: `${TABS(0, { total: 0, inv: 0, cor: 0 })}${table({ tablet: true, count: '0 طلاب', noCounts: true, pagination: null, empty: firstS(false) })}` })),
    frame('One student', 'No pagination under 26 rows.', st(420, { badges: {}, body: `${TABS(0, { total: 1, inv: 0, cor: 0 })}${table({ tablet: true, rows: STUDENTS.slice(2, 3), count: 'طالب واحد', noCounts: true, pagination: null })}` })),
    frame('Search and filters with no match', 'The search is done by the database over all 442 students, not over the loaded page.', st(520, { searchValue: undefined, body: `${TABS(0)}${table({ tablet: true, search: 'سارة عبد الجواد', line: 'شربين', status: 3, count: 'لا نتائج', pagination: null, empty: emptyState({ icon: 'search', title: 'لا طالب بهذه المواصفات', text: 'جرّب اسماً أقصر أو رقم الهاتف، أو أزل التصفية بالخط والحالة.', action: btn('إزالة البحث والتصفية', { kind: 'secondary' }) }) })}` })),
    frame('Filtered', 'A chosen line and status: the count and the pagination follow the filter.', st(520, { body: `${TABS(0)}${table({ tablet: true, rows: STUDENTS.filter((s) => s.st === 'unpaid').concat(STUDENTS.filter((s) => s.st === 'unpaid')).slice(0, 4).map((s, i) => ({ ...s, line: 'فارسكور', go: '7:15', name: i > 1 ? STUDENTS[20 + i].name : s.name, phone: STUDENTS[20 + i].phone })), line: 'فارسكور', status: 3, count: '4 طلاب', pagination: null })}` })),
    frame('Error', 'With a retry — today this page has none.', st(520, { body: `${TABS(0)}${errorState({ card: true, title: 'تعذّر تحميل الطلاب', text: 'لم نستطع جلب قائمة الطلاب. تأكد من اتصالك ثم حاول مرة أخرى.' })}` })),
    frame('Invitations · none', 'The tab explains itself; there is no «invite» button because an invitation is only ever the outcome of adding a student.', st(480, { body: `${TABS(1, { inv: 0 })}${invTable([], { count: '', empty: emptyState({ icon: 'mail', title: 'لم تُرسل أي دعوة', text: 'عندما تضيف طالباً ولرقمه حساب في باصك من قبل، تُرسل له دعوة بدل إنشاء حساب جديد، وتتابعها هنا.', action: addBtn }) })}` })),
    frame('Name corrections · none', '', st(460, { body: `${TABS(2, { cor: 0 })}${corTable([], { empty: emptyState({ icon: 'pencil', title: 'لم تطلب أي تصحيح', text: 'إن وجدت خطأ في اسم طالب فافتح صفحته واضغط «طلب تصحيح الاسم». تعتمده إدارة المنصة وتظهر النتيجة هنا.' }) })}` })),
    frame('Offline', 'The loaded page stays readable; «إضافة طالب» and every action in the panel wait.', st(520, { offline: true, actions: btn('إضافة طالب', { icon: 'plus', state: 'disabled' }), body: `${TABS(0)}${table({ tablet: true, rows: STUDENTS.slice(0, 4), pagination: { from: 1, to: 25, total: TOTAL, page: 1, pages: 18 } })}` })),
  ].join('\n'), { title: 'Students · states' }) });

/* ── Super admin inside the company ─────────────────────────────── */
board('AdmStudentWorkspace', { row: ROW, w: 1440, title: 'Admin web · Students · Side panel as the platform admin', tab: 'لوحة الشركة · الطلاب · مدير المنصة',
  body: (size) => page(size, { role: 'workspace', states: { 4: 'open' }, overlay: scrim(panel(STUDENTS[4], { role: 'workspace', past: false }), 'end', { extra: 'top:48px;' }) }) });
const who = (s) => `<div style="border-radius:${R.inner}px;background:${C.ground};padding:12px 16px;display:flex;align-items:center;gap:12px">${avatar(s.name, 40)}<div style="min-width:0"><div style="${T.small};font-weight:600;color:${C.ink}">${s.name}</div><div style="${T.label};color:${C.ink2}">${ltr(s.phone)} · ${s.uni[0]} · النورس للنقل</div></div></div>`;
const resetDialog = (s, o = {}) => dialog({ phone: o.phone, w: 520, icon: 'key', tone: 'warning', title: `إعادة تعيين كلمة مرور ${s.short}؟`,
  body: `${who(s)}
${field({ type: 'radio', label: 'كلمة المرور المؤقتة', cols: 2, phone: o.phone, options: [{ label: 'يولّدها النظام', sub: 'كلمة آمنة تظهر لك مرة واحدة', on: !o.manual }, { label: 'أكتبها أنا', sub: '8 أحرف على الأقل', on: !!o.manual }] })}
${o.manual ? field({ label: 'الكلمة المؤقتة', ltr: true, value: 'omar12', error: 'كلمة المرور المؤقتة أقصر من 8 أحرف.', phone: o.phone }) : ''}
${field({ type: 'checkbox', label: 'تحققت من هوية الطالب، وأعرف أن كلمته الحالية ستتوقف عن العمل.', on: !o.manual })}`,
  actions: [btn('رجوع', { kind: 'secondary', phone: o.phone, full: o.phone }), btn('إعادة التعيين', { phone: o.phone, full: o.phone, state: o.manual ? 'disabled' : undefined })] });
const resetDone = (s, o = {}) => dialog({ phone: o.phone, w: 520, icon: 'check', tone: 'success', title: `تغيّرت كلمة مرور ${s.short}`,
  body: `<div style="display:flex;align-items:center;gap:12px;border-radius:${R.inner}px;background:${C.tint};padding:16px 20px"><span dir="ltr" style="flex:1;text-align:center;font-size:26px;line-height:36px;font-weight:600;letter-spacing:2px;color:${C.ink};unicode-bidi:isolate">Tq7#mB2x9L</span>${btn('نسخ', { kind: 'outline', icon: 'copy', sm: true })}</div>
<span>سلّمها للطالب بنفسك، في مقابلة أو مكالمة. سيُطلب منه تغييرها عند أول دخول.</span>
${note({ tone: 'warning', title: 'تظهر مرة واحدة فقط', text: 'لا تُحفظ ولا يمكن عرضها بعد إغلاق هذه النافذة.' })}`,
  actions: [btn('تم، سلّمتها للطالب', { phone: o.phone, full: o.phone })] });
const wsPage = (size, d) => page(size, { role: 'workspace', states: { 4: 'open' }, overlay: `${scrim(panel(STUDENTS[4], { role: 'workspace', past: false }), 'end', { extra: 'top:48px;' })}${scrim(d, 'center', { extra: 'z-index:11;align-items:flex-start;padding-top:220px;' })}` });
board('AdmPasswordReset', { row: 'PP', w: 1440, title: 'Admin web · Reset a student password · platform admin only', tab: 'لوحة الشركة · إعادة تعيين كلمة المرور',
  body: (size) => wsPage(size, resetDialog(STUDENTS[4])) });
board('AdmPasswordResetDone', { row: 'PP', w: 1440, title: 'Admin web · Reset a student password · the temporary password, once', tab: 'لوحة الشركة · كلمة المرور المؤقتة',
  body: (size) => wsPage(size, resetDone(STUDENTS[4])) });
board('AdmPasswordResetStates', { row: 'PP', w: 1440, lang: 'en', title: 'Admin web · Reset a student password · typed by hand, error', tab: 'Basak admin web · Reset password · states',
  body: (size) => sheet(size, grid([
    spec('Typed by hand · too short', 'The second way today’s dialog offers. The button waits for 8 characters and the tick.', resetDialog(STUDENTS[4], { manual: true })),
    spec('Phone form', 'Bottom-anchored, stacked buttons.', `<div style="width:390px">${resetDialog(STUDENTS[4], { phone: true })}</div>`, { pad: 0 }),
  ]), { title: 'Reset a student password · other forms', sub: 'Only a super admin sees this (role check as today). A company admin answers the student’s own request on «طلبات كلمة المرور» instead.' }) });

/* ── Phone ──────────────────────────────────────────────────────── */
const pCard = (s) => recordCard({ title: s.name, sub: ltr(s.phone), end: stCell(s), fields: [['الجامعة', `${s.uni[0]}${study(s.uni) ? ' · ' + s.uni[1] : ''}`], ['الخط', s.st === 'none' ? '—' : `${s.line} · ذهاب ${goTime(s)}`], ['الاشتراك', s.st === 'none' ? '—' : `${s.period.replace(' 2026/2027', '')} · ${money(s.price, { unit: 11 })}`]] });
const pFilters = `<div style="display:flex;gap:6px;overflow:hidden;margin-inline:-16px;padding-inline:16px">${filterSelect('الخط', 'الكل', { phone: true })}${filterSelect('الجامعة', 'الكل', { phone: true })}${filterSelect('الحالة', 'الكل', { phone: true })}</div>`;
const pList = (o = {}) => `${TABS(o.tab ?? 0, { phone: true, ...o })}${o.body ?? recordList({ toolbar: { search: 'ابحث بالاسم أو الهاتف أو الجامعة', count: `${TOTAL} طالباً`, sort: 'الأحدث تسجيلاً' }, cards: STUDENTS.slice(0, 8).map(pCard), pagination: { from: 1, to: 25, total: TOTAL, page: 1, pages: 18 } }).replace('<div style="display:flex;align-items:center;gap:8px;min-height:24px">', `${pFilters}<div style="display:flex;align-items:center;gap:8px;min-height:24px">`)}`;
board('AdmStudentsPhone', { row: ROW, w: 390, title: 'Admin web · Students · Phone · List (8 of 25 cards drawn)', tab: 'لوحة الشركة · الطلاب · هاتف',
  body: (size) => shellPhone({ size, active: 'students', gap: 14, body: pList(), bottomBar: btn('إضافة طالب', { icon: 'plus', phone: true, full: true }) }) });
const pStudent = (size, s, o = {}) => shellPhone({ size, active: 'students', back: 'الطلاب', title: s.short, gap: 16, overlay: o.overlay,
  body: `<section style="${CARD};padding:16px;display:flex;flex-direction:column;gap:12px"><div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><span style="flex:1;min-width:0;${T.small};font-weight:600">${s.name}</span>${stCell(s)}</div><a href="tel:+20" style="display:inline-flex;align-items:center;gap:8px;${T.small};color:${C.teal};font-weight:500">${ico('phone', 16, 2)}${ltr(s.phone)}</a>${idBlock(s, { phone: true })}</section>
${panelBody(s, { ...o, phone: true }).replace(idBlock(s, { ...o, phone: true }), '')}
<div style="display:flex;flex-direction:column;gap:8px">${btn('طلب تصحيح الاسم', { kind: 'outline', icon: 'pencil', phone: true, full: true })}${btn('إزالة من الشركة', { kind: 'dangerQuiet', icon: 'trash', phone: true, full: true })}</div>` });
board('AdmStudentPhone', { row: ROW, w: 390, title: 'Admin web · Students · Phone · One student', tab: 'لوحة الشركة · طالب · هاتف',
  body: (size) => pStudent(size, S1, { request: true }) });
board('AdmStudentActivatePhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Students · Phone · Activate after cash payment', tab: 'لوحة الشركة · تفعيل اشتراك · هاتف',
  body: (size) => pStudent(size, S1, { request: true, overlay: scrim(D.activate(S1, { phone: true }), 'bottom') }) });
board('AdmStudentRemovePhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Students · Phone · Remove from the company', tab: 'لوحة الشركة · إزالة طالب · هاتف',
  body: (size) => pStudent(size, S1, { request: true, overlay: scrim(D.remove(S1, { phone: true }), 'bottom') }) });
const pWizard = (size, n, body, o = {}) => shellPhone({ size, active: 'students', back: 'الطلاب', title: 'إضافة طالب', gap: 16, overlay: o.overlay,
  body: `${stepper({ phone: true, steps: STEPS(n) })}${body}`,
  bottomBar: n === 0 ? btn('التالي', { iconEnd: 'fwd', phone: true, full: true }) : `<div style="display:grid;grid-template-columns:minmax(0,1fr) minmax(0,2fr);gap:8px">${btn('السابق', { kind: 'secondary', phone: true, full: true })}${n === 2 ? btn('تسجيل الطالب', { icon: 'check', phone: true, full: true }) : btn('التالي', { iconEnd: 'fwd', phone: true, full: true })}</div>` });
board('AdmStudentAdd1Phone', { row: ROW, w: 390, title: 'Admin web · Add student · Phone · Step 1', tab: 'لوحة الشركة · إضافة طالب · 1 · هاتف', body: (size) => pWizard(size, 0, step1({ phone: true })) });
board('AdmStudentAdd2Phone', { row: ROW, w: 390, title: 'Admin web · Add student · Phone · Step 2', tab: 'لوحة الشركة · إضافة طالب · 2 · هاتف', body: (size) => pWizard(size, 1, step2({ phone: true })) });
board('AdmStudentAdd3Phone', { row: ROW, w: 390, title: 'Admin web · Add student · Phone · Step 3', tab: 'لوحة الشركة · إضافة طالب · 3 · هاتف', body: (size) => pWizard(size, 2, step3({ phone: true })) });
board('AdmStudentAddInvitedPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Add student · Phone · Invited instead', tab: 'لوحة الشركة · إضافة طالب · دعوة · هاتف',
  body: (size) => pWizard(size, 2, step3({ phone: true }), { overlay: scrim(invitedDialog({ phone: true }), 'bottom') }) });
const invCard = (r) => recordCard({ title: ltr(r[0]), sub: `خط ${r[1]}`, end: state(...r[4]), fields: [['أُرسلت', r[2]], ['تنتهي', r[3]]], actions: r[5] ? btn('إلغاء الدعوة', { kind: 'outline', phone: true, full: true }) : undefined });
board('AdmStudentsInvitesPhone', { row: ROW, w: 390, title: 'Admin web · Students · Phone · Invitations', tab: 'لوحة الشركة · الدعوات · هاتف',
  body: (size) => shellPhone({ size, active: 'students', gap: 14, body: pList({ tab: 1, body: `${invNote}${recordList({ toolbar: { count: 'آخر 10 دعوات · الأحدث أولاً' }, cards: INV.slice(0, 5).map(invCard) })}` }) }) });
const corCard = (r) => recordCard({ title: r[1], sub: `<span style="text-decoration:line-through">${r[0]}</span>`, fields: [['أُرسل', r[2]], ['النتيجة', state(...r[3])], ...(r[4] ? [['ملاحظة المنصة', r[4]]] : [])] });
board('AdmStudentsCorrectionsPhone', { row: ROW, w: 390, title: 'Admin web · Students · Phone · Name corrections', tab: 'لوحة الشركة · تصحيح الاسم · هاتف',
  body: (size) => shellPhone({ size, active: 'students', gap: 14, body: pList({ tab: 2, body: `${corNote}${recordList({ toolbar: { count: 'آخر 10 طلبات · الأحدث أولاً' }, cards: COR.map(corCard) })}` }) }) });
board('AdmStudentsEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Students · Phone · First use', tab: 'لوحة الشركة · الطلاب · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'students', dot: false, gap: 14, body: pList({ total: 0, inv: 0, cor: 0, body: firstS(true) }) }) });
