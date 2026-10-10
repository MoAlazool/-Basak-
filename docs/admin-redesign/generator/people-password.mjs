import {
  board, shellDesktop, shellPhone, scrim, dialog, dataTable, recordList, recordCard, state, badge, btn, iconBtn,
  toast, note, emptyState, errorState, skeleton, time, ltr, ico, C, T, R, CARD,
} from './kit.mjs';
import { person, codeBox, frame, sheet, W } from './people-local.mjs';

const ROW = 'PP';
const SUB = 'طالب نسي كلمة المرور وطلب المساعدة من التطبيق. اتصل به لتتأكد أنه هو، ثم أعطه رمزاً يكتبه في التطبيق مع كلمة مرور جديدة.';
const RULES = note({ tone: 'teal', title: 'الرمز يصلح 30 دقيقة ولمرة واحدة', text: 'للطالب 5 محاولات لكتابته. لا تظهر كلمات المرور هنا أبداً، ولا يستطيع أحد غير الطالب أن يختار كلمته الجديدة.' });

/* ── Data ───────────────────────────────────────────────────────── */
const REQ = [
  { name: 'عبد الرحمن محمد السيد الشربيني', short: 'عبد الرحمن محمد', phone: '011 3456 7891', when: `اليوم ${'9:02'}`, at: ['9:02', 'ص'], ago: 'منذ 10 دقائق', st: 'pending' },
  { name: 'سلمى طارق عبد الحميد سالم', short: 'سلمى طارق', phone: '011 7890 1235', at: ['8:40', 'ص'], ago: 'منذ 32 دقيقة', st: 'issued', until: ['9:21', 'ص'], fails: 2 },
  { name: 'كريم وائل السعيد أبو النجا', phone: '011 1234 5679', day: 'أمس', at: ['6:15', 'م'], st: 'done' },
  { name: 'آية مصطفى كامل النحاس', phone: '010 6789 0124', day: 'أمس', at: ['1:30', 'م'], st: 'expired' },
  { name: 'محمد إيهاب رمضان الجمل', phone: '011 3456 7891', day: '8 أكتوبر', at: ['10:05', 'ص'], st: 'done' },
  { name: 'روان هشام عبد الله الطنطاوي', phone: '012 4567 8902', day: '7 أكتوبر', at: ['7:48', 'م'], st: 'cancelled' },
  { name: 'حازم مدحت السيد الصياد', phone: '011 3456 7891', day: '5 أكتوبر', at: ['8:12', 'ص'], st: 'done' },
  { name: 'ندى علاء الدين محمد البسيوني', phone: '012 4567 8902', day: '2 أكتوبر', at: ['3:20', 'م'], st: 'done' },
  { name: 'فارس جمال عبد الناصر قنديل', phone: '015 5678 9013', day: '29 سبتمبر', at: ['9:55', 'ص'], st: 'expired' },
];
const stCell = (r) => ({
  pending: state('open', 'ينتظر رمزاً منك'),
  issued: `<div style="display:flex;flex-direction:column;align-items:flex-start;gap:2px">${badge(`معه رمز · صالح حتى ${time(...(r.until ?? ['0:00', 'ص']))}`, 'teal')}${r.fails ? `<span style="${T.cap};color:${C.ink3}">أخطأ في كتابته ${r.fails} من 5</span>` : ''}</div>`,
  done: state('done', 'غيّر كلمة المرور'),
  expired: state('archived', 'انتهى الرمز ولم يُستعمل'),
  cancelled: state('cancelled', 'أُلغي'),
}[r.st]);
const whenCell = (r) => (r.day ? `${r.day} · ${time(...r.at)}` : `<div>اليوم ${time(...r.at)}</div><div style="${T.cap};color:${C.ink3}">${r.ago}</div>`);
const more = (r) => iconBtn('dots', `إجراءات أخرى لطلب ${r.name}`, { sm: true });
const acts = (r) => (r.st === 'pending' ? `<span style="display:inline-flex;gap:4px;align-items:center">${btn('أعطه رمزاً', { sm: true, icon: 'key' })}${more(r)}</span>`
  : r.st === 'issued' ? `<span style="display:inline-flex;gap:4px;align-items:center">${btn('رمز جديد', { sm: true, kind: 'tonal', icon: 'refresh' })}${more(r)}</span>` : '');
