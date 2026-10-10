/** Platform batch · rows D–E: Companies (table, panel, new company in steps, status changes) and company admins. */
import {
  board, sectionHead, dataTable, recordList, recordCard, sidePanel, infoRows, dialog, scrim, field, fieldRow, formSection, stepper,
  badge, btn, note, emptyState, errorState, skeleton, time, ltr, money, ico, cell2, state, toast, C, T, R, CARD,
} from './kit.mjs';
import {
  P, PP, COMPANIES, LIVE, num, personName, rnd, pick, sheetBoard, frame, mini, dlgTile, tiles, group, checkRow, phonePage, emptyPhone, coState, card, dropFilter,
} from './p-common.mjs';

/* ════ D · Companies ════ */
const coSub = 'كل شركات النقل على المنصة. اضغط شركة لترى حالها، أو ادخل لوحتها لتعمل فيها كأنك مديرها.';
const newBtn = (o = {}) => btn('شركة جديدة', { icon: 'plus', ...o });
const saleCell = (c) => (c.st !== 'on' ? `<span style="color:${C.ink3}">—</span>` : c.sale ? badge('معروض', 'success') : badge('لا شيء معروض', 'warning'));
const payCell = (c) => (c.pay ? `${c.pay}` : badge('لا توجد', 'danger'));
const lineCell = (c) => (c.lines[1] ? `${c.lines[0]} <span style="color:${C.ink3};font-size:12px">من ${c.lines[1]}</span>` : badge('بلا خطوط', 'danger'));
const CUR = COMPANIES.filter((c) => c.st !== 'archived');
const chips = (on = 0) => [{ label: 'الحالية', on: on === 0, count: CUR.length }, { label: 'تعمل', on: on === 1, count: LIVE.length }, { label: 'موقوفة', on: on === 2, count: 2 }, { label: 'مؤرشفة', on: on === 3, count: 3 }];
const COLS = [{ label: 'الشركة', sorted: 'asc' }, { label: 'الحالة', w: 124 }, { label: 'خطوط تعمل', w: 116 }, { label: 'الطلاب', w: 88 }, { label: 'المديرون', w: 92 }, { label: 'وسائل الدفع', w: 112 }, { label: 'معروض للبيع', w: 140 }, { label: '', w: 100, align: 'end' }];
const coRow = (c) => [cell2(c.name, `منذ ${c.since}`, { w: 600 }), coState(c), lineCell(c), num(c.students), `${c.admins}`, payCell(c), saleCell(c), c.st === 'archived' ? '' : btn('ادخل', { kind: 'tonal', sm: true, iconEnd: 'fwd' })];
const coTable = (rows, states = {}, o = {}) => dataTable({
  caption: 'الشركات',
  toolbar: { search: 'ابحث باسم الشركة', filters: chips(o.chip ?? 0), sort: 'بالاسم' },
  columns: COLS, rows: rows.map((c, i) => ({ state: states[i], muted: c.st === 'archived', cells: coRow(c) })),
  pagination: o.pag ?? { from: 1, to: 25, total: CUR.length, page: 1, pages: 2 },
});
const N = COMPANIES[0];
const tile = (k, v) => `<div style="background:${C.ground};border-radius:${R.control}px;padding:8px 12px"><div style="${T.cap};color:${C.ink3}">${k}</div><div style="font-size:18px;line-height:26px;font-weight:600">${v}</div></div>`;
const coPanelBody = (c, phone) => `<div style="display:grid;grid-template-columns:repeat(${phone ? 2 : 4},minmax(0,1fr));gap:8px">${tile('الطلاب', num(c.students))}${tile('اشتراكات نشطة', num(c.subs))}${tile('ركاب الغد', num(c.go))}${tile('إيصالات تنتظر', c.rec)}</div>
${group('هل يستطيع طالب أن يشترك؟', `<div style="display:flex;flex-direction:column">
${checkRow(true, `${c.lines[0]} خطوط تعمل من ${c.lines[1]}`, 'خط «كفر البطيخ» لا يظهر للطلاب: تنقصه رحلة ذهاب')}
${checkRow(true, 'وسيلتا دفع تعملان', 'إنستاباي · محفظة هاتف')}
${checkRow(true, 'الفصل الأول والفصلان معاً معروضان للبيع', 'الفصل الثاني والصيفي موقوفان عن البيع')}
${checkRow(true, `${c.sups} مشرفين`, 'خط «شربين» بلا مشرف')}
</div>`)}
${group('عن الشركة', infoRows([['أُنشئت', c.since], ['رقم التواصل', ltr(c.phone)], ['جهة التواصل', 'خدمة العملاء'], ['المديرون', `أحمد سعيد النورس · هدى سعيد النورس ${btn('اعرضهم', { kind: 'link', sm: true })}`], ['الإيرادات المسجّلة', money(c.rev)]]))}`;
const coPanelFooter = (phone) => `${btn('أوقف الشركة', { kind: 'dangerQuiet', icon: 'power', phone, full: phone })}${phone ? '' : '<span style="flex:1"></span>'}${btn('ادخل إلى الشركة', { iconEnd: 'fwd', phone, full: phone })}`;

