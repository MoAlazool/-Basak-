import {
  board, shellDesktop, shellPhone, scrim, dialog, field, infoRows, recordList, recordCard, chip, searchBox,
  badge, btn, iconBtn, toast, note, emptyState, errorState, skeleton, money, time, ltr, ico, receiptImg, status,
  C, T, R, CARD,
} from './kit.mjs';
import { keyHints, frame, sheet, W, ELL, STOPS, avatar } from './people-local.mjs';

const ROW = 'PR';
const SUB = 'الأقدم أولاً. قارن المبلغ في صورة التحويل بالمبلغ المطلوب، ثم اقبل أو ارفض.';

/* ── Data: the 7 receipts waiting (invented) ────────────────────── */
const Q = [
  { name: 'منة الله إبراهيم عبد الرازق', short: 'منة الله إبراهيم', phone: '010 2345 6780', uni: 'جامعة دمياط · التجارة · محاسبة', line: 'الزرقا', go: '7:00', back: '3:00', period: 'الفصل الأول 2026/2027', type: 'فصل دراسي', dates: 'من 19 سبتمبر 2026 إلى 14 يناير 2027', amount: 4500, attempt: 2, ago: 'منذ 3 ساعات', at: `اليوم ${'6:12'}`, atT: ['6:12', 'ص'] },
  { name: 'عمر خالد إسماعيل البنا', short: 'عمر خالد إسماعيل', phone: '010 6789 0124', uni: 'جامعة حورس · طب الأسنان', line: 'دمياط الجديدة', go: '7:30', back: '3:30', period: 'الفصل الأول 2026/2027', type: 'فصل دراسي', dates: 'من 19 سبتمبر 2026 إلى 14 يناير 2027', amount: 4500, attempt: 5, ago: 'منذ ساعتين', atT: ['7:05', 'ص'] },
  { name: 'نورهان محمود عبد العزيز شلبي', short: 'نورهان محمود', phone: '015 0123 4567', uni: 'جامعة دمياط · التربية · رياض أطفال', line: 'شربين', go: '6:45', back: '2:30', period: 'الفصلان معاً 2026/2027', type: 'الفصلان معاً', dates: 'من 19 سبتمبر 2026 إلى 10 يونيو 2027', amount: 9000, attempt: 1, ago: 'منذ ساعة ونصف', atT: ['7:41', 'ص'] },
  { name: 'زياد عمرو حسن البدراوي', short: 'زياد عمرو حسن', phone: '011 1234 5673', uni: 'جامعة دمياط · العلوم · كيمياء', line: 'دمياط الجديدة', go: '8:15', back: '4:00', period: 'الفصل الثاني 2026/2027', type: 'فصل دراسي', dates: 'من 6 فبراير 2027 إلى 10 يونيو 2027', amount: 4500, attempt: 1, ago: 'منذ ساعة', atT: ['8:10', 'ص'], soon: true },
  { name: 'هاجر أشرف محمد عبد الغني', short: 'هاجر أشرف محمد', phone: '010 2345 6780', uni: 'جامعة حورس · الصيدلة', line: 'الزرقا', go: '7:00', back: '3:00', period: 'الفصل الأول 2026/2027', type: 'فصل دراسي', dates: 'من 19 سبتمبر 2026 إلى 14 يناير 2027', amount: 4500, attempt: 3, ago: 'منذ 40 دقيقة', atT: ['8:32', 'ص'] },
  { name: 'مصطفى ياسر عبد الهادي زهران', short: 'مصطفى ياسر', phone: '012 8901 2345', uni: 'المعهد العالي بدمياط الجديدة · نظم المعلومات', line: 'فارسكور', go: '7:15', back: '3:15', period: 'الفصل الأول 2026/2027', type: 'فصل دراسي', dates: 'من 19 سبتمبر 2026 إلى 14 يناير 2027', amount: 4200, attempt: 1, ago: 'منذ 12 دقيقة', atT: ['9:00', 'ص'] },
  { name: 'شهد تامر إبراهيم الشناوي', short: 'شهد تامر إبراهيم', phone: '011 7890 1236', uni: 'جامعة دمياط · الآداب · لغة إنجليزية', line: 'دمياط الجديدة', go: '7:30', back: '3:30', period: 'الفصل الأول 2026/2027', type: 'فصل دراسي', dates: 'من 19 سبتمبر 2026 إلى 14 يناير 2027', amount: 4500, attempt: 1, ago: 'منذ 4 دقائق', atT: ['9:08', 'ص'] },
];
const lastTag = badge('آخر محاولة', 'danger');
const soonTag = badge('دفع مقدم', 'teal');
const amt = (n) => n.toLocaleString('en-US') + '.00';

