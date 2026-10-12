import React, { useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import { Badge, Button, Card, Icon, IconButton, Note, Switch, TextField } from '../../ui';
import {
  BUS_CAPACITY_MAX, bothPriceNote, countOf, dailyPrice, isSold, joinAnd, newKey, pricesText, stationsText, stepSubs, tripsRangeText, unitWord, W,
  type Issue, type LineDraft, type SaleContext, type StepNo,
} from '../../lib/lines';
import { parseBusCapacity } from '../../lib/lineCapacity';
import { SALE_OPTIONS, optionName, type SaleOption } from '../../lib/saleOptions';
import { clockLabel } from '../../lib/time';

export const STEPS: { label: string; next: string }[] = [
  { label: 'الاسم والجامعات', next: 'التالي: المحطات' }, { label: 'المحطات', next: 'التالي: الرحلات' },
  { label: 'الرحلات', next: 'التالي: الأسعار' }, { label: 'الأسعار', next: 'التالي: المراجعة' }, { label: 'المراجعة والحفظ', next: '' },
];

type Patch = (fn: (d: LineDraft) => LineDraft) => void;
export interface Uni { id: string; name: string; is_active: boolean }

// ── The step list (desktop) ─────────────────────────────────────────────────
export const StepsNav: React.FC<{ step: StepNo; d: LineDraft; reached: number; edit: boolean; go: (s: StepNo) => void }> = ({ step, d, reached, edit, go }) => {
  const subs = stepSubs(d);
  return (
    <Card as="section" className="p-5">
      <h2 className="sr-only">الخطوات</h2>
      <ol className="m-0 flex list-none flex-col p-0">
        {STEPS.map((s, i) => {
          const n = (i + 1) as StepNo;
          const state = n === step ? 'current' : edit || n < reached || (n <= reached && n !== step) ? 'done' : 'todo';
          const can = edit || n <= reached;
          const sub = state === 'done' && n < 5 ? subs[n as 1 | 2 | 3 | 4] : '';
          return (
            <li key={n} aria-current={state === 'current' ? 'step' : undefined} className="flex gap-3">
              <div className="flex flex-col items-center">
                <span aria-hidden="true" className={`flex h-7 w-7 flex-none items-center justify-center rounded-full text-label font-semibold ${state === 'done' ? 'bg-ok text-white' : state === 'current' ? 'bg-teal text-white' : 'bg-surface text-ink-3 shadow-[inset_0_0_0_1.5px_#9DB0BB]'}`}>
                  {state === 'done' ? <Icon name="check" size={16} stroke={2.5} /> : n}
                </span>
                {i < STEPS.length - 1 && <span className={`my-1 min-h-4 w-0.5 flex-1 ${state === 'done' ? 'bg-ok' : 'bg-hair'}`} />}
              </div>
              <button type="button" disabled={!can || state === 'current'} onClick={() => go(n)}
                className={`min-w-0 flex-1 text-start ${i < STEPS.length - 1 ? 'pb-4' : ''} ${can && state !== 'current' ? 'hover:text-teal' : ''}`}>
                <span className={`block text-small leading-7 ${state === 'current' ? 'font-semibold text-ink' : state === 'todo' ? 'text-ink-2' : 'font-semibold text-ink'}`}>{s.label}</span>
                {sub && <span className="block text-label text-ink-2">{sub}</span>}
              </button>
            </li>
          );
        })}
      </ol>
    </Card>
  );
};

/** Tablet: the five steps in a row, only the current one named. */
export const StepsRow: React.FC<{ step: StepNo; reached: number; edit: boolean; go: (s: StepNo) => void }> = ({ step, reached, edit, go }) => (
  <ol className="m-0 flex list-none items-center gap-2 p-0" aria-label="الخطوات">
    {STEPS.map((s, i) => {
      const n = (i + 1) as StepNo;
      const state = n === step ? 'current' : edit || n < reached ? 'done' : 'todo';
      return (
        <React.Fragment key={n}>
          <li aria-current={state === 'current' ? 'step' : undefined} className="flex flex-none items-center gap-2">
            <button type="button" disabled={state === 'current' || !(edit || n <= reached)} onClick={() => go(n)} aria-label={s.label}
              className={`flex h-7 w-7 items-center justify-center rounded-full text-label font-semibold ${state === 'done' ? 'bg-ok text-white' : state === 'current' ? 'bg-teal text-white' : 'bg-surface text-ink-3 shadow-[inset_0_0_0_1.5px_#9DB0BB]'}`}>
              {state === 'done' ? <Icon name="check" size={16} stroke={2.5} /> : n}
            </button>
            {state === 'current' && <span className="whitespace-nowrap text-small font-semibold">{s.label}</span>}
          </li>
          {i < STEPS.length - 1 && <li aria-hidden="true" className={`h-0.5 min-w-4 flex-1 rounded-sm ${state === 'done' ? 'bg-ok' : 'bg-hair'}`} />}
        </React.Fragment>
      );
    })}
  </ol>
);

// ── «ملخص الخط» ──────────────────────────────────────────────────────────────
export const Summary: React.FC<{ d: LineDraft; uniName: (id: string) => string; badge: React.ReactNode }> = ({ d, uniName, badge }) => {
  const seats = parseBusCapacity(d.capacity);
  const rows: [string, string, string][] = [
    ['الاسم', d.name.trim() || d.stations[0]?.name.trim() || '', 'لم يُكتب بعد'],
    ['الجامعات', d.university_ids.map(uniName).join(' · '), 'لم تُختر بعد'],
    ['مقاعد الباص', seats.ok && seats.value ? `${seats.value} ${unitWord(seats.value, W.seat)}` : '', 'لم تُحدد'],
    ['المحطات', stationsText(d), 'لم تُضف بعد'],
    ['رحلات الذهاب', tripsRangeText(d, 'departure'), 'لم تُضف بعد'],
    ['العودة من الجامعة', tripsRangeText(d, 'return'), 'لم تُضف بعد'],
    ['الأسعار', pricesText(d), 'لم تُكتب بعد'],
  ];
  return (
    <Card as="section" className="px-5 pb-2 pt-5">
      <div className="flex items-center gap-2 pb-3"><h2 className="m-0 flex-1 text-card">ملخص الخط</h2>{badge}</div>
      <dl className="m-0">
        {rows.map(([k, v, empty]) => (
          <div key={k} className="border-t border-hair py-3">
            <dt className="text-cap text-ink-2">{k}</dt>
            <dd className={`m-0 text-small ${v ? 'font-semibold text-ink' : 'text-ink-2'}`}>{v || empty}</dd>
          </div>
        ))}
      </dl>
    </Card>
  );
};

// ── Step 1 ──────────────────────────────────────────────────────────────────
export const Step1: React.FC<{ d: LineDraft; patch: Patch; universities: Uni[]; issues: Issue[]; show: boolean }> = ({ d, patch, universities, issues, show }) => {
  const list = universities.filter((u) => u.is_active || d.university_ids.includes(u.id));
  const n = d.university_ids.length;
  const seats = parseBusCapacity(d.capacity);
  const nameIssue = issues.find((i) => i.message.startsWith('اسم الخط') || i.message.includes('بلا أسهم'));
  const uniIssue = show ? issues.find((i) => i.message.startsWith('اختر جامعة')) : undefined;
  const toggle = (id: string) => patch((c) => {
    const ids = c.university_ids.includes(id) ? c.university_ids.filter((x) => x !== id) : [...c.university_ids, id];
    // A trip can only go to a university the line serves.
    return { ...c, university_ids: ids, trips: c.trips.map((t) => (t.university_id && !ids.includes(t.university_id) ? { ...t, university_id: '' } : t)) };
  });
  return (
    <div className="flex flex-col gap-6">
      <TextField label="اسم الخط" value={d.name} maxLength={60} placeholder={d.stations[0]?.name.trim() || 'مثال: الزرقا'}
        onChange={(e) => { const v = e.target.value; patch((c) => ({ ...c, name: v })); }}
        error={nameIssue?.message} help="اسم المنطقة يكفي، حتى 40 حرفاً. لا تكتب فيه اسم الجامعة. إن تركته فارغاً أخذ اسم أول محطة." />
      <fieldset className="m-0 flex flex-col gap-2 border-0 p-0">
        <legend className="mb-2 text-label font-medium text-ink">الجامعات التي يوصل إليها الخط</legend>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {list.map((u) => {
            const on = d.university_ids.includes(u.id);
            return (
              <label key={u.id} className={`flex min-h-12 cursor-pointer items-center gap-3 rounded-control px-3.5 sm:min-h-11 ${on ? 'bg-teal-tint shadow-[inset_0_0_0_2px_#00658D]' : 'bg-surface shadow-field hover:shadow-field-hover'}`}>
                <input type="checkbox" className="peer sr-only" checked={on} onChange={() => toggle(u.id)} />
                <span aria-hidden="true" className={`flex h-5 w-5 flex-none items-center justify-center rounded-md peer-focus-visible:shadow-focus ${on ? 'bg-teal text-white' : 'bg-surface shadow-[inset_0_0_0_1.5px_#58707F]'}`}>{on && <Icon name="check" size={14} stroke={3} />}</span>
                <span className={`min-w-0 flex-1 truncate text-small ${on ? 'font-semibold text-teal' : 'text-ink'}`}>{u.name}</span>
              </label>
            );
          })}
        </div>
        {uniIssue ? <div role="alert" className="flex items-start gap-1.5 text-label text-bad"><Icon name="alert" size={14} stroke={2} className="mt-[3px]" /><span>{uniIssue.message}</span></div>
          : <p className="m-0 text-label text-ink-2">{n === 0 ? 'اختر الجامعات التي يوصل إليها الخط. طلاب الجامعات الأخرى لا يرونه.' : `${n === 1 ? 'اختيرت جامعة واحدة' : n === 2 ? 'اختيرت جامعتان' : `اختيرت ${n} ${unitWord(n, W.university)}`}. طلاب الجامعات الأخرى لا يرون هذا الخط.`}</p>}
        <p className="m-0 text-label text-ink-2">لا تجد جامعتك في القائمة؟ الجامعات تضيفها إدارة المنصة: اطلبها منها.</p>
      </fieldset>
      <TextField label="مقاعد الباص" optional value={d.capacity} inputMode="numeric" ltr suffix="مقعداً" className="sm:max-w-[240px]"
        onChange={(e) => { const v = e.target.value.replace(/[^\d٠-٩]/g, '').slice(0, 3); patch((c) => ({ ...c, capacity: v })); }}
        error={!seats.ok ? seats.message : undefined}
        help={`عدد من 1 إلى ${BUS_CAPACITY_MAX}. به نخبرك أنت والمشرف حين يؤكد الركوب أكثر مما يسع الباص.`} />
    </div>
  );
};

// ── Step 2 ──────────────────────────────────────────────────────────────────
export const Step2: React.FC<{
  d: LineDraft; patch: Patch; uniName: (id: string) => string; onRemove: (key: string) => void;
  counts: Record<string, number> | null; issues: Issue[]; show: boolean;
}> = ({ d, patch, uniName, onRemove, counts, issues, show }) => {
  const focus = useRef<string | null>(null);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!focus.current) return;
    box.current?.querySelector<HTMLInputElement>(`[data-station="${focus.current}"]`)?.focus();
    focus.current = null;
  });
  const add = (after?: number) => {
    const key = newKey();
    focus.current = key;
    patch((c) => { const list = [...c.stations]; list.splice(after == null ? list.length : after + 1, 0, { key, name: '' }); return { ...c, stations: list }; });
  };
  const move = (i: number, delta: number) => patch((c) => {
    const list = [...c.stations]; const j = i + delta;
    if (j < 0 || j >= list.length) return c;
    [list[i], list[j]] = [list[j], list[i]];
    return { ...c, stations: list };
  });
  const unis = d.university_ids.map(uniName);
  return (
    <div ref={box} className="flex flex-col gap-4">
      {counts && (
        <div className="hidden items-center gap-2 text-label text-ink-2 sm:flex">
          <span className="w-[52px]" /><span className="w-[214px] flex-none">المحطة</span><span className="w-[88px]">مشتركون منها</span>
        </div>
      )}
      <ol className="m-0 flex list-none flex-col gap-2 p-0">
        {d.stations.map((s, i) => {
          const empty = show && !s.name.trim();
          const c = counts && s.id ? counts[s.id] ?? 0 : null;
          return (
            <li key={s.key} className="flex flex-col gap-1">
              <div className="flex items-center gap-2">
                <Icon name="grip" size={16} className="hidden flex-none text-disabled sm:block" />
                <span aria-hidden="true" className="flex h-6 w-6 flex-none items-center justify-center rounded-full bg-sunken text-cap font-medium text-ink-2 tabular">{i + 1}</span>
                <div className={`flex h-12 min-w-0 flex-1 items-center rounded-control bg-surface px-3 sm:h-11 sm:max-w-[214px] ${empty ? 'shadow-field-error' : 'shadow-field hover:shadow-field-hover focus-within:!shadow-field-focus'}`}>
                  <input data-station={s.key} value={s.name} aria-label={`اسم المحطة ${i + 1}`} placeholder={`اسم المحطة ${i + 1}`} aria-invalid={empty || undefined}
                    onChange={(e) => { const v = e.target.value; patch((cur) => ({ ...cur, stations: cur.stations.map((x) => (x.key === s.key ? { ...x, name: v } : x)) })); }}
                    onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); if (i === d.stations.length - 1) add(); else box.current?.querySelector<HTMLInputElement>(`[data-station="${d.stations[i + 1].key}"]`)?.focus(); } }}
                    className="h-full min-w-0 flex-1 bg-transparent text-small outline-none placeholder:text-ink-3" />
                </div>
                {counts && <span className="hidden w-[88px] flex-none text-label text-ink-2 sm:block">{c == null ? 'جديدة' : c ? `${c} ${unitWord(c, W.student)}` : 'لا أحد'}</span>}
                <span className="hidden flex-1 sm:block" />
                <IconButton icon="aup" label={`انقل «${s.name || `المحطة ${i + 1}`}» لأعلى`} sm disabled={i === 0} onClick={() => move(i, -1)} />
                <IconButton icon="adown" label={`انقل «${s.name || `المحطة ${i + 1}`}» لأسفل`} sm disabled={i === d.stations.length - 1} onClick={() => move(i, 1)} />
                <IconButton icon="trash" label={`احذف «${s.name || `المحطة ${i + 1}`}»`} sm onClick={() => onRemove(s.key)} />
              </div>
              {empty && <span role="alert" className="ms-[64px] text-label text-bad">اكتب اسم المحطة أو احذفها.</span>}
            </li>
          );
        })}
      </ol>
      {show && issues.some((x) => x.message === 'أضف محطة واحدة على الأقل.') && <Note tone="danger" title="أضف محطة واحدة على الأقل." />}
      <div className="flex"><Button kind="outline" icon="plus" onClick={() => add()} className="max-sm:w-full">أضف محطة</Button></div>
      <div className="flex items-center gap-2.5 rounded-control bg-teal-tint px-4 py-3 text-small font-semibold text-teal">
        <Icon name="school" size={18} />
        <span>{unis.length ? `ثم الجامعة: ${unis.join(' · ')}` : 'ثم الجامعة: اخترها في الخطوة الأولى'}</span>
      </div>
      <p className="m-0 text-label text-ink-2">الترتيب هو ترتيب مرور الباص في الذهاب: الأولى أبعد محطة عن الجامعة. في العودة يتحرك الباص من الجامعة ويعيد كل طالب إلى محطته، فلا تحتاج ترتيباً آخر.</p>
    </div>
  );
};

