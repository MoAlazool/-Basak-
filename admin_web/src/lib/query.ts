import { keepPreviousData, QueryClient, useQuery } from '@tanstack/react-query';
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister';

const DAY = 24 * 60 * 60 * 1000;

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
 * shared computer. Signed links (receipt images, avatars) expire and are not kept.
 */
const NOT_PERSISTED = new Set(['receipts', 'avatars', 'walletCard']);
export const persister = createSyncStoragePersister({ storage: window.sessionStorage, key: 'basak.admin.cache' });
export const persistOptions = (adminId: string) => ({
  persister,
  maxAge: DAY,
  buster: adminId, // another account never restores this account's cache
  dehydrateOptions: {
    shouldDehydrateQuery: (query: { queryKey: readonly unknown[]; state: { status: string } }) =>
      query.state.status === 'success' && !query.queryKey.some((part) => typeof part === 'string' && NOT_PERSISTED.has(part)),
  },
});

/** Sign-out: nothing of the session stays in memory or in the tab's storage. */
export function clearCache() {
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
export function usePageData<T>(queryKey: readonly unknown[], load: () => Promise<T>, options: { keepPrevious?: boolean; enabled?: boolean } = {}) {
  const query = useQuery({
    queryKey, queryFn: load, enabled: options.enabled,
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
