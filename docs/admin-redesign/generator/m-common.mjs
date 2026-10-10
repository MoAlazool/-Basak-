/** Local helpers of the `money` batch (candidates for the kit — see the report). */
import { board, shellDesktop, ico, btn, badge, ltr, C, T, R, CARD, FONT, SHADOW } from './kit.mjs';

export const ELL = 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
export const LINES = ['دمياط الجديدة', 'الزرقا', 'شربين', 'فارسكور', 'كفر سعد', 'السرو', 'ميت أبو غالب', 'كفر البطيخ'];
export const col = (inner, gap = 12, extra = '') => `<div style="display:flex;flex-direction:column;gap:${gap}px;min-width:0;${extra}">${inner}</div>`;
export const row = (inner, gap = 8, extra = '') => `<div style="display:flex;align-items:center;gap:${gap}px;${extra}">${inner}</div>`;
export const grid = (cols, inner, gap = 24, extra = '') => `<div style="display:grid;grid-template-columns:${cols};gap:${gap}px;align-items:start;${extra}">${inner}</div>`;
export const muted = (s, extra = '') => `<span style="color:${C.ink3};${extra}">${s}</span>`;
export const p = (s, extra = '') => `<p style="margin:0;${T.small};color:${C.ink2};${extra}">${s}</p>`;

/** A plain card with a title row: card({ title, help, end, body, pad, phone }). */
export const card = ({ title, help, end = '', body = '', pad, phone, extra = '' } = {}) => `<section style="${CARD};padding:${pad ?? (phone ? 16 : 24)}px;display:flex;flex-direction:column;gap:${phone ? 14 : 16}px;min-width:0;${extra}">
${title ? `<div style="display:flex;align-items:flex-start;gap:12px"><div style="flex:1;min-width:0"><h2 style="margin:0;${T.card}">${title}</h2>${help ? `<p style="margin:2px 0 0;${T.label};color:${C.ink2}">${help}</p>` : ''}</div>${end}</div>` : ''}
${body}
</section>`;

/** A dropdown filter button: selectBtn('الخط', 'كل الخطوط'). */
export const selectBtn = (label, value, o = {}) => `<button type="button" aria-haspopup="listbox" style="display:inline-flex;align-items:center;gap:6px;height:${o.phone ? 44 : 36}px;padding:0 12px;border-radius:${R.control}px;font-size:13px;line-height:20px;background:${o.on ? C.tint : C.surface};color:${C.ink};box-shadow:inset 0 0 0 1px ${o.on ? C.teal : C.hair};white-space:nowrap;flex:none">${label ? `<span style="color:${C.ink3}">${label}</span>` : ''}<span style="font-weight:${o.on ? 600 : 500}">${value}</span>${ico('down', 14, 2)}</button>`;

/** The switch drawn alone (the kit keeps its own private). */
export const sw = (on, o = {}) => `<span role="switch" aria-checked="${!!on}" aria-label="${o.label ?? ''}" style="width:44px;height:24px;border-radius:12px;background:${o.locked ? C.sunken : on ? C.teal : C.disabled};display:inline-flex;align-items:center;padding:2px;justify-content:${on ? 'flex-end' : 'flex-start'};flex:none;${o.changed ? `box-shadow:0 0 0 2px ${C.surface}, 0 0 0 4px ${C.warn};` : ''}"><span style="width:20px;height:20px;border-radius:10px;background:#FFFFFF;box-shadow:0 1px 2px rgba(23,56,74,.25)"></span></span>`;

/** A bare control box (for compound fields the kit's field() cannot draw). */
export const box = (inner, o = {}) => `<span style="height:${o.phone ? 48 : 44}px;${o.w ? `width:${o.w}px;flex:none;` : 'flex:1;min-width:0;'}border-radius:${R.control}px;background:${o.disabled ? C.ground : C.surface};box-shadow:inset 0 0 0 ${o.error ? `2px ${C.bad}` : o.changed ? `2px ${C.warn}` : `1px ${o.disabled ? C.hair : C.disabled}`};display:flex;align-items:center;gap:6px;padding:0 12px;${T.small};color:${o.disabled ? C.ink3 : C.ink}">${inner}</span>`;

