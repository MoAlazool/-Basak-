/** A new line in five steps (saved once), editing a line, the failed save — desktop then phone. */
import {
  board, shellDesktop, shellPhone, stepper, dialog, field, fieldRow, badge, btn, iconBtn, note, money, ico, C, T, R, CARD,
} from './kit.mjs';
import {
  col, row, small, text, hr, pick, box, seg, dialogsBoard, back, ELL, UNI, UNI_ALL, STATIONS, GO, BACK, at, forUni,
} from './lines-kit.mjs';

const STEPS = ['الاسم والجامعات', 'المحطات', 'الرحلات', 'الأسعار', 'المراجعة والحفظ'];
const DONE_SUB = ['الزرقا · جامعتان · 50 مقعداً', '8 محطات', '5 ذهاب · 5 عودة', '4 أسعار'];
const steps = (cur, o = {}) => STEPS.map((label, i) => ({ label, state: o.edit ? (i === cur ? 'current' : 'done') : i < cur ? 'done' : i === cur ? 'current' : 'todo', sub: (o.edit || i < cur) && i < 4 ? (o.subs ?? DONE_SUB)[i] : '' }));
const link = (t) => `<a href="#" style="font-weight:500">${t}</a>`;

/* ── The live summary (desktop, end side) ───────────────────────── */
const sumRow = (k, v, filled = true) => `<div style="display:flex;flex-direction:column;gap:0;padding:10px 0;border-top:1px solid ${C.hair}"><span style="${T.cap};color:${C.ink3}">${k}</span><span style="${T.small};${filled ? `font-weight:500;color:${C.ink}` : `color:${C.ink3}`}">${v}</span></div>`;
const summary = (cur, o = {}) => {
  const f = (i) => o.edit || cur > i || (cur === i && !o.blank);
  return `<aside aria-label="ملخص الخط" style="${CARD};padding:20px 20px 12px;display:flex;flex-direction:column;position:sticky;top:0">
<div style="display:flex;align-items:center;gap:8px;padding-bottom:10px"><h2 style="margin:0;${T.card}">ملخص الخط</h2><span style="flex:1"></span>${badge(o.edit ? 'تعديلات لم تُحفظ' : 'لم يُحفظ بعد', 'warning')}</div>
${sumRow('الاسم', f(0) ? 'الزرقا' : 'لم يُكتب بعد', f(0))}
${sumRow('الجامعات', f(0) ? 'جامعة دمياط · جامعة حورس' : 'لم تُختر بعد', f(0))}
${sumRow('مقاعد الباص', f(0) ? '50 مقعداً' : 'لم تُحدد', f(0))}
${sumRow('المحطات', f(1) ? `${o.stations ?? 8} محطات: من موقف الزرقا إلى مدخل فارسكور` : 'لم تُضف بعد', f(1))}
${sumRow('رحلات الذهاب', f(2) ? `5 رحلات: من ${at(375)} إلى ${at(495)}` : 'لم تُضف بعد', f(2))}
${sumRow('العودة من الجامعة', f(2) ? `5 مواعيد: من ${at(780)} إلى ${at(1050)}` : 'لم تُضف بعد', f(2))}
${sumRow('الأسعار', f(3) ? (o.prices ?? `الأول ${money(3200)} · الفصلان معاً ${money(6000)} · اليومي ${money(45)}`) : 'لم تُكتب بعد', f(3))}
</aside>`;
};

