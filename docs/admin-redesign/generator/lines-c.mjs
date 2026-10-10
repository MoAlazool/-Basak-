/** Ride confirmation: when students confirm tomorrow's ride, reminders, days without reminders. */
import {
  board, shellDesktop, shellPhone, dialog, scrim, field, fieldRow, badge, btn, note, toast, errorState, skeleton, time, ico, C, T, R, CARD,
} from './kit.mjs';
import { col, card, h3, small, pick, tag, statesBoard, dialogsBoard, back, FW } from './lines-kit.mjs';

const SUB = 'كل مساء يؤكد الطالب في التطبيق أنه سيركب غداً، فتعرف كم راكباً في كل رحلة. هنا تحدد متى يُفتح التأكيد، متى يُقفل، ومتى نذكّر من لم يؤكد.';
const OPEN = time('4:00', 'م'); const CLOSE = time('6:00', 'ص');
const WEEK = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

/** Local: several titled groups of fields in one card with ONE save row (the page saves with one request). */
const formGroup = (groups, footer, phone) => `<section style="${CARD};display:flex;flex-direction:column;min-width:0">${groups.map((g, i) => `<div style="display:grid;grid-template-columns:${phone ? 'minmax(0,1fr)' : 'minmax(0,4fr) minmax(0,8fr)'};gap:${phone ? 12 : 32}px;padding:${phone ? 16 : 24}px;${i ? `border-top:1px solid ${C.hair}` : ''}">
<div><h2 style="margin:0;${T.card}">${g.title}</h2>${g.help ? `<p style="margin:${phone ? 2 : 4}px 0 0;${T.label};color:${C.ink2}">${g.help}</p>` : ''}</div>
<div style="display:flex;flex-direction:column;gap:16px;min-width:0">${g.body}</div></div>`).join('')}
${footer ? `<div style="display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:12px 24px;border-top:1px solid ${C.hair}">${footer}</div>` : ''}</section>`;

/* ── The plain timeline: today → tomorrow's ride ────────────────── */
const mark = (pct, top, label, o = {}) => `<div style="position:absolute;inset-inline-start:${pct}%;${top ? 'bottom:22px' : 'top:22px'};transform:translateX(50%);display:flex;flex-direction:column;align-items:center;gap:2px;white-space:nowrap">${top ? `<span style="${T.label};font-weight:600;color:${o.color ?? C.ink}">${label}</span><span style="${T.cap};color:${C.ink2}">${o.sub ?? ''}</span>` : `<span style="display:flex;color:${C.ink3}">${ico('megaphone', 14)}</span><span style="${T.cap};color:${C.ink2}">${label}</span>`}</div>`;
const dot = (pct, color) => `<span aria-hidden="true" style="position:absolute;inset-inline-start:${pct}%;top:50%;width:14px;height:14px;border-radius:7px;background:${color};box-shadow:0 0 0 3px ${C.surface};transform:translate(50%,-50%)"></span>`;
const timeline = () => card(`${h3('مثال: رحلة الأحد 11 أكتوبر', `<span style="display:flex;align-items:center;gap:6px;${T.label};color:${C.ink2}"><span style="width:20px;height:8px;border-radius:4px;background:${C.teal}"></span>التأكيد مفتوح</span>`)}
<div style="position:relative;height:150px;margin:0 8px" role="img" aria-label="يُفتح التأكيد السبت 4:00 م ويُقفل الأحد 6:00 ص، مع ثلاثة تذكيرات">
<div style="position:absolute;inset-inline:0;top:50%;height:8px;border-radius:4px;background:${C.sunken};transform:translateY(-50%)"></div>
<div style="position:absolute;inset-inline-start:16.7%;width:58.3%;top:50%;height:8px;border-radius:4px;background:${C.teal};transform:translateY(-50%)"></div>
<div aria-hidden="true" style="position:absolute;inset-inline-start:50%;top:30%;bottom:30%;width:0;border-inline-start:1.5px dashed ${C.disabled}"></div>
${dot(16.7, C.teal)}${dot(75, C.ink)}
<div style="position:absolute;inset:0 0 50% 0">${mark(16.7, true, `يُفتح ${OPEN}`, { sub: 'يظهر السؤال للطلاب', color: C.teal })}${mark(75, true, `يُقفل ${CLOSE}`, { sub: 'تثبت الأعداد للمشرف ولك' })}</div>
<div style="position:absolute;inset:50% 0 0 0">${mark(16.7, false, `تذكير ${OPEN}`)}${mark(41.7, false, `تذكير ${time('10:00', 'م')}`)}${mark(66.7, false, `تذكير ${time('4:00', 'ص')}`)}</div>
</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:0;${T.label};color:${C.ink2};border-top:1px solid ${C.hair};padding-top:10px"><span><b style="font-weight:600;color:${C.ink}">السبت 10 أكتوبر</b> · اليوم السابق للرحلة</span><span style="padding-inline-start:12px"><b style="font-weight:600;color:${C.ink}">الأحد 11 أكتوبر</b> · يوم الرحلة، وأول رحلة ${time('6:15', 'ص')}</span></div>`);
const TL = [
  ['السبت', OPEN, 'يُفتح التأكيد، ويصل أول تذكير', C.teal], ['السبت', time('10:00', 'م'), 'تذكير لمن لم يؤكد', C.disabled], ['الأحد', time('4:00', 'ص'), 'تذكير لمن لم يؤكد', C.disabled],
  ['الأحد', CLOSE, 'يُقفل التأكيد وتثبت الأعداد', C.ink], ['الأحد', time('6:15', 'ص'), 'أول رحلة ذهاب', C.ok],
];
const timelinePhone = () => card(`${h3('مثال: رحلة الأحد 11 أكتوبر')}
<ol style="margin:0;padding:0;list-style:none">${TL.map(([d, t, s, c], i) => `<li style="display:flex;gap:12px"><div style="display:flex;flex-direction:column;align-items:center;width:14px"><span style="width:14px;height:14px;border-radius:7px;background:${c};margin-top:5px;flex:none"></span>${i < TL.length - 1 ? `<span style="flex:1;width:${i < 3 ? 4 : 2}px;background:${i < 3 ? C.teal : C.hair};min-height:22px"></span>` : ''}</div><div style="flex:1;padding-bottom:${i < TL.length - 1 ? 12 : 0}px"><div style="${T.small};font-weight:600">${d} ${t}</div><div style="${T.label};color:${C.ink2}">${s}</div></div></li>`).join('')}</ol>`, 16);