// ── Step 4 ──────────────────────────────────────────────────────────────────
const PriceRow: React.FC<{
  label: string; on: boolean; sold: boolean; onToggle?: (on: boolean) => void;
  value: number | ''; onValue: (v: number | '') => void; sub: React.ReactNode; error?: string;
}> = ({ label, on, sold, onToggle, value, onValue, sub, error }) => (
  <div className="flex flex-col gap-3 border-t border-hair py-4 first:border-t-0 first:pt-0 sm:flex-row sm:items-center sm:gap-6">
    <div className="flex min-w-0 flex-1 items-center gap-4">
      <Switch checked={sold && on} disabled={!sold} onChange={(v) => onToggle?.(v)} label={`بيع ${label} على هذا الخط`} />
      <div className="min-w-0 flex-1">
        <div className={`text-small font-semibold ${sold ? 'text-ink' : 'text-ink-2'}`}>{label}</div>
        <div className="text-label text-ink-2">{sub}</div>
      </div>
    </div>
    <TextField aria-label={`سعر ${label}`} value={value === '' ? '' : Number(value).toLocaleString('en-US')} inputMode="numeric" ltr suffix="ج.م"
      onChange={(e) => { const v = e.target.value.replace(/[٠-٩]/g, (x) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(x))).replace(/[^\d]/g, '').replace(/^0+(?=\d)/, '').slice(0, 6); onValue(v === '' ? '' : Number(v)); }}
      disabled={!sold || !on} placeholder={sold && on ? 'اكتب السعر' : ''} error={error} className="sm:w-[200px] sm:flex-none" />
  </div>
);

