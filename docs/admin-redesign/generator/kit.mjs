/**
 * Basak admin WEB kit — shared partials for every admin artboard.
 * Read build2/README.md first. Every function returns an HTML string with inline styles.
 * Options named `phone: true` switch a part to its phone-web form (< 640).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const OUT = path.join(here, '..', 'project');
export const MEASURE = path.join(here, 'measure');

/* ══ Tokens (the mobile app's, exactly) ═════════════════════════════ */
export const C = {
  ink: '#17384A', teal: '#00658D', tealPressed: '#004F6E', tealHover: '#005A7E',
  ground: '#F0F5F8', surface: '#FFFFFF', sunken: '#E4ECF1', hair: '#DCE6EC',
  ink2: '#476273', ink3: '#58707F', disabled: '#9DB0BB', tint: '#E5F3FA',
  ok: '#0A6B4A', okBg: '#E3F4EC', warn: '#8A5300', warnBg: '#FCF1DC',
  bad: '#B3261E', badBg: '#FCEBE9', badge: '#C8372D',
};
export const FONT = "font-family:'Readex Pro','Segoe UI',Tahoma,sans-serif";
export const SHADOW = { card: '0 1px 2px rgba(23,56,74,.05)', floating: '0 16px 40px -12px rgba(23,56,74,.28)' };
export const R = { control: 10, card: 16, inner: 14, dialog: 20 };
/** Web type scale. */
export const T = {
  page: 'font-size:28px;line-height:36px;font-weight:600',
  pagePhone: 'font-size:22px;line-height:30px;font-weight:600',
  section: 'font-size:18px;line-height:26px;font-weight:600',
  card: 'font-size:16px;line-height:24px;font-weight:600',
  body: 'font-size:15px;line-height:24px',
  small: 'font-size:14px;line-height:22px',
  label: 'font-size:13px;line-height:20px',
  cap: 'font-size:12px;line-height:18px',
  num: 'font-size:32px;line-height:40px;font-weight:600',
};
export const CARD = `background:${C.surface};border-radius:${R.card}px;box-shadow:${SHADOW.card}`;
export const FOCUS = `box-shadow:0 0 0 2px ${C.surface}, 0 0 0 4px ${C.teal}`;
const ELL = 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis';

/* ══ Icons (inline stroke SVG, 24 box) ══════════════════════════════ */
const P = {
  home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"></path>',
  receipt: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"></path><path d="M9 8h6M9 12h6"></path>',
  route: '<circle cx="6" cy="19" r="3"></circle><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"></path><circle cx="18" cy="5" r="3"></circle>',
  key: '<circle cx="7.5" cy="15.5" r="5.5"></circle><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"></path>',
  user: '<circle cx="12" cy="8" r="4"></circle><path d="M4 21a8 8 0 0 1 16 0"></path>',
  users: '<circle cx="9" cy="8" r="4"></circle><path d="M2 21a7 7 0 0 1 14 0M16 4.1a4 4 0 0 1 0 7.8M22 21a7 7 0 0 0-4-6.3"></path>',
  scan: '<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2M7 12h10"></path>',
  megaphone: '<path d="m3 11 18-5v12L3 14v-3zM11.6 16.8a3 3 0 1 1-5.8-1.6"></path>',
  card: '<rect x="2" y="5" width="20" height="14" rx="3"></rect><path d="M2 10h20"></path>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"></path>',
  calendar: '<rect x="3" y="4" width="18" height="18" rx="3"></rect><path d="M3 10h18M8 2v4M16 2v4"></path>',
  clock: '<circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path>',
  idcard: '<rect x="3" y="4" width="18" height="16" rx="3"></rect><circle cx="9" cy="11" r="2.5"></circle><path d="M5.5 17a3.5 3.5 0 0 1 7 0M15 9h3M15 13h3"></path>',
  building: '<path d="M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16M16 9h2a2 2 0 0 1 2 2v10M2 21h20M8 7h4M8 11h4M8 15h4"></path>',
  school: '<path d="m2 9 10-5 10 5-10 5zM6 11v5c0 1.5 3 3 6 3s6-1.500 6-3v-5M22 9v6"></path>',
  sliders: '<path d="M4 6h10M4 12h4M12 12h8M4 18h12"></path><circle cx="16" cy="6" r="2"></circle><circle cx="10" cy="12" r="2"></circle><circle cx="18" cy="18" r="2"></circle>',
  smartphone: '<rect x="6" y="2" width="12" height="20" rx="3"></rect><path d="M11 18h2"></path>',
  shield: '<path d="m12 3 8 3v6c0 5-3.500 8-8 9-4.500-1-8-4-8-9V6z"></path>',
  bus: '<rect x="4" y="3" width="16" height="14" rx="3"></rect><path d="M4 11h16M8 21v-4M16 21v-4M8 14.500h.01M16 14.500h.01"></path>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"></path>',
  search: '<circle cx="11" cy="11" r="7"></circle><path d="m21 21-4.300-4.300"></path>',
  zoom: '<circle cx="11" cy="11" r="7"></circle><path d="m21 21-4.300-4.300M11 8v6M8 11h6"></path>',
  filter: '<path d="M3 5h18l-7 8v6l-4 2v-8z"></path>',
  sort: '<path d="M7 4v16M3 16l4 4 4-4M17 20V4M13 8l4-4 4 4"></path>',
  dots: '<circle cx="12" cy="5" r="1"></circle><circle cx="12" cy="12" r="1"></circle><circle cx="12" cy="19" r="1"></circle>',
  /** fwd = the direction of reading in RTL (points left); back points right. */
  fwd: '<path d="m15 18-6-6 6-6"></path>',
  back: '<path d="m9 18 6-6-6-6"></path>',
  arrowBack: '<path d="M5 12h14M12 5l7 7-7 7"></path>',
  arrowFwd: '<path d="M19 12H5M12 19l-7-7 7-7"></path>',
  down: '<path d="m6 9 6 6 6-6"></path>',
  up: '<path d="m18 15-6-6-6 6"></path>',
  aup: '<path d="M12 19V5M5 12l7-7 7 7"></path>',
  adown: '<path d="M12 5v14M19 12l-7 7-7-7"></path>',
  x: '<path d="M18 6 6 18M6 6l12 12"></path>',
  check: '<path d="M20 6 9 17l-5-5"></path>',
  plus: '<path d="M12 5v14M5 12h14"></path>',
  alert: '<path d="M12 9v4M12 17h.01M10.300 3.900 2.400 17.500a2 2 0 0 0 1.700 3h15.800a2 2 0 0 0 1.700-3L13.700 3.900a2 2 0 0 0-3.400 0Z"></path>',
  info: '<circle cx="12" cy="12" r="9"></circle><path d="M12 11v5M12 8h.01"></path>',
  help: '<circle cx="12" cy="12" r="9"></circle><path d="M9.100 9a3 3 0 0 1 5.800 1c0 2-3 2.500-3 4M12 17h.01"></path>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"></path>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"></path>',
  undo: '<path d="M9 14 4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3"></path>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16v4zM14 6l4 4"></path>',
  copy: '<rect x="9" y="9" width="12" height="12" rx="2"></rect><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"></path>',
  eye: '<path d="M2 12s3.500-7 10-7 10 7 10 7-3.500 7-10 7-10-7-10-7Z"></path><circle cx="12" cy="12" r="3"></circle>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path>',
  phone: '<path d="M5 4h4l2 5-2.500 1.500a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2"></path>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="m3 7 9 6 9-6"></path>',
  image: '<rect x="3" y="3" width="18" height="18" rx="3"></rect><circle cx="9" cy="9" r="2"></circle><path d="m21 15-5-5L5 21"></path>',
  pin: '<path d="M12 21s7-6.200 7-11a7 7 0 0 0-14 0c0 4.800 7 11 7 11Z"></path><circle cx="12" cy="10" r="2.500"></circle>',
  wifiOff: '<path d="m2 2 20 20M8.500 16.400a5 5 0 0 1 7 0M5 12.900a10 10 0 0 1 5.200-2.700M19 12.900a10 10 0 0 0-2-1.500M2 8.800a15 15 0 0 1 4.200-2.600M22 8.800a15 15 0 0 0-11.300-3.700M12 20h.01"></path>',
  refresh: '<path d="M21 12a9 9 0 1 1-3-6.700L21 8M21 3v5h-5"></path>',
  external: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"></path>',
  power: '<path d="M12 3v9M6.300 6.300a8 8 0 1 0 11.400 0"></path>',
  panel: '<rect x="3" y="4" width="18" height="16" rx="3"></rect><path d="M15 4v16"></path>',
  grip: '<path d="M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01"></path>',
  wand: '<path d="m4 20 11-11M14 5l1 2 2 1-2 1-1 2-1-2-2-1 2-1zM19 13l.600 1.400L21 15l-1.400.600L19 17l-.600-1.400L17 15l1.400-.600z"></path>',
};
export const ICONS = Object.keys(P);
export const ico = (n, s = 20, sw = 1.75, extra = '') => {
  if (!P[n]) throw new Error(`kit: unknown icon "${n}"`);
  return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex:none;${extra}">${P[n]}</svg>`;
};

/* ══ Small text helpers ═════════════════════════════════════════════ */
/** Phone numbers, codes, times, e-mails: LTR, isolated, still aligned to the start edge. */
export const ltr = (s, extra = '') => `<span dir="ltr" style="unicode-bidi:isolate;${extra}">${s}</span>`;
export const money = (n, o = {}) => `<span style="white-space:nowrap">${typeof n === 'number' ? n.toLocaleString('en-US') : n} <span style="font-size:${o.unit ?? 12}px;font-weight:400;color:${o.unitColor ?? C.ink3}">ج.م</span></span>`;
export const time = (hm, ap) => `<span style="white-space:nowrap">${ltr(hm)} ${ap}</span>`;

/* ══ Badges and statuses ════════════════════════════════════════════ */
const TONES = {
  success: [C.okBg, C.ok], warning: [C.warnBg, C.warn], danger: [C.badBg, C.bad],
  teal: [C.tint, C.teal], neutral: [C.sunken, C.ink2],
};
export const tone = (t) => TONES[t] ?? TONES.neutral;
/** A plain tag (counts, kinds, «آخر محاولة»). */
export const badge = (text, t = 'neutral', extra = '') =>
  `<span style="display:inline-flex;align-items:center;gap:6px;background:${tone(t)[0]};color:${tone(t)[1]};border-radius:10px;padding:2px 10px;font-size:12px;line-height:20px;font-weight:500;flex:none;white-space:nowrap;${extra}">${text}</span>`;
/** The six subscription statuses — labels are fixed, never write them by hand. */
export const STATUS = {
  active: ['نشط', 'success'], review: ['قيد المراجعة', 'warning'], unpaid: ['بانتظار الدفع', 'teal'],
  rejected: ['إيصال مرفوض', 'danger'], soon: ['يبدأ قريباً', 'teal'], ended: ['منتهٍ', 'neutral'],
};
/** Other on/off things: lines, supervisors, payment methods, companies. */
export const STATE = {
  on: ['يعمل', 'success'], off: ['متوقف', 'neutral'], archived: ['مؤرشفة', 'neutral'], suspended: ['موقوفة', 'warning'],
  open: ['بانتظار الرد', 'warning'], done: ['تم', 'success'], cancelled: ['أُلغي', 'neutral'], failed: ['فشل الإرسال', 'danger'],
  scheduled: ['مجدول', 'teal'], sent: ['أُرسل', 'success'],
};
const dotPill = (label, t) =>
  `<span style="display:inline-flex;align-items:center;gap:7px;border-radius:999px;padding:3px 12px 3px 10px;font-size:13px;line-height:20px;font-weight:500;background:${tone(t)[0]};color:${tone(t)[1]};flex:none;white-space:nowrap"><span style="width:7px;height:7px;border-radius:4px;background:${tone(t)[1]};flex:none"></span><span>${label}</span></span>`;
