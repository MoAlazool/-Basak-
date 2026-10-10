/** Platform batch · row K: the super admin inside a company (workspace shell). */
import {
  board, shellDesktop, shellPhone, sectionHead, statCard, attentionList, dataTable, recordCard, recordList, scrim, searchBox,
  badge, btn, note, time, ltr, ico, cell2, C, T, R, CARD, FONT, SHADOW,
} from './kit.mjs';
import { COMPANIES, coState, num, onlyBadge, DATE, TOMORROW } from './p-common.mjs';

const W = (o) => shellDesktop({ role: 'workspace', ...o });
const WP = (o) => shellPhone({ role: 'workspace', ...o });
const ATTN = [
  { count: 7, tone: 'warning', title: '7 إيصالات تنتظر المراجعة', sub: 'أقدمها منذ 3 ساعات · واحد منها في آخر محاولة', action: 'راجع الإيصالات', primary: true },
  { count: 2, tone: 'teal', title: 'طالبان نسيا كلمة المرور', sub: 'يظهران أيضاً في طلبات المنصة', action: 'افتح الطلبات' },
  { icon: 'scan', tone: 'danger', title: 'خط شربين بلا مشرف', sub: 'لا أحد يسجّل ركابه عند الصعود', action: 'عيّن مشرفاً' },
  { icon: 'route', tone: 'danger', title: 'خط كفر البطيخ لا يظهر للطلاب', sub: 'تنقصه رحلة ذهاب إلى جامعة دمياط', action: 'أكمل الخط' },
];
const LINES = [['دمياط الجديدة', 168, 124, 118, 'إبراهيم الدسوقي عبد الحميد'], ['الزرقا', 124, 107, 105, 'محمود السيد عبد الغني'], ['شربين', 112, 81, 75, null], ['فارسكور', 96, 71, 68, 'هاني عبد المقصود'], ['كفر سعد', 74, 52, 49, 'سامح فتحي البنا'], ['السرو', 61, 44, 40, 'محمود السيد عبد الغني']];
const nb = (n) => `<span style="font-size:16px;font-weight:600">${n}</span>`;
const todayBody = () => `${note({ tone: 'teal', icon: 'shield', title: 'تعمل هنا كمدير لهذه الشركة', text: 'ترى ما يراه مديرها وتستطيع كل ما يستطيعه. ما تقبله أو تغيّره يصل طلابها فوراً.' })}
<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج منك الآن', { meta: badge('4 أمور', 'neutral') })}${attentionList(ATTN)}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('ركاب الغد', { meta: badge(TOMORROW, 'teal') })}<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px">${statCard({ label: 'الذهاب', icon: 'aup', value: 512, unit: 'راكباً', hint: 'في 7 خطوط' })}${statCard({ label: 'العودة', icon: 'adown', value: 486, unit: 'راكباً', hint: 'من الجامعات' })}</div>${statCard({ label: 'أكّدوا الركوب حتى الآن', icon: 'check', value: 512, unit: `من 718 مشتركاً · ${ltr('71%')}`, bar: 71, hint: `التأكيد مفتوح حتى ${time('6:00', 'ص')}` })}</section>
</div>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('ركاب الغد في كل خط')}${dataTable({ columns: [{ label: 'الخط' }, { label: 'المشتركون', w: 120 }, { label: 'ذهاب', w: 100 }, { label: 'عودة', w: 100 }, { label: 'المشرف', w: 280 }], rows: LINES.map(([n, s, g, b, sup]) => ({ cells: [cell2(n, '', { w: 600 }), `${s}`, nb(g), nb(b), sup ?? badge('بلا مشرف', 'danger')] })) })}</section>`;

