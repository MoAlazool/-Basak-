/** مواعيد الاشتراك — /c/:companyId/subscription-periods */
import {
  board, shellDesktop, shellPhone, sectionHead, dataTable, btn, badge, note, dialog, scrim, emptyState, errorState, skeleton,
  money, cell2, ico, C, T, R, CARD,
} from './kit.mjs';
import { col, row, card, sw, box, statesBoard, mini, muted, LINES, ticks } from './m-common.mjs';

const ROW = 'D';
const YEAR = 'العام الدراسي 2026/2027';
const SUB = 'متى يبدأ كل فصل وينتهي، وأي الاشتراكات يجدها الطالب في التطبيق الآن. السعر يُكتب في كل خط.';

/* ── Data ───────────────────────────────────────────────────────── */
const TERMS = [
  { code: 'first', name: 'الفصل الأول', s: [26, 'سبتمبر', 2026], e: [21, 'يناير', 2027], on: true, see: ['success', 'يُباع الآن', 'في 7 خطوط من 8'] },
  { code: 'second', name: 'الفصل الثاني', s: [6, 'فبراير', 2027], e: [3, 'يونيو', 2027], on: true, see: ['teal', 'يُباع مقدماً', 'في 7 خطوط من 8 · يبدأ 6 فبراير'] },
  { code: 'both', name: 'الفصلان معاً', fixed: 'اشتراك واحد للفصلين الأول والثاني، بلا الصيفي', span: 'من بداية الأول إلى نهاية الثاني', on: true, see: ['success', 'يُباع الآن', 'في 4 خطوط من 8 · حتى نهاية الفصل الأول'] },
  { code: 'summer', name: 'الفصل الصيفي', s: [3, 'يوليو', 2027], e: [2, 'سبتمبر', 2027], on: false, see: ['neutral', 'لا يظهر للطلاب', 'أنت أوقفت بيعه'] },
  { code: 'daily', name: 'اليومي (نقداً)', fixed: 'ليوم واحد، يُدفع نقداً', span: 'بلا مواعيد: متاح كل يوم', on: true, see: ['success', 'يُباع الآن', 'سعره في كل خط'] },
];
const WHY = { off: ['أوقفت بيعه', 'neutral'], lineOff: ['الخط متوقف', 'neutral'], notHere: ['متوقف في هذا الخط', 'neutral'], noPrice: ['بلا سعر', 'warning'], advance: ['الدفع المسبق متوقف', 'neutral'], season: ['ليس وقته الآن', 'neutral'] };
const why = (k) => badge(`لا يظهر: ${WHY[k][0]}`, WHY[k][1]);
const PRICES = [[4500, 4500, 8000], [4500, 4500, 8000], [4200, 4200, 7600], [4000, 4000, 'notHere'], [3800, 3800, 7000], [3600, 3600, 'noPrice'], [3600, 3600, 'noPrice'], ['lineOff', 'lineOff', 'lineOff']];
const cellOpt = (v, adv) => (typeof v === 'number' ? `<span style="display:inline-flex;align-items:center;gap:8px;font-weight:500">${money(v)}${adv ? badge('مقدماً', 'teal') : ''}</span>` : why(v));

/* ── Parts ──────────────────────────────────────────────────────── */
const dayMonth = (d, o = {}) => `<div style="display:flex;flex-direction:column;gap:4px;min-width:0"><div style="display:flex;gap:6px">${box(`<span dir="ltr" style="flex:1;text-align:center">${d[0]}</span>`, { w: 52, changed: o.changed, error: o.error, phone: o.phone })}${box(`<span style="flex:1;min-width:0">${d[1]}</span><span style="display:flex;color:${C.ink3}">${ico('down', 16)}</span>`, { changed: o.changed, error: o.error, phone: o.phone })}</div><span style="${T.cap};color:${o.error ? C.bad : o.changed ? C.warn : C.ink3}">${o.error ?? (o.changed ? `كان ${o.changed} · لم يُحفظ` : d[2])}</span></div>`;
const seeCell = (t, o = {}) => `<div style="display:flex;flex-direction:column;gap:2px;min-width:0;align-items:flex-start">${o.badge ?? badge(t.see[1], t.see[0])}<span style="${T.label};color:${C.ink2}">${o.text ?? t.see[2]}</span></div>`;
const HEAD = ['الاشتراك', 'يبدأ', 'ينتهي', 'معروض للبيع', 'ما يراه الطلاب الآن'];
const COLS = 'minmax(0,1.25fr) 188px 188px 104px minmax(0,1.35fr)';
const termsCard = (o = {}) => `<section style="${CARD};overflow:hidden">
<div role="row" style="display:grid;grid-template-columns:${COLS};gap:20px;align-items:center;height:44px;padding:0 20px;background:${C.ground};${T.label};font-weight:500;color:${C.ink2}">${HEAD.map((h) => `<span>${h}</span>`).join('')}</div>
${TERMS.map((t) => {
    const x = o[t.code] ?? {};
    return `<div role="row" style="display:grid;grid-template-columns:${COLS};gap:20px;align-items:center;min-height:92px;padding:14px 20px;border-top:1px solid ${C.hair}">
