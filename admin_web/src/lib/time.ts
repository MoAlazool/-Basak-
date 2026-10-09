/**
 * Clock and calendar helpers. The dashboard works in Cairo time wherever the
 * browser is; nothing here touches the network or React.
 */

export const CAIRO_ZONE = 'Africa/Cairo';
export const CAIRO_LABEL = 'بتوقيت القاهرة';

/** `07:30:00` → `07:30` ('' when there is no time). */
export const hhmm = (time?: string | null): string => (time ? String(time).slice(0, 5) : '');

/** `07:30:00` → `7:30 ص` ('' when there is no time). */
export function clockLabel(time: string | null | undefined): string {
  if (!time) return '';
  const [h, m] = time.slice(0, 5).split(':').map(Number);
  if (Number.isNaN(h) || Number.isNaN(m)) return '';
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'ص' : 'م'}`;
}

export const isDay = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value);

const cairoPartsFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: CAIRO_ZONE, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});

function cairoParts(date: Date) {
  const parts: Record<string, string> = {};
  cairoPartsFormat.formatToParts(date).forEach((part) => { parts[part.type] = part.value; });
  // Some engines print midnight as 24 with h23 missing; keep the wall clock sane.
  const hour = parts.hour === '24' ? '00' : parts.hour;
  return { day: `${parts.year}-${parts.month}-${parts.day}`, time: `${hour}:${parts.minute}` };
}

/** Today's calendar day in Cairo, `YYYY-MM-DD`, wherever the browser is. */
export const cairoToday = (now: Date = new Date()) => cairoParts(now).day;

export function addDays(day: string, days: number): string {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** An instant as the value of a `datetime-local` field showing Cairo wall time. */
export function isoToCairoLocal(iso: string | Date): string {
  const date = typeof iso === 'string' ? new Date(iso) : iso;
  if (Number.isNaN(date.getTime())) return '';
  const parts = cairoParts(date);
  return `${parts.day}T${parts.time}`;
}

const wallMs = (local: string): number | null => {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(local);
  return match ? Date.UTC(+match[1], +match[2] - 1, +match[3], +match[4], +match[5]) : null;
};

/**
 * Cairo wall time (`YYYY-MM-DDTHH:mm`) → the instant, as ISO. The offset is
 * taken from the zone's own rules for that day (Egypt moves between +2 and +3),
 * not from the browser's time zone.
 */
export function cairoLocalToIso(local: string): string | null {
  const wall = wallMs(local);
  if (wall === null) return null;
  let utc = wall - 2 * 3_600_000;
  for (let round = 0; round < 2; round += 1) {
    const shown = wallMs(isoToCairoLocal(new Date(utc)));
    if (shown === null) return null;
    utc += wall - shown;
  }
  return new Date(utc).toISOString();
}

/** A moment for the admin to read, always in Cairo time. */
export function formatCairo(iso: string | null | undefined, withYear = false): string {
  if (!iso) return '';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleString('ar-EG', {
    timeZone: CAIRO_ZONE, day: 'numeric', month: 'long', hour: 'numeric', minute: '2-digit',
    ...(withYear ? { year: 'numeric' as const } : {}),
  });
}
