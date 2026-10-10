/** Platform batch — shared data and local helpers (candidates for the kit are marked LOCAL HELPER). */
import {
  board, shellDesktop, shellPhone, btn, badge, state, ltr, ico, C, T, R, CARD, FONT, SHADOW, emptyState,
} from './kit.mjs';

export const DATE = 'السبت 10 أكتوبر 2026';
export const TOMORROW = 'الأحد 11 أكتوبر';
/** The kit's platform top bar leaves ~90px for the breadcrumb (spacer + 380 search + switcher); this local patch drops the spacer and narrows the search. */
export const P = (o) => shellDesktop({ role: 'platform', ...o }).replace('<div style="flex:1"></div>', '').replace('width:380px;', 'width:320px;');
export const PP = (o) => shellPhone({ role: 'platform', ...o });
export const phoneNo = (s) => ltr(s);
export const num = (n) => n.toLocaleString('en-US');

/* ── seeded numbers so every run draws the same boards ── */
let seed = 7;
export const rnd = (a, b) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return a + (seed % (b - a + 1)); };
export const pick = (arr) => arr[rnd(0, arr.length - 1)];

/* ── Companies (invented) ── */
const CN = ['النورس للنقل', 'الصفوة للرحلات', 'باصات النيل', 'الفيروز لنقل الطلاب', 'أبناء الدقهلية للنقل الجماعي', 'السلام ترافل', 'المدينة للرحلات الجامعية', 'الأمانة لنقل الطلاب',
  'رحلات الشروق', 'الهدى للنقل', 'خطوط الدلتا', 'الريان باص', 'النخبة للنقل الجامعي', 'المنارة ترانس', 'الوفاء لنقل الطلاب', 'البدر للرحلات', 'أولاد الحاج سعيد للنقل',
  'الياسمين باص', 'القمة للنقل', 'الأصدقاء للرحلات', 'طيبة لنقل الطلاب', 'الرحاب ترانس', 'النجمة الذهبية للنقل', 'المستقبل باص', 'الإخلاص للرحلات الجامعية',
  'الكوثر للنقل', 'دمياط الجديدة للنقل الجماعي', 'الأندلس باص', 'السندباد للرحلات', 'الفرسان للنقل', 'البركة لنقل الطلاب'];
const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
export const COMPANIES = CN.map((name, i) => {
  const st = i === 9 || i === 22 ? 'suspended' : i === 28 || i === 29 || i === 30 ? 'archived' : 'on';
  const fresh = i === 1 || i === 17;            // just created: nothing set up
  const total = fresh ? (i === 1 ? 1 : 0) : rnd(2, 9);
  const active = fresh ? total : Math.max(1, total - rnd(0, 2));
  const students = fresh ? 0 : i === 0 ? 806 : rnd(40, 640);
  const live = st === 'on' && !fresh;
  return {
    name, st, since: i === 1 ? '10 أكتوبر 2026' : i === 17 ? '4 أكتوبر 2026' : ((d, m) => `${d} ${MONTHS[i >= 12 && m > 8 ? m - 4 : m]} ${i < 12 ? 2025 : 2026}`)(rnd(1, 28), rnd(0, 11)),
    lines: [active, total], students, subs: live ? Math.round(students * rnd(62, 91) / 100) : 0,
    admins: fresh ? 1 : rnd(1, 3), sups: fresh ? 0 : rnd(1, 7),
    pay: fresh ? 0 : i === 12 ? 0 : rnd(1, 3), sale: live && i !== 6,
    rec: live ? (i === 0 ? 7 : i % 4 === 0 ? 0 : rnd(0, 14)) : 0,
    go: live ? Math.round(students * rnd(48, 74) / 100) : 0,
    rev: fresh ? 0 : students * rnd(2600, 4100),
    phone: `010 ${rnd(1000, 9999)} ${rnd(1000, 9999)}`,
  };
});
if (COMPANIES[0]) { COMPANIES[0].lines = [7, 8]; COMPANIES[0].go = 512; COMPANIES[0].subs = 718; COMPANIES[0].admins = 2; COMPANIES[0].sups = 4; COMPANIES[0].pay = 2; }
export const coState = (c) => state(c.st, c.st === 'on' ? 'تعمل' : undefined);
export const LIVE = COMPANIES.filter((c) => c.st === 'on');
export const ALL_STUDENTS = COMPANIES.reduce((a, c) => a + c.students, 0) + 143;

