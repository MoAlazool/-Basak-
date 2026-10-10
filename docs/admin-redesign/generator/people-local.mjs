/** Local helpers and sample data of the `people` batch (receipts, password requests, students). */
import { C, T, R, CARD, FONT, SHADOW, ico, ltr, time, badge, btn, iconBtn } from './kit.mjs';

export const ELL = 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis';

/* ── Local helpers (candidates for the kit) ─────────────────────── */
/** Page tabs under the header: tabs([{ label, count, on }]). */
export const tabs = (items, o = {}) => `<div role="tablist" style="display:flex;gap:${o.phone ? 4 : 8}px;border-bottom:1px solid ${C.hair};${o.phone ? 'margin-inline:-16px;padding-inline:16px;overflow:hidden;' : ''}">${items.map((t) => `<a href="#" role="tab" aria-selected="${!!t.on}" style="display:inline-flex;align-items:center;gap:8px;height:${o.phone ? 48 : 44}px;padding:0 ${o.phone ? 10 : 12}px;font-size:14px;line-height:22px;font-weight:${t.on ? 600 : 400};color:${t.on ? C.teal : C.ink2};box-shadow:${t.on ? `inset 0 -2px 0 ${C.teal}` : 'none'};white-space:nowrap;flex:none"><span>${t.label}</span>${t.count != null ? `<span style="min-width:22px;height:20px;padding:0 6px;border-radius:10px;background:${t.on ? C.tint : C.sunken};color:${t.on ? C.teal : C.ink2};font-size:12px;line-height:20px;font-weight:500;text-align:center">${t.count}</span>` : ''}</a>`).join('')}</div>`;

/** A student's photo stand-in: the first letter on a tint. */
const AV = [[C.tint, C.teal], [C.okBg, C.ok], [C.warnBg, C.warn], [C.sunken, C.ink2]];
export const avatar = (name, s = 36) => { const [bg, fg] = AV[name.charCodeAt(0) % AV.length]; return `<span aria-hidden="true" style="width:${s}px;height:${s}px;border-radius:50%;background:${bg};color:${fg};display:flex;align-items:center;justify-content:center;font-size:${Math.round(s * 0.42)}px;font-weight:600;flex:none">${name[0]}</span>`; };
/** Name cell with the photo. */
export const person = (name, sub, o = {}) => `<div style="display:flex;align-items:center;gap:10px;min-width:0">${avatar(name, o.s ?? 36)}<div style="min-width:0"><div style="font-weight:${o.w ?? 500};${ELL}">${name}</div>${sub ? `<div style="font-size:12px;line-height:18px;color:${C.ink3};${ELL}">${sub}</div>` : ''}</div></div>`;

/** A filter that picks one value from a list (line, university): a labelled dropdown button. */
export const filterSelect = (label, value, o = {}) => `<button type="button" aria-haspopup="listbox" style="display:inline-flex;align-items:center;gap:6px;height:${o.phone ? 40 : 36}px;padding:0 12px;border-radius:${R.control}px;font-size:13px;line-height:20px;color:${C.ink};background:${o.on ? C.tint : C.surface};box-shadow:inset 0 0 0 1px ${o.on ? C.teal : C.hair};white-space:nowrap;flex:none"><span style="color:${C.ink3}">${label}</span><span style="font-weight:500">${value}</span>${ico('down', 14, 2)}</button>`;

/** A keyboard key. */
export const kbd = (k) => `<kbd dir="ltr" style="display:inline-flex;align-items:center;justify-content:center;min-width:24px;height:24px;padding:0 6px;border-radius:6px;background:${C.surface};box-shadow:inset 0 0 0 1px ${C.hair}, 0 1px 0 ${C.hair};font:inherit;font-size:12px;font-weight:600;color:${C.ink2}">${k}</kbd>`;
export const keyHints = (pairs) => `<div aria-label="اختصارات لوحة المفاتيح" style="display:flex;align-items:center;gap:14px;flex-wrap:wrap;${T.cap};color:${C.ink3}">${pairs.map(([k, l]) => `<span style="display:inline-flex;align-items:center;gap:6px">${kbd(k)}<span>${l}</span></span>`).join('')}</div>`;

