import React, { useEffect, useMemo, useState } from 'react';
import { Select } from '../ui/Select';
import { Link, useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import { refreshIfNotUpdated, STALE, unwrap, usePageData } from '../lib/query';
import { settingsKey, switchesKey } from '../lib/reference';
import { rememberApplied } from '../lib/recentChanges';
import { rpcOr } from '../lib/rpc';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';
import { cairoToday } from '../lib/time';
import type { SaleOption, SaleRow } from '../lib/saleOptions';
import {
  MONTHS, academicYearOf, cellView, changesWord, linesWord, optionView, problemCount, problemSentence, termDayText,
  termProblems, termRange, unsavedTitle, type EdgeProblem, type LinePreview, type OptionView, type Term, type TermCode,
} from '../lib/money';
import {
  Badge, Button, DataTable, Dialog, EmptyState, ErrorState, Icon, Money, Note, Page, PageHeader, PhoneBar, SectionHead,
  SkeletonBar, Switch, errorText, useOnline, type Column, type Tone,
} from '../ui';
import { LeaveDialog, useLeaveGuard } from '../components/money/LeaveGuard';

// ── What the database answers ───────────────────────────────────────
interface Period { period_code: string; academic_year: number; label: string; start_date: string; end_date: string }
interface Settings {
  company_id: string | null;
  annual_company: boolean | null; annual_effective: boolean; annual_global: boolean;
  advance_enabled: boolean | null;
  terms: Term[] | null;
  periods: Period[] | null;
  sale_preview: LinePreview[] | null;
}
interface Switches { daily_global: boolean; daily_company: boolean | null; daily_effective: boolean }
interface Impact { moved: Partial<Record<string, number>>; moved_total: number; open: Partial<Record<string, number>> }
interface Saved {
  moved_subscriptions?: number; advance_enabled?: boolean | null; on_sale?: Record<string, boolean> | null;
  annual_company?: boolean | null; annual_effective?: boolean; daily_company?: boolean | null; daily_effective?: boolean;
}

/** What the admin changed and has not saved: only fields that differ from what is saved. */
interface Edits {
  terms: Partial<Record<TermCode, Partial<Pick<Term, 'name' | 'start_day' | 'start_month' | 'end_day' | 'end_month'>>>>;
  sale: Partial<Record<TermCode, boolean>>;
  annual?: boolean; daily?: boolean; advance?: boolean;
}
const NO_EDITS: Edits = { terms: {}, sale: {} };
const TERM_FIELDS = ['name', 'start_day', 'start_month', 'end_day', 'end_month'] as const;

/** The lists a change to the company's own row makes out of date (lib/sync.ts, `companies`). */
const COMPANY_ROW_LISTS = ['company', 'overview', 'settings', 'switches', 'vote'];

const OPTION_NAME: Record<SaleOption, string> = { first: 'الفصل الأول', second: 'الفصل الثاني', both: 'الفصلان معاً', summer: 'الفصل الصيفي' };

// ── Small parts ─────────────────────────────────────────────────────
const CHANGED = '!shadow-[inset_0_0_0_2px_#8A5300]';
const FIELD = 'h-12 sm:h-11 rounded-control bg-surface text-small outline-none';
const ring = (error?: boolean, changed?: boolean) => (error ? '!shadow-field-error' : changed ? CHANGED : 'shadow-field hover:shadow-field-hover focus-within:!shadow-field-focus focus:!shadow-field-focus');

/** Day number + month: one edge of a term. The year it falls in is written under it. */
const EdgeField: React.FC<{
  label: string; day: number; month: number; onDay: (d: number) => void; onMonth: (m: number) => void;
  under: React.ReactNode; error?: string; changed?: boolean; disabled?: boolean; showLabel?: string;
}> = ({ label, day, month, onDay, onMonth, under, error, changed, disabled, showLabel }) => (
  <div className="flex min-w-0 flex-col gap-1.5" role="group" aria-label={label}>
    {showLabel && <span aria-hidden="true" className="text-label font-medium text-ink">{showLabel}</span>}
    <div className="flex gap-2">
      <input aria-label={`${label}: اليوم`} inputMode="numeric" maxLength={2} disabled={disabled} value={day ? String(day) : ''}
        aria-invalid={error ? true : undefined}
        onChange={(e) => { const d = e.target.value.replace(/[٠-٩]/g, (x) => String(x.charCodeAt(0) - 0x0660)).replace(/\D/g, ''); onDay(d ? Number(d) : 0); }}
        className={`${FIELD} w-[52px] flex-none text-center tabular ${ring(!!error, changed)} disabled:bg-ground disabled:text-disabled`} />
      <div className="min-w-0 flex-1">
        <Select value={String(month)} disabled={disabled} onChange={(v) => onMonth(Number(v))} ariaLabel={`${label}: الشهر`}
          options={MONTHS.map((m, i) => ({ value: String(i + 1), label: m }))}
          className={`flex w-full items-center gap-2 px-3 text-start ${FIELD} ${ring(!!error, changed)} disabled:cursor-default disabled:!bg-ground disabled:text-disabled`} />
      </div>
    </div>
    <div className={`min-h-[18px] text-cap ${error ? 'font-medium text-bad' : changed ? 'font-medium text-warn' : 'text-ink-3'}`} role={error ? 'alert' : undefined}>
      {error ?? under}
    </div>
  </div>
);

/** The name students read, edited in place. */
const NameField: React.FC<{ value: string; onChange: (v: string) => void; changed?: boolean; disabled?: boolean; phone?: boolean }> = ({ value, onChange, changed, disabled, phone }) => (
  phone ? (
    <label className="flex min-w-0 flex-col">
      <input value={value} maxLength={40} disabled={disabled} onChange={(e) => onChange(e.target.value)} aria-label="الاسم كما يراه الطالب"
        className={`-mx-1 rounded-md bg-transparent px-1 text-body font-semibold text-ink outline-none focus:shadow-field-focus ${changed ? 'text-warn' : ''}`} />
      <span className={`text-label ${changed ? 'font-medium text-warn' : 'text-ink-2'}`}>{changed ? 'اسم جديد · لم يُحفظ' : 'اضغط الاسم لتغييره'}</span>
    </label>
  ) : (
    <label className="flex min-w-0 flex-col gap-1.5">
      <span className={`flex items-center gap-2 px-3 ${FIELD} ${ring(false, changed)} ${disabled ? '!bg-ground' : ''}`}>
        <input value={value} maxLength={40} disabled={disabled} onChange={(e) => onChange(e.target.value)} aria-label="الاسم كما يراه الطالب"
          className="h-full min-w-0 flex-1 bg-transparent font-semibold text-ink outline-none disabled:text-disabled" />
        <Icon name="pencil" size={16} className="text-ink-3" />
      </span>
      <span className={`text-cap ${changed ? 'font-medium text-warn' : 'text-ink-3'}`}>{changed ? 'اسم جديد · لم يُحفظ' : 'الاسم كما يراه الطالب'}</span>
    </label>
  )
);

/** A new line's default for one option, with the word under it («مفتوح», «مقفول», «لم يُحفظ», «أوقفته المنصة»). */
const SaleSwitch: React.FC<{ on: boolean; onChange: (on: boolean) => void; changed?: boolean; locked?: boolean; disabled?: boolean; label: string; card?: boolean }> = ({ on, onChange, changed, locked, disabled, label, card }) => (
  <div className={`flex flex-col gap-1 ${card ? 'items-end' : 'items-start'}`}>
    <span className={`rounded-full ${changed ? 'shadow-[0_0_0_2px_#fff,0_0_0_4px_#8A5300]' : ''}`}>
      <Switch checked={on && !locked} onChange={onChange} disabled={disabled || locked} label={label} />
    </span>
    <span className={`text-cap ${changed ? 'font-medium text-warn' : 'text-ink-3'}`}>{locked ? 'أوقفته المنصة' : changed ? 'لم يُحفظ' : card ? 'في الخط الجديد' : on ? 'مفتوح' : 'مقفول'}</span>
  </div>
);

/** «ما يراه الطلاب الآن» (from the lines), or what saving a new default changes. */
const StatusCell: React.FC<{ view: OptionView; change?: 'stop' | 'open'; inline?: boolean }> = ({ view, change, inline }) => (
  <div className={`flex min-w-0 items-start gap-1 ${inline ? 'flex-row flex-wrap items-center gap-x-2' : 'flex-col'}`}>
    {change
      ? <Badge tone="warning">{change === 'stop' ? 'الخطوط الجديدة تبدأ به مقفولاً' : 'الخطوط الجديدة تبدأ به مفتوحاً'}</Badge>
      : <Badge tone={view.tone as Tone}>{view.label}</Badge>}
    <span className="text-label text-ink-2">{change ? `الخطوط الحالية كما هي · ${view.label}${view.lines ? ` في ${linesWord(view.lines)}` : ''}` : view.sub}</span>
  </div>
);

// ── The page ────────────────────────────────────────────────────────
/**
 * «مواعيد الاشتراك»: the company's terms, what a new line starts with, paying ahead and the daily
 * cash option — saved together. What each line sells is switched on its own page.
 */
export const SubscriptionPeriodsPage: React.FC = () => {
  const company = useCompany();
  const companyId = company.id;
  const online = useOnline();
  const navigate = useNavigate();
  const client = useQueryClient();
  const guard = useGuard();

  const page = usePageData(settingsKey(companyId), () =>
    unwrap<Settings>(supabase.rpc('get_subscription_settings', { p_company_id: companyId })), { staleTime: STALE.reference });
  const switchesPage = usePageData(switchesKey(companyId), () =>
    unwrap<Switches>(supabase.rpc('get_subscription_switches', { p_company_id: companyId })), { staleTime: STALE.reference });
  const settings = page.data;
  const sw = switchesPage.data;

  const [edits, setEdits] = useState<Edits>(NO_EDITS);
  const [confirm, setConfirm] = useState<{ impact: Impact | null } | null>(null);
  const [saving, setSaving] = useState(false);
  const [preparing, setPreparing] = useState(false);
  const [allLines, setAllLines] = useState(false);

  const today = cairoToday();
  const year = academicYearOf(settings?.periods, today);
  const saved = useMemo(() => [...(settings?.terms ?? [])].sort((a, b) => a.sort_order - b.sort_order), [settings?.terms]);
  const terms: Term[] = useMemo(() => saved.map((t) => ({ ...t, ...edits.terms[t.code], is_on_sale: edits.sale[t.code] ?? t.is_on_sale })), [saved, edits]);
  const preview = settings?.sale_preview ?? [];

  const annualSaved = !!settings?.annual_company;
  const dailySaved = !!sw?.daily_company;
  const advanceSaved = !!settings?.advance_enabled;
  const annual = edits.annual ?? annualSaved;
  const daily = edits.daily ?? dailySaved;
  const advance = edits.advance ?? advanceSaved;

  // Edits that equal what is saved are dropped, so the count and the amber marks are exact.
  const setTerm = (code: TermCode, patch: Partial<Term>) => setEdits((e) => {
    const base = saved.find((t) => t.code === code)!;
    const next = { ...e.terms[code], ...patch } as Record<string, unknown>;
    TERM_FIELDS.forEach((k) => { if (next[k] === base[k]) delete next[k]; });
    return { ...e, terms: { ...e.terms, [code]: Object.keys(next).length ? next : undefined } };
  });
  const setSale = (code: TermCode, on: boolean) => setEdits((e) => {
    const base = saved.find((t) => t.code === code)!;
    const sale = { ...e.sale };
    if (on === base.is_on_sale) delete sale[code]; else sale[code] = on;
    return { ...e, sale };
  });
  const setFlag = (k: 'annual' | 'daily' | 'advance', on: boolean, base: boolean) => setEdits((e) => ({ ...e, [k]: on === base ? undefined : on }));

  const termChanged = (code: TermCode, k: (typeof TERM_FIELDS)[number]) => edits.terms[code]?.[k] !== undefined;
  const edgeChanged = (code: TermCode, edge: 'start' | 'end') => termChanged(code, `${edge}_day`) || termChanged(code, `${edge}_month`);

  const changes = useMemo(() => {
    const list: { key: string; kind: 'date' | 'name' | 'stop' | 'open' | 'advance' | 'daily' }[] = [];
    saved.forEach((t) => {
      if (edgeChanged(t.code, 'start')) list.push({ key: `${t.code}.start`, kind: 'date' });
      if (edgeChanged(t.code, 'end')) list.push({ key: `${t.code}.end`, kind: 'date' });
      if (termChanged(t.code, 'name')) list.push({ key: `${t.code}.name`, kind: 'name' });
      if (edits.sale[t.code] !== undefined) list.push({ key: `${t.code}.sale`, kind: edits.sale[t.code] ? 'open' : 'stop' });
    });
    if (edits.annual !== undefined) list.push({ key: 'both.sale', kind: edits.annual ? 'open' : 'stop' });
    if (edits.daily !== undefined) list.push({ key: 'daily', kind: 'daily' });
    if (edits.advance !== undefined) list.push({ key: 'advance', kind: 'advance' });
    return list;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [saved, edits]);
  const dirty = changes.length > 0;
  const problems = useMemo(() => termProblems(terms, year), [terms, year]);
  const nProblems = problemCount(problems);
  const nameProblem = terms.some((t) => !t.name.trim());

  const leave = useLeaveGuard(dirty);
  const leaveWhat = useMemo(() => {
    const kinds = new Set(changes.map((c) => c.kind));
    const parts = [kinds.has('date') && 'غيّرت موعداً', kinds.has('name') && 'غيّرت اسماً', (kinds.has('stop') || kinds.has('open')) && 'غيّرت ما يبدأ به الخط الجديد',
      kinds.has('advance') && 'غيّرت الدفع المسبق', kinds.has('daily') && 'غيّرت الاشتراك اليومي'].filter(Boolean) as string[];
    return parts.length > 1 ? `${parts.slice(0, -1).join('، ')} و${parts[parts.length - 1].replace(/^غيّرت /, '')}` : parts[0] ?? 'غيّرت شيئاً';
  }, [changes]);

  // After a company change while editing: start clean.
  useEffect(() => { setEdits(NO_EDITS); }, [companyId]);

  const views: Record<SaleOption, OptionView> = useMemo(() => ({
    first: optionView('first', preview), second: optionView('second', preview), summer: optionView('summer', preview),
    both: optionView('both', preview, { platformOff: settings ? !settings.annual_global : false }),
  }), [preview, settings]);
  const dailyView: OptionView = !sw?.daily_global
    ? { tone: 'neutral', label: 'لا يظهر للطلاب', sub: 'أوقفته إدارة المنصة عند كل الشركات', lines: 0, total: preview.length }
    : preview.length === 0 ? { tone: 'neutral', label: 'لا يظهر للطلاب', sub: 'لا توجد خطوط بعد', lines: 0, total: 0 }
    : sw.daily_effective ? { tone: 'success', label: 'يُباع الآن', sub: 'في الخطوط التي فتحته وكتبت سعره', lines: 0, total: preview.length }
      : { tone: 'neutral', label: 'لا يظهر للطلاب', sub: 'لا يبيعه أي خط', lines: 0, total: preview.length };

  const blocked = !online || saving || nProblems > 0 || nameProblem;

  // ── Save ──
  const termsPayload = () => saved.map((t) => {
    const e = edits.terms[t.code];
    if (!e) return null;
    const merged = terms.find((x) => x.code === t.code)!;
    return { code: t.code, name: merged.name.trim(), start_month: merged.start_month, start_day: merged.start_day, end_month: merged.end_month, end_day: merged.end_day };
  }).filter(Boolean) as Record<string, unknown>[];
  const datesPayload = () => termsPayload().filter((t) => edgeChanged(t.code as TermCode, 'start') || edgeChanged(t.code as TermCode, 'end'));

  const askSave = () => guard('prepare', async () => {
    if (blocked || !dirty) return;
    setPreparing(true);
    try {
      // The real numbers first: how many open subscriptions move, and how many hold each option.
      const impact = await rpcOr<Impact | null>('company_terms_impact',
        () => supabase.rpc('company_terms_impact', { p_company_id: companyId, p_terms: datesPayload() }), async () => null);
      setConfirm({ impact });
    } catch (err) {
      notifyError('هذه المواعيد لا تُحفظ', errorText(err));
    } finally {
      setPreparing(false);
    }
  });

  const save = () => guard('save', async () => {
    setSaving(true);
    const sale = Object.keys(edits.sale).length ? edits.sale as Record<string, boolean> : null;
    const tp = termsPayload();
    try {
      const out = await rpcOr<Saved>('save_company_subscription_settings',
        () => supabase.rpc('save_company_subscription_settings', {
          p_company_id: companyId, p_terms: tp.length ? tp : null, p_on_sale: sale, p_advance: edits.advance ?? null,
          p_annual: edits.annual ?? null, p_daily: edits.daily ?? null,
        }),
        // A database without the all-in-one function: the same steps one by one (each with its own checks).
        async () => {
          let moved = 0;
          if (tp.length) moved = Number((await unwrap<{ moved_subscriptions?: number }>(supabase.rpc('save_company_terms', { p_company_id: companyId, p_terms: tp })))?.moved_subscriptions ?? 0);
          if (sale || edits.advance !== undefined) await unwrap(supabase.rpc('set_company_sale_settings', { p_company_id: companyId, p_advance: edits.advance ?? null, p_on_sale: sale }));
          if (edits.annual !== undefined) await unwrap(supabase.rpc('set_annual_subscription', { p_enabled: edits.annual, p_company_id: companyId }));
          if (edits.daily !== undefined) await unwrap(supabase.rpc('set_daily_subscription', { p_enabled: edits.daily, p_company_id: companyId }));
          return { moved_subscriptions: moved };
        });
      // What was saved goes on screen at once; what follows from it (the preview per line) is read once.
      client.setQueryData<Settings>(settingsKey(companyId), (cur) => (cur ? {
        ...cur, terms: terms.map((t) => ({ ...t, name: t.name.trim() })),
        advance_enabled: out?.advance_enabled ?? advance, annual_company: out?.annual_company ?? annual,
      } : cur));
      client.setQueryData<Switches>(switchesKey(companyId), (cur) => (cur ? { ...cur, daily_company: out?.daily_company ?? daily, daily_effective: out?.daily_effective ?? (daily && cur.daily_global) } : cur));
      rememberApplied([companyId], COMPANY_ROW_LISTS.filter((n) => n !== 'settings'));
      void client.invalidateQueries({ queryKey: settingsKey(companyId) });
      refreshIfNotUpdated(switchesKey(companyId));
      setEdits(NO_EDITS);
      setConfirm(null);
      const moved = Number(out?.moved_subscriptions ?? 0);
      notifyDone('حُفظت مواعيد الاشتراك', moved > 0 ? `انتقل ${moved.toLocaleString('en-US')} اشتراكاً مفتوحاً إلى المواعيد الجديدة.` : 'يرى الطلاب الآن ما حفظته.');
    } catch (err) {
      setConfirm(null);
      notifyError('لم تُحفظ التغييرات', `بقيت تغييراتك في الصفحة. ${errorText(err)}`);
      void page.reload();
    } finally {
      setSaving(false);
    }
  });

  const header = (
    <PageHeader title="مواعيد الاشتراك" phoneActions={false}
      meta={settings && <Badge tone="teal" className="hidden !text-label sm:inline-flex">العام الدراسي {year}/{year + 1}</Badge>}
      sub="متى يبدأ كل فصل وينتهي، وما يبدأ به كل خط جديد. ما يُباع فعلاً وسعره تختاره في كل خط."
      actions={settings && (
        <>
          <Button kind="outline" icon="undo" disabled={!dirty || saving} onClick={() => setEdits(NO_EDITS)}>تراجع عن التغييرات</Button>
          <Button icon="check" disabled={!dirty || blocked} loading={preparing || saving} onClick={() => void askSave()}>حفظ التغييرات</Button>
        </>
      )} />
  );

  if (page.error && !settings) {
    return (
      <Page>{header}
        <ErrorState card title="تعذّر تحميل مواعيد الاشتراك" text="لم نستطع جلب المواعيد. تأكد من اتصالك ثم حاول مرة أخرى." onRetry={() => { void page.reload(); void switchesPage.reload(); }} />
      </Page>
    );
  }
  if (!settings) return <Page>{header}<DatesSkeleton /></Page>;

  // ── One row of the terms table / one phone card ──
  const termParts = (t: Term): TermParts => {
    const p: EdgeProblem = problems[t.code] ?? {};
    const r = termRange(t, year);
    const base = saved.find((x) => x.code === t.code)!;
    const was = (edge: 'start' | 'end') => `كان ${termDayText(year, base[`${edge}_month`], base[`${edge}_day`], false)} · لم يُحفظ`;
    const under = (edge: 'start' | 'end') => (edgeChanged(t.code, edge) ? was(edge) : r[edge].slice(0, 4));
    const saleChange = edits.sale[t.code] === undefined ? undefined : edits.sale[t.code] ? 'open' as const : 'stop' as const;
    return {
      name: (phone?: boolean) => <NameField phone={phone} value={t.name} onChange={(v) => setTerm(t.code, { name: v })} changed={termChanged(t.code, 'name')} disabled={!online} />,
      start: (showLabel?: boolean) => <EdgeField label={`بداية ${t.name}`} showLabel={showLabel ? 'يبدأ' : undefined} day={t.start_day} month={t.start_month} disabled={!online}
        onDay={(d) => setTerm(t.code, { start_day: d })} onMonth={(m) => setTerm(t.code, { start_month: m })}
        under={under('start')} error={p.start} changed={edgeChanged(t.code, 'start')} />,
      end: (showLabel?: boolean) => <EdgeField label={`نهاية ${t.name}`} showLabel={showLabel ? 'ينتهي' : undefined} day={t.end_day} month={t.end_month} disabled={!online}
        onDay={(d) => setTerm(t.code, { end_day: d })} onMonth={(m) => setTerm(t.code, { end_month: m })}
        under={under('end')} error={p.end} changed={edgeChanged(t.code, 'end')} />,
      sale: (card?: boolean) => <SaleSwitch card={card} label={`${t.name} مفتوح في الخط الجديد`} on={t.is_on_sale} onChange={(on) => setSale(t.code, on)} changed={saleChange !== undefined} disabled={!online} />,
      status: (inline?: boolean) => <StatusCell inline={inline} view={views[t.code]} change={saleChange} />,
    };
  };
  const bothChange = edits.annual === undefined ? undefined : edits.annual ? 'open' as const : 'stop' as const;
  const dailyChange = edits.daily === undefined ? undefined : edits.daily ? 'open' as const : 'stop' as const;
  const bothSwitch = (card?: boolean) => <SaleSwitch card={card} label="الفصلان معاً مفتوح في الخط الجديد" on={annual} onChange={(on) => setFlag('annual', on, annualSaved)} changed={bothChange !== undefined} locked={!settings.annual_global} disabled={!online} />;
  const dailySwitch = (card?: boolean) => <SaleSwitch card={card} label="اليومي (نقداً) مفتوح في الخط الجديد" on={daily} onChange={(on) => setFlag('daily', on, dailySaved)} changed={dailyChange !== undefined} locked={sw ? !sw.daily_global : false} disabled={!online || !sw} />;
  const advanceSwitch = (
    <span className={`rounded-full ${edits.advance !== undefined ? 'shadow-[0_0_0_2px_#fff,0_0_0_4px_#8A5300]' : ''}`}>
      <Switch label="الدفع المسبق للفصل القادم" checked={advance} onChange={(on) => setFlag('advance', on, advanceSaved)} disabled={!online} />
    </span>
  );
  const ADVANCE_TITLE = 'الدفع المسبق للفصل القادم';
  const ADVANCE_TEXT = 'يدفع الطالب الفصل القادم قبل أن يبدأ، بسعره في الخط. عند إيقافه يُباع الفصل الجاري فقط.';

  const summer = terms.find((t) => t.code === 'summer');

  return (
    <Page>
      {header}
      {nProblems > 0 ? (
        <Note tone="danger" title={nProblems === 1 ? 'موعد يحتاج تصحيحاً قبل الحفظ' : nProblems === 2 ? 'موعدان يحتاجان تصحيحاً قبل الحفظ' : `${nProblems} مواعيد تحتاج تصحيحاً قبل الحفظ`}>
          {problemSentence(problems, terms)}
        </Note>
      ) : nameProblem ? (
        <Note tone="danger" title="اسم فصل فارغ">اكتب الاسم الذي يراه الطالب لكل فصل قبل الحفظ.</Note>
      ) : dirty ? (
        <Note tone="warning" icon="pencil" title={unsavedTitle(changes.length)}>الطلاب ما زالوا يرون ما كان محفوظاً. لا شيء يتغيّر عندهم حتى تضغط «حفظ التغييرات».</Note>
      ) : null}

      {/* Phone: the year above the cards (the header's meta is in the top bar's place). */}
      <div className="-mt-1 sm:hidden"><Badge tone="teal">العام الدراسي {year}/{year + 1}</Badge></div>

      {/* Wide screens: one table */}
      <section aria-label="الفصول وما يبدأ به الخط الجديد" className="hidden overflow-hidden rounded-card bg-surface shadow-card xl:block">
        <table className="w-full table-fixed border-collapse">
          <thead>
            <tr className="h-11 bg-ground text-start text-label font-medium text-ink-2">
              <th scope="col" className="w-[25%] px-4 text-start font-medium">الاشتراك</th>
              <th scope="col" className="w-[19%] px-3 text-start font-medium">يبدأ</th>
              <th scope="col" className="w-[19%] px-3 text-start font-medium">ينتهي</th>
              <th scope="col" className="w-[10%] px-3 text-start font-medium">في الخط الجديد</th>
              <th scope="col" className="px-4 text-start font-medium">ما يراه الطلاب الآن</th>
            </tr>
          </thead>
          <tbody>
            {terms.filter((t) => t.code !== 'summer').map((t) => { const p = termParts(t); return (
              <tr key={t.code} className="border-t border-hair align-top">
                <td className="px-4 py-4">{p.name()}</td><td className="px-3 py-4">{p.start()}</td><td className="px-3 py-4">{p.end()}</td>
                <td className="px-3 py-4">{p.sale()}</td><td className="px-4 py-4">{p.status()}</td>
              </tr>
            ); })}
            <tr className="border-t border-hair align-top">
              <td className="px-4 py-4"><div className="text-small font-semibold">الفصلان معاً</div><div className="text-label text-ink-2">اشتراك واحد للفصلين الأول والثاني، بلا الصيفي</div></td>
              <td colSpan={2} className="px-3 py-4 text-small text-ink-2"><div className="flex min-h-11 items-center">من بداية الأول إلى نهاية الثاني</div></td>
              <td className="px-3 py-4">{bothSwitch()}</td><td className="px-4 py-4"><StatusCell view={views.both} change={bothChange} /></td>
            </tr>
            {summer && (() => { const p = termParts(summer); return (
              <tr className="border-t border-hair align-top">
                <td className="px-4 py-4">{p.name()}</td><td className="px-3 py-4">{p.start()}</td><td className="px-3 py-4">{p.end()}</td>
                <td className="px-3 py-4">{p.sale()}</td><td className="px-4 py-4">{p.status()}</td>
              </tr>
            ); })()}
            <tr className="border-t border-hair align-top">
              <td className="px-4 py-4"><div className="text-small font-semibold">اليومي (نقداً)</div><div className="text-label text-ink-2">ليوم واحد، يُدفع نقداً</div></td>
              <td colSpan={2} className="px-3 py-4 text-small text-ink-2"><div className="flex min-h-11 items-center">بلا مواعيد: متاح كل يوم</div></td>
              <td className="px-3 py-4">{dailySwitch()}</td><td className="px-4 py-4"><StatusCell view={dailyView} change={dailyChange} /></td>
            </tr>
            <tr className="border-t border-hair">
              <td colSpan={4} className="px-4 py-4"><div className="text-small font-semibold">{ADVANCE_TITLE}</div><div className="text-label text-ink-2">{ADVANCE_TEXT}</div></td>
              <td className="px-4 py-4 text-end">{advanceSwitch}{edits.advance !== undefined && <div className="mt-1 text-cap font-medium text-warn">لم يُحفظ</div>}</td>
            </tr>
          </tbody>
        </table>
        <div className="flex items-center gap-2 border-t border-hair bg-ground/60 px-4 py-3 text-label text-ink-2">
          <Icon name="info" size={16} className="text-ink-3" />
          <span>المواعيد تتكرر كل عام في اليوم والشهر نفسيهما، ويستخدمها التطبيق والإيصالات وانتهاء الاشتراكات. مفتاح «في الخط الجديد» هو ما يبدأ به كل خط تضيفه؛ ما يبيعه كل خط تغيّره من صفحة الخط.</span>
        </div>
      </section>

      {/* Phone and tablet: one card per subscription */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-4 xl:hidden">
        {terms.filter((t) => t.code !== 'summer').map((t) => <TermCard key={t.code} parts={termParts(t)} />)}
        <SimpleCard title="الفصلان معاً" sub="اشتراك واحد للفصلين الأول والثاني، بلا الصيفي" line="من بداية الأول إلى نهاية الثاني" control={bothSwitch(true)}
          status={<StatusCell inline view={views.both} change={bothChange} />} />
        {summer && <TermCard parts={termParts(summer)} />}
        <SimpleCard title="اليومي (نقداً)" sub="ليوم واحد، يُدفع نقداً" line="بلا مواعيد: متاح كل يوم" control={dailySwitch(true)} status={<StatusCell inline view={dailyView} change={dailyChange} />} />
        <div className="flex items-center gap-4 rounded-card bg-surface px-4 py-4 shadow-card sm:col-span-2">
          <div className="min-w-0 flex-1"><div className="text-body font-semibold">{ADVANCE_TITLE}</div>
            <div className="text-label text-ink-2"><span className="sm:hidden">يدفع الطالب الفصل القادم قبل أن يبدأ.</span><span className="hidden sm:inline">{ADVANCE_TEXT}</span></div>
            {edits.advance !== undefined && <div className="text-cap font-medium text-warn">لم يُحفظ</div>}</div>
          {advanceSwitch}
        </div>
        <p className="m-0 hidden items-start gap-2 text-label text-ink-2 sm:col-span-2 sm:flex"><Icon name="info" size={16} className="mt-0.5 text-ink-3" />المواعيد تتكرر كل عام في اليوم والشهر نفسيهما، ويستخدمها التطبيق والإيصالات وانتهاء الاشتراكات. مفتاح «في الخط الجديد» هو ما يبدأ به كل خط تضيفه؛ ما يبيعه كل خط تغيّره من صفحة الخط.</p>
      </div>

      {/* What students see on each line, as saved now */}
      <section className="flex flex-col gap-3">
        <SectionHead title="ما يراه الطلاب في كل خط" meta={<span className="hidden text-label text-ink-2 sm:inline">السعر، أو سبب عدم الظهور</span>} />
        {preview.length === 0 ? (
          <EmptyState card icon="sliders" title="لا توجد خطوط بعد"
            text={<>المواعيد جاهزة، لكن الطالب لا يجد شيئاً يشترك فيه حتى تضيف خطاً وتكتب أسعاره.<span className="hidden sm:inline"> سترى هنا ما يظهر له في كل خط.</span></>}
            action={<Button icon="plus" to={`/c/${companyId}/lines/new`}>أضف أول خط</Button>} />
        ) : (
          <>
            <div className="-mt-2 text-label text-ink-2 sm:hidden">كما هو محفوظ الآن · {linesWord(preview.length).replace('خط واحد', 'خط')}</div>
            <DataTable<LinePreview> rows={allLines ? preview : preview.slice(0, 4)} rowKey={(l) => l.line_id} caption="ما يراه الطلاب في كل خط"
              onOpen={(l) => navigate(`/c/${companyId}/lines/${l.line_id}`)}
              toolbar={<div className="hidden min-h-[52px] items-center border-b border-hair px-4 text-label text-ink-2 sm:flex">كما هو محفوظ الآن · {linesWord(preview.length)}</div>}
              columns={previewColumns(companyId)} card={(l) => previewCard(l)} />
            {!allLines && preview.length > 4 && (
              <>
                <Button kind="outline" full className="sm:hidden" onClick={() => setAllLines(true)}>اعرض {preview.length - 4 === 4 ? 'الخطوط الأربعة الباقية' : `الخطوط الباقية (${preview.length - 4})`}</Button>
                <ShowAllOnWide onShow={() => setAllLines(true)} />
              </>
            )}
          </>
        )}
      </section>

      {/* Phone: save at the bottom */}
      <PhoneBar>
        <Button full icon="check" disabled={!dirty || blocked} loading={preparing || saving} onClick={() => void askSave()}>حفظ التغييرات</Button>
        {dirty && <Button kind="link" full onClick={() => setEdits(NO_EDITS)}>تراجع عن التغييرات</Button>}
      </PhoneBar>

      {confirm && (
        <SaveDialog impact={confirm.impact} onClose={() => setConfirm(null)} onConfirm={() => void save()} saving={saving}
          changes={changes} saved={saved} terms={terms} year={year} views={views} preview={preview} flags={{ daily: edits.daily, advance: edits.advance }} />
      )}
      <LeaveDialog guard={leave} what={leaveWhat} />
    </Page>
  );
};

/** All lines are shown on wider screens at once; this only renders the phone's short list helper there. */
const ShowAllOnWide: React.FC<{ onShow: () => void }> = ({ onShow }) => {
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 640px)');
    const run = () => { if (mq.matches) onShow(); };
    run();
    mq.addEventListener('change', run);
    return () => mq.removeEventListener('change', run);
  }, [onShow]);
  return null;
};