export const status = (key) => { if (!STATUS[key]) throw new Error(`kit: unknown status "${key}"`); return dotPill(...STATUS[key]); };
export const state = (key, label) => dotPill(label ?? STATE[key][0], STATE[key][1]);
export const countBadge = (n, extra = '') =>
  `<span style="min-width:20px;height:20px;padding:0 6px;border-radius:10px;background:${C.badge};color:#FFFFFF;font-size:12px;line-height:20px;font-weight:600;text-align:center;flex:none;${extra}">${n}</span>`;

/* ══ Buttons ════════════════════════════════════════════════════════ */
const BTN = {
  primary: { bg: C.teal, fg: '#FFFFFF', hover: C.tealHover, pressed: C.tealPressed, w: 600 },
  secondary: { bg: C.sunken, fg: C.ink, hover: C.hair, pressed: '#D2DEE5', w: 500 },
  outline: { bg: C.surface, fg: C.ink, hover: C.ground, pressed: C.sunken, w: 500, ring: C.hair },
  tonal: { bg: C.tint, fg: C.teal, hover: '#D6EBF5', pressed: '#C6E2F0', w: 600 },
  danger: { bg: C.bad, fg: '#FFFFFF', hover: '#9F2019', pressed: '#8C1B15', w: 600 },
  dangerQuiet: { bg: C.badBg, fg: C.bad, hover: '#F8DBD8', pressed: '#F3CCC8', w: 600 },
  link: { bg: 'transparent', fg: C.teal, hover: 'transparent', pressed: 'transparent', w: 500 },
};
/**
 * btn('حفظ', { kind, icon, iconEnd, phone, sm, full, href, state })
 * kind: primary | secondary | outline | tonal | danger | dangerQuiet | link
 * state: hover | pressed | focus | disabled | loading   (drawn states for spec boards)
 * Height: 44 desktop, 48 phone, 36 with sm (table rows and toolbars only).
 */
export const btn = (label, o = {}) => {
  const k = BTN[o.kind ?? 'primary'];
  const h = o.sm ? 36 : o.phone ? 48 : 44;
  const dis = o.state === 'disabled';
  const bg = dis ? C.sunken : o.state === 'hover' ? k.hover : o.state === 'pressed' ? k.pressed : k.bg;
  const fg = dis ? C.disabled : k.fg;
  const shadow = [o.state === 'focus' ? `0 0 0 2px ${C.surface}, 0 0 0 4px ${C.teal}` : '', k.ring && !dis ? `inset 0 0 0 1px ${k.ring}` : ''].filter(Boolean).join(', ');
  const link = (o.kind === 'link');
  const st = `height:${h}px;border-radius:${R.control}px;display:${o.full ? 'flex' : 'inline-flex'};align-items:center;justify-content:center;gap:8px;font-size:${o.sm ? 13 : 14}px;line-height:20px;font-weight:${k.w};padding:0 ${link ? 4 : o.sm ? 12 : 16}px;background:${bg};color:${fg};white-space:nowrap;flex:none;${o.full ? 'width:100%;' : ''}${shadow ? `box-shadow:${shadow};` : ''}${link && o.state === 'hover' ? 'text-decoration:underline;' : ''}${dis ? 'cursor:default;' : ''}${o.extra ?? ''}`;
  const spin = o.state === 'loading' ? `<span aria-hidden="true" style="width:16px;height:16px;border-radius:8px;border:2px solid rgba(255,255,255,.4);border-top-color:#FFFFFF;flex:none"></span>` : '';
  const inner = `${spin}${o.icon && !spin ? ico(o.icon, o.sm ? 16 : 18) : ''}<span>${label}</span>${o.iconEnd ? ico(o.iconEnd, o.sm ? 16 : 18) : ''}`;
  return o.href ? `<a href="${o.href}" style="${st}">${inner}</a>` : `<button type="button"${dis ? ' disabled' : ''} style="${st}">${inner}</button>`;
};
/** A square icon button with an accessible name. 40 desktop, 48 phone. */
export const iconBtn = (icon, label, o = {}) => {
  const s = o.phone ? 48 : o.sm ? 36 : 40;
  const bg = o.state === 'hover' ? C.sunken : o.bg ?? 'transparent';
  return `<button type="button" aria-label="${label}" title="${label}" style="width:${s}px;height:${s}px;border-radius:${R.control}px;background:${bg};color:${o.color ?? C.ink2};display:inline-flex;align-items:center;justify-content:center;flex:none;position:relative;${o.state === 'focus' ? FOCUS + ';' : ''}${o.extra ?? ''}">${ico(icon, o.size ?? 20)}${o.dot ? `<span style="position:absolute;top:8px;inset-inline-end:8px;width:9px;height:9px;border-radius:5px;background:${C.badge};box-shadow:0 0 0 2px ${C.surface}"></span>` : ''}</button>`;
};

/* ══ Navigation trees — THE single source for labels and grouping ═══ */
/** id is the route slug under /c/:companyId/ ('' = the workspace root). */
export const NAV = {
  company: [
    { group: null, items: [{ id: 'today', slug: '', label: 'اليوم', icon: 'home' }] },
    { group: 'كل يوم', items: [
      { id: 'receipts', slug: 'receipts', label: 'الإيصالات', icon: 'receipt', badge: 'receipts' },
      { id: 'password-requests', slug: 'password-requests', label: 'طلبات كلمة المرور', icon: 'key', badge: 'requests' },
      { id: 'notifications', slug: 'notifications', label: 'الإشعارات', icon: 'megaphone' }] },
    { group: 'الطلاب والفريق', items: [
      { id: 'students', slug: 'students', label: 'الطلاب', icon: 'users' },
      { id: 'supervisors', slug: 'supervisors', label: 'المشرفون', icon: 'scan' },
      { id: 'team', slug: 'team', label: 'مديرو الشركة', icon: 'shield' }] },
    { group: 'الخطوط والرحلات', items: [
      { id: 'lines', slug: 'lines', label: 'الخطوط', icon: 'route' },
      { id: 'ride-confirmation', slug: 'ride-confirmation', label: 'تأكيد الركوب', icon: 'clock' }] },
    { group: 'الاشتراكات والمدفوعات', items: [
      { id: 'subscription-periods', slug: 'subscription-periods', label: 'مواعيد الاشتراك', icon: 'calendar' },
      { id: 'payment-methods', slug: 'payment-methods', label: 'وسائل الدفع', icon: 'card' },
      { id: 'reports', slug: 'reports', label: 'الإيرادات', icon: 'chart' }] },
    { group: 'هوية الشركة', items: [
      { id: 'wallet-card', slug: 'wallet-card', label: 'بطاقة الطالب', icon: 'idcard' },
      { id: 'receipt-details', slug: 'receipt-details', label: 'بيانات الإيصال', icon: 'building' }] },
  ],
  /** slug under /platform/ */
  platform: [
    { group: null, items: [{ id: 'p-today', slug: '', label: 'اليوم', icon: 'home' }] },
    { group: 'يحتاج قرارك', items: [
      { id: 'p-corrections', slug: 'corrections', label: 'طلبات تصحيح البيانات', icon: 'pencil', badge: 'corrections' },
      { id: 'p-password-requests', slug: 'password-requests', label: 'طلبات كلمة المرور', icon: 'key', badge: 'requests' }] },
    { group: 'الشركات', items: [
      { id: 'p-companies', slug: 'companies', label: 'الشركات', icon: 'building' },
      { id: 'p-admins', slug: 'admins', label: 'مديرو الشركات', icon: 'shield' }] },
    { group: 'الطلاب', items: [
      { id: 'p-students', slug: 'students', label: 'كل الطلاب', icon: 'users' },
      { id: 'p-notifications', slug: 'notifications', label: 'إشعارات المنصة', icon: 'megaphone' }] },
    { group: 'إعدادات المنصة', items: [
      { id: 'p-universities', slug: 'universities', label: 'الجامعات والكليات', icon: 'school' },
      { id: 'p-defaults', slug: 'defaults', label: 'الإعدادات الافتراضية', icon: 'sliders' },
      { id: 'p-app-versions', slug: 'app-versions', label: 'إصدارات التطبيق', icon: 'smartphone' }] },
  ],
};
/** role: 'company' | 'platform' | 'workspace' (a super admin inside a company). */
export const navFor = (role) => (role === 'platform' ? NAV.platform : NAV.company);
export const navItem = (role, id) => navFor(role).flatMap((g) => g.items).find((i) => i.id === id);
/** Demo identities and badge counts used by every board unless overridden. */
export const WHO = {
  company: { name: 'أحمد سعيد النورس', role: 'مدير الشركة', initial: 'أ', company: 'النورس للنقل', scope: 'لوحة الشركة' },
  platform: { name: 'محمد عادل', role: 'مدير المنصة', initial: 'م', company: 'المنصة', scope: 'إدارة المنصة' },
  workspace: { name: 'محمد عادل', role: 'مدير المنصة', initial: 'م', company: 'النورس للنقل', scope: 'لوحة الشركة' },
};
export const BADGES = { receipts: 7, requests: 2, corrections: 3 };

export const navRow = (it, on, o = {}) => {
  const n = it.badge ? (o.badges ?? BADGES)[it.badge] : 0;
  const h = o.h ?? 40;
  const hov = o.hover === it.id;
  return `<a href="#"${on ? ' aria-current="page"' : ''} style="display:flex;align-items:center;gap:12px;height:${h}px;padding:0 12px;border-radius:${R.control}px;font-size:${h >= 48 ? 15 : 14}px;line-height:20px;font-weight:${on ? 600 : 400};background:${on ? C.tint : hov ? C.ground : 'transparent'};color:${on ? C.teal : C.ink};position:relative;${o.focus === it.id ? FOCUS + ';' : ''}">${on ? `<span aria-hidden="true" style="position:absolute;inset-inline-start:-12px;top:8px;bottom:8px;width:3px;border-radius:2px;background:${C.teal}"></span>` : ''}<span style="display:flex;color:${on ? C.teal : C.ink2}">${ico(it.icon, 18)}</span><span style="flex:1;min-width:0;${ELL}">${it.label}</span>${n ? countBadge(n) : ''}</a>`;
};
const navGroups = (role, active, o = {}) => navFor(role).map((g) => `<div style="display:flex;flex-direction:column;gap:2px">
${g.group ? `<div style="font-size:12px;line-height:18px;font-weight:500;color:${C.ink3};padding:${o.h >= 48 ? 14 : 12}px 12px 4px">${g.group}</div>` : ''}
${g.items.map((it) => navRow(it, it.id === active, o)).join('\n')}
</div>`).join('\n');
const brand = (role, o = {}) => `<div style="display:flex;align-items:center;gap:12px;min-width:0;flex:1">
<span aria-hidden="true" style="width:36px;height:36px;border-radius:${R.control}px;background:${C.ink};color:#FFFFFF;display:flex;align-items:center;justify-content:center;flex:none">${ico('bus', 18)}</span>
${o.iconOnly ? '' : `<div style="min-width:0"><div style="font-size:16px;line-height:22px;font-weight:600">باصك</div><div style="font-size:12px;line-height:18px;color:${C.ink3};${ELL}">${(o.who ?? WHO[role]).scope}</div></div>`}
</div>`;