/* ── Parts ──────────────────────────────────────────────────────── */
const lineChips = (list, phone) => {
  const by = {}; list.forEach((r) => { by[r.line] = (by[r.line] ?? 0) + 1; });
  return [chip('كل الخطوط', { on: true, count: list.length, phone }), ...Object.entries(by).map(([l, n]) => chip(l, { count: n, phone }))].join('');
};
const queueItem = (r, i, o = {}) => {
  const on = o.open === i;
  return `<a href="#"${on ? ' aria-current="true"' : ''} style="display:flex;align-items:center;gap:12px;min-height:72px;padding:10px 16px;${i ? `border-top:1px solid ${C.hair};` : ''}background:${on ? C.tint : o.hover === i ? C.ground : 'transparent'};color:${C.ink};position:relative">${on ? `<span aria-hidden="true" style="position:absolute;inset-inline-start:0;top:0;bottom:0;width:3px;background:${C.teal}"></span>` : ''}
${o.broken === i ? `<span aria-hidden="true" style="width:40px;height:52px;border-radius:8px;background:${C.sunken};color:${C.ink3};display:flex;align-items:center;justify-content:center;flex:none">${ico('image', 18)}</span>` : receiptImg(40, 52, { r: 8 })}
<span style="flex:1;min-width:0;display:flex;flex-direction:column;gap:2px"><span style="display:flex;align-items:center;gap:8px"><span style="flex:1;min-width:0;${T.small};font-weight:${on ? 600 : 500};${ELL}">${r.short}</span>${r.attempt === 5 ? lastTag : r.soon ? soonTag : ''}</span><span style="display:flex;align-items:baseline;gap:8px;${T.cap};color:${C.ink2}"><span style="flex:1;min-width:0;${ELL}">${r.line} · ${money(r.amount, { unit: 11 })}</span><span style="color:${C.ink3};white-space:nowrap">${r.ago}</span></span></span></a>`;
};
const queue = (list, o = {}) => `<section aria-label="الإيصالات المنتظرة" style="${CARD};overflow:hidden;display:flex;flex-direction:column">
<div style="padding:12px 16px;display:flex;flex-direction:column;gap:10px;border-bottom:1px solid ${C.hair}">
${searchBox({ placeholder: 'ابحث باسم الطالب أو هاتفه', value: o.search }).replace('flex:1;min-width:0;', '').replace(/flex:none">/, 'align-self:stretch">')}
<div role="group" aria-label="تصفية بالخط" style="display:flex;gap:6px;flex-wrap:wrap">${o.chips ?? lineChips(o.all ?? list)}</div>
</div>
${o.body ?? list.map((r, i) => queueItem(r, i, o)).join('\n')}
${o.more ? `<div style="padding:12px 16px;border-top:1px solid ${C.hair};display:flex;flex-direction:column;gap:8px;align-items:center"><span style="${T.cap};color:${C.ink3}">معروض ${ltr('50')} من ${ltr('64')}</span>${btn('عرض المزيد من الإيصالات', { kind: 'outline', sm: true })}</div>` : ''}
</section>`;

