/**
 * «عروض باصك» of the platform admin: merchants and the offers shown to the
 * students they are meant for (supabase/migrations/20261123000001_offers.sql).
 * One request reads both pages, `platform_offers_overview`; every write goes
 * through its own function, and the server's refusals are written for the admin.
 *
 * A picture is one file in the public "offer-assets" bucket,
 *   merchants/<merchant id>/<file>   offers/<offer id>/<file>
 * and the database stores that path, never a URL. A new picture is a new file:
 * the one it replaces is removed only after the row that names it was saved.
 */
import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import { keys, STALE, unwrap, usePageData, VARIANT_GC } from './query';
import { rpcOr } from './rpc';
import { cairoLocalToIso, isoToCairoLocal } from './time';
import { GENERAL_COLLEGES } from './colleges';
import type { SheetSpec } from './excel';
import { cairo, countText, dayText, num, NOUN } from '../ui/format';
import type { Tone } from '../ui/Status';

// ── What the server answers ──────────────────────────────────────────
export type MerchantCategory = 'food' | 'study' | 'services' | 'health' | 'shopping' | 'other';
export type OfferKind = 'percent' | 'amount' | 'gift' | 'info';
export type OfferStatus = 'draft' | 'live' | 'paused' | 'ended';

/** Who an offer is for. Every key is optional and all of them must hold. */
export interface AudienceSpec {
  university_ids?: string[]; colleges?: string[]; specialisations?: string[];
  company_ids?: string[]; line_ids?: string[]; governorates?: string[];
  /** Absent = 'active': only students with a running subscription. */
  subscription?: 'active' | 'any';
  min_rides?: number; min_attendance?: number; window_days?: number;
}

export interface Merchant {
  id: string; name: string; category: MerchantCategory; logo_path: string | null; phone: string | null; whatsapp: string | null;
  link_url: string | null; address: string | null; university_id: string | null; notes: string | null; is_active: boolean; offers: number;
}

export interface Offer {
  id: string; merchant_id: string; merchant_name: string; title: string; description: string; terms: string; image_path: string | null;
  kind: OfferKind; value_label: string; starts_at: string; ends_at: string | null; status: OfferStatus;
  /** Students can see it right now: live, inside its dates, its merchant active. */
  running: boolean;
  audience: AudienceSpec; special: boolean; per_student_limit: number; total_limit: number | null; coupon_minutes: number;
  has_pin: boolean; sort: number; price: number | null; internal_note: string | null; published_at: string | null;
  seen: number; opened: number; redeemed: number;
}

export interface OffersOverview { merchants: Merchant[]; offers: Offer[] }

export interface StatsGroup { name: string; seen: number; redeemed: number }
export interface OfferStats {
  reach: number; seen: number; opened: number; coupons: number; redeemed: number; students_redeemed: number;
  by_university: StatsGroup[]; by_college: StatsGroup[]; by_day: { day: string; redeemed: number }[];
}

// ── Words ────────────────────────────────────────────────────────────
export const MERCHANT_CATEGORIES: { value: MerchantCategory; label: string }[] = [
  { value: 'food', label: 'مطاعم وكافيهات' }, { value: 'study', label: 'أدوات دراسية' }, { value: 'services', label: 'خدمات' },
  { value: 'health', label: 'صحة' }, { value: 'shopping', label: 'تسوّق' }, { value: 'other', label: 'أخرى' },
];
export const categoryLabel = (c: string | null | undefined) => MERCHANT_CATEGORIES.find((x) => x.value === c)?.label ?? 'أخرى';

export const OFFER_KINDS: { value: OfferKind; label: string; sub: string; example: string }[] = [
  { value: 'percent', label: 'خصم بنسبة', sub: 'كوبون', example: '20%' },
  { value: 'amount', label: 'خصم بمبلغ', sub: 'كوبون', example: '50 ج.م' },
  { value: 'gift', label: 'هدية', sub: 'كوبون', example: 'مشروب مجاني' },
  { value: 'info', label: 'إعلان', sub: 'بلا كوبون', example: '' },
];
export const kindLabel = (k: string | null | undefined) => OFFER_KINDS.find((x) => x.value === k)?.label ?? '';

/** The folded group's name in the numbers of an offer. */
export const FOLDED = 'أخرى';
/** A university or college fewer than this many students saw is folded into «أخرى». */
export const FOLD_UNDER = 5;

// ── An offer's state ─────────────────────────────────────────────────
export type OfferStateKey = OfferStatus | 'expired' | 'upcoming' | 'merchantOff';
export interface OfferState { key: OfferStateKey; label: string; tone: Tone }

const STATES: Record<OfferStateKey, [string, Tone]> = {
  draft: ['مسودة', 'neutral'], live: ['منشور', 'success'], paused: ['موقوف', 'warning'], ended: ['منتهٍ', 'neutral'],
  expired: ['انتهت مدته', 'danger'], upcoming: ['لم يبدأ بعد', 'teal'], merchantOff: ['التاجر موقوف', 'warning'],
};
export const stateOf = (key: OfferStateKey): OfferState => ({ key, label: STATES[key][0], tone: STATES[key][1] });