/** Desktop side navigation, 264 wide, start side. All destinations visible. */
export const sidebar = ({ active, role = 'company', badges, hover, focus } = {}) => `
<nav aria-label="التنقل الرئيسي" style="width:264px;flex:none;background:${C.surface};border-inline-end:1px solid ${C.hair};display:flex;flex-direction:column">
<div style="height:64px;flex:none;display:flex;align-items:center;padding:0 20px;border-bottom:1px solid ${C.hair}">${brand(role)}</div>
<div style="flex:1;padding:12px 12px 16px;display:flex;flex-direction:column;gap:2px">
${navGroups(role, active, { badges, hover, focus })}
</div>
<div style="flex:none;padding:12px;border-top:1px solid ${C.hair}"><button type="button" style="display:flex;align-items:center;gap:12px;height:40px;width:100%;padding:0 12px;border-radius:${R.control}px;font-size:13px;line-height:20px;color:${C.ink2}">${ico('panel', 18)}<span>تصغير القائمة</span></button></div>
</nav>`;

/** Tablet icon rail, 72 wide. `tip` = id of the item whose label bubble is drawn (hover/focus). */
export const rail = ({ active, role = 'company', badges, tip } = {}) => `
<nav aria-label="التنقل الرئيسي" style="width:72px;flex:none;background:${C.surface};border-inline-end:1px solid ${C.hair};display:flex;flex-direction:column;align-items:center;position:relative;z-index:2">
<div style="height:64px;flex:none;display:flex;align-items:center;justify-content:center;align-self:stretch;border-bottom:1px solid ${C.hair}"><span aria-hidden="true" style="width:36px;height:36px;border-radius:${R.control}px;background:${C.ink};color:#FFFFFF;display:flex;align-items:center;justify-content:center">${ico('bus', 18)}</span></div>
<div style="flex:1;padding:12px 0;display:flex;flex-direction:column;align-items:center;gap:4px">
<button type="button" aria-label="توسيع القائمة لإظهار الأسماء" style="width:44px;height:44px;border-radius:${R.control}px;color:${C.ink2};display:flex;align-items:center;justify-content:center">${ico('menu', 20)}</button>
${navFor(role).map((g, gi) => `${gi ? `<span aria-hidden="true" style="width:28px;height:1px;background:${C.hair};margin:6px 0"></span>` : ''}${g.items.map((it) => {
    const on = it.id === active; const n = it.badge ? (badges ?? BADGES)[it.badge] : 0;
    return `<a href="#" aria-label="${it.label}"${on ? ' aria-current="page"' : ''} style="width:44px;height:44px;border-radius:${R.control}px;background:${on ? C.tint : tip === it.id ? C.ground : 'transparent'};color:${on ? C.teal : C.ink2};display:flex;align-items:center;justify-content:center;position:relative">${ico(it.icon, 20)}${n ? countBadge(n, `position:absolute;top:-2px;inset-inline-end:-4px;box-shadow:0 0 0 2px ${C.surface};min-width:18px;height:18px;line-height:18px;font-size:11px;padding:0 4px`) : ''}${tip === it.id ? `<span role="tooltip" style="position:absolute;inset-inline-start:54px;top:6px;height:32px;padding:0 12px;border-radius:${R.control}px;background:${C.ink};color:#FFFFFF;font-size:13px;line-height:32px;font-weight:500;white-space:nowrap;box-shadow:${SHADOW.floating}">${it.label}</span>` : ''}</a>`;
  }).join('\n')}`).join('\n')}
</div>
</nav>`;

/* ══ Top bars ═══════════════════════════════════════════════════════ */
const crumbs = (list) => `<nav aria-label="مسار الصفحة" style="display:flex;align-items:center;gap:6px;min-width:0;font-size:14px;line-height:22px">${list.map((c, i) => {
  const last = i === list.length - 1;
  return `${i ? `<span style="display:flex;color:${C.disabled}">${ico('fwd', 14, 2)}</span>` : ''}<span style="${last ? `font-weight:600;color:${C.ink}` : `color:${C.ink3}`};${ELL}">${c}</span>`;
}).join('')}</nav>`;
/** The global search: a student by name or phone. */
export const searchBox = (o = {}) => {
  const h = o.phone ? 48 : 44;
  const focus = o.state === 'focus';
  return `<label style="display:flex;align-items:center;gap:10px;height:${h}px;${o.w ? `width:${o.w}px;` : 'flex:1;min-width:0;'}border-radius:${R.control}px;background:${o.bg ?? C.ground};padding:0 12px;color:${C.ink3};box-shadow:${focus ? `inset 0 0 0 2px ${C.teal}, 0 0 0 3px ${C.tint}` : `inset 0 0 0 1px ${o.ring ?? C.hair}`};flex:none">${ico('search', 18)}<span style="flex:1;min-width:0;font-size:14px;line-height:22px;color:${o.value ? C.ink : C.ink3};${ELL}">${o.value ?? o.placeholder ?? 'ابحث عن طالب بالاسم أو رقم الهاتف'}</span>${o.kbd ? `<span aria-hidden="true" dir="ltr" style="height:22px;min-width:22px;padding:0 6px;border-radius:6px;background:${C.surface};box-shadow:inset 0 0 0 1px ${C.hair};font-size:12px;line-height:22px;text-align:center;color:${C.ink3}">/</span>` : ''}${o.value ? `<span style="display:flex">${ico('x', 16)}</span>` : ''}</label>`;
};
const person = (w, o = {}) => `<div style="display:flex;align-items:center;gap:10px;min-width:0">
<span aria-hidden="true" style="width:36px;height:36px;border-radius:18px;background:${C.tint};color:${C.teal};display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;flex:none">${w.initial}</span>
${o.compact ? '' : `<div style="min-width:0"><div style="font-size:14px;line-height:20px;font-weight:500;${ELL}">${w.name}</div><div style="font-size:12px;line-height:18px;color:${C.ink3}">${w.role}</div></div>`}
</div>`;
/** The company picker a super admin uses (top bar on the platform, return bar inside a company). */
export const companySwitcher = (label, o = {}) =>
  `<button type="button" aria-label="الانتقال إلى شركة أخرى" aria-haspopup="listbox" style="display:inline-flex;align-items:center;gap:8px;height:${o.h ?? 44}px;padding:0 12px;border-radius:${R.control}px;background:${o.onInk ? 'rgba(255,255,255,.12)' : C.surface};color:${o.onInk ? '#FFFFFF' : C.ink};font-size:14px;line-height:20px;font-weight:500;${o.onInk ? '' : `box-shadow:inset 0 0 0 1px ${C.hair};`}flex:none;${o.w ? `width:${o.w}px;` : ''}">${ico('building', 18)}<span style="flex:1;min-width:0;text-align:start;${ELL}">${label}</span>${ico('down', 16, 2)}</button>`;

export const topbar = ({ breadcrumb = [], role = 'company', tablet, searchValue, searchState, who } = {}) => {
  const w = who ?? WHO[role];
  return `<header style="height:64px;flex:none;background:${C.surface};border-bottom:1px solid ${C.hair};display:flex;align-items:center;gap:${tablet ? 12 : 16}px;padding:0 ${tablet ? 20 : 32}px">
<div style="flex:1;min-width:0;display:flex">${crumbs(breadcrumb)}</div>
${searchBox({ w: tablet ? 280 : 380, kbd: !tablet, value: searchValue, state: searchState })}
${tablet ? '' : '<div style="flex:1"></div>'}
${role === 'platform' && !tablet ? companySwitcher('ادخل إلى شركة', { w: 190 }) : ''}
<span aria-hidden="true" style="width:1px;height:28px;background:${C.hair};flex:none"></span>
${person(w, { compact: tablet })}
${tablet ? iconBtn('logout', 'تسجيل الخروج') : btn('خروج', { kind: 'outline', icon: 'logout', sm: true })}
</header>`;
};
/** Super admin inside a company: says whose workspace is open, the way back, and the switcher. */
export const workspaceBar = ({ company = 'النورس للنقل', companyState, tablet, phone } = {}) => phone
  ? `<div style="flex:none;background:${C.ink};color:#FFFFFF;display:flex;align-items:center;gap:8px;padding:6px 8px 6px 16px;min-height:48px">
<a href="#" style="display:inline-flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:${R.control}px;color:#FFFFFF;font-size:13px;line-height:20px;font-weight:500;background:rgba(255,255,255,.12);flex:none">${ico('arrowBack', 16, 2)}<span>المنصة</span></a>
${companySwitcher(company, { onInk: true, h: 36 }).replace('flex:none;', 'flex:1;min-width:0;')}
</div>`
  : `<div style="height:48px;flex:none;background:${C.ink};color:#FFFFFF;display:flex;align-items:center;gap:12px;padding:0 ${tablet ? 16 : 20}px">
<a href="#" style="display:inline-flex;align-items:center;gap:8px;height:36px;padding:0 12px;border-radius:${R.control}px;color:#FFFFFF;font-size:14px;line-height:20px;font-weight:500;background:rgba(255,255,255,.12);flex:none">${ico('arrowBack', 16, 2)}<span>العودة إلى المنصة</span></a>
<span style="font-size:14px;line-height:20px;color:#C9D8E1">أنت الآن داخل شركة</span>
${companySwitcher(company, { onInk: true, h: 36, w: 220 })}
${companyState ? state(companyState) : ''}
<span style="flex:1"></span>
${tablet ? '' : `<span style="font-size:13px;line-height:20px;color:#C9D8E1">كل ما تغيّره هنا يتغيّر عند الشركة وطلابها</span>`}
</div>`;

export const topbarPhone = ({ title, back, dot = true, search = true } = {}) => `<header style="height:56px;flex:none;background:${C.surface};border-bottom:1px solid ${C.hair};display:flex;align-items:center;gap:4px;padding:0 4px;position:sticky;top:0;z-index:3">
${back ? `<a href="#" aria-label="رجوع إلى ${back}" style="width:48px;height:48px;border-radius:${R.control}px;color:${C.ink};display:flex;align-items:center;justify-content:center;flex:none">${ico('arrowBack', 20)}</a>` : iconBtn('menu', 'فتح القائمة', { phone: true, color: C.ink, dot })}
<h1 style="margin:0;flex:1;min-width:0;font-size:17px;line-height:26px;font-weight:600;${ELL}">${title}</h1>
${search ? iconBtn('search', 'ابحث عن طالب', { phone: true, color: C.ink }) : ''}
</header>`;

/* ══ Page header ════════════════════════════════════════════════════ */
/**
 * pageHeader({ title, sub, actions, back, phone, meta })
 * Desktop: the h1 with one sentence under it; actions at the end side (primary last = furthest end).
 * Phone: the title is already in the sticky top bar, so only `sub` and `actions` are drawn.
 */
