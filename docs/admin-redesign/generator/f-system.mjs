import {
  board, NAV, navRow, btn, field, dataTable, status, state, badge, ico, ltr, cell2,
  C, T, FONT, STATUS,
} from './kit.mjs';

const H2 = 'margin:0;font-size:24px;line-height:32px;font-weight:600';
const H3 = 'margin:0;font-size:13px;line-height:20px;font-weight:600;color:#476273;letter-spacing:.04em;text-transform:uppercase';
const NOTE = `margin:0;font-size:14px;line-height:22px;color:${C.ink2}`;
const PANEL = `background:${C.ground};border-radius:20px;padding:24px`;
const sec = (title, lead, inner) => `<section style="display:flex;flex-direction:column;gap:20px">
<div style="display:flex;align-items:baseline;gap:24px"><h2 style="${H2};flex:none">${title}</h2><p style="${NOTE};max-width:860px">${lead}</p></div>
${inner}
</section>`;
const ar = (s) => `<bdi dir="rtl">${s}</bdi>`;

/* ── 1 · three widths ───────────────────────────────────────────── */
const blk = (st) => `<span style="display:block;border-radius:3px;${st}"></span>`;
const wfTable = `<div style="flex:1;background:#FFFFFF;border-radius:4px;display:flex;flex-direction:column;gap:5px;padding:6px">${blk(`height:6px;background:${C.ground}`)}${[1, 2, 3, 4, 5, 6].map(() => blk(`height:4px;background:${C.sunken}`)).join('')}</div>`;
const wfTop = (crumb, search) => `<div style="height:20px;background:#FFFFFF;border-bottom:1px solid ${C.hair};display:flex;align-items:center;gap:6px;padding:0 8px">${blk(`height:5px;width:${crumb}px;background:${C.disabled}`)}<span style="flex:1"></span>${blk(`height:10px;width:${search}px;background:${C.ground}`)}<span style="flex:1"></span>${blk(`height:10px;width:10px;border-radius:5px;background:${C.tint}`)}</div>`;
const wfHead = (w) => `<div style="display:flex;align-items:center">${blk(`height:9px;width:${w}px;background:${C.ink}`)}<span style="flex:1"></span>${blk(`height:12px;width:${Math.round(w * 0.72)}px;background:${C.teal}`)}</div>`;
const wfDesktop = `<div dir="rtl" style="width:340px;height:200px;border-radius:8px;background:${C.ground};box-shadow:0 0 0 1px ${C.disabled};display:flex;overflow:hidden">
<div style="width:64px;background:#FFFFFF;border-inline-end:1px solid ${C.hair};padding:8px 6px;display:flex;flex-direction:column;gap:4px">${blk(`height:10px;width:70%;background:${C.ink}`)}<span style="height:4px"></span>${blk(`height:9px;background:${C.tint}`)}${blk(`height:4px;width:50%;background:${C.hair};margin-top:4px`)}${[1, 2, 3].map(() => blk(`height:7px;background:${C.sunken}`)).join('')}${blk(`height:4px;width:60%;background:${C.hair};margin-top:4px`)}${[1, 2, 3].map(() => blk(`height:7px;background:${C.sunken}`)).join('')}${blk(`height:4px;width:40%;background:${C.hair};margin-top:4px`)}${[1, 2].map(() => blk(`height:7px;background:${C.sunken}`)).join('')}</div>
<div style="flex:1;display:flex;flex-direction:column">${wfTop(40, 90)}
<div style="flex:1;padding:10px;display:flex;flex-direction:column;gap:6px">${wfHead(60)}<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:6px">${[1, 2, 3, 4].map(() => blk('height:26px;background:#FFFFFF')).join('')}</div>${wfTable}</div></div></div>`;
const wfTablet = `<div dir="rtl" style="width:200px;height:200px;border-radius:8px;background:${C.ground};box-shadow:0 0 0 1px ${C.disabled};display:flex;overflow:hidden">
<div style="width:20px;background:#FFFFFF;border-inline-end:1px solid ${C.hair};padding:6px 4px;display:flex;flex-direction:column;gap:5px">${blk(`height:10px;background:${C.ink}`)}${blk(`height:10px;background:${C.tint}`)}${[1, 2, 3, 4, 5, 6].map(() => blk(`height:10px;background:${C.sunken}`)).join('')}</div>
<div style="flex:1;display:flex;flex-direction:column">${wfTop(30, 60)}
<div style="flex:1;padding:8px;display:flex;flex-direction:column;gap:6px">${wfHead(50)}<div style="display:grid;grid-template-columns:repeat(2,1fr);gap:6px">${[1, 2].map(() => blk('height:24px;background:#FFFFFF')).join('')}</div>${wfTable}</div></div></div>`;
const wfPhone = `<div dir="rtl" style="width:100px;height:200px;border-radius:8px;background:${C.ground};box-shadow:0 0 0 1px ${C.disabled};display:flex;flex-direction:column;overflow:hidden">
<div style="height:18px;background:#FFFFFF;border-bottom:1px solid ${C.hair};display:flex;align-items:center;gap:5px;padding:0 6px">${blk(`height:7px;width:8px;background:${C.ink2}`)}${blk(`height:6px;width:30px;background:${C.ink}`)}<span style="flex:1"></span>${blk(`height:7px;width:7px;border-radius:4px;background:${C.ink2}`)}</div>
<div style="flex:1;padding:6px;display:flex;flex-direction:column;gap:5px">${[1, 2, 3, 4].map(() => `<div style="background:#FFFFFF;border-radius:4px;padding:5px;display:flex;flex-direction:column;gap:3px">${blk(`height:4px;width:60%;background:${C.ink2}`)}${blk(`height:3px;background:${C.sunken}`)}${blk(`height:3px;width:70%;background:${C.sunken}`)}</div>`).join('')}</div>
<div style="height:24px;background:#FFFFFF;border-top:1px solid ${C.hair};padding:5px 6px">${blk(`height:14px;background:${C.teal}`)}</div></div>`;
const WIDTHS = [
  { name: 'Desktop', range: '1024 and wider · drawn at 1440', wf: wfDesktop, rows: [
    ['Navigation', `Side navigation, 264, start side. Every destination visible, grouped under plain headings. Nothing behind ${ar('«المزيد»')}.`],
    ['Top bar', '64 high: breadcrumb, student search (name or phone), company switcher for the super admin, the signed-in person, sign out.'],
    ['Grid', '12 columns, 24 gutter, 32 margins. Content never wider than 1200.'],
    ['Lists', 'A real table: toolbar, 56 rows, 25 per page.'],
    ['One record', 'Row click opens a side panel, 480, at the end side.'],
    ['Confirming', 'Centred dialog, 480.'],
    ['Primary action', 'End of the page header; for a form, end of the section footer.'],
    ['Controls', '44 high. 36 only inside table rows and toolbars.']] },
  { name: 'Tablet', range: '640 – 1023 · drawn at 834', wf: wfTablet, rows: [
    ['Navigation', 'Icon rail, 72. The menu button at its top expands it to the 264 list over the page; labels also show on hover and focus.'],
    ['Top bar', 'Same, search 280, the person shrinks to the avatar.'],
    ['Grid', '8 columns, 16 gutter, 24 margins. Supporting content drops under the main content.'],
    ['Lists', 'The same table without its hideTablet columns: the name, the status, the number that matters and the action stay.'],
    ['One record', 'The same side panel, over the page.'],
    ['Confirming', 'The same dialog.'],
    ['Primary action', 'As desktop.'],
    ['Controls', '44 high.']] },
  { name: 'Phone web', range: 'below 640 · drawn at 390', wf: wfPhone, rows: [
    ['Navigation', 'A menu button opens a full-height drawer with the same groups. No tab bar, no device frame — it is a page in a browser.'],
    ['Top bar', '56, sticky: menu button, page title, search button. A back arrow replaces the menu on a record\'s page.'],
    ['Grid', '4 columns, 16 gutter, 16 margins. One column of content.'],
    ['Lists', 'Each row becomes a record card with the same fields in the same order. No sideways scrolling.'],
    ['One record', 'A full page with a back arrow.'],
    ['Confirming', 'A full-width panel anchored to the bottom; buttons stacked, the confirming one first.'],
    ['Primary action', 'A plain full-width bar stuck to the bottom of the viewport.'],
    ['Controls', '48 high.']] },
];
const widths = `<div style="display:grid;grid-template-columns:1.25fr 1fr 1fr;gap:24px;align-items:stretch">
${WIDTHS.map((b) => `<div style="${PANEL};display:flex;flex-direction:column;gap:16px">
<div style="height:200px;display:flex;align-items:flex-end;justify-content:flex-start">${b.wf}</div>
<div><div style="font-size:18px;line-height:26px;font-weight:600">${b.name}</div><div style="font-size:13px;line-height:20px;color:${C.ink3}">${b.range}</div></div>
<div style="display:flex;flex-direction:column">${b.rows.map(([k, v]) => `<div style="display:grid;grid-template-columns:104px minmax(0,1fr);gap:12px;padding:8px 0;border-top:1px solid ${C.hair};font-size:13px;line-height:20px"><span style="font-weight:600">${k}</span><span style="color:${C.ink2}">${v}</span></div>`).join('')}</div>
</div>`).join('')}
</div>`;