<div style="min-width:0;display:flex;flex-direction:column;gap:4px">${t.fixed ? `<span style="${T.small};font-weight:600">${t.name}</span><span style="${T.label};color:${C.ink2}">${t.fixed}</span>` : `<div style="display:flex">${box(`<span style="flex:1;min-width:0;font-weight:600">${t.name}</span><span style="display:flex;color:${C.ink3}">${ico('pencil', 15)}</span>`)}</div><span style="${T.cap};color:${C.ink3}">الاسم كما يراه الطالب</span>`}</div>
${t.fixed ? `<div style="grid-column:span 2;${T.small};color:${C.ink2}">${t.span}</div>` : `${dayMonth(x.s ?? t.s, { error: x.sErr })}${dayMonth(x.e ?? t.e, { changed: x.eWas, error: x.eErr })}`}
<div style="display:flex;flex-direction:column;gap:4px;align-items:flex-start">${sw(x.on ?? t.on, { label: `بيع ${t.name}`, changed: x.onChanged, locked: x.locked })}<span style="${T.cap};color:${x.onChanged ? C.warn : C.ink3}">${x.locked ? 'أوقفته المنصة' : x.onChanged ? 'لم يُحفظ' : (x.on ?? t.on) ? 'نعم' : 'لا'}</span></div>
${seeCell(t, x.see ?? {})}
</div>`;
  }).join('')}
<div style="display:flex;align-items:center;gap:16px;min-height:76px;padding:14px 20px;border-top:1px solid ${C.hair};background:${C.surface}">
<div style="flex:1;min-width:0"><div style="${T.small};font-weight:600">الدفع المسبق للفصل القادم</div><div style="${T.label};color:${C.ink2}">يدفع الطالب الفصل القادم قبل أن يبدأ، بسعره في الخط. عند إيقافه يُباع الفصل الجاري فقط.</div></div>
${sw(o.advance ?? true, { label: 'الدفع المسبق', changed: o.advanceChanged })}
</div>
<div style="display:flex;align-items:center;gap:8px;padding:10px 20px;border-top:1px solid ${C.hair};background:${C.ground};${T.label};color:${C.ink2}">${ico('info', 16)}<span>المواعيد تتكرر كل عام في اليوم والشهر نفسيهما. هذه مواعيد شركتك وحدها، ويستخدمها التطبيق والإيصالات وانتهاء الاشتراكات.</span></div>
</section>`;

const previewTable = (o = {}) => dataTable({
  caption: 'ما يراه الطلاب في كل خط',
  toolbar: { count: o.count ?? 'كما هو محفوظ الآن · 8 خطوط' },
  columns: [{ label: 'الخط' }, { label: 'الفصل الأول', w: 190 }, { label: 'الفصل الثاني', w: 210 }, { label: 'الفصلان معاً', w: 230 }, { label: 'الفصل الصيفي', w: 170 }, { label: '', w: 130, align: 'end' }],
  rows: LINES.map((l, i) => ({ cells: [cell2(l, i === 7 ? 'لا يظهر للطلاب' : '', { w: 600 }), cellOpt(PRICES[i][0]), cellOpt(o.advanceOff && typeof PRICES[i][1] === 'number' ? 'advance' : PRICES[i][1], true), cellOpt(PRICES[i][2]), i === 7 ? why('lineOff') : why('off'), btn('أسعار الخط', { kind: 'link', sm: true, iconEnd: 'fwd' })] })),
  empty: o.empty,
});