export const pageHeader = ({ title, sub, actions = '', back, phone, meta = '' } = {}) => phone
  ? (sub || actions ? `<div style="display:flex;flex-direction:column;gap:12px">${sub ? `<p style="margin:0;${T.small};color:${C.ink2}">${sub}</p>` : ''}${actions ? `<div style="display:flex;flex-direction:column;gap:8px">${actions}</div>` : ''}</div>` : '')
  : `<div style="display:flex;align-items:flex-end;gap:24px">
<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:2px">
${back ? `<a href="#" style="display:inline-flex;align-items:center;gap:6px;font-size:13px;line-height:20px;font-weight:500;color:${C.teal};align-self:flex-start;margin-bottom:4px">${ico('arrowBack', 14, 2)}<span>${back}</span></a>` : ''}
<div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap"><h1 style="margin:0;${T.page}">${title}</h1>${meta}</div>
${sub ? `<p style="margin:0;${T.small};color:${C.ink2};max-width:720px">${sub}</p>` : ''}
</div>
${actions ? `<div style="display:flex;align-items:center;gap:8px;flex:none">${actions}</div>` : ''}
</div>`;
/** A section title inside a page. */
export const sectionHead = (title, o = {}) => `<div style="display:flex;align-items:center;gap:12px;min-height:${o.phone ? 28 : 36}px">
<h2 style="margin:0;${o.phone ? T.card : T.section}">${title}</h2>${o.meta ?? ''}<span style="flex:1"></span>${o.end ?? ''}
</div>`;

/* ══ Shells ═════════════════════════════════════════════════════════ */
/**
 * shellDesktop({ size, active, role, title, sub, breadcrumb, actions, meta, back, body, overlay,
 *                offline, tablet, tip, badges, searchValue, navHover, navFocus, who })
 * `size` is the string board() hands to body(). `body` is the page content (sections separated by 24).
 * Leave `title` out to draw your own header inside `body`.
 * `tablet: true` (or shellTablet) swaps the 264 sidebar for the 72 rail.
 */
export function shellDesktop(o) {
  const role = o.role ?? 'company';
  const who = o.who ?? WHO[role];
  const item = navItem(role, o.active);
  const bc = o.breadcrumb ?? [who.company, item?.label ?? o.title].filter(Boolean);
  const pad = o.tablet ? 24 : 32;
  return `<div data-root dir="rtl" style="${o.size};background:${C.ground};${FONT};color:${C.ink};display:flex;flex-direction:column;position:relative;overflow:hidden">
${role === 'workspace' ? workspaceBar({ company: who.company, tablet: o.tablet, companyState: o.companyState }) : ''}
<div style="flex:1;min-height:0;display:flex">
${o.tablet ? rail({ active: o.active, role, badges: o.badges, tip: o.tip }) : sidebar({ active: o.active, role, badges: o.badges, hover: o.navHover, focus: o.navFocus })}
<div style="flex:1;min-width:0;display:flex;flex-direction:column">
${topbar({ breadcrumb: bc, role, tablet: o.tablet, searchValue: o.searchValue, searchState: o.searchState, who })}
${o.offline ? offlineBar() : ''}
<main style="flex:1;padding:${o.tablet ? 24 : 28}px ${pad}px 40px">
<div style="max-width:1200px;margin:0 auto;display:flex;flex-direction:column;gap:24px">
${o.title ? pageHeader({ title: o.title, sub: o.sub, actions: o.actions, meta: o.meta, back: o.back }) : ''}
${o.body ?? ''}
</div>
</main>
</div>
</div>
${o.overlay ?? ''}
</div>`;
}
export const shellTablet = (o) => shellDesktop({ ...o, tablet: true });

/**
 * shellPhone({ size, active, role, title, sub, actions, back, body, bottomBar, overlay, offline })
 * A browser page at 390: sticky top bar (menu button + title, or a back arrow when `back` names the parent),
 * one column with 16 gutters, and an optional plain full-width action bar stuck to the bottom.
 */
export function shellPhone(o) {
  const role = o.role ?? 'company';
  const item = navItem(role, o.active);
  return `<div data-root dir="rtl" style="${o.size};background:${C.ground};${FONT};color:${C.ink};display:flex;flex-direction:column;position:relative;overflow:hidden">
${role === 'workspace' ? workspaceBar({ company: (o.who ?? WHO[role]).company, phone: true }) : ''}
${topbarPhone({ title: o.title ?? item?.label, back: o.back, dot: o.dot })}
${o.offline ? offlineBar({ phone: true }) : ''}
<main style="flex:1;padding:16px 16px 24px;display:flex;flex-direction:column;gap:${o.gap ?? 20}px">
${pageHeader({ phone: true, sub: o.sub, actions: o.actions })}
${o.body ?? ''}
</main>
${o.bottomBar ? bottomBar(o.bottomBar) : ''}
${o.overlay ?? ''}
</div>`;
}
/** Phone: the primary action of a form, stuck to the bottom of the viewport. Plain, full width, no rounding. */
export const bottomBar = (inner) => `<div style="flex:none;position:sticky;bottom:0;background:${C.surface};border-top:1px solid ${C.hair};padding:12px 16px;display:flex;flex-direction:column;gap:8px;z-index:3">${inner}</div>`;

/** A dimmed layer over the shell. where: 'end' (side panel) | 'center' (dialog) | 'bottom' (phone dialog) | 'start' (phone drawer). */
export const scrim = (inner, where = 'center', o = {}) => {
  const lay = { end: 'justify-content:flex-end;align-items:stretch', start: 'justify-content:flex-start;align-items:stretch', center: 'justify-content:center;align-items:center', bottom: 'justify-content:center;align-items:flex-end' }[where];
  return `<div style="position:${o.position ?? 'absolute'};inset:0;background:rgba(23,56,74,.45);display:flex;${lay};z-index:10;${o.extra ?? ''}">${inner}</div>`;
};

/**
 * navDrawerPhone({ active, role, badges }) — the full-height drawer the menu button opens.
 * Returns the overlay (scrim + drawer); pass it as shellPhone({ overlay }).
 */
export const navDrawerPhone = ({ active, role = 'company', badges, who } = {}) => {
  const w = who ?? WHO[role];
  return scrim(`<nav aria-label="التنقل الرئيسي" style="width:320px;background:${C.surface};display:flex;flex-direction:column;box-shadow:${SHADOW.floating}">
<div style="height:56px;flex:none;display:flex;align-items:center;gap:8px;padding:0 16px 0 4px;border-bottom:1px solid ${C.hair}">${brand(role, { who: { scope: w.company } })}${iconBtn('x', 'إغلاق القائمة', { phone: true, color: C.ink })}</div>
${role === 'workspace' ? `<div style="flex:none;padding:12px 12px 0;display:flex;flex-direction:column;gap:8px">${btn('العودة إلى المنصة', { kind: 'secondary', icon: 'arrowBack', phone: true, full: true })}</div>` : ''}
<div style="flex:1;padding:8px 12px 16px;display:flex;flex-direction:column;gap:2px">
${navGroups(role, active, { badges, h: 48 })}
</div>
<div style="flex:none;padding:12px 16px 16px;border-top:1px solid ${C.hair};display:flex;flex-direction:column;gap:12px">
${person(w)}
${btn('تسجيل الخروج', { kind: 'secondary', icon: 'logout', phone: true, full: true })}
</div>
</nav>`, 'start');
};

/* ══ Stat card ══════════════════════════════════════════════════════ */
/** statCard({ label, value, unit, hint, icon, tone, href, phone, bar }) — one number, one sentence. bar = 0..100 draws a meter. */
export const statCard = ({ label, value, unit, hint, icon, tone: t, href, phone, bar, state: st } = {}) => {
  const body = `<div style="display:flex;align-items:center;gap:8px;color:${C.ink2};${T.label};font-weight:500">${icon ? `<span style="display:flex;color:${t ? tone(t)[1] : C.ink3}">${ico(icon, 16, 2)}</span>` : ''}<span style="flex:1;min-width:0;${ELL}">${label}</span>${href ? `<span style="display:flex;color:${C.ink3}">${ico('fwd', 16, 2)}</span>` : ''}</div>
<div style="display:flex;align-items:baseline;gap:6px;margin-top:${phone ? 4 : 8}px"><span style="${phone ? 'font-size:26px;line-height:34px;font-weight:600' : T.num}">${value}</span>${unit ? `<span style="${T.label};color:${C.ink3}">${unit}</span>` : ''}</div>
${bar != null ? `<div aria-hidden="true" style="height:6px;border-radius:3px;background:${C.sunken};overflow:hidden;margin-top:8px"><div style="width:${bar}%;height:6px;border-radius:3px;background:${C.teal}"></div></div>` : ''}
${hint ? `<div style="${T.label};color:${C.ink3};margin-top:${bar != null ? 8 : 2}px">${hint}</div>` : ''}`;
  const style = `${CARD};padding:${phone ? '14px 16px' : '18px 20px'};display:flex;flex-direction:column;min-width:0;color:${C.ink};${st === 'hover' ? `box-shadow:${SHADOW.card}, inset 0 0 0 1px ${C.disabled};` : ''}${st === 'focus' ? FOCUS + ';' : ''}`;
  return href ? `<a href="${href}" style="${style}">${body}</a>` : `<div style="${style}">${body}</div>`;
};

/* ══ Attention rows ═════════════════════════════════════════════════ */
/**
 * attentionRow({ count | icon, tone, title, sub, action, href, phone, first })
 * tone: warning = waiting on you · danger = broken for students · teal = a request.
 * Desktop: a named button at the end. Phone: the whole row is the link, a chevron at the end.
 */
export const attentionRow = (a) => {
  const [bg, fg] = tone(a.tone);
  const lead = `<span aria-hidden="true" style="width:40px;height:40px;border-radius:${R.control}px;background:${bg};color:${fg};display:flex;align-items:center;justify-content:center;font-size:17px;font-weight:600;flex:none">${a.count ?? ico(a.icon, 20)}</span>
<span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="font-size:15px;line-height:22px;font-weight:600">${a.title}</span><span style="${T.label};color:${C.ink2}">${a.sub}</span></span>`;
  const st = `display:flex;align-items:center;gap:12px;min-height:${a.phone ? 72 : 68}px;padding:12px ${a.phone ? 16 : 20}px;color:${C.ink};${a.first ? '' : `border-top:1px solid ${C.hair};`}${a.state === 'hover' ? `background:${C.ground};` : ''}`;
  return a.phone
    ? `<a href="${a.href ?? '#'}" style="${st}">${lead}<span style="display:flex;color:${C.ink3};flex:none">${ico('fwd', 18)}</span></a>`
    : `<div style="${st}">${lead}${btn(a.action, { kind: a.primary ? 'primary' : 'tonal', sm: true, href: a.href ?? '#' })}</div>`;
};
/** The «يحتاج منك الآن» card: many rows, one row, or the green "nothing waits" row. Never disappears. */
export const attentionList = (rows, o = {}) => `<div style="${CARD};overflow:hidden">${rows.length
  ? rows.map((r, i) => attentionRow({ ...r, phone: o.phone, first: i === 0 })).join('\n')
  : `<div style="display:flex;align-items:center;gap:12px;min-height:${o.phone ? 72 : 68}px;padding:12px ${o.phone ? 16 : 20}px"><span aria-hidden="true" style="width:40px;height:40px;border-radius:${R.control}px;background:${C.okBg};color:${C.ok};display:flex;align-items:center;justify-content:center;flex:none">${ico('check', 20, 2.25)}</span><span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="font-size:15px;line-height:22px;font-weight:600">${o.zeroTitle ?? 'لا شيء ينتظرك'}</span><span style="${T.label};color:${C.ink2}">${o.zeroSub ?? 'راجعت كل الإيصالات، وكل الخطوط جاهزة.'}</span></span></div>`}</div>`;

