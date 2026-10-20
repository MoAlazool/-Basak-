import React, { useEffect, useId, useRef, useState } from 'react';
import { FieldFrame, Icon } from '../../ui';
import { clockLabel } from '../../lib/time';
import { parseClock } from '../../lib/lines';

const RING = 'shadow-field hover:shadow-field-hover focus-within:!shadow-field-focus';
const frame = (error?: boolean, disabled?: boolean, sm?: boolean) =>
  `relative flex ${sm ? 'h-11 sm:h-10' : 'h-12 sm:h-11'} items-center gap-2 rounded-control px-3 text-small ${disabled ? 'bg-ground shadow-ring text-disabled' : `bg-surface ${error ? 'shadow-field-error' : RING}`}`;

/** Opens the browser's own picker of a hidden native field (clock or calendar), where it can. */
function openPicker(el: HTMLInputElement | null) {
  if (!el) return;
  try { (el as HTMLInputElement & { showPicker?: () => void }).showPicker?.(); } catch { el.focus(); }
}

/**
 * A time as the dashboard writes it («7:30 ص»). Typed freely («730», «7:30 م»,
 * «19:30») and read on leaving the field; the clock opens the browser's picker.
 * `value` and `onChange` are `HH:MM` ('' when empty).
 */
export const TimeField: React.FC<{
  value: string; onChange: (v: string) => void; label?: React.ReactNode; help?: React.ReactNode; error?: string | boolean;
  optional?: boolean; disabled?: boolean; assume?: 'am' | 'pm'; ariaLabel?: string; sm?: boolean; className?: string; placeholder?: string;
}> = ({ value, onChange, label, help, error, optional, disabled, assume, ariaLabel, sm, className = '', placeholder = 'مثال: 7:30 ص' }) => {
  const id = useId();
  const native = useRef<HTMLInputElement>(null);
  const [text, setText] = useState(clockLabel(value));
  const [focused, setFocused] = useState(false);
  const [bad, setBad] = useState(false);
  useEffect(() => { if (!focused) { setText(clockLabel(value)); setBad(false); } }, [value, focused]);
  const commit = () => {
    const parsed = parseClock(text, assume);
    if (parsed === null) { setBad(true); return; }
    setBad(false);
    setText(clockLabel(parsed));
    if (parsed !== value) onChange(parsed);
  };
  const message = bad ? 'اكتب الموعد مثل 7:30 ص.' : typeof error === 'string' ? error : undefined;
  const field = (
    <div className={`${frame(bad || !!error, disabled, sm)} ${label ? '' : className}`}>
      <input id={id} type="text" inputMode="text" dir="rtl" value={text} disabled={disabled} placeholder={placeholder}
        aria-label={label ? undefined : ariaLabel} aria-invalid={bad || !!error || undefined} aria-describedby={message || help ? `${id}-msg` : undefined}
        onFocus={() => setFocused(true)} onBlur={() => { setFocused(false); commit(); }}
        onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); commit(); } }}
        onChange={(e) => setText(e.target.value)}
        className="h-full min-w-0 flex-1 bg-transparent text-start tabular outline-none placeholder:text-ink-3 disabled:cursor-not-allowed" />
      {/* The clock icon is the tap target: the native time input sits over it (opacity 0),
          so a tap opens the phone's own picker (iOS included, where showPicker is unavailable),
          and a desktop click calls showPicker. */}
      <span className="relative -me-1 flex h-9 w-9 flex-none items-center justify-center rounded-control text-ink-2">
        <Icon name="clock" size={17} className={disabled ? 'text-disabled' : ''} />
        <input ref={native} type="time" tabIndex={-1} value={value} disabled={disabled}
          aria-label={ariaLabel ?? (typeof label === 'string' ? label : 'الوقت')}
          onClick={() => openPicker(native.current)}
          onChange={(e) => { onChange(e.target.value); setText(clockLabel(e.target.value)); setBad(false); }}
          className="absolute inset-0 cursor-pointer opacity-0 disabled:cursor-not-allowed" />
      </span>
    </div>
  );
  if (!label) return message ? <div className={`flex flex-col gap-1.5 ${className}`}>{field}<FieldMsg id={id} text={message} /></div> : field;
  return <FieldFrame id={id} label={label} help={help} error={message} optional={optional} className={className}>{field}</FieldFrame>;
};

const FieldMsg: React.FC<{ id: string; text: string }> = ({ id, text }) => (
  <div id={`${id}-msg`} role="alert" className="flex items-start gap-1.5 text-label text-bad"><Icon name="alert" size={14} stroke={2} className="mt-[3px]" /><span>{text}</span></div>
);

/** A calendar day chosen from the browser's calendar, shown as «الخميس 22 أكتوبر». */
export const DayField: React.FC<{
  value: string; onChange: (v: string) => void; min?: string; text: string; label: string; error?: string; disabled?: boolean; className?: string;
}> = ({ value, onChange, min, text, label, error, disabled, className = '' }) => {
  const native = useRef<HTMLInputElement>(null);
  const id = useId();
  return (
    <div className={`flex min-w-0 flex-col gap-1.5 ${className}`}>
      <div className={frame(!!error, disabled)}>
        {/* The native date input overlays the whole field (opacity 0), so a tap opens the
            phone's own calendar (iOS included); a desktop click calls showPicker. */}
        <div aria-hidden="true" className="flex h-full min-w-0 flex-1 items-center gap-2">
          <span className={`min-w-0 flex-1 truncate ${value ? 'text-ink' : 'text-ink-3'}`}>{value ? text : 'اختر يوماً'}</span>
          <Icon name="calendar" size={17} className={disabled ? 'text-disabled' : 'text-ink-2'} />
        </div>
        <input ref={native} type="date" tabIndex={disabled ? -1 : 0} value={value} min={min} disabled={disabled}
          aria-label={`${label}: ${value ? text : 'اختر يوماً'}`} aria-describedby={error ? `${id}-msg` : undefined}
          onClick={() => openPicker(native.current)} onChange={(e) => onChange(e.target.value)}
          className="absolute inset-0 cursor-pointer opacity-0 disabled:cursor-not-allowed" />
      </div>
      {error && <FieldMsg id={id} text={error} />}
    </div>
  );
};