/** A one-time code, large, with its copy button. */
export const codeBox = (code, o = {}) => `<div style="display:flex;align-items:center;gap:12px;border-radius:${R.inner}px;background:${C.tint};padding:${o.phone ? '14px 16px' : '16px 20px'}"><span dir="ltr" style="flex:1;font-size:${o.size ?? 36}px;line-height:${(o.size ?? 36) + 12}px;font-weight:600;letter-spacing:${o.spacing ?? 6}px;color:${C.ink};text-align:center;unicode-bidi:isolate">${code}</span>${btn('نسخ', { kind: 'outline', icon: 'copy', sm: !o.phone, phone: o.phone })}</div>`;

/** A titled block inside a panel or a detail page. */
export const block = (title, inner, o = {}) => `<section style="display:flex;flex-direction:column;gap:${o.gap ?? 8}px"><div style="display:flex;align-items:center;gap:8px"><h3 style="margin:0;${T.label};font-weight:600;color:${C.ink2}">${title}</h3><span style="flex:1"></span>${o.end ?? ''}</div>${inner}</section>`;
/** A bordered inner card (a subscription inside the student panel). */
export const innerCard = (inner, o = {}) => `<div style="border-radius:${R.inner}px;box-shadow:inset 0 0 0 1px ${C.hair};background:${o.bg ?? C.surface};padding:${o.pad ?? '14px 16px'};display:flex;flex-direction:column;gap:${o.gap ?? 12}px">${inner}</div>`;

/** A states sheet frame: an English caption outside the mock, the mock inside. */
export const frame = (label, text, inner) => `<section style="display:flex;flex-direction:column;gap:12px">
<div dir="ltr" style="display:flex;align-items:baseline;gap:12px"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600;white-space:nowrap">${label}</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2}">${text}</p></div>
<div dir="rtl" style="border-radius:${R.inner}px;overflow:hidden;box-shadow:0 0 0 1px ${C.hair}, ${SHADOW.floating}">${inner.replace('data-root ', '')}</div>
</section>`;
export const sheet = (size, inner, o = {}) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">${o.title ? `<div dir="ltr"><div style="font-size:12px;letter-spacing:1.5px;font-weight:600;color:${C.ink3}">BASAK · ADMIN WEB · 2026</div><h1 style="margin:4px 0 0;font-size:32px;line-height:40px;font-weight:600">${o.title}</h1>${o.sub ? `<p style="margin:6px 0 0;font-size:15px;line-height:24px;color:${C.ink2};max-width:900px">${o.sub}</p>` : ''}</div>` : ''}${inner}</div>`;
/** A sheet cell: a caption with a bare part under it (dialogs drawn on the dimmed ground). */
export const spec = (label, text, inner, o = {}) => `<div style="display:flex;flex-direction:column;gap:10px;min-width:0"><div dir="ltr"><div style="font-size:14px;line-height:22px;font-weight:600">${label}</div>${text ? `<div style="font-size:13px;line-height:20px;color:${C.ink2}">${text}</div>` : ''}</div><div dir="rtl" style="border-radius:${R.inner}px;background:${o.bg ?? '#8FA3AF'};padding:${o.pad ?? 28}px;display:flex;justify-content:center;align-items:flex-start;flex:1">${inner}</div></div>`;
export const W = 1312;