/* ── 2 · grid ───────────────────────────────────────────────────── */
const dim = (label, w) => `<div dir="ltr" style="width:${w};text-align:center;font-size:12px;line-height:18px;color:${C.ink3};border-top:1px solid ${C.disabled};padding-top:4px;flex:none;white-space:nowrap">${label}</div>`;
const grid = `<div style="${PANEL};display:flex;flex-direction:column;gap:8px">
<div dir="rtl" style="height:150px;display:flex;border-radius:8px;overflow:hidden;box-shadow:0 0 0 1px ${C.disabled};background:${C.ground}">
<div dir="ltr" style="width:18.33%;background:#FFFFFF;border-inline-start:1px solid ${C.hair};display:flex;align-items:center;justify-content:center;font-size:13px;color:${C.ink2}">Side navigation</div>
<div style="flex:1;display:flex;flex-direction:column"><div style="height:30px;background:#FFFFFF;border-bottom:1px solid ${C.hair};display:flex;align-items:center;padding:0 16px;font-size:12px;color:${C.ink2}" dir="ltr">Top bar · 64</div>
<div style="flex:1;padding:0 2.72%;display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:2.16%">${Array.from({ length: 12 }, (_, i) => `<span style="background:${C.tint};font-size:12px;line-height:28px;text-align:center;color:${C.teal}">${i + 1}</span>`).join('')}</div></div>
</div>
<div dir="rtl" style="display:flex">${dim('264', '18.33%')}${dim('32', '2.22%')}${dim('1112 at 1440 · 12 columns of 70.7 with 24 between · max 1200, then centred', '77.23%')}${dim('32', '2.22%')}</div>
<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin-top:12px;font-size:13px;line-height:20px;color:${C.ink2}">
<div><b style="font-weight:600;color:${C.ink}">Common splits</b><br>12 · a table or a list<br>8 + 4 · content + supporting<br>7 + 5 · two equal-weight sections<br>3 × 4 · stat cards</div>
<div><b style="font-weight:600;color:${C.ink}">Forms</b><br>A form section is a 12-column card: 4 for its title and one helping sentence, 8 for the fields. Fields pair up 4 + 4.</div>
<div><b style="font-weight:600;color:${C.ink}">Vertical rhythm</b><br>24 between sections · 12 between a section heading and its card · 16 between fields · 4 / 8 inside a row.</div>
<div><b style="font-weight:600;color:${C.ink}">Breakpoints</b><br>640 and 1024 only. Logical CSS everywhere (start / end), never left / right.</div>
</div>
</div>`;

