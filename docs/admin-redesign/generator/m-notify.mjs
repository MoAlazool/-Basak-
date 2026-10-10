/** الإشعارات — /c/:companyId/notifications  (+ /notifications/new) */
import {
  board, shellDesktop, shellPhone, dataTable, recordList, recordCard, sidePanel, infoRows, dialog, scrim, field, fieldRow, btn, badge, state, note, chip,
  emptyState, errorState, skeleton, cell2, ltr, time, ico, C, T, R, CARD,
} from './kit.mjs';
import { card, grid, phoneNotif, counter, labelled, inputBox, statesBoard, mini, rowActions, dots, muted, LINES } from './m-common.mjs';

const ROW = 'G';
const SUB = 'رسائلك إلى الطلاب: تصلهم داخل التطبيق وتنبيهاً على الهاتف. يظهر هنا أيضاً ما أرسله المشرفون وما يرسله النظام وحده.';
const head = { active: 'notifications', title: 'الإشعارات', sub: SUB, actions: btn('إشعار جديد', { icon: 'plus' }) };

/* ── Data ───────────────────────────────────────────────────────── */
const ME = 'أنت'; const SYS = 'النظام';
const H = [
  { t: 'إجازة المولد النبوي', b: 'الخميس 15 أكتوبر إجازة رسمية ولا توجد رحلات. تعود الرحلات السبت في مواعيدها.', to: 'كل طلاب الشركة', by: ME, when: `الأربعاء 14 أكتوبر · ${'6:00'} م`, st: 'scheduled', n: 718 },
  { t: 'تأخير رحلة العودة', b: 'رحلة العودة 3:00 م من جامعة دمياط تتأخر 20 دقيقة بسبب زحام الكوبري.', to: 'ركاب رحلة · خط شربين', by: 'المشرف محمود السيد', when: `اليوم · ${'2:41'} م`, st: 'sent', n: 31, read: 27, urgent: true },
  { t: 'تعديل مواعيد الرحلات', b: 'تم تعديل مواعيد بعض الرحلات، راجع مواعيدك في التطبيق قبل تأكيد الركوب.', to: 'طلاب خط فارسكور', by: ME, when: `اليوم · ${'9:12'} ص`, st: 'sent', n: 96, read: 71 },
  { t: 'تذكير بسداد الاشتراك', b: 'اقترب موعد سداد الاشتراك. ادفع من صفحة الاشتراك في التطبيق لتستمر رحلاتك.', to: 'كل طلاب الشركة', by: ME, when: `أمس · ${'8:00'} م`, st: 'failed', n: 0, why: 'لم يصل إلى أحد: انقطع الاتصال أثناء الإرسال.' },
  { t: 'قبول الاشتراك', b: 'تم قبول إيصالك، واشتراكك في الفصل الأول نشط الآن.', to: 'طالب واحد', by: SYS, when: `أمس · ${'6:25'} م`, st: 'sent', n: 1, read: 1 },
  { t: 'رحلة إضافية يوم السبت', b: 'أضفنا رحلة ذهاب 8:15 ص من دمياط الجديدة ابتداءً من السبت.', to: 'طلاب خط دمياط الجديدة', by: ME, when: `8 أكتوبر · ${'5:30'} م`, st: 'cancelled', n: 0, why: 'ألغيته قبل موعده.' },
];
const MORE = [['وصول الباص', 'الباص وصل إلى محطة كوبري السرو.', 'ركاب رحلة · خط السرو', 'المشرف محمود السيد'], ['رفض الإيصال', 'لم نستطع قبول إيصالك: المبلغ أقل من ثمن الاشتراك.', 'طالب واحد', SYS], ['انطلاق الرحلة', 'انطلقت رحلة 7:00 ص من الزرقا.', 'ركاب رحلة · خط الزرقا', 'المشرف محمود السيد'], ['اقتراب انتهاء الاشتراك', 'ينتهي اشتراكك بعد 7 أيام. جدّده من التطبيق.', '12 طالباً', SYS], ['امتحانات منتصف الفصل', 'في أسبوع الامتحانات تعمل كل الرحلات في مواعيدها المعتادة.', 'طلاب جامعة حورس', ME], ['العودة من الجامعة', 'باص العودة 2:00 م يتحرك بعد 10 دقائق.', 'ركاب رحلة · خط كفر سعد', 'المشرف سامح فتحي']];
for (let i = 0; H.length < 25; i++) { const m = MORE[i % 6]; const n = [44, 1, 38, 12, 147, 27][i % 6]; H.push({ t: m[0], b: m[1], to: m[2], by: m[3], when: `${7 - Math.floor(i / 4)} أكتوبر · ${['7:02', '4:15', '7:00', '10:00', '1:30', '1:50'][i % 6]} ${i % 6 < 3 && i % 6 !== 1 ? 'ص' : 'م'}`, st: 'sent', n, read: Math.round(n * [0.9, 1, 0.8, 0.5, 0.72, 0.85][i % 6]) }); }
const readCell = (r) => (r.st === 'sent' ? `<div style="display:flex;flex-direction:column;gap:4px"><span><b style="font-weight:600">${r.read}</b> ${muted(`من ${r.n}`)}</span><span aria-hidden="true" style="display:block;height:4px;width:96px;border-radius:2px;background:${C.sunken};overflow:hidden"><span style="display:block;height:4px;background:${C.ok};width:${Math.round((r.read / r.n) * 100)}%"></span></span></div>` : muted('—'));
const titleCell = (r) => `<div style="min-width:0"><div style="display:flex;align-items:center;gap:8px"><span style="font-weight:500;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${r.t}</span>${r.urgent ? badge('عاجل', 'danger') : ''}</div><div style="font-size:12px;line-height:18px;color:${r.st === 'failed' ? C.bad : C.ink3};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${r.why ?? r.b}</div></div>`;
const table = (rows = H, o = {}) => dataTable({
  caption: 'سجل الإشعارات',
  toolbar: { search: 'ابحث في الإشعارات', searchValue: o.q, filters: ['الكل', 'المُرسلة', 'المجدولة', 'الملغاة', 'الفاشلة'].map((l, i) => ({ label: l, on: i === (o.filter ?? 0) })), actions: `<button type="button" aria-label="تحديث" style="width:36px;height:36px;border-radius:${R.control}px;display:inline-flex;align-items:center;justify-content:center;color:${C.ink2};box-shadow:inset 0 0 0 1px ${C.hair}">${ico('refresh', 16)}</button>` },
  tablet: o.compact,
  columns: [{ label: 'الإشعار' }, { label: 'إلى', w: 180 }, { label: 'المرسل', w: 150, hideTablet: true }, { label: 'الموعد', w: 180, sorted: 'desc' }, { label: 'قرأه', w: 110, hideTablet: true }, { label: 'الحالة', w: 136 }, { label: '', w: 128, align: 'end' }],
  rows: rows.map((r, i) => ({ state: o.open === i ? 'open' : undefined, muted: r.st === 'cancelled', cells: [titleCell(r), r.to, r.by, r.when.replace(/(\d+:\d+)/, (m) => ltr(m)), readCell(r), state(r.st), rowActions(r.st === 'scheduled' ? btn('تعديل', { kind: 'outline', sm: true }) : '', dots())] })),
  empty: o.empty,
});
const moreFoot = `<div style="${CARD};margin-top:-12px;border-radius:0 0 ${R.card}px ${R.card}px;border-top:1px solid ${C.hair};height:56px;display:flex;align-items:center;gap:16px;padding:0 16px"><span style="${T.label};color:${C.ink2}">يُعرض أحدث 25 إشعاراً</span><span style="flex:1"></span>${btn('اعرض 25 أقدم', { kind: 'outline', sm: true, icon: 'adown' })}</div>`;
const list = (o) => `<div style="display:flex;flex-direction:column;gap:12px">${table(H, o)}${moreFoot}</div>`;

