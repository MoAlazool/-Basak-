/**
 * Pure helpers of the notifications page: shapes, audience → payload, the
 * idempotency key, labels and Cairo time. Nothing here touches the network or
 * React, so every function can be tested with plain values.
 */

export const TITLE_MAX = 80;
export const BODY_MAX = 600;
export const CAIRO_ZONE = 'Africa/Cairo';
export const CAIRO_LABEL = 'بتوقيت القاهرة';

// ---------------------------------------------------------------- shapes ----

export type AudienceKind = 'company' | 'line' | 'trip' | 'university';

/** What the server takes. It resolves the recipients itself; ids of people are never sent. */
export type AudienceSpec =
  | { kind: 'company' }
  | { kind: 'line'; line_id: string }
  | { kind: 'trip'; line_id: string; trip_id: string; ride_date: string }
  | { kind: 'university'; university_id: string };

/** The picker's state: every field kept, so switching kind and back loses nothing. */
export interface AudienceDraft {
  kind: AudienceKind;
  lineId: string;
  tripId: string;
  /** YYYY-MM-DD, a Cairo calendar day. */
  rideDate: string;
  universityId: string;
}

export type Priority = 'normal' | 'high';

export interface NotificationDraft {
  title: string;
  body: string;
  audience: AudienceDraft;
  priority: Priority;
  when: 'now' | 'later';
  /** `YYYY-MM-DDTHH:mm` as typed, read as Cairo wall time. */
  scheduledLocal: string;
}

export interface AudiencePreview { label: string; students: number; supervisors: number; devices: number; }

export type NotificationStatus = 'scheduled' | 'sent' | 'cancelled' | 'failed';
export type StatusFilter = 'all' | NotificationStatus;

export interface PushStats { devices: number; queued: number; accepted: number; failed: number; skipped: number; }

export interface HistoryRow {
  id: string;
  type: string | null;
  category: string | null;
  priority: Priority | null;
  title: string;
  body: string;
  created_at: string;
  scheduled_at: string | null;
  sent_at: string | null;
  status: NotificationStatus;
  status_note: string | null;
  sender_role: 'admin' | 'supervisor' | 'system';
  sender_name: string | null;
  audience: string | null;
  audience_spec: AudienceSpec | null;
  line_id: string | null;
  students: number;
  read: number;
  opened: number;
  push: PushStats | null;
}

export interface HistoryPage { items: HistoryRow[]; next_before: string | null; push_configured: boolean | null; }

export interface ComposeResult { id: string; status: 'sent' | 'scheduled'; students: number; duplicate: boolean; }

// -------------------------------------------------------------- audience ----

export const emptyAudience = (today: string): AudienceDraft =>
  ({ kind: 'company', lineId: '', tripId: '', rideDate: today, universityId: '' });

export const emptyDraft = (today: string): NotificationDraft =>
  ({ title: '', body: '', audience: emptyAudience(today), priority: 'normal', when: 'now', scheduledLocal: '' });

/** The payload for the server, or null while the choice is incomplete. */
export function audienceToPayload(audience: AudienceDraft): AudienceSpec | null {
  switch (audience.kind) {
    case 'company':
      return { kind: 'company' };
    case 'line':
      return audience.lineId ? { kind: 'line', line_id: audience.lineId } : null;
    case 'trip':
      return audience.lineId && audience.tripId && isDay(audience.rideDate)
        ? { kind: 'trip', line_id: audience.lineId, trip_id: audience.tripId, ride_date: audience.rideDate }
        : null;
    case 'university':
      return audience.universityId ? { kind: 'university', university_id: audience.universityId } : null;
    default:
      return null;
  }
}

/** A stored audience back into the picker (editing a scheduled notification). */
export function audienceFromSpec(spec: AudienceSpec | null | undefined, today: string): AudienceDraft {
  const base = emptyAudience(today);
  switch (spec?.kind) {
    case 'line':
      return { ...base, kind: 'line', lineId: spec.line_id };
    case 'trip':
      return { ...base, kind: 'trip', lineId: spec.line_id, tripId: spec.trip_id, rideDate: spec.ride_date || today };
    case 'university':
      return { ...base, kind: 'university', universityId: spec.university_id };
    default:
      return base;
  }
}

