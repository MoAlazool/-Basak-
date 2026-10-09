import { useEffect, useState } from 'react';
import { keepPreviousData, useInfiniteQuery, useQueryClient, type InfiniteData, type QueryClient, type QueryKey } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, refreshIfNotUpdated, unwrap, usePageData, VARIANT_GC } from './query';
import { forgetApplied, rememberApplied } from './recentChanges';
import {
  audienceKey, platformCompanyIds, withCancelled, withoutRow,
  type AudiencePreview, type AudienceSpec, type ComposeResult, type HistoryPage, type HistoryRow, type PlatformComposeResult,
  type PlatformHistoryPage, type PlatformPreview, type Priority, type StatusFilter,
} from './notifications';

const PAGE_SIZE = 30;

/**
 * The history lives under `keys.company(id, 'notifications', …)`, the key
 * `useWorkspaceSync` refreshes when the `notifications` table changes.
 */
const historyRoot = (companyId: string) => keys.company(companyId, 'notifications', 'history');
const historyKey = (companyId: string, filter: StatusFilter) => keys.company(companyId, 'notifications', 'history', filter);
/** What a write to a notification brings up to date in this tab (the name lib/sync.ts refreshes for the table). */
const APPLIED_HERE = ['notifications'];

type History = InfiniteData<{ items: HistoryRow[] }, string | null>;

/** A history, newest first, a page at a time: the company's own or the platform's. */
function useHistoryPages<P extends { items: HistoryRow[]; next_before: string | null }>(
  queryKey: readonly unknown[], load: (before: string | null) => Promise<P>, keepPrevious = false,
) {
  const query = useInfiniteQuery({
    queryKey,
    queryFn: ({ pageParam }) => load(pageParam),
    initialPageParam: null as string | null,
    getNextPageParam: (last: P) => last?.next_before ?? undefined,
    placeholderData: keepPrevious ? keepPreviousData : undefined,
  });
  const pages: P[] = query.data?.pages ?? [];
  return {
    first: pages[0] as P | undefined,
    rows: pages.flatMap((page) => page?.items ?? []),
    loading: query.isPending,
    refreshing: query.isFetching && !query.isPending && !query.isFetchingNextPage,
    error: query.error instanceof Error ? query.error.message : '',
    hasMore: !!query.hasNextPage,
    loadingMore: query.isFetchingNextPage,
    loadMore: () => { void query.fetchNextPage(); },
    reload: () => { void query.refetch(); },
  };
}

/** The company's notifications. */
export function useNotificationHistory(companyId: string, filter: StatusFilter) {
  const { first, ...history } = useHistoryPages(historyKey(companyId, filter), (before) =>
    unwrap<HistoryPage>(supabase.rpc('get_company_notifications_page', {
      p_company_id: companyId, p_before: before, p_limit: PAGE_SIZE, p_status: filter === 'all' ? null : filter,
    })), true);
  /** null until the first page says so. */
  return { ...history, pushConfigured: first ? first.push_configured ?? false : null };
}

/** What the history list needs, whichever history it shows. */
export type HistoryState = ReturnType<typeof useNotificationHistory>;

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
    // Its own key, apart from the history: a new notification does not change who a line or a university reaches.
    keys.company(companyId, 'audience', asked),
    () => unwrap<AudiencePreview>(supabase.rpc('preview_notification_audience', { p_company_id: companyId, p_audience: JSON.parse(asked) })),
    // One answer per audience tried: kept only while it is likely to be asked for again.
    { enabled: !!asked, gcTime: VARIANT_GC },
  );
  if (!wanted) return { status: 'incomplete', error: '' };
  if (asked !== wanted || query.loading || query.refreshing) return { status: 'loading', error: '' };
  if (query.error || !query.data) return { status: 'error', error: query.error };
  return { status: 'ready', data: query.data, error: '' };
}

// ------------------------------------------------------------------ writes ----

interface ComposeInput {
  title: string; body: string; audience: AudienceSpec; scheduledAt: string | null; idempotencyKey: string; priority: Priority;
}

export const composeNotification = (companyId: string, input: ComposeInput) =>
  unwrap<ComposeResult>(supabase.rpc('compose_notification', {
    p_company_id: companyId, p_title: input.title, p_body: input.body, p_audience: input.audience,
    p_scheduled_at: input.scheduledAt, p_idempotency_key: input.idempotencyKey, p_priority: input.priority,
  }));

interface UpdateScheduledInput { id: string; title: string; body: string; audience: AudienceSpec; scheduledAt: string; }

export async function updateScheduledNotification(input: UpdateScheduledInput): Promise<void> {
  const { error } = await supabase.rpc('update_scheduled_notification', {
    p_id: input.id, p_title: input.title, p_body: input.body, p_audience: input.audience, p_scheduled_at: input.scheduledAt,
  });
  if (error) throw new Error(error.message);
}

