/** وسائل الدفع — /c/:companyId/payment-methods */
import {
  board, shellDesktop, shellPhone, dataTable, recordList, recordCard, sidePanel, dialog, scrim, field, fieldRow, btn, iconBtn, state, note,
  emptyState, errorState, skeleton, toast, money, ltr, ico, C, T, R, CARD, SHADOW,
} from './kit.mjs';
import { statesBoard, mini, rowActions, dots, menu, labelled, inputBox, counter } from './m-common.mjs';

const ROW = 'E';
const SUB = 'الحسابات التي يحوّل عليها الطلاب ثمن الاشتراك. الطالب يحوّل ثم يرفع صورة التحويل، وأنت تراجعها في «الإيصالات».';
const TYPE = { instapay: ['إنستاباي', 'card'], wallet: ['محفظة فودافون كاش', 'smartphone'], bank: ['حساب بنكي', 'building'] };
const M = [
  { t: 'instapay', name: 'إنستاباي النورس', acc: 'elnawras@instapay', holder: 'أحمد سعيد النورس', on: true, note: 'حوّل المبلغ كاملاً، ثم ارفع صورة التحويل من التطبيق.' },
  { t: 'wallet', name: 'فودافون كاش', acc: '010 2345 6789', holder: 'أحمد سعيد النورس', on: true, note: 'اكتب اسمك في خانة الملاحظات عند التحويل.' },
  { t: 'bank', name: 'البنك الأهلي المصري', acc: '1234 5678 9012 3456', iban: 'EG38 0003 0001 2345 6789 0123 4567', bank: 'البنك الأهلي المصري · فرع دمياط', holder: 'شركة النورس للنقل', on: true, note: 'التحويل البنكي يصل خلال يوم عمل. ارفع صورة إيصال البنك.' },
  { t: 'wallet', name: 'فودافون كاش (المكتب)', acc: '010 9876 5432', holder: 'محمود السيد عبد الغني', on: false },
  { t: 'instapay', name: 'إنستاباي (قديم)', acc: 'nawras.bus@instapay', holder: 'أحمد سعيد النورس', on: false },
];
const typeTag = (m) => `<span style="display:inline-flex;align-items:center;gap:6px;color:${C.ink3};font-size:12px;line-height:18px">${ico(TYPE[m.t][1], 13, 2)}${TYPE[m.t][0]}</span>`;
const st = (m) => state(m.on ? 'on' : 'off', m.on ? 'تظهر للطلاب' : 'متوقفة');
const order = (i, n) => `<div style="display:flex;align-items:center;gap:2px"><span style="width:20px;font-weight:600;color:${C.ink2}">${i + 1}</span>${iconBtn('aup', 'تقديم', { sm: true, color: i === 0 ? C.disabled : C.ink2 })}${iconBtn('adown', 'تأخير', { sm: true, color: i === n - 1 ? C.disabled : C.ink2 })}</div>`;
const table = (list, o = {}) => dataTable({
  caption: 'وسائل الدفع',
  tablet: o.compact,
  toolbar: { count: o.count ?? `${list.length} وسائل · ${list.filter((m) => m.on).length} تظهر للطلاب بهذا الترتيب` },
  columns: [{ label: 'الترتيب', w: 124 }, { label: 'الوسيلة' }, { label: 'الحساب الذي يحوّل عليه الطالب', w: 250 }, { label: 'صاحب الحساب', w: 220, hideTablet: true }, { label: 'الحالة', w: 150 }, { label: '', w: 136, align: 'end' }],
  rows: list.map((m, i) => ({ state: o.open === i ? 'open' : undefined, muted: !m.on, cells: [order(i, list.length), `<div style="min-width:0"><div style="font-weight:600;color:${C.ink}">${m.name}</div>${typeTag(m)}</div>`, ltr(m.acc, 'font-weight:500'), m.holder, st(m), rowActions(btn('تعديل', { kind: 'outline', sm: true }), dots())] })),
});
const head = { active: 'payment-methods', title: 'وسائل الدفع', sub: SUB, actions: btn('إضافة وسيلة دفع', { icon: 'plus' }) };
const orderNote = note({ tone: 'teal', title: 'الترتيب هنا هو ترتيبها عند الطالب', text: 'ضع في الأعلى الوسيلة التي تفضّل أن يحوّل عليها الطلاب. الوسيلة المتوقفة تبقى محفوظة ولا يراها أحد.' });