/* ── Step bodies (phone: true stacks) ───────────────────────────── */
const lbl = (t, opt) => `<div style="display:flex;align-items:baseline;gap:8px;${T.label};font-weight:500"><span>${t}</span>${opt ? `<span style="font-weight:400;color:${C.ink3}">اختياري</span>` : ''}</div>`;
const step1 = (phone, o = {}) => col(`
${field({ label: 'اسم الخط', value: o.blank ? '' : 'الزرقا', placeholder: 'مثال: الزرقا', phone, state: o.blank ? 'focus' : undefined, help: 'اسم المنطقة يكفي، حتى 40 حرفاً. لا تكتب فيه اسم الجامعة. إن تركته فارغاً أخذ اسم أول محطة.' })}
<div style="display:flex;flex-direction:column;gap:8px">${lbl('الجامعات التي يوصل إليها الخط')}
<div style="display:grid;grid-template-columns:${phone ? 'minmax(0,1fr)' : 'repeat(2,minmax(0,1fr))'};gap:8px">${UNI_ALL.map((u, i) => pick(u, !o.blank && i < 2, { phone, full: true })).join('')}</div>
${o.blank ? '' : small('اختيرت جامعتان. طلاب الجامعات الأخرى لا يرون هذا الخط.')}
${small(`لا تجد جامعتك في القائمة؟ الجامعات تضيفها إدارة المنصة: اطلبها منها.`, C.ink3)}</div>
${field({ label: 'مقاعد الباص', optional: true, value: o.blank ? '' : '50', placeholder: 'مثال: 50', suffix: 'مقعداً', ltr: true, phone, w: phone ? undefined : 240, help: 'عدد من 1 إلى 500. به نخبرك أنت والمشرف حين يؤكد الركوب أكثر مما يسع الباص.' })}`, 20);

const stationRow = (name, i, o = {}) => `<div style="display:flex;align-items:center;gap:${o.phone ? 4 : 8}px;min-height:${o.phone ? 52 : 48}px">
${o.phone ? '' : `<span aria-hidden="true" title="اسحب لتغيير الترتيب" style="display:flex;color:${C.disabled};cursor:grab">${ico('grip', 18)}</span>`}
<span aria-hidden="true" style="width:24px;height:24px;border-radius:12px;background:${C.sunken};color:${C.ink2};font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center;flex:none">${i + 1}</span>
<span style="flex:1;min-width:0;display:flex;margin-inline-start:${o.phone ? 4 : 0}px">${box(name || `اسم المحطة ${i + 1}`, { h: o.phone ? 48 : 44, ph: !name, focus: o.focus === i })}</span>
${o.subs ? `<span style="width:92px;flex:none;${T.cap};color:${C.ink2};text-align:center">${o.subs[i] ? `${o.subs[i]} طالباً` : 'لا أحد'}</span>` : ''}
${iconBtn('aup', `انقل «${name}» لأعلى`, { extra: `${o.phone ? 'height:48px;' : ''}${i === 0 ? `color:${C.disabled};` : ''}` })}
${iconBtn('adown', `انقل «${name}» لأسفل`, { extra: `${o.phone ? 'height:48px;' : ''}${i === o.n - 1 ? `color:${C.disabled};` : ''}` })}
${iconBtn('trash', `احذف محطة «${name}»`, { extra: o.phone ? 'height:48px;' : '' })}
</div>`;
const step2 = (phone, o = {}) => col(`
${o.subs && !phone ? `<div style="display:flex;align-items:center;gap:8px;${T.cap};color:${C.ink3};padding-inline:50px 136px"><span style="flex:1">المحطة</span><span style="width:92px;text-align:center">مشتركون منها</span></div>` : ''}
<div style="display:flex;flex-direction:column;gap:${phone ? 4 : 4}px">${(o.list ?? STATIONS).map((s, i, a) => stationRow(s, i, { phone, n: a.length, focus: o.focus, subs: phone ? null : o.subs })).join('')}</div>
<div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">${btn('أضف محطة', { kind: 'outline', icon: 'plus', phone, full: phone })}</div>
<div style="display:flex;align-items:center;gap:10px;border-radius:${R.control}px;background:${C.tint};padding:10px 14px;color:${C.teal};${T.small};font-weight:500">${ico('school', 20)}<span>ثم الجامعة: جامعة دمياط · جامعة حورس</span></div>
${small('الترتيب هو ترتيب مرور الباص في الذهاب: الأولى أبعد محطة عن الجامعة. في العودة يتحرك الباص من الجامعة ويعيد كل طالب إلى محطته، فلا تحتاج ترتيباً آخر.')}`, 16);