/* ── 3 · type and density ───────────────────────────────────────── */
const TYPE = [
  ['Page title', '28 / 36 · 600', T.page, 'الإيصالات', 'One per page. On a phone it sits in the top bar at 17 / 26.'],
  ['Section', '18 / 26 · 600', T.section, 'ركاب الغد في كل خط', 'Headings inside a page, panel and dialog titles.'],
  ['Card title', '16 / 24 · 600', T.card, 'بيانات الخط', 'Form sections, empty states.'],
  ['Body', '15 / 24', T.body, 'يؤكد الطلاب ركوبهم كل مساء.', 'Attention rows, sentences.'],
  ['Table · control', '14 / 22', T.small, 'منة الله إبراهيم عبد الرازق', 'Table cells, inputs, buttons (600), navigation.'],
  ['Label', '13 / 20 · 500', `${T.label};font-weight:500`, 'رقم الهاتف', 'Field labels, column headings, help text (400).'],
  ['Caption', '12 / 18', T.cap, 'منذ 3 ساعات', 'Second line of a cell, group headings. Nothing smaller.'],
  ['Number', '32 / 40 · 600', T.num, '512', 'Stat cards. 26 / 34 on a phone. Western digits always.'],
];
const typeTable = `<div style="${PANEL};display:flex;flex-direction:column">
<h3 style="${H3};margin-bottom:8px">Type · Readex Pro</h3>
${TYPE.map(([n, s, st, sample, use]) => `<div style="display:grid;grid-template-columns:104px 96px minmax(0,1fr) 210px;gap:16px;align-items:center;padding:10px 0;border-top:1px solid ${C.hair}"><span style="font-size:13px;font-weight:600">${n}</span><span style="font-size:13px;color:${C.ink3}">${s}</span><span dir="rtl" style="${st};text-align:right;white-space:nowrap;overflow:hidden">${sample}</span><span style="font-size:13px;line-height:20px;color:${C.ink2}">${use}</span></div>`).join('')}
</div>`;
const DENS = [
  ['Table row', '56', 'two-line cells fit; 52 when every cell is one line'],
  ['Table header · toolbar · pager', '44 · 60 · 56', ''],
  ['Control height', '44 · 48', 'desktop and tablet · phone'],
  ['Small control', '36', 'only inside table rows and toolbars, never on a phone'],
  ['Navigation item', '40 · 48', 'sidebar · phone drawer; rail icons 44'],
  ['Attention row', '68 · 72', 'desktop · phone'],
  ['Card padding', '20–24 · 16', 'desktop · phone'],
  ['Page margins', '32 · 24 · 16', 'desktop · tablet · phone'],
  ['Spacing steps', '4 8 12 16 24 32', 'nothing in between'],
  ['Radii', '10 · 14 · 16 · 20', 'controls · record cards, notes, toasts · cards and tables · dialogs'],
  ['Shadows', 'card · floating', 'cards and tables · panels, dialogs, drawer, toasts'],
];
const density = `<div style="${PANEL};display:flex;flex-direction:column">
<h3 style="${H3};margin-bottom:8px">Density</h3>
${DENS.map(([k, v, n]) => `<div style="display:grid;grid-template-columns:180px 110px minmax(0,1fr);gap:12px;padding:9px 0;border-top:1px solid ${C.hair};font-size:13px;line-height:20px"><span style="font-weight:600">${k}</span><span>${v}</span><span style="color:${C.ink2}">${n}</span></div>`).join('')}
</div>`;