board('AdmPay', { row: ROW, w: 1440, title: 'Admin web · Payment methods · Desktop (the row menu open)', tab: 'لوحة الشركة · وسائل الدفع',
  body: (size) => shellDesktop({ size, ...head, body: `<div style="position:relative">${table(M)}<div style="position:absolute;inset-inline-end:16px;top:214px;z-index:2">${menu([['power', 'إيقاف الوسيلة'], ['aup', 'اجعلها الأولى'], ['trash', 'حذف الوسيلة', 'danger']])}</div></div>
${orderNote}` }) });

/* ── What the student sees ──────────────────────────────────────── */
const payPreview = (list, sel = 0, o = {}) => `<div role="img" aria-label="معاينة صفحة الدفع في تطبيق الطالب" style="width:${o.w ?? 320}px;max-width:100%;border-radius:20px;background:${C.ground};box-shadow:0 0 0 1px ${C.hair}, ${SHADOW.card};padding:14px;display:flex;flex-direction:column;gap:10px;align-self:center">
<div style="display:flex;align-items:baseline;gap:8px"><span style="flex:1;font-size:15px;line-height:22px;font-weight:600">ادفع اشتراكك</span><span style="font-size:15px;font-weight:600">${money(4500)}</span></div>
<span style="${T.cap};color:${C.ink2}">اختر وسيلة، حوّل المبلغ، ثم ارفع صورة التحويل.</span>
${list.filter((m) => m.on).map((m, i) => i === sel ? `<div style="background:${C.surface};border-radius:${R.inner}px;box-shadow:inset 0 0 0 2px ${C.teal};padding:12px;display:flex;flex-direction:column;gap:8px">
<div style="display:flex;align-items:center;gap:8px"><span style="display:flex;color:${C.teal}">${ico(TYPE[m.t][1], 18)}</span><span style="flex:1;min-width:0;font-size:14px;line-height:20px;font-weight:600;overflow-wrap:anywhere">${m.name || 'اسم الوسيلة'}</span></div>
<div style="display:flex;align-items:center;gap:8px;background:${C.tint};border-radius:${R.control}px;padding:8px 10px"><span style="flex:1;min-width:0;font-size:14px;line-height:22px;font-weight:600;color:${m.acc ? C.ink : C.disabled};overflow-wrap:anywhere;text-align:right" dir="ltr">${m.acc || (m.t === 'wallet' ? '01x xxxx xxxx' : 'name@instapay')}</span><span style="display:inline-flex;align-items:center;gap:4px;font-size:12px;font-weight:600;color:${C.teal}">${ico('copy', 14, 2)}نسخ</span></div>
${m.iban ? `<div style="${T.cap};color:${C.ink2}">${m.bank}<br>IBAN <span dir="ltr" style="unicode-bidi:isolate">${m.iban}</span></div>` : ''}
${m.holder ? `<div style="${T.cap};color:${C.ink2}">باسم: <b style="font-weight:600;color:${C.ink}">${m.holder}</b></div>` : ''}
${m.note ? `<div style="${T.cap};color:${C.ink2};border-top:1px solid ${C.hair};padding-top:8px">${m.note}</div>` : ''}
</div>` : `<div style="background:${C.surface};border-radius:${R.inner}px;box-shadow:inset 0 0 0 1px ${C.hair};padding:10px 12px;display:flex;align-items:center;gap:8px"><span style="display:flex;color:${C.ink3}">${ico(TYPE[m.t][1], 18)}</span><span style="flex:1;min-width:0;font-size:13px;line-height:20px;font-weight:500">${m.name}</span><span style="display:flex;color:${C.ink3}">${ico('down', 16)}</span></div>`).join('')}
<div style="height:40px;border-radius:${R.control}px;background:${C.sunken};color:${C.ink3};display:flex;align-items:center;justify-content:center;gap:6px;font-size:13px;font-weight:600">${ico('image', 16)}ارفع صورة التحويل</div>
</div>`;
const previewCol = (list, sel, o = {}) => `<div style="display:flex;flex-direction:column;gap:12px;${o.phone ? '' : `background:${C.sunken};border-radius:${R.card}px;padding:20px;align-self:stretch;`}"><div><div style="${T.small};font-weight:600">هكذا يراها الطالب</div><div style="${T.label};color:${C.ink2}">صفحة الدفع في التطبيق، وتتغيّر وأنت تكتب.</div></div>${payPreview(list, sel, o)}${o.foot ?? ''}</div>`;

