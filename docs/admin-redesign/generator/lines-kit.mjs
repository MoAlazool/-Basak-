/** Local helpers and sample data for the `lines` batch (lines, ride confirmation, supervisors, company managers). */
import { board, shellDesktop, scrim, badge, btn, iconBtn, ico, time, ltr, C, T, R, CARD, FONT, SHADOW } from './kit.mjs';

export const ELL = 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
export const col = (inner, gap = 12, extra = '') => `<div style="display:flex;flex-direction:column;gap:${gap}px;min-width:0;${extra}">${inner}</div>`;
export const row = (inner, gap = 8, extra = '') => `<div style="display:flex;align-items:center;gap:${gap}px;min-width:0;${extra}">${inner}</div>`;
export const card = (inner, pad = 20, extra = '') => `<section style="${CARD};padding:${pad}px;display:flex;flex-direction:column;gap:12px;min-width:0;${extra}">${inner}</section>`;
export const h3 = (t, end = '') => `<div style="display:flex;align-items:center;gap:10px;min-height:28px"><h3 style="margin:0;${T.card}">${t}</h3><span style="flex:1"></span>${end}</div>`;
export const small = (t, color = C.ink2) => `<p style="margin:0;${T.label};color:${color}">${t}</p>`;
export const text = (t, color = C.ink) => `<p style="margin:0;${T.small};color:${color}">${t}</p>`;
export const hr = `<div aria-hidden="true" style="height:1px;background:${C.hair}"></div>`;

/** A person's round picture: initial on a tint, or (photo: true) a drawn portrait stand-in. */
export const avatar = (name, s = 36, o = {}) => `<span aria-hidden="true" style="width:${s}px;height:${s}px;border-radius:${s / 2}px;flex:none;display:flex;align-items:center;justify-content:center;font-size:${Math.round(s * 0.42)}px;font-weight:600;position:relative;${o.photo ? `background:${C.ink};color:#FFFFFF` : `background:${C.tint};color:${C.teal}`}">${o.photo ? ico('user', Math.round(s * 0.55)) : name.trim()[0]}${o.cam ? `<span style="position:absolute;bottom:-2px;inset-inline-end:-2px;width:22px;height:22px;border-radius:11px;background:${C.teal};color:#FFFFFF;display:flex;align-items:center;justify-content:center;box-shadow:0 0 0 2px ${C.surface}">${ico('image', 12, 2)}</span>` : ''}</span>`;

/** The open ⋮ menu of a row or a page: [{ label, icon, danger, sub }]. */
export const menu = (items, w = 232) => `<div role="menu" style="width:${w}px;background:${C.surface};border-radius:${R.inner}px;box-shadow:${SHADOW.floating}, 0 0 0 1px ${C.hair};padding:6px;display:flex;flex-direction:column">${items.map((i) => i === '-' ? `<span aria-hidden="true" style="height:1px;background:${C.hair};margin:6px 0"></span>` : `<button type="button" role="menuitem" style="display:flex;align-items:center;gap:10px;min-height:44px;padding:6px 10px;border-radius:8px;text-align:start;color:${i.danger ? C.bad : C.ink};${i.hover ? `background:${C.ground};` : ''}"><span style="display:flex;color:${i.danger ? C.bad : C.ink2}">${ico(i.icon, 18)}</span><span style="flex:1;min-width:0;display:flex;flex-direction:column"><span style="${T.small};font-weight:500">${i.label}</span>${i.sub ? `<span style="${T.cap};color:${C.ink3}">${i.sub}</span>` : ''}</span></button>`).join('')}</div>`;

/** Two or three views of one thing (ذهاب / عودة). */
export const seg = (tabs, o = {}) => `<div role="tablist" style="display:${o.full ? 'grid' : 'inline-grid'};grid-auto-flow:column;grid-auto-columns:${o.full ? 'minmax(0,1fr)' : 'auto'};gap:4px;background:${C.sunken};border-radius:${R.control}px;padding:4px">${tabs.map((t) => `<button type="button" role="tab" aria-selected="${!!t.on}" style="height:${o.phone ? 40 : 36}px;padding:0 16px;border-radius:7px;font-size:14px;font-weight:${t.on ? 600 : 400};color:${t.on ? C.ink : C.ink2};${t.on ? `background:${C.surface};box-shadow:${SHADOW.card};` : ''}display:inline-flex;align-items:center;justify-content:center;gap:8px;white-space:nowrap"><span>${t.label}</span>${t.count != null ? `<span style="font-size:12px;color:${C.ink3}">${t.count}</span>` : ''}</button>`).join('')}</div>`;

