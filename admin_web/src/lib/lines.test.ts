import { describe, expect, it } from 'vitest';
import {
  addMinutes, buildSavePayload, countOf, draftFromLine, draftIssues, emptyDraft, emptyTrip, fillStopTimes, joinAnd,
  lineVisibility, pricesText, stationsText, stepSubs, tripProblems, tripsRangeText, uncoveredUniversities, unitWord, W,
  type LineDraft, type LineLike, type StationDraft, type TripDraft,
} from './lines';

const st = (key: string, name: string): StationDraft => ({ key, name });
const route = [st('a', 'موقف الزرقا'), st('b', 'كوبري الزرقا'), st('c', 'ميت الخولي'), st('d', 'شرباص')];
const trip = (p: Partial<TripDraft>): TripDraft => ({ ...emptyTrip('departure'), ...p });
const ctx = { sold: { first: true, second: true, both: true, summer: false }, daily: true, uniName: (id: string) => ({ u1: 'جامعة دمياط', u2: 'جامعة حورس' }[id] ?? id) };

function ready(): LineDraft {
  const d = emptyDraft('co', ctx.sold);
  d.name = 'الزرقا';
  d.university_ids = ['u1'];
  d.capacity = '50';
  d.stations = route.map((s) => ({ ...s }));
  d.trips = [trip({ key: 't1', start_time: '06:15', times: fillStopTimes('06:15', 6, route) }), { ...emptyTrip('return', '13:00'), key: 'r1' }];
  d.prices.first = { enabled: true, price: 3200 };
  d.prices.second = { enabled: true, price: 3200 };
  d.prices.both = { enabled: false, price: '' };
  d.price_daily = 45;
  return d;
}

describe('minutes between stations', () => {
  it('adds minutes within the day', () => {
    expect(addMinutes('07:30', 15)).toBe('07:45');
    expect(addMinutes('07:50', 15)).toBe('08:05');
    expect(addMinutes('23:50', 30)).toBe('23:59');
  });
  it('starts at the first station and counts each station by its place on the route', () => {
    expect(fillStopTimes('07:30', 6, route)).toEqual({ a: '07:30', b: '07:36', c: '07:42', d: '07:48' });
  });
  it('leaves stations the trip skips without a time, keeping the others in their place', () => {
    expect(fillStopTimes('07:30', 6, route, new Set(['c']))).toEqual({ a: '07:30', b: '07:36', d: '07:48' });
  });
  it('treats a bad gap as no gap', () => {
    expect(fillStopTimes('07:00', Number.NaN, route.slice(0, 2))).toEqual({ a: '07:00', b: '07:00' });
  });
});

describe('timetable checks', () => {
  it('accepts stop times in route order', () => {
    expect(tripProblems(trip({ start_time: '07:30', times: { a: '07:30', b: '07:36', d: '07:48' } }), route)).toEqual([]);
  });
  it('names the station whose time is before the one before it', () => {
    const p = tripProblems(trip({ start_time: '07:30', times: { a: '07:30', b: '08:00', c: '07:50', d: '08:12' } }), route);
    expect(p).toHaveLength(1);
    expect(p[0].stationKey).toBe('c');
    expect(p[0].message).toBe('موعد «ميت الخولي» (7:50 ص) قبل محطة «كوبري الزرقا» (8:00 ص). المواعيد يجب أن تكون بترتيب المسار.');
    expect(p[0].short).toBe('موعد محطة «ميت الخولي» قبل المحطة التي قبلها.');
  });
  it('refuses a first stop before the start', () => {
    expect(tripProblems(trip({ start_time: '07:30', times: { a: '07:00' } }), route)[0].message).toContain('قبل موعد التحرك');
  });
  it('needs at least one stop time on the way there', () => {
    expect(tripProblems(trip({ start_time: '07:30', times: {} }), route)[0].field).toBe('stops');
  });
  it('needs a start time, and for a return trip nothing else', () => {
    expect(tripProblems(trip({ start_time: '' }), route)[0].field).toBe('start');
    expect(tripProblems({ ...emptyTrip('return'), start_time: '' }, route)[0].message).toBe('اكتب موعد تحرك الباص من الجامعة.');
    expect(tripProblems({ ...emptyTrip('return'), start_time: '14:00' }, route)).toEqual([]);
  });
  it('refuses an arrival before the last stop', () => {
    expect(tripProblems(trip({ start_time: '07:00', arrival_time: '07:05', times: { a: '07:00', b: '07:10' } }), route)[0].field).toBe('arrival');
  });
});