/** The English caption + framed mock used on state boards. */
export const frame = (label, text, inner, o = {}) => `<section style="display:flex;flex-direction:column;gap:12px;min-width:0">
<div dir="ltr" style="display:flex;align-items:baseline;gap:12px"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600;white-space:nowrap">${label}</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2}">${text}</p></div>
<div dir="rtl" style="border-radius:${R.inner}px;overflow:hidden;box-shadow:0 0 0 1px ${C.hair}, ${SHADOW.floating};${o.w ? `width:${o.w}px;` : ''}${o.extra ?? ''}">${inner.replace('data-root ', '')}</div>
</section>`;
export const FW = 1312;
/** A states board: white sheet, 64 padding, frames stacked. frames: [[label, text, html]]. */
export const statesBoard = (file, { row: r, title, frames }) => board(file, { row: r, w: 1440, lang: 'en', title, tab: title,
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">
${frames.map(([l, t, h, o]) => frame(l, t, h, o)).join('\n')}
</div>` });
/** A desktop shell at frame width and a fixed height. */
export const mini = (h, o) => shellDesktop({ size: `width:${FW}px;height:${h}px`, ...o });

/** Horizontal bars: barList([[label, value, sub]], { unit }) — the widest value is 100%. */
export const barList = (rows, o = {}) => {
  const max = Math.max(...rows.map((x) => x[1]), 1);
  return `<div style="display:flex;flex-direction:column;gap:${o.gap ?? 12}px">${rows.map(([k, v, s]) => `<a href="#" style="display:flex;flex-direction:column;gap:4px;color:${C.ink}"><span style="display:flex;align-items:baseline;gap:8px;${T.small}"><span style="flex:1;min-width:0;${ELL}">${k}${s ? ` <span style="${T.cap};color:${C.ink3}">${s}</span>` : ''}</span><span style="font-weight:600;white-space:nowrap;color:${v ? C.ink : C.disabled}">${v.toLocaleString('en-US')} <span style="font-size:12px;font-weight:400;color:${C.ink3}">ج.م</span></span></span><span aria-hidden="true" style="height:6px;border-radius:3px;background:${C.sunken};overflow:hidden;display:flex"><span style="display:block;height:6px;border-radius:3px;background:${C.teal};width:${Math.max(v ? 1 : 0, Math.round((v / max) * 100))}%"></span></span></a>`).join('')}</div>`;
};

/** A notification as a phone shows it on its lock screen. */
export const phoneNotif = ({ title, body, when = 'الآن', urgent, w = 300, ghost } = {}) => `<div role="img" aria-label="معاينة الإشعار على الهاتف" style="width:${w}px;max-width:100%;border-radius:24px;background:linear-gradient(180deg,#2A4F63,${C.ink});padding:14px 12px 16px;display:flex;flex-direction:column;gap:10px;flex:none">
<span aria-hidden="true" style="align-self:center;width:56px;height:5px;border-radius:3px;background:rgba(255,255,255,.22)"></span>
<div style="align-self:center;color:#FFFFFF;font-size:30px;line-height:36px;font-weight:300" dir="ltr">9:41</div>
<div style="background:rgba(255,255,255,.96);border-radius:16px;padding:10px 12px;display:flex;flex-direction:column;gap:2px;color:${C.ink}">
<div style="display:flex;align-items:center;gap:6px;font-size:11px;line-height:16px;color:${C.ink3}"><span style="width:18px;height:18px;border-radius:5px;background:${C.ink};color:#FFFFFF;display:flex;align-items:center;justify-content:center">${ico('bus', 11, 2)}</span><span style="font-weight:600;color:${C.ink2}">باصك</span>${urgent ? `<span style="color:${C.bad};font-weight:600">· عاجل</span>` : ''}<span style="flex:1"></span><span>${when}</span></div>
<div style="font-size:13px;line-height:20px;font-weight:600;color:${ghost && !title ? C.disabled : C.ink};overflow-wrap:anywhere">${title || 'عنوان الإشعار'}</div>
<div style="font-size:12px;line-height:19px;color:${ghost && !body ? C.disabled : C.ink2};overflow-wrap:anywhere">${body || 'نص الإشعار يظهر هنا كما يقرؤه الطالب.'}</div>
</div>
<div style="text-align:center;font-size:11px;line-height:16px;color:rgba(255,255,255,.62)">شكل تقريبي، ويختلف من هاتف لآخر</div>
</div>`;

/** A counter under a text field: counter(21, 80). */
export const counter = (n, max) => `<span dir="ltr" style="${T.cap};color:${n > max ? C.bad : C.ink3}">${n} / ${max}</span>`;
/** Label row with something at its end (a counter). */
export const labelled = (label, end, control, o = {}) => `<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><div style="display:flex;align-items:baseline;gap:8px;${T.label};font-weight:500"><span style="flex:1">${label}${o.optional ? ` <span style="font-weight:400;color:${C.ink3}">اختياري</span>` : ''}</span>${end ?? ''}</div>${control}${o.error ? `<div role="alert" style="display:flex;align-items:flex-start;gap:6px;${T.label};color:${C.bad}"><span style="display:flex;padding-top:2px">${ico('alert', 14, 2)}</span><span>${o.error}</span></div>` : o.help ? `<div style="${T.label};color:${C.ink2}">${o.help}</div>` : ''}</div>`;
export const inputBox = (value, o = {}) => `<div style="${o.rows ? `min-height:${o.rows * 24 + 20}px;padding:10px 12px;` : `min-height:${o.phone ? 48 : 44}px;display:flex;align-items:center;padding:8px 12px;`}border-radius:${R.control}px;background:${C.surface};box-shadow:inset 0 0 0 ${o.error ? `2px ${C.bad}` : o.focus ? `2px ${C.teal}, 0 0 0 3px ${C.tint}` : `1px ${C.disabled}`};${T.small};color:${value ? C.ink : C.ink3}">${value || o.placeholder || ''}</div>`;

/** A check / cross list: ticks([['text', true]]). */
export const ticks = (items) => `<ul style="margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:6px">${items.map(([t, ok]) => `<li style="display:flex;align-items:flex-start;gap:8px;${T.small};color:${C.ink}"><span style="display:flex;padding-top:3px;color:${ok ? C.ok : C.bad}">${ico(ok ? 'check' : 'x', 16, 2.25)}</span><span style="flex:1;min-width:0">${t}</span></li>`).join('')}</ul>`;

/** Small ⋮ menu drawn open: menu([['pencil','تعديل'], ['trash','حذف','danger']]). */
export const menu = (items, o = {}) => `<div role="menu" style="width:${o.w ?? 220}px;background:${C.surface};border-radius:${R.inner}px;box-shadow:${SHADOW.floating}, 0 0 0 1px ${C.hair};padding:6px;display:flex;flex-direction:column">${items.map(([i, t, tone]) => `<button type="button" role="menuitem" style="display:flex;align-items:center;gap:10px;height:40px;padding:0 10px;border-radius:8px;${T.small};color:${tone === 'danger' ? C.bad : C.ink};text-align:start">${ico(i, 16)}<span>${t}</span></button>`).join('')}</div>`;
export const dots = (label = 'إجراءات أخرى') => `<button type="button" aria-label="${label}" aria-haspopup="menu" style="width:36px;height:36px;border-radius:${R.control}px;color:${C.ink2};display:inline-flex;align-items:center;justify-content:center;flex:none">${ico('dots', 18)}</button>`;
export const rowActions = (...parts) => `<div style="display:flex;align-items:center;justify-content:flex-end;gap:4px">${parts.join('')}</div>`;
export { btn, badge, ltr };