/** One stable string per audience: the cache key of its preview. */
export const audienceKey = (spec: AudienceSpec | null) => (spec ? JSON.stringify(spec) : '');

export const AUDIENCE_KINDS: { key: AudienceKind; label: string }[] = [
  { key: 'company', label: 'كل طلاب الشركة' },
  { key: 'line', label: 'طلاب خط' },
  { key: 'trip', label: 'ركاب رحلة' },
  { key: 'university', label: 'طلاب جامعة' },
];

/** What is still missing from the audience, in the admin's words ('' = complete). */
export function audienceProblem(audience: AudienceDraft): string {
  if (audience.kind === 'line' && !audience.lineId) return 'اختر الخط.';
  if (audience.kind === 'trip' && !audience.lineId) return 'اختر الخط ثم الرحلة.';
  if (audience.kind === 'trip' && !audience.tripId) return 'اختر الرحلة.';
  if (audience.kind === 'university' && !audience.universityId) return 'اختر الجامعة.';
  return '';
}

// ------------------------------------------------------------------ draft ----

export const isDirty = (draft: NotificationDraft) => draft.title.trim() !== '' || draft.body.trim() !== '';

/** Why the draft cannot be submitted yet ('' = it can). The server checks again. */
export function draftProblem(draft: NotificationDraft, now: Date = new Date()): string {
  if (!draft.title.trim() || !draft.body.trim()) return 'اكتب عنوان الإشعار ونصه.';
  if (draft.title.trim().length > TITLE_MAX) return `العنوان أطول من ${TITLE_MAX} حرفاً.`;
  if (draft.body.trim().length > BODY_MAX) return `نص الإشعار أطول من ${BODY_MAX} حرفاً.`;
  const audience = audienceProblem(draft.audience);
  if (audience) return audience;
  return draft.when === 'later' ? scheduleProblem(draft.scheduledLocal, now) : '';
}

// -------------------------------------------------------- idempotency key ----

export function newIdempotencyKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * The key of the submission being prepared. It appears when the form becomes
 * dirty, stays the same through double clicks and retries, and is dropped when
 * the form is clean again (after a success the form is reset, so the next
 * notification gets a new key).
 */
export function idempotencyKeyFor(current: string | null, dirty: boolean, generate: () => string = newIdempotencyKey): string | null {
  if (!dirty) return null;
  return current ?? generate();
}

// ----------------------------------------------------------------- labels ----

export const STATUS_FILTERS: { key: StatusFilter; label: string }[] = [
  { key: 'all', label: 'الكل' },
  { key: 'sent', label: 'المُرسلة' },
  { key: 'scheduled', label: 'المجدولة' },
  { key: 'cancelled', label: 'الملغاة' },
  { key: 'failed', label: 'الفاشلة' },
];

const STATUS: Record<NotificationStatus, { label: string; className: string }> = {
  sent: { label: 'أُرسل', className: 'bg-emerald-50 text-emerald-700' },
  scheduled: { label: 'مجدول', className: 'bg-amber-50 text-amber-700' },
  cancelled: { label: 'أُلغي', className: 'bg-slate-100 text-slate-500' },
  failed: { label: 'فشل الإرسال', className: 'bg-rose-50 text-rose-700' },
};

export const statusLabel = (status: string) => STATUS[status as NotificationStatus]?.label ?? status;
export const statusClass = (status: string) => STATUS[status as NotificationStatus]?.className ?? 'bg-slate-100 text-slate-500';

const CATEGORY: Record<string, string> = {
  subscription: 'الاشتراك',
  transport: 'الرحلات',
  announcement: 'إعلان',
  reminder: 'تذكير',
};

const TYPE: Record<string, string> = {
  'subscription.payment_received': 'استلام إيصال الدفع',
  'subscription.approved': 'قبول الاشتراك',
  'subscription.rejected': 'رفض الاشتراك',
  'subscription.expiring': 'اقتراب انتهاء الاشتراك',
  'subscription.expired': 'انتهاء الاشتراك',
  'transport.delay': 'تأخير رحلة',
  'transport.arrived': 'وصول الباص',
  'transport.departed': 'انطلاق الرحلة',
  'transport.cancelled': 'إلغاء رحلة',
  'transport.return_departing': 'العودة من الجامعة',
  'announcement.admin': 'إعلان من الإدارة',
  'announcement.supervisor': 'إعلان من المشرف',
};