export const Step4: React.FC<{ d: LineDraft; patch: Patch; ctx: SaleContext; companyId: string; show: boolean }> = ({ d, patch, ctx, companyId, show }) => {
  const setP = (o: SaleOption, p: Partial<LineDraft['prices'][SaleOption]>) => patch((c) => ({ ...c, prices: { ...c.prices, [o]: { ...c.prices[o], ...p } } }));
  const periods = <Link to={`/c/${companyId}/subscription-periods`} className="font-semibold text-teal hover:underline">مواعيد الاشتراك</Link>;
  const platformOff = 'أوقفته إدارة باصك عند كل الشركات الآن';
  const note = bothPriceNote(d);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col">
        {SALE_OPTIONS.map((o) => {
          const sold = isSold(ctx, o); const p = d.prices[o];
          const missing = show && sold && p.enabled && (p.price === '' || Number(p.price) <= 0);
          return (
            <PriceRow key={o} label={optionName[o]} on={p.enabled} sold={sold} onToggle={(v) => setP(o, { enabled: v })}
              value={p.price} onValue={(v) => setP(o, { price: v })} error={missing ? 'اكتب السعر أو أوقف بيعه.' : undefined}
              sub={!sold ? platformOff : p.enabled ? 'يُباع على هذا الخط' : 'لا يُباع على هذا الخط'} />
          );
        })}
        <PriceRow label="اليومي (نقداً في الباص)" on={d.daily_enabled} sold={ctx.daily} onToggle={(v) => patch((c) => ({ ...c, daily_enabled: v }))}
          value={d.price_daily} onValue={(v) => patch((c) => ({ ...c, price_daily: v }))}
          error={show && ctx.daily && d.daily_enabled && dailyPrice(d) <= 0 ? 'اكتب السعر أو أوقف بيعه.' : undefined}
          sub={!ctx.daily ? platformOff : d.daily_enabled ? 'يدفعه الطالب للمشرف عند الركوب' : 'لا يُباع على هذا الخط'} />
      </div>
      {note && <Note tone="warning" title={note} />}
      <Note tone="teal" icon="info" title="ما يُباع على هذا الخط تقرره هنا">
        يرى الطالب الاشتراك المفتوح هنا حين يأتي موعد بيعه. تواريخ الفصول، وما يبدأ به كل خط جديد، في {periods}.
      </Note>
      <p className="m-0 text-label text-ink-2">لا نكتب عنك أي سعر. الاشتراك الذي تتركه مفتوحاً بلا سعر يمنع الحفظ حتى تكتبه أو توقفه.</p>
    </div>
  );
};