const tool = (icon, label) => `<button type="button" aria-label="${label}" title="${label}" style="width:40px;height:40px;border-radius:${R.control}px;color:#FFFFFF;display:flex;align-items:center;justify-content:center">${ico(icon, 20)}</button>`;
const zoomOut = `<button type="button" aria-label="تصغير" title="تصغير" style="width:40px;height:40px;border-radius:${R.control}px;color:#FFFFFF;display:flex;align-items:center;justify-content:center"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"></circle><path d="m21 21-4.300-4.300M8 11h6"></path></svg></button>`;
const tools = (o = {}) => `<div role="toolbar" aria-label="أدوات الصورة" style="display:flex;align-items:center;gap:2px;background:${C.ink};border-radius:${R.inner}px;padding:4px;box-shadow:${'0 8px 20px -8px rgba(23,56,74,.5)'}">${tool('zoom', 'تكبير')}${zoomOut}<span dir="ltr" style="min-width:44px;text-align:center;font-size:12px;font-weight:500;color:#C9D8E1">100%</span>${tool('refresh', 'تدوير الصورة')}<span aria-hidden="true" style="width:1px;height:20px;background:rgba(255,255,255,.2);margin:0 4px"></span><a href="#" aria-label="فتح الصورة الأصلية في تبويب جديد" style="display:inline-flex;align-items:center;gap:6px;height:40px;padding:0 10px;border-radius:${R.control}px;color:#FFFFFF;font-size:13px;font-weight:500">${ico('external', 18)}<span>${o.phone ? 'الأصل' : 'الصورة الأصلية'}</span></a></div>`;
const viewer = (r, o = {}) => {
  const w = o.w ?? (o.compact ? 250 : 372); const h = o.h ?? (o.compact ? 420 : 560);
  const inner = o.broken
    ? `<div role="alert" style="display:flex;flex-direction:column;align-items:center;text-align:center;gap:6px;padding:24px;max-width:300px"><span aria-hidden="true" style="width:56px;height:56px;border-radius:28px;background:${C.badBg};color:${C.bad};display:flex;align-items:center;justify-content:center;margin-bottom:6px">${ico('image', 26)}</span><div style="${T.card}">تعذّر عرض صورة الإيصال</div><div style="${T.small};color:${C.ink2}">قد يكون الاتصال ضعيفاً أو الصورة لم تُحفظ. لا تقبل ولا ترفض قبل أن تراها.</div><div style="margin-top:10px">${btn('حمّل الصورة مرة أخرى', { kind: 'secondary', icon: 'refresh', phone: o.phone })}</div></div>`
    : o.loading ? `<span role="status" style="${T.small};color:${C.ink3}">جاري تحميل الصورة…</span>`
      : receiptImg(Math.round(h * 0.86 * 0.62), Math.round(h * 0.86), { amount: amt(o.shown ?? r.amount), from: r.short });
  return `<div style="width:${typeof w === 'number' ? w + 'px' : w};height:${h}px;flex:none;border-radius:${R.inner}px;background:#D5E0E7;display:flex;align-items:center;justify-content:center;position:relative;overflow:hidden">${inner}${o.broken || o.loading ? '' : `<div style="position:absolute;bottom:12px;left:0;right:0;display:flex;justify-content:center">${tools(o)}</div>`}</div>`;
};
const dueCard = (r, o = {}) => `<div style="border-radius:${R.inner}px;background:${C.tint};padding:${o.phone ? '12px 16px' : '14px 16px'};display:flex;flex-direction:column;gap:2px"><span style="${T.label};font-weight:500;color:${C.ink2}">المبلغ المطلوب</span><span style="font-size:${o.phone ? 28 : 32}px;line-height:${o.phone ? 36 : 40}px;font-weight:600">${money(r.amount, { unit: 14, unitColor: C.ink2 })}</span><span style="${T.label};color:${C.ink2}">يجب أن يطابق المبلغ في الصورة، وأن يكون التحويل إلى حسابك.</span></div>`;
const facts = (r, o = {}) => infoRows([
  ['الطالب', `<div style="font-weight:500">${r.name}</div><div style="${T.label};color:${C.ink2}">${ltr(r.phone)}</div>`],
  ['الجامعة', r.uni],
  ['الخط والمحطة', `${r.line} · ${STOPS[r.line]}`],
  ['الرحلات', `ذهاب ${time(r.go, 'ص')} · عودة ${time(r.back, 'م')}`],
  ['الاشتراك', `<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><span>${r.period}</span>${r.soon ? soonTag : ''}</div><div style="${T.label};color:${C.ink2}">${r.dates}</div>`],
  ['المحاولة', `<span style="display:inline-flex;align-items:center;gap:8px;flex-wrap:wrap"><span>${r.attempt} من 5</span>${r.attempt === 5 ? lastTag : ''}</span>`],
  ['أُرسل', `اليوم ${time(...r.atT)} · ${r.ago}`],
], { labelW: o.phone ? 104 : 112 });
const lastNote = note({ tone: 'danger', title: 'آخر محاولة لهذا الطالب', text: 'إن رفضت هذا الإيصال فلن يستطيع إرسال إيصال آخر لهذا الاشتراك. راجعه بعناية.' });
const HINTS = keyHints([['A', 'قبول'], ['R', 'رفض'], ['↑ ↓', 'الإيصال السابق والتالي'], ['Z', 'تكبير']]);