const tripClosed = (t, o = {}) => `<button type="button" aria-expanded="false" style="display:flex;align-items:center;gap:12px;width:100%;min-height:${o.phone ? 60 : 56}px;padding:8px ${o.phone ? 12 : 16}px;border-radius:${R.control}px;box-shadow:inset 0 0 0 1px ${C.hair};text-align:start;background:${C.surface}"><span style="font-size:16px;font-weight:600;width:${o.phone ? 76 : 88}px;flex:none">${at(t.start)}</span><span style="flex:1;min-width:0;${T.label};color:${C.ink2};${ELL}">${o.phone ? '' : `تصل ${at(t.start + t.gap * 7 + 25)} · `}${8 - t.skip.length} محطات · ${forUni(t.uni)}${t.label && !o.phone ? ` · ${t.label}` : ''}</span><span style="display:flex;color:${C.ink3}">${ico('down', 18)}</span></button>`;
const BAD = { 5: 480, 6: 470 }; // the trip being edited: station 6 earlier than station 5
const stopRow = (s, i, o = {}) => {
  const skip = i === 2; const bad = i === 6;
  const t = BAD[i] ?? 450 + 6 * i;
  return `<div style="display:flex;flex-direction:column;gap:4px;padding:6px 0;${i ? `border-top:1px solid ${C.hair}` : ''}"><div style="display:flex;align-items:center;gap:10px;min-height:${o.phone ? 48 : 40}px">
<span aria-hidden="true" style="width:22px;height:22px;border-radius:11px;background:${C.sunken};color:${C.ink2};font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center;flex:none">${i + 1}</span>
<span style="flex:1;min-width:0;${T.small};${skip ? `color:${C.ink3};` : ''}${ELL}">${s}</span>
${skip ? `<span style="${T.label};color:${C.ink3};white-space:nowrap">لا تقف هنا</span>${btn('تقف هنا', { kind: 'link', sm: true, extra: o.phone ? 'height:48px;' : '' })}` : `${box(at(t), { w: o.phone ? 108 : 116, h: o.phone ? 48 : 40, icon: 'clock', error: bad })}${iconBtn('x', `رحلة ${'7:30'} لا تقف في «${s}»`, { sm: !o.phone, extra: o.phone ? 'width:40px;height:48px;' : '' })}`}
</div>${bad ? `<div role="alert" style="display:flex;align-items:flex-start;gap:6px;${T.label};color:${C.bad};padding-inline-start:32px"><span style="display:flex;padding-top:2px">${ico('alert', 14, 2)}</span><span>موعد «دقهلة» (${at(470)}) قبل محطة «السرو – المزلقان» (${at(480)}). المواعيد يجب أن تكون بترتيب المسار.</span></div>` : ''}</div>`;
};
const tripOpen = (phone) => `<div style="border-radius:${R.inner}px;box-shadow:inset 0 0 0 2px ${C.teal};background:${C.surface};padding:${phone ? 12 : 16}px;display:flex;flex-direction:column;gap:16px">
<div style="display:flex;align-items:center;gap:12px"><span style="font-size:16px;font-weight:600">رحلة ${at(450)}</span>${badge('مشكلة واحدة', 'danger')}<span style="flex:1"></span><span style="display:flex;color:${C.ink3}">${ico('up', 18)}</span></div>
${fieldRow([
    field({ type: 'time', label: 'تتحرك من أول محطة', value: at(450), phone }),
    `<div style="display:flex;flex-direction:column;gap:6px">${lbl('الدقائق بين كل محطة والتالية')}<div style="display:flex;gap:8px">${box('6', { w: 72, h: phone ? 48 : 44 })}${btn('احسب المواعيد', { kind: 'tonal', icon: 'wand', phone, extra: 'flex:1;' })}</div></div>`,
  ], { phone })}
<div style="display:flex;flex-direction:column">${lbl('موعد المرور على كل محطة')}<div style="${T.label};color:${C.ink2};margin-bottom:4px">محسوبة من موعد التحرك، وتستطيع تعديل أي موعد. اضغط × إن كانت الرحلة لا تقف في محطة.</div>
${STATIONS.map((s, i) => stopRow(s, i, { phone })).join('')}</div>
${fieldRow([
    field({ type: 'time', label: 'تصل الجامعة', optional: true, value: at(517), phone }),
    field({ type: 'select', label: 'لطلاب', value: 'كل جامعات الخط', phone }),
  ], { phone })}
${field({ label: 'اسم الرحلة', optional: true, value: 'سريعة', placeholder: 'مثال: أول رحلة صباحية', phone })}
<div style="display:flex;align-items:center;gap:8px;border-top:1px solid ${C.hair};padding-top:12px">${btn('انسخ الرحلة', { kind: 'outline', icon: 'copy', sm: !phone, phone })}<span style="flex:1"></span>${btn('احذف الرحلة', { kind: 'link', icon: 'trash', sm: !phone, phone, extra: `color:${C.bad};` })}</div>
</div>`;
const backRow = (t, phone) => phone
  ? `<div style="border-radius:${R.control}px;box-shadow:inset 0 0 0 1px ${C.hair};padding:10px 12px;display:grid;grid-template-columns:100px minmax(0,1fr) 36px;gap:6px;align-items:center">${box(at(t.start), { h: 48, icon: 'clock' })}${box(forUni(t.uni), { h: 48, icon: 'down' })}${iconBtn('dots', `نسخ أو حذف موعد العودة`, { extra: 'height:48px;' })}</div>`
  : `<div style="display:grid;grid-template-columns:116px minmax(0,1fr) 132px 40px;gap:8px;align-items:center">${box(at(t.start), { h: 44, icon: 'clock' })}${box(`من ${forUni(t.uni)}`, { h: 44, icon: 'down' })}${box(t.start === 780 ? 'عودة الظهر' : 'اسم (اختياري)', { h: 44, ph: t.start !== 780 })}${iconBtn('dots', 'نسخ أو حذف موعد العودة')}</div>`;