interface TermParts { name: (phone?: boolean) => React.ReactNode; start: (label?: boolean) => React.ReactNode; end: (label?: boolean) => React.ReactNode; sale: (card?: boolean) => React.ReactNode; status: (inline?: boolean) => React.ReactNode }
const TermCard: React.FC<{ parts: TermParts }> = ({ parts }) => (
  <div className="flex flex-col gap-3 rounded-card bg-surface px-4 py-4 shadow-card">
    <div className="flex items-start gap-3">
      <div className="min-w-0 flex-1">{parts.name(true)}</div>
      {parts.sale(true)}
    </div>
    <div className="grid grid-cols-2 gap-3">{parts.start(true)}{parts.end(true)}</div>
    <div className="border-t border-hair pt-3">{parts.status(true)}</div>
  </div>
);

const SimpleCard: React.FC<{ title: string; sub: string; line: string; control: React.ReactNode; status: React.ReactNode }> = ({ title, sub, line, control, status }) => (
  <div className="flex flex-col gap-3 rounded-card bg-surface px-4 py-4 shadow-card">
    <div className="flex items-start gap-3">
      <div className="min-w-0 flex-1"><div className="text-body font-semibold">{title}</div><div className="text-label text-ink-2">{sub}</div></div>
      {control}
    </div>
    <div className="text-label text-ink-2">{line}</div>
    <div className="border-t border-hair pt-3">{status}</div>
  </div>
);