/**
 * What the list says about an offer. A published offer students cannot see says
 * why: its start has not come, its merchant is stopped, or («انتهت مدته») its end
 * has passed.
 */
export function offerState(
  o: Pick<Offer, 'status' | 'running' | 'starts_at'>, merchantActive: boolean | undefined = undefined, now: number = Date.now(),
): OfferState {
  if (o.status !== 'live' || o.running) return stateOf(o.status);
  if (new Date(o.starts_at).getTime() > now) return stateOf('upcoming');
  if (merchantActive === false) return stateOf('merchantOff');
  return stateOf('expired');
}

/** What can be done to an offer from where it is. */
export function offerActions(status: OfferStatus): { publish: boolean; pause: boolean; end: boolean } {
  return { publish: status !== 'live', pause: status === 'live', end: status === 'live' || status === 'paused' };
}

/** «من 10 أكتوبر 2026 · 7:30 م حتى 31 أكتوبر 2026 · 11:59 م», or «… · بلا نهاية». */
export function periodText(startsAt: string | null | undefined, endsAt: string | null | undefined): string {
  if (!startsAt) return '';
  const a = cairo(startsAt);
  if (!endsAt) return `من ${dayText(a.day)} · بلا نهاية`;
  const b = cairo(endsAt);
  return `${dayText(a.day, { year: a.day.slice(0, 4) !== b.day.slice(0, 4) })} – ${dayText(b.day)}`;
}

// ── Numbers ──────────────────────────────────────────────────────────
/** `part` of `whole` as a whole percentage; null when there is nothing to divide by. */
export function rate(part: number, whole: number): number | null {
  if (!(whole > 0) || !(part >= 0)) return null;
  return Math.round((part / whole) * 100);
}
export const rateText = (part: number, whole: number): string => { const r = rate(part, whole); return r === null ? '—' : `${num(r)}%`; };

/** «يصل إلى 1,240 طالباً الآن». */
export function reachText(students: number | null | undefined): string {
  if (students == null) return '';
  return students === 0 ? 'لا يصل إلى أي طالب الآن' : `يصل إلى ${countText(students, NOUN.student)} الآن`;
}

/** The rates the details view shows, each of the step before it. */
export function statsRates(s: Pick<OfferStats, 'reach' | 'seen' | 'opened' | 'students_redeemed'>) {
  return {
    seen: rate(s.seen, s.reach), opened: rate(s.opened, s.seen), redeemed: rate(s.students_redeemed, s.seen),
  };
}

// ── Audience ─────────────────────────────────────────────────────────
/** «ملتزم»: rode on 8 days and was on the bus 80% of the days they said they would, in the last 30. */
export const COMMITTED = { min_rides: 8, min_attendance: 80, window_days: 30 } as const;
export const WINDOW_DEFAULT = 30;
const WINDOW = { min: 7, max: 120 } as const;
const MAX_LIST = 200;

/** The audience as the form holds it: every list present, the numbers as typed. */
export interface AudienceDraft {
  universityIds: string[]; colleges: string[]; specialisations: string[]; companyIds: string[]; lineIds: string[]; governorates: string[];
  subscription: 'active' | 'any'; minRides: number | ''; minAttendance: number | ''; windowDays: number | '';
}
export const emptyAudience = (): AudienceDraft => ({
  universityIds: [], colleges: [], specialisations: [], companyIds: [], lineIds: [], governorates: [],
  subscription: 'active', minRides: '', minAttendance: '', windowDays: WINDOW_DEFAULT,
});

export function audienceDraftOf(spec: AudienceSpec | null | undefined): AudienceDraft {
  const s = spec ?? {};
  return {
    universityIds: [...(s.university_ids ?? [])], colleges: [...(s.colleges ?? [])], specialisations: [...(s.specialisations ?? [])],
    companyIds: [...(s.company_ids ?? [])], lineIds: [...(s.line_ids ?? [])], governorates: [...(s.governorates ?? [])],
    subscription: s.subscription === 'any' ? 'any' : 'active',
    minRides: s.min_rides ?? '', minAttendance: s.min_attendance ?? '', windowDays: s.window_days ?? WINDOW_DEFAULT,
  };
}

const tidy = (list: readonly string[]) => [...new Set(list.map((x) => x.trim()).filter(Boolean))].sort();

/**
 * The spec as the server stores it (offer_audience_clean): empty lists and zeros
 * left out, each list without repeats and in one order, the window only when a
 * commitment is asked for. Two drafts that mean the same audience give the same spec.
 */
export function audienceSpecOf(d: AudienceDraft): AudienceSpec {
  const out: AudienceSpec = {};
  const put = (key: 'university_ids' | 'colleges' | 'specialisations' | 'company_ids' | 'line_ids' | 'governorates', list: string[]) => {
    const clean = tidy(list);
    if (clean.length) out[key] = clean;
  };
  put('university_ids', d.universityIds); put('colleges', d.colleges); put('specialisations', d.specialisations);
  put('company_ids', d.companyIds); put('line_ids', d.lineIds); put('governorates', d.governorates);
  if (d.subscription === 'any') out.subscription = 'any';
  if (d.minRides !== '' && d.minRides > 0) out.min_rides = d.minRides;
  if (d.minAttendance !== '' && d.minAttendance > 0) out.min_attendance = d.minAttendance;
  if (out.min_rides !== undefined || out.min_attendance !== undefined) out.window_days = d.windowDays === '' ? WINDOW_DEFAULT : d.windowDays;
  return out;
}