const typeRadio = (on, phone) => field({ type: 'radio', label: 'نوع الوسيلة', phone, cols: 3, options: Object.entries(TYPE).map(([k, v]) => ({ label: v[0], on: k === on })) });
const bankForm = (phone) => `${typeRadio('bank', phone)}
${fieldRow([field({ label: 'الاسم الظاهر للطالب', value: 'البنك الأهلي المصري', phone }), field({ label: 'اسم صاحب الحساب', value: 'شركة النورس للنقل', phone })], { phone })}
${fieldRow([field({ label: 'اسم البنك والفرع', value: 'البنك الأهلي المصري · فرع دمياط', phone }), field({ label: 'رقم الحساب', value: '1234 5678 9012 3456', ltr: true, state: 'focus', phone })], { phone })}
${field({ label: 'IBAN', optional: true, value: 'EG38 0003 0001 2345 6789 0123 4567', ltr: true, phone })}
${labelled('تعليمات للطالب', counter(58, 300), inputBox('التحويل البنكي يصل خلال يوم عمل. ارفع صورة إيصال البنك.', { rows: 3 }), { optional: true, help: 'تظهر تحت رقم الحساب. مثال: حوّل المبلغ كاملاً ثم ارفع صورة التحويل.' })}
${field({ type: 'toggle', label: 'تظهر للطلاب', help: 'عند إيقافها تبقى محفوظة هنا ولا يراها أحد في التطبيق.', on: true, phone })}`;

board('AdmPayPanel', { row: ROW, w: 1440, h: 1000, title: 'Admin web · Payment methods · Edit panel with the live student preview', tab: 'لوحة الشركة · وسائل الدفع · تعديل',
  body: (size) => shellDesktop({ size, ...head, body: `${table(M, { open: 2 })}${orderNote}`,
    overlay: scrim(sidePanel({ w: 920, title: 'تعديل وسيلة الدفع', sub: 'البنك الأهلي المصري · حساب بنكي', meta: st(M[2]),
      body: `<div style="display:grid;grid-template-columns:minmax(0,1fr) 360px;gap:24px;flex:1;min-height:0"><div style="display:flex;flex-direction:column;gap:16px;min-width:0">${bankForm()}</div>${previewCol([M[2], M[0], M[1]], 0, { foot: `<span style="${T.cap};color:${C.ink2};text-align:center">الطالب يضغط «نسخ» فينسخ رقم الحساب كما كتبته.</span>` })}</div>`,
      footer: `${btn('حذف الوسيلة', { kind: 'dangerQuiet', icon: 'trash' })}<span style="flex:1"></span>${btn('رجوع', { kind: 'secondary' })}${btn('حفظ وسيلة الدفع')}` }), 'end') }) });

/* ── Confirmations ──────────────────────────────────────────────── */
const stopDialog = (phone) => dialog({ phone, icon: 'power', tone: 'warning', title: 'إيقاف «فودافون كاش»؟',
  body: '<span>تختفي من صفحة الدفع عند الطلاب فوراً، وتبقى محفوظة هنا لتشغّلها متى أردت.</span><span>تبقى وسيلتان تعملان: إنستاباي النورس والبنك الأهلي المصري. الإيصالات التي رُفعت عليها من قبل لا تتأثر.</span>',
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('إيقاف الوسيلة', { phone, full: phone })] });
const stopLastDialog = (phone) => dialog({ phone, icon: 'alert', tone: 'danger', title: 'إيقاف آخر وسيلة دفع تعمل؟',
  body: `<span>«إنستاباي النورس» هي الوسيلة الوحيدة التي يراها الطلاب الآن.</span>${note({ tone: 'danger', title: 'لن يستطيع أي طالب أن يدفع', text: 'تظهر له صفحة الدفع بلا حساب يحوّل عليه، حتى تشغّل وسيلة أخرى.' })}`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('إيقاف الوسيلة', { kind: 'danger', phone, full: phone })] });