const FILTERS = (a = 0) => [{ label: 'تنتظرك', count: 2, on: a === 0 }, { label: 'كل الطلبات', count: 16, on: a === 1 }];
const table = (rows, o = {}) => dataTable({
  caption: 'طلبات كلمة المرور',
  toolbar: { filters: FILTERS(o.filter ?? 1), count: o.count ?? '16 طلباً · الأحدث أولاً', actions: iconBtn('refresh', 'تحديث القائمة', { sm: true }) },
  columns: [{ label: 'الطالب' }, { label: 'طلب المساعدة', w: 190 }, { label: 'الحالة', w: 260 }, { label: '', w: 190, align: 'end' }],
  rows: rows.map((r, i) => ({ state: o.states?.[i], muted: false, cells: [person(r.name, ltr(r.phone)), whenCell(r), stCell(r), acts(r)] })),
  empty: o.empty,
});
const page = (size, o = {}) => shellDesktop({ size, active: 'password-requests', breadcrumb: ['طلبات كلمة المرور'], title: 'طلبات كلمة المرور', sub: SUB, meta: badge(`${o.n ?? 2} تنتظر`, (o.n ?? 2) ? 'warning' : 'success'), badges: o.badges, overlay: o.overlay, offline: o.offline,
  body: o.body ?? `${RULES}${table(REQ, o)}` });

/* ── Dialogs ────────────────────────────────────────────────────── */
const phoneBig = (p) => `<div style="display:flex;align-items:center;gap:12px;border-radius:${R.inner}px;background:${C.ground};padding:12px 16px"><span style="display:flex;color:${C.ink2}">${ico('phone', 20)}</span><span dir="ltr" style="flex:1;text-align:right;font-size:20px;line-height:28px;font-weight:600;color:${C.ink};unicode-bidi:isolate">${p}</span><a href="tel:+201134567891" style="display:inline-flex;align-items:center;height:36px;padding:0 12px;border-radius:${R.control}px;background:${C.surface};box-shadow:inset 0 0 0 1px ${C.hair};font-size:13px;font-weight:500;color:${C.ink}">اتصل</a></div>`;
const verifyDialog = (r, o = {}) => dialog({ phone: o.phone, icon: 'key', tone: 'teal', title: `هل تأكدت أنه ${r.short}؟`,
  body: `<span>اتصل به على رقمه المسجّل واسأله عن اسمه وخطّه. من يأخذ الرمز يستطيع أن يغيّر كلمة المرور ويدخل إلى الحساب.</span>${phoneBig(r.phone)}<span>${o.again ? 'الرمز السابق يتوقف عن العمل فور إصدار رمز جديد.' : 'يصلح الرمز 30 دقيقة ولمرة واحدة.'}</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone: o.phone, full: o.phone }), btn(o.again ? 'إصدار رمز جديد' : 'إصدار الرمز', { phone: o.phone, full: o.phone })] });
const how = (r) => `<ol style="margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px">${[
  `أبلغه بالرمز في مكالمة، أو في رسالة واتساب إلى الرقم نفسه ${ltr(r.phone, `font-weight:500;color:${C.ink}`)}.`,
  'يفتح التطبيق ويضغط «نسيت كلمة المرور»، ثم يكتب الرمز وكلمة مرور جديدة يختارها.',
].map((t, i) => `<li style="display:flex;gap:10px"><span aria-hidden="true" style="width:22px;height:22px;border-radius:11px;background:${C.sunken};color:${C.ink2};font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center;flex:none">${i + 1}</span><span style="flex:1">${t}</span></li>`).join('')}</ol>`;
const codeDialog = (r, o = {}) => dialog({ phone: o.phone, w: 520, icon: 'check', tone: 'success', title: `رمز ${r.short}`,
  body: `${codeBox('482 916', { phone: o.phone, size: o.phone ? 32 : 40 })}
<div style="display:flex;align-items:center;gap:8px;color:${C.ink}"><span style="display:flex;color:${C.ink2}">${ico('clock', 16, 2)}</span><span>صالح حتى ${time('9:42', 'ص')} (30 دقيقة) ولمرة واحدة.</span></div>
${how(r)}
${note({ tone: 'warning', title: 'لن يظهر الرمز مرة أخرى', text: 'بعد إغلاق هذه النافذة لا يمكن عرضه. إن ضاع فأصدر رمزاً جديداً من الصف نفسه.' })}`,
  actions: [btn('تم، أبلغته بالرمز', { phone: o.phone, full: o.phone })] });
const cancelDialog = (r, o = {}) => dialog({ phone: o.phone, icon: 'x', tone: 'danger', title: `إلغاء طلب ${r.short}؟`,
  body: `<span>يُغلق الطلب${r.st === 'issued' ? '، ويتوقف الرمز الذي أعطيته له عن العمل' : ' بدون رمز'}. تبقى كلمة مروره الحالية كما هي، ويستطيع أن يطلب المساعدة من التطبيق مرة أخرى.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone: o.phone, full: o.phone }), btn('إلغاء الطلب', { kind: 'danger', phone: o.phone, full: o.phone })] });

