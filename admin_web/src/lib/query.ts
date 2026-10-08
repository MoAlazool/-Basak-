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
  /** Signed storage links (valid for an hour): re-signed a little before they expire. */
  signed: 50 * MINUTE,
} as const;

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
 * shared computer. Signed links (receipt images, photos) expire and are not kept.
 */
const NOT_PERSISTED = new Set(['receipts', 'signed']);
const CACHE_SHAPE = 2;
export const persister = createSyncStoragePersister({ storage: window.sessionStorage, key: 'basak.admin.cache' });
export const persistOptions = (adminId: string) => ({
  persister,
  maxAge: DAY,
  // Another account never restores this account's cache; nor does a release that
  // changed what is stored under a key restore the older shape (bump CACHE_SHAPE then).
  buster: `${adminId}:${CACHE_SHAPE}`,
  dehydrateOptions: {
    shouldDehydrateQuery: (query: { queryKey: readonly unknown[]; state: { status: string } }) =>
      query.state.status === 'success' && !query.queryKey.some((part) => typeof part === 'string' && NOT_PERSISTED.has(part)),
  },
});

/** Sign-out: nothing of the session stays in memory or in the tab's storage. */
export function clearCache() {
  clearApplied();
  queryClient.clear();
  persister.removeClient();
}

/** Supabase returns `{ data, error }`; queries want the data or a thrown error. */
export async function unwrap<T>(request: PromiseLike<{ data: T | null; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await request;
  if (error) throw new Error(error.message);
  return data as T;
}

/**
 * A page's data as one cached value: what it last had is shown at once while a
 * fresh copy is fetched behind it. `loading` is true only when nothing has ever
 * been loaded for this key; `reload` is for after the page's own writes.
 */
export function usePageData<T>(queryKey: readonly unknown[], load: () => Promise<T>, options: { keepPrevious?: boolean; enabled?: boolean; staleTime?: number } = {}) {
  const query = useQuery({
    queryKey, queryFn: load, enabled: options.enabled, staleTime: options.staleTime,
    placeholderData: options.keepPrevious ? keepPreviousData : undefined,
  });
  return {
    data: query.data,
    loading: query.isPending,
    refreshing: query.isFetching && !query.isPending,
    error: query.error instanceof Error ? query.error.message : '',
    reload: async () => { await query.refetch(); },
  };
}
