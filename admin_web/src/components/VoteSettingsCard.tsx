import React, { useEffect, useState } from 'react';
import { SkeletonForm } from './Skeleton';
import { BellRing, CalendarOff, Clock3, Plus, RotateCcw, Save, X } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useQueryClient } from '@tanstack/react-query';
import { keys, unwrap, usePageData } from '../lib/query';
import { clockLabel } from '../lib/overview';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { cairoToday } from '../lib/time';
import { notifyError } from '../lib/toasts';

interface Settings {
  opens_at: string;
  closes_at: string;
  reminder_minutes: number;
  /** Ride days without reminders: ISO weekdays (1 = Monday ... 7 = Sunday) and dates (YYYY-MM-DD). */
  off_weekdays: number[];
  off_dates: string[];
}
interface VoteSettings extends Settings {
  window_text: string;
  /** The company has its own settings (otherwise it follows the platform). */
  custom: boolean;
  can_edit_platform: boolean;
  platform: Settings;
}

/** The week as it is lived in Egypt, Saturday first (ISO numbers). */
const WEEK = [
  { iso: 6, name: 'السبت' }, { iso: 7, name: 'الأحد' }, { iso: 1, name: 'الاثنين' }, { iso: 2, name: 'الثلاثاء' },
  { iso: 3, name: 'الأربعاء' }, { iso: 4, name: 'الخميس' }, { iso: 5, name: 'الجمعة' },
];
const dateLabel = new Intl.DateTimeFormat('ar-EG', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
const formatDate = (ymd: string) => dateLabel.format(new Date(`${ymd}T00:00:00Z`));
const sameList = <T,>(a: T[], b: T[]) => a.length === b.length && a.every((x, i) => x === b[i]);
const sorted = (list: number[]) => [...list].sort((a, b) => a - b);

/** The days off in words: "كل الجمعة، الثلاثاء ٦ أكتوبر". */
function daysOffText(weekdays: number[], dates: string[]): string {
  return [
    ...WEEK.filter((d) => weekdays.includes(d.iso)).map((d) => `كل ${d.name}`),
    ...dates.map(formatDate),
  ].join('، ');
}

const REMINDERS = [
  { value: 0, label: 'بدون تذكير' },
  { value: 15, label: 'كل ١٥ دقيقة' },
  { value: 30, label: 'كل ٣٠ دقيقة' },
  { value: 60, label: 'كل ساعة' },
  { value: 120, label: 'كل ساعتين' },
  { value: 180, label: 'كل ٣ ساعات' },
  { value: 240, label: 'كل ٤ ساعات' },
  { value: 360, label: 'كل ٦ ساعات' },
  { value: 1440, label: 'مرة واحدة عند فتح التصويت' },
];
const reminderLabel = (minutes: number) =>
  REMINDERS.find((r) => r.value === minutes)?.label ?? `كل ${minutes.toLocaleString('ar-EG')} دقيقة`;

const toMinutes = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};
const fromMinutes = (total: number) => {
  const t = ((total % 1440) + 1440) % 1440;
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};

/** The vote closes on the ride day when its closing time is not after the opening time. */
const closesOnRideDay = (opens: string, closes: string) => toMinutes(closes) <= toMinutes(opens);

/** Reminder times in one window: when it opens, then every `every` minutes until it closes. */
function reminderTimes(opens: string, closes: string, every: number): string[] {
  if (!every || opens === closes) return [];
  const start = toMinutes(opens);
  const length = closesOnRideDay(opens, closes) ? toMinutes(closes) + 1440 - start : toMinutes(closes) - start;
  const times: string[] = [];
  for (let t = 0; t < length; t += every) times.push(fromMinutes(start + t));
  return times;
}

/**
 * When students can confirm a ride and how often the app reminds those who have
 * not yet. companyId = null edits the platform's settings (Super Admin), which
 * every company follows until it sets its own.
 */