const detail = (r, o = {}) => `<section aria-label="الإيصال المفتوح" style="${CARD};display:flex;flex-direction:column;min-width:0">
<header style="display:flex;align-items:center;gap:12px;padding:14px 20px;border-bottom:1px solid ${C.hair}">${avatar(r.name, 40)}<div style="flex:1;min-width:0"><h2 style="margin:0;${T.card};${ELL}">${r.name}</h2><div style="${T.label};color:${C.ink2}">${r.line} · ${r.period}</div></div>
<span style="${T.label};color:${C.ink2};white-space:nowrap">${o.pos ?? 1} من ${o.total ?? 7}</span>${iconBtn('up', 'الإيصال السابق', { sm: true })}${iconBtn('down', 'الإيصال التالي', { sm: true })}</header>
${o.banner ? `<div style="padding:16px 20px 0">${o.banner}</div>` : ''}
<div style="display:flex;gap:20px;padding:20px;align-items:flex-start">
${viewer(r, o)}
<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:12px">${dueCard(r)}${r.attempt === 5 && !o.gone ? lastNote : ''}${facts(r)}</div>
</div>
<footer style="display:flex;align-items:center;gap:12px;padding:14px 20px;border-top:1px solid ${C.hair}">${o.gone ? `<span style="flex:1"></span>${btn('افتح الإيصال التالي', { iconEnd: 'fwd' })}` : `<div style="flex:1;min-width:0">${HINTS}</div>${btn('رفض', { kind: 'dangerQuiet', icon: 'x', state: o.locked ? 'disabled' : undefined })}${btn('قبول الإيصال', { icon: 'check', state: o.locked ? 'disabled' : undefined, extra: 'min-width:160px;' })}`}</footer>
</section>`;
const split = (list, o = {}) => `<div style="display:grid;grid-template-columns:340px minmax(0,1fr);gap:24px;align-items:start">${queue(list, o)}${o.detail ?? detail(list[o.open ?? 0], { pos: (o.open ?? 0) + 1, total: list.length, ...o })}</div>`;
const meta = (n) => badge(`${n} تنتظر`, n ? 'warning' : 'success');
const page = (size, o = {}) => shellDesktop({ size, active: 'receipts', title: 'الإيصالات', sub: SUB, meta: meta(o.n ?? 7), badges: o.badges, overlay: o.overlay, offline: o.offline, body: o.body });
const toastAt = (t) => `<div style="position:absolute;inset-inline-start:296px;bottom:32px;z-index:5">${t}</div>`;