const goPart = (phone) => col(`
<div style="display:flex;align-items:baseline;gap:8px"><h3 style="margin:0;${T.card}">رحلات الذهاب</h3><span style="${T.label};color:${C.ink2}">5 رحلات</span></div>
${small('لكل رحلة موعد تحركها من أول محطة، ومنه نحسب موعد كل محطة. الطالب يختار رحلة ويرى موعد محطته.')}
${GO.slice(0, 3).map((t) => tripClosed(t, { phone })).join('')}
${tripOpen(phone)}
${tripClosed(GO[4], { phone })}
<div style="display:flex">${btn('أضف رحلة ذهاب', { kind: 'outline', icon: 'plus', phone, full: phone })}</div>`, 8);
const backPart = (phone) => col(`
<div style="display:flex;align-items:baseline;gap:8px"><h3 style="margin:0;${T.card}">العودة من الجامعة</h3><span style="${T.label};color:${C.ink2}">5 مواعيد</span></div>
${small('للعودة موعد واحد: متى يتحرك الباص من الجامعة. لا مواعيد للمحطات، فالباص يعيد كل طالب إلى محطته.')}
${BACK.map((t) => backRow(t, phone)).join('')}
<div style="display:flex">${btn('أضف موعد عودة', { kind: 'outline', icon: 'plus', phone, full: phone })}</div>`, 8);
const step3 = (phone, part) => (phone
  ? col(`${seg([{ label: 'الذهاب', count: 5, on: part !== 'back' }, { label: 'العودة', count: 5, on: part === 'back' }], { full: true, phone: true })}${part === 'back' ? backPart(true) : goPart(true)}`, 16)
  : col(`${goPart(false)}${hr}${backPart(false)}`, 20));