// ── «ما يراه الطلاب في كل خط» ─────────────────────────────────────────
const OPTIONS: SaleOption[] = ['first', 'second', 'both', 'summer'];
const Cell: React.FC<{ row?: SaleRow; lineOff: boolean }> = ({ row, lineOff }) => {
  const c = lineOff ? { reason: 'الخط متوقف' } as ReturnType<typeof cellView> : cellView(row);
  if (c.price != null) return <span className="inline-flex items-center gap-2"><span className="font-semibold"><Money value={c.price} /></span>{c.ahead && <Badge tone="teal">مقدماً</Badge>}</span>;
  return <Badge tone={c.warn ? 'warning' : 'neutral'} className="!whitespace-normal">لا يظهر: {c.reason}</Badge>;
};
const previewColumns = (companyId: string): Column<LinePreview>[] => [
  { key: 'line', label: 'الخط', w: 190, render: (l) => (
    <div className="min-w-0"><div className="truncate font-semibold">{l.line}</div>{!l.is_active && <div className="truncate text-cap text-ink-3">لا يظهر للطلاب</div>}</div>
  ) },
  ...OPTIONS.map((o): Column<LinePreview> => ({ key: o, label: OPTION_NAME[o], hideTablet: o === 'summer', render: (l) => <Cell row={(l.options ?? []).find((x) => x.option === o)} lineOff={!l.is_active} /> })),
  { key: 'go', label: <span className="sr-only">أسعار الخط</span>, w: 120, align: 'end', hideTablet: true, render: (l) => (
    <Link to={`/c/${companyId}/lines/${l.line_id}?edit=4`} onClick={(e) => e.stopPropagation()} className="inline-flex items-center gap-1 text-label font-medium text-teal hover:underline">أسعار الخط<Icon name="fwd" size={14} stroke={2} /></Link>
  ) },
];
const previewCard = (l: LinePreview) => ({
  title: <span className="flex items-center justify-between gap-2"><span>{l.line}</span><Icon name="fwd" size={18} className="text-ink-3" /></span>,
  sub: !l.is_active ? 'لا يظهر للطلاب' : undefined,
  fields: OPTIONS.map((o) => [o === 'summer' ? 'الصيفي' : OPTION_NAME[o], <Cell key={o} row={(l.options ?? []).find((x) => x.option === o)} lineOff={!l.is_active} />] as [React.ReactNode, React.ReactNode]),
});

