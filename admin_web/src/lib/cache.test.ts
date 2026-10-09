import { describe, expect, it } from 'vitest';
import { cappedStorage, defined, keys, shouldPersist } from './query';
import { normalizePaths, pathsNeedingSignature } from './signedUrls';
import { createGuard } from './guard';
import { forgetMissingFunctions, rpcOr } from './rpc';

const A = '11111111-1111-1111-1111-111111111111';
const B = '22222222-2222-2222-2222-222222222222';
/** TanStack matches a query by prefix: every part of the filter key equals the same part of the query key. */
const isUnder = (queryKey: readonly unknown[], prefix: readonly unknown[]) =>
  prefix.every((part, index) => JSON.stringify(queryKey[index]) === JSON.stringify(part));

describe('cache keys', () => {
  it('start with their scope, and a company key with that company', () => {
    expect(keys.company(A, 'students', 'page', { search: '', pageIndex: 0 })).toEqual(['c', A, 'students', 'page', { search: '', pageIndex: 0 }]);
    expect(keys.platform('overview')).toEqual(['platform', 'overview']);
    expect(keys.shared('universities')).toEqual(['shared', 'universities']);
  });

  it('never let one company\'s key fall under another company\'s', () => {
    const lists = ['overview', 'students', 'receipts', 'lines', 'lineNames', 'supervisors', 'supervisorLines', 'reports',
      'paymentMethods', 'notifications', 'settings', 'switches', 'team', 'walletCard', 'resetRequests', 'invites', 'corrections', 'vote', 'periods', 'company'];
    for (const list of lists) {
      const ofA = keys.company(A, list, { search: 'x' });
      expect(isUnder(ofA, keys.company(A))).toBe(true);
      expect(isUnder(ofA, keys.company(A, list))).toBe(true);
      // Refreshing or reading company B, in whole or one list, never reaches A's entry.
      expect(isUnder(ofA, keys.company(B))).toBe(false);
      expect(isUnder(ofA, keys.company(B, list))).toBe(false);
      expect(isUnder(ofA, keys.platform())).toBe(false);
      expect(isUnder(ofA, keys.shared())).toBe(false);
    }
  });

  it('keep the platform\'s and the shared catalogue\'s entries out of every company', () => {
    expect(isUnder(keys.platform('students', { search: '' }), keys.company(A))).toBe(false);
    expect(isUnder(keys.shared('signed', 'receipts', 'url', `${A}/x.jpg`), keys.company(A))).toBe(false);
  });
});

describe('what is written to the tab\'s storage', () => {
  it('keeps the default view of a list and the lookups', () => {
    expect(shouldPersist(keys.company(A, 'overview'))).toBe(true);
    expect(shouldPersist(keys.company(A, 'lines'))).toBe(true);
    expect(shouldPersist(keys.company(A, 'students', 'page', { search: '', pageIndex: 0 }))).toBe(true);
    expect(shouldPersist(keys.company(A, 'students', 'total', { search: '' }))).toBe(true);
    expect(shouldPersist(keys.company(A, 'notifications', 'history', 'all'))).toBe(true);
    expect(shouldPersist(keys.platform('students', { search: '', companyId: '', membership: '', pageIndex: 0 }))).toBe(true);
  });

  it('leaves out every search, filter and later page', () => {
    expect(shouldPersist(keys.company(A, 'students', 'page', { search: 'أحمد', pageIndex: 0 }))).toBe(false);
    expect(shouldPersist(keys.company(A, 'students', 'page', { search: '', pageIndex: 3 }))).toBe(false);
    expect(shouldPersist(keys.company(A, 'students', 'total', { search: '010' }))).toBe(false);
    expect(shouldPersist(keys.platform('students', { search: '', companyId: B, membership: '', pageIndex: 0 }))).toBe(false);
  });

  it('leaves out signed links, the receipts queue, report rows and audience counts', () => {
    expect(shouldPersist(keys.shared('signed', 'receipts', 'url', 'a/b.jpg'))).toBe(false);
    expect(shouldPersist(keys.company(A, 'receipts', 'pending', 50))).toBe(false);
    expect(shouldPersist(keys.company(A, 'reports', { search: '' }))).toBe(false);
    expect(shouldPersist(keys.company(A, 'notifications', 'audience', '{"kind":"company"}'))).toBe(false);
    expect(shouldPersist(keys.platform('notifications', 'preview', 'all'))).toBe(false);
  });

  it('refuses a copy above the size limit and drops the older one', () => {
    const held = new Map<string, string>([['k', 'old']]);
    const store = cappedStorage({
      getItem: (key) => held.get(key) ?? null,
      setItem: (key, value) => { held.set(key, value); },
      removeItem: (key) => { held.delete(key); },
    }, 10);
    store.setItem('k', 'small');
    expect(store.getItem('k')).toBe('small');
    store.setItem('k', 'x'.repeat(11));
    expect(store.getItem('k')).toBeNull();
  });

  it('survives a storage that is full', () => {
    const held = new Map<string, string>([['k', 'old']]);
    const store = cappedStorage({
      getItem: (key) => held.get(key) ?? null,
      setItem: () => { throw new Error('QuotaExceededError'); },
      removeItem: (key) => { held.delete(key); },
    }, 100);
    expect(() => store.setItem('k', 'new')).not.toThrow();
    expect(store.getItem('k')).toBeNull();
  });
});