/* ── Reject dialog ──────────────────────────────────────────────── */
const REASONS = ['الصورة غير واضحة', 'المبلغ أقل من المطلوب', 'التحويل ليس إلى حساب الشركة', 'الإيصال قديم أو مكرر', 'سبب آخر'];
const tells = (text, left) => `<div style="border-radius:${R.inner}px;background:${C.ground};padding:12px 14px;display:flex;flex-direction:column;gap:4px"><span style="${T.cap};font-weight:600;color:${C.ink3}">ما سيقرؤه الطالب في التطبيق</span><span style="${T.small};color:${C.ink}">«رُفض إيصالك: ${text}»</span><span style="${T.label};color:${C.ink2}">${left}</span></div>`;
const rejectDialog = (r, o = {}) => dialog({
  phone: o.phone, w: 560, icon: 'x', tone: 'danger', title: `رفض إيصال ${r.short}؟`,
  body: `<span>اختر السبب. يبقى اشتراكه «إيصال مرفوض» حتى يرسل إيصالاً جديداً.</span>
${field({ type: 'radio', label: 'سبب الرفض', phone: o.phone, cols: 2, options: REASONS.slice(0, o.other ? 5 : 4).map((l, i) => ({ label: l, on: o.other ? i === 4 : i === 1 })).concat(o.other ? [] : [{ label: 'سبب آخر' }]) })}
${o.other ? field({ type: 'textarea', label: 'اكتب السبب للطالب', value: o.empty ? '' : 'الاسم في التحويل ليس اسمك ولا اسم ولي أمرك. أرسل ما يثبت أن التحويل منك.', placeholder: 'مثال: رقم العملية مقطوع من الصورة', error: o.empty ? 'اكتب السبب؛ لا يُرفض إيصال بدون سبب يقرؤه الطالب.' : undefined, rows: 2, phone: o.phone }) : field({ type: 'text', label: 'توضيح للطالب', optional: true, value: 'المحوَّل 4,000 والمطلوب 4,500', phone: o.phone })}
${o.empty ? '' : tells(o.other ? 'الاسم في التحويل ليس اسمك ولا اسم ولي أمرك. أرسل ما يثبت أن التحويل منك.' : 'المبلغ أقل من المطلوب. المحوَّل 4,000 والمطلوب 4,500.', r.attempt === 5 ? 'لا تبقى له محاولات أخرى لهذا الاشتراك.' : `ثم: «يمكنك إرسال إيصال جديد. بقيت لك ${5 - r.attempt} محاولات.»`)}`,
  actions: [btn('رجوع', { kind: 'secondary', phone: o.phone, full: o.phone }), btn('رفض الإيصال', { kind: 'danger', phone: o.phone, full: o.phone, state: o.empty ? 'disabled' : undefined })],
});

/* ── Desktop boards ─────────────────────────────────────────────── */
board('AdmReceipts', { row: ROW, w: 1440, title: 'Admin web · Receipts · Desktop', tab: 'لوحة الشركة · الإيصالات',
  body: (size) => page(size, { body: split(Q, { open: 0, hover: 2 }) }) });

board('AdmReceiptsReject', { row: ROW, w: 1440, min: 1000, title: 'Admin web · Receipts · Reject with a reason', tab: 'لوحة الشركة · الإيصالات · رفض',
  body: (size) => page(size, { body: split(Q, { open: 0, shown: 4000 }), overlay: scrim(rejectDialog(Q[0])) }) });

board('AdmReceiptsAccepted', { row: ROW, w: 1440, title: 'Admin web · Receipts · After accepting (next opens, undo)', tab: 'لوحة الشركة · الإيصالات · بعد القبول',
  body: (size) => page(size, { n: 6, badges: { receipts: 6, requests: 2 }, body: split(Q.slice(1), { open: 0 }),
    overlay: toastAt(toast({ text: `قُبل إيصال منة الله إبراهيم. صار اشتراكها نشطاً.`, action: 'تراجع', w: 460 })) }) });