// ── The save confirmation ─────────────────────────────────────────────
interface SaveProps {
  impact: Impact | null; onClose: () => void; onConfirm: () => void; saving: boolean;
  changes: { key: string; kind: string }[]; saved: Term[]; terms: Term[]; year: number; views: Record<SaleOption, OptionView>;
  preview: LinePreview[]; flags: { daily?: boolean; advance?: boolean };
}
const openWord = (n: number) => (n === 1 ? 'اشتراك واحد مفتوح' : n === 2 ? 'اشتراكان مفتوحان' : n <= 10 ? `${n} اشتراكات مفتوحة` : `${n.toLocaleString('en-US')} اشتراكاً مفتوحاً`);

/** «حفظ تغييرين في مواعيد الاشتراك؟» — each change with what it does to students, in real numbers. */
const SaveDialog: React.FC<SaveProps> = ({ impact, onClose, onConfirm, saving, changes, saved, terms, year, views, preview, flags }) => {
  const blocks: { title: string; lines: string[] }[] = [];
  const day = (t: Term, edge: 'start' | 'end', withYear = true) => termDayText(year + t[`${edge}_year_offset`], t[`${edge}_month`], t[`${edge}_day`], withYear);
  const done = new Set<string>();
  changes.forEach((c) => {
    const [code, what] = c.key.split('.');
    if (c.kind === 'date' && !done.has(code)) {
      done.add(code);
      const t = terms.find((x) => x.code === code)!; const b = saved.find((x) => x.code === code)!;
      const s = changes.some((x) => x.key === `${code}.start`); const e = changes.some((x) => x.key === `${code}.end`);
      const sameYear = (edge: 'start' | 'end') => termRange(t, year)[edge].slice(0, 4) === termRange(b, year)[edge].slice(0, 4);
      const title = s && e ? `${b.name} من ${day(t, 'start')} إلى ${day(t, 'end')}`
        : s ? `${b.name} يبدأ ${day(t, 'start')} بدل ${day(b, 'start', !sameYear('start'))}`
          : `${b.name} ينتهي ${day(t, 'end')} بدل ${day(b, 'end', !sameYear('end'))}`;
      const moved = impact?.moved?.[code];
      const verb = s && !e ? 'يبدأ' : 'ينتهي';
      blocks.push({ title, lines: [
        moved === undefined ? `الاشتراكات المفتوحة في ${b.name} تنتقل إلى الموعد الجديد.`
          : moved > 0 ? `${openWord(moved)} في ${b.name} ${verb} في الموعد الجديد.` : `لا يوجد اشتراك مفتوح في ${b.name} الآن، فلا يتغيّر اشتراك أحد.`,
        ...(impact?.moved?.both && (code === 'first' || code === 'second') && !done.has('both') ? (done.add('both'), [`ومعها ${openWord(impact.moved.both)} في «الفصلان معاً».`]) : []),
        'الإيصالات التي صدرت من قبل تبقى بتاريخها القديم.',
      ] });
    }
    if (c.kind === 'name') {
      const t = terms.find((x) => x.code === code)!; const b = saved.find((x) => x.code === code)!;
      blocks.push({ title: `يظهر «${b.name}» للطلاب باسم «${t.name.trim()}»`, lines: ['في التطبيق وعلى الإيصالات التي تصدر بعد الحفظ.'] });
    }
    if ((c.kind === 'stop' || c.kind === 'open') && what === 'sale') {
      const name = code === 'both' ? 'الفصلان معاً' : saved.find((x) => x.code === code)?.name ?? '';
      blocks.push({ title: `«${name}» ${c.kind === 'open' ? 'مفتوح' : 'مقفول'} في كل خط جديد`, lines: [
        'الخطوط الموجودة تبقى كما هي، والطلاب لا يتغيّر عندهم شيء.', 'ما يبيعه كل خط تغيّره من صفحة الخط، خطوة «الأسعار».',
      ] });
    }
  });
  if (flags.daily !== undefined) {
    blocks.push({ title: `اليومي (نقداً) ${flags.daily ? 'مفتوح' : 'مقفول'} في كل خط جديد`,
      lines: ['الخطوط الموجودة تبقى كما هي، والطلاب لا يتغيّر عندهم شيء.', 'ما يبيعه كل خط تغيّره من صفحة الخط، خطوة «الأسعار».'] });
  }
  if (flags.advance !== undefined) {
    blocks.push(flags.advance
      ? { title: 'تشغيل الدفع المسبق', lines: ['يظهر الفصل القادم للطلاب ليدفعوه قبل أن يبدأ، بسعره في كل خط.'] }
      : { title: 'إيقاف الدفع المسبق', lines: ['يُباع الفصل الجاري فقط؛ يظهر الفصل القادم حين يبدأ.', 'من دفع مقدماً من قبل يبقى اشتراكه كما هو.'] });
  }
  const actions = (verb: string) => [
    <Button key="c" kind="secondary" onClick={onClose} disabled={saving}>رجوع</Button>,
    <Button key="s" onClick={onConfirm} loading={saving}>{verb}</Button>,
  ];
  return (
    <Dialog open onClose={onClose} title={`حفظ ${changesWord(changes.length)} في مواعيد الاشتراك؟`} icon="calendar" actions={actions('حفظ التغييرات')} w={560}>
      <p className="m-0">هذا ما سيتغيّر فور الحفظ:</p>
      {blocks.map((bl, i) => (
        <div key={i} className="flex flex-col gap-1 rounded-inner bg-ground px-4 py-3">
          <div className="text-small font-semibold text-ink">{bl.title}</div>
          {bl.lines.map((l, j) => <div key={j} className="text-label text-ink-2">{l}</div>)}
        </div>
      ))}
    </Dialog>
  );
};

const DatesSkeleton: React.FC = () => (
  <div aria-busy="true" className="flex flex-col gap-6">
    <div className="overflow-hidden rounded-card bg-surface shadow-card">
      <div className="h-11 bg-ground" />
      {[0, 1, 2, 3, 4].map((i) => (
        <div key={i} className="flex h-[94px] items-center gap-6 border-t border-hair px-4">
          <SkeletonBar w={180} h={40} /><span className="hidden sm:block"><SkeletonBar w={170} h={40} /></span>
          <span className="hidden lg:block"><SkeletonBar w={170} h={40} /></span><SkeletonBar w={44} h={24} /><span className="flex-1" /><SkeletonBar w={120} h={12} />
        </div>
      ))}
    </div>
    <SkeletonBar w={220} h={18} />
    <div className="overflow-hidden rounded-card bg-surface shadow-card">
      {[0, 1, 2, 3].map((i) => <div key={i} className="flex h-14 items-center gap-8 border-t border-hair px-4 first:border-0"><SkeletonBar w={120} /><SkeletonBar w={80} /><SkeletonBar w={80} /><span className="hidden sm:block"><SkeletonBar w={80} /></span></div>)}
    </div>
  </div>
);