/* ══ Data table (desktop / tablet) ══════════════════════════════════ */
const checkbox = (on, o = {}) => `<span role="checkbox" aria-checked="${on === 'mixed' ? 'mixed' : !!on}" aria-label="${o.label ?? 'تحديد الصف'}" style="width:20px;height:20px;border-radius:6px;display:inline-flex;align-items:center;justify-content:center;flex:none;${on ? `background:${C.teal};color:#FFFFFF` : `background:${C.surface};box-shadow:inset 0 0 0 1.500px ${C.ink3}`};${o.focus ? FOCUS : ''}">${on === 'mixed' ? '<span style="width:10px;height:2px;border-radius:1px;background:#FFFFFF"></span>' : on ? ico('check', 14, 3) : ''}</span>`;
export { checkbox };
/** Filter chip: chip('قيد المراجعة', { on, count }). */
export const chip = (label, o = {}) => `<button type="button" aria-pressed="${!!o.on}" style="display:inline-flex;align-items:center;gap:6px;height:${o.phone ? 40 : 36}px;padding:0 12px;border-radius:999px;font-size:13px;line-height:20px;font-weight:${o.on ? 600 : 400};background:${o.on ? C.ink : C.surface};color:${o.on ? '#FFFFFF' : C.ink};${o.on ? '' : `box-shadow:inset 0 0 0 1px ${C.hair};`}white-space:nowrap;flex:none;${o.state === 'focus' ? FOCUS + ';' : ''}">${o.icon ? ico(o.icon, 14, 2) : ''}<span>${label}</span>${o.count != null ? `<span style="font-size:12px;color:${o.on ? '#C9D8E1' : C.ink3}">${o.count}</span>` : ''}</button>`;
/** Two-line cell: a name with a quieter line under it. */
export const cell2 = (main, sub, o = {}) => `<div style="min-width:0"><div style="font-weight:${o.w ?? 500};${ELL}">${main}</div>${sub ? `<div style="font-size:12px;line-height:18px;color:${C.ink3};${ELL}">${sub}</div>` : ''}</div>`;
export const pager = ({ from, to, total, page = 1, pages, phone } = {}) => {
  const count = `<span style="${T.label};color:${C.ink2}">${ltr(`${from}–${to}`)} من ${ltr(total.toLocaleString ? total.toLocaleString('en-US') : total)}</span>`;
  if (phone) return `<div style="display:flex;align-items:center;gap:8px"><span style="flex:1">${count}</span>${btn('السابق', { kind: 'outline', sm: true, state: page === 1 ? 'disabled' : undefined, extra: 'height:44px;' })}${btn('التالي', { kind: 'outline', sm: true, state: page === pages ? 'disabled' : undefined, extra: 'height:44px;' })}</div>`;
  const nums = pages <= 6 ? Array.from({ length: pages }, (_, i) => i + 1) : page <= 3 ? [1, 2, 3, 4, '…', pages] : page >= pages - 2 ? [1, '…', pages - 3, pages - 2, pages - 1, pages] : [1, '…', page - 1, page, page + 1, '…', pages];
  const b = (inner, on, dis, label) => `<button type="button"${label ? ` aria-label="${label}"` : ''}${on ? ' aria-current="page"' : ''} style="min-width:36px;height:36px;padding:0 8px;border-radius:${R.control}px;display:inline-flex;align-items:center;justify-content:center;font-size:13px;font-weight:${on ? 600 : 400};background:${on ? C.ink : 'transparent'};color:${on ? '#FFFFFF' : dis ? C.disabled : C.ink}">${inner}</button>`;
  return `<div style="display:flex;align-items:center;gap:16px;height:56px;padding:0 16px;border-top:1px solid ${C.hair}">${count}<span style="flex:1"></span><div style="display:flex;align-items:center;gap:2px">${b(ico('back', 16, 2), false, page === 1, 'الصفحة السابقة')}${nums.map((n) => (n === '…' ? `<span style="min-width:24px;text-align:center;color:${C.ink3}">…</span>` : b(n, n === page))).join('')}${b(ico('fwd', 16, 2), false, page === pages, 'الصفحة التالية')}</div></div>`;
};
/**
 * Toolbar above a table or a record list.
 * toolbar: { search: 'placeholder', searchValue, filters: [{ label, on, count }], sort: 'الأحدث أولاً', count: '442 طالباً', actions: html }
 * bulk:    { count: 3, actions: html }  — replaces the toolbar while rows are selected.
 */
export const tableToolbar = (t = {}, bulk) => bulk
  ? `<div style="display:flex;align-items:center;gap:12px;min-height:60px;padding:8px 16px;background:${C.tint};border-bottom:1px solid ${C.hair}"><span style="font-size:14px;line-height:22px;font-weight:600;color:${C.teal}">${bulk.label ?? `تم تحديد ${bulk.count}`}</span>${btn('إلغاء التحديد', { kind: 'link', sm: true })}<span style="flex:1"></span>${bulk.actions ?? ''}</div>`
  : `<div style="display:flex;align-items:center;gap:12px;min-height:60px;padding:8px 16px;border-bottom:1px solid ${C.hair};flex-wrap:wrap">
${t.search ? searchBox({ w: t.searchW ?? 280, placeholder: t.search, value: t.searchValue, state: t.searchState }) : ''}
${t.filters ? `<div role="group" aria-label="تصفية" style="display:flex;align-items:center;gap:6px;flex-wrap:wrap">${t.filters.map((f) => chip(f.label, f)).join('')}</div>` : ''}
<span style="flex:1"></span>
${t.count ? `<span style="${T.label};color:${C.ink2};white-space:nowrap">${t.count}</span>` : ''}
${t.sort ? `<button type="button" aria-haspopup="listbox" style="display:inline-flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:${R.control}px;font-size:13px;line-height:20px;color:${C.ink};box-shadow:inset 0 0 0 1px ${C.hair};white-space:nowrap">${ico('sort', 14, 2)}<span>${t.sort}</span>${ico('down', 14, 2)}</button>` : ''}
${t.actions ?? ''}
</div>`;
/**
 * dataTable({ columns, rows, toolbar, bulk, pagination, selectable, foot, empty, rowH, caption })
 * columns: [{ label, w, align: 'start' | 'end' | 'center', sorted: 'asc' | 'desc', hideTablet }]
 *          w = px number, or leave out to share the rest. The first column is the record's name.
 * rows:    [{ cells: [html…], state: 'hover' | 'selected' | 'open' | 'focus', muted, href }]
 *          'open' = the row whose side panel is showing.
 * pagination: { from, to, total, page, pages } → «1–25 من 442» + page buttons. Page size is 25.
 * foot:    [html…] a totals row.  empty: html shown instead of rows (use emptyState()).
 * tablet:  true drops columns marked hideTablet.
 */
export function dataTable(o) {
  const cols = o.columns.filter((c) => !(o.tablet && c.hideTablet));
  const keep = o.columns.map((c, i) => (!(o.tablet && c.hideTablet) ? i : -1)).filter((i) => i >= 0);
  const rowH = o.rowH ?? 56;
  const al = (c) => `text-align:${c.align ?? 'start'}`;
  const sel = o.selectable;
  const allOn = sel && o.rows.length && o.rows.every((r) => r.state === 'selected');
  const someOn = sel && o.rows.some((r) => r.state === 'selected');
  const head = `<tr style="height:44px;background:${C.ground}">${sel ? `<th style="width:48px;padding:0 0 0 0;text-align:center">${checkbox(allOn ? true : someOn ? 'mixed' : false, { label: 'تحديد كل الصفوف' })}</th>` : ''}${cols.map((c, i) => `<th scope="col"${c.sorted ? ` aria-sort="${c.sorted === 'asc' ? 'ascending' : 'descending'}"` : ''} style="${c.w ? `width:${c.w}px;` : ''}${al(c)};font-size:13px;line-height:20px;font-weight:500;color:${c.sorted ? C.ink : C.ink2};padding:0 ${i === cols.length - 1 ? 16 : 12}px 0 ${i === 0 && !sel ? 16 : 12}px;padding-inline:${i === 0 && !sel ? 16 : 12}px ${i === cols.length - 1 ? 16 : 12}px;white-space:nowrap">${c.label}${c.sorted ? `<span style="display:inline-flex;vertical-align:-2px;margin-inline-start:4px">${ico(c.sorted === 'asc' ? 'aup' : 'adown', 13, 2)}</span>` : ''}</th>`).join('')}</tr>`;
  const body = o.rows.map((r) => {
    const bg = r.state === 'selected' || r.state === 'open' ? C.tint : r.state === 'hover' ? C.ground : 'transparent';
    return `<tr style="height:${rowH}px;background:${bg};border-top:1px solid ${C.hair};${r.state === 'focus' ? `outline:2px solid ${C.teal};outline-offset:-2px;` : ''}${r.muted ? `color:${C.ink3};` : ''}${r.state === 'open' ? `box-shadow:inset -3px 0 0 ${C.teal};` : ''}">${sel ? `<td style="text-align:center">${checkbox(r.state === 'selected')}</td>` : ''}${keep.map((ci, i) => `<td style="${al(o.columns[ci])};padding-block:8px;padding-inline:${i === 0 && !sel ? 16 : 12}px ${i === keep.length - 1 ? 16 : 12}px;font-size:14px;line-height:22px;overflow:hidden">${r.cells[ci] ?? ''}</td>`).join('')}</tr>`;
  }).join('\n');
  const foot = o.foot ? `<tr style="height:${rowH}px;border-top:2px solid ${C.hair};background:${C.surface}">${sel ? '<td></td>' : ''}${keep.map((ci, i) => `<td style="${al(o.columns[ci])};padding-inline:${i === 0 && !sel ? 16 : 12}px ${i === keep.length - 1 ? 16 : 12}px;font-size:14px;line-height:22px;font-weight:600">${o.foot[ci] ?? ''}</td>`).join('')}</tr>` : '';
  return `<div style="${CARD};overflow:hidden;display:flex;flex-direction:column">
${o.toolbar || o.bulk ? tableToolbar(o.toolbar, o.bulk) : ''}
${o.empty ? o.empty : `<table style="width:100%;border-collapse:collapse;table-layout:fixed">${o.caption ? `<caption style="position:absolute;width:1px;height:1px;overflow:hidden">${o.caption}</caption>` : ''}
<thead>${head}</thead>
<tbody>
${body}
${foot}
</tbody>
</table>`}
${o.pagination && !o.empty ? pager(o.pagination) : ''}
</div>`;
}

