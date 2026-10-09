import { describe, expect, it } from 'vitest';
import {
  audienceFromSpec, audienceToPayload, draftProblem, emptyDraft, idempotencyKeyFor, isDirty, platformCompanyIds, rideDayLabel,
  scheduleProblem, withCancelled, withoutRow, type HistoryRow,
} from './notifications';
import { addDays, cairoLocalToIso, cairoToday, clockLabel, formatCairo, hhmm, isDay, isoToCairoLocal } from './time';
import { toAdminProfile } from './adminProfile';
import { activeStations, toLineOptions, type LineRow, type UniversityRow } from './reference';

describe('the key that makes a notification go out once', () => {
  let made = 0;
  const generate = () => `key-${++made}`;

  it('does not exist while the form is clean', () => {
    expect(idempotencyKeyFor(null, false, generate)).toBeNull();
  });
  it('appears when the form becomes dirty and stays the same through retries and double clicks', () => {
    const first = idempotencyKeyFor(null, true, generate);
    expect(first).toBe(`key-${made}`);
    expect(idempotencyKeyFor(first, true, generate)).toBe(first);
    expect(idempotencyKeyFor(first, true, generate)).toBe(first);
  });
  it('is dropped when the form is clean again, and the next notification gets a new one', () => {
    const first = idempotencyKeyFor(null, true, generate);
    expect(idempotencyKeyFor(first, false, generate)).toBeNull();
    const second = idempotencyKeyFor(null, true, generate);
    expect(second).not.toBe(first);
  });
  it('follows the draft: a title or a text makes it dirty, blanks do not', () => {
    const draft = emptyDraft('2026-10-09');
    expect(isDirty(draft)).toBe(false);
    expect(isDirty({ ...draft, title: '   ' })).toBe(false);
    expect(isDirty({ ...draft, body: 'نص' })).toBe(true);
  });
  it('generates a different key each time by default', () => {
    expect(idempotencyKeyFor(null, true)).not.toBe(idempotencyKeyFor(null, true));
  });
});

describe('Cairo time', () => {
  it('names the calendar day in Cairo, not in UTC', () => {
    // 22:30 UTC is already the next day in Cairo (UTC+3 in summer, UTC+2 in winter).
    expect(cairoToday(new Date('2026-07-01T22:30:00Z'))).toBe('2026-07-02');
    expect(cairoToday(new Date('2026-01-15T22:30:00Z'))).toBe('2026-01-16');
    expect(cairoToday(new Date('2026-01-15T21:30:00Z'))).toBe('2026-01-15');
  });
  it('turns Cairo wall time into the instant, with the offset of that day', () => {
    expect(cairoLocalToIso('2026-01-15T09:00')).toBe('2026-01-15T07:00:00.000Z');   // winter, UTC+2
    expect(cairoLocalToIso('2026-07-15T09:00')).toBe('2026-07-15T06:00:00.000Z');   // summer, UTC+3
  });
  it('goes there and back without drift, in both seasons', () => {
    for (const local of ['2026-01-15T00:05', '2026-07-15T23:55', '2026-10-09T12:00', '2026-12-31T23:59']) {
      expect(isoToCairoLocal(cairoLocalToIso(local)!)).toBe(local);
    }
  });
  it('refuses what is not a date and time', () => {
    expect(cairoLocalToIso('')).toBeNull();
    expect(cairoLocalToIso('tomorrow')).toBeNull();
    expect(isoToCairoLocal('not a date')).toBe('');
    expect(formatCairo(null)).toBe('');
    expect(formatCairo('not a date')).toBe('');
  });
  it('adds days across months and years', () => {
    expect(addDays('2026-10-31', 1)).toBe('2026-11-01');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });
  it('reads clock times', () => {
    expect(hhmm('07:30:00')).toBe('07:30');
    expect(hhmm(null)).toBe('');
    expect(clockLabel('07:30:00')).toBe('7:30 ص');
    expect(clockLabel('12:00')).toBe('12:00 م');
    expect(clockLabel('00:05')).toBe('12:05 ص');
    expect(clockLabel('16:45:00')).toBe('4:45 م');
    expect(clockLabel('')).toBe('');
    expect(clockLabel('??')).toBe('');
    expect(isDay('2026-10-09')).toBe(true);
    expect(isDay('9/10/2026')).toBe(false);
  });
  it('accepts a send time only in the future, whatever the browser\'s zone', () => {
    const now = new Date('2026-10-09T10:00:00Z');   // 13:00 in Cairo
    expect(scheduleProblem('2026-10-09T12:59', now)).not.toBe('');
    expect(scheduleProblem('2026-10-09T13:00', now)).not.toBe('');
    expect(scheduleProblem('2026-10-09T13:01', now)).toBe('');
    expect(scheduleProblem('', now)).not.toBe('');
  });
  it('words a ride day', () => {
    expect(rideDayLabel('2026-10-09', '2026-10-09')).toBe('اليوم');
    expect(rideDayLabel('2026-10-10', '2026-10-09')).toBe('غداً');
    expect(rideDayLabel('2026-10-12', '2026-10-09')).not.toMatch(/اليوم|غداً/);
  });
});