/** LOCAL HELPER: the open company switcher — a search box and the companies, the current one ticked. */
const others = [COMPANIES[0], COMPANIES[2], COMPANIES[3], COMPANIES[9], COMPANIES[1], COMPANIES[4], COMPANIES[5]];
const switchRow = (c, i, phone) => `<a href="#" role="option" aria-selected="${i === 0}" style="display:flex;align-items:center;gap:10px;min-height:${phone ? 56 : 48}px;padding:6px 12px;border-radius:${R.control}px;color:${C.ink};background:${i === 0 ? C.tint : i === 1 && !phone ? C.ground : 'transparent'}"><span style="display:flex;color:${i === 0 ? C.teal : C.ink3}">${ico('building', 18)}</span><span style="flex:1;min-width:0"><span style="display:block;${T.small};font-weight:${i === 0 ? 600 : 400};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${c.name}</span><span style="display:block;${T.cap};color:${C.ink3}">${num(c.students)} طالباً</span></span>${c.st !== 'on' ? coState(c) : ''}${i === 0 ? `<span style="display:flex;color:${C.teal}">${ico('check', 18, 2.25)}</span>` : ''}</a>`;
const switcherList = (phone) => `<div role="listbox" aria-label="الشركات" style="display:flex;flex-direction:column;gap:2px">${others.slice(0, phone ? 6 : 7).map((c, i) => switchRow(c, i, phone)).join('')}</div>`;
const fullSearch = (o) => searchBox(o).replace('flex:1;min-width:0;', '').replace('flex:none', 'align-self:stretch');
const switcherPop = () => `<div style="position:absolute;top:44px;inset-inline-start:323px;width:340px;background:${C.surface};border-radius:${R.inner}px;box-shadow:${SHADOW.floating}, 0 0 0 1px ${C.hair};padding:12px;display:flex;flex-direction:column;gap:8px;z-index:20;color:${C.ink}">
${fullSearch({ placeholder: 'ابحث باسم الشركة', state: 'focus', bg: C.surface })}
<div style="${T.cap};color:${C.ink3};padding:4px 12px 0">تبقى في الصفحة نفسها «اليوم» في الشركة التي تختارها</div>
${switcherList(false)}
<a href="#" style="display:flex;align-items:center;gap:8px;height:44px;padding:0 24px;border-top:1px solid ${C.hair};margin:4px -12px -12px;${T.label};font-weight:500;color:${C.teal}"><span style="flex:1">كل الشركات (${COMPANIES.length})</span>${ico('fwd', 16, 2)}</a></div>`;
const sendBtn = btn('إرسال إشعار للطلاب', { kind: 'outline', icon: 'megaphone' });

board('AdmPlatWsToday', { row: 'K', w: 1440, title: 'Admin web · Super admin inside a company · Today', tab: 'إدارة المنصة · داخل شركة · اليوم',
  body: (size) => W({ size, active: 'today', title: 'اليوم', sub: DATE, actions: sendBtn, body: todayBody() }) });
board('AdmPlatWsSwitcher', { row: 'K', w: 1440, title: 'Admin web · Super admin inside a company · Company switcher open', tab: 'إدارة المنصة · داخل شركة · تبديل الشركة',
  body: (size) => W({ size, active: 'today', title: 'اليوم', sub: DATE, actions: sendBtn, body: todayBody(), overlay: switcherPop() }) });

