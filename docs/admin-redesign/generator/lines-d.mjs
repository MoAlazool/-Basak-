/** Supervisors and company managers — desktop then phone. */
import {
  board, shellDesktop, shellPhone, dataTable, recordList, recordCard, sidePanel, infoRows, dialog, scrim, field, badge, state, btn, iconBtn,
  note, toast, emptyState, errorState, skeleton, ltr, ico, cell2, C, T, R, CARD, SHADOW,
} from './kit.mjs';
import { col, card, h3, small, avatar, menu, pick, statesBoard, dialogsBoard, back, FW, ELL, LINES, SUPS, NO_SUP } from './lines-kit.mjs';

/* ══ Supervisors ════════════════════════════════════════════════════ */
const SUB = 'المشرف يركب مع الباص ويسجّل صعود الطلاب بهاتفه. يدخل التطبيق برقم هاتفه وكلمة مرور، ويرى خطوطه فقط.';
const addBtn = (o = {}) => btn('أضف مشرفاً', { icon: 'plus', ...o });
const lineBadges = (s, o = {}) => (s.lines.length === 0 ? badge('بلا خطوط', 'warning') : `<span style="display:flex;gap:6px;flex-wrap:wrap;${o.end ? 'justify-content:flex-end' : ''}">${s.lines.map((l) => badge(l === 'رأس البر' ? `${l} · متوقف` : l, 'neutral')).join('')}</span>`);
const supState = (s) => (s.on ? state('on') : state('off'));
const FILT = [{ label: 'الكل', on: true, count: SUPS.length }, { label: 'يعمل', count: SUPS.filter((s) => s.on).length }, { label: 'متوقف', count: SUPS.filter((s) => !s.on).length }, { label: 'بلا خطوط', count: SUPS.filter((s) => !s.lines.length).length }];
const supTable = (o = {}) => dataTable({
  caption: 'مشرفو الشركة',
  toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', filters: FILT, sort: 'الاسم' },
  columns: [{ label: 'المشرف' }, { label: 'رقم الهاتف', w: 160 }, { label: 'الخطوط', w: 330 }, { label: 'الحالة', w: 120 }, { label: '', w: 52, align: 'end' }],
  rows: (o.rows ?? SUPS).map((s, i) => ({ state: o.states?.[i], muted: !s.on, cells: [
    `<div style="display:flex;align-items:center;gap:12px;min-width:0">${avatar(s.name, 36, { photo: s.photo })}<span style="font-weight:500;${ELL}">${s.name}</span></div>`, ltr(s.phone), lineBadges(s), supState(s), iconBtn('dots', `إجراءات ${s.name}`, { sm: true }),
  ] })),
});
const noSupNote = (phone) => note({ tone: 'danger', title: `خطان بلا مشرف: ${NO_SUP.join('، ')}`, text: 'لا أحد يسجّل ركاب هذين الخطين عند الصعود. أسندهما لمشرف موجود أو أضف مشرفاً.', action: phone ? '' : btn('اختر مشرفاً لخط شربين', { kind: 'outline', sm: true }) });
const listBody = (o = {}) => `${noSupNote()}${supTable(o)}`;
const supShell = (size, o = {}) => shellDesktop({ size, active: 'supervisors', title: 'المشرفون', sub: SUB, actions: addBtn(), body: o.body ?? listBody(o), overlay: o.overlay });

board('AdmSupervisors', { row: 'S', w: 1440, title: 'Admin web · Supervisors · Desktop', tab: 'لوحة الشركة · المشرفون',
  body: (size) => supShell(size, { body: `${noSupNote()}<div style="position:relative">${supTable({ states: { 2: 'hover' } })}<div style="position:absolute;inset-inline-end:44px;top:${60 + 44 + 56 * 2 + 46}px;z-index:2">${menu([
    { label: 'افتح بيانات المشرف', icon: 'eye' }, { label: 'تغيير الخطوط', icon: 'route', hover: true }, { label: 'تغيير الصورة', icon: 'image' }, '-', { label: 'إيقاف المشرف', icon: 'power' }, { label: 'حذف المشرف', icon: 'trash', danger: true }])}</div></div>` }) });

/* Add: side panel */
const linePicks = (chosen, o = {}) => `<div style="display:grid;grid-template-columns:${o.phone ? 'minmax(0,1fr)' : 'repeat(2,minmax(0,1fr))'};gap:8px">${LINES.map((l) => pick(l.name, chosen.includes(l.name), { phone: o.phone, full: true, muted: l.vis === 'off' && !chosen.includes(l.name),
    end: l.vis === 'off' ? `<span style="${T.cap};font-weight:400;color:${C.ink3}">متوقف</span>` : !l.sup.length ? `<span style="${T.cap};font-weight:500;color:${C.bad}">بلا مشرف</span>` : '' })).join('')}</div>`;