// ── Step 5 ──────────────────────────────────────────────────────────────────
/** «5 رحلات ذهاب من 6:15 ص إلى 8:15 ص», «5 مواعيد عودة من 1:00 م إلى 5:30 م». */
function rangeOf(d: LineDraft, dir: 'departure' | 'return'): string {
  const list = d.trips.filter((t) => t.direction === dir && t.start_time).sort((a, b) => a.start_time.localeCompare(b.start_time));
  const word = dir === 'departure' ? 'ذهاب' : 'عودة';
  if (!list.length) return '';
  if (list.length === 1) return `${dir === 'departure' ? 'رحلة' : 'موعد'} ${word} واحد${dir === 'departure' ? 'ة' : ''}: ${clockLabel(list[0].start_time)}`;
  return `${countOf(list.length, dir === 'departure' ? W.trip : W.time)} ${word} من ${clockLabel(list[0].start_time)} إلى ${clockLabel(list[list.length - 1].start_time)}`;
}
export const Step5: React.FC<{
  d: LineDraft; issues: Issue[]; uniName: (id: string) => string; go: (s: StepNo) => void; edit: boolean; supervised: boolean;
  saveError: React.ReactNode; after: React.ReactNode[];
}> = ({ d, issues, uniName, go, saveError, after }) => {
  const seats = parseBusCapacity(d.capacity);
  const unis = d.university_ids.map(uniName);
  const rows: { step: StepNo; title: string; text: string }[] = [
    { step: 1, title: 'الاسم والجامعات', text: [d.name.trim() || d.stations[0]?.name.trim(), joinAnd(unis), seats.ok && seats.value ? `الباص ${seats.value} ${unitWord(seats.value, W.seat)}` : null].filter(Boolean).join(' · ') },
    { step: 2, title: 'المحطات', text: stationsText(d) },
    { step: 3, title: 'الرحلات', text: [rangeOf(d, 'departure'), rangeOf(d, 'return')].filter(Boolean).join(' · ') || 'لا رحلات بعد' },
    { step: 4, title: 'الأسعار', text: pricesText(d, true) || 'لم يُكتب سعر' },
  ];
  const left = issues.length;
  return (
    <div className="flex flex-col gap-4">
      {saveError}
      {!saveError && left > 0 && (
        <Note tone="warning" title={left === 1 ? 'بقي أمر واحد قبل الحفظ' : left === 2 ? 'بقي أمران قبل الحفظ' : `بقيت ${left} ${left <= 10 ? 'أمور' : 'أمراً'} قبل الحفظ`}>
          {left === 1 ? 'أكمله ثم احفظ.' : 'أكملها ثم احفظ.'} كل ما كتبته باقٍ كما هو.
        </Note>
      )}
      <ul className="m-0 flex list-none flex-col p-0">
        {rows.map((r) => {
          const mine = issues.filter((i) => i.step === r.step);
          return (
            <li key={r.step} className="flex items-center gap-3 border-b border-hair py-3.5">
              <span aria-hidden="true" className={`flex h-8 w-8 flex-none items-center justify-center rounded-full ${mine.length ? 'bg-bad-bg text-bad' : 'bg-ok-bg text-ok'}`}><Icon name={mine.length ? 'alert' : 'check'} size={16} stroke={2.25} /></span>
              <div className="min-w-0 flex-1">
                <div className="text-small font-semibold">{r.title}</div>
                {mine.length ? mine.map((m, k) => <div key={k} className="text-label text-bad">{m.message}</div>) : <div className="text-label text-ink-2">{r.text}</div>}
              </div>
              {mine.length ? <Button kind="tonal" sm onClick={() => go(r.step)}>أكمل</Button> : <Button kind="link" sm onClick={() => go(r.step)}>عدّل</Button>}
            </li>
          );
        })}
      </ul>
      {after.length > 0 && (
        <div className="rounded-inner bg-ground px-4 py-3">
          <h3 className="m-0 mb-1 text-small font-semibold">بعد الحفظ</h3>
          <ul className="m-0 flex list-disc flex-col gap-1 ps-5 text-label text-ink-2">{after.map((a, i) => <li key={i}>{a}</li>)}</ul>
        </div>
      )}
    </div>
  );
};

export const UnsavedBadge: React.FC<{ edit: boolean; dirty: boolean }> = ({ edit, dirty }) => (edit
  ? (dirty ? <Badge tone="warning">تعديلات لم تُحفظ</Badge> : null)
  : <Badge tone="warning">لم يُحفظ بعد</Badge>);