const TEAM = [['أحمد سعيد النورس', 'ahmed@elnawras.example', '14 مارس 2025'], ['هدى سعيد النورس', 'hoda@elnawras.example', '2 سبتمبر 2026']];
const teamSub = 'من يدخل لوحة هذه الشركة. كل مدير يرى كل صفحاتها.';
const teamTable = dataTable({ toolbar: { count: 'مديران' }, columns: [{ label: 'المدير' }, { label: 'البريد الإلكتروني', w: 320 }, { label: 'أُضيف في', w: 180 }], rows: TEAM.map(([n, m, d]) => ({ cells: [cell2(n, '', { w: 600 }), ltr(m), d] })) });
const teamOnly = note({ tone: 'teal', icon: 'shield', title: 'إضافة مدير: لمدير المنصة فقط', text: 'مدير الشركة يرى هذه القائمة للقراءة بلا الزر. الإضافة هنا هي نفسها في «مديرو الشركات» مع الشركة محددة سلفاً؛ والحذف من هناك.' });
const onlyList = `<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('ما يراه مدير المنصة فقط داخل أي شركة')}<div style="${CARD};overflow:hidden">${[
  ['shield', 'مديرو الشركة', 'زر «إضافة مدير»'],
  ['users', 'الطلاب', 'في لوحة الطالب: «عيّن كلمة مرور مؤقتة» و«احذف الحساب نهائياً»'],
  ['building', 'الشريط الداكن', 'العودة إلى المنصة، تبديل الشركة مع البقاء في الصفحة نفسها، وحالة الشركة إن كانت موقوفة'],
].map(([i, a, b], k) => `<div style="display:flex;align-items:center;gap:12px;min-height:60px;padding:8px 20px;${k ? `border-top:1px solid ${C.hair}` : ''}"><span style="display:flex;color:${C.ink2}">${ico(i, 20)}</span><span style="flex:1;min-width:0"><span style="display:block;${T.small};font-weight:500">${a}</span><span style="display:block;${T.label};color:${C.ink2}">${b}</span></span>${onlyBadge}</div>`).join('')}</div></section>`;
board('AdmPlatWsTeam', { row: 'K', w: 1440, title: 'Admin web · Super admin inside a company · Company admins (the control only the super admin sees)', tab: 'إدارة المنصة · داخل شركة · مديرو الشركة',
  body: (size) => W({ size, active: 'team', title: 'مديرو الشركة', sub: teamSub, actions: `${onlyBadge}${btn('إضافة مدير', { icon: 'plus' })}`, body: `${teamOnly}${teamTable}${onlyList}` }) });
const SUS = COMPANIES[9];
const SUSWHO = { name: 'محمد عادل', role: 'مدير المنصة', initial: 'م', company: SUS.name, scope: 'لوحة الشركة' };
board('AdmPlatWsSuspended', { row: 'K', w: 1440, title: 'Admin web · Super admin inside a suspended company', tab: 'إدارة المنصة · داخل شركة موقوفة',
  body: (size) => W({ size, active: 'today', who: SUSWHO, companyState: 'suspended', badges: {}, title: 'اليوم', sub: DATE, body: `
${note({ tone: 'warning', title: 'هذه الشركة موقوفة', text: 'مديروها ومشرفوها لا يدخلون، وطلابها لا يرونها في التطبيق. أنت وحدك تراها. بياناتها كما كانت يوم الإيقاف.', action: btn('أعد تشغيلها من «الشركات»', { kind: 'outline', sm: true, iconEnd: 'fwd' }) })}
<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px;align-items:start">
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج منك الآن')}${attentionList([], { zeroTitle: 'لا شيء يتحرك في شركة موقوفة', zeroSub: 'لا إيصالات جديدة ولا طلبات حتى يُعاد تشغيلها.' })}</section>
<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('ركاب الغد')}<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px">${statCard({ label: 'الذهاب', icon: 'aup', value: 0, unit: 'راكباً' })}${statCard({ label: 'العودة', icon: 'adown', value: 0, unit: 'راكباً' })}</div></section></div>` }) });
board('AdmPlatWsDenied', { row: 'K', w: 1440, title: 'Admin web · A company admin opens a suspended company (what the owner sees)', tab: 'لوحة الشركة · شركة موقوفة',
  body: (size) => `<div data-root dir="rtl" style="${size};background:${C.ground};${FONT};color:${C.ink};display:flex;align-items:center;justify-content:center"><div style="${CARD};width:520px;padding:32px;display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px"><span aria-hidden="true" style="width:56px;height:56px;border-radius:28px;background:${C.warnBg};color:${C.warn};display:flex;align-items:center;justify-content:center;margin-bottom:8px">${ico('power', 26)}</span><h1 style="margin:0;${T.section}">«${SUS.name}» موقوفة الآن</h1><p style="margin:0;${T.small};color:${C.ink2}">أوقفت إدارة المنصة العمل بهذه الشركة مؤقتاً، فلا يمكن فتح لوحتها ولا يراها الطلاب. بياناتك كلها محفوظة. تواصل مع إدارة المنصة لإعادة التشغيل.</p><div style="margin-top:12px">${btn('تسجيل الخروج', { kind: 'secondary', icon: 'logout' })}</div></div></div>` });