describe('query options', () => {
  it('drops options given as undefined, so the client\'s defaults stay in force', () => {
    expect(defined({ staleTime: undefined, enabled: false, gcTime: 0 })).toEqual({ enabled: false, gcTime: 0 });
    expect('staleTime' in defined({ staleTime: undefined })).toBe(false);
  });
});

describe('signed links', () => {
  const MAX = 50;
  it('signs only what has no link young enough', () => {
    const signedAt: Record<string, number> = { fresh: 990, old: 900, edge: 950 };
    expect(pathsNeedingSignature(['fresh', 'old', 'edge', 'new'], (path) => signedAt[path], 1000, MAX)).toEqual(['old', 'edge', 'new']);
  });
  it('asks for a file once, however often it appears', () => {
    expect(pathsNeedingSignature(['a', 'a', 'b', 'a'], () => undefined, 0, MAX)).toEqual(['a', 'b']);
  });
  it('signs nothing when every link is still good', () => {
    expect(pathsNeedingSignature(['a', 'b'], () => 1000, 1001, MAX)).toEqual([]);
  });
  it('gives a set of files one identity whatever order the rows came in', () => {
    expect(normalizePaths(['b', null, 'a', undefined, 'b', ''])).toEqual(['a', 'b']);
    expect(normalizePaths(['a', 'b'])).toEqual(normalizePaths(['b', 'a']));
  });
});

describe('double-submit guard', () => {
  it('runs one task per key at a time and ignores the second call', async () => {
    const guard = createGuard();
    let release: () => void = () => undefined;
    let runs = 0;
    const task = () => new Promise<string>((resolve) => { runs += 1; release = () => resolve('done'); });
    const first = guard('save', task);
    const second = guard('save', task);
    expect(guard.isRunning('save')).toBe(true);
    expect(await second).toBeUndefined();
    release();
    expect(await first).toBe('done');
    expect(runs).toBe(1);
    expect(guard.isRunning('save')).toBe(false);
  });
  it('does not block another key, and frees the key after a failure', async () => {
    const guard = createGuard();
    const failing = guard('row-1', async () => { throw new Error('refused'); });
    expect(await guard('row-2', async () => 2)).toBe(2);
    await expect(failing).rejects.toThrow('refused');
    expect(await guard('row-1', async () => 1)).toBe(1);
  });
});

describe('a server function that may not exist yet', () => {
  const missing = { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } };
  it('answers with the function when it is there', async () => {
    forgetMissingFunctions();
    let fallbacks = 0;
    const answer = await rpcOr('f', async () => ({ data: { ok: 1 }, error: null }), async () => { fallbacks += 1; return { ok: 0 }; });
    expect(answer).toEqual({ ok: 1 });
    expect(fallbacks).toBe(0);
  });
  it('does the job the older way when the function is missing, and does not ask again at once', async () => {
    forgetMissingFunctions();
    let calls = 0;
    let clock = 0;
    const run = () => rpcOr('g', async () => { calls += 1; return missing; }, async () => 'older way', () => clock);
    expect(await run()).toBe('older way');
    expect(await run()).toBe('older way');
    expect(calls).toBe(1);
    // Minutes later it is asked for once more (the migration may have been applied meanwhile).
    clock = 6 * 60 * 1000;
    await run();
    expect(calls).toBe(2);
  });
  it('uses the function again as soon as it answers', async () => {
    forgetMissingFunctions();
    let clock = 0;
    let present = false;
    const run = () => rpcOr('h', async () => (present ? { data: 'new way', error: null } : missing), async () => 'older way', () => clock);
    expect(await run()).toBe('older way');
    present = true;
    clock = 6 * 60 * 1000;
    expect(await run()).toBe('new way');
    expect(await run()).toBe('new way');
  });
  it('shows any other failure as the server worded it, without falling back', async () => {
    forgetMissingFunctions();
    let fallbacks = 0;
    await expect(rpcOr('i', async () => ({ data: null, error: { code: 'P0001', message: 'غير مصرح لك بهذه الشركة.' } }),
      async () => { fallbacks += 1; return null; })).rejects.toThrow('غير مصرح لك بهذه الشركة.');
    expect(fallbacks).toBe(0);
  });
});