/* ══ Record cards (the phone form of a table row) ═══════════════════ */
/**
 * recordCard({ title, sub, end, stats: [[label, number]…], fields: [[label, value]…], actions, state, selectable })
 * stats = the record's counts, drawn as tiles in one row (at most 3).
 * Same fields, same order as the table's columns; column 1 is the title. The whole card opens the record's page.
 */
export const recordCard = (r) => `<a href="${r.href ?? '#'}" style="background:${r.state === 'selected' ? C.tint : C.surface};border-radius:${R.inner}px;box-shadow:${SHADOW.card};padding:14px 16px;display:flex;flex-direction:column;gap:10px;color:${C.ink}">
<div style="display:flex;align-items:flex-start;gap:10px">${r.selectable ? `<span style="display:flex;padding-top:2px">${checkbox(r.state === 'selected')}</span>` : ''}<div style="flex:1;min-width:0"><div style="font-size:15px;line-height:22px;font-weight:600">${r.title}</div>${r.sub ? `<div style="${T.label};color:${C.ink2}">${r.sub}</div>` : ''}</div>${r.end ?? ''}</div>
${r.stats?.length ? `<div style="display:grid;grid-template-columns:repeat(${r.stats.length},minmax(0,1fr));gap:8px">${r.stats.map(([k, v]) => `<div style="background:${C.ground};border-radius:${R.control}px;padding:6px 12px"><div style="font-size:12px;line-height:18px;color:${C.ink3}">${k}</div><div style="font-size:18px;line-height:26px;font-weight:600">${v}</div></div>`).join('')}</div>` : ''}
${r.fields?.length ? `<dl style="margin:0;display:grid;grid-template-columns:auto minmax(0,1fr);gap:4px 16px;font-size:14px;line-height:22px">${r.fields.map(([k, v]) => `<dt style="color:${C.ink3};font-size:13px">${k}</dt><dd style="margin:0;text-align:end;min-width:0">${v}</dd>`).join('')}</dl>` : ''}
${r.actions ? `<div style="display:flex;gap:8px;padding-top:2px">${r.actions}</div>` : ''}
</a>`;
/** recordList({ toolbar, cards, pagination, empty }) — search on its own row, chips scroll sideways, then the cards. */
export const recordList = ({ toolbar: t, cards = [], pagination, empty } = {}) => `<div style="display:flex;flex-direction:column;gap:12px">
${t?.search ? searchBox({ phone: true, placeholder: t.search, value: t.searchValue, bg: C.surface }).replace('flex:1;min-width:0;', '').replace('flex:none', 'align-self:stretch') : ''}
${t?.filters ? `<div role="group" aria-label="تصفية" style="display:flex;gap:6px;overflow:hidden;margin-inline:-16px;padding-inline:16px">${t.filters.map((f) => chip(f.label, { ...f, phone: true })).join('')}</div>` : ''}
${t?.count || t?.sort ? `<div style="display:flex;align-items:center;gap:8px;min-height:24px"><span style="flex:1;${T.label};color:${C.ink2}">${t.count ?? ''}</span>${t.sort ? `<button type="button" style="display:inline-flex;align-items:center;gap:6px;height:40px;font-size:13px;line-height:20px;font-weight:500;color:${C.teal}">${ico('sort', 14, 2)}<span>${t.sort}</span></button>` : ''}</div>` : ''}
${empty ?? cards.join('\n')}
${pagination && !empty ? pager({ ...pagination, phone: true }) : ''}
</div>`;

/* ══ Side panel, dialog ═════════════════════════════════════════════ */
/**
 * sidePanel({ title, sub, body, footer, w, meta }) — the panel itself (480 wide, end side, full height).
 * Wrap it: shellDesktop({ overlay: scrim(sidePanel({...}), 'end') }).
 * On a phone the same content is a full page: shellPhone({ back: 'الطلاب', title, body, bottomBar: footer }).
 */
export const sidePanel = ({ title, sub, body = '', footer, w = 480, meta = '' } = {}) => `<aside role="dialog" aria-modal="true" aria-label="${title}" style="width:${w}px;background:${C.surface};display:flex;flex-direction:column;box-shadow:${SHADOW.floating}">
<header style="flex:none;display:flex;align-items:flex-start;gap:12px;padding:20px 24px 16px;border-bottom:1px solid ${C.hair}">
<div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap"><h2 style="margin:0;${T.section}">${title}</h2>${meta}</div>${sub ? `<div style="${T.label};color:${C.ink2}">${sub}</div>` : ''}</div>
${iconBtn('x', 'إغلاق', { extra: 'margin:-6px -8px 0 0;margin-inline:0 -8px;' })}
</header>
<div style="flex:1;min-height:0;padding:20px 24px;display:flex;flex-direction:column;gap:20px;overflow:hidden">${body}</div>
${footer ? `<footer style="flex:none;display:flex;align-items:center;gap:8px;padding:16px 24px;border-top:1px solid ${C.hair}">${footer}</footer>` : ''}
</aside>`;
/** Label/value rows for a panel or a detail page: infoRows([[label, value]…]). */
export const infoRows = (rows, o = {}) => `<dl style="margin:0;display:flex;flex-direction:column">${rows.map(([k, v], i) => `<div style="display:flex;align-items:baseline;gap:16px;padding:10px 0;${i ? `border-top:1px solid ${C.hair}` : ''}"><dt style="width:${o.labelW ?? 128}px;flex:none;${T.label};color:${C.ink3}">${k}</dt><dd style="margin:0;flex:1;min-width:0;${T.small}">${v}</dd></div>`).join('')}</dl>`;
/**
 * dialog({ title, body, actions, tone, icon, phone, w })
 * Desktop: centred, 480 wide — wrap with scrim(…, 'center'). Phone: bottom-anchored, full width — scrim(…, 'bottom').
 * actions: [cancelHtml, confirmHtml]; on a phone they stack, confirm first. The confirm verb repeats the title's verb.
 */
export const dialog = ({ title, body = '', actions = [], tone: t, icon, phone, w = 480 } = {}) => {
  const lead = icon ? `<span aria-hidden="true" style="width:44px;height:44px;border-radius:22px;background:${tone(t ?? 'teal')[0]};color:${tone(t ?? 'teal')[1]};display:flex;align-items:center;justify-content:center;flex:none">${ico(icon, 22)}</span>` : '';
  const text = `<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px"><h2 style="margin:0;${T.section}">${title}</h2><div style="${T.small};color:${C.ink2};display:flex;flex-direction:column;gap:12px">${body}</div></div>`;
  return phone
    ? `<div role="alertdialog" aria-modal="true" aria-label="${title}" style="width:100%;background:${C.surface};border-radius:${R.dialog}px ${R.dialog}px 0 0;padding:20px 16px 16px;display:flex;flex-direction:column;gap:16px;box-shadow:${SHADOW.floating}">
<div style="display:flex;flex-direction:column;gap:12px">${lead}${text}</div>
<div style="display:flex;flex-direction:column;gap:8px">${[...actions].reverse().join('')}</div>
</div>`
    : `<div role="alertdialog" aria-modal="true" aria-label="${title}" style="width:${w}px;background:${C.surface};border-radius:${R.dialog}px;padding:24px;display:flex;flex-direction:column;gap:24px;box-shadow:${SHADOW.floating}">
<div style="display:flex;gap:16px">${lead}${text}</div>
<div style="display:flex;justify-content:flex-end;gap:8px">${actions.join('')}</div>
</div>`;
};

/* ══ Forms ══════════════════════════════════════════════════════════ */
/**
 * formSection({ title, help, body, footer, phone })
 * Desktop: a card; the title and one helping sentence on the start side (4 of 12 columns), the fields on the end side.
 * Phone: stacked. `footer` is the section's own save row (desktop only — on a phone the page's bottomBar saves).
 */
export const formSection = ({ title, help, body = '', footer, phone } = {}) => phone
  ? `<section style="${CARD};padding:16px;display:flex;flex-direction:column;gap:16px"><div><h2 style="margin:0;${T.card}">${title}</h2>${help ? `<p style="margin:2px 0 0;${T.label};color:${C.ink2}">${help}</p>` : ''}</div>${body}</section>`
  : `<section style="${CARD};display:flex;flex-direction:column"><div style="display:grid;grid-template-columns:minmax(0,4fr) minmax(0,8fr);gap:32px;padding:24px">
<div><h2 style="margin:0;${T.card}">${title}</h2>${help ? `<p style="margin:4px 0 0;${T.label};color:${C.ink2}">${help}</p>` : ''}</div>
<div style="display:flex;flex-direction:column;gap:16px;min-width:0">${body}</div>
</div>${footer ? `<div style="display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:12px 24px;border-top:1px solid ${C.hair}">${footer}</div>` : ''}</section>`;
/** Lay fields side by side on desktop: fieldRow([field(), field()]) — stacks on a phone. */
export const fieldRow = (fields, o = {}) => o.phone ? fields.join('\n') : `<div style="display:grid;grid-template-columns:${o.cols ?? `repeat(${fields.length},minmax(0,1fr))`};gap:16px;align-items:start">${fields.join('')}</div>`;

const switchEl = (on, dis) => `<span role="switch" aria-checked="${!!on}" style="width:44px;height:24px;border-radius:12px;background:${dis ? C.sunken : on ? C.teal : C.disabled};display:flex;align-items:center;padding:2px;justify-content:${on ? 'flex-end' : 'flex-start'};flex:none"><span style="width:20px;height:20px;border-radius:10px;background:#FFFFFF;box-shadow:0 1px 2px rgba(23,56,74,.25)"></span></span>`;
/**
 * field({ type, label, value, placeholder, help, error, optional, state, phone, options, suffix, ltr, rows, on })
 * type:  text | password | tel | search | select | date | time | money | textarea | toggle | radio | checkbox
 * state: hover | focus | disabled       error: the Arabic sentence shown under the field (turns the ring red)
 * money  draws the «ج.م» unit inside the end of the control.   tel / money values are LTR; pass a time as time('6:45', 'ص').
 * toggle { label, help, on }            — a row with a switch at the end; say in `help` when it takes effect.
 * radio  { options: [{ label, sub, on, end }] , cols } — radio cards.
 * checkbox { label, on }
 */