/* ── States ─────────────────────────────────────────────────────── */
const emptyQ = (phone) => emptyState({ card: true, phone, icon: 'check', title: 'لا إيصالات تنتظرك', text: 'راجعت كل ما وصل. عندما يدفع طالب ويرسل صورة التحويل من التطبيق تظهر هنا فوراً، ويظهر عددها بجانب «الإيصالات» في القائمة.' });
const firstQ = (phone) => emptyState({ card: true, phone, icon: 'receipt', title: 'هنا تراجع إيصالات الدفع', text: 'يحوّل الطالب ثمن الاشتراك إلى حسابك ثم يرسل صورة التحويل من التطبيق. تفتحها هنا، تقارن المبلغ، وتقبل أو ترفض. لم يصل أي إيصال بعد.', action: btn('تأكد من وسائل الدفع', { kind: 'secondary', iconEnd: 'fwd', phone, full: phone }) });
const loadingBody = `<div style="display:grid;grid-template-columns:340px minmax(0,1fr);gap:24px;align-items:start">${skeleton('list', { rows: 5, rowH: 72, phone: true })}<div aria-busy="true" style="${CARD};padding:20px;display:flex;gap:20px">${skeleton('bar', { w: 300, h: 380 })}<div style="flex:1;display:flex;flex-direction:column;gap:16px">${skeleton('bar', { w: 220, h: 72 })}${skeleton('text', { rows: 6 })}</div></div></div>`;
const goneBanner = note({ tone: 'teal', title: 'قرّر مدير آخر في هذا الإيصال قبلك', text: 'لم يُحفظ قرارك ولا تحتاج أن تفعل شيئاً. حالة اشتراك الطالب الآن تجدها في صفحة «الطلاب».' });
const noMatch = `<div style="padding:28px 16px;text-align:center;${T.small};color:${C.ink2}">لا إيصال منتظر بهذا الاسم أو الرقم.<div style="margin-top:8px">${btn('امسح البحث', { kind: 'link', sm: true })}</div></div>`;
const pickOne = `<section style="${CARD}">${emptyState({ icon: 'search', title: 'لا نتيجة للبحث', text: 'البحث في الإيصالات المنتظرة فقط. إن كان إيصال الطالب قد قُبل أو رُفض فستجد حالة اشتراكه في صفحة «الطلاب».', action: btn('ابحث في الطلاب', { kind: 'secondary', iconEnd: 'fwd' }) })}</section>`;
const st = (h, o) => shellDesktop({ size: `width:${W}px;min-height:${h}px`, active: 'receipts', breadcrumb: ['الإيصالات'], title: 'الإيصالات', sub: SUB, ...o, body: o.body });

board('AdmReceiptsStates', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Receipts · States', tab: 'Basak admin web · Receipts · states',
  body: (size) => sheet(size, [
    frame('Loading', 'The queue and the open receipt keep their shapes; the picture loads last and says so.', st(600, { body: loadingBody })),
    frame('Nothing waiting', 'The normal good state. Says what will make a receipt appear. The sidebar badge is gone.', st(520, { meta: meta(0), badges: { requests: 2 }, body: emptyQ(false) })),
    frame('First use', 'A company that has never received a receipt: what the page is for, and the one thing worth checking.', st(560, { meta: meta(0), badges: {}, body: firstQ(false) })),
    frame('Picture did not load', 'The signed link is asked for again once by itself; if that fails too, this. Accept and reject are held back until the picture shows.', st(600, { body: split(Q, { open: 1, broken: 1, locked: true, compact: true }) })),
    frame('Decided by another admin meanwhile', 'The save is refused, the queue is read again, and the receipt says it was already decided. Nothing is lost and nothing needs doing.', st(600, { n: 6, badges: { receipts: 6, requests: 2 }, body: split(Q, { open: 0, gone: true, banner: goneBanner, compact: true }) })),
    frame('Search with no match · long queue', 'Search and the line filter work on the loaded receipts (50 at a time); the foot of the list loads the next 50.', st(600, { n: 64, badges: { receipts: 64, requests: 2 }, body: split(Q.slice(0, 0), { search: 'سارة', chips: lineChips(Q).replace('>7<', '>64<'), body: noMatch, more: true, detail: pickOne }) })),
    frame('Offline', 'The loaded queue stays readable; deciding waits for the connection.', st(600, { offline: true, body: split(Q, { open: 0, locked: true, compact: true }) })),
    frame('Save failed', 'The receipt returns to its place in the queue and a toast says so in plain words.', st(600, { body: split(Q, { open: 0, compact: true }), overlay: toastAt(toast({ tone: 'danger', text: 'لم يُحفظ قبول إيصال منة الله. ما زال في الانتظار؛ حاول مرة أخرى.', action: 'إعادة المحاولة', w: 520 })) })),
  ].join('\n'), { title: 'Receipts · states', sub: 'Every frame is the full page at desktop width. The phone forms follow the same words.' }) });