board('AdmPlatCompanies', { row: 'D', w: 1440, title: 'Admin web · Platform · Companies · Desktop', tab: 'إدارة المنصة · الشركات',
  body: (size) => P({ size, active: 'p-companies', title: 'الشركات', sub: coSub, actions: newBtn(), body: coTable(CUR.slice(0, 25), { 3: 'hover' }) }) });
board('AdmPlatCompaniesPanel', { row: 'D', w: 1440, h: 1000, title: 'Admin web · Platform · Companies · Company panel', tab: 'إدارة المنصة · شركة',
  body: (size) => P({ size, active: 'p-companies', title: 'الشركات', sub: coSub, actions: newBtn(), body: coTable(CUR.slice(0, 25), { 0: 'open' }),
    overlay: scrim(sidePanel({ w: 520, title: N.name, sub: 'شركة نقل', meta: coState(N), body: coPanelBody(N), footer: coPanelFooter(false) }), 'end') }) });

/* — New company, in steps — */
const STEPS = ['بيانات الشركة', 'مدير الشركة', 'وسيلة الدفع', 'المراجعة والإنشاء'];
const steps = (cur) => STEPS.map((label, i) => ({ label, state: i < cur ? 'done' : i === cur ? 'current' : 'todo' }));
const wizard = (cur, inner, o = {}) => `<div style="${CARD};padding:16px 24px">${stepper({ steps: steps(cur) })}</div>
${inner}
<div style="display:flex;align-items:center;gap:8px">${btn('إلغاء', { kind: 'link' })}<span style="${T.label};color:${C.ink3}">لا يُحفظ شيء قبل الخطوة الأخيرة</span><span style="flex:1"></span>${cur ? btn('السابق', { kind: 'secondary', icon: 'arrowBack' }) : ''}${cur === 3 ? btn('أنشئ الشركة', { icon: 'check', state: o.busy ? 'loading' : undefined }) : btn(`التالي: ${STEPS[cur + 1]}`, { iconEnd: 'arrowFwd' })}</div>`;
const wizPage = (size, cur, inner, o = {}) => P({ size, active: 'p-companies', breadcrumb: ['الشركات', 'شركة جديدة'], title: 'شركة جديدة', back: 'الشركات', sub: 'أربع خطوات قصيرة. تُنشأ الشركة ومديرها ووسيلة دفعها معاً في آخر خطوة، أو لا يُنشأ شيء.', body: wizard(cur, inner, o), overlay: o.overlay });
const step1 = (phone, o = {}) => formSection({ phone, title: 'بيانات الشركة', help: 'الاسم الذي يراه الطلاب في التطبيق وعلى بطاقاتهم وإيصالاتهم. الشعار والألوان يضبطها مدير الشركة لاحقاً من «بطاقة الطالب».', body: `
${field({ phone, label: 'اسم الشركة', value: o.err ? 'ا' : 'الصفوة للرحلات', error: o.err ? 'اكتب اسم الشركة كاملاً (حرفان على الأقل).' : undefined, placeholder: 'مثال: باصات النيل' })}
${fieldRow([field({ phone, type: 'tel', label: 'رقم التواصل', optional: true, value: '010 4471 2256', help: 'يظهر للطلاب على بطاقة الطالب.' }), field({ phone, label: 'اسم جهة التواصل', optional: true, value: 'خدمة العملاء', placeholder: 'مثال: خدمة العملاء' })], { phone })}` });
const step2 = (phone, mode = 'invite') => formSection({ phone, title: 'مدير الشركة الأول', help: 'صاحب الشركة أو من يديرها. يدخل اللوحة ببريده، ويستطيع بعدها أن يعمل وحده. تضيف مديرين آخرين من «مديرو الشركات».', body: `
${field({ phone, label: 'اسم مدير الشركة', value: 'كريم حسن الشناوي' })}
${field({ phone, label: 'البريد الإلكتروني', ltr: true, value: 'karim@elsafwa-trips.example', help: 'به يسجّل الدخول. تأكد منه حرفاً حرفاً.' })}
${field({ phone, type: 'radio', label: 'كيف يحصل على كلمة المرور؟', cols: 2, options: [
    { label: 'أرسل له دعوة بالبريد', sub: 'يفتح الرابط ويختار كلمة المرور بنفسه', on: mode === 'invite' },
    { label: 'أكتب كلمة مرور مبدئية الآن', sub: 'تسلّمها له بنفسك', on: mode === 'password' }] })}
${mode === 'password' ? field({ phone, type: 'password', label: 'كلمة المرور المبدئية', value: 'x', help: '8 أحرف على الأقل. لا يمكن عرضها بعد الإنشاء.' }) : ''}` });
const PAY = { later: 'لاحقاً', instapay: 'إنستاباي', wallet: 'محفظة هاتف', bank: 'حساب بنكي' };
const step3 = (phone, type = 'instapay') => formSection({ phone, title: 'وسيلة الدفع الأولى', help: 'الحساب الذي يحوّل عليه الطلاب ثمن الاشتراك. بدون وسيلة دفع لا يستطيع أي طالب أن يدفع لهذه الشركة. يمكن تركها للمدير.', body: `
${field({ phone, type: 'radio', label: 'النوع', cols: 4, options: Object.entries(PAY).map(([k, label]) => ({ label, sub: k === 'later' ? 'يضيفها المدير' : undefined, on: k === type })) })}
${type === 'later' ? note({ tone: 'warning', title: 'ستُنشأ الشركة بلا وسيلة دفع', text: 'يظهر لمديرها في صفحة «اليوم» أن هذه أول خطوة عليه، وتظهر لك في «يحتاج قرارك» حتى يضيفها.' }) : `
${fieldRow([field({ phone, label: 'الاسم الظاهر للطالب', value: type === 'bank' ? 'حساب الشركة · البنك الأهلي' : type === 'wallet' ? 'محفظة الشركة' : 'إنستاباي الصفوة' }), field({ phone, label: 'اسم صاحب الحساب', optional: true, value: 'كريم حسن الشناوي' })], { phone })}
${type === 'instapay' ? field({ phone, label: 'عنوان إنستاباي', ltr: true, value: 'elsafwa@instapay' }) : ''}
${type === 'wallet' ? field({ phone, type: 'tel', label: 'رقم المحفظة', value: '010 4471', error: 'الرقم ناقص. اكتب 11 رقماً تبدأ بـ 01.' }) : ''}
${type === 'bank' ? `${fieldRow([field({ phone, label: 'اسم البنك', value: 'البنك الأهلي المصري' }), field({ phone, label: 'رقم الحساب', ltr: true, value: '2010 0456 7781 203' })], { phone })}${field({ phone, label: 'رقم الآيبان (IBAN)', optional: true, ltr: true, value: 'EG38 0003 0201 0045 6778 1203 000' })}` : ''}`}` });
const sumRow = (k, v) => [k, v];
const step4 = (phone) => `${formSection({ phone, title: 'ما كتبته', help: 'راجعه قبل الإنشاء. اضغط «تعديل» لتعود إلى خطوته.', body: `
${group('بيانات الشركة', infoRows([sumRow('الاسم', 'الصفوة للرحلات'), sumRow('التواصل', `${ltr('010 4471 2256')} · خدمة العملاء`)]), btn('تعديل', { kind: 'link', sm: true }))}
${group('مدير الشركة', infoRows([sumRow('الاسم', 'كريم حسن الشناوي'), sumRow('البريد', ltr('karim@elsafwa-trips.example')), sumRow('كلمة المرور', 'تصله دعوة بالبريد ليختارها')]), btn('تعديل', { kind: 'link', sm: true }))}
${group('وسيلة الدفع', infoRows([sumRow('النوع', 'إنستاباي · «إنستاباي الصفوة»'), sumRow('العنوان', ltr('elsafwa@instapay'))]), btn('تعديل', { kind: 'link', sm: true }))}` })}
${formSection({ phone, title: 'ما تأخذه الشركة من إعدادات المنصة', help: 'تبدأ الشركة بهذه القيم ثم يغيّرها مديرها متى أراد. تغييرك لـ«الإعدادات الافتراضية» بعد اليوم لا يمس مواعيد فصولها.', body: `
${infoRows([
    ['مواعيد الفصول', `نسخة خاصة بها: الأول ${ltr('20')} سبتمبر – ${ltr('15')} يناير · الثاني ${ltr('7')} فبراير – ${ltr('10')} يونيو · الصيفي ${ltr('1')} يوليو – ${ltr('31')} أغسطس`],
    ['معروض للبيع', 'الفصل الأول والثاني معروضان · الصيفي موقوف حتى يفتحه المدير'],
    ['تأكيد الركوب', `تتبع المنصة: يفتح ${time('2:00', 'م')} ويُقفل ${time('6:00', 'ص')}، تذكير كل ساعتين — حتى يحدد المدير مواعيده`],
    ['بطاقة الطالب', 'التصميم الافتراضي بألوان باصك، حتى يضع المدير شعاره'],
    ['ما لا يُنسخ', 'الخطوط والأسعار والمشرفون: يضيفها المدير، وتظهر له خطوات التجهيز في صفحة «اليوم»'],
  ], { labelW: 136 })}` })}`;