export function field(o) {
  const h = o.phone ? 48 : 44;
  const type = o.type ?? 'text';
  const id = `f${Math.abs([...(o.label ?? '') + type].reduce((a, c) => (a * 31 + c.charCodeAt(0)) | 0, 7))}`;
  if (type === 'toggle') {
    return `<label style="display:flex;align-items:center;gap:16px;min-height:${h}px;${o.state === 'disabled' ? `color:${C.disabled};` : ''}"><span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="${T.small};font-weight:500">${o.label}</span>${o.help ? `<span style="${T.label};color:${o.state === 'disabled' ? C.disabled : C.ink2}">${o.help}</span>` : ''}</span>${switchEl(o.on, o.state === 'disabled')}</label>`;
  }
  if (type === 'checkbox') {
    return `<label style="display:flex;align-items:center;gap:10px;min-height:${h}px;${T.small}">${checkbox(o.on, { label: o.label, focus: o.state === 'focus' })}<span>${o.label}</span></label>`;
  }
  const ring = o.error ? `inset 0 0 0 2px ${C.bad}` : o.state === 'focus' ? `inset 0 0 0 2px ${C.teal}, 0 0 0 3px ${C.tint}` : o.state === 'hover' ? `inset 0 0 0 1px ${C.ink3}` : o.state === 'disabled' ? `inset 0 0 0 1px ${C.hair}` : `inset 0 0 0 1px ${C.disabled}`;
  const bg = o.state === 'disabled' ? C.ground : C.surface;
  const isLtr = o.ltr ?? ['tel', 'money', 'password'].includes(type);
  const shown = o.value ?? '';
  const valHtml = shown !== ''
    ? `<span ${isLtr ? 'dir="ltr" ' : ''}style="flex:1;min-width:0;text-align:${isLtr ? 'right' : 'start'};color:${o.state === 'disabled' ? C.disabled : C.ink};${ELL}">${type === 'password' ? '••••••••••' : shown}</span>`
    : `<span style="flex:1;min-width:0;color:${C.ink3};${ELL}">${o.placeholder ?? ''}</span>`;
  const endIcon = { select: 'down', date: 'calendar', time: 'clock', password: 'eye', search: null }[type];
  let control;
  if (type === 'radio') {
    control = `<div role="radiogroup" aria-labelledby="${id}" style="display:grid;grid-template-columns:${o.phone ? 'minmax(0,1fr)' : `repeat(${o.cols ?? o.options.length},minmax(0,1fr))`};gap:8px">${o.options.map((r) => `<div role="radio" aria-checked="${!!r.on}" style="display:flex;align-items:center;gap:12px;min-height:${r.sub ? 64 : h}px;padding:10px 14px;border-radius:${R.control}px;background:${r.on ? C.tint : C.surface};box-shadow:inset 0 0 0 ${r.on ? `2px ${C.teal}` : `1px ${C.disabled}`}"><span aria-hidden="true" style="width:20px;height:20px;border-radius:10px;flex:none;display:flex;align-items:center;justify-content:center;box-shadow:inset 0 0 0 ${r.on ? `6px ${C.teal}` : `1.500px ${C.ink3}`};background:${C.surface}"></span><span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="${T.small};font-weight:${r.on ? 600 : 500}">${r.label}</span>${r.sub ? `<span style="${T.label};color:${C.ink2}">${r.sub}</span>` : ''}</span>${r.end ?? ''}</div>`).join('')}</div>`;
  } else if (type === 'textarea') {
    control = `<div style="min-height:${(o.rows ?? 3) * 24 + 20}px;border-radius:${R.control}px;background:${bg};box-shadow:${ring};padding:10px 12px;${T.small};color:${shown ? C.ink : C.ink3}">${shown || o.placeholder || ''}</div>`;
  } else {
    control = `<div style="height:${h}px;border-radius:${R.control}px;background:${bg};box-shadow:${ring};display:flex;align-items:center;gap:8px;padding:0 12px;${T.small}">${type === 'search' ? `<span style="display:flex;color:${C.ink3}">${ico('search', 18)}</span>` : ''}${o.prefix ?? ''}${valHtml}${type === 'money' ? `<span style="${T.label};color:${C.ink3};flex:none">ج.م</span>` : ''}${o.suffix ? `<span style="${T.label};color:${C.ink3};flex:none">${o.suffix}</span>` : ''}${endIcon ? `<span style="display:flex;color:${C.ink3}">${ico(endIcon, 18)}</span>` : ''}</div>`;
  }
  return `<div style="display:flex;flex-direction:column;gap:6px;min-width:0;${o.w ? `width:${o.w}px;` : ''}">
${o.label ? `<div id="${id}" style="display:flex;align-items:baseline;gap:8px;${T.label};font-weight:500;color:${C.ink}"><span>${o.label}</span>${o.optional ? `<span style="font-weight:400;color:${C.ink3}">اختياري</span>` : ''}</div>` : ''}
${control}
${o.error ? `<div role="alert" style="display:flex;align-items:flex-start;gap:6px;${T.label};color:${C.bad}"><span style="display:flex;padding-top:2px">${ico('alert', 14, 2)}</span><span>${o.error}</span></div>` : o.help ? `<div style="${T.label};color:${C.ink2}">${o.help}</div>` : ''}
</div>`;
}

/* ══ Stepper ════════════════════════════════════════════════════════ */
/**
 * stepper({ steps: [{ label, sub, state: 'done' | 'current' | 'todo' }], phone, vertical })
 * Desktop: numbered steps in a row.  vertical: a column (setup lists).  Phone: «الخطوة 2 من 4 · المحطات» and a segmented bar.
 */
export function stepper({ steps, phone, vertical } = {}) {
  const dot = (s, i) => `<span aria-hidden="true" style="width:28px;height:28px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:600;${s.state === 'done' ? `background:${C.ok};color:#FFFFFF` : s.state === 'current' ? `background:${C.teal};color:#FFFFFF` : `background:${C.surface};color:${C.ink3};box-shadow:inset 0 0 0 1.500px ${C.disabled}`}">${s.state === 'done' ? ico('check', 16, 2.5) : i + 1}</span>`;
  const cur = Math.max(0, steps.findIndex((s) => s.state === 'current'));
  if (phone) {
    return `<div style="display:flex;flex-direction:column;gap:8px"><div style="display:flex;align-items:baseline;gap:8px"><span style="${T.small};font-weight:600">${steps[cur].label}</span><span style="flex:1"></span><span style="${T.label};color:${C.ink2}">الخطوة ${cur + 1} من ${steps.length}</span></div><div aria-hidden="true" style="display:grid;grid-template-columns:repeat(${steps.length},minmax(0,1fr));gap:4px">${steps.map((s) => `<span style="height:4px;border-radius:2px;background:${s.state === 'todo' ? C.sunken : s.state === 'done' ? C.ok : C.teal}"></span>`).join('')}</div></div>`;
  }
  if (vertical) {
    return `<ol style="margin:0;padding:0;list-style:none;display:flex;flex-direction:column">${steps.map((s, i) => `<li${s.state === 'current' ? ' aria-current="step"' : ''} style="display:flex;gap:12px"><div style="display:flex;flex-direction:column;align-items:center">${dot(s, i)}${i < steps.length - 1 ? `<span style="flex:1;width:2px;min-height:16px;background:${s.state === 'done' ? C.ok : C.hair};margin:4px 0"></span>` : ''}</div><div style="flex:1;min-width:0;padding-bottom:${i < steps.length - 1 ? 16 : 0}px"><div style="${T.small};line-height:28px;font-weight:${s.state === 'current' ? 600 : 500};color:${s.state === 'todo' ? C.ink2 : C.ink}">${s.label}</div>${s.sub ? `<div style="${T.label};color:${C.ink2}">${s.sub}</div>` : ''}${s.body ?? ''}</div></li>`).join('')}</ol>`;
  }
  return `<ol style="margin:0;padding:0;list-style:none;display:flex;align-items:center;gap:12px">${steps.map((s, i) => `<li${s.state === 'current' ? ' aria-current="step"' : ''} style="display:flex;align-items:center;gap:10px;flex:none">${dot(s, i)}<span style="${T.small};font-weight:${s.state === 'current' ? 600 : 400};color:${s.state === 'todo' ? C.ink2 : C.ink};white-space:nowrap">${s.label}</span></li>${i < steps.length - 1 ? `<li aria-hidden="true" style="flex:1;min-width:24px;height:2px;border-radius:1px;background:${s.state === 'done' ? C.ok : C.hair}"></li>` : ''}`).join('')}</ol>`;
}