/** The chip of a row. An unknown type falls back to its category, then to a plain word. */
export function typeLabel(type: string | null | undefined, category?: string | null): string {
  if (type && TYPE[type]) return TYPE[type];
  const fromCategory = CATEGORY[category || (type ? type.split('.')[0] : '')];
  return fromCategory ?? 'إشعار';
}

export function senderLabel(role: string | null | undefined, name?: string | null): string {
  if (role === 'system') return 'النظام';
  if (role === 'supervisor') return name ? `المشرف ${name}` : 'مشرف';
  return name ? `الإدارة · ${name}` : 'الإدارة';
}

/**
 * The push numbers of a row, worded as what is actually known. The provider
 * accepting a message is not the phone showing it, so nothing here says so.
 */
export function pushStatParts(push: PushStats | null | undefined): { key: keyof PushStats; label: string; value: number }[] {
  const stats = push ?? { devices: 0, queued: 0, accepted: 0, failed: 0, skipped: 0 };
  return [
    { key: 'devices', label: 'أجهزة مسجّلة', value: stats.devices ?? 0 },
    { key: 'queued', label: 'في الانتظار', value: stats.queued ?? 0 },
    { key: 'accepted', label: 'قبِلها مزوّد الإشعارات', value: stats.accepted ?? 0 },
    { key: 'failed', label: 'فشلت', value: stats.failed ?? 0 },
    { key: 'skipped', label: 'لم تُرسل (بلا جهاز أو أوقفها الطالب)', value: stats.skipped ?? 0 },
  ];
}

export const percent = (part: number, whole: number) => (whole > 0 ? Math.min(100, Math.round((part / whole) * 100)) : 0);

/** `07:30:00` → `7:30 ص`. */
export function clockLabel(time: string | null | undefined): string {
  if (!time) return '';
  const [h, m] = time.slice(0, 5).split(':').map(Number);
  if (Number.isNaN(h) || Number.isNaN(m)) return '';
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'ص' : 'م'}`;
}

export function tripLabel(trip: { direction: 'departure' | 'return'; label?: string | null; start_time: string }): string {
  const direction = trip.direction === 'departure' ? 'ذهاب' : 'عودة من الجامعة';
  return [direction, clockLabel(trip.start_time), trip.label?.trim()].filter(Boolean).join(' · ');
}

// ------------------------------------------------------------- Cairo time ----

const isDay = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value);

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

/** Why this send time cannot be used ('' = it can). */
export function scheduleProblem(local: string, now: Date = new Date()): string {
  const iso = local ? cairoLocalToIso(local) : null;
  if (!iso) return 'حدد موعد الإرسال.';
  if (new Date(iso).getTime() <= now.getTime()) return `موعد الإرسال يجب أن يكون في المستقبل (${CAIRO_LABEL}).`;
  return '';
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

/** A ride day in words: اليوم / غداً, or the date itself. */
export function rideDayLabel(day: string, today: string): string {
  if (day === today) return 'اليوم';
  if (day === addDays(today, 1)) return 'غداً';
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12)).toLocaleDateString('ar-EG', { timeZone: 'UTC', weekday: 'long', day: 'numeric', month: 'long' });
}

// ------------------------------------------------------- optimistic edits ----

/** The list without one notification (deleted, or cancelled under a filter that no longer shows it). */
export const withoutRow = (items: HistoryRow[], id: string) => items.filter((row) => row.id !== id);

/** A cancelled notification as each filter shows it: gone from «scheduled», marked elsewhere. */
export function withCancelled(items: HistoryRow[], id: string, filter: StatusFilter): HistoryRow[] {
  if (filter === 'scheduled') return withoutRow(items, id);
  return items.map((row) => (row.id === id ? { ...row, status: 'cancelled' as const } : row));
}
