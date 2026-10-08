import { useEffect, useState } from 'react';
import { useInfiniteQuery, useQueryClient, type InfiniteData, type QueryClient, type QueryKey } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, unwrap, usePageData } from './query';
import { loadLineOptions } from './lineOptions';
import {
  audienceKey, withCancelled, withoutRow,
  type AudiencePreview, type AudienceSpec, type ComposeResult, type HistoryPage, type HistoryRow, type Priority, type StatusFilter,
} from './notifications';

const PAGE_SIZE = 30;

/**
 * Everything of this page lives under `keys.company(id, 'notifications', …)`,
 * the key `useWorkspaceSync` refreshes when the `notifications` table changes.
 */
const historyRoot = (companyId: string) => keys.company(companyId, 'notifications', 'history');
const historyKey = (companyId: string, filter: StatusFilter) => keys.company(companyId, 'notifications', 'history', filter);

type History = InfiniteData<HistoryPage, string | null>;

/** The lines (with their trips) and universities the audience is chosen from: the cache other pages already fill. */
export const useAudienceOptions = (companyId: string) =>
  usePageData(keys.company(companyId, 'lineOptions'), () => loadLineOptions(companyId));

/** The company's notifications, newest first, a page at a time. */
export function useNotificationHistory(companyId: string, filter: StatusFilter) {
  const query = useInfiniteQuery({
    queryKey: historyKey(companyId, filter),
    queryFn: ({ pageParam }) => unwrap<HistoryPage>(supabase.rpc('get_company_notifications_page', {
      p_company_id: companyId, p_before: pageParam, p_limit: PAGE_SIZE, p_status: filter === 'all' ? null : filter,
    })),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last?.next_before ?? undefined,
  });
  const pages = query.data?.pages ?? [];
  return {
    rows: pages.flatMap((page) => page?.items ?? []),
    /** null until the first page says so. */
    pushConfigured: pages.length ? pages[0]?.push_configured ?? false : null,
    loading: query.isPending,
    refreshing: query.isFetching && !query.isPending && !query.isFetchingNextPage,
    error: query.error instanceof Error ? query.error.message : '',
    hasMore: !!query.hasNextPage,
    loadingMore: query.isFetchingNextPage,
    loadMore: () => { void query.fetchNextPage(); },
    reload: () => { void query.refetch(); },
  };
}

function useDebounced<T>(value: T, delay: number): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const timer = window.setTimeout(() => setSettled(value), delay);
    return () => window.clearTimeout(timer);
  }, [value, delay]);
  return settled;
}

export interface AudiencePreviewState {
  /** `ready` only when the numbers on screen belong to the audience currently chosen. */
  status: 'incomplete' | 'loading' | 'ready' | 'error';
  data?: AudiencePreview;
  error: string;
}

/** Who would receive it, counted by the server. Asked a moment after the choice settles. */
export function useAudiencePreview(companyId: string, spec: AudienceSpec | null): AudiencePreviewState {
  const wanted = audienceKey(spec);
  const asked = useDebounced(wanted, 350);
  const query = usePageData(
    keys.company(companyId, 'notifications', 'audience', asked),
    () => unwrap<AudiencePreview>(supabase.rpc('preview_notification_audience', { p_company_id: companyId, p_audience: JSON.parse(asked) })),
    { enabled: !!asked },
  );
  if (!wanted) return { status: 'incomplete', error: '' };
  if (asked !== wanted || query.loading || query.refreshing) return { status: 'loading', error: '' };
  if (query.error || !query.data) return { status: 'error', error: query.error };
  return { status: 'ready', data: query.data, error: '' };
}

// ------------------------------------------------------------------ writes ----

export interface ComposeInput {
  title: string; body: string; audience: AudienceSpec; scheduledAt: string | null; idempotencyKey: string; priority: Priority;
}

export const composeNotification = (companyId: string, input: ComposeInput) =>
  unwrap<ComposeResult>(supabase.rpc('compose_notification', {
    p_company_id: companyId, p_title: input.title, p_body: input.body, p_audience: input.audience,
    p_scheduled_at: input.scheduledAt, p_idempotency_key: input.idempotencyKey, p_priority: input.priority,
  }));

export interface UpdateScheduledInput { id: string; title: string; body: string; audience: AudienceSpec; scheduledAt: string; }

export async function updateScheduledNotification(input: UpdateScheduledInput): Promise<void> {
  const { error } = await supabase.rpc('update_scheduled_notification', {
    p_id: input.id, p_title: input.title, p_body: input.body, p_audience: input.audience, p_scheduled_at: input.scheduledAt,
  });
  if (error) throw new Error(error.message);
}

/** Applies a change to every cached list of the history and returns what was there, for a rollback. */
async function patchHistory(client: QueryClient, companyId: string, change: (items: HistoryRow[], filter: StatusFilter) => HistoryRow[]) {
  await client.cancelQueries({ queryKey: historyRoot(companyId) });
  const before = client.getQueriesData<History>({ queryKey: historyRoot(companyId) });
  before.forEach(([queryKey, data]) => {
    if (!data) return;
    const filter = queryKey[queryKey.length - 1] as StatusFilter;
    client.setQueryData<History>(queryKey, {
      ...data,
      pages: data.pages.map((page) => ({ ...page, items: change(page.items ?? [], filter) })),
    });
  });
  return before;
}

const restore = (client: QueryClient, before: [QueryKey, History | undefined][]) =>
  before.forEach(([queryKey, data]) => client.setQueryData(queryKey, data));

/**
 * Delete and cancel: the row changes on screen at once, the server is asked,
 * and on a refusal the lists go back to what they were and the error is thrown
 * for the page to show.
 */
export function useNotificationActions(companyId: string) {
  const client = useQueryClient();
  const refresh = () => client.invalidateQueries({ queryKey: keys.company(companyId, 'notifications') });

  const run = async (rpc: 'delete_notification' | 'cancel_scheduled_notification', id: string,
    change: (items: HistoryRow[], filter: StatusFilter) => HistoryRow[]) => {
    const before = await patchHistory(client, companyId, change);
    const { error } = await supabase.rpc(rpc, { p_id: id });
    if (error) {
      restore(client, before);
      throw new Error(error.message);
    }
    void refresh();
  };

  return {
    refresh,
    remove: (id: string) => run('delete_notification', id, (items) => withoutRow(items, id)),
    cancel: (id: string) => run('cancel_scheduled_notification', id, (items, filter) => withCancelled(items, id, filter)),
  };
}