const pwField = (o = {}) => `<div style="display:flex;flex-direction:column;gap:6px"><div style="${T.label};font-weight:500">كلمة المرور</div>
<div style="display:flex;gap:8px;${o.phone ? 'flex-direction:column' : ''}"><div style="flex:1;min-width:0">${field({ type: 'password', value: o.empty ? '' : 'x', placeholder: '8 أحرف أو أكثر', phone: o.phone, error: o.error })}</div>${btn('ولّد كلمة مرور', { kind: 'tonal', icon: 'wand', phone: o.phone })}</div>
${o.error ? '' : `<div style="${T.label};color:${C.ink2}">مخفية وأنت تكتب؛ العين تُظهرها. بعد الإضافة نعرضها لك مرة واحدة لتسلّمها له، ثم لا يمكن عرضها ولا تغييرها.</div>`}</div>`;
const addForm = (o = {}) => col(`
${field({ label: 'اسم المشرف', value: o.empty ? '' : 'كريم عادل الطنطاوي', placeholder: 'مثال: أحمد محمود', phone: o.phone, state: o.empty ? 'focus' : undefined })}
${field({ type: 'tel', label: 'رقم الهاتف', value: o.empty ? '' : o.taken ? '011 3456 7890' : '010 4455 6677', placeholder: '01x xxxx xxxx', phone: o.phone, help: 'رقم مصري من 11 رقماً. يدخل به التطبيق، ولا يتغيّر بعد الإضافة.', error: o.taken ? 'هذا الرقم مسجل لمشرف آخر: محمود السيد عبد الغني.' : undefined })}
${pwField({ phone: o.phone, empty: o.empty })}
<div style="display:flex;flex-direction:column;gap:8px"><div style="${T.label};font-weight:500">الخطوط التي يشرف عليها</div>${linePicks(o.empty ? [] : ['شربين', 'عزبة البرج'], { phone: o.phone })}
<div style="${T.label};color:${C.ink2}">خط واحد على الأقل. الخط المتوقف لا يُسند لمشرف جديد.</div></div>`, 16);
const addPanel = (o = {}) => sidePanel({ title: 'مشرف جديد', sub: 'يُنشأ حسابه فوراً ويدخل به تطبيق الهاتف', body: addForm(o),
  footer: `${back('رجوع')}<span style="flex:1"></span>${btn('أضف المشرف', { icon: 'plus' })}` });
board('AdmSupervisorAdd', { row: 'S', w: 1440, min: 1060, title: 'Admin web · Supervisors · Add (side panel) · Desktop', tab: 'لوحة الشركة · المشرفون · مشرف جديد',
  body: (size) => supShell(size, { overlay: scrim(addPanel(), 'end') }) });

/* Created: the sign-in details, once */
const secret = (k, v, o = {}) => `<div style="display:flex;align-items:center;gap:12px;min-height:52px;padding:6px 6px 6px 14px;padding-inline:14px 6px;border-radius:${R.control}px;background:${C.ground};box-shadow:inset 0 0 0 1px ${C.hair}"><span style="width:92px;flex:none;${T.label};color:${C.ink2}">${k}</span><span dir="ltr" style="flex:1;min-width:0;text-align:right;font-size:17px;font-weight:600;letter-spacing:.5px">${v}</span>${iconBtn('copy', `نسخ ${k}`, { phone: o.phone })}</div>`;
const createdDialog = (phone) => dialog({ phone, tone: 'success', icon: 'check', w: 520, title: 'أُضيف كريم عادل الطنطاوي. سلّمه بيانات الدخول الآن', body: `
<span>يدخل تطبيق باصك بهذين، ويرى خطي شربين وعزبة البرج.</span>
<div style="display:flex;flex-direction:column;gap:8px">${secret('رقم الهاتف', '010 4455 6677', { phone })}${secret('كلمة المرور', 'Nq7-rb4K-2xm', { phone })}</div>
${note({ tone: 'warning', title: 'هذه آخر مرة تظهر فيها كلمة المرور', text: 'تُحفظ مشفّرة ولا نستطيع عرضها ولا تغييرها بعد إغلاق هذه النافذة.' })}`,
  actions: [btn('نسخ البيانات معاً', { kind: 'outline', icon: 'copy', phone, full: phone }), btn('سلّمتها، إغلاق', { phone, full: phone })] });
board('AdmSupervisorCreated', { row: 'S', w: 1440, min: 900, title: 'Admin web · Supervisors · Created, password shown once · Desktop', tab: 'لوحة الشركة · المشرفون · أُضيف المشرف',
  body: (size) => supShell(size, { overlay: scrim(createdDialog(), 'center') }) });

