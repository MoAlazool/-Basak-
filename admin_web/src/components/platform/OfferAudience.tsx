import React, { useId, useMemo, useState } from 'react';
import { Badge, Button, Card, Checkbox, FieldFrame, FieldRow, Icon, RadioCards, TextField, errorText, num } from '../../ui';
import { matches, useColleges } from '../../lib/platform';
import { usePlatformCompanies, useUniversities } from '../../lib/reference';
import { useGovernorates } from '../../lib/governorates';
import {
  COMMITTED, audienceSpecOf, audienceSummary, collegeOptions, hasProblems, isCommitted, keepLinesOf, nameMap, phoneDigits, reachText,
  useAudienceLines, useAudienceReach, type AudienceDraft, type AudienceNames, type AudienceProblems,
} from '../../lib/offers';

interface Option { value: string; label: string; sub?: string }

/**
 * Several choices from a list: closed, one line saying what is chosen (or that
 * nothing narrows the audience); open, the list with a search above it when it
 * is long. A chosen value that is no longer in the list stays ticked and visible.
 */
const MultiPick: React.FC<{
  label: string; allLabel: string; options: Option[]; value: string[]; onChange: (next: string[]) => void;
  help?: React.ReactNode; disabled?: boolean; loading?: boolean; emptyText?: string; goneLabel?: string;
}> = ({ label, allLabel, options, value, onChange, help, disabled, loading, emptyText = 'لا خيارات', goneLabel }) => {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const all = useMemo<Option[]>(() => {
    const known = new Set(options.map((o) => o.value));
    return [...options, ...value.filter((v) => !known.has(v)).map((v) => ({ value: v, label: goneLabel ?? v }))];
  }, [options, value, goneLabel]);
  const shown = all.filter((o) => matches(search, o.label, o.sub));
  const chosen = all.filter((o) => value.includes(o.value));
  const toggle = (v: string, on: boolean) => onChange(on ? [...new Set([...value, v])] : value.filter((x) => x !== v));
  return (
    <FieldFrame id={id} label={label} help={help} labelAs="div">
      <div className={`overflow-hidden rounded-inner shadow-ring ${disabled ? 'bg-ground' : 'bg-surface'}`}>
        <button type="button" disabled={disabled} aria-expanded={open} aria-controls={`${id}-list`} aria-labelledby={`${id}-label ${id}-now`} onClick={() => setOpen((o) => !o)}
          className="flex min-h-12 w-full items-center gap-2 px-3 py-2 text-start text-small disabled:cursor-not-allowed disabled:text-disabled sm:min-h-11">
          <span id={`${id}-now`} className={`min-w-0 flex-1 truncate ${chosen.length ? 'font-medium' : 'text-ink-3'}`}>{chosen.length ? chosen.map((o) => o.label).join('، ') : allLabel}</span>
          {chosen.length > 0 && <Badge tone="teal">{num(chosen.length)}</Badge>}
          <Icon name="down" size={16} stroke={2} className={`text-ink-3 transition-transform ${open ? 'rotate-180' : ''}`} />
        </button>
        {open && !disabled && (
          <div id={`${id}-list`} className="border-t border-hair">
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 bg-ground px-3 py-1.5">
              {all.length > 8 ? (
                <label className="flex h-9 min-w-0 flex-1 items-center gap-2 text-ink-3">
                  <Icon name="search" size={16} />
                  <input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="ابحث" aria-label={`ابحث في ${label}`}
                    className="h-full min-w-0 flex-1 bg-transparent text-label text-ink outline-none placeholder:text-ink-3 [&::-webkit-search-cancel-button]:hidden" />
                </label>
              ) : <span className="flex-1 text-label text-ink-2">{num(chosen.length)} من {num(all.length)}</span>}
              <Button kind="link" sm disabled={value.length === 0} onClick={() => onChange([])}>امسح</Button>
            </div>
            <div className="grid max-h-56 grid-cols-1 gap-x-4 overflow-y-auto px-3 py-1 sm:grid-cols-2">
              {shown.map((o) => (
                <Checkbox key={o.value} className="min-w-0" checked={value.includes(o.value)} onChange={(on) => toggle(o.value, on)}
                  label={<span className="flex min-w-0 flex-col"><span className="truncate">{o.label}</span>{o.sub && <span className="truncate text-cap text-ink-3">{o.sub}</span>}</span>} />
              ))}
              {shown.length === 0 && <p className="m-0 py-2 text-label text-ink-2 sm:col-span-2">{loading ? 'جاري التحميل…' : search.trim() ? 'لا نتيجة بهذا البحث.' : emptyText}</p>}
            </div>
          </div>
        )}
      </div>
    </FieldFrame>
  );
};