const dirtyBar = (n = 'تغييران لم يُحفظا بعد', phone) => note({ tone: 'warning', icon: 'pencil', title: n, text: 'الطلاب ما زالوا يرون ما كان محفوظاً. لا شيء يتغيّر عندهم حتى تضغط «حفظ التغييرات».' });
const actions = (state) => btn('تراجع عن التغييرات', { kind: 'outline', icon: 'undo', state }) + btn('حفظ التغييرات', { icon: 'check', state });
const DRAFT = { first: { e: [28, 'يناير', 2027], eWas: '21 يناير' }, both: { on: false, onChanged: true, see: { badge: badge('سيتوقف بيعه بعد الحفظ', 'warning'), text: 'يُباع الآن في 4 خطوط' } } };
const pageBody = (o = DRAFT, extra = {}) => `${extra.top ?? dirtyBar()}
${termsCard(o)}
<section style="display:flex;flex-direction:column;gap:12px">
${sectionHead('ما يراه الطلاب في كل خط', { meta: muted('السعر، أو سبب عدم الظهور', T.label) })}
${extra.table ?? previewTable()}
</section>`;
const meta = badge(YEAR, 'teal');

board('AdmDates', { row: ROW, w: 1440, title: 'Admin web · Subscription periods · Desktop (two unsaved changes)', tab: 'لوحة الشركة · مواعيد الاشتراك',
  body: (size) => shellDesktop({ size, active: 'subscription-periods', title: 'مواعيد الاشتراك', sub: SUB, meta, actions: actions(), body: pageBody() }) });

/* ── Confirmations ──────────────────────────────────────────────── */
const change = (title, lines) => `<div style="border-radius:${R.inner}px;background:${C.ground};padding:12px 14px;display:flex;flex-direction:column;gap:4px"><div style="${T.small};font-weight:600;color:${C.ink}">${title}</div>${lines.map((l) => `<div style="${T.label};color:${C.ink2}">${l}</div>`).join('')}</div>`;
const saveDialog = (phone) => dialog({ phone, w: 560, icon: 'calendar', title: 'حفظ تغييرين في مواعيد الاشتراك؟',
  body: `<span>هذا ما سيحدث عند الطلاب فور الحفظ:</span>
${change('الفصل الأول ينتهي 28 يناير 2027 بدل 21 يناير', ['412 اشتراكاً مفتوحاً في الفصل الأول ينتهي في الموعد الجديد.', 'الإيصالات التي صدرت من قبل تبقى بتاريخها القديم.'])}
${change('إيقاف بيع «الفصلان معاً»', ['يختفي من التطبيق في 4 خطوط، ولا يستطيع طالب جديد أن يشتريه.', 'المشتركون فيه الآن (180 طالباً) يبقى اشتراكهم كما هو.'])}`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('حفظ التغييرات', { phone, full: phone })] });
const openDialog = (phone) => dialog({ phone, w: 560, icon: 'check', tone: 'success', title: 'فتح بيع الفصل الصيفي؟',
  body: `<span>يظهر الفصل الصيفي (3 يوليو – 2 سبتمبر 2027) للطلاب في الخطوط التي كتبت له سعراً.</span>${note({ tone: 'warning', title: 'لا خط له سعر صيفي بعد', text: 'لن يراه أحد حتى تكتب سعره في خط واحد على الأقل، من صفحة «الخطوط».' })}`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('حفظ وفتح البيع', { phone, full: phone })] });
const leaveDialog = (phone) => dialog({ phone, icon: 'alert', tone: 'warning', title: 'الخروج دون حفظ؟',
  body: '<span>غيّرت موعداً وأوقفت اشتراكاً ولم تحفظ. إن خرجت الآن يبقى كل شيء كما كان.</span>',
  actions: [btn('رجوع إلى الصفحة', { kind: 'secondary', phone, full: phone }), btn('الخروج دون حفظ', { kind: 'dangerQuiet', phone, full: phone })] });

board('AdmDatesConfirm', { row: ROW, w: 1440, h: 1180, title: 'Admin web · Subscription periods · Save, open-a-period and leave confirmations', tab: 'لوحة الشركة · مواعيد الاشتراك · تأكيد',
  body: (size) => shellDesktop({ size, active: 'subscription-periods', title: 'مواعيد الاشتراك', sub: SUB, meta, actions: actions(), body: pageBody(),
    overlay: scrim(`<div style="display:flex;flex-direction:column;gap:24px;align-items:center">${saveDialog()}${openDialog()}${leaveDialog()}</div>`) }) });