/* One supervisor: side panel */
const S3 = SUPS[2];
const viewBody = (o = {}) => col(`
<div style="display:flex;align-items:center;gap:16px">${avatar(S3.name, 72, { cam: true })}<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px"><div style="${T.label};color:${C.ink2}">صورته تظهر له في التطبيق ولطلاب خطوطه.</div><div style="display:flex;gap:8px">${btn('أضف صورة', { kind: 'outline', sm: !o.phone, icon: 'image', phone: o.phone })}</div></div></div>
${infoRows([['رقم الهاتف', ltr(S3.phone)], ['الحالة', `<span style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">${state('on')}<span style="${T.label};color:${C.ink2}">يرى خطوطه ويسجّل الركوب</span></span>`]], { labelW: 108 })}
${small('الاسم ورقم الهاتف لا يتغيّران بعد الإضافة.', C.ink3)}
<div style="display:flex;flex-direction:column;gap:10px;border-top:1px solid ${C.hair};padding-top:16px">${h3('خطوطه', btn('تغيير الخطوط', { kind: 'link', sm: true, icon: 'pencil' }))}
${[['فارسكور', '96 مشتركاً · 5 ذهاب · 5 عودة', true], ['رأس البر', '12 مشتركاً · الخط متوقف', false]].map(([n, s, on]) => `<div style="display:flex;align-items:center;gap:12px;min-height:52px;padding:6px 14px;border-radius:${R.control}px;box-shadow:inset 0 0 0 1px ${C.hair}"><span style="display:flex;color:${C.ink2}">${ico('route', 18)}</span><span style="flex:1;min-width:0"><span style="display:block;${T.small};font-weight:500">${n}</span><span style="display:block;${T.cap};color:${C.ink3}">${s}</span></span>${on ? '' : state('off')}</div>`).join('')}</div>
<div style="display:flex;flex-direction:column;gap:10px;border-top:1px solid ${C.hair};padding-top:16px">${h3('كلمة المرور')}
${note({ tone: 'warning', icon: 'lock', title: 'لا يمكن عرضها ولا تغييرها من هنا', text: 'إن نسيها المشرف فالحل الوحيد اليوم: احذف حسابه ثم أضفه من جديد بنفس الرقم وكلمة مرور جديدة، وأسند إليه خطوطه. الحذف يمحو سجلات الركوب التي سجّلها.', action: '' })}
<div style="display:flex">${btn('نسي كلمة المرور؟', { kind: 'outline', sm: !o.phone, icon: 'key', phone: o.phone, full: o.phone })}</div></div>`, 16);
const viewPanel = () => sidePanel({ title: S3.name, sub: 'مشرف', meta: state('on'), body: viewBody(),
  footer: `${btn('حذف المشرف', { kind: 'dangerQuiet', icon: 'trash' })}<span style="flex:1"></span>${btn('إيقاف المشرف', { kind: 'outline', icon: 'power' })}` });
board('AdmSupervisor', { row: 'S', w: 1440, min: 1000, title: 'Admin web · Supervisors · One supervisor (side panel) · Desktop', tab: 'لوحة الشركة · المشرفون · مشرف',
  body: (size) => supShell(size, { states: { 2: 'open' }, overlay: scrim(viewPanel(), 'end') }) });

/* Change lines: same panel, lines in edit */
const linesEdit = (chosen, o = {}) => col(`
<div style="display:flex;align-items:center;gap:12px">${avatar(o.name ?? S3.name, 44)}<div style="min-width:0"><div style="${T.small};font-weight:600;${ELL}">${o.name ?? S3.name}</div><div style="${T.label};color:${C.ink2}">${ltr(o.tel ?? S3.phone)}</div></div></div>
<div style="display:flex;flex-direction:column;gap:8px"><div style="${T.label};font-weight:500">الخطوط التي يشرف عليها</div>${linePicks(chosen, { phone: o.phone })}</div>
${chosen.length ? small('يرى في التطبيق هذه الخطوط فقط، من لحظة الحفظ. خط رأس البر متوقف: يبقى معه، ولا يُسند لغيره حتى يعمل.') : note({ tone: 'warning', title: 'بلا خطوط لن يرى المشرف أي خط في التطبيق', text: 'يبقى حسابه كما هو. تستطيع الحفظ هكذا وإسناد خط له لاحقاً.' })}`, 16);
board('AdmSupervisorLines', { row: 'S', w: 1440, min: 1000, title: 'Admin web · Supervisors · Change lines (side panel) · Desktop', tab: 'لوحة الشركة · المشرفون · تغيير الخطوط',
  body: (size) => supShell(size, { states: { 2: 'open' }, overlay: scrim(sidePanel({ title: 'خطوط المشرف', sub: 'أضف خطاً أو ارفعه عنه', body: linesEdit(['فارسكور', 'رأس البر', 'شربين']),
    footer: `${back('رجوع')}<span style="flex:1"></span>${btn('حفظ الخطوط', {})}` }), 'end') }) });

/* Confirmations */
const D = {
  stop: (phone) => dialog({ phone, tone: 'danger', icon: 'power', title: 'إيقاف المشرف هاني عبد المقصود؟', body: `<span>لن يرى خطوطه ولن يسجّل الركوب في التطبيق، ولن يظهر لطلاب خطوطه. حسابه وخطوطه تبقى كما هي، وتشغّله متى شئت.</span><span>خط <b style="color:${C.ink}">فارسكور</b> يبقى معه مشرف آخر (أحمد رضا الجمل). خط رأس البر متوقف.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('إيقاف المشرف', { kind: 'danger', phone, full: phone })] }),
  start: (phone) => dialog({ phone, tone: 'teal', icon: 'power', title: 'تشغيل المشرف طارق عبد الفتاح سليمان؟', body: '<span>يعود ليرى خط الزرقا ويسجّل ركابه في التطبيق بنفس رقمه وكلمة مروره.</span>',
    actions: [back('رجوع', { phone, full: phone }), btn('تشغيل المشرف', { phone, full: phone })] }),
  del: (phone) => dialog({ phone, tone: 'danger', icon: 'trash', title: 'حذف المشرف مصطفى كمال أبو العينين؟', body: '<span>يُحذف حساب دخوله وصورته نهائياً، وتُحذف معه سجلات الركوب التي سجّلها. لا يمكن التراجع.</span><span>لا خطوط معه، فلن يتأثر أي خط. إن أردت الاحتفاظ بسجلاته فأوقفه بدلاً من حذفه.</span>',
    actions: [back('رجوع', { phone, full: phone }), btn('حذف المشرف', { kind: 'danger', phone, full: phone })] }),
  delLast: (phone) => dialog({ phone, tone: 'danger', icon: 'trash', title: 'حذف المشرف سامح فتحي البنا؟', body: `<span>يُحذف حساب دخوله وصورته نهائياً، وتُحذف معه سجلات الركوب التي سجّلها. لا يمكن التراجع؛ الإيقاف يحفظها.</span><span>هو المشرف الوحيد على <b style="color:${C.ink}">كفر سعد</b> (74 مشتركاً) و<b style="color:${C.ink}">كفر البطيخ</b>: يصبحان بلا مشرف ولا يسجّل ركابهما أحد حتى تسند كل خط لمشرف آخر.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('حذف المشرف', { kind: 'danger', phone, full: phone })] }),
  forgot: (phone) => dialog({ phone, tone: 'warning', icon: 'key', title: 'نسي هاني كلمة المرور؟', body: `<span>لا نستطيع تغيير كلمة مرور المشرف اليوم. الطريق الوحيد:</span><span>1. احذف حسابه. يصبح خط رأس البر بلا مشرف، وخط فارسكور مع أحمد رضا الجمل وحده.<br>2. أضفه من جديد بنفس الرقم ${ltr('012 4567 8901')} وكلمة مرور جديدة.<br>3. أسند إليه خطيه وأضف صورته.</span><span>تنبيه: الحذف يمحو سجلات الركوب التي سجّلها حتى اليوم.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('حذف الحساب لإعادة إضافته', { kind: 'dangerQuiet', phone, full: phone })] }),
  photo: (phone) => dialog({ phone, tone: 'danger', icon: 'image', title: 'إزالة صورة إبراهيم الدسوقي عبد الحميد؟', body: '<span>يظهر مكانها الحرف الأول من اسمه، عنده في التطبيق وعند طلاب خطوطه. تستطيع إضافة صورة أخرى بعدها.</span>',
    actions: [back('رجوع', { phone, full: phone }), btn('إزالة الصورة', { kind: 'dangerQuiet', phone, full: phone })] }),
};
dialogsBoard('AdmSupervisorDialogs', { row: 'S', title: 'Admin web · Supervisors · Confirmations', heading: 'Supervisors · every confirmation' }, [
  ['Stop a supervisor', 'Today: a tap on the status pill, no question. is_active = false: the app\'s data rules stop answering him and students no longer see him. Says which lines keep another supervisor.', D.stop()],
  ['Reactivate', 'Same tap today. Asked for symmetry and because it restores access.', D.start()],
  ['Delete · no lines', 'admin-delete-supervisor removes the sign-in account, the row, the line assignments and the photos — and, by the schema (supervisor_scan_events.supervisor_id ON DELETE CASCADE), every boarding record he scanned. The current confirm() does not say so.', D.del()],
  ['Delete · the only supervisor of a line', 'The same action with its real consequence: lines left without anyone. Derivable from the assignments already loaded.', D.delLast()],
  ['Forgot the password — the honest current route', 'No function resets a supervisor\'s password. Until one exists, the dashboard walks the owner through delete and re-create instead of leaving him to discover it.', D.forgot()],
  ['Remove the photo', 'Today a browser confirm().', D.photo()],
]);