board('AdmNotify', { row: ROW, w: 1440, title: 'Admin web · Notifications · History · Desktop', tab: 'لوحة الشركة · الإشعارات',
  body: (size) => shellDesktop({ size, ...head, body: list() }) });

/* ── Composer: /notifications/new ───────────────────────────────── */
const TPL = ['إجازة رسمية', 'تعديل المواعيد', 'تذكير بالدفع'];
const DRAFT = { title: 'تعديل مواعيد الرحلات', body: 'تم تعديل مواعيد بعض الرحلات، راجع مواعيدك في التطبيق قبل تأكيد الركوب.' };
const KINDS = [['كل طلاب الشركة', '718 طالباً'], ['طلاب خط', 'خط واحد تختاره'], ['ركاب رحلة', 'من أكّدوا رحلة اليوم أو غداً'], ['طلاب جامعة', 'جامعة واحدة تختارها']];
const audience = (k, phone, o = {}) => `${field({ type: 'radio', label: 'يصل إلى', phone, cols: 2, options: KINDS.map(([label, sub], i) => ({ label, sub, on: i === k })) })}
${k === 1 ? fieldRow([field({ type: 'select', label: 'الخط', value: o.line ?? 'شربين', phone })], { phone, cols: 'minmax(0,1fr) minmax(0,1fr)' }) : ''}
${k === 2 ? fieldRow([field({ type: 'select', label: 'الخط', value: 'شربين', phone }), field({ type: 'select', label: 'الرحلة', value: `عودة من الجامعة · ${ltr('3:00')} م`, phone }), field({ type: 'select', label: 'يوم الرحلة', value: 'اليوم', phone })], { phone }) : ''}
${k === 3 ? fieldRow([field({ type: 'select', label: 'الجامعة', value: o.uni, placeholder: 'اختر', error: o.uniErr, phone })], { phone, cols: 'minmax(0,1fr) minmax(0,1fr)' }) : ''}`;
const message = (d, phone, o = {}) => `<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><span style="${T.label};color:${C.ink2}">رسائل جاهزة</span>${TPL.map((t, i) => chip(t, { on: i === o.tpl, phone })).join('')}</div>
${labelled('العنوان', counter(o.titleLen ?? d.title.length, 80), inputBox(d.title, { placeholder: 'مثال: إجازة رسمية', phone, error: o.titleErr }), { error: o.titleErr })}
${labelled('نص الإشعار', counter(d.body.length, 600), inputBox(d.body, { rows: 4, placeholder: 'اكتب ما تريد أن يعرفه الطلاب' }))}
${field({ type: 'toggle', label: 'عاجل', help: 'للأمور العاجلة فقط، مثل تغيير يخص رحلة اليوم.', on: o.urgent, phone })}`;
const when = (later, phone, o = {}) => `${field({ type: 'radio', label: 'موعد الإرسال', phone, cols: 2, options: [{ label: 'الآن', on: !later }, { label: 'في موعد لاحق', on: later }] })}
${later ? `${fieldRow([field({ type: 'date', label: 'اليوم', value: o.day ?? 'الأحد 11 أكتوبر 2026', phone, error: o.dayErr }), field({ type: 'time', label: 'الساعة', value: time(o.hm ?? '6:00', 'ص'), help: 'بتوقيت القاهرة', phone })], { phone })}` : ''}`;
const reach = (o = {}) => `<section aria-live="polite" style="${CARD};padding:16px 20px;display:flex;flex-direction:column;gap:8px"><div style="${T.label};font-weight:500;color:${C.ink2}">من سيصله الإشعار</div>${o.loading ? skeleton('text', { rows: 2 }) : o.incomplete ? `<div style="${T.small};color:${C.ink2}">${o.incomplete}</div>` : `<div style="display:flex;align-items:baseline;gap:8px"><span style="font-size:28px;line-height:36px;font-weight:600;color:${(o.n ?? 96) ? C.ink : C.bad}">${o.n ?? 96}</span><span style="${T.small}">طالباً · ${o.label ?? 'خط فارسكور'}</span></div><div style="display:flex;gap:16px;flex-wrap:wrap;${T.label};color:${C.ink2}"><span style="display:inline-flex;align-items:center;gap:6px">${ico('scan', 14, 2)}${o.sup ?? 'مشرف واحد'}</span><span style="display:inline-flex;align-items:center;gap:6px">${ico('smartphone', 14, 2)}${o.dev ?? '83 هاتفاً يصله التنبيه'}</span></div>${o.n === 0 ? `<div style="${T.label};color:${C.bad};font-weight:500">لا يوجد طلاب في هذا الاختيار، فلن يصل الإشعار إلى أحد.</div>` : `<div style="${T.cap};color:${C.ink3}">الباقون يجدونه داخل التطبيق عند فتحه.</div>`}`}</section>`;
const newHead = (st) => ({ active: 'notifications', title: 'إشعار جديد', back: 'الإشعارات', breadcrumb: ['الإشعارات', 'إشعار جديد'], actions: btn('رجوع', { kind: 'outline' }) + btn('إرسال الإشعار', { icon: 'megaphone', state: st }) });
const composer = (o = {}) => grid('minmax(0,8fr) minmax(0,4fr)', `<div style="display:flex;flex-direction:column;gap:16px;min-width:0">
${card({ title: '1 · إلى من؟', body: audience(o.k ?? 1, false, { line: 'فارسكور', ...o }) })}
${card({ title: '2 · الرسالة', body: message(o.d ?? DRAFT, false, { tpl: 1, ...o }) })}
${card({ title: '3 · متى؟', body: when(o.later, false, o) })}
</div>
<div style="display:flex;flex-direction:column;gap:16px;min-width:0">${card({ title: 'كما يظهر على هاتف الطالب', pad: 20, body: `<div style="display:flex;justify-content:center">${phoneNotif({ title: (o.d ?? DRAFT).title, body: (o.d ?? DRAFT).body, urgent: o.urgent, ghost: true, w: 312 })}</div>` })}${reach(o.reach)}</div>`);
board('AdmNotifyNew', { row: ROW, w: 1440, title: 'Admin web · Notifications · New notification · Desktop', tab: 'لوحة الشركة · إشعار جديد',
  body: (size) => shellDesktop({ size, ...newHead(), body: composer() }) });