/* ── 4 · colour ─────────────────────────────────────────────────── */
const SW = [
  ['ink', C.ink, 'text, active chips, toasts, return bar'], ['teal', C.teal, 'primary action, links, active nav'], ['teal pressed', C.tealPressed, 'pressed'], ['ground', C.ground, 'page, table header, hover row'],
  ['surface', C.surface, 'cards, bars, panels'], ['sunken', C.sunken, 'secondary buttons, skeleton'], ['hairline', C.hair, 'dividers, quiet borders'], ['ink 2', C.ink2, 'secondary text'],
  ['ink 3', C.ink3, 'captions, icons'], ['disabled', C.disabled, 'disabled text, input border'], ['teal tint', C.tint, 'active nav, selected row'], ['badge', C.badge, 'counts in the navigation'],
  ['success', C.ok, C.okBg], ['warning', C.warn, C.warnBg], ['danger', C.bad, C.badBg],
];
const colours = `<div style="${PANEL};display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:16px 16px">
${SW.map(([n, hex, use]) => `<div style="display:flex;flex-direction:column;gap:4px"><div style="height:44px;border-radius:10px;background:${hex};box-shadow:inset 0 0 0 1px ${C.hair};${use.startsWith('#') ? `display:flex;justify-content:flex-end;padding:8px` : ''}">${use.startsWith('#') ? `<span style="width:28px;height:28px;border-radius:8px;background:${use}"></span>` : ''}</div><div style="font-size:13px;line-height:20px;font-weight:600">${n} <span style="font-weight:400;color:${C.ink3}">${hex}${use.startsWith('#') ? ` / ${use}` : ''}</span></div><div style="font-size:12px;line-height:18px;color:${C.ink2}">${use.startsWith('#') ? 'text and icon / fill' : use}</div></div>`).join('')}
</div>`;

