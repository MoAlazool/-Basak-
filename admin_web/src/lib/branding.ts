/**
 * A company's identity: its LOGO (the full mark, any shape: receipts, headers,
 * the Wallet card) and its EMBLEM (a square mark: avatars, list rows, the
 * notification sender).
 *
 * The database stores a folder for each, never a URL:
 *   logo_path    "<company id>/logo/<stamp>"     master.png (longer side at most 1024 px),
 *                                                google.png (660x660, centred on a transparent
 *                                                square) and the sizes Apple Wallet wants
 *   emblem_path  "<company id>/emblem/<stamp>"   master.png (512x512), small.png (128x128)
 * in the public "wallet-assets" bucket. Every upload is a new folder and a file
 * is never replaced in place, so an address always shows the same picture: a
 * new logo has a new address, and no cache can serve the old one for it.
 *
 * Nothing here talks to the network: these are the rules, and the one place an
 * address is built from a stored path.
 */

export const BRAND_BUCKET = 'wallet-assets';
export type BrandKind = 'logo' | 'emblem';
/** What every answer that names a company carries (absent from a database that does not know them yet). */
export interface CompanyBrand { logo_path?: string | null; emblem_path?: string | null }

const projectUrl = (): string => String(import.meta.env?.VITE_SUPABASE_URL || 'https://your-project.supabase.co').replace(/\/+$/, '');

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const FOLDER = new RegExp(`^(${UUID})/(logo|emblem|banner)/[A-Za-z0-9_-]{1,64}$`);
const FILE = /^[A-Za-z0-9@_-]{1,40}\.png$/;

/**
 * Whether `path` is an artwork folder as the database stores it; with `companyId`
 * and `kind`, whether it is that company's folder of that kind. A URL, a file
 * name or a path that climbs out of its folder is never one.
 */
export function isBrandPath(path: unknown, companyId?: string, kind?: BrandKind | 'banner'): path is string {
  if (typeof path !== 'string') return false;
  const match = FOLDER.exec(path);
  return !!match && (!companyId || match[1] === companyId.toLowerCase()) && (!kind || match[2] === kind);
}

/** A new folder for an upload: "<company id>/<kind>/<stamp>", different every time. */
export function newBrandFolder(companyId: string, kind: BrandKind | 'banner', now: number = Date.now(), random: number = Math.random()): string {
  return `${companyId}/${kind}/${now.toString(36)}${Math.floor(random * 36 ** 4).toString(36).padStart(4, '0')}`;
}

/**
 * The public address of one file of a stored folder, or null when the path is
 * not an artwork folder (nothing is ever built from an unexpected string).
 */
export function brandFileUrl(path: string | null | undefined, file: string, base: string = projectUrl()): string | null {
  if (!isBrandPath(path) || !FILE.test(file)) return null;
  return `${base.replace(/\/+$/, '')}/storage/v1/object/public/${BRAND_BUCKET}/${path}/${file}`;
}

/** The full logo, for a header or a receipt. */
export const logoUrl = (brand: CompanyBrand | null | undefined, base?: string): string | null =>
  brandFileUrl(brand?.logo_path, 'master.png', base);

/**
 * The square mark, for a box `displayPx` wide: the emblem (128 px file up to a
 * 64 px box, 512 px above), else the logo centred on a square, else null (the
 * caller shows the company's initial).
 */
export function emblemUrl(brand: CompanyBrand | null | undefined, displayPx = 40, base?: string): string | null {
  return brandFileUrl(brand?.emblem_path, displayPx <= 64 ? 'small.png' : 'master.png', base)
    ?? brandFileUrl(brand?.logo_path, 'google.png', base);
}

/** Words that say what a company is, not which one. */
const GENERIC = new Set(['شركة', 'شركه', 'مؤسسة', 'مؤسسه', 'مجموعة', 'company', 'co', 'co.', 'the']);

/**
 * What stands in for a missing mark: the letter that tells companies apart
 * ("شركة النورس" → "ن", not the article), or two initials for a Latin name.
 */