const sendDialog = (phone) => dialog({ phone, w: 520, icon: 'megaphone', title: 'إرسال الإشعار إلى 96 طالباً؟',
  body: `<span>يصل الآن إلى <b style="font-weight:600;color:${C.ink}">طلاب خط فارسكور</b> (96 طالباً ومشرف واحد). لا يمكن تعديله بعد الإرسال، ويمكن حذفه من عندهم.</span><div style="display:flex;justify-content:center">${phoneNotif({ ...DRAFT, w: phone ? 326 : 340 })}</div>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('إرسال إلى 96 طالباً', { phone, full: phone })] });
const scheduleDialog = (phone) => dialog({ phone, w: 520, icon: 'clock', title: 'جدولة الإشعار؟',
  body: `<span>يُرسل إلى <b style="font-weight:600;color:${C.ink}">كل طلاب الشركة</b> (718 طالباً و5 مشرفين) يوم <b style="font-weight:600;color:${C.ink}">الأربعاء 14 أكتوبر، ${time('6:00', 'م')}</b> بتوقيت القاهرة. يُحسب المستلمون من جديد عند الإرسال، ويمكنك تعديله أو إلغاؤه قبل موعده.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('جدولة الإشعار', { phone, full: phone })] });
const cancelDialog = (phone) => dialog({ phone, icon: 'x', tone: 'warning', title: 'إلغاء إرسال «إجازة المولد النبوي»؟',
  body: `<span>لن يُرسل إلى كل طلاب الشركة في موعده (الأربعاء 14 أكتوبر، ${time('6:00', 'م')}). يبقى في السجل كإشعار ملغى.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('إلغاء الإرسال', { kind: 'danger', phone, full: phone })] });
const deleteDialog = (phone) => dialog({ phone, icon: 'trash', tone: 'danger', title: 'حذف إشعار «تعديل مواعيد الرحلات»؟',
  body: '<span>يختفي من عند كل الطلاب والمشرفين الذين وصلهم (96 طالباً)، ومن هذا السجل. من قرأه لا يُمحى من ذاكرته، ولا يمكن استرجاع الإشعار.</span>',
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('حذف الإشعار', { kind: 'danger', phone, full: phone })] });
board('AdmNotifyConfirm', { row: ROW, w: 1440, h: 1180, title: 'Admin web · Notifications · Send, schedule, cancel and delete confirmations', tab: 'لوحة الشركة · الإشعارات · تأكيد',
  body: (size) => shellDesktop({ size, ...newHead(), body: composer(),
    overlay: scrim(`<div style="display:grid;grid-template-columns:auto auto;gap:24px;align-items:start">${sendDialog()}<div style="display:flex;flex-direction:column;gap:24px">${scheduleDialog()}${cancelDialog()}${deleteDialog()}</div></div>`) }) });

/* ── Details and editing a scheduled one (side panels) ──────────── */
const tile = (v, k, s) => `<div style="background:${C.ground};border-radius:${R.control}px;padding:10px 12px"><div style="font-size:20px;line-height:28px;font-weight:600">${v}${s ? ` <span style="font-size:12px;font-weight:500;color:${C.ok}">${s}</span>` : ''}</div><div style="${T.cap};color:${C.ink2}">${k}</div></div>`;
const sub3 = (t) => `<h3 style="margin:0;${T.small};font-weight:600">${t}</h3>`;
const details = (phone) => `<div style="border-radius:${R.inner}px;background:${C.ground};padding:14px 16px;${T.small};color:${C.ink}">${H[2].b}</div>
${infoRows([['إلى', 'طلاب خط فارسكور'], ['المرسل', 'أحمد سعيد النورس (أنت)'], ['النوع', 'إعلان من الإدارة'], ['أُنشئ', `اليوم 10 أكتوبر · ${time('9:10', 'ص')}`], ['أُرسل', `اليوم 10 أكتوبر · ${time('9:12', 'ص')}`]], { labelW: 96 })}
<div style="display:flex;flex-direction:column;gap:8px">${sub3('داخل التطبيق')}<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px">${tile(96, 'طالباً وصلهم')}${tile(71, 'قرؤوه', '74%')}${tile(38, 'فتحوه من التنبيه')}</div></div>
<div style="display:flex;flex-direction:column;gap:8px">${sub3('التنبيه على الهواتف')}<div style="display:grid;grid-template-columns:repeat(${phone ? 2 : 4},minmax(0,1fr));gap:8px">${tile(83, 'هاتفاً مسجّلاً')}${tile(81, 'أُرسل إليها')}${tile(2, 'فشلت')}${tile(13, 'بلا تنبيه')}</div><p style="margin:0;${T.cap};color:${C.ink3}">«أُرسل إليها» تعني أن خدمة التنبيهات استلمت الرسالة لتوصلها، ولا تؤكد أنها ظهرت على الهاتف. «بلا تنبيه»: طالب بلا هاتف مسجّل أو أوقف التنبيهات.</p></div>
<p style="margin:0;${T.cap};color:${C.ink3}">كل الأوقات بتوقيت القاهرة.</p>`;
board('AdmNotifyDetail', { row: ROW, w: 1440, h: 1000, title: 'Admin web · Notifications · Details of a sent notification (side panel)', tab: 'لوحة الشركة · الإشعارات · تفاصيل',
  body: (size) => shellDesktop({ size, ...head, body: list({ open: 2 }),
    overlay: scrim(sidePanel({ title: H[2].t, meta: state('sent'), sub: 'طلاب خط فارسكور · اليوم 9:12 ص', body: details(),
      footer: `${btn('حذف الإشعار', { kind: 'dangerQuiet', icon: 'trash' })}<span style="flex:1"></span>${btn('إغلاق', { kind: 'secondary' })}` }), 'end') }) });
const editBody = (phone) => `${audience(0, phone)}
${labelled('العنوان', counter(19, 80), inputBox(H[0].t, { phone }))}
${labelled('نص الإشعار', counter(H[0].b.length, 600), inputBox(H[0].b, { rows: 4 }))}
${fieldRow([field({ type: 'date', label: 'اليوم', value: 'الأربعاء 14 أكتوبر 2026', phone }), field({ type: 'time', label: 'الساعة', value: time('6:00', 'م'), help: 'بتوقيت القاهرة', phone, state: 'focus' })], { phone })}
${note({ tone: 'teal', title: 'يصل إلى 718 طالباً و5 مشرفين', text: 'يُحسب المستلمون من جديد عند الإرسال.' })}`;
board('AdmNotifyEdit', { row: ROW, w: 1440, h: 1080, title: 'Admin web · Notifications · Editing a scheduled notification (side panel)', tab: 'لوحة الشركة · الإشعارات · تعديل مجدول',
  body: (size) => shellDesktop({ size, ...head, body: list({ open: 0 }),
    overlay: scrim(sidePanel({ w: 520, title: 'تعديل إشعار مجدول', meta: state('scheduled'), sub: 'لم يُرسل بعد: تستطيع تغيير كلماته ومستلميه وموعده.', body: editBody(),
      footer: `${btn('إلغاء الإرسال', { kind: 'dangerQuiet', icon: 'x' })}<span style="flex:1"></span>${btn('رجوع', { kind: 'secondary' })}${btn('حفظ التعديل')}` }), 'end') }) });

/* ── States ─────────────────────────────────────────────────────── */
const LONG = { title: 'تنبيه مهم جداً لكل الطلاب المشتركين في جميع الخطوط بخصوص تعديل مواعيد رحلات الأسبوع القادم', body: DRAFT.body };
statesBoard('AdmNotifyStates', { row: ROW, title: 'Admin web · Notifications · States and limits', frames: [
  ['Empty · first use', 'What the page is for, and the first action.',
    mini(560, { ...head, actions: '', body: `<div style="${CARD}">${emptyState({ icon: 'megaphone', title: 'لم يُرسل أي إشعار بعد', text: 'أخبر طلابك بإجازة، أو بتعديل في المواعيد، أو ذكّرهم بالدفع. تختار من يصله، وترى كم طالباً قرأه.', action: btn('اكتب أول إشعار', { icon: 'plus' }) })}</div>` })],
  ['Phone alerts not connected · a failed send · a filter with nothing', 'The blue note replaces today\'s «الإشعارات الفورية غير مربوطة»: plain words, no jargon. A failed row says why in its second line; it can be opened or deleted, as today.',
    mini(800, { ...head, body: `${note({ tone: 'teal', title: 'التنبيه على الهواتف لم يُفعَّل بعد', text: 'إشعاراتك تصل إلى الطلاب داخل التطبيق في صفحة الإشعارات، ولا تظهر تنبيهاً على الهاتف حتى تفعّله إدارة المنصة.' })}${table(H.slice(3, 4), { filter: 4, compact: true })}${table([], { filter: 3, compact: true, empty: emptyState({ icon: 'megaphone', title: 'لا إشعارات ملغاة', text: 'الإشعار المجدول الذي تلغيه قبل موعده يظهر هنا.' }) })}` })],
  ['Composer limits', 'Every limit is said under its field or in the reach card, and «إرسال الإشعار» stays off until it is fixed: a title over 80 letters, an audience left unchosen, a time in the past, and an audience of zero.',
    mini(1400, { ...newHead('disabled'), body: composer({ k: 3, uniErr: 'اختر الجامعة.', d: LONG, titleErr: 'العنوان أطول من 80 حرفاً. اختصره بـ 9 أحرف.', later: true, day: 'الجمعة 9 أكتوبر 2026', dayErr: 'هذا الموعد مضى. اختر وقتاً قادماً بتوقيت القاهرة.', reach: { incomplete: 'اختر الجامعة لنحسب عدد من يصلهم.' } }) })],
  ['Audience of zero', 'The server counted nobody: the number turns red and sending is held back.',
    mini(560, { ...newHead('disabled'), body: grid('minmax(0,8fr) minmax(0,4fr)', `${card({ title: '1 · إلى من؟', body: audience(2, false) })}${reach({ n: 0, label: 'رحلة العودة 3:00 م · خط شربين · اليوم', sup: 'مشرف واحد', dev: 'لا هواتف' })}`) }), { extra: '' }],
  ['Loading', 'Skeleton rows; the filters and «إشعار جديد» are real.', mini(520, { ...head, body: skeleton('table', { rows: 5, cols: 6 }) })],
  ['Error', 'Plain Arabic and a retry.', mini(520, { ...head, body: errorState({ card: true, title: 'تعذّر تحميل الإشعارات', text: 'لم نستطع جلب السجل. تأكد من اتصالك ثم حاول مرة أخرى.' }) })],
] });

/* ── Phone ──────────────────────────────────────────────────────── */
const rc = (r) => recordCard({ title: `${r.t}${r.urgent ? ` ${badge('عاجل', 'danger')}` : ''}`, sub: r.why ?? r.b, end: state(r.st), fields: [['إلى', r.to], ['المرسل', r.by], ['الموعد', r.when.replace(/(\d+:\d+)/, (m) => ltr(m))], ...(r.st === 'sent' ? [['قرأه', `<b style="font-weight:600">${r.read}</b> من ${r.n}`]] : [])],
  actions: r.st === 'scheduled' ? `${btn('تعديل', { kind: 'secondary', phone: true })}${btn('إلغاء الإرسال', { kind: 'outline', phone: true })}` : '' });
board('AdmNotifyPhone', { row: ROW, w: 390, title: 'Admin web · Notifications · History · Phone', tab: 'لوحة الشركة · الإشعارات · هاتف',
  body: (size) => shellPhone({ size, active: 'notifications', sub: SUB, body: `${recordList({ toolbar: { search: 'ابحث في الإشعارات', filters: ['الكل', 'المُرسلة', 'المجدولة', 'الملغاة', 'الفاشلة'].map((l, i) => ({ label: l, on: !i })) }, cards: H.slice(0, 6).map(rc) })}${btn('اعرض 25 أقدم', { kind: 'outline', phone: true, full: true, icon: 'adown' })}`, bottomBar: btn('إشعار جديد', { icon: 'plus', phone: true, full: true }) }) });
board('AdmNotifyNewPhone', { row: ROW, w: 390, title: 'Admin web · Notifications · New notification · Phone', tab: 'لوحة الشركة · إشعار جديد · هاتف',
  body: (size) => shellPhone({ size, active: 'notifications', title: 'إشعار جديد', back: 'الإشعارات', gap: 16, body: `${card({ phone: true, title: '1 · إلى من؟', body: audience(1, true, { line: 'فارسكور' }) })}
${reach()}
${card({ phone: true, title: '2 · الرسالة', body: message(DRAFT, true, { tpl: 1 }) })}
${card({ phone: true, title: '3 · متى؟', body: when(true, true) })}
${card({ phone: true, title: 'كما يظهر على هاتف الطالب', body: `<div style="display:flex;justify-content:center">${phoneNotif({ ...DRAFT, w: 326 })}</div>` })}`, bottomBar: btn('جدولة الإشعار', { icon: 'clock', phone: true, full: true }) }) });
board('AdmNotifyConfirmPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Notifications · Send confirmation · Phone', tab: 'لوحة الشركة · تأكيد الإرسال · هاتف',
  body: (size) => shellPhone({ size, active: 'notifications', title: 'إشعار جديد', back: 'الإشعارات', body: card({ phone: true, title: '1 · إلى من؟', body: audience(1, true, { line: 'فارسكور' }) }), overlay: scrim(sendDialog(true), 'bottom') }) });
board('AdmNotifyDetailPhone', { row: ROW, w: 390, title: 'Admin web · Notifications · Details · Phone (a page)', tab: 'لوحة الشركة · تفاصيل إشعار · هاتف',
  body: (size) => shellPhone({ size, active: 'notifications', title: H[2].t, back: 'الإشعارات', body: `<div style="display:flex">${state('sent')}</div><section style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px">${details(true)}</section>`, bottomBar: btn('حذف الإشعار', { kind: 'dangerQuiet', icon: 'trash', phone: true, full: true }) }) });
board('AdmNotifyEmptyPhone', { row: ROW, w: 390, title: 'Admin web · Notifications · Empty · Phone', tab: 'لوحة الشركة · الإشعارات · فارغة · هاتف',
  body: (size) => shellPhone({ size, active: 'notifications', body: emptyState({ card: true, phone: true, icon: 'megaphone', title: 'لم يُرسل أي إشعار بعد', text: 'أخبر طلابك بإجازة، أو بتعديل في المواعيد، أو ذكّرهم بالدفع. تختار من يصله، وترى كم طالباً قرأه.', action: btn('اكتب أول إشعار', { icon: 'plus', phone: true, full: true }) }) }) });
void LINES;
