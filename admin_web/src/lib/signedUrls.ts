import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, queryClient, STALE } from './query';

/**
 * Signed links to private files (receipt images, student and supervisor photos).
 *
 * Each link is kept once per file, for as long as it is safely valid. A list
 * that is re-read, a tab that regains focus or a page that is reopened gets the
 * very same link back, so the browser shows the picture from its own cache
 * instead of downloading it again under a new token.
 */

/** Links are signed for two hours and reused for at most 50 + 50 minutes. */
const LIFETIME_SECONDS = 2 * 60 * 60;

const urlKey = (bucket: string, path: string) => keys.shared('signed', bucket, 'url', path);

/** The paths that have no link young enough to hand out again. */
export function pathsNeedingSignature(
  paths: readonly string[], signedAt: (path: string) => number | undefined, now: number, maxAge: number = STALE.signed,
): string[] {
  return [...new Set(paths)].filter((path) => {
    const at = signedAt(path);
    return at === undefined || now - at >= maxAge;
  });
}

/** Stable identity of a set of paths, whatever order the rows came in. */
export const normalizePaths = (paths: readonly (string | null | undefined)[]): string[] =>
  [...new Set(paths.filter((path): path is string => !!path))].sort();

/** Links for all of `paths`, signing in ONE request only those not already held. */
export async function signPaths(bucket: string, paths: readonly string[]): Promise<Record<string, string>> {
  const known = (path: string) => {
    const state = queryClient.getQueryState<string>(urlKey(bucket, path));
    return state?.data ? state.dataUpdatedAt : undefined;
  };
  const missing = pathsNeedingSignature(paths, known, Date.now());
  if (missing.length) {
    const { data, error } = await supabase.storage.from(bucket).createSignedUrls(missing, LIFETIME_SECONDS);
    if (error) throw new Error(error.message);
    // A file that no longer exists yields no link; its row simply shows no picture.
    (data ?? []).forEach((item) => {
      if (item.path && item.signedUrl && !item.error) queryClient.setQueryData(urlKey(bucket, item.path), item.signedUrl);
    });
  }
  const urls: Record<string, string> = {};
  paths.forEach((path) => {
    const url = queryClient.getQueryData<string>(urlKey(bucket, path));
    if (url) urls[path] = url;
  });
  return urls;
}

/** path → link for the files on screen. Empty until the first answer; never blocks the rows. */
export function useSignedUrls(bucket: string, paths: readonly (string | null | undefined)[]): Record<string, string> {
  const list = normalizePaths(paths);
  const query = useQuery({
    queryKey: keys.shared('signed', bucket, 'set', list),
    queryFn: () => signPaths(bucket, list),
    enabled: list.length > 0,
    staleTime: STALE.signed,
    refetchInterval: STALE.signed,   // a tab left open gets fresh links before the old ones expire
    placeholderData: keepPreviousData,
  });
  return query.data ?? EMPTY;
}
const EMPTY: Record<string, string> = {};

/** A link that stopped working (expired while the tab slept, file replaced): sign that file again. */
export async function resignPath(bucket: string, path: string): Promise<string | null> {
  queryClient.removeQueries({ queryKey: urlKey(bucket, path), exact: true });
  const urls = await signPaths(bucket, [path]);
  void queryClient.invalidateQueries({ queryKey: keys.shared('signed', bucket, 'set') });
  return urls[path] ?? null;
}