export function companyInitials(name: string | null | undefined): string {
  const words = (name ?? '').trim().split(/\s+/).filter(Boolean);
  const telling = words.filter((word) => !GENERIC.has(word.toLowerCase()));
  const chosen = telling.length > 0 ? telling : words;
  if (chosen.length === 0) return '؟';
  const first = chosen[0];
  if (/^[A-Za-z]/.test(first)) return chosen.slice(0, 2).map((word) => word[0]).join('').toUpperCase();
  const bare = first.startsWith('ال') && first.length > 3 ? first.slice(2) : first;
  return Array.from(bare)[0] ?? '؟';
}

// ── What may be uploaded ─────────────────────────────────────────────
/** SVG is refused on purpose: the bucket is public, and an SVG can carry script. */
export const BRAND_SOURCE_TYPES = ['image/png', 'image/jpeg', 'image/webp'] as const;
export const BRAND_SOURCE_MAX_BYTES = 5 * 1024 * 1024;
/** The stored sizes: the logo's longer side, the emblem's square. */
export const BRAND_STORED = { logo: 1024, emblem: 512 } as const;
/** Below this the picture is too small to look right anywhere. */
const BRAND_MIN = { logo: 120, emblem: 128 } as const;

/** The reason a chosen file cannot be used, or null. Checked before anything is read or uploaded. */
export function checkBrandFile(file: { type: string; size: number }): string | null {
  if (file.type === 'image/svg+xml') return 'ملفات SVG غير مقبولة. احفظ الشعار بصيغة PNG ثم ارفعه.';
  if (!(BRAND_SOURCE_TYPES as readonly string[]).includes(file.type)) return 'اختر صورة بصيغة PNG أو JPG أو WebP.';
  if (file.size <= 0) return 'الملف فارغ.';
  if (file.size > BRAND_SOURCE_MAX_BYTES) return 'حجم الصورة يجب ألا يزيد عن 5 ميجابايت.';
  return null;
}

/** The reason a picture of this size cannot be used as this mark, or null. */
export function checkBrandDimensions(kind: BrandKind, width: number, height: number): string | null {
  if (!(width > 0 && height > 0)) return 'تعذر قراءة الصورة.';
  const min = BRAND_MIN[kind];
  if (kind === 'logo') {
    if (Math.max(width, height) < min) return `الشعار صغير جداً (${width}×${height}). استخدم صورة لا يقل طولها عن ${min} بكسل.`;
    if (Math.max(width, height) / Math.min(width, height) > 6) return 'الشعار طويل جداً بالنسبة لارتفاعه. استخدم نسخة أقرب إلى المستطيل.';
    return null;
  }
  if (Math.min(width, height) < min) return `الرمز صغير جداً (${width}×${height}). استخدم صورة مربعة لا تقل عن ${min}×${min} بكسل.`;
  return null;
}

/**
 * The size a picture is stored at. A logo keeps its shape and is only ever
 * made smaller (longer side at most 1024); an emblem always fills a 512 square
 * box, the whole picture kept and centred, never cut.
 */
export function storedSize(kind: BrandKind, width: number, height: number): { width: number; height: number } {
  if (kind === 'emblem') return { width: BRAND_STORED.emblem, height: BRAND_STORED.emblem };
  const scale = Math.min(1, BRAND_STORED.logo / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/** A square source is used as it is; anything else is centred with clear margins. */
export const isSquarish = (width: number, height: number): boolean =>
  width > 0 && height > 0 && Math.max(width, height) / Math.min(width, height) <= 1.1;

// ── Saving ───────────────────────────────────────────────────────────
/** What `set_company_branding` answers with. */
export interface SavedBranding {
  company_id: string; name: string; logo_path: string | null; emblem_path: string | null;
  /** Folders nothing shows any more: their files can be removed. */
  stale: string[];
}

/** undefined = keep what is saved, null = remove it, a value = replace it. */
export type BrandChange<T> = T | null | undefined;
/** The path to save for one mark, given what is saved and what the admin chose. */
export const nextPath = (saved: string | null | undefined, change: BrandChange<string>): string | null =>
  (change === undefined ? saved ?? null : change);

/** The same numbers with the company's marks replaced by what was just saved. */
export function withBranding<T extends { company: { id: string } }>(numbers: T, saved: Pick<SavedBranding, 'company_id' | 'logo_path' | 'emblem_path'>): T {
  if (numbers.company.id !== saved.company_id) return numbers;
  return { ...numbers, company: { ...numbers.company, logo_path: saved.logo_path, emblem_path: saved.emblem_path } };
}