/* ── People (invented) ── */
const FIRST = ['منة الله', 'عبد الرحمن', 'يوسف', 'ملك', 'عمر', 'سلمى', 'مريم', 'أحمد', 'ندى', 'محمود', 'روان', 'زياد', 'هاجر', 'كريم', 'آية', 'مصطفى', 'بسملة', 'إسلام', 'شهد', 'حازم'];
const MID = ['إبراهيم', 'محمد السيد', 'أحمد', 'حسام الدين', 'خالد', 'طارق', 'عبد الله', 'السيد', 'مجدي', 'عادل', 'وليد', 'ياسر', 'سامي'];
const LAST = ['عبد الرازق', 'الشربيني', 'عبد الفتاح', 'منصور', 'إسماعيل البنا', 'عبد الحميد', 'الدسوقي', 'أبو العينين', 'الجمال', 'عبد المقصود', 'البدراوي', 'الشناوي', 'غنيم', 'أبو زيد', 'المرسي'];
export const personName = () => `${pick(FIRST)} ${pick(MID)} ${pick(LAST)}`;
export const mobile = () => `01${pick(['0', '1', '2', '5'])} ${rnd(1000, 9999)} ${rnd(1000, 9999)}`;
export const UNIS = [
  { name: 'جامعة المنصورة', city: 'المنصورة', colleges: 18, students: 2140, cos: 14, on: true },
  { name: 'جامعة دمياط', city: 'دمياط الجديدة', colleges: 11, students: 1386, cos: 9, on: true },
  { name: 'جامعة حورس', city: 'دمياط الجديدة', colleges: 9, students: 962, cos: 8, on: true },
  { name: 'جامعة الدلتا للعلوم والتكنولوجيا', city: 'جمصة', colleges: 8, students: 874, cos: 11, on: true },
  { name: 'جامعة المنصورة الجديدة', city: 'المنصورة الجديدة', colleges: 10, students: 511, cos: 6, on: true },
  { name: 'المعهد العالي للهندسة والتكنولوجيا', city: 'دمياط الجديدة', colleges: 4, students: 238, cos: 3, on: true },
  { name: 'جامعة المنصورة الأهلية', city: 'جمصة', colleges: 6, students: 197, cos: 4, on: true },
  { name: 'الأكاديمية العربية للعلوم والتكنولوجيا', city: 'دمياط الجديدة', colleges: 3, students: 94, cos: 2, on: true },
  { name: 'المعهد العالي للعلوم الإدارية', city: 'المنصورة', colleges: 2, students: 61, cos: 2, on: true },
  { name: 'جامعة الأزهر · فرع دمياط الجديدة', city: 'دمياط الجديدة', colleges: 5, students: 19, cos: 1, on: true },
  { name: 'جامعة كفر الشيخ', city: 'كفر الشيخ', colleges: 0, students: 0, cos: 0, on: true },
  { name: 'معهد مصر العالي للتجارة والحاسبات', city: 'المنصورة', colleges: 2, students: 12, cos: 0, on: false },
];