/* ── States ─────────────────────────────────────────────────────── */
const head = { active: 'subscription-periods', title: 'مواعيد الاشتراك', sub: SUB, meta };
const ERR = { second: { s: [20, 'يناير', 2027], sErr: 'يبدأ قبل نهاية الفصل الأول' }, summer: { e: [31, 'يونيو', 2027], eErr: 'يونيو 30 يوماً فقط' }, daily: { on: false, locked: true, see: { badge: badge('لا يظهر للطلاب', 'neutral'), text: 'أوقفته إدارة المنصة عند كل الشركات' } } };
const NOL = { see: { badge: badge('لا يظهر للطلاب', 'neutral'), text: 'لا توجد خطوط بعد' } };
const NOLINES = { first: NOL, second: NOL, both: NOL, summer: NOL, daily: NOL };
statesBoard('AdmDatesStates', { row: ROW, title: 'Admin web · Subscription periods · States', frames: [
  ['Saved', 'Nothing to save: the buttons are held back and the amber bar is gone. The advance switch is off here, so the second term shows why students do not see it.',
    mini(1010, { ...head, actions: actions('disabled'), body: pageBody({ second: { see: { badge: badge('لا يظهر للطلاب', 'neutral'), text: 'يبدأ 6 فبراير، والدفع المسبق متوقف' } }, advance: false }, { top: '', table: previewTable({ advanceOff: true }) }) })],
  ['Field errors and a platform lock', 'Dates are checked as they are typed, under the field. A subscription the platform has stopped is locked and says who stopped it. Save stays off until the errors are fixed.',
    mini(840, { ...head, actions: btn('تراجع عن التغييرات', { kind: 'outline', icon: 'undo' }) + btn('حفظ التغييرات', { icon: 'check', state: 'disabled' }), body: `${note({ tone: 'danger', title: 'موعدان يحتاجان تصحيحاً قبل الحفظ', text: 'الفصل الثاني يبدأ قبل نهاية الأول، ونهاية الفصل الصيفي ليست يوماً صحيحاً.' })}${termsCard(ERR)}` })],
  ['No lines yet', 'First use: the dates work from the platform defaults; the preview says what is missing and offers the step that fills it.',
    mini(1180, { ...head, actions: actions('disabled'), body: pageBody(NOLINES, { top: '', table: `<div style="${CARD}">${emptyState({ icon: 'route', title: 'لا توجد خطوط بعد', text: 'المواعيد جاهزة، لكن الطالب لا يجد شيئاً يشترك فيه حتى تضيف خطاً وتكتب أسعاره. سترى هنا ما يظهر له في كل خط.', action: btn('أضف أول خط', { icon: 'plus' }) })}</div>` }) })],
  ['Loading', 'The shell and the title are real; the table of periods and the preview are grey.',
    mini(560, { ...head, body: `${skeleton('list', { rows: 4, rowH: 84 })}${skeleton('table', { rows: 2, cols: 5 })}` })],
  ['Error', 'Plain Arabic and a retry. Nothing typed is lost if a save fails: the page keeps the draft and says so in a toast.',
    mini(520, { ...head, body: errorState({ card: true, title: 'تعذّر تحميل مواعيد الاشتراك', text: 'لم نستطع جلب المواعيد. تأكد من اتصالك ثم حاول مرة أخرى.' }) })],
  ['Offline', 'The last loaded dates stay readable; switches and save are held back until the connection returns.',
    mini(560, { ...head, offline: true, actions: actions('disabled'), body: termsCard({}) })],
] });