/* ── 5 · states ─────────────────────────────────────────────────── */
const st5 = (label, items) => `<div style="display:flex;flex-direction:column;gap:10px"><h3 style="${H3}">${label}</h3><div dir="rtl" style="display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end">${items.map(([cap, html]) => `<div style="display:flex;flex-direction:column;gap:6px;align-items:flex-start">${html}<span dir="ltr" style="font-size:12px;line-height:18px;color:${C.ink3}">${cap}</span></div>`).join('')}</div></div>`;
const SNAMES = ['Default', 'Hover', 'Pressed', 'Focus', 'Disabled', 'Loading'];
const bstates = (kind, label, icon) => [undefined, 'hover', 'pressed', 'focus', 'disabled', 'loading'].filter((s) => !(s === 'loading' && kind !== 'primary')).map((s, i) => [SNAMES[i], btn(label, { kind, state: s, icon })]);
const navIt = NAV.company[1].items[0];
const navBox = (inner) => `<div style="width:200px;background:#FFFFFF;border-radius:10px">${inner}</div>`;
const cap = (s) => `<span dir="ltr" style="font-size:12px;color:${C.ink3}">${s}</span>`;
const statesBlock = `<div style="${PANEL};display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:32px 48px">
${st5('Primary button', bstates('primary', 'حفظ'))}
${st5('Secondary button', bstates('secondary', 'إلغاء'))}
${st5('Outline button (on the page ground)', bstates('outline', 'إشعار', 'megaphone'))}
${st5('Danger button (only inside a confirmation)', bstates('danger', 'إيقاف'))}
${st5('Text field', [['Default', field({ label: 'اسم الخط', value: 'الزرقا', w: 128 })], ['Hover', field({ label: 'اسم الخط', value: 'الزرقا', state: 'hover', w: 128 })], ['Focus', field({ label: 'اسم الخط', value: 'الزرقا', state: 'focus', w: 128 })], ['Disabled', field({ label: 'اسم الخط', value: 'الزرقا', state: 'disabled', w: 128 })]])}
${st5('Navigation item', [['Default', navBox(navRow(navIt, false))], ['Hover', navBox(navRow(navIt, false, { hover: navIt.id }))], ['Focus', navBox(navRow(navIt, false, { focus: navIt.id }))], ['Current page', navBox(navRow(navIt, true)).replace('border-radius:10px"', 'border-radius:10px;padding-inline-start:12px"')]])}
<div style="grid-column:1 / -1;display:flex;flex-direction:column;gap:10px"><h3 style="${H3}">Table row · default, hover, keyboard focus, selected, open in the side panel</h3>
<div dir="rtl">${dataTable({ selectable: true, columns: [{ label: 'الطالب' }, { label: 'الخط', w: 180 }, { label: 'الاشتراك', w: 160 }, { label: 'الحالة', w: 170 }, { label: '', w: 260, align: 'end' }],
    rows: [
      { cells: [cell2('منة الله إبراهيم عبد الرازق', ltr('010 2345 6789')), 'الزرقا', 'الفصل الأول', status('active'), cap('default')] },
      { state: 'hover', cells: [cell2('عبد الرحمن محمد السيد الشربيني', ltr('011 3456 7890')), 'دمياط الجديدة', 'الفصلان معاً', status('review'), cap('hover · the whole row is the target')] },
      { state: 'focus', cells: [cell2('يوسف أحمد عبد الفتاح', ltr('012 4567 8901')), 'الزرقا', 'الفصل الأول', status('unpaid'), cap('focus · Enter opens it')] },
      { state: 'selected', cells: [cell2('ملك حسام الدين مصطفى', ltr('015 5678 9012')), 'شربين', 'الفصل الثاني', status('soon'), cap('selected for a bulk action')] },
      { state: 'open', cells: [cell2('عمر خالد إسماعيل البنا', ltr('010 6789 0123')), 'دمياط الجديدة', 'الفصل الأول', status('rejected'), cap('open in the side panel')] },
    ] })}</div></div>
<p style="${NOTE};grid-column:1 / -1">Focus is always visible: 2 px teal outside a 2 px surface gap on buttons, links, chips and navigation; inputs take a 2 px inner teal ring with a 3 px tint halo; table rows an inset 2 px outline. :focus-visible only. Hover is one tone step (teal → #005A7E, the only colour the web adds), pressed is the app's pressed teal. Tab order follows reading order, Escape closes the topmost panel or dialog and returns focus to what opened it, <span style="font-weight:600">/</span> focuses the student search.</p>
</div>`;