/* ── LOCAL HELPER: a labelled frame on a white spec sheet (states, dialogs) ── */
export const frame = (label, text, inner, o = {}) => `<section style="display:flex;flex-direction:column;gap:12px;${o.w ? `width:${o.w}px;flex:none;` : ''}">
<div dir="ltr" style="display:flex;flex-direction:column;gap:2px"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600">${label}</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2};max-width:920px">${text}</p></div>
<div style="border-radius:${R.inner}px;overflow:hidden;box-shadow:0 0 0 1px ${C.hair}, 0 16px 40px -12px rgba(23,56,74,.28)">${inner.replace('data-root ', '')}</div>
</section>`;
/** A whole 1312-wide platform page inside a frame. */
export const mini = (h, o) => P({ size: `width:1312px;height:${h}px`, ...o });
/** LOCAL HELPER: a spec sheet board — stacked frames with English captions outside the mocks. */
export const sheetBoard = (file, row, name, frames, o = {}) => board(file, { row, w: 1440, lang: 'en', title: `Admin web · Platform · ${name}`, tab: `Basak admin web · Platform · ${name}`,
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">${frames.join('\n')}</div>` });
/** LOCAL HELPER: a dialog on its dimmed backdrop, for dialog sheets. phone: bottom-anchored at 390. */
export const dlgTile = (label, text, dlg, o = {}) => frame(label, text, o.phone
  ? `<div dir="rtl" style="width:390px;min-height:${o.h ?? 560}px;background:#8FA0AB;display:flex;align-items:flex-end;${FONT};color:${C.ink}">${dlg}</div>`
  : `<div dir="rtl" style="background:#8FA0AB;padding:40px 24px;display:flex;justify-content:center;align-items:center;min-height:${o.h ?? 320}px;${FONT};color:${C.ink}">${dlg}</div>`, { w: o.phone ? 390 : o.w ?? 640 });
export const tiles = (list) => `<div style="display:flex;flex-wrap:wrap;gap:48px 32px;align-items:flex-start">${list.join('\n')}</div>`;

/** LOCAL HELPER: a dropdown filter button for a table toolbar («كل الشركات ▾»). */
export const dropFilter = (label, o = {}) => `<button type="button" aria-haspopup="listbox" style="display:inline-flex;align-items:center;gap:6px;height:${o.phone ? 40 : 36}px;padding:0 12px;border-radius:${R.control}px;font-size:13px;line-height:20px;color:${C.ink};background:${C.surface};box-shadow:inset 0 0 0 1px ${o.on ? C.teal : C.hair};white-space:nowrap;flex:none">${o.icon ? ico(o.icon, 14, 2) : ''}<span>${label}</span>${ico('down', 14, 2)}</button>`;
/** LOCAL HELPER: underline tabs inside a page (Android / iPhone; history / new). */
export const tabs = (list, o = {}) => `<div role="tablist" style="display:flex;gap:${o.phone ? 4 : 8}px;border-bottom:1px solid ${C.hair}">${list.map((t) => `<button type="button" role="tab" aria-selected="${!!t.on}" style="display:inline-flex;align-items:center;gap:8px;height:${o.phone ? 48 : 44}px;padding:0 ${o.phone ? 12 : 16}px;font-size:14px;line-height:20px;font-weight:${t.on ? 600 : 400};color:${t.on ? C.teal : C.ink2};box-shadow:${t.on ? `inset 0 -2px 0 ${C.teal}` : 'none'};${o.phone ? 'flex:1;justify-content:center;' : ''}">${t.icon ? ico(t.icon, 16, 2) : ''}<span>${t.label}</span>${t.meta ?? ''}</button>`).join('')}</div>`;
/** LOCAL HELPER: «before → after» side by side (stacked on a phone). */
export const beforeAfter = (label, before, after, o = {}) => `<div style="display:grid;grid-template-columns:${o.phone ? 'minmax(0,1fr)' : 'minmax(0,1fr) 24px minmax(0,1fr)'};gap:${o.phone ? 6 : 8}px;align-items:stretch">
<div style="border-radius:${R.inner}px;background:${C.ground};padding:12px 14px"><div style="${T.cap};color:${C.ink3}">${label} الآن</div><div style="${T.body};font-weight:500;color:${C.ink2}">${before}</div></div>
<span aria-hidden="true" style="display:flex;align-items:center;justify-content:center;color:${C.ink3}">${ico(o.phone ? 'adown' : 'arrowFwd', 18, 2)}</span>
<div style="border-radius:${R.inner}px;background:${C.tint};box-shadow:inset 0 0 0 1.500px ${C.teal};padding:12px 14px"><div style="${T.cap};color:${C.teal}">${label} بعد التغيير</div><div style="${T.body};font-weight:600">${after}</div></div>
</div>`;
/** LOCAL HELPER: a one-time code or temporary password, shown once, with a named copy button. */
export const codeBox = (code, o = {}) => `<div style="border-radius:${R.inner}px;background:${C.okBg};padding:16px;display:flex;flex-direction:column;align-items:center;gap:10px">
<div dir="ltr" style="font-size:${o.size ?? 34}px;line-height:44px;font-weight:600;letter-spacing:${o.spacing ?? 8}px;color:${C.ink}">${code}</div>
${btn(o.copy ?? 'انسخ الرمز', { kind: 'outline', icon: 'copy', sm: true })}
</div>`;
/** LOCAL HELPER: a group title inside a side panel. */
export const panelHead = (t, end = '') => `<div style="display:flex;align-items:center;gap:8px"><h3 style="margin:0;${T.small};font-weight:600">${t}</h3><span style="flex:1"></span>${end}</div>`;
export const group = (title, inner, end) => `<div style="display:flex;flex-direction:column;gap:8px">${panelHead(title, end)}${inner}</div>`;
/** LOCAL HELPER: a ticked / missing line in a readiness list. */
export const checkRow = (ok, text, sub, end = '') => `<div style="display:flex;align-items:flex-start;gap:10px;padding:8px 0"><span aria-hidden="true" style="width:22px;height:22px;border-radius:11px;flex:none;display:flex;align-items:center;justify-content:center;background:${ok ? C.okBg : C.badBg};color:${ok ? C.ok : C.bad};margin-top:1px">${ico(ok ? 'check' : 'x', 13, 2.5)}</span><div style="flex:1;min-width:0"><div style="${T.small};font-weight:500">${text}</div>${sub ? `<div style="${T.label};color:${C.ink2}">${sub}</div>` : ''}</div>${end}</div>`;
/** A phone full page that stands for a side panel. */
export const phonePage = (o) => PP({ ...o, dot: false });
export const onlyBadge = badge('لمدير المنصة فقط', 'teal');
export const card = (inner, pad = 20) => `<div style="${CARD};padding:${pad}px;display:flex;flex-direction:column;gap:12px">${inner}</div>`;
export const emptyPhone = (file, row, name, active, o) => board(file, { row, w: 390, title: `Admin web · Platform · ${name} · Empty · Phone`, tab: `إدارة المنصة · ${name}`,
  body: (size) => PP({ size, active, dot: false, sub: o.sub, body: emptyState({ card: true, phone: true, ...o.empty }), bottomBar: o.bottom }) });
export { SHADOW };