const priceRow = (name, o = {}) => `<div style="display:grid;grid-template-columns:${o.phone ? 'minmax(0,1fr)' : 'minmax(0,1fr) 200px'};gap:${o.phone ? 8 : 16}px;align-items:start;padding:14px 0;${o.first ? '' : `border-top:1px solid ${C.hair}`}">
<label style="display:flex;align-items:center;gap:12px;min-height:44px"><span role="switch" aria-checked="${!!o.on}" style="width:44px;height:24px;border-radius:12px;background:${o.locked ? C.sunken : o.on ? C.teal : C.disabled};display:flex;align-items:center;padding:2px;justify-content:${o.on ? 'flex-end' : 'flex-start'};flex:none"><span style="width:20px;height:20px;border-radius:10px;background:#FFFFFF;box-shadow:0 1px 2px rgba(23,56,74,.25)"></span></span><span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="${T.small};font-weight:500;${o.locked ? `color:${C.ink3}` : ''}">${name}</span><span style="${T.label};color:${C.ink2}">${o.help}</span></span></label>
${field({ type: 'money', value: o.value ?? '', placeholder: o.on ? 'اكتب السعر' : '', state: o.locked || !o.on ? 'disabled' : o.focus ? 'focus' : undefined, error: o.error, phone: o.phone })}
</div>`;
const step4 = (phone, o = {}) => col(`
<div>
${priceRow('الفصل الأول', { first: true, on: true, value: '3,200', help: 'يُباع على هذا الخط', phone })}
${priceRow('الفصل الثاني', { on: true, focus: !o.review, error: o.review ? 'اكتب سعراً أكبر من صفر، أو أوقف بيع الفصل الثاني على هذا الخط.' : undefined, help: 'يُباع على هذا الخط', phone })}
${priceRow('الفصلان معاً', { on: true, value: '6,000', help: 'يُباع على هذا الخط', phone })}
${priceRow('الفصل الصيفي', { on: false, locked: true, help: `شركتك لا تبيع الفصل الصيفي الآن. تفتحه من ${link('مواعيد الاشتراك')}.`, phone })}
${priceRow('اليومي (نقداً في الباص)', { on: true, value: '45', help: 'يدفعه الطالب للمشرف عند الركوب', phone })}
</div>
${note({ tone: 'teal', title: 'السعر هنا، وموعد البيع في «مواعيد الاشتراك»', text: 'يرى الطالب الاشتراك حين يكون مفتوحاً في المكانين: مفتاحه هنا على هذا الخط، وموعد بيعه عند الشركة.' })}
${small('لا نكتب عنك أي سعر. الاشتراك الذي تتركه مفتوحاً بلا سعر يمنع الحفظ حتى تكتبه أو توقفه.')}`, 16);

const checkRow = (ok, title, sub, o = {}) => `<div style="display:flex;align-items:flex-start;gap:12px;padding:14px 0;${o.first ? '' : `border-top:1px solid ${C.hair}`}"><span aria-hidden="true" style="width:28px;height:28px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;${ok ? `background:${C.okBg};color:${C.ok}` : `background:${C.badBg};color:${C.bad}`}">${ico(ok ? 'check' : 'alert', 16, 2.25)}</span><div style="flex:1;min-width:0"><div style="${T.small};font-weight:600">${title}</div><div style="${T.label};color:${ok ? C.ink2 : C.bad}">${sub}</div></div>${btn(ok ? 'عدّل' : 'أكمل', { kind: ok ? 'link' : 'tonal', sm: true, extra: o.phone ? 'height:44px;' : '' })}</div>`;
const step5 = (phone, o = {}) => col(`
${o.error ? note({ tone: 'danger', title: 'لم يكتمل حفظ الخط', text: 'حُفظت المحطات والرحلات، ولم نستطع حفظ الأسعار وعدد المقاعد. الخط لن يظهر للطلاب حتى تكتمل. بياناتك كلها كما كتبتها هنا: حاول مرة أخرى، ولن يتكرر الخط.', action: phone ? '' : btn('إعادة المحاولة', { kind: 'primary', sm: true, icon: 'refresh' }) }) : o.ok ? note({ tone: 'success', title: 'كل شيء مكتمل', text: 'راجع الملخص ثم احفظ. لا يُحفظ شيء قبل أن تضغط «حفظ الخط».' }) : note({ tone: 'warning', title: 'بقي أمران قبل الحفظ', text: 'أكملهما ثم احفظ. كل ما كتبته باقٍ كما هو.' })}
<div>
${checkRow(true, 'الاسم والجامعات', 'الزرقا · جامعة دمياط وجامعة حورس · الباص 50 مقعداً', { first: true, phone })}
${checkRow(true, 'المحطات', '8 محطات: من موقف الزرقا إلى مدخل فارسكور', { phone })}
${o.ok || o.error ? checkRow(true, 'الرحلات', `5 رحلات ذهاب من ${at(375)} إلى ${at(495)} · 5 مواعيد عودة من ${at(780)} إلى ${at(1050)}`, { phone }) : checkRow(false, 'الرحلات', `رحلة ${at(450)}: موعد محطة «دقهلة» قبل المحطة التي قبلها.`, { phone })}
${o.ok || o.error ? checkRow(true, 'الأسعار', `الفصل الأول ${money(3200)} · الثاني ${money(3200)} · الفصلان معاً ${money(6000)} · اليومي ${money(45)}`, { phone }) : checkRow(false, 'الأسعار', 'الفصل الثاني مفتوح للبيع وبلا سعر.', { phone })}
</div>
<div style="border-radius:${R.inner}px;background:${C.ground};padding:14px 16px;display:flex;flex-direction:column;gap:6px"><div style="${T.small};font-weight:600">بعد الحفظ</div>
<div style="${T.label};color:${C.ink2}">• يظهر الخط في التطبيق لطلاب جامعة دمياط وجامعة حورس، بالاشتراكات المعروضة للبيع الآن.</div>
<div style="${T.label};color:${C.ink2}">• ليس له مشرف بعد: عيّنه من صفحة «المشرفون» ليسجّل صعود الطلاب.</div></div>`, 16);

