import {
  board, shellDesktop, shellPhone, sectionHead, statCard, attentionList, dataTable, recordCard, stepper,
  badge, btn, note, emptyState, errorState, skeleton, time, ltr, ico, cell2, C, T, R, CARD, FONT,
} from './kit.mjs';

/* ── Data ───────────────────────────────────────────────────────── */
const DATE = 'السبت 10 أكتوبر 2026';
const TOMORROW = 'الأحد 11 أكتوبر';
export const ATTN = [
  { count: 7, tone: 'warning', title: '7 إيصالات تنتظر مراجعتك', sub: 'أقدمها منذ 3 ساعات · واحد منها في آخر محاولة', action: 'راجع الإيصالات', primary: true },
  { count: 2, tone: 'teal', title: 'طالبان نسيا كلمة المرور', sub: 'أعطِ كل طالب رمزاً مؤقتاً يدخل به', action: 'افتح الطلبات' },
  { icon: 'scan', tone: 'danger', title: 'خط شربين بلا مشرف', sub: 'لا أحد يسجّل ركابه عند الصعود', action: 'عيّن مشرفاً' },
  { icon: 'route', tone: 'danger', title: 'خط كفر البطيخ لا يظهر للطلاب', sub: 'تنقصه رحلة ذهاب إلى جامعة دمياط', action: 'أكمل الخط' },
  { icon: 'bus', tone: 'warning', title: `رحلة فارسكور ${time('7:15', 'ص')} أكبر من الباص`, sub: '47 راكباً أكّدوا والباص 45 مقعداً', action: 'اعرض الرحلة' },
];
export const LINES = [
  { name: 'دمياط الجديدة', subs: 168, go: 124, back: 118, big: ['7:30', 44], seats: 50, sup: 'إبراهيم الدسوقي عبد الحميد' },
  { name: 'الزرقا', subs: 124, go: 107, back: 105, big: ['7:00', 38], seats: 50, sup: 'محمود السيد عبد الغني' },
  { name: 'شربين', subs: 112, go: 81, back: 75, big: ['6:45', 31], seats: 45, sup: null },
  { name: 'فارسكور', subs: 96, go: 71, back: 68, big: ['7:15', 47], seats: 45, sup: 'هاني عبد المقصود', over: 2 },
  { name: 'كفر سعد', subs: 74, go: 52, back: 49, big: ['6:30', 27], seats: 30, sup: 'سامح فتحي البنا' },
  { name: 'السرو', subs: 61, go: 44, back: 40, big: ['7:00', 24], seats: 30, sup: 'محمود السيد عبد الغني' },
  { name: 'ميت أبو غالب', subs: 45, go: 33, back: 31, big: ['6:50', 18], seats: 30, sup: 'إبراهيم الدسوقي عبد الحميد' },
  { name: 'كفر البطيخ', subs: 38, go: 0, back: 0, big: null, seats: 30, sup: 'سامح فتحي البنا', hidden: true },
];
const SUM = LINES.reduce((a, l) => ({ subs: a.subs + l.subs, go: a.go + l.go, back: a.back + l.back }), { subs: 0, go: 0, back: 0 });
const PCT = Math.round((SUM.go / SUM.subs) * 100);

const big = (l) => (l.big ? `${time(l.big[0], 'ص')} · ${l.big[1]} راكباً` : `<span style="color:${C.ink3}">لم يؤكد أحد بعد</span>`);
const seats = (l) => (l.over ? `<span style="display:inline-flex;align-items:center;gap:8px">${l.seats}${badge(`يزيد ${l.over}`, 'warning')}</span>` : `${l.seats}`);
const sup = (l) => (l.sup ?? badge('بلا مشرف', 'danger'));
const numCell = (n) => `<span style="font-size:16px;font-weight:600;color:${n ? C.ink : C.disabled}">${n}</span>`;

const ridersStats = (phone) => `<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:${phone ? 12 : 16}px">
${statCard({ label: 'الذهاب', icon: 'aup', value: SUM.go, unit: 'راكباً', hint: 'في 7 خطوط', phone })}
${statCard({ label: 'العودة', icon: 'adown', value: SUM.back, unit: 'راكباً', hint: 'من الجامعات', phone })}
</div>
${statCard({ label: 'أكّدوا الركوب حتى الآن', icon: 'check', value: `${SUM.go}`, unit: `من ${SUM.subs} مشتركاً · ${ltr(PCT + '%')}`, bar: PCT, hint: `التأكيد مفتوح حتى ${time('6:00', 'ص')} · الأعداد تتغيّر`, phone })}`;