/** One text per audience: the key the live count is cached under. */
export const audienceKey = (spec: AudienceSpec): string => JSON.stringify(spec, Object.keys(spec).sort());

export interface AudienceProblems { lists?: string; minRides?: string; minAttendance?: string; windowDays?: string }
/** What the server would refuse, said next to the field (the same limits as offer_audience_clean). */
export function audienceProblems(d: AudienceDraft): AudienceProblems {
  const out: AudienceProblems = {};
  if ([d.universityIds, d.colleges, d.specialisations, d.companyIds, d.lineIds, d.governorates].some((l) => l.length > MAX_LIST)) out.lists = `كل قائمة ${num(MAX_LIST)} اختياراً على الأكثر.`;
  if (d.minRides !== '' && d.minRides > 200) out.minRides = 'عدد الرحلات المطلوب كبير جداً.';
  if (d.minAttendance !== '' && d.minAttendance > 100) out.minAttendance = 'نسبة الحضور من 0 إلى 100.';
  const asked = (d.minRides !== '' && d.minRides > 0) || (d.minAttendance !== '' && d.minAttendance > 0);
  if (asked && d.windowDays !== '' && (d.windowDays < WINDOW.min || d.windowDays > WINDOW.max)) out.windowDays = `مدة قياس الالتزام من ${WINDOW.min} إلى ${WINDOW.max} يوماً.`;
  return out;
}
export const hasProblems = (problems: object) => Object.values(problems).some(Boolean);

/** Whether the commitment asked for is exactly the «ملتزم» preset. */
export const isCommitted = (s: Pick<AudienceSpec, 'min_rides' | 'min_attendance' | 'window_days'>) =>
  s.min_rides === COMMITTED.min_rides && s.min_attendance === COMMITTED.min_attendance && (s.window_days ?? WINDOW_DEFAULT) === COMMITTED.window_days;

/** The lines that still belong to a chosen company (a company unticked takes its lines with it). */
export function keepLinesOf(lineIds: readonly string[], lines: readonly { id: string; company_id: string }[], companyIds: readonly string[]): string[] {
  const allowed = new Set(lines.filter((l) => companyIds.includes(l.company_id)).map((l) => l.id));
  return lineIds.filter((id) => allowed.has(id));
}

/**
 * The colleges to choose from, by name: those of the chosen universities (of
 * every university when none is chosen), then the general list, then anything
 * already chosen that is in neither. Each name once, as it is written.
 */
export function collegeOptions(colleges: readonly { university_id: string; name: string }[], universityIds: readonly string[], chosen: readonly string[] = []): string[] {
  const own = colleges.filter((c) => universityIds.length === 0 || universityIds.includes(c.university_id)).map((c) => c.name.trim()).filter(Boolean)
    .sort((a, b) => a.localeCompare(b, 'ar'));
  return [...new Set([...own, ...GENERAL_COLLEGES, ...chosen.map((c) => c.trim()).filter(Boolean)])];
}

/** Names for the ids of a spec; an id without a name is counted instead of shown. */
export interface AudienceNames {
  universities?: ReadonlyMap<string, string>; companies?: ReadonlyMap<string, string>;
  lines?: ReadonlyMap<string, string>; governorates?: ReadonlyMap<string, string>;
}
export const nameMap = <T,>(rows: readonly T[] | null | undefined, id: (row: T) => string, name: (row: T) => string): Map<string, string> =>
  new Map((rows ?? []).map((row) => [id(row), name(row)]));

const SHOWN = 2;
/** «الهندسة، الطب +3». */
function namesText(names: readonly string[]): string {
  const shown = names.slice(0, SHOWN).join('، ');
  return names.length > SHOWN ? `${shown} +${num(names.length - SHOWN)}` : shown;
}
/** The names of the ids; ids nobody can name are counted instead («3 جامعات»). */
function idsText(ids: readonly string[], names: ReadonlyMap<string, string> | undefined, noun: [string, string, string, string]): string {
  const known = ids.map((id) => names?.get(id)).filter((name): name is string => !!name);
  return known.length < ids.length ? countText(ids.length, noun) : namesText(known);
}

const UNIVERSITY: [string, string, string, string] = ['جامعة واحدة', 'جامعتان', 'جامعات', 'جامعة'];
const GOVERNORATE: [string, string, string, string] = ['محافظة واحدة', 'محافظتان', 'محافظات', 'محافظة'];
const ONE_COMPANY: [string, string, string, string] = ['شركة واحدة', NOUN.company[1], NOUN.company[2], NOUN.company[3]];
const ONE_LINE: [string, string, string, string] = ['خط واحد', NOUN.line[1], NOUN.line[2], NOUN.line[3]];

/**
 * The audience in one line, as the admin would say it:
 * «طلاب الهندسة · جامعة الدلتا · ملتزمون». Nothing chosen is «كل المشتركين حالياً».
 */
