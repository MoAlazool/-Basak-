import { keepPreviousData, QueryClient, useQuery } from '@tanstack/react-query';
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister';
import { clearApplied } from './recentChanges';

const DAY = 24 * 60 * 60 * 1000;
const MINUTE = 60 * 1000;

/**
 * How long a cached value is used without asking again. Live events still mark
 * a list out of date at once; these only stop needless re-reads on focus/remount.
 */
export const STALE = {
  /** Lookups that rarely change: universities, lines, supervisors, switches, the company row. */
  reference: 5 * MINUTE,
  /** Signed storage links (valid for two hours): re-signed well before they expire. */
  signed: 50 * MINUTE,
} as const;

/**
 * How long an unused answer to a search, a filter or a later page stays in
 * memory. The default view of a list is kept for the day; its variants are not
 * (every word typed in a search box would otherwise stay for 24 hours).
 */
export const VARIANT_GC = 5 * MINUTE;

/**
 * One cache for the whole dashboard. A page shows what it last had at once and
 * refreshes behind it; a blocking loader only appears the very first time.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,        // live events invalidate sooner; this covers everything else
      gcTime: DAY,              // must outlive the persisted copy
      retry: 1,
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
    },
  },
});

/**
 * Every key starts with its scope, so one company's rows can never be read
 * under another company's key:
 *   ['platform', …]            what spans companies (platform admin only)
 *   ['c', companyId, …]        one company's workspace
 *   ['shared', …]              the catalogue every company uses (universities)
 */
export const keys = {
  platform: (...rest: unknown[]) => ['platform', ...rest] as const,
  company: (companyId: string, ...rest: unknown[]) => ['c', companyId, ...rest] as const,
  shared: (...rest: unknown[]) => ['shared', ...rest] as const,
};

/**
 * The cache also survives a page reload, for this browser tab only
 * (sessionStorage): closing the tab or signing out leaves nothing behind on a
 * shared computer.
 *
 * Not everything is kept. Left out are:
 *   - signed links (they expire) and the receipts queue (always read fresh);
 *   - financial report rows and audience counts (large, or cheap to ask again);
 *   - every search / filter / later-page variant of a list: a key part that is an
 *     object with any value set (`{ search: 'أحمد' }`, `{ pageIndex: 2 }`) marks one.
 * So what is stored is one default view per list and the lookups, and its size
 * follows the number of pages visited, not the number of things typed.
 */
const NOT_PERSISTED = new Set(['receipts', 'signed', 'reports', 'audience', 'preview']);
const CACHE_SHAPE = 3;

const isVariant = (part: unknown) =>
  typeof part === 'object' && part !== null && Object.values(part).some((value) => !!value);

/** Whether a query's answer is written to the tab's storage. */
export function shouldPersist(queryKey: readonly unknown[]): boolean {
  return !queryKey.some((part) => (typeof part === 'string' && NOT_PERSISTED.has(part)) || isVariant(part));
}

/** The most the stored cache may take, in characters (sessionStorage allows about 5 million per site). */
export const PERSIST_MAX_CHARS = 1_500_000;

type KeyValueStore = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

/**
 * A store that refuses a value above `maxChars`: the older copy is dropped
 * rather than left behind out of date, and the next reload simply starts cold.
 * A full or unavailable storage is treated the same way instead of throwing.
 */
export function cappedStorage(storage: KeyValueStore, maxChars: number = PERSIST_MAX_CHARS): KeyValueStore {
  return {
    getItem: (key) => storage.getItem(key),
    removeItem: (key) => storage.removeItem(key),
    setItem: (key, value) => {
      if (value.length > maxChars) { storage.removeItem(key); return; }
      try { storage.setItem(key, value); } catch { storage.removeItem(key); }
    },
  };
}

const persister = createSyncStoragePersister({ storage: cappedStorage(window.sessionStorage), key: 'basak.admin.cache' });
export const persistOptions = (adminId: string) => ({
  persister,
  maxAge: DAY,
  // Another account never restores this account's cache; nor does a release that
  // changed what is stored under a key restore the older shape (bump CACHE_SHAPE then).
  buster: `${adminId}:${CACHE_SHAPE}`,
  dehydrateOptions: {
    shouldDehydrateQuery: (query: { queryKey: readonly unknown[]; state: { status: string } }) =>
      query.state.status === 'success' && shouldPersist(query.queryKey),
  },
});

/** Sign-out: nothing of the session stays in memory or in the tab's storage. */
export function clearCache() {
  clearApplied();
  queryClient.clear();
  persister.removeClient();
}

/**
 * For a write whose result reaches this tab through the live topic (lib/sync.ts
 * reads the list again when the change is announced): if no fresh copy of
 * `queryKey` has arrived a moment later, the topic is not delivering, and the
 * list is read once here instead. When the topic works this costs nothing.
 * Call it after any change made to the cache by hand (that counts as an update
 * of this very millisecond, hence the `+ 1`).
 */
export function refreshIfNotUpdated(queryKey: readonly unknown[], since: number = Date.now() + 1, wait = 2500) {
  window.setTimeout(() => {
    queryClient.getQueryCache().findAll({ queryKey, type: 'active' }).forEach((query) => {
      if (query.state.dataUpdatedAt < since && query.state.fetchStatus === 'idle') {
        void queryClient.invalidateQueries({ queryKey: query.queryKey, exact: true });
      }
    });
  }, wait);
}

/** Supabase returns `{ data, error }`; queries want the data or a thrown error. */
export async function unwrap<T>(request: PromiseLike<{ data: T | null; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await request;
  if (error) throw new Error(error.message);
  return data as T;
}

/** An embedded relation arrives as one object or as a list of one, depending on how PostgREST reads the key. */
export const one = <T,>(value: T | T[] | null | undefined): T | undefined => (Array.isArray(value) ? value[0] : value ?? undefined);

/**
 * A page's data as one cached value: what it last had is shown at once while a
 * fresh copy is fetched behind it. `loading` is true only when nothing has ever
 * been loaded for this key; `reload` is for after the page's own writes.
 */
export function usePageData<T>(queryKey: readonly unknown[], load: () => Promise<T>, options: PageDataOptions = {}) {
  const { keepPrevious, ...given } = options;
  const query = useQuery({
    queryKey, queryFn: load, ...defined(given),
    placeholderData: keepPrevious ? keepPreviousData : undefined,
  });
  return {
    data: query.data,
    loading: query.isPending,
    refreshing: query.isFetching && !query.isPending,
    error: query.error instanceof Error ? query.error.message : '',
    reload: async () => { await query.refetch(); },
  };
}

interface PageDataOptions { keepPrevious?: boolean; enabled?: boolean; staleTime?: number; gcTime?: number }

/**
 * Only the options that were actually given. An option passed as `undefined`
 * would replace the client's default with nothing (`staleTime: undefined` means
 * "always stale", not "30 seconds").
 */
export function defined<T extends object>(options: T): Partial<T> {
  return Object.fromEntries(Object.entries(options).filter(([, value]) => value !== undefined)) as Partial<T>;
}