/* States */
const supEmpty = (phone) => emptyState({ card: true, phone, icon: 'scan', title: 'لا مشرفين بعد', text: 'المشرف يركب مع الباص ويسجّل صعود الطلاب بهاتفه، فتعرف من ركب فعلاً. أضف أول مشرف وأسند إليه خطاً.', action: addBtn({ phone, full: phone }) });
statesBoard('AdmSupervisorsStates', { row: 'S', title: 'Admin web · Supervisors · Loading, first use, no line yet, mistakes, added, error' }, [
  ['Loading', 'The table in grey.', shellDesktop({ size: `width:${FW}px;height:520px`, active: 'supervisors', title: 'المشرفون', sub: SUB, actions: addBtn(), body: skeleton('table', { rows: 4, cols: 4 }) })],
  ['First use', 'What a supervisor is for, and the one button.', shellDesktop({ size: `width:${FW}px;height:560px`, active: 'supervisors', title: 'المشرفون', sub: SUB, body: supEmpty(false) })],
  ['No line yet', 'A supervisor needs at least one line (the server refuses without). The page says so and sends the owner to make the line first; «أضف مشرفاً» is not offered.',
    shellDesktop({ size: `width:${FW}px;height:560px`, active: 'supervisors', badges: {}, title: 'المشرفون', sub: SUB, body: emptyState({ card: true, icon: 'route', title: 'أضف خطاً أولاً', text: 'كل مشرف يلزمه خط واحد على الأقل يشرف عليه، وليس عندك خطوط بعد.', action: btn('أضف أول خط', { icon: 'plus' }) }) })],
  ['Mistakes in the add panel', 'Under the field, in the server\'s own Arabic rules: a phone already used, a password shorter than 8. Nothing is created half-way (the function is all-or-nothing).',
    shellDesktop({ size: `width:${FW}px;height:1060px`, active: 'supervisors', title: 'المشرفون', sub: SUB, actions: addBtn(), body: supTable({ rows: SUPS.slice(0, 6) }),
      overlay: scrim(sidePanel({ title: 'مشرف جديد', sub: 'يُنشأ حسابه فوراً ويدخل به تطبيق الهاتف', body: col(`
${field({ label: 'اسم المشرف', value: 'كريم عادل الطنطاوي' })}
${field({ type: 'tel', label: 'رقم الهاتف', value: '011 3456 7890', error: 'هذا الرقم مسجل بالفعل لمشرف آخر.' })}
${pwField({ error: 'كلمة المرور يجب ألا تقل عن 8 أحرف.' })}
<div style="display:flex;flex-direction:column;gap:8px"><div style="${T.label};font-weight:500">الخطوط التي يشرف عليها</div>${linePicks([])}
<div role="alert" style="display:flex;align-items:flex-start;gap:6px;${T.label};color:${C.bad}"><span style="display:flex;padding-top:2px">${ico('alert', 14, 2)}</span><span>اختر خطاً واحداً على الأقل يشرف عليه.</span></div></div>`, 16),
        footer: `${back('رجوع')}<span style="flex:1"></span>${btn('أضف المشرف', { icon: 'plus' })}` }), 'end') })],
  ['Lines saved', 'A toast after each quiet save (lines, photo, stop, reactivate).', shellDesktop({ size: `width:${FW}px;height:520px`, active: 'supervisors', title: 'المشرفون', sub: SUB, actions: addBtn(), body: supTable({ rows: SUPS.slice(0, 4) }),
    overlay: `<div style="position:absolute;inset-inline-start:${264 + 32}px;bottom:24px">${toast({ text: 'حُفظت خطوط هاني عبد المقصود: فارسكور، رأس البر، شربين.' })}</div>` })],
  ['Error', 'Plain words and a retry.', shellDesktop({ size: `width:${FW}px;height:520px`, active: 'supervisors', title: 'المشرفون', sub: SUB, body: errorState({ card: true, title: 'تعذّر تحميل المشرفين', text: 'لم نستطع جلب المشرفين وخطوطهم. تأكد من اتصالك ثم حاول مرة أخرى.' }) })],
]);