/** A choice that is on or off inside a form (a weekday, a line): pressed = chosen. */
export const pick = (label, on, o = {}) => `<button type="button" aria-pressed="${!!on}" style="display:inline-flex;align-items:center;gap:8px;height:${o.phone ? 48 : 40}px;padding:0 14px 0 12px;padding-inline:12px 14px;border-radius:${R.control}px;font-size:14px;font-weight:${on ? 600 : 400};background:${on ? C.tint : C.surface};color:${on ? C.teal : C.ink};box-shadow:inset 0 0 0 ${on ? `2px ${C.teal}` : `1px ${C.disabled}`};white-space:nowrap;${o.full ? 'width:100%;' : ''}${o.muted ? `color:${C.ink3};` : ''}"><span aria-hidden="true" style="width:20px;height:20px;border-radius:6px;flex:none;display:flex;align-items:center;justify-content:center;${on ? `background:${C.teal};color:#FFFFFF` : `background:${C.surface};box-shadow:inset 0 0 0 1.5px ${C.ink3}`}">${on ? ico('check', 14, 3) : ''}</span><span style="flex:1;min-width:0;text-align:start;${ELL}">${label}</span>${o.end ?? ''}</button>`;

/** A value that can be taken away (a holiday date). */
export const tag = (label, o = {}) => `<span style="display:inline-flex;align-items:center;gap:4px;height:${o.phone ? 44 : 36}px;padding-inline:12px 4px;border-radius:${R.control}px;background:${C.sunken};color:${C.ink};font-size:13px;font-weight:500;white-space:nowrap">${label}<button type="button" aria-label="حذف ${o.name ?? ''}" style="width:${o.phone ? 40 : 30}px;height:${o.phone ? 40 : 30}px;display:flex;align-items:center;justify-content:center;color:${C.ink2}">${ico('x', 14, 2)}</button></span>`;

/** A compact control inside dense forms (stop times): value or placeholder, optional error ring. */
export const box = (value, o = {}) => `<span style="display:inline-flex;align-items:center;gap:6px;height:${o.h ?? 40}px;width:${o.w ? o.w + 'px' : '100%'};flex:none;border-radius:${R.control}px;padding:0 10px;background:${o.off ? C.ground : C.surface};box-shadow:inset 0 0 0 ${o.error ? `2px ${C.bad}` : o.focus ? `2px ${C.teal}` : `1px ${o.off ? C.hair : C.disabled}`};font-size:14px;color:${o.off || o.ph ? C.ink3 : C.ink};white-space:nowrap"><span style="flex:1;min-width:0;${ELL}">${value}</span>${o.icon ? `<span style="display:flex;color:${C.ink3}">${ico(o.icon, 16)}</span>` : ''}</span>`;

/** n riders against the bus seats, with a meter; amber when the bus is too small. */
export const seatsMeter = (n, seats, o = {}) => {
  const over = seats && n > seats;
  const pct = seats ? Math.min(100, Math.round((n / seats) * 100)) : 0;
  return `<div style="display:flex;flex-direction:column;gap:4px;min-width:0"><div style="display:flex;align-items:baseline;gap:4px;white-space:nowrap"><span style="font-size:${o.big ? 18 : 15}px;font-weight:600;color:${n ? C.ink : C.disabled}">${n}</span>${seats ? `<span style="${T.cap};color:${C.ink3}">من ${seats}</span>` : ''}</div>${seats ? `<div aria-hidden="true" style="height:5px;border-radius:3px;background:${C.sunken};overflow:hidden"><div style="width:${pct}%;height:5px;border-radius:3px;background:${over ? C.warn : C.teal}"></div></div>` : ''}${over ? `<span style="${T.cap};font-weight:500;color:${C.warn};white-space:nowrap">يزيد ${n - seats}</span>` : ''}</div>`;
};

