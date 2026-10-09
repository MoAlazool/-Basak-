import { beforeEach, describe, expect, it } from 'vitest';
import { affectedBy, affectedByAll, nextFlushDelay, planRefresh, platformAffectedBy } from './sync';
import { appliedLists, clearApplied, forgetApplied, rememberApplied } from './recentChanges';

describe('which lists a change makes out of date', () => {
  it('follows a receipt or a subscription into every list that shows it', () => {
    expect(affectedBy({ table: 'receipts' })).toEqual(['receipts', 'overview', 'students', 'reports']);
    expect(affectedBy({ table: 'subscriptions' })).toEqual(['students', 'overview', 'reports', 'receipts']);
  });
  it('re-reads the overview for a ride confirmation only while it is open', () => {
    expect(affectedBy({ table: 'daily_ride_status' })).toEqual(['overview?']);
    expect(affectedBy({ table: 'supervisor_scan_events' })).toEqual(['overview?']);
  });
  it('ignores a table no page shows', () => {
    expect(affectedBy({ table: 'complaints' })).toEqual([]);
  });
  it('leaves alone the lists this tab already brought up to date', () => {
    expect(affectedBy({ table: 'receipts' }, ['receipts', 'overview'])).toEqual(['students', 'reports']);
    expect(affectedBy({ table: 'subscriptions' }, ['students'])).toEqual(['overview', 'reports', 'receipts']);
    expect(affectedBy({ table: 'daily_ride_status' }, ['overview'])).toEqual([]);
  });
  it('handles a burst once per list, own rows apart from other people\'s', () => {
    const own = new Set(['r1', 's1']);
    const names = affectedByAll([
      { table: 'receipts', id: 'r1' }, { table: 'subscriptions', id: 's1' }, { table: 'notifications', id: 'n1' },
    ], (id) => (id && own.has(id) ? ['receipts', 'overview'] : []));
    expect(names.sort()).toEqual(['notifications', 'reports', 'students']);
    // The same burst with someone else's receipt in it reads the queue and the numbers.
    const mixed = affectedByAll([{ table: 'receipts', id: 'r1' }, { table: 'receipts', id: 'r2' }],
      (id) => (id && own.has(id) ? ['receipts', 'overview'] : []));
    expect(mixed).toContain('receipts');
    expect(mixed).toContain('overview');
  });
});

describe('what is read now and what only on the next visit', () => {
  it('reads plain names now', () => {
    expect(planRefresh(['students', 'overview'], false)).toEqual({ now: ['students', 'overview'], later: [] });
  });
  it('postpones the overview of a ride event unless that page is open', () => {
    expect(planRefresh(['overview?'], false)).toEqual({ now: [], later: ['overview'] });
    expect(planRefresh(['overview?'], true)).toEqual({ now: ['overview'], later: [] });
  });
  it('does not postpone what something else in the burst reads now', () => {
    expect(planRefresh(['overview?', 'overview'], false)).toEqual({ now: ['overview'], later: [] });
  });
});

describe('how long a burst waits', () => {
  it('waits the delay after the latest event', () => {
    expect(nextFlushDelay(1000, 1100, 400, 2000)).toBe(400);
  });
  it('never waits past the limit counted from the first event', () => {
    expect(nextFlushDelay(1000, 2900, 400, 2000)).toBe(100);
    expect(nextFlushDelay(1000, 3500, 400, 2000)).toBe(0);
  });
});

describe('the platform admin\'s lists', () => {
  it('refreshes only what a change concerns', () => {
    expect(platformAffectedBy([{ table: 'receipts', id: 'r' }])).toEqual(['overview']);
    expect(platformAffectedBy([{ table: 'notifications', id: 'n' }])).toEqual(['notifications']);
    expect(platformAffectedBy([{ table: 'receipts', id: 'r' }, { table: 'company_students', id: 's' }])?.sort()).toEqual(['overview', 'students']);
  });
  it('refreshes everything for a table it does not know', () => {
    expect(platformAffectedBy([{ table: 'receipts', id: 'r' }, { table: 'something_new', id: 'x' }])).toBeNull();
  });
  it('skips what this tab already applied', () => {
    expect(platformAffectedBy([{ table: 'notifications', id: 'n' }], () => ['notifications'])).toEqual([]);
    expect(platformAffectedBy([{ table: 'student_correction_requests', id: 'c' }], () => ['corrections'])).toEqual(['students']);
  });
});

describe('rows this tab changed itself', () => {
  beforeEach(clearApplied);
  it('are remembered with the lists that already show them, for a while', () => {
    rememberApplied(['r1', null, undefined], ['receipts', 'overview'], 1000, 10_000);
    expect(appliedLists('r1', 5000)).toEqual(['receipts', 'overview']);
    expect(appliedLists('r1', 11_000)).toEqual([]);
    expect(appliedLists('r2', 5000)).toEqual([]);
    expect(appliedLists(null, 5000)).toEqual([]);
  });
  it('add up when the same row is changed twice', () => {
    rememberApplied(['c1'], ['settings'], 1000);
    rememberApplied(['c1'], ['switches'], 2000);
    expect([...appliedLists('c1', 3000)].sort()).toEqual(['settings', 'switches']);
  });
  it('are forgotten when the write failed, so its announcement counts again', () => {
    rememberApplied(['r1'], ['receipts'], 1000);
    forgetApplied(['r1']);
    expect(appliedLists('r1', 2000)).toEqual([]);
  });
  it('drop expired entries when new ones arrive', () => {
    rememberApplied(['old'], ['receipts'], 0, 10);
    rememberApplied(['new'], ['receipts'], 1000, 10);
    expect(appliedLists('old', 5)).toEqual([]);
  });
});