describe('what blocks the save', () => {
  it('nothing, for a complete line', () => {
    expect(draftIssues(ready(), ctx)).toEqual([]);
  });
  it('a new line starts with no price written and nothing to save', () => {
    const d = emptyDraft('co', ctx.sold);
    expect(Object.values(d.prices).every((p) => p.price === '')).toBe(true);
    expect(d.price_daily).toBe('');
    expect(d.daily_enabled).toBe(true);
    expect(d.prices.summer.enabled).toBe(false);
    const steps = new Set(draftIssues(d, ctx).map((i) => i.step));
    expect([...steps].sort()).toEqual([1, 2, 3, 4]);
  });
  it('a new line starts with what the company chose for new lines, daily included', () => {
    const d = emptyDraft('co', { first: true, second: false, both: false, summer: false }, false);
    expect(Object.fromEntries(Object.entries(d.prices).map(([o, p]) => [o, p.enabled]))).toEqual({ first: true, second: false, both: false, summer: false });
    expect(d.daily_enabled).toBe(false);
    expect(draftIssues({ ...ready(), daily_enabled: false, price_daily: '' }, ctx).filter((i) => i.step === 4)).toEqual([]);
  });
  it('an option on sale without a price, but not one the company does not sell', () => {
    const d = ready();
    d.prices.second = { enabled: true, price: '' };
    d.prices.summer = { enabled: true, price: '' };
    expect(draftIssues(d, ctx).map((i) => i.message)).toEqual(['الفصل الثاني مفتوح للبيع وبلا سعر.']);
  });
  it('a university with no departure trip', () => {
    const d = ready();
    d.university_ids = ['u1', 'u2'];
    d.trips[0].university_id = 'u1';
    expect(uncoveredUniversities(d)).toEqual(['u2']);
    expect(draftIssues(d, ctx).map((i) => i.message)).toContain('لا رحلة ذهاب إلى جامعة حورس: اجعل رحلة «لكل جامعات الخط» أو أضف رحلة لها.');
  });
  it('a return time with no time, two trips at the same time, a trip out of order', () => {
    const d = ready();
    d.trips.push({ ...emptyTrip('return', ''), key: 'r2' });
    d.trips.push(trip({ key: 't2', start_time: '06:15', times: { a: '06:15' } }));
    d.trips.push(trip({ key: 't3', start_time: '07:30', times: { a: '07:30', b: '07:20' } }));
    const msgs = draftIssues(d, ctx).map((i) => i.message);
    expect(msgs).toContain('موعد العودة: موعد عودة بلا وقت.');
    expect(msgs).toContain('رحلتان في 6:15 ص لنفس الجامعة. احذف إحداهما أو غيّر موعدها.');
    expect(msgs).toContain('رحلة 7:30 ص: موعد محطة «كوبري الزرقا» قبل المحطة التي قبلها.');
  });
  it('bus seats out of range and an empty station name', () => {
    const d = ready();
    d.capacity = '600';
    d.stations[1].name = ' ';
    expect(draftIssues(d, ctx).map((i) => i.step)).toEqual([1, 2]);
  });
  it('the daily price only when the company sells the daily ride and it is on for the line', () => {
    const d = ready();
    d.price_daily = '';
    expect(draftIssues(d, ctx).map((i) => i.message)).toEqual(['اليومي (نقداً في الباص) مفتوح للبيع وبلا سعر.']);
    expect(draftIssues(d, { ...ctx, daily: false })).toEqual([]);
    expect(draftIssues({ ...d, daily_enabled: false }, ctx)).toEqual([]);
  });
});