export function audienceSummary(spec: AudienceSpec | null | undefined, names: AudienceNames = {}): string {
  const s = spec ?? {};
  const any = s.subscription === 'any';
  const parts: string[] = [];
  const colleges = (s.colleges ?? []).map((c) => c.replace(/^كلية\s+/, ''));
  parts.push(colleges.length ? `طلاب ${namesText(colleges)}` : any ? 'كل الطلاب' : 'كل المشتركين حالياً');
  if (s.specialisations?.length) parts.push(`تخصص ${namesText(s.specialisations)}`);
  if (s.university_ids?.length) parts.push(idsText(s.university_ids, names.universities, UNIVERSITY));
  if (s.company_ids?.length) parts.push(idsText(s.company_ids, names.companies, ONE_COMPANY));
  if (s.line_ids?.length) parts.push(idsText(s.line_ids, names.lines, ONE_LINE));
  if (s.governorates?.length) parts.push(idsText(s.governorates, names.governorates, GOVERNORATE));
  if (colleges.length && any) parts.push('مشتركون وغير مشتركين');
  if (s.min_rides || s.min_attendance) {
    if (isCommitted(s)) parts.push('ملتزمون');
    else {
      const asked = [s.min_rides ? `${countText(s.min_rides, NOUN.day)} ركوب على الأقل` : '', s.min_attendance ? `حضور ${num(s.min_attendance)}% على الأقل` : ''].filter(Boolean).join(' و');
      parts.push(`${asked} في آخر ${countText(s.window_days ?? WINDOW_DEFAULT, NOUN.day)}`);
    }
  }
  return parts.join(' · ');
}

// ── Pictures ─────────────────────────────────────────────────────────
export const OFFER_BUCKET = 'offer-assets';
export type PictureFolder = 'merchants' | 'offers';
/** SVG is refused on purpose: the bucket is public, and an SVG can carry script. */
export const PICTURE_SOURCE_TYPES = ['image/png', 'image/jpeg', 'image/webp'] as const;
/** The chosen file is re-encoded before it is stored, so it may be larger than what the bucket takes. */
export const PICTURE_SOURCE_MAX_BYTES = 12 * 1024 * 1024;
/** What the bucket takes. */
export const PICTURE_STORED_MAX_BYTES = 3 * 1024 * 1024;
/** The stored picture's longer side. */
export const PICTURE_EDGE: Record<PictureFolder, number> = { merchants: 512, offers: 1600 };
const PICTURE_MIN: Record<PictureFolder, number> = { merchants: 96, offers: 320 };

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const PICTURE_PATH = new RegExp(`^(offers|merchants)/(${UUID})/[A-Za-z0-9_.-]{1,80}\\.(png|jpg|jpeg|webp)$`);

const projectUrl = (): string => String(import.meta.env?.VITE_SUPABASE_URL || 'https://your-project.supabase.co').replace(/\/+$/, '');

/**
 * Whether `path` is a picture as the database stores it; with `folder` and `id`,
 * whether it is that merchant's or that offer's. A URL or a path that climbs out
 * of its folder is never one.
 */
export function isPicturePath(path: unknown, folder?: PictureFolder, id?: string): path is string {
  if (typeof path !== 'string' || path.includes('..')) return false;
  const match = PICTURE_PATH.exec(path);
  return !!match && (!folder || match[1] === folder) && (!id || match[2] === id.toLowerCase());
}

/** A new file for an upload: "<folder>/<id>/<stamp>.<ext>", different every time. */
export function newPicturePath(folder: PictureFolder, id: string, ext: 'webp' | 'jpg', now: number = Date.now(), random: number = Math.random()): string {
  return `${folder}/${id.toLowerCase()}/${now.toString(36)}${Math.floor(random * 36 ** 4).toString(36).padStart(4, '0')}.${ext}`;
}

/** The public address of a stored picture, or null when the path is not one (nothing is built from an unexpected string). */
export function pictureUrl(path: string | null | undefined, base: string = projectUrl()): string | null {
  return isPicturePath(path) ? `${base.replace(/\/+$/, '')}/storage/v1/object/public/${OFFER_BUCKET}/${path}` : null;
}

/** The reason a chosen file cannot be used, or null. Checked before anything is read or uploaded. */
export function checkPictureFile(file: { type: string; size: number }): string | null {
  if (file.type === 'image/svg+xml') return 'ملفات SVG غير مقبولة. احفظ الصورة بصيغة PNG أو JPG ثم ارفعها.';
  if (!(PICTURE_SOURCE_TYPES as readonly string[]).includes(file.type)) return 'اختر صورة بصيغة PNG أو JPG أو WebP.';
  if (file.size <= 0) return 'الملف فارغ.';
  if (file.size > PICTURE_SOURCE_MAX_BYTES) return 'حجم الصورة يجب ألا يزيد عن 12 ميجابايت.';
  return null;
}

/** The reason a picture of this size cannot be used, or null. */
export function checkPictureDimensions(folder: PictureFolder, width: number, height: number): string | null {
  if (!(width > 0 && height > 0)) return 'تعذر قراءة الصورة.';
  const min = PICTURE_MIN[folder];
  if (Math.max(width, height) < min) return `الصورة صغيرة جداً (${width}×${height}). استخدم صورة لا يقل طولها عن ${min} بكسل.`;
  return null;
}