/* ── Phone ──────────────────────────────────────────────────────── */
const termPhone = (t, x = {}) => `<section style="${CARD};border-radius:${R.inner}px;padding:14px 16px;display:flex;flex-direction:column;gap:12px">
<div style="display:flex;align-items:flex-start;gap:12px"><div style="flex:1;min-width:0"><div style="font-size:15px;line-height:22px;font-weight:600">${t.name}</div><div style="${T.label};color:${C.ink2}">${t.fixed ?? 'اضغط الاسم لتغييره'}</div></div><div style="display:flex;flex-direction:column;align-items:flex-end;gap:2px">${sw(x.on ?? t.on, { label: `بيع ${t.name}`, changed: x.onChanged })}<span style="${T.cap};color:${x.onChanged ? C.warn : C.ink3}">${x.onChanged ? 'لم يُحفظ' : 'معروض للبيع'}</span></div></div>
${t.fixed ? `<div style="${T.label};color:${C.ink2}">${t.span}</div>` : `<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px"><div style="display:flex;flex-direction:column;gap:6px"><span style="${T.label};font-weight:500">يبدأ</span>${dayMonth(x.s ?? t.s, { phone: true })}</div><div style="display:flex;flex-direction:column;gap:6px"><span style="${T.label};font-weight:500">ينتهي</span>${dayMonth(x.e ?? t.e, { phone: true, changed: x.eWas })}</div></div>`}
<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;border-top:1px solid ${C.hair};padding-top:10px">${(x.see?.badge) ?? badge(t.see[1], t.see[0])}<span style="${T.label};color:${C.ink2}">${x.see?.text ?? t.see[2]}</span></div>
</section>`;
const linePhone = (l, i) => `<a href="#" style="${CARD};border-radius:${R.inner}px;padding:12px 16px;display:flex;flex-direction:column;gap:8px;color:${C.ink}"><div style="display:flex;align-items:center;gap:8px"><span style="flex:1;font-size:15px;line-height:22px;font-weight:600">${l}</span><span style="display:flex;color:${C.ink3}">${ico('fwd', 16, 2)}</span></div><dl style="margin:0;display:grid;grid-template-columns:auto minmax(0,1fr);gap:6px 16px;${T.small}">${[['الفصل الأول', cellOpt(PRICES[i][0])], ['الفصل الثاني', cellOpt(PRICES[i][1], true)], ['الفصلان معاً', cellOpt(PRICES[i][2])], ['الصيفي', i === 7 ? why('lineOff') : why('off')]].map(([k, v]) => `<dt style="color:${C.ink3};font-size:13px">${k}</dt><dd style="margin:0;text-align:end">${v}</dd>`).join('')}</dl></a>`;
const phoneBody = `${dirtyBar()}
<div style="display:flex">${meta}</div>
${TERMS.map((t) => termPhone(t, DRAFT[t.code])).join('\n')}
<section style="${CARD};border-radius:${R.inner}px;padding:14px 16px;display:flex;align-items:center;gap:12px"><div style="flex:1;min-width:0"><div style="${T.small};font-weight:600">الدفع المسبق للفصل القادم</div><div style="${T.label};color:${C.ink2}">يدفع الطالب الفصل القادم قبل أن يبدأ.</div></div>${sw(true, { label: 'الدفع المسبق' })}</section>
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('ما يراه الطلاب في كل خط', { phone: true })}<span style="${T.label};color:${C.ink2}">كما هو محفوظ الآن · 8 خطوط</span>${LINES.slice(0, 4).map(linePhone).join('\n')}${btn('اعرض الخطوط الأربعة الباقية', { kind: 'outline', phone: true, full: true })}</section>`;
const phoneBar = btn('حفظ التغييرات', { phone: true, full: true, icon: 'check' }) + btn('تراجع عن التغييرات', { kind: 'link', phone: true, full: true });
board('AdmDatesPhone', { row: ROW, w: 390, title: 'Admin web · Subscription periods · Phone', tab: 'لوحة الشركة · مواعيد الاشتراك · هاتف',
  body: (size) => shellPhone({ size, active: 'subscription-periods', sub: SUB, body: phoneBody, bottomBar: phoneBar }) });
board('AdmDatesConfirmPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Subscription periods · Save confirmation · Phone', tab: 'لوحة الشركة · مواعيد الاشتراك · تأكيد · هاتف',
  body: (size) => shellPhone({ size, active: 'subscription-periods', sub: SUB, body: phoneBody, overlay: scrim(saveDialog(true), 'bottom') }) });
board('AdmDatesEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Subscription periods · No lines yet · Phone', tab: 'لوحة الشركة · مواعيد الاشتراك · بلا خطوط · هاتف',
  body: (size) => shellPhone({ size, active: 'subscription-periods', sub: SUB, body: `<div style="display:flex">${meta}</div>
${TERMS.slice(0, 2).map((t) => termPhone(t, { see: { badge: badge('لا يظهر للطلاب', 'neutral'), text: 'لا توجد خطوط بعد' } })).join('\n')}
${emptyState({ card: true, phone: true, icon: 'route', title: 'لا توجد خطوط بعد', text: 'المواعيد جاهزة، لكن الطالب لا يجد شيئاً يشترك فيه حتى تضيف خطاً وتكتب أسعاره.', action: btn('أضف أول خط', { icon: 'plus', phone: true, full: true }) })}`, bottomBar: btn('حفظ التغييرات', { phone: true, full: true, state: 'disabled' }) }) });
void row; void col; void card; void ticks;