const studentsSee = (phone) => card(`${h3('ما يراه الطالب')}
${[['smartphone', `من ${OPEN} السبت حتى ${CLOSE} الأحد يؤكد ركوبه لرحلة الأحد أو يلغيه.`], ['megaphone', 'من لم يؤكد يصله تذكير في التطبيق 3 مرات. يتوقف التذكير حين يؤكد أو يلغي.'], ['lock', `بعد ${CLOSE} يُقفل تأكيد رحلة الأحد.`]].map(([i, t]) => `<div style="display:flex;gap:12px;align-items:flex-start"><span style="display:flex;color:${C.teal};padding-top:2px">${ico(i, 18)}</span><span style="${T.small};color:${C.ink2}">${t}</span></div>`).join('')}
<div style="border-top:1px solid ${C.hair};padding-top:10px;${T.label};color:${C.ink2}">أعداد من أكّدوا تراها في <a href="#" style="font-weight:500">اليوم</a>، ولكل خط في <a href="#" style="font-weight:500">الخطوط</a>.</div>`, phone ? 16 : 20);
const sourceCard = (custom, phone) => card(custom
  ? `${h3('مواعيد خاصة بشركتك', badge('خاصة', 'teal'))}${small(`مواعيد المنصة التي تركتها: يُفتح ${OPEN}، يُقفل ${CLOSE}، تذكير كل 3 ساعات، وبلا تذكير كل جمعة.`)}<div style="display:flex">${btn('الرجوع إلى مواعيد المنصة', { kind: 'outline', icon: 'undo', phone, full: phone })}</div>`
  : `${h3('تعمل بمواعيد المنصة', badge('المنصة', 'neutral'))}${small('لم تحدد شركتك مواعيدها بعد، فتتبع ما تضعه إدارة المنصة وتتغيّر معه. أي تعديل تحفظه هنا يصبح خاصاً بشركتك.')}`, phone ? 16 : 20);