const linesTable = (o = {}) => dataTable({
  caption: 'ركاب الغد في كل خط',
  tablet: o.tablet,
  toolbar: { count: `${LINES.length} خطوط · اضغط خطاً لترى كل رحلة وركابها`, sort: 'الأكثر ركاباً أولاً' },
  columns: [
    { label: 'الخط' }, { label: 'المشتركون', w: 112 }, { label: 'ذهاب', w: 88, sorted: 'desc' }, { label: 'عودة', w: 88 },
    { label: 'أكبر رحلة ذهاب', w: 200 }, { label: 'مقاعد الباص', w: 150 }, { label: 'المشرف', w: 230, hideTablet: true },
  ],
  rows: LINES.map((l, i) => ({ state: o.states?.[i], cells: [
    cell2(l.name, l.hidden ? 'لا يظهر للطلاب بعد' : '', { w: 600 }), `${l.subs}`, numCell(l.go), numCell(l.back), big(l), seats(l), sup(l),
  ] })),
  foot: ['الإجمالي', `${SUM.subs}`, `${SUM.go}`, `${SUM.back}`, '', '', ''],
});

/* ── AdmToday · desktop ─────────────────────────────────────────── */
const todayBody = (states) => `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('يحتاج منك الآن', { meta: badge(`${ATTN.length} أمور`, 'neutral') })}
${attentionList(ATTN)}
</section>
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('ركاب الغد', { meta: badge(TOMORROW, 'teal') })}
${ridersStats(false)}
</section>
</div>
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('ركاب الغد في كل خط', { end: btn('كل الخطوط', { kind: 'link', iconEnd: 'fwd', sm: true }) })}
${linesTable({ states })}
</section>`;
const todayActions = btn('إرسال إشعار للطلاب', { kind: 'outline', icon: 'megaphone' });

board('AdmToday', { row: 'C', w: 1440, title: 'Admin web · Today · Desktop', tab: 'لوحة الشركة · اليوم',
  body: (size) => shellDesktop({ size, active: 'today', title: 'اليوم', sub: DATE, actions: todayActions, body: todayBody({ 1: 'hover' }) }) });

/* ── AdmTodayPhone ──────────────────────────────────────────────── */
board('AdmTodayPhone', { row: 'C', w: 390, title: 'Admin web · Today · Phone', tab: 'لوحة الشركة · اليوم · هاتف',
  body: (size) => shellPhone({ size, active: 'today', sub: DATE, body: `
<section style="display:flex;flex-direction:column;gap:10px">
${sectionHead('يحتاج منك الآن', { phone: true, meta: badge(`${ATTN.length} أمور`, 'neutral') })}
${attentionList(ATTN, { phone: true })}
</section>
<section style="display:flex;flex-direction:column;gap:10px">
${sectionHead('ركاب الغد', { phone: true, meta: badge(TOMORROW, 'teal') })}
${ridersStats(true)}
</section>
<section style="display:flex;flex-direction:column;gap:10px">
${sectionHead('في كل خط', { phone: true, meta: `<span style="${T.label};color:${C.ink2}">${LINES.length} خطوط</span>` })}
${LINES.map((l) => recordCard({
    title: l.name, sub: `${l.subs} مشتركاً${l.hidden ? ' · لا يظهر للطلاب بعد' : ''}`,
    end: `<span style="display:flex;color:${C.ink3};padding-top:2px">${ico('fwd', 18)}</span>`,
    stats: [['ذهاب', numCell(l.go).replace('16px', '18px')], ['عودة', numCell(l.back).replace('16px', '18px')]],
    fields: [['أكبر رحلة ذهاب', big(l)], ['مقاعد الباص', seats(l)], ['المشرف', sup(l)]],
  })).join('\n')}
<div style="${CARD};border-radius:${R.inner}px;padding:12px 16px;display:grid;grid-template-columns:minmax(0,1fr) auto auto;gap:4px 20px;${T.small}"><span style="font-weight:600">الإجمالي</span><span style="color:${C.ink3}">ذهاب <b style="font-weight:600;color:${C.ink}">${SUM.go}</b></span><span style="color:${C.ink3}">عودة <b style="font-weight:600;color:${C.ink}">${SUM.back}</b></span></div>
</section>
${btn('إرسال إشعار للطلاب', { kind: 'outline', icon: 'megaphone', phone: true, full: true })}` }) });