const HEAD = [
  ['الاسم والجامعات', 'ما اسم الخط، وإلى أي جامعات يوصل؟'],
  ['المحطات', 'من أين يركب الطلاب؟ اكتب المحطات بترتيب مرور الباص.'],
  ['الرحلات', 'متى يتحرك الباص في الذهاب، ومتى يعود من الجامعة؟'],
  ['الأسعار', 'اكتب سعر كل اشتراك تبيعه على هذا الخط.'],
  ['المراجعة والحفظ', 'نظرة أخيرة. هنا فقط يُحفظ الخط.'],
];
const NEXT = ['التالي: المحطات', 'التالي: الرحلات', 'التالي: الأسعار', 'التالي: المراجعة', 'حفظ الخط'];
const stepCard = (cur, inner, o = {}) => `<section style="${CARD};display:flex;flex-direction:column;min-width:0">
<div style="padding:20px 24px 16px;border-bottom:1px solid ${C.hair}"><div style="${T.cap};color:${C.ink3}">الخطوة ${cur + 1} من 5</div><h2 style="margin:0;${T.section}">${HEAD[cur][0]}</h2><p style="margin:2px 0 0;${T.small};color:${C.ink2}">${HEAD[cur][1]}</p></div>
<div style="padding:20px 24px;display:flex;flex-direction:column;gap:16px">${inner}</div>
<div style="display:flex;align-items:center;gap:8px;padding:12px 24px;border-top:1px solid ${C.hair}">${cur ? btn('السابق', { kind: 'secondary', icon: 'arrowBack' }) : ''}<span style="flex:1"></span>${o.footNote ? `<span style="${T.label};color:${C.ink2}">${o.footNote}</span>` : ''}${btn(o.next ?? NEXT[cur], { state: o.nextState, ...(cur === 4 || o.edit ? { icon: 'check' } : { iconEnd: 'arrowFwd' }) })}</div>
</section>`;
const wizard = (size, cur, inner, o = {}) => shellDesktop({ size, active: 'lines', breadcrumb: ['الخطوط', o.edit ? 'تعديل خط الزرقا' : 'خط جديد'], title: o.edit ? 'تعديل خط الزرقا' : 'خط جديد', back: 'الخطوط',
  sub: o.edit ? 'انتقل بين الخطوات كما تشاء. لا يتغيّر شيء عند الطلاب حتى تضغط «حفظ التعديلات».' : 'خمس خطوات. لا يُحفظ شيء ولا يراه الطلاب حتى تضغط «حفظ الخط» في آخر خطوة.',
  actions: btn('إغلاق', { kind: 'outline', icon: 'x' }), overlay: o.overlay, body: `${o.top ?? ''}
<div style="display:grid;grid-template-columns:208px minmax(0,1fr) 292px;gap:24px;align-items:start">
<nav aria-label="خطوات الخط" style="${CARD};padding:20px 16px">${stepper({ vertical: true, steps: steps(cur, o) })}</nav>
${stepCard(cur, inner, o)}
${summary(cur, o)}
</div>` });