board('AdmPlatCompanyNew1', { row: 'D', w: 1440, title: 'Admin web · Platform · New company · Step 1 · Company', tab: 'إدارة المنصة · شركة جديدة · 1',
  body: (size) => wizPage(size, 0, step1(false)) });
board('AdmPlatCompanyNew2', { row: 'D', w: 1440, title: 'Admin web · Platform · New company · Step 2 · First admin', tab: 'إدارة المنصة · شركة جديدة · 2',
  body: (size) => wizPage(size, 1, step2(false, 'password')) });
board('AdmPlatCompanyNew3', { row: 'D', w: 1440, title: 'Admin web · Platform · New company · Step 3 · Payment method', tab: 'إدارة المنصة · شركة جديدة · 3',
  body: (size) => wizPage(size, 2, step3(false, 'bank')) });
board('AdmPlatCompanyNew4', { row: 'D', w: 1440, title: 'Admin web · Platform · New company · Step 4 · Review and create', tab: 'إدارة المنصة · شركة جديدة · 4',
  body: (size) => wizPage(size, 3, step4(false)) });
const afterSteps = (phone) => stepper({ vertical: true, steps: [
  { state: 'done', label: 'الشركة ومديرها ووسيلة الدفع', sub: 'أُنشئت معاً. أُرسلت الدعوة إلى karim@elsafwa-trips.example' },
  { state: 'current', label: 'أول خط', sub: 'جامعة واحدة على الأقل، محطات، رحلة ذهاب ورحلة عودة، وسعر. بدونه لا يرى الطلاب الشركة.' },
  { state: 'todo', label: 'مشرف', sub: 'من يركب الباص ويسجّل صعود الطلاب. يلزمه خط.' },
] });
const createdBody = (phone) => `<section style="${CARD};padding:${phone ? 16 : 24}px;display:flex;flex-direction:column;gap:16px">
<div style="display:flex;align-items:center;gap:12px"><span aria-hidden="true" style="width:44px;height:44px;border-radius:22px;background:${C.okBg};color:${C.ok};display:flex;align-items:center;justify-content:center;flex:none">${ico('check', 22, 2.25)}</span><div style="min-width:0"><h2 style="margin:0;${phone ? T.card : T.section}">أُنشئت «الصفوة للرحلات»</h2><p style="margin:0;${T.label};color:${C.ink2}">لا يراها الطلاب بعد: ينقصها خط.</p></div></div>
${note({ tone: 'teal', icon: 'mail', title: 'وصلت الدعوة إلى بريد كريم', text: 'يفتح الرابط ويختار كلمة المرور. الرابط صالح 24 ساعة؛ إن لم يصله فاحذف حسابه من «مديرو الشركات» وأضفه من جديد.' })}
<div style="display:flex;flex-direction:column;gap:8px"><div style="${T.small};font-weight:600">ما بقي حتى يشترك أول طالب</div>${afterSteps(phone)}</div>
<p style="margin:0;${T.label};color:${C.ink2}">هذه الخطوات نفسها تظهر لكريم في صفحة «اليوم» عند أول دخول. تستطيع أن تبدأها أنت الآن من داخل لوحة الشركة.</p>
${phone ? '' : `<div style="display:flex;gap:8px;justify-content:flex-end;border-top:1px solid ${C.hair};padding-top:16px">${btn('العودة إلى الشركات', { kind: 'secondary' })}${btn('ادخل إلى الشركة وأضف أول خط', { iconEnd: 'fwd' })}</div>`}
</section>`;
board('AdmPlatCompanyCreated', { row: 'D', w: 1440, title: 'Admin web · Platform · New company · Created · hand-off', tab: 'إدارة المنصة · أُنشئت الشركة',
  body: (size) => P({ size, active: 'p-companies', breadcrumb: ['الشركات', 'الصفوة للرحلات'], title: 'شركة جديدة', back: 'الشركات', body: `<div style="max-width:760px">${createdBody(false)}</div>` }) });