/* ── AdmTodayNew: a brand-new company ───────────────────────────── */
const NEWWHO = { name: 'كريم حسن الشناوي', role: 'مدير الشركة', initial: 'ك', company: 'الصفوة للرحلات', scope: 'لوحة الشركة' };
const setupSteps = (phone) => [
  { state: 'done', label: 'أضف أول خط', sub: 'خط الزرقا · 8 محطات · 5 رحلات ذهاب و5 رحلات عودة',
    body: `<div style="margin-top:8px">${btn('عرض الخط', { kind: 'link', sm: true, iconEnd: 'fwd' })}</div>` },
  { state: 'current', label: 'أضف وسيلة دفع', sub: 'الحساب الذي يحوّل عليه الطلاب ثمن الاشتراك: إنستاباي، محفظة هاتف، أو حساب بنكي. بدونها لا يستطيع أحد أن يدفع.',
    body: `<div style="margin-top:12px;display:flex">${btn('أضف وسيلة دفع', { icon: 'plus', phone, full: phone })}</div>` },
  { state: 'todo', label: 'أضف مشرفاً', sub: 'من يركب مع الباص ويسجّل صعود الطلاب بهاتفه. يلزمه خط واحد على الأقل، وقد أضفته.',
    body: `<div style="margin-top:12px;display:flex">${btn('أضف مشرفاً', { kind: 'secondary', icon: 'plus', phone, full: phone })}</div>` },
];
const setupCard = (phone) => `<section style="${CARD};padding:${phone ? 16 : 24}px;display:flex;flex-direction:column;gap:${phone ? 16 : 20}px">
<div style="display:flex;flex-direction:column;gap:8px">
<div style="display:flex;align-items:baseline;gap:12px"><h2 style="margin:0;${phone ? T.card : T.section}">تجهيز الشركة</h2><span style="flex:1"></span><span style="${T.label};color:${C.ink2}">تمت خطوة واحدة من 3</span></div>
<div role="progressbar" aria-valuemin="0" aria-valuemax="3" aria-valuenow="1" style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px"><span style="height:6px;border-radius:3px;background:${C.ok}"></span><span style="height:6px;border-radius:3px;background:${C.sunken}"></span><span style="height:6px;border-radius:3px;background:${C.sunken}"></span></div>
</div>
${stepper({ vertical: true, steps: setupSteps(phone) })}
<div style="display:flex;align-items:flex-start;gap:12px;border-top:1px solid ${C.hair};padding-top:${phone ? 14 : 16}px;color:${C.ink2}"><span style="display:flex;padding-top:2px;color:${C.ink3}">${ico('users', 20)}</span><div><div style="${T.small};font-weight:500;color:${C.ink}">بعدها: أول طالب يشترك</div><div style="${T.label}">سيصلك إيصاله في صفحة «الإيصالات» لتراجعه، ويظهر هنا عدد الركاب كل يوم.</div></div></div>
</section>`;
const LATER = [
  ['calendar', 'مواعيد الاشتراك', 'الفصل الأول والثاني معروضان للبيع الآن'],
  ['clock', 'تأكيد الركوب', `يؤكد الطلاب حتى ${time('6:00', 'ص')} كل يوم`],
  ['idcard', 'بطاقة الطالب', 'بالشعار والألوان الافتراضية'],
  ['building', 'بيانات الإيصال', 'لم تُكتب بعد'],
];
const laterCard = (phone) => `<section style="${CARD};overflow:hidden">
<div style="padding:${phone ? '14px 16px 8px' : '18px 20px 10px'}"><h2 style="margin:0;${T.card}">لاحقاً، متى أردت</h2><p style="margin:2px 0 0;${T.label};color:${C.ink2}">تعمل الآن بإعدادات المنصة. غيّرها عندما تحتاج.</p></div>
${LATER.map(([i, t, s]) => `<a href="#" style="display:flex;align-items:center;gap:12px;min-height:${phone ? 64 : 60}px;padding:8px ${phone ? 16 : 20}px;border-top:1px solid ${C.hair};color:${C.ink}"><span style="display:flex;color:${C.ink2}">${ico(i, 20)}</span><span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="${T.small};font-weight:500">${t}</span><span style="${T.label};color:${C.ink2}">${s}</span></span><span style="display:flex;color:${C.ink3}">${ico('fwd', 16, 2)}</span></a>`).join('')}
</section>`;
const studentsSee = note({ tone: 'warning', title: 'لا يستطيع الطلاب الاشتراك بعد', text: 'خطك يظهر لهم في التطبيق، لكن لا توجد وسيلة يدفعون بها.' });
const ridersEmpty = (phone) => emptyState({ card: true, phone, icon: 'users', title: 'لا ركاب بعد', text: 'عندما يشترك الطلاب ويؤكدون ركوبهم كل مساء، ترى هنا عدد ركاب الغد في كل خط لتعرف كم باصاً تحتاج.' });