/* ══ Feedback and page states ═══════════════════════════════════════ */
/** toast({ tone: 'success' | 'danger' | 'info', text, action, phone }) — ink, bottom start corner on desktop, full width above the bottom bar on a phone. */
export const toast = ({ tone: t = 'success', text, action, phone, w } = {}) => `<div role="${t === 'danger' ? 'alert' : 'status'}" style="display:flex;align-items:center;gap:12px;min-height:${phone ? 56 : 52}px;${phone ? 'width:100%;' : `width:${w ?? 400}px;`}border-radius:${R.inner}px;background:${C.ink};color:#FFFFFF;padding:8px 16px;padding-inline-end:${action ? 8 : 12}px;box-shadow:${SHADOW.floating}">
<span style="display:flex;color:${t === 'success' ? '#5BD4A0' : t === 'danger' ? '#FF9C94' : '#A8D8F0'}">${ico(t === 'success' ? 'check' : t === 'danger' ? 'alert' : 'info', 18, 2.25)}</span>
<span style="flex:1;min-width:0;${T.small}">${text}</span>
${action ? `<button type="button" style="height:${phone ? 44 : 36}px;padding:0 12px;border-radius:${R.control}px;background:rgba(255,255,255,.14);color:#FFFFFF;font-size:13px;font-weight:600;display:inline-flex;align-items:center;gap:6px;flex:none">${action === 'تراجع' ? ico('undo', 14, 2) : ''}<span>${action}</span></button>` : `<button type="button" aria-label="إغلاق" style="width:36px;height:36px;display:flex;align-items:center;justify-content:center;color:#C9D8E1;flex:none">${ico('x', 16)}</button>`}
</div>`;
/** An inline message inside a page or a form: note({ tone, title, text, action }). */
export const note = ({ tone: t = 'teal', title, text, action = '', icon } = {}) => `<div role="${t === 'danger' ? 'alert' : 'note'}" style="display:flex;align-items:flex-start;gap:12px;border-radius:${R.inner}px;background:${tone(t)[0]};padding:12px 16px;color:${C.ink}"><span style="display:flex;color:${tone(t)[1]};padding-top:2px">${ico(icon ?? (t === 'danger' || t === 'warning' ? 'alert' : t === 'success' ? 'check' : 'info'), 18, 2)}</span><div style="flex:1;min-width:0">${title ? `<div style="${T.small};font-weight:600">${title}</div>` : ''}${text ? `<div style="${T.label};color:${C.ink2}">${text}</div>` : ''}</div>${action}</div>`;
const stateBox = (iconName, t, title, text, action, o = {}) => `<div style="display:flex;flex-direction:column;align-items:center;text-align:center;gap:4px;padding:${o.phone ? '32px 16px' : '48px 24px'};${o.card ? CARD + ';' : ''}">
<span aria-hidden="true" style="width:56px;height:56px;border-radius:28px;background:${tone(t)[0]};color:${tone(t)[1]};display:flex;align-items:center;justify-content:center;margin-bottom:8px">${ico(iconName, 26)}</span>
<div style="${T.card}">${title}</div>
<div style="${T.small};color:${C.ink2};max-width:420px">${text}</div>
${action ? `<div style="margin-top:12px;display:flex;gap:8px;${o.phone ? 'align-self:stretch;flex-direction:column' : ''}">${action}</div>` : ''}
</div>`;
/** emptyState({ icon, title, text, action, phone, card }) — one sentence saying what will appear here, and the button that fills it. */
export const emptyState = ({ icon = 'info', title, text, action, phone, card } = {}) => stateBox(icon, 'teal', title, text, action, { phone, card });
/** errorState({ title, text, phone, card }) — plain Arabic, never the server's text; always a retry. */
export const errorState = ({ title = 'تعذّر تحميل الصفحة', text = 'حدث خطأ من جهتنا. حاول مرة أخرى، وإن تكرر فتواصل مع الدعم.', phone, card, retry = 'إعادة المحاولة' } = {}) => stateBox('alert', 'danger', title, text, btn(retry, { kind: 'secondary', icon: 'refresh', phone, full: phone }), { phone, card });
/** offlineBar({ phone }) — under the top bar, on every page, while there is no connection. */
export const offlineBar = ({ phone } = {}) => `<div role="status" style="flex:none;display:flex;align-items:center;gap:10px;min-height:44px;padding:8px ${phone ? 16 : 32}px;background:${C.warnBg};color:${C.warn};${T.label};font-weight:500"><span style="display:flex">${ico('wifiOff', 18, 2)}</span><span style="flex:1;min-width:0">${phone ? 'لا يوجد اتصال بالإنترنت. لن يُحفظ أي تغيير حتى يعود.' : 'لا يوجد اتصال بالإنترنت. ما تراه هو آخر ما حُمّل، ولن يُحفظ أي تغيير حتى يعود الاتصال.'}</span>${phone ? '' : `<button type="button" style="display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 10px;border-radius:${R.control}px;font-size:13px;font-weight:600;color:${C.warn};box-shadow:inset 0 0 0 1px ${C.warn}">${ico('refresh', 14, 2)}<span>حاول الآن</span></button>`}</div>`;
const sk = (w, h, r = 6, extra = '') => `<span aria-hidden="true" style="display:block;width:${typeof w === 'number' ? w + 'px' : w};height:${h}px;border-radius:${r}px;background:${C.sunken};flex:none;${extra}"></span>`;
/** skeleton('stat' | 'table' | 'list' | 'cards' | 'form' | 'text', { rows, cols, phone }) — the shape of what is loading. */
export function skeleton(kind = 'text', o = {}) {
  const rows = o.rows ?? 5;
  if (kind === 'bar') return sk(o.w ?? 120, o.h ?? 12);
  if (kind === 'stat') return `<div aria-busy="true" style="${CARD};padding:18px 20px;display:flex;flex-direction:column;gap:12px">${sk(96, 12)}${sk(72, 28, 8)}${sk(140, 10)}</div>`;
  if (kind === 'list') return `<div aria-busy="true" style="${CARD};overflow:hidden">${Array.from({ length: rows }, (_, i) => `<div style="display:flex;align-items:center;gap:12px;height:${o.rowH ?? 68}px;padding:0 20px;${i ? `border-top:1px solid ${C.hair}` : ''}">${sk(40, 40, 10)}<div style="flex:1;display:flex;flex-direction:column;gap:8px">${sk(`${[46, 38, 52, 34, 44][i % 5]}%`, 12)}${sk(`${[30, 24, 36, 22, 28][i % 5]}%`, 10)}</div>${o.phone ? '' : sk(96, 32, 10)}</div>`).join('')}</div>`;
  if (kind === 'table') {
    const cols = o.cols ?? 5;
    return `<div aria-busy="true" style="${CARD};overflow:hidden"><div style="display:flex;align-items:center;gap:12px;height:60px;padding:0 16px;border-bottom:1px solid ${C.hair}">${sk(280, 36, 10)}${sk(72, 28, 14)}${sk(88, 28, 14)}<span style="flex:1"></span>${sk(80, 12)}</div><div style="height:44px;background:${C.ground}"></div>${Array.from({ length: rows }, (_, i) => `<div style="display:grid;grid-template-columns:2fr repeat(${cols - 1},1fr);gap:24px;align-items:center;height:56px;padding:0 16px;border-top:1px solid ${C.hair}">${Array.from({ length: cols }, (_, c) => sk(`${[70, 50, 60, 40, 55, 45][(i + c) % 6]}%`, 12)).join('')}</div>`).join('')}</div>`;
  }
  if (kind === 'cards') return `<div aria-busy="true" style="display:flex;flex-direction:column;gap:12px">${Array.from({ length: rows }, (_, i) => `<div style="background:${C.surface};border-radius:${R.inner}px;box-shadow:${SHADOW.card};padding:14px 16px;display:flex;flex-direction:column;gap:12px"><div style="display:flex;justify-content:space-between">${sk(`${[52, 44, 60][i % 3]}%`, 14)}${sk(64, 22, 11)}</div>${sk('80%', 10)}${sk('56%', 10)}</div>`).join('')}</div>`;
  if (kind === 'form') return `<div aria-busy="true" style="${CARD};padding:24px;display:grid;grid-template-columns:${o.phone ? 'minmax(0,1fr)' : 'minmax(0,4fr) minmax(0,8fr)'};gap:${o.phone ? 16 : 32}px"><div style="display:flex;flex-direction:column;gap:10px">${sk(120, 14)}${sk('80%', 10)}</div><div style="display:flex;flex-direction:column;gap:16px">${Array.from({ length: rows > 3 ? 3 : rows }, () => `<div style="display:flex;flex-direction:column;gap:8px">${sk(80, 10)}${sk('100%', 44, 10)}</div>`).join('')}</div></div>`;
  return `<div aria-busy="true" style="display:flex;flex-direction:column;gap:10px">${Array.from({ length: rows }, (_, i) => sk(`${[90, 76, 84, 52, 68][i % 5]}%`, 12)).join('')}</div>`;
}

/** A drawn stand-in for a photographed transfer screenshot (receipts). */
export const receiptImg = (w, h, o = {}) => {
  const s = w / 300; const px = (n) => `${Math.round(n * s * 10) / 10}px`;
  const big = w >= 200;
  return `<div role="img" aria-label="صورة الإيصال" style="width:${w}px;height:${h}px;flex:none;border-radius:${o.r ?? R.inner}px;background:#D5E0E7;overflow:hidden;display:flex;align-items:center;justify-content:center">
<div style="width:${Math.round(w * 0.84)}px;height:${Math.round(h * 0.9)}px;background:#FFFFFF;border-radius:${px(14)};padding:${px(18)} ${px(16)};display:flex;flex-direction:column;align-items:center">
<span style="width:${px(44)};height:${px(44)};border-radius:50%;background:${C.okBg};color:${C.ok};display:flex;align-items:center;justify-content:center;flex:none">${ico('check', Math.max(8, Math.round(22 * s)), 2.5)}</span>
${big ? `<span style="font-size:${px(14)};line-height:${px(22)};color:${C.ink2};margin-top:${px(8)}">تم التحويل بنجاح</span>
<span dir="ltr" style="font-size:${px(30)};line-height:${px(40)};font-weight:600">${o.amount || '4,500.00'} <span style="font-size:${px(13)};font-weight:400;color:${C.ink3}">EGP</span></span>
<div style="align-self:stretch;margin-top:${px(12)};border-top:1px dashed #C3D1DA;padding-top:${px(10)};display:flex;flex-direction:column;gap:${px(8)};font-size:${px(12)};line-height:${px(18)};color:${C.ink2}">
<div style="display:flex;justify-content:space-between;gap:8px"><span>إلى</span><span dir="ltr" style="color:${C.ink};font-weight:500">elnawras@instapay</span></div>
<div style="display:flex;justify-content:space-between;gap:8px"><span>من</span><span style="color:${C.ink};font-weight:500">${o.from || 'منة الله إ. عبد الرازق'}</span></div>
<div style="display:flex;justify-content:space-between;gap:8px"><span>الرقم المرجعي</span><span dir="ltr" style="color:${C.ink};font-weight:500">3098 4471 2256</span></div>
</div>` : `<span style="display:block;width:70%;height:4px;border-radius:2px;background:${C.ink2};margin-top:5px"></span>${[90, 78, 84].map((x) => `<span style="display:block;width:${x}%;height:3px;border-radius:2px;background:${C.disabled};margin-top:4px"></span>`).join('')}`}
</div></div>`;
};

/* ══ Board writer ═══════════════════════════════════════════════════ */
const CSS = `body{margin:0}
*{box-sizing:border-box}
button{font:inherit;color:inherit;background:none;border:0;padding:0;cursor:pointer}
a{color:${C.teal};text-decoration:none}
table{font:inherit;color:inherit}
th{font-weight:inherit}
input,textarea{font:inherit;color:inherit}`;

const saved = {};
for (const f of fs.readdirSync(here)) if (/^heights.*\.json$/.test(f)) { try { Object.assign(saved, JSON.parse(fs.readFileSync(path.join(here, f), 'utf8'))); } catch { /* not measured yet */ } }
export const boards = [];

/**
 * board('AdmStudents', { row, w, title, tab, body: (size) => html, min, h, lang, interactive })
 * body receives the root size string ("width:1440px;height:1234px") and must put it on the element
 * that carries `data-root` (the shells do). Height: `h` fixes it; otherwise it is measured
 * (node shot.mjs measure <batch>) and never below `min` (default: 900 desktop, 1000 tablet, 844 phone).
 * Phone boards are 390 wide and get NO radius.
 */
export function board(file, o) {
  const { w, title, tab, body, lang = 'ar', row, interactive = false } = o;
  const min = o.min ?? (w <= 430 ? 844 : w < 1024 ? 1000 : 900);
  const h = o.h ?? Math.max(min, saved[file] ?? 0);
  const make = (root, extra = '') => `<!doctype html>
<html lang="${lang}"${lang === 'ar' ? ' dir="rtl"' : ''}>
<head>
<meta charset="utf-8">
<title>${tab ?? title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=Readex+Pro:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
${CSS}
</style>
</helmet>
${root}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":${w},"height":${h}}}'>
class Component extends DCLogic {
renderVals() {
return {};
}
}
</script>
${extra}</body>
</html>
`;
  const html = body(`width:${w}px;height:${h}px`);
  if (/\{\{|\}\}/.test(html)) throw new Error(`kit: ${file} contains {{ or }} — the canvas runtime would treat it as a placeholder`);
  fs.writeFileSync(path.join(OUT, `${file}.dc.html`), make(html));
  if (o.h == null) {
    fs.mkdirSync(MEASURE, { recursive: true });
    fs.writeFileSync(path.join(MEASURE, `${file}.dc.html`), make(body(`width:${w}px;min-height:10px`), `<script>setTimeout(function(){var r=document.querySelector('[data-root]');var h=r?Math.ceil(r.getBoundingClientRect().height):-1;try{var x=new XMLHttpRequest();x.open('GET','/__h?n=${file}&h='+h,false);x.send();}catch(e){}},2500)</script>\n`));
  }
  boards.push({ file: `${file}.dc.html`, row, w, h, title, is_interactive: !!interactive });
}

/**
 * finish({ batch, rows }) — writes the index of the boards this script drew.
 * batch 'foundation' → project/boards.json; any other batch → project/boards.<batch>.json (merged later).
 */
export function finish({ batch = 'foundation', rows = { A: 'Foundations', B: 'Shell', C: 'Today' } } = {}) {
  const name = batch === 'foundation' ? 'boards.json' : `boards.${batch}.json`;
  const order = Object.keys(rows);
  boards.sort((a, b) => order.indexOf(a.row) - order.indexOf(b.row)); // stable: keeps drawing order inside a row
  fs.writeFileSync(path.join(OUT, name), JSON.stringify({ rows, boards }, null, 1));
  fs.writeFileSync(path.join(here, `names.${batch}.txt`), boards.map((b) => b.file.replace('.dc.html', '')).join('\n'));
  console.log(boards.map((b) => `${b.file} ${b.w}x${b.h}`).join('\n'));
}
