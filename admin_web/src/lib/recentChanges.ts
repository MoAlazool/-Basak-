/**
 * Rows this browser tab has just changed itself and already shown the result of.
 * The database announces every change to everyone, the author included; the
 * author's own announcement must not make the dashboard read again what it has
 * just written into its cache.
 */
const applied = new Map<string, number>();
const TTL = 10_000;

/** Remember these row ids for a few seconds. */
export function rememberApplied(ids: (string | null | undefined)[], now = Date.now(), ttl = TTL) {
  for (const [id, until] of applied) if (until <= now) applied.delete(id);
  ids.forEach((id) => { if (id) applied.set(id, now + ttl); });
}

/** The write failed: its announcement, if any, is real news again. */
export function forgetApplied(ids: (string | null | undefined)[]) {
  ids.forEach((id) => { if (id) applied.delete(id); });
}

export function wasAppliedHere(id: string | null | undefined, now = Date.now()): boolean {
  if (!id) return false;
  const until = applied.get(id);
  return until !== undefined && until > now;
}

export function clearApplied() { applied.clear(); }