/** The size a picture is stored at: its own shape, only ever made smaller. */
export function storedPictureSize(folder: PictureFolder, width: number, height: number): { width: number; height: number } {
  const scale = Math.min(1, PICTURE_EDGE[folder] / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/** undefined = keep what is saved, null = remove it, a file = replace it. */
export type PictureChange = File | null | undefined;

// ── A merchant in the form ───────────────────────────────────────────
export interface MerchantDraft {
  id: string; isNew: boolean; name: string; category: MerchantCategory; phone: string; whatsapp: string; linkUrl: string;
  address: string; universityId: string; notes: string; isActive: boolean; logoPath: string | null;
}

export const emptyMerchant = (id: string): MerchantDraft => ({
  id, isNew: true, name: '', category: 'food', phone: '', whatsapp: '', linkUrl: '', address: '', universityId: '', notes: '', isActive: true, logoPath: null,
});
export const merchantDraftOf = (m: Merchant): MerchantDraft => ({
  id: m.id, isNew: false, name: m.name, category: m.category, phone: m.phone ?? '', whatsapp: m.whatsapp ?? '', linkUrl: m.link_url ?? '',
  address: m.address ?? '', universityId: m.university_id ?? '', notes: m.notes ?? '', isActive: m.is_active, logoPath: m.logo_path,
});

/** Arabic-Indic digits to Latin ones, spaces and dashes out: a number as it is dialled. */
export const phoneDigits = (value: string): string => value
  .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
  .replace(/[\s\-()]/g, '');
const PHONE = /^\+?\d{7,15}$/;
const LINK = /^https:\/\/\S{3,300}$/i;

export const NAME_MAX = 80;
export interface MerchantProblems { name?: string; phone?: string; whatsapp?: string; linkUrl?: string }
export function merchantProblems(d: MerchantDraft): MerchantProblems {
  const out: MerchantProblems = {};
  const name = d.name.trim();
  if (!name) out.name = 'اكتب اسم التاجر.';
  else if (name.length > NAME_MAX) out.name = `الاسم ${NAME_MAX} حرفاً على الأكثر.`;
  if (d.phone.trim() && !PHONE.test(phoneDigits(d.phone))) out.phone = 'اكتب رقم الهاتف بالأرقام فقط.';
  if (d.whatsapp.trim() && !PHONE.test(phoneDigits(d.whatsapp))) out.whatsapp = 'اكتب رقم واتساب بالأرقام فقط.';
  if (d.linkUrl.trim() && !LINK.test(d.linkUrl.trim())) out.linkUrl = 'الرابط يجب أن يبدأ بـ https://';
  return out;
}

/** What `platform_save_merchant` takes. `logoPath` is the picture to store (after any upload). */
export function merchantPayload(d: MerchantDraft, logoPath: string | null = d.logoPath) {
  return {
    id: d.id, name: d.name.trim().replace(/\s+/g, ' '), category: d.category, logo_path: logoPath ?? '',
    phone: d.phone.trim() ? phoneDigits(d.phone) : '', whatsapp: d.whatsapp.trim() ? phoneDigits(d.whatsapp) : '',
    link_url: d.linkUrl.trim(), address: d.address.trim(), university_id: d.universityId, notes: d.notes.trim(), is_active: d.isActive,
  };
}

// ── An offer in the form ─────────────────────────────────────────────
export const TEXT_MAX = 600;
export const VALUE_MAX = 24;
export const LIMITS = { perStudent: { min: 1, max: 100 }, coupon: { min: 2, max: 60 }, sort: { min: -9999, max: 9999 } } as const;

export interface OfferDraft {
  id: string; isNew: boolean; merchantId: string; title: string; description: string; terms: string; kind: OfferKind; valueLabel: string;
  /** Cairo wall time, `YYYY-MM-DDTHH:mm`; an empty end = no end. */
  startsLocal: string; endsLocal: string;
  perStudentLimit: number | ''; totalLimit: number | ''; couponMinutes: number | '';
  /** A new PIN to set; '' keeps what is saved unless `removePin`. The saved one is never read back. */
  pin: string; removePin: boolean; hasPin: boolean;
  special: boolean; sort: number | ''; price: string; internalNote: string; audience: AudienceDraft; imagePath: string | null;
}

export const emptyOffer = (id: string, now: Date = new Date()): OfferDraft => ({
  id, isNew: true, merchantId: '', title: '', description: '', terms: '', kind: 'percent', valueLabel: '',
  startsLocal: isoToCairoLocal(now), endsLocal: '', perStudentLimit: 1, totalLimit: '', couponMinutes: 10,
  pin: '', removePin: false, hasPin: false, special: false, sort: 0, price: '', internalNote: '', audience: emptyAudience(), imagePath: null,
});
export const offerDraftOf = (o: Offer): OfferDraft => ({
  id: o.id, isNew: false, merchantId: o.merchant_id, title: o.title, description: o.description ?? '', terms: o.terms ?? '', kind: o.kind,
  valueLabel: o.value_label ?? '', startsLocal: isoToCairoLocal(o.starts_at), endsLocal: o.ends_at ? isoToCairoLocal(o.ends_at) : '',
  perStudentLimit: o.per_student_limit, totalLimit: o.total_limit ?? '', couponMinutes: o.coupon_minutes,
  pin: '', removePin: false, hasPin: o.has_pin, special: o.special, sort: o.sort, price: o.price == null ? '' : String(o.price),
  internalNote: o.internal_note ?? '', audience: audienceDraftOf(o.audience), imagePath: o.image_path,
});

const PIN = /^\d{4,6}$/;
const PRICE = /^\d{1,8}(\.\d{1,2})?$/;
const between = (v: number | '', min: number, max: number) => v !== '' && Number.isInteger(v) && v >= min && v <= max;

export interface OfferProblems {
  merchantId?: string; title?: string; description?: string; terms?: string; valueLabel?: string; starts?: string; ends?: string;
  perStudentLimit?: string; totalLimit?: string; couponMinutes?: string; pin?: string; sort?: string; price?: string; audience?: AudienceProblems;
}
/** Why the offer cannot be saved, field by field (the same rules the server keeps). */
export function offerProblems(d: OfferDraft): OfferProblems {
  const out: OfferProblems = {};
  const coupon = d.kind !== 'info';
  if (!d.merchantId) out.merchantId = 'اختر التاجر.';
  const title = d.title.trim();
  if (!title) out.title = 'اكتب عنوان العرض.';
  else if (title.length > NAME_MAX) out.title = `العنوان ${NAME_MAX} حرفاً على الأكثر.`;
  if (d.description.trim().length > TEXT_MAX) out.description = `الوصف ${num(TEXT_MAX)} حرف على الأكثر.`;
  if (d.terms.trim().length > TEXT_MAX) out.terms = `الشروط ${num(TEXT_MAX)} حرف على الأكثر.`;
  if (d.valueLabel.trim().length > VALUE_MAX) out.valueLabel = `القيمة ${VALUE_MAX} حرفاً على الأكثر.`;
  const starts = cairoLocalToIso(d.startsLocal);
  if (!starts) out.starts = 'اختر يوم البداية وساعتها.';
  if (d.endsLocal) {
    const ends = cairoLocalToIso(d.endsLocal);
    if (!ends) out.ends = 'اختر يوم النهاية وساعتها، أو اتركه بلا نهاية.';
    else if (starts && new Date(ends).getTime() <= new Date(starts).getTime()) out.ends = 'النهاية يجب أن تكون بعد البداية.';
  }
  if (coupon) {
    if (!between(d.perStudentLimit, LIMITS.perStudent.min, LIMITS.perStudent.max)) out.perStudentLimit = `من ${LIMITS.perStudent.min} إلى ${LIMITS.perStudent.max} مرة.`;
    if (d.totalLimit !== '' && !(Number.isInteger(d.totalLimit) && d.totalLimit >= 1)) out.totalLimit = 'مرة واحدة على الأقل، أو اتركه فارغاً.';
    if (!between(d.couponMinutes, LIMITS.coupon.min, LIMITS.coupon.max)) out.couponMinutes = `من ${LIMITS.coupon.min} إلى ${LIMITS.coupon.max} دقيقة.`;
    if (d.pin && !d.removePin && !PIN.test(d.pin)) out.pin = 'رمز التاجر من 4 إلى 6 أرقام.';
  }
  if (d.sort !== '' && !between(d.sort, LIMITS.sort.min, LIMITS.sort.max)) out.sort = 'رقم صحيح صغير.';
  if (d.price.trim() && !PRICE.test(d.price.trim())) out.price = 'اكتب المبلغ بالأرقام، مثل 1500 أو 1500.50.';
  const audience = audienceProblems(d.audience);
  if (hasProblems(audience)) out.audience = audience;
  return out;
}

/**
 * What `platform_save_offer` takes. "pin" is left out to keep the saved PIN, ""
 * removes it, digits set it; an advert has none. `imagePath` is the picture to
 * store (after any upload).
 */
export function offerPayload(d: OfferDraft, imagePath: string | null = d.imagePath) {
  const coupon = d.kind !== 'info';
  const payload: Record<string, unknown> = {
    id: d.id, merchant_id: d.merchantId, title: d.title.trim().replace(/\s+/g, ' '), description: d.description.trim(), terms: d.terms.trim(),
    image_path: imagePath ?? '', kind: d.kind, value_label: d.valueLabel.trim(),
    starts_at: cairoLocalToIso(d.startsLocal) ?? '', ends_at: (d.endsLocal && cairoLocalToIso(d.endsLocal)) || '',
    audience: audienceSpecOf(d.audience), special: d.special,
    per_student_limit: coupon && d.perStudentLimit !== '' ? d.perStudentLimit : 1,
    total_limit: coupon ? d.totalLimit : '',
    coupon_minutes: coupon && d.couponMinutes !== '' ? d.couponMinutes : 10,
    sort: d.sort === '' ? 0 : d.sort, price: d.price.trim(), internal_note: d.internalNote.trim(),
  };
  if (coupon && d.removePin) payload.pin = '';
  else if (coupon && d.pin) payload.pin = d.pin;
  return payload;
}

/**
 * When publishing a special offer tells its audience: 'now' when it has started,
 * 'atStart' when its start is still ahead (the server tells them then), 'no' for
 * an ordinary offer. Each offer is announced once; whether that already happened
 * is the server's to know.
 */
export function specialNotice(o: Pick<Offer, 'special' | 'starts_at'>, now: number = Date.now()): 'now' | 'atStart' | 'no' {
  if (!o.special) return 'no';
  return new Date(o.starts_at).getTime() <= now ? 'now' : 'atStart';
}

// ── Excel ────────────────────────────────────────────────────────────
/** One offer's numbers as a workbook: the totals, by university, by college, by day. */
export function statsSheets(offer: Pick<Offer, 'title' | 'merchant_name'>, s: OfferStats): SheetSpec[] {
  const rates = statsRates(s);
  const pct = (r: number | null) => (r === null ? null : r / 100);
  const totals: { label: string; value: number | string | null; share: number | null }[] = [
    { label: 'العرض', value: offer.title, share: null },
    { label: 'التاجر', value: offer.merchant_name, share: null },
    { label: 'يصل إليهم الآن', value: s.reach, share: null },
    { label: 'شاهدوه', value: s.seen, share: pct(rates.seen) },
    { label: 'فتحوه', value: s.opened, share: pct(rates.opened) },
    { label: 'كوبونات صدرت', value: s.coupons, share: null },
    { label: 'مرات الاستخدام', value: s.redeemed, share: null },
    { label: 'طلاب استخدموه', value: s.students_redeemed, share: pct(rates.redeemed) },
  ];
  const group = (sheet: string, label: string, rows: StatsGroup[]): SheetSpec<StatsGroup> => ({
    sheet, rows,
    columns: [
      { label, value: (r) => r.name, width: 34 },
      { label: 'شاهدوه', value: (r) => r.seen, format: '#,##0' },
      { label: 'مرات الاستخدام', value: (r) => r.redeemed, format: '#,##0', width: 16 },
    ],
  });
  return [
    { sheet: 'الأرقام', rows: totals, columns: [
      { label: 'البند', value: (r: typeof totals[number]) => r.label, width: 24 },
      { label: 'العدد', value: (r: typeof totals[number]) => r.value, format: '#,##0', width: 30 },
      { label: 'النسبة', value: (r: typeof totals[number]) => r.share, format: '0%' },
    ] },
    group('بالجامعة', 'الجامعة', s.by_university),
    group('بالكلية', 'الكلية', s.by_college),
    { sheet: 'باليوم', rows: s.by_day, columns: [
      { label: 'اليوم', value: (r: OfferStats['by_day'][number]) => r.day, width: 16 },
      { label: 'مرات الاستخدام', value: (r: OfferStats['by_day'][number]) => r.redeemed, format: '#,##0', width: 16 },
    ] },
  ];
}

// ── Reading and writing ─────────────────────────────────────────────
export const offersKey = keys.platform('offers');

/** Null when the database does not have the feature yet. */
export const loadOffersOverview = () => rpcOr<OffersOverview | null>('platform_offers_overview',
  () => supabase.rpc('platform_offers_overview'), async () => null);

export const useOffersOverview = () => usePageData(offersKey, loadOffersOverview);

export const saveMerchant = (payload: ReturnType<typeof merchantPayload>) =>
  unwrap<{ id: string }>(supabase.rpc('platform_save_merchant', { p_merchant: payload }));

/** `students`: who the saved audience reaches now. */
export const saveOffer = (payload: ReturnType<typeof offerPayload>) =>
  unwrap<{ id: string; students: number }>(supabase.rpc('platform_save_offer', { p_offer: payload }));

/** `notified`: how many students were told of a special offer by this very call. */
export const setOfferStatus = (id: string, status: OfferStatus) =>
  unwrap<{ status: OfferStatus; notified: number }>(supabase.rpc('platform_set_offer_status', { p_id: id, p_status: status }));

/** Refused by the server, in its own words, for a merchant that has offers. */
export async function deleteMerchant(id: string): Promise<void> {
  const { error } = await supabase.rpc('platform_delete_merchant', { p_id: id });
  if (error) throw new Error(error.message);
}

export async function deleteOffer(id: string): Promise<void> {
  const { error } = await supabase.rpc('platform_delete_offer', { p_id: id });
  if (error) throw new Error(error.message);
}

export const offerStatsKey = (id: string) => keys.platform('offers', 'stats', id);
export const useOfferStats = (id: string | null) => usePageData(offerStatsKey(id ?? ''),
  () => unwrap<OfferStats>(supabase.rpc('platform_offer_stats', { p_id: id })), { enabled: !!id, gcTime: VARIANT_GC });

function useDebounced<T>(value: T, delay: number): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const timer = window.setTimeout(() => setSettled(value), delay);
    return () => window.clearTimeout(timer);
  }, [value, delay]);
  return settled;
}