/** Words typed one at a time (Enter adds), each shown as a tag that can be removed. */
const TagsField: React.FC<{ label: string; value: string[]; onChange: (next: string[]) => void; placeholder?: string; help?: React.ReactNode; disabled?: boolean }> = ({ label, value, onChange, placeholder, help, disabled }) => {
  const [text, setText] = useState('');
  const add = () => {
    const word = text.trim().replace(/\s+/g, ' ');
    if (word && !value.includes(word)) onChange([...value, word]);
    setText('');
  };
  return (
    <div className="flex flex-col gap-2">
      <TextField label={label} optional value={text} disabled={disabled} placeholder={placeholder} maxLength={80} help={help}
        onChange={(e) => setText(e.target.value)} onBlur={add}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ',' || e.key === '،') { e.preventDefault(); add(); } }}
        end={<Button sm kind="tonal" icon="plus" disabled={disabled || !text.trim()} onClick={add} className="-me-1.5">أضف</Button>} />
      {value.length > 0 && (
        <ul className="m-0 flex list-none flex-wrap gap-1.5 p-0">
          {value.map((word) => (
            <li key={word} className="inline-flex h-8 items-center gap-1 rounded-control bg-teal-tint ps-2.5 text-label font-medium text-teal">
              <span>{word}</span>
              <button type="button" disabled={disabled} aria-label={`احذف ${word}`} onClick={() => onChange(value.filter((x) => x !== word))}
                className="flex h-8 w-8 items-center justify-center rounded-control hover:bg-teal-tint2"><Icon name="x" size={14} stroke={2} /></button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};

/** A whole number typed in Western digits; empty stays empty. */
export const NumberField: React.FC<Omit<React.ComponentProps<typeof TextField>, 'value' | 'onChange' | 'type'> & { value: number | ''; onValue: (v: number | '') => void; digits?: number }> = ({ value, onValue, digits = 4, ...rest }) => (
  <TextField {...rest} inputMode="numeric" ltr value={value}
    onChange={(e) => { const d = phoneDigits(e.target.value).replace(/\D/g, '').slice(0, digits); onValue(d === '' ? '' : Number(d)); }} />
);

/** The lookups the builder chooses from and the summary names things by. */
function useAudienceLookups(companyIds: readonly string[]) {
  const universities = useUniversities();
  const colleges = useColleges();
  const companies = usePlatformCompanies();
  const governorates = useGovernorates();
  const lines = useAudienceLines(companyIds);
  const names: AudienceNames = useMemo(() => ({
    universities: nameMap(universities.data, (u) => u.id, (u) => u.name),
    companies: nameMap(companies.data, (c) => c.id, (c) => c.name),
    governorates: nameMap(governorates.data, (g) => g.code, (g) => g.name),
    lines: nameMap(lines.data, (l) => l.id, (l) => l.name),
  }), [universities.data, companies.data, governorates.data, lines.data]);
  return { universities, colleges, companies, governorates, lines, names };
}

/** The names a stored audience is written with (the list and the details view). */
export function useAudienceNames(): AudienceNames {
  const universities = useUniversities();
  const companies = usePlatformCompanies();
  const governorates = useGovernorates();
  return useMemo(() => ({
    universities: nameMap(universities.data, (u) => u.id, (u) => u.name),
    companies: nameMap(companies.data, (c) => c.id, (c) => c.name),
    governorates: nameMap(governorates.data, (g) => g.code, (g) => g.name),
  }), [universities.data, companies.data, governorates.data]);
}

/**
 * «من يراه»: who an offer is for. Every choice narrows the audience and all of
 * them must hold; nothing chosen in a list means that list does not narrow it.
 * Only the choice leaves the page; the server works out the students.
 */
export const AudienceBuilder: React.FC<{ value: AudienceDraft; onChange: (next: AudienceDraft) => void; problems?: AudienceProblems; disabled?: boolean }> = ({ value, onChange, problems = {}, disabled }) => {
  const look = useAudienceLookups(value.companyIds);
  const set = (patch: Partial<AudienceDraft>) => onChange({ ...value, ...patch });
  const lines = look.lines.data ?? [];
  const companyName = (id: string) => look.names.companies?.get(id) ?? '';
  const spec = audienceSpecOf(value);
  const committed = isCommitted(spec);
  const asks = spec.min_rides !== undefined || spec.min_attendance !== undefined;

  return (
    <div className="flex flex-col gap-4">
      <RadioCards<'active' | 'any'> label="الاشتراك" cols={2} value={value.subscription} onChange={(subscription) => { if (!disabled) set({ subscription }); }} options={[
        { value: 'active', label: 'مشتركون حالياً', sub: 'لهم اشتراك سارٍ اليوم', disabled },
        { value: 'any', label: 'كل الطلاب', sub: 'مشتركون وغير مشتركين', disabled },
      ]} />
      <FieldRow>
        <MultiPick label="الجامعات" allLabel="كل الجامعات" disabled={disabled} loading={look.universities.loading} goneLabel="جامعة غير موجودة"
          options={(look.universities.data ?? []).filter((u) => u.is_active || value.universityIds.includes(u.id)).map((u) => ({ value: u.id, label: u.name, sub: u.city }))}
          value={value.universityIds} onChange={(universityIds) => set({ universityIds })} />
        <MultiPick label="الكليات" allLabel="كل الكليات" disabled={disabled} loading={look.colleges.loading}
          options={collegeOptions(look.colleges.data ?? [], value.universityIds, value.colleges).map((name) => ({ value: name, label: name }))}
          value={value.colleges} onChange={(colleges) => set({ colleges })}
          help={value.universityIds.length ? 'كليات الجامعات المختارة ثم القائمة العامة. تُطابق بالاسم كما سجّله الطالب.' : 'تُطابق بالاسم كما سجّله الطالب، في أي جامعة.'} />
      </FieldRow>
      <TagsField label="التخصصات" value={value.specialisations} onChange={(specialisations) => set({ specialisations })} disabled={disabled}
        placeholder="مثل: عمارة" help="اكتب التخصص كما يكتبه الطلاب ثم Enter. يطابق من سجّل هذا التخصص بنصّه." />
      <FieldRow>
        <MultiPick label="الشركات" allLabel="كل الشركات" disabled={disabled} loading={look.companies.loading} goneLabel="شركة غير موجودة"
          options={(look.companies.data ?? []).filter((c) => (c.status ?? 'active') !== 'archived' || value.companyIds.includes(c.id)).map((c) => ({ value: c.id, label: c.name }))}
          value={value.companyIds} onChange={(companyIds) => set({ companyIds, lineIds: look.lines.data ? keepLinesOf(value.lineIds, lines, companyIds) : companyIds.length ? value.lineIds : [] })} />
        <MultiPick label="الخطوط" allLabel={value.companyIds.length ? 'كل خطوط الشركات المختارة' : 'اختر شركة أولاً'} disabled={disabled || (value.companyIds.length === 0 && value.lineIds.length === 0)}
          loading={look.lines.loading} emptyText="لا خطوط لهذه الشركات." goneLabel="خط غير موجود"
          options={lines.filter((l) => value.companyIds.includes(l.company_id)).map((l) => ({ value: l.id, label: l.name, sub: value.companyIds.length > 1 ? companyName(l.company_id) : undefined }))}
          value={value.lineIds} onChange={(lineIds) => set({ lineIds })} help="خط محدد يعني من له اشتراك سارٍ عليه." />
      </FieldRow>
      <MultiPick label="المحافظات" allLabel="كل المحافظات" disabled={disabled} loading={look.governorates.isPending}
        options={(look.governorates.data ?? []).map((g) => ({ value: g.code, label: g.name }))}
        value={value.governorates} onChange={(governorates) => set({ governorates })} help="محافظة الطالب هي محافظات الشركة التي يركب معها." />
      {problems.lists && <p role="alert" className="m-0 text-label text-bad">{problems.lists}</p>}

      <div className="flex flex-col gap-3 border-t border-hair pt-4">
        <div className="flex flex-wrap items-center gap-2">
          <span className="flex-1 text-label font-medium">الالتزام بالركوب</span>
          <button type="button" disabled={disabled} aria-pressed={committed} onClick={() => set({ minRides: COMMITTED.min_rides, minAttendance: COMMITTED.min_attendance, windowDays: COMMITTED.window_days })}
            className={`inline-flex h-10 items-center gap-1.5 rounded-full px-3.5 text-label disabled:opacity-50 sm:h-9 ${committed ? 'bg-ink font-semibold text-white' : 'bg-surface text-ink shadow-ring hover:bg-ground'}`}>
            {committed && <Icon name="check" size={14} stroke={2.5} />}ملتزم
          </button>
          {asks && <Button kind="link" sm disabled={disabled} onClick={() => set({ minRides: '', minAttendance: '' })}>بلا شرط</Button>}
        </div>
        <FieldRow>
          <NumberField label="أيام ركوب على الأقل" optional value={value.minRides} onValue={(minRides) => set({ minRides })} digits={3} suffix="يوم" disabled={disabled} error={problems.minRides} />
          <NumberField label="نسبة الحضور على الأقل" optional value={value.minAttendance} onValue={(minAttendance) => set({ minAttendance })} digits={3} suffix="%" disabled={disabled} error={problems.minAttendance} />
          <NumberField label="خلال آخر" value={value.windowDays} onValue={(windowDays) => set({ windowDays })} digits={3} suffix="يوم" disabled={disabled || !asks} error={problems.windowDays} />
        </FieldRow>
        <p className="m-0 text-label text-ink-2">
          يوم الركوب يوم مسحه المشرف في الباص. الحضور: من الأيام التي أكّد الطالب أنه سيركب فيها، نسبة ما ركبه فعلاً. «ملتزم» = {num(COMMITTED.min_rides)} أيام و{num(COMMITTED.min_attendance)}% خلال آخر {num(COMMITTED.window_days)} يوماً.
        </p>
      </div>
    </div>
  );
};

/**
 * «يصل إلى N طالباً الآن»: the audience as the server counts it today, a moment
 * after the last change. The last number stays (dimmed) while the next is counted.
 */
export const AudienceReach: React.FC<{ value: AudienceDraft; problems?: AudienceProblems; className?: string }> = ({ value, problems = {}, className = '' }) => {
  const look = useAudienceLookups(value.companyIds);
  const invalid = hasProblems(problems);
  const spec = audienceSpecOf(value);
  const reach = useAudienceReach(invalid ? null : spec);
  return (
    <Card as="section" className={`flex flex-col gap-2 px-4 py-4 sm:px-5 ${className}`}>
      <h3 className="m-0 text-label font-medium text-ink-2">من يصله العرض</h3>
      <div aria-live="polite" aria-busy={reach.refreshing} className="flex flex-col gap-1">
        {reach.students === null ? (
          <span className="text-small text-ink-2">{invalid ? 'صحّح شروط الجمهور لنعدّ من يصله.' : reach.error ? 'تعذّر عدّ الطلاب.' : 'نعدّ الطلاب…'}</span>
        ) : (
          <>
            <span className={`text-num-phone tabular transition-opacity sm:text-num ${reach.refreshing || invalid ? 'opacity-40' : ''} ${reach.students === 0 ? 'text-bad' : ''}`}>{num(reach.students)}</span>
            <span className="text-small font-medium">{reachText(reach.students)}</span>
          </>
        )}
        <span className="min-h-[22px] text-label text-ink-3">
          {invalid ? (reach.students !== null ? 'آخر عدد قبل الخطأ في الشروط.' : '')
            : reach.error ? <span role="alert" className="text-bad">{errorText(reach.error, 'تعذّر عدّ الطلاب. غيّر الاختيار أو حاول بعد قليل.')}</span>
              : reach.refreshing ? 'نحدّث العدد…' : reach.students === 0 ? 'لا يطابق هذه الشروط أي طالب اليوم.' : ''}
        </span>
      </div>
      <p className="m-0 border-t border-hair pt-2 text-small">{audienceSummary(spec, look.names)}</p>
      <p className="m-0 text-cap text-ink-3">العدد لليوم ويتغيّر مع الاشتراكات والركوب. من أخفى العروض من تطبيقه لا يُحسب.</p>
    </Card>
  );
};