/* ── Desktop ────────────────────────────────────────────────────── */
board('AdmPassword', { row: ROW, w: 1440, title: 'Admin web · Password requests · Desktop', tab: 'لوحة الشركة · طلبات كلمة المرور',
  body: (size) => page(size, { states: { 1: 'hover' } }) });
board('AdmPasswordVerify', { row: ROW, w: 1440, title: 'Admin web · Password requests · Confirm identity before issuing', tab: 'لوحة الشركة · طلبات كلمة المرور · تأكيد',
  body: (size) => page(size, { states: { 0: 'open' }, overlay: scrim(verifyDialog(REQ[0])) }) });
board('AdmPasswordCode', { row: ROW, w: 1440, title: 'Admin web · Password requests · The code, shown once', tab: 'لوحة الشركة · طلبات كلمة المرور · الرمز',
  body: (size) => { const rows = [{ ...REQ[0], st: 'issued', until: ['9:42', 'ص'], fails: 0 }, ...REQ.slice(1)];
    return page(size, { n: 2, body: `${RULES}${table(rows, { states: { 0: 'open' } })}`, overlay: scrim(codeDialog(REQ[0])) }); } });
board('AdmPasswordCancel', { row: ROW, w: 1440, title: 'Admin web · Password requests · Cancel a request', tab: 'لوحة الشركة · طلبات كلمة المرور · إلغاء',
  body: (size) => page(size, { states: { 1: 'open' }, overlay: scrim(cancelDialog(REQ[1])) }) });