const suspendDlg = (phone) => dialog({ phone, icon: 'power', tone: 'danger', title: `إيقاف «${N.name}»؟`, body: `<span>يفقد مديراها ومشرفوها الـ${N.sups} الدخول فوراً، وتختفي الشركة من تطبيق ${num(N.students)} طالباً: لا تأكيد ركوب ولا اشتراك جديد.</span><span>لا يُحذف شيء: الخطوط والاشتراكات والإيصالات تبقى، وتعود كما هي عند إعادة التشغيل.</span>`,
  actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('أوقف الشركة', { kind: 'danger', phone, full: phone })] });
const archiveDlg = dialog({ icon: 'trash', tone: 'danger', title: 'أرشفة «الهدى للنقل»؟', body: `<span>تُخفى من قائمة الشركات الحالية ومن كل قوائم الاختيار، ويبقى العمل بها متوقفاً. تجدها بعد ذلك تحت «مؤرشفة».</span><span>لا يُحذف شيء، ويمكن إعادة تشغيلها في أي وقت.</span>`, actions: [btn('رجوع', { kind: 'secondary' }), btn('أرشف الشركة', { kind: 'danger' })] });
const reactDlg = dialog({ icon: 'power', tone: 'success', title: 'إعادة تشغيل «الهدى للنقل»؟', body: `<span>يعود مديرها ومشرفوها إلى الدخول، وتظهر للطلاب من جديد بخطوطها الـ4 واشتراكاتها كما كانت يوم الإيقاف.</span>`, actions: [btn('رجوع', { kind: 'secondary' }), btn('أعد تشغيل الشركة')] });
const discardDlg = dialog({ icon: 'alert', tone: 'warning', title: 'ترك إنشاء الشركة؟', body: `<span>لم تُنشأ «الصفوة للرحلات» بعد. إن خرجت الآن يضيع ما كتبته في الخطوات الثلاث.</span>`, actions: [btn('أكمل الإنشاء', { kind: 'secondary' }), btn('اترك ولا تحفظ', { kind: 'danger' })] });
const SUSP = COMPANIES.find((c) => c.st === 'suspended');
sheetBoard('AdmPlatCompaniesDialogs', 'D', 'Companies · Status changes, step variants and failures', [
  tiles([
    dlgTile('Suspend', 'From the panel of a working company. Real counts; nothing is deleted.', suspendDlg(false)),
    dlgTile('Reactivate', 'From a suspended or an archived company.', reactDlg),
    dlgTile('Archive', 'Only a suspended company can be archived (as today).', archiveDlg),
    dlgTile('Leaving the steps', 'Closing or «إلغاء» after anything was typed asks first.', discardDlg),
  ]),
  frame('Panel of a suspended company', 'The panel footer changes with the status: archive at the start, reactivate at the end. The super admin can still enter.', `<div dir="rtl" style="background:#8FA0AB;display:flex;justify-content:flex-end;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${sidePanel({ w: 520, title: SUSP.name, sub: 'شركة نقل', meta: coState(SUSP), body: `${note({ tone: 'warning', title: 'موقوفة منذ 2 أكتوبر 2026', text: 'مديروها ومشرفوها لا يدخلون، ولا يراها الطلاب. بياناتها كما هي.' })}${group('عن الشركة', infoRows([['أُنشئت', SUSP.since], ['الطلاب', num(SUSP.students)], ['الخطوط', `${SUSP.lines[1]}`], ['المديرون', `${SUSP.admins}`]]))}`, footer: `${btn('أرشف الشركة', { kind: 'dangerQuiet' })}${btn('ادخل', { kind: 'secondary' })}<span style="flex:1"></span>${btn('أعد تشغيل الشركة', { icon: 'power' })}` })}</div>`, { w: 720 }),
  frame('Step 1 · error under the field', 'Errors sit under the field that caused them; «التالي» stays where it is.', `<div dir="rtl" style="background:${C.ground};padding:24px;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${step1(false, { err: true })}</div>`),
  frame('Step 2 · invitation by e-mail', 'The other choice of the same step: no password field at all.', `<div dir="rtl" style="background:${C.ground};padding:24px;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${step2(false, 'invite')}</div>`),
  frame('Step 3 · InstaPay', 'One address field.', `<div dir="rtl" style="background:${C.ground};padding:24px;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${step3(false, 'instapay')}</div>`),
  frame('Step 3 · phone wallet, with an error', '11 digits starting with 01.', `<div dir="rtl" style="background:${C.ground};padding:24px;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${step3(false, 'wallet')}</div>`),
  frame('Step 3 · later', 'Skipping is allowed and says what follows.', `<div dir="rtl" style="background:${C.ground};padding:24px;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${step3(false, 'later')}</div>`),
  frame('Step 4 · creation failed', 'Nothing was created. The message names the field to fix and the steps keep what was typed.', `<div dir="rtl" style="background:${C.ground};padding:24px;display:flex;flex-direction:column;gap:16px;font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif;color:${C.ink}">${note({ tone: 'danger', title: 'لم تُنشأ الشركة', text: 'البريد karim@elsafwa-trips.example مستعمل لحساب آخر. غيّره في خطوة «مدير الشركة» ثم حاول مرة أخرى.', action: btn('عدّل البريد', { kind: 'outline', sm: true }) })}${note({ tone: 'danger', title: 'لم تُنشأ الشركة', text: 'انقطع الاتصال قبل أن يكتمل الإنشاء. لم يُحفظ شيء؛ ما كتبته ما زال هنا.', action: btn('حاول مرة أخرى', { kind: 'outline', sm: true, icon: 'refresh' }) })}</div>`),
]);
sheetBoard('AdmPlatCompaniesStates', 'D', 'Companies · States', [
  frame('Empty · first use', 'What the page is for, and the one button that fills it.', mini(520, { active: 'p-companies', title: 'الشركات', sub: coSub, badges: {}, body: emptyState({ card: true, icon: 'building', title: 'لا شركات بعد', text: 'الشركة هي صاحب الباصات: لها خطوطها وطلابها ومديروها. أنشئ الأولى باسمها ومديرها، وهو يكمل الباقي.', action: newBtn() }) })),
  frame('Filter with no match', 'A filter that matches nothing says so and offers the way back; it never looks like an empty platform.', mini(440, { active: 'p-companies', title: 'الشركات', sub: coSub, actions: newBtn(), body: dataTable({ columns: [], rows: [], toolbar: { search: 'ابحث باسم الشركة', searchValue: 'الزهراء', filters: chips(0) }, empty: emptyState({ icon: 'search', title: 'لا شركة بهذا الاسم', text: 'لا توجد شركة حالية اسمها يشبه «الزهراء». جرّب جزءاً من الاسم، أو ابحث في المؤرشفة.', action: btn('امسح البحث', { kind: 'secondary' }) }) }) })),
  frame('One company', '', mini(400, { active: 'p-companies', title: 'الشركات', sub: coSub, actions: newBtn(), body: dataTable({ columns: COLS, toolbar: { search: 'ابحث باسم الشركة', count: 'شركة واحدة' }, rows: [{ cells: coRow(N) }] }) })),
  frame('Loading', '', mini(460, { active: 'p-companies', title: 'الشركات', sub: coSub, actions: newBtn(), body: skeleton('table', { rows: 5, cols: 7 }) })),
  frame('Error', '', mini(480, { active: 'p-companies', title: 'الشركات', sub: coSub, body: errorState({ card: true, title: 'تعذّر تحميل الشركات', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
const coCard = (c) => recordCard({ title: c.name, sub: `منذ ${c.since}`, end: coState(c), stats: [['الطلاب', num(c.students)], ['خطوط تعمل', c.lines[1] ? `${c.lines[0]}/${c.lines[1]}` : '0']], fields: [['المديرون', `${c.admins}`], ['وسائل الدفع', payCell(c)], ['معروض للبيع', saleCell(c)]] });
board('AdmPlatCompaniesPhone', { row: 'D', w: 390, title: 'Admin web · Platform · Companies · Phone', tab: 'إدارة المنصة · الشركات · هاتف',
  body: (size) => PP({ size, active: 'p-companies', sub: coSub, body: recordList({ toolbar: { search: 'ابحث باسم الشركة', filters: chips(0), sort: 'بالاسم', count: `${CUR.length} شركة` }, cards: CUR.slice(0, 6).map(coCard), pagination: { from: 1, to: 25, total: CUR.length, page: 1, pages: 2 } }), bottomBar: newBtn({ phone: true, full: true }) }) });
board('AdmPlatCompanyPhone', { row: 'D', w: 390, title: 'Admin web · Platform · Company · Phone page', tab: 'إدارة المنصة · شركة · هاتف',
  body: (size) => phonePage({ size, active: 'p-companies', back: 'الشركات', title: N.name, body: `<div>${coState(N)}</div>${coPanelBody(N, true)}`, bottomBar: `${btn('ادخل إلى الشركة', { iconEnd: 'fwd', phone: true, full: true })}${btn('أوقف الشركة', { kind: 'dangerQuiet', icon: 'power', phone: true, full: true })}` }) });
const wizPhone = (file, cur, inner, title) => board(file, { row: 'D', w: 390, title: `Admin web · Platform · New company · ${title} · Phone`, tab: 'إدارة المنصة · شركة جديدة · هاتف',
  body: (size) => phonePage({ size, active: 'p-companies', back: 'الشركات', title: 'شركة جديدة', body: `${stepper({ phone: true, steps: steps(cur) })}${inner}`, bottomBar: `${cur === 3 ? btn('أنشئ الشركة', { icon: 'check', phone: true, full: true }) : btn(`التالي: ${STEPS[cur + 1]}`, { phone: true, full: true })}${cur ? btn('السابق', { kind: 'secondary', phone: true, full: true }) : ''}` }) });
wizPhone('AdmPlatCompanyNew2Phone', 1, step2(true, 'invite'), 'Step 2');
wizPhone('AdmPlatCompanyNew3Phone', 2, step3(true, 'instapay'), 'Step 3');
wizPhone('AdmPlatCompanyNew4Phone', 3, step4(true), 'Step 4');
board('AdmPlatCompanyCreatedPhone', { row: 'D', w: 390, title: 'Admin web · Platform · New company · Created · Phone', tab: 'إدارة المنصة · أُنشئت الشركة · هاتف',
  body: (size) => phonePage({ size, active: 'p-companies', back: 'الشركات', title: 'شركة جديدة', body: createdBody(true), bottomBar: `${btn('ادخل وأضف أول خط', { iconEnd: 'fwd', phone: true, full: true })}${btn('العودة إلى الشركات', { kind: 'secondary', phone: true, full: true })}` }) });
board('AdmPlatCompanySuspendPhone', { row: 'D', w: 390, min: 844, title: 'Admin web · Platform · Company · Suspend · Phone', tab: 'إدارة المنصة · إيقاف شركة · هاتف',
  body: (size) => phonePage({ size, active: 'p-companies', back: 'الشركات', title: N.name, body: `<div>${coState(N)}</div>${coPanelBody(N, true).split('\n')[0]}`, overlay: scrim(suspendDlg(true), 'bottom') }) });
emptyPhone('AdmPlatCompaniesEmptyPhone', 'D', 'Companies', 'p-companies', { sub: coSub, empty: { icon: 'building', title: 'لا شركات بعد', text: 'الشركة هي صاحب الباصات: لها خطوطها وطلابها ومديروها. أنشئ الأولى باسمها ومديرها، وهو يكمل الباقي.', action: newBtn({ phone: true, full: true }) } });

/* ════ E · Company admins ════ */
const adSub = 'كل من يدخل لوحة شركة. كل مدير يتبع شركة واحدة ويرى كل صفحاتها.';
const addBtn = (o = {}) => btn('إضافة مدير', { icon: 'plus', ...o });
const mail = (n, i) => i < 3 ? ['ahmed@elnawras.example', 'hoda@elnawras.example', 'karim@elsafwa-trips.example'][i] : `${['info', 'admin', 'office', 'manager', 'owner'][i % 5]}${i > 4 ? i : ''}@${['elnawras', 'elsafwa-trips', 'nilebuses', 'elfayrouz', 'deltalines', 'elrayan'][i % 6]}.example`;
const ADM = [{ n: 'أحمد سعيد النورس', co: 'النورس للنقل', at: '14 مارس 2025', st: 'in' }, { n: 'هدى سعيد النورس', co: 'النورس للنقل', at: '2 سبتمبر 2026', st: 'in' }, { n: 'كريم حسن الشناوي', co: 'الصفوة للرحلات', at: 'اليوم', st: 'invited' },
  ...Array.from({ length: 22 }, (_, i) => ({ n: personName(), co: i === 7 ? null : COMPANIES[(i * 3 + 2) % 27].name, at: `${rnd(1, 28)} ${['يناير', 'مارس', 'مايو', 'يوليو', 'سبتمبر'][i % 5]} ${i % 3 ? 2026 : 2025}`, st: 'in' }))];
const adCo = (a) => (a.co ? a.co : `<span style="display:inline-flex;align-items:center;gap:8px">الهدى للنقل ${state('suspended')}</span>`);
const adCols = [{ label: 'المدير' }, { label: 'البريد الإلكتروني', w: 300 }, { label: 'الشركة', w: 260 }, { label: 'أُضيف في', w: 150, sorted: 'desc' }, { label: '', w: 100, align: 'end' }];
const adRow = (a, i) => [cell2(a.n, a.st === 'invited' ? 'أُرسلت له دعوة ولم يدخل بعد' : '', { w: 600 }), ltr(mail(a.n, i)), adCo(a), a.at, btn('احذف', { kind: 'outline', sm: true, icon: 'trash' })];
const adTable = (rows, states = {}) => dataTable({ caption: 'مديرو الشركات', toolbar: { search: 'ابحث بالاسم أو البريد', actions: dropFilter('كل الشركات', { icon: 'building' }), count: '38 مديراً في 28 شركة', sort: 'الأحدث أولاً' }, columns: adCols,
  rows: rows.map((a, i) => ({ state: states[i], cells: adRow(a, i) })), pagination: { from: 1, to: 25, total: 38, page: 1, pages: 2 } });
const addForm = (phone, mode = 'invite') => `${field({ phone, type: 'select', label: 'الشركة', value: 'الصفوة للرحلات', help: 'الشركات التي تعمل فقط. لا يمكن نقل المدير إلى شركة أخرى بعد الإضافة.' })}
${field({ phone, label: 'اسم المدير', placeholder: 'الاسم بالكامل', value: 'منى حسن الشناوي' })}
${field({ phone, label: 'البريد الإلكتروني', ltr: true, value: 'mona@elsafwa-trips.example', help: 'به يسجّل الدخول.' })}
${field({ phone, type: 'radio', label: 'كيف يحصل على كلمة المرور؟', cols: 1, options: [{ label: 'أرسل له دعوة بالبريد', sub: 'يفتح الرابط ويختار كلمة المرور بنفسه', on: mode === 'invite' }, { label: 'أكتب كلمة مرور الآن', sub: '8 أحرف على الأقل، تسلّمها له بنفسك', on: mode === 'password' }] })}
${mode === 'password' ? field({ phone, type: 'password', label: 'كلمة المرور', value: 'x', help: 'تُحفظ مشفّرة ولا يمكن عرضها بعد الإضافة.' }) : ''}
${note({ tone: 'teal', title: 'يرى كل شيء في شركته', text: 'الإيصالات والطلاب والخطوط والإيرادات والإعدادات. لا يرى أي شركة أخرى ولا صفحات المنصة.' })}`;
const delDlg = (phone) => dialog({ phone, icon: 'trash', tone: 'danger', title: 'حذف المدير هدى سعيد النورس؟', body: `<span>يُحذف حساب دخولها نهائياً ولن تستطيع فتح لوحة «النورس للنقل». لا رجوع عن الحذف؛ لإعادتها تضيفها من جديد.</span><span>يبقى للشركة مدير واحد: أحمد سعيد النورس. لا يتغيّر شيء في بيانات الشركة.</span>`, actions: [btn('رجوع', { kind: 'secondary', phone, full: phone }), btn('احذف المدير', { kind: 'danger', phone, full: phone })] });

board('AdmPlatAdmins', { row: 'E', w: 1440, title: 'Admin web · Platform · Company admins · Desktop', tab: 'إدارة المنصة · مديرو الشركات',
  body: (size) => P({ size, active: 'p-admins', title: 'مديرو الشركات', sub: adSub, actions: addBtn(), body: adTable(ADM, { 2: 'hover' }) }) });
board('AdmPlatAdminsAdd', { row: 'E', w: 1440, h: 1000, title: 'Admin web · Platform · Company admins · Add (panel)', tab: 'إدارة المنصة · إضافة مدير',
  body: (size) => P({ size, active: 'p-admins', title: 'مديرو الشركات', sub: adSub, actions: addBtn(), body: adTable(ADM),
    overlay: scrim(sidePanel({ title: 'إضافة مدير شركة', sub: 'حساب جديد يدخل لوحة شركة واحدة', body: addForm(false, 'password'), footer: `${btn('إلغاء', { kind: 'secondary' })}<span style="flex:1"></span>${btn('أنشئ الحساب', { icon: 'key' })}` }), 'end') }) });
sheetBoard('AdmPlatAdminsStates', 'E', 'Company admins · Dialogs and states', [
  tiles([
    dlgTile('Delete an admin', 'The only change the code allows after creation. Says what is left for the company.', delDlg(false)),
    dlgTile('Deleting the last admin', 'Allowed today; the dialog says the company is left with nobody.', dialog({ icon: 'alert', tone: 'danger', title: 'حذف المدير الوحيد للصفوة للرحلات؟', body: `<span>كريم حسن الشناوي هو مديرها الوحيد. بعد حذفه لا يستطيع أحد من الشركة دخول لوحتها حتى تضيف مديراً آخر. الشركة نفسها تبقى تعمل عند الطلاب.</span>`, actions: [btn('رجوع', { kind: 'secondary' }), btn('احذف المدير', { kind: 'danger' })] })),
    dlgTile('After adding', 'Two outcomes, each says what the admin must do next.', `<div style="display:flex;flex-direction:column;gap:12px">${toast({ text: 'أُرسلت الدعوة إلى بريد منى. تختار كلمة المرور من الرابط.', w: 460 })}${toast({ text: 'أُنشئ حساب منى. تدخل الآن بالبريد وكلمة المرور.', w: 460 })}${toast({ tone: 'danger', text: 'هذا البريد مستعمل لحساب آخر. اكتب بريداً مختلفاً.', w: 460 })}</div>`, { w: 560, h: 280 }),
    dlgTile('Delete · phone', '', delDlg(true), { phone: true, h: 500 }),
  ]),
  frame('Empty', 'No admin yet. Needs a working company first; when none exists the button leads there.', mini(500, { active: 'p-admins', title: 'مديرو الشركات', sub: adSub, body: emptyState({ card: true, icon: 'shield', title: 'لا مديرين بعد', text: 'يُضاف أول مدير مع شركته في «شركة جديدة». من هنا تضيف مديراً ثانياً لشركة قائمة، أو تحذف من ترك العمل.', action: `${btn('شركة جديدة', { kind: 'secondary', icon: 'plus' })}${addBtn()}` }) })),
  frame('No working company', 'The add panel cannot open: nothing to attach an admin to.', mini(360, { active: 'p-admins', title: 'مديرو الشركات', sub: adSub, actions: btn('إضافة مدير', { icon: 'plus', state: 'disabled' }), body: note({ tone: 'warning', title: 'لا توجد شركة تعمل', text: 'أضف شركة أو أعد تشغيل شركة موقوفة، ثم أضف مديرها.', action: btn('افتح الشركات', { kind: 'outline', sm: true }) }) })),
  frame('Loading', '', mini(420, { active: 'p-admins', title: 'مديرو الشركات', sub: adSub, actions: addBtn(), body: skeleton('table', { rows: 4, cols: 4 }) })),
  frame('Error', '', mini(460, { active: 'p-admins', title: 'مديرو الشركات', sub: adSub, body: errorState({ card: true, title: 'تعذّر تحميل المديرين', text: 'تأكد من اتصالك ثم حاول مرة أخرى.' }) })),
]);
board('AdmPlatAdminsPhone', { row: 'E', w: 390, title: 'Admin web · Platform · Company admins · Phone', tab: 'إدارة المنصة · مديرو الشركات · هاتف',
  body: (size) => PP({ size, active: 'p-admins', sub: adSub, body: recordList({ toolbar: { search: 'ابحث بالاسم أو البريد', count: '38 مديراً في 28 شركة', sort: 'الأحدث أولاً' },
    cards: ADM.slice(0, 6).map((a, i) => recordCard({ title: a.n, sub: a.st === 'invited' ? 'أُرسلت له دعوة ولم يدخل بعد' : '', fields: [['البريد', ltr(mail(a.n, i), 'font-size:13px')], ['الشركة', adCo(a)], ['أُضيف في', a.at]], actions: btn('احذف المدير', { kind: 'outline', sm: true, icon: 'trash', extra: 'height:44px;' }) })), pagination: { from: 1, to: 25, total: 38, page: 1, pages: 2 } }), bottomBar: addBtn({ phone: true, full: true }) }) });
board('AdmPlatAdminsAddPhone', { row: 'E', w: 390, title: 'Admin web · Platform · Company admins · Add · Phone page', tab: 'إدارة المنصة · إضافة مدير · هاتف',
  body: (size) => phonePage({ size, active: 'p-admins', back: 'مديرو الشركات', title: 'إضافة مدير شركة', body: `<div style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px">${addForm(true, 'invite')}</div>`, bottomBar: btn('أرسل الدعوة', { icon: 'mail', phone: true, full: true }) }) });
emptyPhone('AdmPlatAdminsEmptyPhone', 'E', 'Company admins', 'p-admins', { sub: adSub, empty: { icon: 'shield', title: 'لا مديرين بعد', text: 'يُضاف أول مدير مع شركته في «شركة جديدة». من هنا تضيف مديراً ثانياً لشركة قائمة.', action: addBtn({ phone: true, full: true }) } });