/** One captioned state inside a states board (same look as AdmTodayStates). */
export const frame = (label, textEn, inner) => `<section style="display:flex;flex-direction:column;gap:12px">
<div dir="ltr" style="display:flex;align-items:baseline;gap:12px"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600;white-space:nowrap">${label}</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2}">${textEn}</p></div>
<div style="border-radius:${R.inner}px;overflow:hidden;box-shadow:0 0 0 1px ${C.hair}, 0 16px 40px -12px rgba(23,56,74,.28)">${inner.replace('data-root ', '')}</div>
</section>`;
export const FW = 1312;
/** A board of stacked captioned states at 1440. frames: [[label, text, html]]. */
export const statesBoard = (file, o, frames) => board(file, { row: o.row, w: 1440, lang: 'en', title: o.title, tab: o.title,
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">${frames.map((f) => frame(...f)).join('\n')}</div>` });
/** A board of every confirmation a page can open, two per row, each on the dimmed page colour. items: [[label, text, dialogHtml]]. */
export const dialogsBoard = (file, o, items) => board(file, { row: o.row, w: 1440, lang: 'en', title: o.title, tab: o.title,
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:32px">
<div dir="ltr"><h1 style="margin:0;font-size:28px;line-height:36px;font-weight:600">${o.heading}</h1><p style="margin:4px 0 0;font-size:14px;line-height:22px;color:${C.ink2};max-width:900px">${o.intro ?? 'Every yes/no this page can ask. Centred, 480 wide, over the dimmed page; bottom-anchored and full width on a phone. Cancel is always «رجوع»; the confirm button repeats the verb; a destructive confirm is red and never the default focus.'}</p></div>
<div style="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:32px 32px;align-items:start">${items.map(([label, textEn, dlg]) => `<section style="display:flex;flex-direction:column;gap:10px"><div dir="ltr"><h2 style="margin:0;font-size:16px;line-height:24px;font-weight:600">${label}</h2><p style="margin:0;font-size:13px;line-height:20px;color:${C.ink2}">${textEn}</p></div><div dir="rtl" style="border-radius:${R.inner}px;background:#8A9BA5;padding:32px 0;display:flex;justify-content:center">${dlg}</div></section>`).join('\n')}</div>
</div>` });

export const back = (label = 'رجوع', o = {}) => btn(label, { kind: 'secondary', ...o });

/* ══ Sample data (all invented) ═════════════════════════════════════ */
export const UNI = ['جامعة دمياط', 'جامعة حورس', 'المعهد العالي للهندسة بدمياط الجديدة'];
export const UNI_ALL = [...UNI, 'جامعة المنصورة', 'جامعة الدلتا للعلوم والتكنولوجيا', 'المعهد العالي للحاسبات برأس البر'];
export const LINES = [
  { name: 'دمياط الجديدة', unis: [0, 1, 2], st: 9, go: 6, ret: 6, subs: 168, rgo: 124, rback: 118, seats: 50, sup: ['إبراهيم الدسوقي عبد الحميد', 'عبد الرحمن محمد السيد الشربيني'], vis: 'on' },
  { name: 'الزرقا', unis: [0, 1], st: 8, go: 5, ret: 5, subs: 124, rgo: 107, rback: 105, seats: 50, sup: ['محمود السيد عبد الغني'], vis: 'on' },
  { name: 'شربين', unis: [0], st: 10, go: 5, ret: 4, subs: 112, rgo: 81, rback: 75, seats: 45, sup: [], vis: 'on' },
  { name: 'فارسكور', unis: [0, 1], st: 8, go: 5, ret: 5, subs: 96, rgo: 71, rback: 68, seats: 45, over: 2, sup: ['هاني عبد المقصود', 'أحمد رضا الجمل'], vis: 'on' },
  { name: 'كفر سعد', unis: [0], st: 7, go: 4, ret: 4, subs: 74, rgo: 52, rback: 49, seats: 30, sup: ['سامح فتحي البنا'], vis: 'on' },
  { name: 'السرو', unis: [0, 1], st: 6, go: 3, ret: 3, subs: 61, rgo: 44, rback: 40, seats: 30, sup: ['محمود السيد عبد الغني'], vis: 'on' },
  { name: 'ميت أبو غالب', unis: [0], st: 5, go: 3, ret: 3, subs: 45, rgo: 33, rback: 31, seats: 30, sup: ['إبراهيم الدسوقي عبد الحميد'], vis: 'on' },
  { name: 'كفر البطيخ', unis: [0], st: 6, go: 0, ret: 2, subs: 38, rgo: 0, rback: 0, seats: 30, sup: ['سامح فتحي البنا'], vis: 'hidden', why: 'تنقصه رحلة ذهاب إلى جامعة دمياط', fix: 'أضف رحلة' },
  { name: 'عزبة البرج', unis: [0], st: 5, go: 2, ret: 2, subs: 0, rgo: 0, rback: 0, seats: null, sup: [], vis: 'hidden', why: 'لم يُكتب سعر لأي اشتراك', fix: 'اكتب الأسعار' },
  { name: 'رأس البر', unis: [0, 2], st: 7, go: 3, ret: 3, subs: 12, rgo: 9, rback: 8, seats: 30, sup: ['هاني عبد المقصود'], vis: 'off', why: 'أوقفته أنت. مشتركوه الحاليون مستمرون' },
];
export const uniShort = (l) => l.unis.map((i) => UNI[i].replace('المعهد العالي للهندسة بدمياط الجديدة', 'المعهد العالي للهندسة')).join(' · ');
export const SUPS = [
  { name: 'إبراهيم الدسوقي عبد الحميد', phone: '010 2345 6789', lines: ['دمياط الجديدة', 'ميت أبو غالب'], on: true, photo: true },
  { name: 'محمود السيد عبد الغني', phone: '011 3456 7890', lines: ['الزرقا', 'السرو'], on: true, photo: true },
  { name: 'هاني عبد المقصود', phone: '012 4567 8901', lines: ['فارسكور', 'رأس البر'], on: true },
  { name: 'سامح فتحي البنا', phone: '015 5678 9012', lines: ['كفر سعد', 'كفر البطيخ'], on: true, photo: true },
  { name: 'عبد الرحمن محمد السيد الشربيني', phone: '010 6789 0123', lines: ['دمياط الجديدة'], on: true },
  { name: 'أحمد رضا الجمل', phone: '011 7890 1234', lines: ['فارسكور'], on: true, photo: true },
  { name: 'مصطفى كمال أبو العينين', phone: '012 8901 2345', lines: [], on: true },
  { name: 'طارق عبد الفتاح سليمان', phone: '015 9012 3456', lines: ['الزرقا'], on: false },
  { name: 'ياسر حمدي عوض', phone: '010 0123 4567', lines: ['كفر سعد'], on: false, photo: true },
];
export const NO_SUP = LINES.filter((l) => !l.sup.length && l.vis !== 'off').map((l) => l.name);

/* The Zarqa line in full: the line page and the new-line steps use the same route. */
export const STATIONS = ['موقف الزرقا', 'كوبري الزرقا', 'ميت الخولي عبد الله', 'شرباص', 'كفر المياسرة', 'السرو – المزلقان', 'دقهلة', 'مدخل فارسكور'];
const clock = (min) => { const h = Math.floor(min / 60); const m = min % 60; const h12 = ((h + 11) % 12) + 1; return [`${h12}:${String(m).padStart(2, '0')}`, h < 12 ? 'ص' : 'م']; };
export const at = (min) => time(...clock(min));
/** Going trips: start (minutes from midnight), gap, stations skipped, riders tomorrow, who it is for. */
export const GO = [
  { start: 375, gap: 6, skip: [], riders: 22, uni: null, label: 'أول رحلة' },
  { start: 405, gap: 6, skip: [], riders: 31, uni: null, label: '' },
  { start: 420, gap: 6, skip: [], riders: 38, uni: null, label: '' },
  { start: 450, gap: 6, skip: [2, 6], riders: 12, uni: null, label: 'سريعة' },
  { start: 495, gap: 6, skip: [], riders: 4, uni: 1, label: '' },
];
export const stopAt = (t, i) => (t.skip.includes(i) ? null : t.start + t.gap * i);
export const arrive = (t) => t.start + t.gap * (STATIONS.length - 1) + 25;
export const BACK = [
  { start: 780, riders: 14, uni: null }, { start: 840, riders: 27, uni: null }, { start: 900, riders: 35, uni: null },
  { start: 960, riders: 21, uni: 0 }, { start: 1050, riders: 8, uni: 1 },
];
export const forUni = (u) => (u == null ? 'كل جامعات الخط' : UNI[u]);
export const TOMORROW = 'الأحد 11 أكتوبر';
export { ltr, badge, iconBtn, shellDesktop, scrim };