/* ── 6 · words ──────────────────────────────────────────────────── */
const WORDS = [
  ['اعتماد · قبول', 'قبول'],
  ['قيد مراجعة الإيصال · إيصال قيد المراجعة', 'قيد المراجعة'],
  ['مرفوض · منتهي', 'إيصال مرفوض · منتهٍ'],
  ['دفع مقدم · قادم (مدفوع مقدماً) · الفترة القادمة', 'يبدأ قريباً'],
  ['الحالي · ساري · السارية', 'نشط'],
  ['نشط (للخط والمشرف) · مفعّلة', 'يعمل'],
  ['معطّل · معطل · متوقف · موقوف · معطّلة', 'متوقف'],
  ['التصويت · تأكيد الرحلة · تأكيدات الركوب', 'تأكيد الركوب'],
  ['نازلين اليوم (مؤكدين) · مؤكدون لرحلة', 'ركاب اليوم · ركاب الغد'],
  ['فصلي (ترم) · فصل دراسي', 'الفصل الأول · الفصل الثاني'],
  ['yearly · annual · both', 'الفصلان معاً'],
  ['يومي (كاش) · سعر اليومي كاش', 'اليومي (نقداً في الباص)'],
  ['معروض للبيع', 'متاح للاشتراك'],
  ['خطوط السير · خط السير · محطات الصعود', 'الخطوط · الخط · المحطات'],
  ['الجامعة / نقطة الوصول · الوجهة', 'الجامعة'],
  ['إصدار رمز', 'أعطه رمزاً مؤقتاً'],
  ['بطاقة المحفظة · Apple / Google Wallet', 'بطاقة الطالب'],
  ['أولوية عالية', 'إشعار عاجل'],
  ['تصفير البيانات المالية', 'بدء حساب الإيرادات من جديد'],
  ['المسؤول · الإدارة · Super Admin', 'مدير الشركة · مدير المنصة'],
  ['المنظومة · النظام · قاعدة البيانات', 'باصك'],
  ['InstaPay · Vodafone Cash · IBAN · HEX', 'إنستاباي · فودافون كاش · رقم الآيبان · (اللون يُختار ولا يُكتب)'],
];
const half = Math.ceil(WORDS.length / 2);
const wordCol = (list) => `<div style="${PANEL};padding:8px 24px 12px">
<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:10px 0 8px;font-size:12px;line-height:18px;font-weight:600;color:${C.ink3};letter-spacing:.04em;text-transform:uppercase"><span>Today in the dashboard</span><span>One word everywhere</span></div>
${list.map(([o, n]) => `<div dir="rtl" style="display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:8px 0;border-top:1px solid ${C.hair};font-size:14px;line-height:22px"><span style="font-weight:600">${n}</span><span style="color:${C.ink3};text-decoration:line-through;text-decoration-color:${C.disabled}">${o}</span></div>`).join('')}
</div>`;
const words = `<div style="display:grid;grid-template-columns:1fr 1fr;gap:24px;align-items:start">${wordCol(WORDS.slice(0, half))}${wordCol(WORDS.slice(half))}</div>
<div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap"><span style="font-size:13px;font-weight:600">Subscription status — fixed, drawn only through status():</span><span dir="rtl" style="display:flex;gap:8px;flex-wrap:wrap">${Object.keys(STATUS).map((k) => status(k)).join('')}</span><span style="font-size:13px;font-weight:600;margin-inline-start:16px">Things that run or stop — state():</span><span dir="rtl" style="display:flex;gap:8px">${state('on')}${state('off')}</span></div>
<p style="${NOTE}">No English on screen. Western digits. Times 12-hour with ${ar('ص / م')} (${ar('7:30 ص')}). Dates ${ar('«10 أكتوبر 2026»')}, ranges with a dash. Money ${ar('«4,500 ج.م»')}. Phone numbers, codes and e-mails are left-to-right but aligned to the start edge. Formal, short sentences; a button names what it does (${ar('«إيقاف الخط»')}, never ${ar('«تأكيد»')}).</p>`;