const groups = (phone, o = {}) => [
  { title: 'متى يؤكد الطلاب', help: 'التأكيد يُفتح في اليوم السابق للرحلة. إن كان موعد الإقفال قبل موعد الفتح فهو في صباح يوم الرحلة.', body: `${fieldRow([
    field({ type: 'time', label: 'يُفتح التأكيد', value: o.same ? time('6:00', 'ص') : OPEN, help: 'في اليوم السابق للرحلة', phone }),
    field({ type: 'time', label: 'يُقفل التأكيد', value: CLOSE, help: o.same ? undefined : 'يوم الرحلة نفسه', error: o.same ? 'موعد الإقفال يجب أن يختلف عن موعد الفتح.' : undefined, phone }),
  ], { phone })}` },
  { title: 'تذكير من لم يؤكد', help: 'إشعار في التطبيق لمن لم يؤكد ولم يلغِ فقط.', body: `${field({ type: 'select', label: 'كم مرة نذكّره', value: o.platform ? 'كل 3 ساعات' : 'كل 6 ساعات', phone, w: phone ? undefined : 320 })}
<div style="border-radius:${R.control}px;background:${C.ground};padding:10px 14px;${T.label};color:${C.ink2}">${o.platform ? `5 تذكيرات: ${OPEN}، ${time('7:00', 'م')}، ${time('10:00', 'م')}، ${time('1:00', 'ص')}، ${time('4:00', 'ص')}.` : `3 تذكيرات: ${OPEN}، ${time('10:00', 'م')}، ${time('4:00', 'ص')}.`} الاختيارات: بدون تذكير، كل 15 أو 30 دقيقة، كل ساعة، ساعتين، 3، 4 أو 6 ساعات، أو مرة واحدة عند فتح التأكيد.</div>` },
  { title: 'أيام بلا تذكير', help: 'أيام لا تعمل فيها الرحلات. المقصود يوم الرحلة نفسه: اختيار الجمعة يوقف تذكير رحلة الجمعة. التأكيد نفسه يبقى متاحاً لمن أراد.', body: `
<div style="display:flex;flex-direction:column;gap:8px"><div style="${T.label};font-weight:500">كل أسبوع</div><div style="display:${phone ? 'grid' : 'flex'};${phone ? 'grid-template-columns:repeat(2,minmax(0,1fr));' : 'flex-wrap:wrap;'}gap:8px">${WEEK.map((d, i) => pick(d, i === 6 || (!o.platform && i === 0 && false), { phone, full: phone })).join('')}</div></div>
<div style="display:flex;flex-direction:column;gap:8px"><div style="${T.label};font-weight:500">إجازات رسمية</div>
<div style="display:flex;gap:8px;align-items:flex-start">${field({ type: 'date', value: o.badDate ? '8 أكتوبر 2026' : '', placeholder: 'اختر يوماً', phone, w: phone ? undefined : 220, error: o.badDate ? 'اختر اليوم أو يوماً بعده.' : undefined }).replace('min-width:0;', 'min-width:0;flex:1;')}${btn('أضف', { kind: 'outline', icon: 'plus', phone, state: o.platform ? 'disabled' : undefined })}</div>
<div style="display:flex;flex-wrap:wrap;gap:8px">${o.platform ? `<span style="${T.label};color:${C.ink3}">لا إجازات قادمة.</span>` : ['الخميس 22 أكتوبر', 'الأحد 1 نوفمبر', 'الاثنين 2 نوفمبر'].map((d) => tag(d, { phone, name: d })).join('')}</div></div>` },
];
const footer = (o = {}) => `${o.changed ? `<span style="${T.label};color:${C.ink2}">غيّرت 3 أشياء ولم تُحفظ</span>` : ''}<span style="flex:1"></span>${btn('تراجع عن التغييرات', { kind: 'secondary', state: o.changed ? undefined : 'disabled' })}${btn('حفظ مواعيد التأكيد', { state: o.changed ? undefined : 'disabled' })}`;
const page = (o = {}) => `${timeline()}
<div style="display:grid;grid-template-columns:minmax(0,8fr) minmax(0,4fr);gap:24px;align-items:start">
${formGroup(groups(false, o), footer(o))}
<div style="display:flex;flex-direction:column;gap:16px">${sourceCard(!o.platform)}${studentsSee()}</div>
</div>`;

board('AdmRide', { row: 'R', w: 1440, title: 'Admin web · Ride confirmation · Desktop', tab: 'لوحة الشركة · تأكيد الركوب',
  body: (size) => shellDesktop({ size, active: 'ride-confirmation', title: 'تأكيد الركوب', sub: SUB, body: page({ changed: true }) }) });

const D = {
  save: (phone) => dialog({ phone, tone: 'teal', icon: 'clock', title: 'حفظ مواعيد التأكيد؟', body: `<span>لكل طلاب شركتك: يُفتح التأكيد ${OPEN} في اليوم السابق ويُقفل ${CLOSE} يوم الرحلة، بتذكير كل 6 ساعات.</span><span>بلا تذكير: كل جمعة، و3 إجازات. تصبح هذه مواعيد خاصة بشركتك ولا تتبع المنصة بعدها.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('حفظ المواعيد', { phone, full: phone })] }),
  reset: (phone) => dialog({ phone, tone: 'warning', icon: 'undo', title: 'الرجوع إلى مواعيد المنصة؟', body: `<span>تُمحى مواعيدك الخاصة وإجازاتك الثلاث، وتتبع شركتك المنصة: يُفتح ${OPEN}، يُقفل ${CLOSE}، تذكير كل 3 ساعات، وبلا تذكير كل جمعة.</span><span>إن غيّرت المنصة مواعيدها لاحقاً تغيّرت عندك معها.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('الرجوع إلى مواعيد المنصة', { kind: 'outline', phone, full: phone })] }),
};
dialogsBoard('AdmRideDialogs', { row: 'R', title: 'Admin web · Ride confirmation · Confirmations', heading: 'Ride confirmation · every confirmation' }, [
  ['Save the hours', 'One request (set_vote_settings). The body restates all five settings in words, because every student of the company is affected. Then the toast «حُفظت مواعيد التأكيد».', D.save()],
  ['Back to the platform\'s hours', 'Today: one click on «الرجوع لإعداد المنصة» with no question. Says what is erased and what applies instead (the platform\'s real values come with get_vote_settings).', D.reset()],
]);