board('AdmPlatWsTodayPhone', { row: 'K', w: 390, title: 'Admin web · Super admin inside a company · Today · Phone', tab: 'إدارة المنصة · داخل شركة · هاتف',
  body: (size) => WP({ size, active: 'today', sub: DATE, body: `
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('يحتاج منك الآن', { phone: true, meta: badge('4 أمور', 'neutral') })}${attentionList(ATTN, { phone: true })}</section>
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('ركاب الغد', { phone: true, meta: badge(TOMORROW, 'teal') })}<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px">${statCard({ phone: true, label: 'الذهاب', icon: 'aup', value: 512, unit: 'راكباً' })}${statCard({ phone: true, label: 'العودة', icon: 'adown', value: 486, unit: 'راكباً' })}</div></section>
<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('في كل خط', { phone: true })}${LINES.slice(0, 3).map(([n, s, g, b, sup]) => recordCard({ title: n, sub: `${s} مشتركاً`, stats: [['ذهاب', g], ['عودة', b]], fields: [['المشرف', sup ?? badge('بلا مشرف', 'danger')]] })).join('')}</section>` }) });
board('AdmPlatWsSwitcherPhone', { row: 'K', w: 390, min: 900, title: 'Admin web · Super admin inside a company · Switcher · Phone', tab: 'إدارة المنصة · تبديل الشركة · هاتف',
  body: (size) => WP({ size, active: 'today', sub: DATE, body: `<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('يحتاج منك الآن', { phone: true })}${attentionList(ATTN.slice(0, 3), { phone: true })}</section>`,
    overlay: scrim(`<div role="dialog" aria-modal="true" aria-label="الانتقال إلى شركة أخرى" style="width:100%;background:${C.surface};border-radius:20px 20px 0 0;padding:12px 12px 12px;display:flex;flex-direction:column;gap:10px;box-shadow:${SHADOW.floating}"><div style="display:flex;align-items:center;padding-inline-start:4px"><h2 style="margin:0;${T.card};flex:1">الانتقال إلى شركة أخرى</h2><button type="button" aria-label="إغلاق" style="width:48px;height:48px;display:flex;align-items:center;justify-content:center;color:${C.ink}">${ico('x', 20)}</button></div>${fullSearch({ phone: true, placeholder: 'ابحث باسم الشركة', bg: C.ground })}${switcherList(true)}${btn('العودة إلى المنصة', { kind: 'secondary', icon: 'arrowBack', phone: true, full: true })}</div>`, 'bottom') }) });
board('AdmPlatWsTeamPhone', { row: 'K', w: 390, title: 'Admin web · Super admin inside a company · Company admins · Phone', tab: 'إدارة المنصة · داخل شركة · مديرو الشركة · هاتف',
  body: (size) => WP({ size, active: 'team', sub: teamSub, body: `${teamOnly}${recordList({ toolbar: { count: 'مديران' }, cards: TEAM.map(([n, m, d]) => recordCard({ title: n, fields: [['البريد', ltr(m, 'font-size:13px')], ['أُضيف في', d]] })) })}`, bottomBar: `<div style="display:flex;justify-content:center">${onlyBadge}</div>${btn('إضافة مدير', { icon: 'plus', phone: true, full: true })}` }) });