board('AdmTodayNew', { row: 'C', w: 1440, title: 'Admin web · Today · New company · Desktop', tab: 'لوحة الشركة · اليوم · شركة جديدة',
  body: (size) => shellDesktop({ size, active: 'today', who: NEWWHO, badges: {}, title: 'أهلاً كريم، لنجهّز شركتك', sub: 'ثلاث خطوات، وبعدها يستطيع أول طالب أن يشترك من التطبيق.', body: `
<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
${setupCard(false)}
<div style="display:flex;flex-direction:column;gap:16px">${studentsSee}${laterCard(false)}</div>
</div>
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('ركاب الغد')}
${ridersEmpty(false)}
</section>` }) });

board('AdmTodayNewPhone', { row: 'C', w: 390, title: 'Admin web · Today · New company · Phone', tab: 'لوحة الشركة · اليوم · شركة جديدة · هاتف',
  body: (size) => shellPhone({ size, active: 'today', who: NEWWHO, dot: false, body: `
<div><h2 style="margin:0;${T.pagePhone}">أهلاً كريم، لنجهّز شركتك</h2><p style="margin:4px 0 0;${T.small};color:${C.ink2}">ثلاث خطوات، وبعدها يستطيع أول طالب أن يشترك من التطبيق.</p></div>
${setupCard(true)}
${studentsSee}
${laterCard(true)}
<section style="display:flex;flex-direction:column;gap:10px">
${sectionHead('ركاب الغد', { phone: true })}
${ridersEmpty(true)}
</section>` }) });

/* ── AdmTodayStates: loading, offline, error ────────────────────── */
const frame = (label, text, inner) => `<section style="display:flex;flex-direction:column;gap:12px">
<div dir="ltr" style="display:flex;align-items:baseline;gap:12px"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600">${label}</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2}">${text}</p></div>
<div style="border-radius:${R.inner}px;overflow:hidden;box-shadow:0 0 0 1px ${C.hair}, ${'0 16px 40px -12px rgba(23,56,74,.28)'}">${inner.replace('data-root ', '')}</div>
</section>`;
const loadingBody = `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج منك الآن')}${skeleton('list', { rows: 4 })}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('ركاب الغد')}<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px">${skeleton('stat')}${skeleton('stat')}</div>${skeleton('stat')}</section>
</div>`;
const staleBody = `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج منك الآن', { meta: badge(`${ATTN.length} أمور`, 'neutral'), end: `<span style="${T.label};color:${C.ink3}">آخر تحديث ${time('9:12', 'ص')}</span>` })}${attentionList(ATTN.slice(0, 4).map((a) => ({ ...a, primary: false })))}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('ركاب الغد', { meta: badge(TOMORROW, 'teal') })}${ridersStats(false)}</section>
</div>`;
const errBody = errorState({ card: true, title: 'تعذّر تحميل صفحة اليوم', text: 'لم نستطع جلب الإيصالات وأعداد الركاب. تأكد من اتصالك ثم حاول مرة أخرى.' });
const W = 1312;
board('AdmTodayStates', { row: 'C', w: 1440, lang: 'en', title: 'Admin web · Today · Loading, offline, error', tab: 'Basak admin web · Today · states',
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">
${frame('Loading', 'A skeleton in the shape of the page. The shell, the title and the section headings are real from the first frame; only the data is grey.', shellDesktop({ size: `width:${W}px;height:620px`, active: 'today', title: 'اليوم', sub: DATE, actions: todayActions, body: loadingBody }))}
${frame('Offline', 'An amber bar under the top bar on every page. The last loaded data stays, marked with its time; buttons that write are held back until the connection returns.', shellDesktop({ size: `width:${W}px;height:700px`, active: 'today', title: 'اليوم', sub: DATE, offline: true, actions: btn('إرسال إشعار للطلاب', { kind: 'outline', icon: 'megaphone', state: 'disabled' }), body: staleBody }))}
${frame('Error', 'Plain Arabic, never the server\'s text or an HTTP code. Always a retry. The navigation keeps working.', shellDesktop({ size: `width:${W}px;height:560px`, active: 'today', title: 'اليوم', sub: DATE, body: errBody }))}
</div>` });
