/**
 * Rows this browser tab has just changed itself, and which lists already show
 * the result. The database announces every change to everyone, the author
 * included; the author's own announcement must not make the dashboard read
 * again what it has just put into its cache.
 */
const applied = new Map<string, { until: number; lists: Set<string> }>();
const TTL = 10_000;
const NONE: readonly string[] = [];

/** These rows' changes are already shown in `lists` (cache names, as in lib/sync.ts) for a few seconds. */
export function rememberApplied(ids: (string | null | undefined)[], lists: readonly string[], now = Date.now(), ttl = TTL) {
  for (const [id, entry] of applied) if (entry.until <= now) applied.delete(id);
  ids.forEach((id) => {
    if (!id) return;
    const known = applied.get(id);
    applied.set(id, { until: now + ttl, lists: new Set([...(known?.lists ?? []), ...lists]) });
  });
}

/** The write failed: its announcement, if any, is real news again. */
export function forgetApplied(ids: (string | null | undefined)[]) {
  ids.forEach((id) => { if (id) applied.delete(id); });
}

/** The lists that already show this row's change (empty when the change is someone else's). */
export function appliedLists(id: string | null | undefined, now = Date.now()): readonly string[] {
  if (!id) return NONE;
  const entry = applied.get(id);
  return entry && entry.until > now ? [...entry.lists] : NONE;
}

export function clearApplied() { applied.clear(); }