/**
 * Who an audience would reach today, counted by the server a moment after the
 * last change. The last count stays on screen while the next one is asked for;
 * `spec` null (a draft the server would refuse) asks for nothing.
 */
export function useAudienceReach(spec: AudienceSpec | null) {
  const wanted = spec ? audienceKey(spec) : '';
  const asked = useDebounced(wanted, 450);
  const query = usePageData(
    // Under 'preview': one answer per audience tried, not kept across reloads.
    keys.platform('preview', 'offer', asked),
    () => unwrap<{ students: number }>(supabase.rpc('platform_preview_offer_audience', { p_spec: JSON.parse(asked) })),
    { enabled: !!asked, gcTime: VARIANT_GC, keepPrevious: true },
  );
  return {
    students: query.data?.students ?? null,
    refreshing: !!wanted && (asked !== wanted || query.loading || query.refreshing),
    error: wanted && asked === wanted ? query.error : '',
  };
}

/** The lines of the chosen companies, for the audience's line list. */
export interface AudienceLine { id: string; name: string; company_id: string; is_active: boolean }
export function useAudienceLines(companyIds: readonly string[]) {
  const ids = [...companyIds].sort();
  return usePageData(keys.platform('offerLines', ids.join(',')),
    () => unwrap<AudienceLine[]>(supabase.from('lines').select('id, name, company_id, is_active').in('company_id', ids).order('name')),
    { enabled: ids.length > 0, staleTime: STALE.reference, gcTime: VARIANT_GC, keepPrevious: true });
}