const W = (n, title, cur, inner, o = {}) => board(n, { row: 'W', w: 1440, title: `Admin web · ${title} · Desktop`, tab: `لوحة الشركة · الخطوط · ${o.edit ? 'تعديل خط' : 'خط جديد'} · ${STEPS[cur]}`, min: o.min,
  body: (size) => wizard(size, cur, inner, o) });
W('AdmLineNew1', 'New line · 1 Name and universities', 0, step1(false));
W('AdmLineNew2', 'New line · 2 Stations', 1, step2(false, { focus: 4 }));
W('AdmLineNew3', 'New line · 3 Trips', 2, step3(false), { footNote: 'في رحلة واحدة مشكلة. تستطيع المتابعة وإصلاحها قبل الحفظ.' });
W('AdmLineNew4', 'New line · 4 Prices', 3, step4(false), { prices: `الأول ${money(3200)} · الفصلان معاً ${money(6000)} · اليومي ${money(45)} · الثاني بلا سعر` });
W('AdmLineNew5', 'New line · 5 Review, things missing', 4, step5(false), { nextState: 'disabled', footNote: 'أكمل الأمرين ليعمل زر الحفظ' });
W('AdmLineSaveError', 'New line · The save did not complete', 4, step5(false, { error: true }), { next: 'إعادة المحاولة', prices: `الأول ${money(3200)} · الثاني ${money(3200)} · الفصلان معاً ${money(6000)} · اليومي ${money(45)}` });

/* Editing a line students already use: the stations step. */
const ST_SUBS = [31, 22, 9, 14, 12, 18, 0, 18];
W('AdmLineEdit', 'Edit a line with subscribers · Stations', 1, step2(false, { subs: ST_SUBS }), { edit: true, next: 'حفظ التعديلات', footNote: 'تعديلان لم يُحفظا',
  top: note({ tone: 'warning', title: 'للخط 124 مشتركاً: ما تغيّره يصلهم', text: 'تغيير اسم محطة أو موعدها يظهر عند طلابها فور الحفظ، ويتغيّر موعد الركوب في اشتراكاتهم. محطة أو رحلة عليها طلاب لا تُحذف: تتوقف وتختفي من الخط، ويبقى طلابها عليها حتى تنقلهم. الاسم، الجامعات، المقاعد، الأسعار والمحطات والرحلات الخالية تتغيّر بحرية.' }) });