/* Phone */
board('AdmSupervisorsPhone', { row: 'S', w: 390, title: 'Admin web · Supervisors · Phone', tab: 'لوحة الشركة · المشرفون · هاتف',
  body: (size) => shellPhone({ size, active: 'supervisors', body: `${noSupNote(true)}${recordList({
    toolbar: { search: 'ابحث بالاسم أو رقم الهاتف', filters: FILT, count: `${SUPS.length} مشرفين` },
    cards: SUPS.map((s) => recordCard({ title: `<span style="display:flex;align-items:center;gap:10px">${avatar(s.name, 36, { photo: s.photo })}<span style="flex:1;min-width:0">${s.name}</span></span>`, end: `<span style="display:flex;color:${C.ink3};padding-top:8px">${ico('fwd', 18)}</span>`,
      fields: [['رقم الهاتف', ltr(s.phone)], ['الخطوط', lineBadges(s, { end: true })], ['الحالة', supState(s)]] })) })}`, bottomBar: addBtn({ phone: true, full: true }) }) });
board('AdmSupervisorAddPhone', { row: 'S', w: 390, title: 'Admin web · Supervisors · Add · Phone', tab: 'لوحة الشركة · المشرفون · مشرف جديد · هاتف',
  body: (size) => shellPhone({ size, active: 'supervisors', title: 'مشرف جديد', back: 'المشرفون', sub: 'يُنشأ حسابه فوراً ويدخل به تطبيق الهاتف.', body: `<section style="${CARD};padding:16px">${addForm({ phone: true })}</section>`, bottomBar: btn('أضف المشرف', { icon: 'plus', phone: true, full: true }) }) });