/* ── Sample data (all invented) ─────────────────────────────────── */
export const LINES = ['دمياط الجديدة', 'الزرقا', 'شربين', 'فارسكور', 'كفر سعد', 'السرو', 'ميت أبو غالب'];
export const STOPS = { 'دمياط الجديدة': 'موقف الحي الثالث', 'الزرقا': 'كوبري الزرقا', 'شربين': 'ميدان المحطة', 'فارسكور': 'موقف فارسكور القديم', 'كفر سعد': 'مدخل كفر سعد', 'السرو': 'كوبري السرو', 'ميت أبو غالب': 'مسجد النور' };
export const GO = { 'دمياط الجديدة': '7:30', 'الزرقا': '7:00', 'شربين': '6:45', 'فارسكور': '7:15', 'كفر سعد': '6:30', 'السرو': '7:00', 'ميت أبو غالب': '6:50' };
export const UNIS = [['جامعة دمياط', 'التجارة', 'محاسبة'], ['جامعة حورس', 'الصيدلة', ''], ['جامعة دمياط', 'الهندسة', 'مدني'], ['جامعة حورس', 'طب الأسنان', ''], ['جامعة دمياط', 'الآداب', 'لغة إنجليزية'], ['جامعة دمياط', 'العلوم', 'كيمياء'], ['المعهد العالي بدمياط الجديدة', 'نظم المعلومات', ''], ['جامعة دمياط', 'التربية', 'رياض أطفال'], ['جامعة حورس', 'العلاج الطبيعي', '']];
export const study = (u) => [u[1], u[2]].filter(Boolean).join(' · ');
const N = ['منة الله إبراهيم عبد الرازق السيد', 'عبد الرحمن محمد السيد الشربيني', 'يوسف أحمد عبد الفتاح البنا', 'ملك حسام الدين مصطفى الغنام', 'عمر خالد إسماعيل البنا', 'سلمى طارق عبد الحميد سالم', 'مريم عادل فتحي الدسوقي', 'أحمد سامي عبد المقصود حجازي', 'نورهان محمود عبد العزيز شلبي', 'كريم وائل السعيد أبو النجا', 'هاجر أشرف محمد عبد الغني', 'محمد إيهاب رمضان الجمل', 'روان هشام عبد الله الطنطاوي', 'زياد عمرو حسن البدراوي', 'آية مصطفى كامل النحاس', 'مصطفى ياسر عبد الهادي زهران', 'شهد تامر إبراهيم الشناوي', 'عبد الله رضا محمود العدوي', 'جنى أيمن فؤاد المرسي', 'إسلام حمدي عبد الباسط خليل', 'بسملة شريف عبد المنعم عوض', 'حازم مدحت السيد الصياد', 'ندى علاء الدين محمد البسيوني', 'فارس جمال عبد الناصر قنديل', 'رحمة ناصر أحمد الحلواني', 'خالد سعيد عبد الوهاب مطر'];
const PH = ['010 2345 6789', '011 3456 7890', '012 4567 8901', '015 5678 9012', '010 6789 0123', '011 7890 1234', '012 8901 2345', '010 9012 3456', '015 0123 4567', '011 1234 5678'];
const ST = ['review', 'unpaid', 'active', 'active', 'active', 'rejected', 'active', 'active', 'soon', 'active', 'active', 'none', 'active', 'review', 'active', 'ended', 'active', 'active', 'unpaid', 'active', 'active', 'active', 'soon', 'active', 'active', 'active'];
const PRICE = { 'دمياط الجديدة': 4500, 'الزرقا': 4500, 'شربين': 5000, 'فارسكور': 4200, 'كفر سعد': 4800, 'السرو': 4600, 'ميت أبو غالب': 4000 };
const DAYS = ['10 أكتوبر', '10 أكتوبر', '9 أكتوبر', '9 أكتوبر', '8 أكتوبر', '8 أكتوبر', '7 أكتوبر', '6 أكتوبر', '6 أكتوبر', '5 أكتوبر', '4 أكتوبر', '4 أكتوبر', '3 أكتوبر', '2 أكتوبر', '1 أكتوبر', '29 سبتمبر', '28 سبتمبر', '27 سبتمبر', '27 سبتمبر', '25 سبتمبر', '24 سبتمبر', '22 سبتمبر', '21 سبتمبر', '20 سبتمبر', '18 سبتمبر', '16 سبتمبر'];
export const STUDENTS = N.map((name, i) => {
  const line = LINES[(i * 3) % LINES.length]; const st = ST[i]; const both = i % 5 === 3;
  return { name, short: name.split(' ').slice(0, name.startsWith('عبد') || name.startsWith('منة') ? 3 : 2).join(' '), phone: PH[i % PH.length].replace(/\d$/, String(i % 10)), uni: UNIS[i % UNIS.length], line, stop: STOPS[line], go: GO[line], st,
    period: st === 'soon' ? 'الفصل الثاني 2026/2027' : st === 'ended' ? 'الفصل الثاني 2025/2026' : both ? 'الفصلان معاً 2026/2027' : 'الفصل الأول 2026/2027',
    price: both ? PRICE[line] * 2 - 1000 : PRICE[line], joined: DAYS[i], extra: i === 3 || i === 9 };
});
export const goTime = (s) => time(s.go, 'ص');
export { time, ltr, badge };