statesBoard('AdmRideStates', { row: 'R', title: 'Admin web · Ride confirmation · Following the platform, mistakes, saved, loading, error' }, [
  ['Following the platform (first visit)', 'Nothing was ever saved here: the form shows the platform\'s values, says so, and both buttons stay off until something changes.',
    shellDesktop({ size: `width:${FW}px;height:1340px`, active: 'ride-confirmation', title: 'تأكيد الركوب', sub: SUB, body: page({ platform: true }) })],
  ['Mistakes, under the field', 'Same opening and closing time (the only rule the page enforces), and a holiday in the past. Save stays off; nothing is sent.',
    shellDesktop({ size: `width:${FW}px;height:1000px`, active: 'ride-confirmation', title: 'تأكيد الركوب', sub: SUB, body: `<div style="display:grid;grid-template-columns:minmax(0,8fr) minmax(0,4fr);gap:24px;align-items:start">${formGroup(groups(false, { same: true, badDate: true }), footer({}))}<div>${sourceCard(true)}</div></div>` })],
  ['Saved', 'Today a successful save gives no sign at all. A toast at the bottom start corner; the buttons go quiet again.',
    shellDesktop({ size: `width:${FW}px;height:560px`, active: 'ride-confirmation', title: 'تأكيد الركوب', sub: SUB, body: timeline(), overlay: `<div style="position:absolute;inset-inline-start:${264 + 32}px;bottom:24px">${toast({ text: 'حُفظت مواعيد التأكيد. تسري على كل طلاب الشركة.' })}</div>` })],
  ['Loading', 'The form\'s shape. Today a failed load leaves this skeleton for ever.',
    shellDesktop({ size: `width:${FW}px;height:520px`, active: 'ride-confirmation', title: 'تأكيد الركوب', sub: SUB, body: `${skeleton('form', { rows: 3 })}` })],
  ['Error · offline', 'Could not load: plain words and a retry. Offline: the amber bar, the last loaded values readable, both buttons off.',
    shellDesktop({ size: `width:${FW}px;height:560px`, active: 'ride-confirmation', offline: true, title: 'تأكيد الركوب', sub: SUB, body: errorState({ card: true, title: 'تعذّر تحميل مواعيد التأكيد', text: 'لم نستطع جلب المواعيد الحالية. تأكد من اتصالك ثم حاول مرة أخرى. لم يتغيّر شيء عند الطلاب.' }) })],
]);

/* ── Phone ──────────────────────────────────────────────────────── */
const phoneBody = (o = {}) => `${timelinePhone()}${formGroup(groups(true, o), null, true)}${sourceCard(!o.platform, true)}${studentsSee(true)}`;
board('AdmRidePhone', { row: 'R', w: 390, title: 'Admin web · Ride confirmation · Phone', tab: 'لوحة الشركة · تأكيد الركوب · هاتف',
  body: (size) => shellPhone({ size, active: 'ride-confirmation', sub: 'متى يؤكد الطلاب ركوب الغد، ومتى نذكّر من لم يؤكد.', gap: 16, body: phoneBody({ changed: true }),
    bottomBar: `${btn('حفظ مواعيد التأكيد', { phone: true, full: true })}` }) });
board('AdmRideSavePhone', { row: 'R', w: 390, h: 844, title: 'Admin web · Ride confirmation · Save · Phone', tab: 'لوحة الشركة · تأكيد الركوب · حفظ · هاتف',
  body: (size) => shellPhone({ size, active: 'ride-confirmation', sub: 'متى يؤكد الطلاب ركوب الغد، ومتى نذكّر من لم يؤكد.', gap: 16, body: timelinePhone(), overlay: scrim(D.save(true), 'bottom') }) });
board('AdmRideErrorPhone', { row: 'R', w: 390, title: 'Admin web · Ride confirmation · Could not load · Phone', tab: 'لوحة الشركة · تأكيد الركوب · خطأ · هاتف',
  body: (size) => shellPhone({ size, active: 'ride-confirmation', body: errorState({ card: true, phone: true, title: 'تعذّر تحميل مواعيد التأكيد', text: 'لم نستطع جلب المواعيد الحالية. تأكد من اتصالك ثم حاول مرة أخرى. لم يتغيّر شيء عند الطلاب.' }) }) });