board('AdmSupervisorCreatedPhone', { row: 'S', w: 390, h: 844, title: 'Admin web · Supervisors · Created, password shown once · Phone', tab: 'لوحة الشركة · المشرفون · أُضيف المشرف · هاتف',
  body: (size) => shellPhone({ size, active: 'supervisors', title: 'مشرف جديد', back: 'المشرفون', body: `<section style="${CARD};padding:16px">${addForm({ phone: true })}</section>`, overlay: scrim(createdDialog(true), 'bottom') }) });
board('AdmSupervisorPhone', { row: 'S', w: 390, title: 'Admin web · Supervisors · One supervisor · Phone', tab: 'لوحة الشركة · المشرفون · مشرف · هاتف',
  body: (size) => shellPhone({ size, active: 'supervisors', title: S3.name, back: 'المشرفون', body: `<section style="${CARD};padding:16px">${viewBody({ phone: true })}</section>
${btn('حذف المشرف', { kind: 'link', phone: true, full: true, extra: `color:${C.bad};` })}`, bottomBar: btn('إيقاف المشرف', { kind: 'outline', icon: 'power', phone: true, full: true }) }) });
board('AdmSupervisorDeletePhone', { row: 'S', w: 390, h: 844, title: 'Admin web · Supervisors · Delete · Phone', tab: 'لوحة الشركة · المشرفون · حذف · هاتف',
  body: (size) => shellPhone({ size, active: 'supervisors', title: 'سامح فتحي البنا', back: 'المشرفون', body: `<section style="${CARD};padding:16px">${viewBody({ phone: true })}</section>`, overlay: scrim(D.delLast(true), 'bottom') }) });