describe('who a notification is for', () => {
  const today = '2026-10-09';
  const base = emptyDraft(today).audience;
  it('sends only the choice, and nothing while it is incomplete', () => {
    expect(audienceToPayload(base)).toEqual({ kind: 'company' });
    expect(audienceToPayload({ ...base, kind: 'line' })).toBeNull();
    expect(audienceToPayload({ ...base, kind: 'line', lineId: 'l1' })).toEqual({ kind: 'line', line_id: 'l1' });
    expect(audienceToPayload({ ...base, kind: 'trip', lineId: 'l1' })).toBeNull();
    expect(audienceToPayload({ ...base, kind: 'trip', lineId: 'l1', tripId: 't1' })).toEqual({ kind: 'trip', line_id: 'l1', trip_id: 't1', ride_date: today });
    expect(audienceToPayload({ ...base, kind: 'trip', lineId: 'l1', tripId: 't1', rideDate: 'x' })).toBeNull();
    expect(audienceToPayload({ ...base, kind: 'university', universityId: 'u1' })).toEqual({ kind: 'university', university_id: 'u1' });
  });
  it('reads a stored audience back into the picker', () => {
    for (const spec of [{ kind: 'line', line_id: 'l1' }, { kind: 'trip', line_id: 'l1', trip_id: 't1', ride_date: '2026-10-10' }, { kind: 'university', university_id: 'u1' }, { kind: 'company' }] as const) {
      expect(audienceToPayload(audienceFromSpec(spec, today))).toEqual(spec);
    }
    expect(audienceFromSpec(null, today)).toEqual(base);
  });
  it('says what stops a draft from being sent', () => {
    const draft = { ...emptyDraft(today), title: 'عنوان', body: 'نص' };
    expect(draftProblem(draft)).toBe('');
    expect(draftProblem({ ...draft, title: ' ' })).not.toBe('');
    expect(draftProblem({ ...draft, title: 'ع'.repeat(81) })).not.toBe('');
    expect(draftProblem({ ...draft, audience: { ...draft.audience, kind: 'university' } })).toBe('اختر الجامعة.');
    expect(draftProblem({ ...draft, when: 'later', scheduledLocal: '2026-10-09T12:00' }, new Date('2026-10-09T10:00:00Z'))).not.toBe('');
  });
  it('orders the chosen companies the same way every time', () => {
    expect(platformCompanyIds(true, ['b', 'a'])).toBeNull();
    expect(platformCompanyIds(false, ['b', 'a'])).toEqual(['a', 'b']);
  });
});

describe('a cancelled or deleted notification on screen', () => {
  const rows = [{ id: 'n1', status: 'scheduled' }, { id: 'n2', status: 'sent' }] as HistoryRow[];
  it('leaves the scheduled list and is marked in the others', () => {
    expect(withCancelled(rows, 'n1', 'scheduled').map((r) => r.id)).toEqual(['n2']);
    expect(withCancelled(rows, 'n1', 'all').map((r) => r.status)).toEqual(['cancelled', 'sent']);
  });
  it('disappears when deleted', () => {
    expect(withoutRow(rows, 'n2').map((r) => r.id)).toEqual(['n1']);
  });
});

describe('lookups in the shape the pages use', () => {
  it('reads an admin with the company embedded as an object or as a list of one', () => {
    const row = { id: 'a1', email: 'a@b.c', full_name: 'مدير', role: 'company_admin', company_id: 'c1' };
    const company = { id: 'c1', name: 'شركة', status: 'active' };
    expect(toAdminProfile({ ...row, companies: company })).toEqual({ profile: { ...row, companyName: 'شركة' }, company });
    expect(toAdminProfile({ ...row, companies: [company] }).company).toEqual(company);
    expect(toAdminProfile({ ...row, role: 'super_admin', company_id: null, companies: null })).toMatchObject({ company: null, profile: { companyName: null } });
  });
  it('offers the forms only what is in use', () => {
    const universities = [{ id: 'u1', name: 'أ', is_active: true }, { id: 'u2', name: 'ب', is_active: false }] as UniversityRow[];
    const lines = [{ id: 'l1', is_active: true }, { id: 'l2', is_active: false }] as LineRow[];
    const options = toLineOptions(universities, lines);
    expect(options.universities).toEqual([{ id: 'u1', name: 'أ' }]);
    expect(options.lines.map((line) => line.id)).toEqual(['l1']);
  });
  it('lists a line\'s stations in route order, without the retired ones', () => {
    const stations = [{ id: 's2', order_index: 2, is_active: true }, { id: 's3', order_index: 3, is_active: false }, { id: 's1', order_index: 1, is_active: true }];
    expect(activeStations({ stations }).map((s) => s.id)).toEqual(['s1', 's2']);
    expect(activeStations(undefined)).toEqual([]);
  });
});