// ── Pictures: the browser's part ─────────────────────────────────────
function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => { URL.revokeObjectURL(url); resolve(image); };
    image.onerror = () => { URL.revokeObjectURL(url); reject(new Error('تعذر قراءة الصورة. اختر ملف PNG أو JPG أو WebP.')); };
    image.src = url;
  });
}

/** The picture's own size, read without uploading anything. */
export async function pictureSize(file: File): Promise<{ width: number; height: number }> {
  const image = await loadImage(file);
  return { width: image.naturalWidth, height: image.naturalHeight };
}

const toBlob = (canvas: HTMLCanvasElement, type: string, quality: number) =>
  new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, type, quality));

/**
 * The one file that is stored: the picture at its stored size as WebP, or as
 * JPEG on a white ground where the browser cannot write WebP. Re-drawing it also
 * drops whatever else the original file carried.
 */
async function encodePicture(folder: PictureFolder, file: File): Promise<{ blob: Blob; ext: 'webp' | 'jpg' }> {
  const image = await loadImage(file);
  const size = storedPictureSize(folder, image.naturalWidth, image.naturalHeight);
  const draw = (ground?: string) => {
    const canvas = document.createElement('canvas');
    canvas.width = size.width; canvas.height = size.height;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('المتصفح لا يدعم معالجة الصور.');
    if (ground) { context.fillStyle = ground; context.fillRect(0, 0, size.width, size.height); }
    context.imageSmoothingQuality = 'high';
    context.drawImage(image, 0, 0, size.width, size.height);
    return canvas;
  };
  for (const quality of [0.86, 0.7]) {
    const webp = await toBlob(draw(), 'image/webp', quality);
    if (webp?.type === 'image/webp' && webp.size <= PICTURE_STORED_MAX_BYTES) return { blob: webp, ext: 'webp' };
    if (webp?.type !== 'image/webp') break;
  }
  for (const quality of [0.86, 0.7]) {
    const jpeg = await toBlob(draw('#FFFFFF'), 'image/jpeg', quality);
    if (jpeg && jpeg.size <= PICTURE_STORED_MAX_BYTES) return { blob: jpeg, ext: 'jpg' };
  }
  throw new Error('تعذر تجهيز الصورة بحجم مناسب. جرّب صورة أخرى.');
}

