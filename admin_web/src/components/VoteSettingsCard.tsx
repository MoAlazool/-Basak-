import React, { useEffect, useState } from 'react';
import { BellRing, Clock3, RotateCcw, Save } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { keys, unwrap, usePageData } from '../lib/query';
import { clockLabel } from '../lib/overview';

interface VoteSettings {
  opens_at: string;
  closes_at: string;
  reminder_minutes: number;
  window_text: string;
  /** The company has its own settings (otherwise it follows the platform). */
  custom: boolean;
  can_edit_platform: boolean;
  platform: { opens_at: string; closes_at: string; reminder_minutes: number };
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
  const page = usePageData(companyId ? keys.company(companyId, 'vote') : keys.platform('vote'), () =>
    unwrap<VoteSettings>(supabase.rpc('get_vote_settings', { p_company_id: companyId })));
  const vote = page.data ?? null;
  const [opens, setOpens] = useState('16:00');
  const [closes, setCloses] = useState('06:00');
  const [every, setEvery] = useState(0);
  const [saving, setSaving] = useState(false);

  // The editable copy follows what is saved, whenever that changes.
  useEffect(() => {
    if (!vote) return;
    setOpens(vote.opens_at);
    setCloses(vote.closes_at);
    setEvery(vote.reminder_minutes);
  }, [vote]);

  if (page.loading || !vote) return null;
  const editable = companyId ? true : vote.can_edit_platform;
  const changed = opens !== vote.opens_at || closes !== vote.closes_at || every !== vote.reminder_minutes;
  const sameTimes = opens === closes;
  const times = reminderTimes(opens, closes, every);

  const save = async (reset = false) => {
    try {
      setSaving(true);
      const { error } = await supabase.rpc('set_vote_settings', {
        p_company_id: companyId,
        p_opens_at: reset ? null : opens,
        p_closes_at: reset ? null : closes,
        p_reminder_minutes: reset ? null : every,
      });
      if (error) throw error;
    } catch (err: any) {
      alert('تعذر حفظ مواعيد التصويت: ' + err.message);
    } finally {
      setSaving(false);
      await page.reload();
    }
  };

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
          </>
        )}
        {companyId && vote.custom && (
          <p className="mt-1 text-slate-400">
            إعداد المنصة: {clockLabel(vote.platform.opens_at)} ← {clockLabel(vote.platform.closes_at)}، {reminderLabel(vote.platform.reminder_minutes)}.
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
