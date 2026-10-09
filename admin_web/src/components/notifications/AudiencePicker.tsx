import React from 'react';
import type { LineOption, UniversityOption } from '../../lib/lineOptions';
import { AUDIENCE_KINDS, rideDayLabel, tripLabel, type AudienceDraft } from '../../lib/notifications';
import { addDays } from '../../lib/time';
import { fieldClass, labelClass } from './parts';

interface Props {
  value: AudienceDraft;
  onChange: (next: AudienceDraft) => void;
  lines: LineOption[];
  universities: UniversityOption[];
  /** Today in Cairo, `YYYY-MM-DD`. */
  today: string;
  loading?: boolean;
  disabled?: boolean;
}

/** Something chosen earlier that is no longer in the list (a stopped line) stays visible instead of silently changing. */
const Missing: React.FC<{ value: string; known: boolean }> = ({ value, known }) =>
  (value && !known ? <option value={value}>غير متاح حالياً</option> : null);

/**
 * Who the notification is for: the whole company, one line, one trip of a line
 * today or tomorrow, or one university. Only the choice leaves this page; the
 * server works out the people.
 */
export const AudiencePicker: React.FC<Props> = ({ value, onChange, lines, universities, today, loading, disabled }) => {
  const set = (patch: Partial<AudienceDraft>) => onChange({ ...value, ...patch });
  const line = lines.find((item) => item.id === value.lineId);
  const trips = (line?.line_trips ?? []).filter((trip) => trip.is_active)
    .sort((a, b) => a.direction.localeCompare(b.direction) || a.start_time.localeCompare(b.start_time));
  const days = [today, addDays(today, 1)];
  if (value.kind === 'trip' && value.rideDate && !days.includes(value.rideDate)) days.push(value.rideDate);
  const placeholder = loading ? 'جاري التحميل…' : 'اختر';

  return (
    <div>
      <span className={labelClass}>يصل إلى</span>
      <div className="mt-1 flex flex-wrap gap-2">
        {AUDIENCE_KINDS.map((kind) => (
          <button key={kind.key} type="button" disabled={disabled} aria-pressed={value.kind === kind.key}
            onClick={() => set({ kind: kind.key })}
            className={`rounded-full px-3 py-1.5 text-xs font-bold transition disabled:opacity-50 ${
              value.kind === kind.key ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
            {kind.label}
          </button>
        ))}
      </div>

      {(value.kind === 'line' || value.kind === 'trip') && (
        <div className={`mt-3 grid grid-cols-1 gap-3 ${value.kind === 'trip' ? 'md:grid-cols-3' : 'md:grid-cols-2'}`}>
          <label className="block">
            <span className={labelClass}>الخط</span>
            <select value={value.lineId} disabled={disabled} className={fieldClass}
              onChange={(e) => set({ lineId: e.target.value, tripId: '' })}>
              <option value="">{placeholder}</option>
              <Missing value={value.lineId} known={!!line} />
              {lines.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
            </select>
          </label>
          {value.kind === 'trip' && (
            <>
              <label className="block">
                <span className={labelClass}>الرحلة</span>
                <select value={value.tripId} disabled={disabled || !value.lineId} className={fieldClass}
                  onChange={(e) => set({ tripId: e.target.value })}>
                  <option value="">{!value.lineId ? 'اختر الخط أولاً' : trips.length ? 'اختر' : 'لا توجد رحلات مفعّلة'}</option>
                  <Missing value={value.tripId} known={trips.some((trip) => trip.id === value.tripId)} />
                  {trips.map((trip) => <option key={trip.id} value={trip.id}>{tripLabel(trip)}</option>)}
                </select>
              </label>
              <label className="block">
                <span className={labelClass}>يوم الرحلة</span>
                <select value={value.rideDate} disabled={disabled} className={fieldClass}
                  onChange={(e) => set({ rideDate: e.target.value })}>
                  {days.map((day) => <option key={day} value={day}>{rideDayLabel(day, today)}</option>)}
                </select>
              </label>
            </>
          )}
        </div>
      )}

      {value.kind === 'university' && (
        <label className="mt-3 block md:w-1/2">
          <span className={labelClass}>الجامعة</span>
          <select value={value.universityId} disabled={disabled} className={fieldClass}
            onChange={(e) => set({ universityId: e.target.value })}>
            <option value="">{placeholder}</option>
            <Missing value={value.universityId} known={universities.some((item) => item.id === value.universityId)} />
            {universities.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
        </label>
      )}
    </div>
  );
};