board('AdmSupervisorsEmptyPhone', { row: 'S', w: 390, title: 'Admin web · Supervisors · First use · Phone', tab: 'لوحة الشركة · المشرفون · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'supervisors', dot: false, body: supEmpty(true) }) });

/* ══ Company managers ═══════════════════════════════════════════════ */
const MSUB = 'من يدخل هذه اللوحة باسم شركتك. كل مدير يرى كل الصفحات ويفعل كل شيء: لا درجات بينهم.';
const MGRS = [
  { name: 'أحمد سعيد النورس', mail: 'ahmed.elnawras@example.com', date: '14 سبتمبر 2026', me: true },
  { name: 'منى سعيد النورس', mail: 'mona.elnawras@example.com', date: '20 سبتمبر 2026' },
  { name: 'خالد عبد الله الصاوي', mail: 'khaled.elsawy@example.com', date: '3 أكتوبر 2026' },
];
const mgrCell = (m, viewer) => `<div style="display:flex;align-items:center;gap:12px;min-width:0">${avatar(m.name, 36)}<span style="font-weight:500;${ELL}">${m.name}</span>${m.me && viewer === 'company' ? badge('أنت', 'teal') : ''}</div>`;
const mgrTable = (viewer, o = {}) => dataTable({
  caption: 'مديرو الشركة', toolbar: { count: `${(o.rows ?? MGRS).length === 1 ? 'مدير واحد' : `${(o.rows ?? MGRS).length} مديرين`} · يدخلون بالبريد الإلكتروني وكلمة المرور` },
  columns: [{ label: 'المدير' }, { label: 'البريد الإلكتروني', w: 320 }, { label: 'أُضيف في', w: 170 }, ...(viewer === 'workspace' ? [{ label: '', w: 110, align: 'end' }] : [])],
  rows: (o.rows ?? MGRS).map((m, i) => ({ state: o.states?.[i], cells: [mgrCell(m, viewer), ltr(m.mail), m.date, ...(viewer === 'workspace' ? [btn('إزالة', { kind: 'outline', sm: true, icon: 'trash', state: o.last ? 'disabled' : undefined })] : [])] })),
});
const askPlatform = (phone) => note({ tone: 'teal', icon: 'shield', title: 'إضافة مدير أو إزالته عند إدارة المنصة', text: 'لا يستطيع مدير الشركة أن يضيف مديراً ولا أن يزيله. اطلب ذلك من إدارة المنصة واذكر الاسم والبريد الإلكتروني.' });
board('AdmManagers', { row: 'M', w: 1440, title: 'Admin web · Company managers · Company admin (read-only) · Desktop', tab: 'لوحة الشركة · مديرو الشركة',
  body: (size) => shellDesktop({ size, active: 'team', title: 'مديرو الشركة', sub: MSUB, body: `${mgrTable('company')}${askPlatform()}` }) });

const superOnly = badge('لمدير المنصة فقط', 'neutral');
board('AdmManagersWorkspace', { row: 'M', w: 1440, title: 'Admin web · Company managers · Super admin inside the company · Desktop', tab: 'لوحة الشركة · مديرو الشركة · مدير المنصة',
  body: (size) => shellDesktop({ size, role: 'workspace', active: 'team', title: 'مديرو الشركة', sub: MSUB, meta: superOnly, actions: btn('أضف مديراً', { icon: 'plus' }),
    body: `${mgrTable('workspace')}<p style="margin:0;${T.label};color:${C.ink2}">كل حساب هنا يرى بيانات هذه الشركة فقط. الإضافة والإزالة تظهران لمدير المنصة وحده؛ مدير الشركة يرى القائمة فقط.</p>` }) });

const mgrForm = (o = {}) => col(`
${field({ label: 'اسم المدير', value: 'خالد عبد الله الصاوي', phone: o.phone })}
${field({ label: 'البريد الإلكتروني', value: 'khaled.elsawy@example.com', ltr: true, phone: o.phone, help: 'يدخل به اللوحة.', error: o.taken ? 'هذا البريد مسجل لمدير آخر.' : undefined })}
${field({ type: 'radio', label: 'كيف يحصل على كلمة المرور؟', phone: o.phone, cols: 1, options: [
    { label: 'دعوة بالبريد', sub: 'يصله رابط يفتحه ويختار كلمة مروره بنفسه', on: !o.pw },
    { label: 'كلمة مرور مبدئية أكتبها الآن', sub: 'يدخل بها فوراً، وتسلّمها له أنت', on: !!o.pw }] })}
${o.pw ? field({ type: 'password', label: 'كلمة المرور المبدئية', value: 'x', phone: o.phone, help: '8 أحرف أو أكثر.' }) : ''}
${note({ tone: 'teal', title: 'يرى كل شيء في هذه الشركة', text: 'الإيصالات، الطلاب، الخطوط، الإيرادات والإعدادات. لا درجات صلاحيات بين المديرين.' })}`, 16);
board('AdmManagerAdd', { row: 'M', w: 1440, min: 960, title: 'Admin web · Company managers · Add (side panel, super admin) · Desktop', tab: 'لوحة الشركة · مديرو الشركة · مدير جديد',
  body: (size) => shellDesktop({ size, role: 'workspace', active: 'team', title: 'مديرو الشركة', sub: MSUB, meta: superOnly, actions: btn('أضف مديراً', { icon: 'plus' }), body: mgrTable('workspace', { rows: MGRS.slice(0, 2) }),
    overlay: scrim(sidePanel({ title: 'مدير جديد لشركة النورس للنقل', meta: superOnly, body: mgrForm(), footer: `${back('رجوع')}<span style="flex:1"></span>${btn('أرسل الدعوة', { icon: 'mail' })}` }), 'end') }) });

const M = {
  remove: (phone) => dialog({ phone, tone: 'danger', icon: 'trash', title: 'إزالة المدير خالد عبد الله الصاوي؟', body: `<span>يُحذف حساب دخوله ${ltr('khaled.elsawy@example.com')} نهائياً ولا يدخل اللوحة بعدها. لا يمكن التراجع؛ لإعادته تضيفه من جديد.</span><span>المشرفون الذين أضافهم يبقون. يبقى للشركة مديران.</span>`,
    actions: [back('رجوع', { phone, full: phone }), btn('إزالة المدير', { kind: 'danger', phone, full: phone })] }),
  last: (phone) => dialog({ phone, tone: 'warning', icon: 'alert', title: 'لا يمكن إزالة آخر مدير للشركة', body: '<span>أحمد سعيد النورس هو المدير الوحيد لشركة النورس للنقل. إن أزلته لم يبقَ من يراجع إيصالات طلابها.</span><span>أضف مديراً آخر أولاً، ثم أزله.</span>',
    actions: [back('رجوع', { phone, full: phone }), btn('أضف مديراً آخر', { kind: 'outline', icon: 'plus', phone, full: phone })] }),
  invited: (phone) => dialog({ phone, tone: 'success', icon: 'mail', title: 'أُرسلت الدعوة إلى خالد عبد الله الصاوي', body: `<span>وصله بريد على ${ltr('khaled.elsawy@example.com')} فيه رابط. يفتحه ويختار كلمة مروره، ثم يدخل اللوحة.</span><span>يظهر الآن في قائمة المديرين.</span>`,
    actions: [btn('تم', { phone, full: phone })] }),
  created: (phone) => dialog({ phone, tone: 'success', icon: 'check', title: 'أُنشئ حساب خالد عبد الله الصاوي', body: `<span>يدخل اللوحة الآن بالبريد ${ltr('khaled.elsawy@example.com')} وكلمة المرور التي كتبتها. سلّمها له، ويستطيع تغييرها من «نسيت كلمة المرور» في صفحة الدخول.</span>`,
    actions: [btn('تم', { phone, full: phone })] }),
};
dialogsBoard('AdmManagerDialogs', { row: 'M', title: 'Admin web · Company managers · Confirmations and results', heading: 'Company managers · every confirmation and result',
  intro: 'All four are seen by the super admin only: a company admin cannot add or remove a manager (the two functions require the platform role). There are no roles among managers in the code.' }, [
  ['Remove a manager', 'admin-delete-company-admin: the account is deleted, not suspended. Supervisors he created stay. Today this exists only on the platform page «مديرو الشركات»; drawn here too because the list is here.', M.remove()],
  ['The last manager', 'NOT enforced by the code today: the function refuses only deleting yourself and deleting a platform admin. Drawn as the rule the dashboard should hold (count is on the page); needs the same check in the function.', M.last()],
  ['After adding · invitation sent', 'admin-create-company-admin answers invited: true when no password was given.', M.invited()],
  ['After adding · account created with a password', 'The other answer of the same function. The manager can change it through the recovery link on the sign-in page.', M.created()],
]);

statesBoard('AdmManagersStates', { row: 'M', title: 'Admin web · Company managers · One, mistakes, loading, error' }, [
  ['One manager (super admin view)', 'The only manager cannot be removed: the button is off and the row says why.',
    shellDesktop({ size: `width:${FW}px;height:560px`, role: 'workspace', active: 'team', title: 'مديرو الشركة', sub: MSUB, meta: superOnly, actions: btn('أضف مديراً', { icon: 'plus' }), body: `${mgrTable('workspace', { rows: MGRS.slice(0, 1), last: true })}${note({ tone: 'warning', title: 'مدير واحد فقط', text: 'لا يُزال آخر مدير للشركة. أضف مديراً آخر إن أردت تغييره، وليبقى من يدخل اللوحة إن غاب.' })}` })],
  ['Mistake in the add panel', 'An e-mail already used by another manager, under the field (the server checks it before creating anything). Password chosen instead of an invitation.',
    shellDesktop({ size: `width:${FW}px;height:940px`, role: 'workspace', active: 'team', title: 'مديرو الشركة', sub: MSUB, meta: superOnly, body: mgrTable('workspace'),
      overlay: scrim(sidePanel({ title: 'مدير جديد لشركة النورس للنقل', meta: superOnly, body: mgrForm({ pw: true, taken: true }), footer: `${back('رجوع')}<span style="flex:1"></span>${btn('أنشئ الحساب', { icon: 'key' })}` }), 'end') })],
  ['Loading', 'Two grey rows.', shellDesktop({ size: `width:${FW}px;height:460px`, active: 'team', title: 'مديرو الشركة', sub: MSUB, body: skeleton('table', { rows: 2, cols: 3 }) })],
  ['Error', 'Plain words and a retry (today: the raw message and no retry). An empty list cannot happen for a signed-in company admin: he is on it.',
    shellDesktop({ size: `width:${FW}px;height:520px`, active: 'team', title: 'مديرو الشركة', sub: MSUB, body: errorState({ card: true, title: 'تعذّر تحميل المديرين', text: 'لم نستطع جلب قائمة المديرين. تأكد من اتصالك ثم حاول مرة أخرى.' }) })],
]);

const mgrCards = (viewer) => MGRS.map((m) => recordCard({ title: `<span style="display:flex;align-items:center;gap:10px">${avatar(m.name, 36)}<span style="flex:1;min-width:0">${m.name}</span>${m.me && viewer === 'company' ? badge('أنت', 'teal') : ''}</span>`,
  fields: [['البريد الإلكتروني', ltr(m.mail, 'font-size:13px')], ['أُضيف في', m.date]], actions: viewer === 'workspace' ? btn('إزالة', { kind: 'outline', sm: true, icon: 'trash', extra: 'height:44px;' }) : undefined }));
board('AdmManagersPhone', { row: 'M', w: 390, title: 'Admin web · Company managers · Company admin · Phone', tab: 'لوحة الشركة · مديرو الشركة · هاتف',
  body: (size) => shellPhone({ size, active: 'team', sub: MSUB, body: `${recordList({ toolbar: { count: '3 مديرين · يدخلون بالبريد وكلمة المرور' }, cards: mgrCards('company') })}${askPlatform(true)}` }) });
board('AdmManagerAddPhone', { row: 'M', w: 390, title: 'Admin web · Company managers · Add (super admin) · Phone', tab: 'لوحة الشركة · مديرو الشركة · مدير جديد · هاتف',
  body: (size) => shellPhone({ size, role: 'workspace', active: 'team', title: 'مدير جديد', back: 'مديرو الشركة', body: `<div>${superOnly}</div><section style="${CARD};padding:16px">${mgrForm({ phone: true })}</section>`, bottomBar: btn('أرسل الدعوة', { icon: 'mail', phone: true, full: true }) }) });
board('AdmManagerRemovePhone', { row: 'M', w: 390, h: 844, title: 'Admin web · Company managers · Remove (super admin) · Phone', tab: 'لوحة الشركة · مديرو الشركة · إزالة · هاتف',
  body: (size) => shellPhone({ size, role: 'workspace', active: 'team', body: recordList({ toolbar: { count: '3 مديرين' }, cards: mgrCards('workspace') }), overlay: scrim(M.remove(true), 'bottom') }) });