describe('the save payload', () => {
  it('carries the whole line, stop times by place on the route, and prices only where written', () => {
    const d = ready();
    d.trips[0].times = { a: '06:15', c: '06:27' };
    const p = buildSavePayload(d);
    expect(p.id).toBeNull();
    expect(p.bus_capacity).toBe(50);
    expect(p.stations).toEqual(route.map((s) => ({ id: null, name: s.name })));
    expect(p.trips[0].stops).toEqual([{ station_index: 0, time: '06:15' }, { station_index: 2, time: '06:27' }]);
    expect(p.trips[1]).toMatchObject({ direction: 'return', stops: [], arrival_time: null, university_id: null });
    expect(p.prices).toEqual([
      { option: 'first', price: 3200, is_enabled: true }, { option: 'second', price: 3200, is_enabled: true },
      { option: 'both', price: null, is_enabled: false }, { option: 'summer', price: null, is_enabled: false },
    ]);
    expect(p).toMatchObject({ price_termly: 3200, price_yearly: 0, price_daily: 45, destination_university_id: null, origin_name: '' });
  });
  it('daily switched off saves the line with no daily price, whatever was typed', () => {
    const d = { ...ready(), daily_enabled: false };
    expect(buildSavePayload(d).price_daily).toBe(0);
    expect(pricesText(d)).toBe('الأول 3,200 ج.م · الثاني 3,200 ج.م');
    expect(buildSavePayload({ ...d, daily_enabled: true }).price_daily).toBe(45);
  });
  it('keeps the line id once known, so a second save edits instead of adding a line', () => {
    const d = { ...ready(), id: 'line-1' };
    expect(buildSavePayload(d).id).toBe('line-1');
    // An edit never switches the line on or off: a stale copy cannot revive or stop it.
    expect('is_active' in buildSavePayload(d)).toBe(false);
    expect(buildSavePayload(ready()).is_active).toBe(true);
  });
  it('an empty seats field clears the capacity; an option switched on with no price is sent off', () => {
    const d = ready();
    d.capacity = '';
    d.prices.summer = { enabled: true, price: '' };
    const p = buildSavePayload(d);
    expect(p.bus_capacity).toBeNull();
    expect(p.prices[3]).toEqual({ option: 'summer', price: null, is_enabled: false });
  });
});

const saved: LineLike = {
  id: 'L', name: 'الزرقا', company_id: 'co', is_active: true, price_daily: 45,
  stations: [{ id: 's2', name: 'ب', order_index: 2, is_active: true }, { id: 's1', name: 'أ', order_index: 1, is_active: true }, { id: 's0', name: 'قديمة', order_index: 10003, is_active: false }],
  line_trips: [
    { id: 'r', direction: 'return', label: null, start_time: '14:00:00', arrival_time: null, university_id: null, is_active: true, line_trip_stops: [] },
    { id: 'd', direction: 'departure', label: 'أول رحلة', start_time: '06:15:00', arrival_time: '07:22:00', university_id: 'u1', is_active: true, line_trip_stops: [{ station_id: 's1', stop_time: '06:15:00' }] },
    { id: 'x', direction: 'departure', label: '', start_time: '09:00:00', arrival_time: null, university_id: null, is_active: false, line_trip_stops: [] },
  ],
  line_universities: [{ university_id: 'u1' }],
  line_period_prices: [{ option: 'first', price: 3200, is_enabled: true }, { option: 'summer', price: 0, is_enabled: false }],
};

describe('a saved line as a draft', () => {
  it('keeps active stations in route order, active trips, ids, and no invented prices', () => {
    const d = draftFromLine(saved, 50);
    expect(d.stations.map((s) => s.id)).toEqual(['s1', 's2']);
    expect(d.trips.map((t) => t.id)).toEqual(['d', 'r']);
    expect(d.trips[0]).toMatchObject({ start_time: '06:15', arrival_time: '07:22', times: { s1: '06:15' } });
    expect(d.prices.first).toEqual({ enabled: true, price: 3200 });
    expect(d.prices.second).toEqual({ enabled: false, price: '' });
    expect(d.prices.summer).toEqual({ enabled: false, price: '' });
    expect(d.capacity).toBe('50');
    expect([d.price_daily, d.daily_enabled]).toEqual([45, true]);
  });
  it('a line with no daily price opens with daily switched off', () => {
    const d = draftFromLine({ ...saved, price_daily: 0 }, 50);
    expect([d.price_daily, d.daily_enabled]).toEqual(['', false]);
    expect(draftIssues(d, ctx).filter((i) => i.step === 4)).toEqual([]);
  });
});