/* ── 7 · navigation trees ───────────────────────────────────────── */
const WAS = {
  today: 'was «نظرة عامة»', receipts: 'was «فحص الإيصالات»', 'password-requests': 'new page · was a card on top of «الطلاب»', notifications: 'same',
  students: 'list, add, invitations, name fixes', supervisors: 'same', team: 'was «فريق الإدارة»', lines: 'was «الخطوط والمحطات»',
  'ride-confirmation': 'new page · was the 7th card of «إعدادات الشركة»', 'subscription-periods': 'was «إعدادات الشركة», cards 1–4 and the daily switch',
  'payment-methods': 'same', reports: 'was «التقارير المالية»', 'wallet-card': 'was «بطاقة المحفظة»', 'receipt-details': 'new page · was the 5th card of «إعدادات الشركة»',
  'p-today': 'was «نظرة عامة على المنصة»', 'p-corrections': 'new page · was a queue on top of «كل الطلاب»', 'p-password-requests': 'new page · was inside the overview',
  'p-companies': 'was «كل الشركات» · includes «شركة جديدة»', 'p-admins': 'same', 'p-students': 'read-only directory', 'p-notifications': 'same',
  'p-universities': 'was «الجامعات والوجهات»', 'p-defaults': 'what a new company starts with', 'p-app-versions': 'same',
};
const tree = (title, lead, groups, base) => `<div style="${PANEL};display:flex;flex-direction:column;gap:4px">
<div style="font-size:18px;line-height:26px;font-weight:600">${title}</div><div style="font-size:13px;line-height:20px;color:${C.ink2};margin-bottom:8px">${lead}</div>
${groups.map((g) => `${g.group ? `<div dir="rtl" style="font-size:12px;line-height:18px;font-weight:500;color:${C.ink3};padding:10px 0 2px">${g.group}</div>` : ''}${g.items.map((it) => `<div style="display:flex;align-items:center;gap:10px;min-height:40px;padding:4px 12px;background:#FFFFFF;border-radius:10px;margin-top:2px"><span dir="rtl" style="display:flex;align-items:center;gap:10px;width:226px;flex:none;font-size:14px;line-height:20px;font-weight:500"><span style="display:flex;color:${C.ink2}">${ico(it.icon, 18)}</span><span>${it.label}</span>${it.badge ? badge('عدد', 'danger') : ''}</span><span style="flex:1;min-width:0;font-size:12px;line-height:16px;color:${C.ink2}">${(WAS[it.id] ?? '').replace(/«[^»]+»/g, (m) => ar(m))}</span><span style="font-size:12px;color:${C.ink3};flex:none">${base}${it.slug}</span></div>`).join('')}`).join('')}
</div>`;
const trees = `<div style="display:grid;grid-template-columns:1fr 1fr;gap:24px;align-items:start">
${tree('Company admin · 14 destinations, 5 groups', 'Each job of the old settings page and of the old students page gets its own page. A red count shows on the two queues.', NAV.company, '/c/:id/')}
<div style="display:flex;flex-direction:column;gap:24px">
${tree('Super admin · the platform · 10 destinations, 4 groups', 'The two queues that were hidden inside other pages come first.', NAV.platform, '/platform/')}
<div style="${PANEL};display:flex;flex-direction:column;gap:8px"><div style="font-size:18px;line-height:26px;font-weight:600">Super admin · inside a company</div>
<p style="${NOTE}">The company admin's navigation exactly, plus an ink bar above the whole window: ${ar('«العودة إلى المنصة»')}, ${ar('«أنت الآن داخل شركة»')} and the company switcher, which keeps the current page when the company changes. On the platform the switcher sits in the top bar as ${ar('«ادخل إلى شركة»')}. Controls only the super admin sees inside company pages (set a student's password, delete an account, add a company admin) carry the tag ${ar('«لمدير المنصة فقط»')}.</p></div>
</div>
</div>`;