/**
 * Applies a change to every cached list of a history and returns what was there,
 * for a rollback. `root` is the history's key; the status filter is its last part.
 */
async function patchHistory(client: QueryClient, root: readonly unknown[], change: (items: HistoryRow[], filter: StatusFilter) => HistoryRow[]) {
  await client.cancelQueries({ queryKey: root });
  const before = client.getQueriesData<History>({ queryKey: root });
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
 * for the page to show. Nothing is read again afterwards: what is on screen is
 * what was saved, and the change's own announcement is recognised as such.
 */
function useHistoryActions(history: readonly unknown[]) {
  const client = useQueryClient();

  const run = async (rpc: 'delete_notification' | 'cancel_scheduled_notification', id: string,
    change: (items: HistoryRow[], filter: StatusFilter) => HistoryRow[]) => {
    rememberApplied([id], APPLIED_HERE);
    const before = await patchHistory(client, history, change);
    const { error } = await supabase.rpc(rpc, { p_id: id });
    if (error) {
      forgetApplied([id]);
      restore(client, before);
      throw new Error(error.message);
    }
    // Out of date in name only: read again the next time the list is opened, not now.
    void client.invalidateQueries({ queryKey: history, refetchType: 'none' });
  };

  return {
    /**
     * After a notification was written or changed here: the history is read once.
     * With the row's id, the announcement of that same change does not read it a second time.
     */
    refresh: (id?: string) => {
      if (id) rememberApplied([id], APPLIED_HERE);
      return client.invalidateQueries({ queryKey: history });
    },
    remove: (id: string) => run('delete_notification', id, (items) => withoutRow(items, id)),
    cancel: (id: string) => run('cancel_scheduled_notification', id, (items, filter) => withCancelled(items, id, filter)),
  };
}

export type HistoryActions = Pick<ReturnType<typeof useHistoryActions>, 'remove' | 'cancel'>;

export const useNotificationActions = (companyId: string) => useHistoryActions(historyRoot(companyId));

// ---------------------------------------------------------------- platform ----

/**
 * The platform admin's side lives under `keys.platform('notifications', …)`,
 * the key `usePlatformSync` refreshes when a notification changes.
 */
const platformHistoryRoot = keys.platform('notifications', 'history');

/** Notifications of every company (or of one), with the platform's push numbers on the first page. */
export function usePlatformNotificationHistory(filter: StatusFilter, companyId: string) {
  // The filter stays last in the key: the optimistic edits read it from there.
  const { first, ...history } = useHistoryPages(keys.platform('notifications', 'history', companyId || 'all', filter), (before) =>
    unwrap<PlatformHistoryPage>(supabase.rpc('get_platform_notifications_page', {
      p_before: before, p_limit: PAGE_SIZE, p_status: filter === 'all' ? null : filter, p_company_id: companyId || null,
    })), true);
  const push = first?.push ?? null;
  return { ...history, push, pushConfigured: first ? push?.configured ?? false : null };
}

export const usePlatformNotificationActions = () => useHistoryActions(platformHistoryRoot);

/**
 * After a platform notification was composed: one notification per company was
 * created, each announced on the platform's topic, which reads the history once.
 */
export const awaitPlatformHistory = () => refreshIfNotUpdated(platformHistoryRoot);

interface PlatformPreviewState { status: AudiencePreviewState['status']; data?: PlatformPreview; error: string; }

/** Who a platform notification would reach, counted by the server a moment after the choice settles. */
export function usePlatformPreview(all: boolean, selected: string[]): PlatformPreviewState {
  const ids = platformCompanyIds(all, selected);
  const wanted = ids === null ? 'all' : ids.join(',');
  const asked = useDebounced(wanted, 350);
  const query = usePageData(
    keys.platform('preview', asked),
    () => unwrap<PlatformPreview>(supabase.rpc('platform_preview_notification', { p_company_ids: asked === 'all' ? null : asked.split(',') })),
    { enabled: !!asked, gcTime: VARIANT_GC },
  );
  if (!wanted) return { status: 'incomplete', error: '' };
  if (asked !== wanted || query.loading || query.refreshing) return { status: 'loading', error: '' };
  if (query.error || !query.data) return { status: 'error', error: query.error };
  return { status: 'ready', data: query.data, error: '' };
}

interface PlatformComposeInput {
  title: string; body: string; companyIds: string[] | null; scheduledAt: string | null; idempotencyKey: string; priority: Priority;
}

export const platformComposeNotification = (input: PlatformComposeInput) =>
  unwrap<PlatformComposeResult>(supabase.rpc('platform_compose_notification', {
    p_title: input.title, p_body: input.body, p_company_ids: input.companyIds,
    p_scheduled_at: input.scheduledAt, p_idempotency_key: input.idempotencyKey, p_priority: input.priority,
  }));
