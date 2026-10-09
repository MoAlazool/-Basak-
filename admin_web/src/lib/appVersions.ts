/**
 * The app's release settings, one row per platform (table `app_versions`):
 * the oldest version still allowed in, the newest one in the store, up to three
 * lines of what is new, and the store link. Everything here is pure: the page
 * reads the rows and saves through `save_app_version`.
 */

export type Platform = 'android' | 'ios';
export const PLATFORMS: Platform[] = ['android', 'ios'];
export const platformName: Record<Platform, string> = { android: 'أندرويد (Google Play)', ios: 'آيفون (App Store)' };

/** How many "what's new" lines the app shows, and how long one may be. */
export const WHATS_NEW_LINES = 3;
export const WHATS_NEW_MAX = 120;
const STORE_URL_MAX = 300;

/** A row as the table gives it. */
export interface AppVersionRow {
  platform: Platform; min_version: string; latest_version: string; whats_new: string[] | null; store_url: string | null;
  updated_at?: string | null;
}

/** The form: always three lines, text everywhere. */
export interface AppVersionDraft { minVersion: string; latestVersion: string; whatsNew: string[]; storeUrl: string }

/** What `save_app_version` is called with. */
export interface AppVersionSave {
  p_platform: Platform; p_min_version: string; p_latest_version: string; p_whats_new: string[]; p_store_url: string | null;
}

const VERSION = /^\d{1,4}(\.\d{1,4}){0,2}$/;

/** '2.5' → [2, 5, 0]; null when it is not one to three numbers separated by dots. */
export function versionParts(version: string): [number, number, number] | null {
  const text = version.trim();
  if (!VERSION.test(text)) return null;
  const [major = 0, minor = 0, patch = 0] = text.split('.').map(Number);
  return [major, minor, patch];
}

/** Negative when `a` is older than `b`, 0 when they are the same release. Number by number: 2.10 is after 2.9. */
export function compareVersions(a: string, b: string): number {
  const x = versionParts(a) ?? [0, 0, 0];
  const y = versionParts(b) ?? [0, 0, 0];
  for (let i = 0; i < 3; i += 1) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
}

/** The saved row as the form shows it (a missing row starts at 0.0.0, which asks nobody to update). */
export function draftFromRow(row: AppVersionRow | undefined): AppVersionDraft {
  const lines = (row?.whats_new ?? []).slice(0, WHATS_NEW_LINES);
  return {
    minVersion: row?.min_version ?? '0.0.0',
    latestVersion: row?.latest_version ?? '0.0.0',
    whatsNew: [...lines, ...Array<string>(WHATS_NEW_LINES - lines.length).fill('')],
    storeUrl: row?.store_url ?? '',
  };
}

/** The lines that will be saved: trimmed, empty ones dropped. */
export const filledLines = (lines: string[]) => lines.map((line) => line.trim()).filter(Boolean);

/** Why the form cannot be saved, in the admin's language; null when it can. The server checks the same rules. */
export function draftProblem(draft: AppVersionDraft): string | null {
  if (!versionParts(draft.minVersion) || !versionParts(draft.latestVersion)) {
    return 'اكتب رقم الإصدار بالأرقام والنقاط فقط، مثل 2.5.0.';
  }
  if (compareVersions(draft.minVersion, draft.latestVersion) > 0) {
    return 'أقل إصدار مسموح لا يمكن أن يكون أحدث من آخر إصدار.';
  }
  const lines = filledLines(draft.whatsNew);
  if (lines.length > WHATS_NEW_LINES) return 'ثلاثة أسطر على الأكثر في «ما الجديد».';
  if (lines.some((line) => line.length > WHATS_NEW_MAX)) return `سطر «ما الجديد» طويل جداً (${WHATS_NEW_MAX} حرفاً على الأكثر).`;
  const url = draft.storeUrl.trim();
  if (url && (!/^https:\/\//.test(url) || url.length > STORE_URL_MAX)) return 'رابط المتجر يجب أن يبدأ بـ https://';
  return null;
}

/** Whether the form differs from what is saved (spaces around a value and empty lines do not count). */
export function draftChanged(draft: AppVersionDraft, row: AppVersionRow | undefined): boolean {
  const saved = draftFromRow(row);
  return draft.minVersion.trim() !== saved.minVersion || draft.latestVersion.trim() !== saved.latestVersion
    || draft.storeUrl.trim() !== saved.storeUrl
    || filledLines(draft.whatsNew).join('\n') !== filledLines(saved.whatsNew).join('\n');
}

export function toSave(platform: Platform, draft: AppVersionDraft): AppVersionSave {
  return {
    p_platform: platform,
    p_min_version: draft.minVersion.trim(),
    p_latest_version: draft.latestVersion.trim(),
    p_whats_new: filledLines(draft.whatsNew),
    p_store_url: draft.storeUrl.trim() || null,
  };
}