const deleteDialog = (phone) => dialog({ phone, icon: 'trash', tone: 'danger', title: 'حذف «إنستاباي (قديم)»؟',
  body: '<span>تُحذف الوسيلة نهائياً ولا يمكن استرجاعها. الإيصالات السابقة تبقى محفوظة، لكن بلا اسم الوسيلة التي دُفعت بها.</span><span>هي متوقفة الآن ولا يراها الطلاب، فلا حاجة إلى الحذف إن أردت إخفاءها فقط.</span>',
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('حذف الوسيلة', { kind: 'danger', phone, full: phone })] });
board('AdmPayConfirm', { row: ROW, w: 1440, h: 1040, title: 'Admin web · Payment methods · Stop, stop-the-last-one and delete confirmations', tab: 'لوحة الشركة · وسائل الدفع · تأكيد',
  body: (size) => shellDesktop({ size, ...head, body: `${table(M)}${orderNote}`,
    overlay: scrim(`<div style="display:flex;flex-direction:column;gap:24px;align-items:center">${stopDialog()}${stopLastDialog()}${deleteDialog()}</div>`) }) });

/* ── States ─────────────────────────────────────────────────────── */
const OFF = M.slice(3).concat([{ ...M[1], on: false }]);
const noPay = (text, action = '') => note({ tone: 'danger', title: 'الطلاب لا يستطيعون الدفع الآن', text, action });
statesBoard('AdmPayStates', { row: ROW, title: 'Admin web · Payment methods · States', frames: [
  ['Empty · first use', 'Says what the page is for, what happens without it, and offers the first action. The same warning is the «أضف وسيلة دفع» step of the setup list on «اليوم».',
    mini(600, { ...head, actions: '', body: `${noPay('لا توجد وسيلة دفع. يرى الطالب الخطوط والأسعار، لكن لا يجد حساباً يحوّل عليه.')}<div style="${CARD}">${emptyState({ icon: 'card', title: 'أضف أول وسيلة دفع', text: 'حساب إنستاباي، أو محفظة فودافون كاش، أو حساب بنكي. يظهر للطالب في صفحة الدفع ليحوّل عليه ثمن الاشتراك.', action: btn('إضافة وسيلة دفع', { icon: 'plus' }) })}</div>` })],
  ['None active', 'Methods exist but all are stopped: the red note stays at the top of the page with the one action that fixes it.',
    mini(620, { ...head, body: `${noPay('كل وسائل الدفع متوقفة. شغّل واحدة على الأقل ليعود الدفع.', btn('شغّل «فودافون كاش»', { kind: 'danger', sm: true }))}${table(OFF, { compact: true, count: '3 وسائل · لا واحدة تظهر للطلاب' })}` })],
  ['One method', 'A single method: the order buttons are off, and stopping it leads to the «آخر وسيلة» confirmation.',
    mini(460, { ...head, body: table(M.slice(0, 1), { compact: true, count: 'وسيلة واحدة · تظهر للطلاب' }) })],
  ['Loading', 'Skeleton rows in the shape of the table.', mini(520, { ...head, body: skeleton('table', { rows: 4, cols: 5 }) })],
  ['Error · and a failed re-order', 'Loading failed: plain Arabic and a retry. A re-order that failed puts the rows back and says so in a toast.',
    mini(600, { ...head, body: `${errorState({ card: true, title: 'تعذّر تحميل وسائل الدفع', text: 'لم نستطع جلب الوسائل. تأكد من اتصالك ثم حاول مرة أخرى.' })}<div style="display:flex">${toast({ tone: 'danger', text: 'لم يتغيّر الترتيب. أعدنا الوسائل إلى ترتيبها المحفوظ.', action: 'حاول مرة أخرى', w: 500 })}</div>` })],
] });