export const VoteSettingsCard: React.FC<{ companyId: string | null; companyName: string }> = ({ companyId, companyName }) => {
  const client = useQueryClient();
  const guard = useGuard();
  const voteKey = companyId ? keys.company(companyId, 'vote') : keys.platform('vote');
  const page = usePageData(voteKey, () =>
    unwrap<VoteSettings>(supabase.rpc('get_vote_settings', { p_company_id: companyId })));
  const vote = page.data ?? null;
  const [opens, setOpens] = useState('16:00');
  const [closes, setCloses] = useState('06:00');
  const [every, setEvery] = useState(0);
  const [offWeekdays, setOffWeekdays] = useState<number[]>([]);
  const [offDates, setOffDates] = useState<string[]>([]);
  const [newDate, setNewDate] = useState('');
  const [saving, setSaving] = useState(false);

  // The editable copy follows what is saved, whenever that changes.
  useEffect(() => {
    if (!vote) return;
    setOpens(vote.opens_at);
    setCloses(vote.closes_at);
    setEvery(vote.reminder_minutes);
    setOffWeekdays(sorted(vote.off_weekdays ?? []));
    setOffDates([...(vote.off_dates ?? [])].sort());
  }, [vote]);

  // The card's place is held while it loads, so the page does not jump when it arrives.
  if (page.loading || !vote) return <SkeletonForm fields={3} />;
  const editable = companyId ? true : vote.can_edit_platform;
  const changed = opens !== vote.opens_at || closes !== vote.closes_at || every !== vote.reminder_minutes
    || !sameList(offWeekdays, sorted(vote.off_weekdays ?? [])) || !sameList(offDates, [...(vote.off_dates ?? [])].sort());
  const today = cairoToday();
  const toggleWeekday = (iso: number) =>
    setOffWeekdays((all) => (all.includes(iso) ? all.filter((d) => d !== iso) : sorted([...all, iso])));
  const canAddDate = !!newDate && newDate >= today && !offDates.includes(newDate);
  const addDate = () => {
    if (!canAddDate) return;
    setOffDates((all) => [...all, newDate].sort());
    setNewDate('');
  };
  const offText = daysOffText(offWeekdays, offDates);
  const platformOff = daysOffText(vote.platform.off_weekdays ?? [], vote.platform.off_dates ?? []);
  const sameTimes = opens === closes;
  const times = reminderTimes(opens, closes, every);

  // One request: the function answers with the settings as they are now, which replace the cached ones.
  const save = (reset = false) => guard('save', async () => {
    setSaving(true);
    const { data, error } = await supabase.rpc('set_vote_settings', {
      p_company_id: companyId,
      p_opens_at: reset ? null : opens,
      p_closes_at: reset ? null : closes,
      p_reminder_minutes: reset ? null : every,
      p_off_weekdays: reset ? null : offWeekdays,
      p_off_dates: reset ? null : offDates,
    });
    setSaving(false);
    if (error) {
      notifyError('تعذر حفظ مواعيد التصويت', error.message);
      return page.reload();
    }
    // The company row's announcement refreshes the overview (it shows when the vote closes), nothing else.
    if (companyId) rememberApplied([companyId], ['company', 'settings', 'switches', 'vote']);
    if (data) client.setQueryData<VoteSettings>(voteKey, data as VoteSettings);
    else await page.reload();
  });

  const input = 'mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm disabled:bg-slate-50';
  const options = REMINDERS.some((r) => r.value === every) ? REMINDERS : [...REMINDERS, { value: every, label: reminderLabel(every) }];

  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
      <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
        <Clock3 className="h-5 w-5 text-blue-600" /> مواعيد تأكيد الرحلة والتذكير
      </h2>
      <p className="mt-1 text-xs text-slate-500">
        {companyId
          ? vote.custom
            ? `مواعيد خاصة بـ ${companyName}. يطبّقها التطبيق على طلابها فقط.`
            : `${companyName} تتبع إعداد المنصة حالياً. أي تعديل هنا يصبح خاصاً بها.`
          : 'تتبعها كل شركة لم تحدد مواعيدها الخاصة من إعداداتها.'}
      </p>

      <div className="mt-4 grid gap-3 sm:grid-cols-3">
        <label className="text-xs font-semibold text-slate-600">
          يفتح التصويت
          <input type="time" disabled={!editable} value={opens} onChange={(e) => setOpens(e.target.value)} className={input} />
          <span className="mt-1 block text-[11px] font-normal text-slate-400">في اليوم السابق للرحلة</span>
        </label>
        <label className="text-xs font-semibold text-slate-600">
          يُقفل التصويت
          <input type="time" disabled={!editable} value={closes} onChange={(e) => setCloses(e.target.value)} className={input} />
          <span className="mt-1 block text-[11px] font-normal text-slate-400">
            {sameTimes ? '—' : closesOnRideDay(opens, closes) ? 'يوم الرحلة نفسه' : 'في نفس اليوم السابق للرحلة'}
          </span>
        </label>
        <label className="text-xs font-semibold text-slate-600">
          <span className="flex items-center gap-1"><BellRing className="h-3.5 w-3.5" /> تذكير الطلاب في التطبيق</span>
          <select disabled={!editable} value={every} onChange={(e) => setEvery(Number(e.target.value))} className={input}>
            {options.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
          </select>
          <span className="mt-1 block text-[11px] font-normal text-slate-400">لمن لم يؤكد رحلته فقط</span>
        </label>
      </div>

      <div className="mt-4 rounded-xl border border-slate-100 p-3">
        <p className="flex items-center gap-1.5 text-xs font-semibold text-slate-600">
          <CalendarOff className="h-3.5 w-3.5" /> أيام بدون تذكير
        </p>
        <p className="mt-0.5 text-[11px] text-slate-400">
          المقصود يوم الرحلة نفسه: اختيار الجمعة يوقف التذكير الخاص برحلة الجمعة. التصويت نفسه يظل متاحاً.
        </p>
        <div className="mt-2 flex flex-wrap gap-1.5">
          {WEEK.map((d) => {
            const off = offWeekdays.includes(d.iso);
            return (
              <button key={d.iso} type="button" disabled={!editable} onClick={() => toggleWeekday(d.iso)} aria-pressed={off}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition disabled:opacity-60 ${
                  off ? 'bg-rose-50 text-rose-700 ring-1 ring-rose-200' : 'bg-slate-50 text-slate-600 ring-1 ring-slate-200'}`}>
                {d.name}{off ? ' · بدون تذكير' : ''}
              </button>
            );
          })}
        </div>

        <p className="mt-3 text-xs font-semibold text-slate-600">إجازات رسمية</p>
        {editable && (
          <div className="mt-1 flex gap-2">
            <input type="date" min={today} value={newDate} onChange={(e) => setNewDate(e.target.value)}
              className="rounded-lg border border-slate-200 px-3 py-1.5 text-sm" />
            <button type="button" onClick={addDate} disabled={!canAddDate}
              className="flex items-center gap-1 rounded-lg bg-slate-100 px-3 py-1.5 text-xs font-semibold text-slate-700 disabled:opacity-50">
              <Plus className="h-3.5 w-3.5" /> إضافة
            </button>
          </div>
        )}
        <div className="mt-2 flex flex-wrap gap-1.5">
          {offDates.length === 0 && <span className="text-[11px] text-slate-400">لا توجد إجازات قادمة.</span>}
          {offDates.map((d) => (
            <span key={d} className="flex items-center gap-1 rounded-full bg-rose-50 px-3 py-1 text-xs font-semibold text-rose-700">
              {formatDate(d)}
              {editable && (
                <button type="button" aria-label={`حذف ${formatDate(d)}`} onClick={() => setOffDates((all) => all.filter((x) => x !== d))}>
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </span>
          ))}
        </div>
      </div>

      <div className="mt-4 rounded-xl bg-slate-50 p-3 text-xs text-slate-600">
        {sameTimes ? (
          <p className="font-semibold text-rose-600">يجب أن يختلف موعد القفل عن موعد الفتح.</p>
        ) : (
          <>
            <p>
              مثال: رحلة الخميس — يفتح التصويت الأربعاء {clockLabel(opens)} ويُقفل{' '}
              {closesOnRideDay(opens, closes) ? 'الخميس' : 'الأربعاء'} {clockLabel(closes)}.
            </p>
            <p className="mt-1">
              {times.length === 0
                ? 'لا تُرسل تذكيرات.'
                : `التذكير ${times.length === 1 ? 'مرة واحدة' : `${times.length.toLocaleString('ar-EG')} مرات`}: ${times.map(clockLabel).join('، ')} — ويتوقف بمجرد أن يؤكد الطالب أو يلغي.`}
            </p>
            {times.length > 0 && offText && <p className="mt-1">لا تذكير لرحلات: {offText}.</p>}
          </>
        )}
        {companyId && vote.custom && (
          <p className="mt-1 text-slate-400">
            إعداد المنصة: {clockLabel(vote.platform.opens_at)} ← {clockLabel(vote.platform.closes_at)}، {reminderLabel(vote.platform.reminder_minutes)}
            {platformOff && `، بدون تذكير: ${platformOff}`}.
          </p>
        )}
      </div>

      {editable && (
        <div className="mt-3 flex flex-wrap justify-end gap-2">
          {companyId && vote.custom && (
            <button disabled={saving} onClick={() => void save(true)}
              className="flex items-center gap-2 rounded-xl border border-slate-200 px-4 py-2 text-sm font-semibold text-slate-600 disabled:opacity-50">
              <RotateCcw className="h-4 w-4" /> الرجوع لإعداد المنصة
            </button>
          )}
          <button disabled={saving || !changed || sameTimes} onClick={() => void save()}
            className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-50">
            <Save className="h-4 w-4" /> {saving ? 'جاري الحفظ...' : 'حفظ المواعيد'}
          </button>
        </div>
      )}
    </div>
  );
};