/* ── 8 · rules ──────────────────────────────────────────────────── */
const RULES = [
  ['One purpose per page', `A fact lives on one page. Today = what needs you and tomorrow's riders; money totals only in ${ar('«الإيرادات»')}; the review queue only in ${ar('«الإيصالات»')}.`],
  ['One primary action per page', 'Teal, last at the end side of the page header. A form\'s save sits in its section footer (desktop) or the bottom bar (phone). Everything else is secondary, outline or a link.'],
  ['Panel or dialog', 'Reading and editing one record → side panel (a page on a phone). A yes/no about one action → dialog. A dialog never holds more than one field; a panel never asks "are you sure".'],
  ['Nothing saved by a mis-click', 'No select or switch that saves on touch when money, status or students are affected. A dialog states exactly what will and will not happen; the button repeats the verb. No browser confirm or prompt, no typed English phrase.'],
  ['Errors beside the cause', `Under the field, in Arabic, when the field loses focus and again on save. Page failures use errorState with a retry. Toasts only confirm what just happened, with ${ar('«تراجع»')} where it is cheap.`],
  ['Draw the real counts', `25 rows a page with ${ar('«<span dir="ltr">1–25</span> من 442»')}, four-word names, 8+ stations, 5–6 trips each way. Every list shows its 0, 1 and many; every count says of what.`],
];
const rules = `<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px">${RULES.map(([t, d]) => `<div style="${PANEL};display:flex;flex-direction:column;gap:4px"><div style="font-size:16px;line-height:24px;font-weight:600">${t}</div><div style="font-size:13px;line-height:20px;color:${C.ink2}">${d}</div></div>`).join('')}</div>`;

board('AdmSystem', { row: 'A', w: 1440, lang: 'en', title: 'Admin web · Foundations', tab: 'Basak admin web · Foundations',
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:56px">
<header style="display:flex;align-items:flex-end;justify-content:space-between;gap:40px;padding-bottom:28px;border-bottom:1px solid ${C.hair}">
<div style="display:flex;flex-direction:column;gap:8px"><div style="font-size:13px;line-height:20px;font-weight:500;color:${C.teal};letter-spacing:.08em;text-transform:uppercase">Basak · Admin web · 2026</div><h1 style="margin:0;font-size:44px;line-height:54px;font-weight:600">A web dashboard, in the app's brand</h1></div>
<p style="margin:0;max-width:560px;font-size:15px;line-height:24px;color:${C.ink2}">A responsive website, not the app in a browser: a side navigation with everything in view, a top bar, real tables, side panels and dialogs. Colours, type family, radii and the two shadows are the mobile app's, unchanged. Arabic only, right to left: the start side is the right.</p>
</header>
${sec('Three widths', 'One product at three widths. What changes is listed row by row; anything not listed stays the same.', widths)}
${sec('Grid and content width', 'Drawn at 1440. The side navigation is fixed; the content column is fluid up to 1200 and then centred.', grid)}
${sec('Type and density', 'Denser than the app: body 14–15 instead of 16–17, rows 56 instead of 72. Never below 12.', `<div style="display:grid;grid-template-columns:minmax(0,1.25fr) minmax(0,1fr);gap:24px;align-items:start">${typeTable}${density}</div>`)}
${sec('Colour', 'The mobile tokens exactly. Colour means something: teal = act, amber = waiting on you, red = broken or destructive, green = done.', colours)}
${sec('States', 'Every interactive part has all of these. Drawn here once; the kit draws them with the state option.', statesBlock)}
${sec('Plain words', 'One name per thing, the same in the navigation, the page title, the buttons and the messages.', words)}
${sec('Navigation', 'The single source for grouping, labels, icons and routes: NAV in build2/kit.mjs. Page titles equal their navigation label.', trees)}
${sec('Rules every page follows', '', rules)}
</div>` });
