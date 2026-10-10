import { board, shellDesktop, shellTablet, shellPhone, navDrawerPhone, btn, C, T, R } from './kit.mjs';

/** A neutral content slot: says what goes there and how many columns it takes. */
const slot = (label, h, extra = '') => `<div style="height:${h}px;border-radius:${R.card}px;border:1.5px dashed ${C.disabled};display:flex;align-items:center;justify-content:center;text-align:center;padding:0 12px;${T.label};color:${C.ink3};${extra}">${label}</div>`;
const cols = (n, gap) => `<div aria-hidden="true" style="display:grid;grid-template-columns:repeat(${n},minmax(0,1fr));gap:${gap}px;height:28px">${Array.from({ length: n }, (_, i) => `<span style="background:${C.tint};border-radius:6px;font-size:12px;line-height:28px;text-align:center;color:${C.teal}">${i + 1}</span>`).join('')}</div>`;

const neutralDesk = `${cols(12, 24)}
<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:24px">${['بطاقة رقم · 3 أعمدة', 'بطاقة رقم · 3 أعمدة', 'بطاقة رقم · 3 أعمدة', 'بطاقة رقم · 3 أعمدة'].map((l) => slot(l, 108)).join('')}</div>
<div style="display:grid;grid-template-columns:minmax(0,8fr) minmax(0,4fr);gap:24px">${slot('المحتوى الأساسي · 8 أعمدة<br>جدول، قائمة، أو أقسام نموذج', 360)}${slot('محتوى مساند · 4 أعمدة', 360)}</div>`;
const actions = `${btn('إجراء ثانوي', { kind: 'outline' })}${btn('الإجراء الأساسي', { icon: 'plus' })}`;
const SUB = 'جملة واحدة تقول ما الذي تفعله في هذه الصفحة.';

board('AdmShell', { row: 'B', w: 1440, min: 972, title: 'Admin web · Shell · Desktop', tab: 'لوحة الشركة · الهيكل',
  body: (size) => shellDesktop({ size, active: 'students', title: 'الطلاب', sub: SUB, actions, body: neutralDesk }) });

board('AdmShellTablet', { row: 'B', w: 834, min: 1112, title: 'Admin web · Shell · Tablet', tab: 'لوحة الشركة · الهيكل · لوحي',
  body: (size) => shellTablet({ size, active: 'students', tip: 'receipts', title: 'الطلاب', sub: SUB, actions, body: `${cols(8, 16)}
<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px">${[1, 2, 3, 4].map(() => slot('بطاقة رقم · 4 أعمدة', 100)).join('')}</div>
${slot('المحتوى الأساسي · 8 أعمدة<br>الجدول يحتفظ بأهم أعمدته فقط', 360)}
${slot('المحتوى المساند ينزل تحت الأساسي', 160)}` }) });

const neutralPhone = `${cols(4, 16)}
<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px">${slot('بطاقة رقم', 88)}${slot('بطاقة رقم', 88)}</div>
${slot('عمود واحد<br>صفوف الجدول تصير بطاقات', 300)}
${slot('المحتوى المساند', 120)}`;
board('AdmShellPhone', { row: 'B', w: 390, title: 'Admin web · Shell · Phone', tab: 'لوحة الشركة · الهيكل · هاتف',
  body: (size) => shellPhone({ size, active: 'students', sub: SUB, body: neutralPhone, bottomBar: btn('الإجراء الأساسي', { phone: true, full: true }) }) });

board('AdmShellPhoneMenu', { row: 'B', w: 390, min: 1110, title: 'Admin web · Shell · Phone · Menu open', tab: 'لوحة الشركة · القائمة',
  body: (size) => shellPhone({ size, active: 'students', sub: SUB, body: neutralPhone, overlay: navDrawerPhone({ active: 'students' }) }) });

board('AdmShellPlatform', { row: 'B', w: 1440, min: 972, title: 'Admin web · Shell · Platform (super admin)', tab: 'إدارة المنصة · الهيكل',
  body: (size) => shellDesktop({ size, role: 'platform', active: 'p-companies', title: 'الشركات', sub: SUB, actions, body: neutralDesk }) });

board('AdmShellWorkspace', { row: 'B', w: 1440, min: 972, title: 'Admin web · Shell · Super admin inside a company', tab: 'إدارة المنصة · داخل شركة',
  body: (size) => shellDesktop({ size, role: 'workspace', active: 'students', title: 'الطلاب', sub: SUB, actions, body: neutralDesk }) });