describe('can students see it', () => {
  const o = { daily: true, uniName: (id: string) => (id === 'u1' ? 'جامعة دمياط' : 'جامعة حورس') };
  it('yes, when it runs, has a trip for each university and a price', () => {
    expect(lineVisibility(saved, o)).toEqual({ state: 'on' });
  });
  it('a stopped line', () => {
    expect(lineVisibility({ ...saved, is_active: false }, o).state).toBe('off');
  });
  it('says what is missing and which step fixes it', () => {
    expect(lineVisibility({ ...saved, line_universities: [{ university_id: 'u1' }, { university_id: 'u2' }] }, o))
      .toEqual({ state: 'hidden', reason: 'تنقصه رحلة ذهاب إلى جامعة حورس', fix: 'أضف رحلة', step: 3 });
    expect(lineVisibility({ ...saved, line_period_prices: [], price_daily: 0 }, o)).toMatchObject({ reason: 'لم يُكتب سعر لأي اشتراك', step: 4 });
    expect(lineVisibility({ ...saved, line_universities: [] }, o)).toMatchObject({ reason: 'لم تُحدد له جامعة', step: 1 });
  });
});

describe('words', () => {
  it('counts the Arabic way', () => {
    expect(unitWord(1, W.student)).toBe('طالب');
    expect(unitWord(5, W.rider)).toBe('ركاب');
    expect(unitWord(124, W.student)).toBe('طالباً');
    expect(countOf(8, W.station)).toBe('8 محطات');
    expect(countOf(2, W.station)).toBe('محطتان');
    expect(countOf(1, W.trip)).toBe('رحلة واحدة');
  });
  it('joins names', () => {
    expect(joinAnd(['جامعة دمياط', 'جامعة حورس'])).toBe('جامعة دمياط وجامعة حورس');
    expect(joinAnd(['أ', 'ب', 'ج'])).toBe('أ، ب وج');
  });
  it('summarises the draft', () => {
    const d = ready();
    d.university_ids = ['u1', 'u2'];
    expect(stepSubs(d)).toEqual({ 1: 'الزرقا · جامعتان · 50 مقعداً', 2: '4 محطات', 3: '1 ذهاب · 1 عودة', 4: '3 أسعار' });
    expect(stationsText(d)).toBe('4 محطات: من موقف الزرقا إلى شرباص');
    expect(tripsRangeText(d, 'departure')).toBe('رحلة واحدة: 6:15 ص');
    expect(pricesText(d)).toBe('الأول 3,200 ج.م · الثاني 3,200 ج.م · اليومي 45 ج.م');
  });
});

describe('typing a time', () => {
  it('reads what admins type', async () => {
    const { parseClock } = await import('./lines');
    expect(parseClock('7:30 ص')).toBe('07:30');
    expect(parseClock('7:30 م')).toBe('19:30');
    expect(parseClock('19:30')).toBe('19:30');
    expect(parseClock('٧:٣٠ م')).toBe('19:30');
    expect(parseClock('730')).toBe('07:30');
    expect(parseClock('7.30pm')).toBe('19:30');
    expect(parseClock('12:00 ص')).toBe('00:00');
    expect(parseClock('2:00')).toBe('14:00');
    expect(parseClock('2:00', 'am')).toBe('02:00');
    expect(parseClock('07:00')).toBe('07:00');
    expect(parseClock('')).toBe('');
    expect(parseClock('25:00')).toBeNull();
    expect(parseClock('7:75')).toBeNull();
    expect(parseClock('صباحاً')).toBeNull();
  });
});

describe('editing a line in use', () => {
  it('counts what changed and lists what reaches students', async () => {
    const { changeCount, editEffects, unsavedText, typedSummary } = await import('./lines');
    const saved = draftFromLine(saved0(), 50);
    const d: LineDraft = JSON.parse(JSON.stringify(saved));
    expect(changeCount(saved, d)).toBe(0);
    d.trips[0].times = { s1: '06:20' };
    d.stations = d.stations.filter((s) => s.id !== 's2');
    expect(changeCount(saved, d)).toBe(2);
    expect(unsavedText(2)).toBe('تعديلان لم يُحفظا');
    expect(editEffects(saved, d, { s2: 14 }, { d: 38 })).toEqual([
      { kind: 'times', trip: '06:15', stations: 1, students: 38 },
      { kind: 'station', name: 'ب', students: 14 },
    ]);
    const n = emptyDraft('co');
    n.name = 'الزرقا';
    n.stations = route.map((s) => ({ ...s }));
    n.trips = [trip({}), trip({})];
    expect(typedSummary(n)).toBe('الاسم، 4 محطات ورحلتان');
  });
});
function saved0(): LineLike { return saved; }