/* ── Phone ──────────────────────────────────────────────────────── */
const card = (r) => recordCard({
  title: r.name, sub: `${r.line} · ${STOPS[r.line]}`,
  end: `<span style="display:flex;color:${C.ink3};padding-top:2px">${ico('fwd', 18)}</span>`,
  fields: [['المبلغ المطلوب', `<b style="font-weight:600">${money(r.amount)}</b>`], ['الاشتراك', `${r.period}${r.soon ? ' ' + soonTag : ''}`], ['المحاولة', `<span style="display:inline-flex;align-items:center;gap:8px">${r.attempt === 5 ? lastTag : ''}<span>${r.attempt} من 5</span></span>`], ['أُرسل', r.ago]],
});
board('AdmReceiptsPhone', { row: ROW, w: 390, title: 'Admin web · Receipts · Phone · Queue', tab: 'لوحة الشركة · الإيصالات · هاتف',
  body: (size) => shellPhone({ size, active: 'receipts', sub: 'الأقدم أولاً. افتح الإيصال لترى الصورة وتقرر.',
    body: recordList({ toolbar: { search: 'ابحث باسم الطالب أو هاتفه', filters: [{ label: 'كل الخطوط', on: true, count: 7 }, { label: 'دمياط الجديدة', count: 3 }, { label: 'الزرقا', count: 2 }, { label: 'شربين', count: 1 }], count: '7 إيصالات تنتظر' }, cards: Q.map(card) }) }) });

const two = (o = {}) => `<div style="display:grid;grid-template-columns:minmax(0,2fr) minmax(0,3fr);gap:8px">${btn('رفض', { kind: 'dangerQuiet', icon: 'x', phone: true, full: true, state: o.locked ? 'disabled' : undefined })}${btn('قبول الإيصال', { icon: 'check', phone: true, full: true, state: o.locked ? 'disabled' : undefined })}</div>`;
const phoneReceipt = (size, r, o = {}) => shellPhone({ size, active: 'receipts', back: 'الإيصالات', title: r.short, gap: 16, overlay: o.overlay, bottomBar: `${o.toast ?? ''}${two(o)}`,
  body: `<div style="display:flex;align-items:center;gap:8px;${T.label};color:${C.ink2}"><span style="flex:1">${o.pos ?? 1} من ${o.total ?? 7} · ${r.ago}</span>${btn('التالي', { kind: 'link', sm: true, iconEnd: 'fwd' })}</div>
${dueCard(r, { phone: true })}
${r.attempt === 5 ? lastNote : ''}
${viewer(r, { w: '100%', h: 470, phone: true, broken: o.broken })}
<section style="${CARD};padding:4px 16px">${facts(r, { phone: true })}</section>` });
board('AdmReceiptPhone', { row: ROW, w: 390, title: 'Admin web · Receipts · Phone · One receipt', tab: 'لوحة الشركة · إيصال · هاتف',
  body: (size) => phoneReceipt(size, Q[0]) });
board('AdmReceiptRejectPhone', { row: ROW, w: 390, min: 1180, title: 'Admin web · Receipts · Phone · Reject', tab: 'لوحة الشركة · رفض إيصال · هاتف',
  body: (size) => phoneReceipt(size, Q[0], { overlay: scrim(rejectDialog(Q[0], { phone: true, other: true }), 'bottom') }) });
board('AdmReceiptAcceptedPhone', { row: ROW, w: 390, title: 'Admin web · Receipts · Phone · After accepting (last attempt next)', tab: 'لوحة الشركة · بعد القبول · هاتف',
  body: (size) => phoneReceipt(size, Q[1], { pos: 1, total: 6, toast: toast({ phone: true, text: 'قُبل إيصال منة الله إبراهيم.', action: 'تراجع' }) }) });
board('AdmReceiptsEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Receipts · Phone · Nothing waiting', tab: 'لوحة الشركة · الإيصالات · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'receipts', dot: true, body: emptyQ(true) }) });
board('AdmReceiptBrokenPhone', { row: ROW, w: 390, title: 'Admin web · Receipts · Phone · Picture did not load', tab: 'لوحة الشركة · إيصال · الصورة لم تُحمّل · هاتف',
  body: (size) => phoneReceipt(size, Q[2], { pos: 3, broken: true, locked: true }) });