/* ── States ─────────────────────────────────────────────────────── */
const emptyP = (phone) => emptyState({ card: true, phone, icon: 'key', title: 'لا طلبات الآن', text: 'عندما ينسى طالب كلمة المرور ويضغط «نسيت كلمة المرور» في التطبيق يظهر طلبه هنا، ويظهر عدده بجانب «طلبات كلمة المرور» في القائمة.' });
const st = (h, o) => shellDesktop({ size: `width:${W}px;min-height:${h}px`, active: 'password-requests', breadcrumb: ['طلبات كلمة المرور'], title: 'طلبات كلمة المرور', sub: SUB, ...o });
board('AdmPasswordStates', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Password requests · States', tab: 'Basak admin web · Password requests · states',
  body: (size) => sheet(size, [
    frame('Loading', 'Today the card is absent until the list arrives; here the page keeps its shape.', st(520, { body: `${RULES}${skeleton('table', { rows: 4, cols: 4 })}` })),
    frame('No requests ever', 'First use: what brings a request here. No button — only a student can start one.', st(520, { meta: badge('0 تنتظر', 'success'), badges: { receipts: 7 }, body: emptyP(false) })),
    frame('None waiting, history only', 'The filter «تنتظرك» is empty; earlier requests stay under «كل الطلبات».', st(480, { meta: badge('0 تنتظر', 'success'), badges: { receipts: 7 },
      body: table([], { filter: 0, count: '', empty: emptyState({ icon: 'check', title: 'لا أحد ينتظر رمزاً', text: 'أجبت كل الطلبات. الطلبات السابقة تجدها في «كل الطلبات».' }) }).replace('>2<', '>0<') })),
    frame('One waiting', 'A single open request, filtered.', st(420, { meta: badge('1 ينتظر', 'warning'), badges: { receipts: 7, requests: 1 }, body: table(REQ.slice(0, 1), { filter: 0, count: 'طلب واحد' }).replace('>2<', '>1<') })),
    frame('Error', 'Plain words and a retry; never the server text.', st(520, { body: errorState({ card: true, title: 'تعذّر تحميل الطلبات', text: 'لم نستطع جلب طلبات كلمة المرور. تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
    frame('Could not issue · already used or cancelled meanwhile', 'The list is read again and shows what the request is now; the toast says why nothing happened.', st(560, { body: `${RULES}${table([{ ...REQ[0], st: 'done' }, ...REQ.slice(1, 5)])}`, overlay: `<div style="position:absolute;inset-inline-start:296px;bottom:32px;z-index:5">${toast({ tone: 'info', w: 520, text: 'لم يُصدر رمز: غيّر عبد الرحمن كلمة المرور قبل لحظات برمز سابق.' })}</div>` })),
    frame('Offline', 'Reading stays; issuing and cancelling wait for the connection.', st(520, { offline: true, body: `${RULES}${table(REQ.slice(0, 4)).replace(/<button type="button" style="height:36px/g, '<button type="button" disabled style="opacity:.45;height:36px')}` })),
  ].join('\n'), { title: 'Password requests · states' }) });

/* ── Phone ──────────────────────────────────────────────────────── */
const pCard = (r) => recordCard({ title: r.name, sub: ltr(r.phone), fields: [['طلب المساعدة', r.day ? `${r.day} · ${time(...r.at)}` : `اليوم ${time(...r.at)} · ${r.ago}`], ['الحالة', stCell(r).replace('align-items:flex-start', 'align-items:flex-end')]],
  actions: r.st === 'pending' ? `${btn('أعطه رمزاً', { icon: 'key', phone: true, extra: 'flex:1;' })}${iconBtn('dots', 'إجراءات أخرى', { phone: true, bg: C.sunken })}` : r.st === 'issued' ? `${btn('رمز جديد', { kind: 'tonal', icon: 'refresh', phone: true, extra: 'flex:1;' })}${iconBtn('dots', 'إجراءات أخرى', { phone: true, bg: C.sunken })}` : undefined });
const phonePage = (size, o = {}) => shellPhone({ size, active: 'password-requests', sub: 'اتصل بالطالب لتتأكد أنه هو، ثم أعطه رمزاً يكتبه في التطبيق مع كلمة مرور جديدة.', overlay: o.overlay,
  body: o.body ?? `${RULES}${recordList({ toolbar: { filters: FILTERS(1), count: '16 طلباً · الأحدث أولاً' }, cards: REQ.slice(0, 6).map(pCard) })}` });
board('AdmPasswordPhone', { row: ROW, w: 390, title: 'Admin web · Password requests · Phone', tab: 'لوحة الشركة · طلبات كلمة المرور · هاتف',
  body: (size) => phonePage(size) });
board('AdmPasswordVerifyPhone', { row: ROW, w: 390, min: 844, h: 844, title: 'Admin web · Password requests · Phone · Confirm identity', tab: 'لوحة الشركة · طلبات كلمة المرور · تأكيد · هاتف',
  body: (size) => phonePage(size, { overlay: scrim(verifyDialog(REQ[0], { phone: true }), 'bottom') }) });
board('AdmPasswordCodePhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Password requests · Phone · The code', tab: 'لوحة الشركة · طلبات كلمة المرور · الرمز · هاتف',
  body: (size) => phonePage(size, { overlay: scrim(codeDialog(REQ[0], { phone: true }), 'bottom') }) });
board('AdmPasswordEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Password requests · Phone · Empty', tab: 'لوحة الشركة · طلبات كلمة المرور · فارغة · هاتف',
  body: (size) => phonePage(size, { body: emptyP(true) }) });

export { verifyDialog, codeDialog, cancelDialog, REQ };