/* ── Confirmations of the steps ─────────────────────────────────── */
const E = {
  leave: (phone) => dialog({ phone, tone: 'warning', icon: 'alert', title: 'إغلاق دون حفظ الخط؟', body: '<span>كتبت الاسم، 8 محطات و10 رحلات، ولم يُحفظ شيء منها بعد. إن أغلقت الآن ضاع ما كتبته.</span>',
    actions: [back('رجوع إلى الخط', { phone, full: phone }), btn('إغلاق دون حفظ', { kind: 'dangerQuiet', phone, full: phone })] }),
  station: (phone) => dialog({ phone, tone: 'danger', icon: 'trash', title: 'إزالة محطة «شرباص»؟', body: `<span><b style="color:${C.ink}">14 طالباً</b> اشتراكهم من هذه المحطة. لن تُحذف: تختفي من الخط ولا يختارها طالب جديد، وتسقط مواعيدها من كل الرحلات.</span><span>هؤلاء الطلاب يبقون مسجلين عليها بلا موعد مرور. أبلغهم أين يركبون قبل أن تحفظ.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('إزالة المحطة', { kind: 'danger', phone, full: phone })] }),
  trip: (phone) => dialog({ phone, tone: 'danger', icon: 'trash', title: 'حذف رحلة 7:30 ص؟', body: `<span><b style="color:${C.ink}">12 طالباً</b> مشتركون على هذه الرحلة. لن تُحذف: تتوقف ولا تظهر لطالب جديد.</span><span>هؤلاء الطلاب يبقون عليها في اشتراكاتهم. أبلغهم بالرحلة البديلة قبل أن تحفظ.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('حذف الرحلة', { kind: 'danger', phone, full: phone })] }),
  save: (phone) => dialog({ phone, tone: 'teal', icon: 'check', title: 'حفظ تعديلات خط الزرقا؟', body: `<span>تغيّر موعد رحلة ${at(420)} على 8 محطات: <b style="color:${C.ink}">38 طالباً</b> يتغيّر موعد ركوبهم في التطبيق فور الحفظ.</span><span>أُزيلت محطة «شرباص» وعليها 14 طالباً.</span><span>إن أردت إبلاغهم فأرسل لهم إشعاراً من صفحة «الإشعارات» بعد الحفظ.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('حفظ التعديلات', { phone, full: phone })] }),
};
dialogsBoard('AdmLineStepDialogs', { row: 'W', title: 'Admin web · New line and editing · Confirmations', heading: 'New line and editing · every confirmation',
  intro: 'What the steps ask before something is lost or before students are affected. Today the editor closes with no warning, and removing a station or a trip that students use says nothing.' }, [
  ['Close before saving', 'Closing (×, «إغلاق», the back link, the browser\'s back) asks first when anything was typed. Says what would be lost.', E.leave()],
  ['Remove a station students board from', 'save_line does not delete a used station: it retires it (is_active = false) and its stop times go. Needs the count of subscribers per station.', E.station()],
  ['Remove a trip students ride', 'save_line deactivates a trip that subscriptions point to instead of deleting it. Needs the count of subscribers per trip.', E.trip()],
  ['Save changes to a line in use', 'Only when the edit reaches students: changed stop times are copied into their subscriptions by save_line. Lists the real effects.', E.save()],
]);

/* ── Phone: one step per page ───────────────────────────────────── */
const navBar = (cur, o = {}) => `<div style="display:flex;gap:8px">${cur ? btn('السابق', { kind: 'secondary', phone: true }) : ''}${btn(o.next ?? NEXT[cur], { phone: true, state: o.nextState, extra: 'flex:1;', ...(cur === 4 ? { icon: 'check' } : { iconEnd: 'arrowFwd' }) })}</div>`;
const P = (n, title, cur, inner, o = {}) => board(n, { row: 'W', w: 390, title: `Admin web · ${title} · Phone`, tab: `لوحة الشركة · خط جديد · ${STEPS[cur]} · هاتف`, min: o.min, h: o.h,
  body: (size) => shellPhone({ size, active: 'lines', title: 'خط جديد', back: 'الخطوط', gap: 16, overlay: o.overlay, body: `
${stepper({ phone: true, steps: steps(cur) })}
<div><h2 style="margin:0;${T.card}">${HEAD[cur][1]}</h2></div>
<section style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px">${inner}</section>
${o.after ?? ''}`, bottomBar: navBar(cur, o) }) });
P('AdmLineNew1Phone', 'New line · 1 Name and universities', 0, step1(true));
P('AdmLineNew2Phone', 'New line · 2 Stations', 1, step2(true, { focus: 4 }));
P('AdmLineNew3Phone', 'New line · 3 Trips, going', 2, step3(true));
P('AdmLineNew3BackPhone', 'New line · 3 Trips, return', 2, step3(true, 'back'));
P('AdmLineNew4Phone', 'New line · 4 Prices', 3, step4(true));
P('AdmLineNew5Phone', 'New line · 5 Review, things missing', 4, step5(true), { nextState: 'disabled' });
P('AdmLineSaveErrorPhone', 'New line · The save did not complete', 4, step5(true, { error: true }), { next: 'إعادة المحاولة' });
P('AdmLineLeavePhone', 'New line · Close before saving', 1, step2(true, { list: STATIONS.slice(0, 5) }), { h: 844, overlay: `<div style="position:absolute;inset:0;background:rgba(23,56,74,.45);display:flex;align-items:flex-end;z-index:10">${E.leave(true)}</div>` });