/* ── Phone ──────────────────────────────────────────────────────── */
const cardM = (m, i, n) => recordCard({ title: m.name, sub: typeTag(m), end: st(m), fields: [['الحساب', ltr(m.acc, 'font-weight:500')], ['صاحب الحساب', m.holder]],
  actions: `${iconBtn('aup', 'تقديم', { phone: true, bg: C.ground, color: i === 0 ? C.disabled : C.ink2 })}${iconBtn('adown', 'تأخير', { phone: true, bg: C.ground, color: i === n - 1 ? C.disabled : C.ink2 })}<span style="flex:1"></span>${btn(m.on ? 'إيقاف' : 'تشغيل', { kind: 'outline', phone: true })}${btn('تعديل', { kind: 'secondary', phone: true })}` });
board('AdmPayPhone', { row: ROW, w: 390, title: 'Admin web · Payment methods · Phone', tab: 'لوحة الشركة · وسائل الدفع · هاتف',
  body: (size) => shellPhone({ size, active: 'payment-methods', sub: SUB, body: recordList({ toolbar: { count: '5 وسائل · 3 تظهر للطلاب بهذا الترتيب' }, cards: M.map((m, i) => cardM(m, i, M.length)) }), bottomBar: btn('إضافة وسيلة دفع', { icon: 'plus', phone: true, full: true }) }) });

const NEW = { t: 'wallet', name: 'فودافون كاش (الفرع)', acc: '010 2345 67', holder: 'سامح فتحي البنا', on: true, note: '' };
board('AdmPayEditPhone', { row: ROW, w: 390, title: 'Admin web · Payment methods · New method (a number error) · Phone', tab: 'لوحة الشركة · وسيلة دفع جديدة · هاتف',
  body: (size) => shellPhone({ size, active: 'payment-methods', title: 'وسيلة دفع جديدة', back: 'وسائل الدفع', body: `<section style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px">
${typeRadio('wallet', true)}
${field({ label: 'الاسم الظاهر للطالب', value: NEW.name, phone: true })}
${field({ type: 'tel', label: 'رقم المحفظة', value: NEW.acc, phone: true, error: 'الرقم ناقص. اكتب 11 رقماً تبدأ بـ 01.' })}
${field({ label: 'اسم صاحب المحفظة', value: NEW.holder, phone: true, help: 'كما يظهر للطالب عند التحويل.' })}
${labelled('تعليمات للطالب', counter(0, 300), inputBox('', { rows: 3, placeholder: 'مثال: حوّل المبلغ كاملاً ثم ارفع صورة التحويل.' }), { optional: true })}
${field({ type: 'toggle', label: 'تظهر للطلاب', help: 'تظهر فور الحفظ في صفحة الدفع.', on: true, phone: true })}
</section>
<section style="${CARD};padding:16px">${previewCol([NEW, M[0], M[1]], 0, { phone: true, w: 326 })}</section>`, bottomBar: btn('حفظ وسيلة الدفع', { phone: true, full: true }) }) });
board('AdmPayEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Payment methods · Empty · Phone', tab: 'لوحة الشركة · وسائل الدفع · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'payment-methods', body: `${noPay('لا توجد وسيلة دفع يحوّلون عليها.')}${emptyState({ card: true, phone: true, icon: 'card', title: 'أضف أول وسيلة دفع', text: 'حساب إنستاباي، أو محفظة فودافون كاش، أو حساب بنكي. يظهر للطالب في صفحة الدفع ليحوّل عليه ثمن الاشتراك.', action: btn('إضافة وسيلة دفع', { icon: 'plus', phone: true, full: true }) })}` }) });
board('AdmPayStopPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Payment methods · Stopping the last method · Phone', tab: 'لوحة الشركة · وسائل الدفع · إيقاف · هاتف',
  body: (size) => shellPhone({ size, active: 'payment-methods', sub: SUB, body: recordList({ cards: M.slice(0, 2).map((m, i) => cardM({ ...m, on: i === 0 }, i, 2)) }), overlay: scrim(stopLastDialog(true), 'bottom') }) });