/** Uploads the picture as one new file and answers its path. */
export async function uploadPicture(folder: PictureFolder, id: string, file: File): Promise<string> {
  const { blob, ext } = await encodePicture(folder, file);
  const path = newPicturePath(folder, id, ext);
  const { error } = await supabase.storage.from(OFFER_BUCKET).upload(path, blob, { contentType: blob.type, cacheControl: '31536000' });
  if (error) throw new Error(`تعذر رفع الصورة: ${error.message}`);
  return path;
}

/** Removes pictures nothing shows any more. Best effort and never thrown. */
export async function removePictures(paths: readonly (string | null | undefined)[]): Promise<void> {
  const names = paths.filter((path): path is string => isPicturePath(path));
  if (names.length === 0) return;
  try { await supabase.storage.from(OFFER_BUCKET).remove(names); } catch { /* left for a later clean-up */ }
}

/**
 * Saves a row with its picture: uploads the chosen file first (under the row's
 * id), hands `write` the path to store, and afterwards removes the picture that
 * was replaced. If the row is refused, the file just uploaded is removed again.
 */
export async function saveWithPicture<T>(
  folder: PictureFolder, id: string, saved: string | null, change: PictureChange, write: (path: string | null) => Promise<T>,
): Promise<T> {
  const uploaded = change instanceof File ? await uploadPicture(folder, id, change) : null;
  const path = change === undefined ? saved : uploaded;
  try {
    const out = await write(path);
    if (saved && saved !== path) void removePictures([saved]);
    return out;
  } catch (error) {
    if (uploaded) void removePictures([uploaded]);
    throw error;
  }
}
