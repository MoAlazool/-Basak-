import { describe, expect, it } from 'vitest';
import {
  COMMITTED, audienceDraftOf, audienceKey, audienceProblems, audienceSpecOf, audienceSummary, categoryLabel, checkPictureDimensions, checkPictureFile,
  collegeOptions, emptyAudience, emptyMerchant, emptyOffer, isCommitted, isPicturePath, keepLinesOf, kindLabel, merchantDraftOf, merchantPayload,
  merchantProblems, nameMap, newPicturePath, offerActions, offerDraftOf, offerPayload, offerProblems, offerState, periodText, phoneDigits, pictureUrl,
  rate, rateText, reachText, statsRates, specialNotice, statsSheets, storedPictureSize,
  type AudienceDraft, type Merchant, type Offer, type OfferDraft, type OfferStats,
} from './offers';
import { GENERAL_COLLEGES } from './colleges';

const M = '11111111-1111-4111-8111-111111111111';
const O = '22222222-2222-4222-8222-222222222222';
const U1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const U2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const NOW = Date.parse('2026-10-11T10:00:00Z');

const audience = (o: Partial<AudienceDraft> = {}): AudienceDraft => ({ ...emptyAudience(), ...o });
const merchant = (o: Partial<Merchant> = {}): Merchant => ({
  id: M, name: 'كافيه الجامعة', category: 'food', logo_path: null, phone: '01012345678', whatsapp: null, link_url: null, address: null,
  university_id: null, notes: null, is_active: true, offers: 2, ...o,
});
const offer = (o: Partial<Offer> = {}): Offer => ({
  id: O, merchant_id: M, merchant_name: 'كافيه الجامعة', title: 'خصم على المشروبات', description: '', terms: '', image_path: null, kind: 'percent',
  value_label: '20%', starts_at: '2026-10-01T07:00:00Z', ends_at: '2026-10-31T20:59:00Z', status: 'live', running: true, audience: {}, special: false,
  per_student_limit: 1, total_limit: null, coupon_minutes: 10, has_pin: true, sort: 0, price: 1500, internal_note: null, published_at: '2026-10-01T07:00:00Z',
  seen: 120, opened: 60, redeemed: 12, ...o,
});
const draft = (o: Partial<OfferDraft> = {}): OfferDraft => ({ ...emptyOffer(O, new Date(NOW)), merchantId: M, title: 'خصم على المشروبات', valueLabel: '20%', ...o });

describe('words', () => {
  it('names a category and a kind, and falls back for one it does not know', () => {
    expect(categoryLabel('study')).toBe('أدوات دراسية');
    expect(categoryLabel('new-one')).toBe('أخرى');
    expect(kindLabel('info')).toBe('إعلان');
  });
});

describe('an offer\'s state', () => {
  it('is its status while students can see it, or when it is not published', () => {
    expect(offerState(offer(), true, NOW).label).toBe('منشور');
    expect(offerState(offer({ status: 'draft', running: false }), true, NOW).label).toBe('مسودة');
    expect(offerState(offer({ status: 'paused', running: false }), true, NOW).label).toBe('موقوف');
    expect(offerState(offer({ status: 'ended', running: false }), true, NOW).label).toBe('منتهٍ');
  });
  it('says why a published offer is not shown', () => {
    expect(offerState(offer({ running: false, ends_at: '2026-10-05T00:00:00Z' }), true, NOW).key).toBe('expired');
    expect(offerState(offer({ running: false, ends_at: '2026-10-05T00:00:00Z' }), undefined, NOW).label).toBe('انتهت مدته');
    expect(offerState(offer({ running: false, starts_at: '2026-11-01T00:00:00Z' }), true, NOW).key).toBe('upcoming');
    expect(offerState(offer({ running: false }), false, NOW).key).toBe('merchantOff');
  });
  it('offers the actions that fit the status', () => {
    expect(offerActions('draft')).toEqual({ publish: true, pause: false, end: false });
    expect(offerActions('live')).toEqual({ publish: false, pause: true, end: true });
    expect(offerActions('paused')).toEqual({ publish: true, pause: false, end: true });
    expect(offerActions('ended')).toEqual({ publish: true, pause: false, end: false });
  });
  it('writes its period in Cairo days', () => {
    expect(periodText('2026-10-01T07:00:00Z', '2026-10-31T20:59:00Z')).toBe('1 أكتوبر – 31 أكتوبر 2026');
    expect(periodText('2026-12-20T07:00:00Z', '2027-01-05T07:00:00Z')).toBe('20 ديسمبر 2026 – 5 يناير 2027');
    expect(periodText('2026-10-01T07:00:00Z', null)).toBe('من 1 أكتوبر 2026 · بلا نهاية');
    // 22:30 UTC is already the next day in Cairo.
    expect(periodText('2026-10-01T22:30:00Z', null)).toBe('من 2 أكتوبر 2026 · بلا نهاية');
  });
  it('knows when publishing a special offer tells its audience', () => {
    expect(specialNotice(offer({ special: true }), NOW)).toBe('now');
    expect(specialNotice(offer({ special: true, starts_at: '2026-11-01T00:00:00Z' }), NOW)).toBe('atStart');
    expect(specialNotice(offer({ special: false }), NOW)).toBe('no');
  });
});

describe('numbers', () => {
  it('gives a whole percentage, or nothing when there is nothing to divide by', () => {
    expect(rate(60, 120)).toBe(50);
    expect(rate(1, 3)).toBe(33);
    expect(rate(0, 0)).toBeNull();
    expect(rateText(60, 120)).toBe('50%');
    expect(rateText(5, 0)).toBe('—');
  });
  it('takes each rate of the step before it', () => {
    expect(statsRates({ reach: 400, seen: 120, opened: 60, students_redeemed: 12 })).toEqual({ seen: 30, opened: 50, redeemed: 10 });
    expect(statsRates({ reach: 0, seen: 0, opened: 0, students_redeemed: 0 })).toEqual({ seen: null, opened: null, redeemed: null });
  });
  it('says the reach as a sentence', () => {
    expect(reachText(1240)).toBe('يصل إلى 1,240 طالباً الآن');
    expect(reachText(1)).toBe('يصل إلى طالب الآن');
    expect(reachText(0)).toBe('لا يصل إلى أي طالب الآن');
    expect(reachText(null)).toBe('');
  });
});

describe('the audience', () => {
  it('leaves out what is empty, as the server stores it', () => {
    expect(audienceSpecOf(audience())).toEqual({});
    expect(audienceSpecOf(audience({ colleges: [' الهندسة ', 'الهندسة', ''], subscription: 'any', minRides: 0, windowDays: 60 })))
      .toEqual({ colleges: ['الهندسة'], subscription: 'any' });
  });
  it('sends the window only with a commitment, 30 days when none is typed', () => {
    expect(audienceSpecOf(audience({ minRides: 8, minAttendance: 80 }))).toEqual({ min_rides: 8, min_attendance: 80, window_days: 30 });
    expect(audienceSpecOf(audience({ minAttendance: 50, windowDays: '' }))).toEqual({ min_attendance: 50, window_days: 30 });
    expect(audienceSpecOf(audience({ minRides: 3, windowDays: 14 }))).toEqual({ min_rides: 3, window_days: 14 });
  });
  it('gives one key to the same audience however it was chosen', () => {
    const a = audienceSpecOf(audience({ universityIds: [U2, U1], colleges: ['الطب', 'الهندسة'] }));
    const b = audienceSpecOf(audience({ colleges: ['الهندسة', 'الطب'], universityIds: [U1, U2, U1] }));
    expect(audienceKey(a)).toBe(audienceKey(b));
    expect(audienceKey(a)).not.toBe(audienceKey(audienceSpecOf(audience({ universityIds: [U1] }))));
  });
  it('reads a stored spec back into the form', () => {
    const spec = { university_ids: [U1], colleges: ['الهندسة'], min_rides: 8, min_attendance: 80, window_days: 30 };
    expect(audienceSpecOf(audienceDraftOf(spec))).toEqual(spec);
    expect(audienceDraftOf(null)).toEqual(emptyAudience());
    expect(audienceDraftOf({ subscription: 'any' }).subscription).toBe('any');
  });
  it('says what the server would refuse', () => {
    expect(audienceProblems(audience({ minRides: 8, minAttendance: 80 }))).toEqual({});
    expect(audienceProblems(audience({ minRides: 201 })).minRides).toBeTruthy();
    expect(audienceProblems(audience({ minAttendance: 101 })).minAttendance).toBeTruthy();
    expect(audienceProblems(audience({ minRides: 4, windowDays: 3 })).windowDays).toBeTruthy();
    expect(audienceProblems(audience({ minRides: 4, windowDays: 121 })).windowDays).toBeTruthy();
    // No commitment asked for: the window is not sent, so it is not checked.
    expect(audienceProblems(audience({ windowDays: 3 }))).toEqual({});
  });
  it('knows the «ملتزم» preset', () => {
    expect(isCommitted(COMMITTED)).toBe(true);
    expect(isCommitted({ min_rides: 8, min_attendance: 80 })).toBe(true);
    expect(isCommitted({ min_rides: 8, min_attendance: 70, window_days: 30 })).toBe(false);
    expect(isCommitted({})).toBe(false);
  });
  it('drops the lines of a company that is no longer chosen', () => {
    const lines = [{ id: 'l1', company_id: 'c1' }, { id: 'l2', company_id: 'c2' }];
    expect(keepLinesOf(['l1', 'l2'], lines, ['c1'])).toEqual(['l1']);
    expect(keepLinesOf(['l1', 'l2'], lines, [])).toEqual([]);
  });
  it('lists the colleges of the chosen universities, then the general ones, each once', () => {
    const rows = [{ university_id: U1, name: 'الهندسة' }, { university_id: U1, name: 'العمارة' }, { university_id: U2, name: 'طب الفم' }];
    const one = collegeOptions(rows, [U1], ['كلية خاصة']);
    expect(one.slice(0, 2).sort()).toEqual(['العمارة', 'الهندسة']);
    expect(one).not.toContain('طب الفم');
    expect(one.filter((c) => c === 'الهندسة')).toHaveLength(1);
    expect(one).toContain('كلية خاصة');
    expect(one).toHaveLength(GENERAL_COLLEGES.length + 2);
    expect(collegeOptions(rows, [])).toContain('طب الفم');
  });
});

describe('the audience in one line', () => {
  const names = { universities: nameMap([{ id: U1, name: 'جامعة الدلتا' }, { id: U2, name: 'جامعة حورس' }], (u) => u.id, (u) => u.name) };
  it('reads as the admin would say it', () => {
    expect(audienceSummary({ colleges: ['الهندسة'], university_ids: [U1], ...COMMITTED }, names)).toBe('طلاب الهندسة · جامعة الدلتا · ملتزمون');
  });
  it('names everyone when nothing is chosen', () => {
    expect(audienceSummary({})).toBe('كل المشتركين حالياً');
    expect(audienceSummary(null)).toBe('كل المشتركين حالياً');
    expect(audienceSummary({ subscription: 'any' })).toBe('كل الطلاب');
  });
  it('shortens a long list and counts ids it cannot name', () => {
    expect(audienceSummary({ colleges: ['كلية الهندسة', 'الطب', 'الصيدلة', 'العلوم'] })).toBe('طلاب الهندسة، الطب +2');
    expect(audienceSummary({ university_ids: [U1, U2] }, names)).toBe('كل المشتركين حالياً · جامعة الدلتا، جامعة حورس');
    expect(audienceSummary({ university_ids: [U1, 'unknown', 'other'] }, names)).toBe('كل المشتركين حالياً · 3 جامعات');
    expect(audienceSummary({ line_ids: ['l1'] })).toBe('كل المشتركين حالياً · خط واحد');
  });
  it('spells out a commitment that is not the preset', () => {
    expect(audienceSummary({ min_rides: 4, window_days: 14 })).toBe('كل المشتركين حالياً · 4 أيام ركوب على الأقل في آخر 14 يوماً');
    expect(audienceSummary({ min_attendance: 60, window_days: 30, colleges: ['الطب'], subscription: 'any' }))
      .toBe('طلاب الطب · مشتركون وغير مشتركين · حضور 60% على الأقل في آخر 30 يوماً');
  });
});

describe('pictures', () => {
  it('builds a path the bucket accepts, different every time', () => {
    const path = newPicturePath('offers', O.toUpperCase(), 'webp', 1_760_000_000_000, 0.5);
    expect(path).toMatch(new RegExp(`^offers/${O}/[a-z0-9]{6,}\\.webp$`));
    expect(isPicturePath(path, 'offers', O)).toBe(true);
    expect(newPicturePath('offers', O, 'webp', 1, 0.1)).not.toBe(newPicturePath('offers', O, 'webp', 2, 0.1));
    expect(newPicturePath('merchants', M, 'jpg', 1, 0)).toBe(`merchants/${M}/10000.jpg`);
  });
  it('takes only a picture of that folder and that row', () => {
    expect(isPicturePath(`merchants/${M}/logo.webp`)).toBe(true);
    expect(isPicturePath(`merchants/${M}/logo.webp`, 'offers')).toBe(false);
    expect(isPicturePath(`merchants/${M}/logo.webp`, 'merchants', O)).toBe(false);
    expect(isPicturePath(`merchants/${M}/logo.svg`)).toBe(false);
    expect(isPicturePath(`merchants/${M}/../x.png`)).toBe(false);
    expect(isPicturePath(`merchants/${M}/a/b.png`)).toBe(false);
    expect(isPicturePath(`https://example.com/merchants/${M}/logo.png`)).toBe(false);
    expect(isPicturePath(null)).toBe(false);
  });
  it('builds the public address from a stored path only', () => {
    expect(pictureUrl(`offers/${O}/a.webp`, 'https://x.supabase.co/')).toBe(`https://x.supabase.co/storage/v1/object/public/offer-assets/offers/${O}/a.webp`);
    expect(pictureUrl('https://evil.example/a.png', 'https://x.supabase.co')).toBeNull();
    expect(pictureUrl(null)).toBeNull();
  });
  it('refuses SVG, other types, empty and huge files', () => {
    expect(checkPictureFile({ type: 'image/svg+xml', size: 100 })).toMatch(/SVG/);
    expect(checkPictureFile({ type: 'application/pdf', size: 100 })).toBeTruthy();
    expect(checkPictureFile({ type: 'image/png', size: 0 })).toBeTruthy();
    expect(checkPictureFile({ type: 'image/jpeg', size: 13 * 1024 * 1024 })).toBeTruthy();
    expect(checkPictureFile({ type: 'image/webp', size: 4 * 1024 * 1024 })).toBeNull();
  });
  it('keeps the shape and only makes a picture smaller', () => {
    expect(storedPictureSize('offers', 3200, 1600)).toEqual({ width: 1600, height: 800 });
    expect(storedPictureSize('offers', 800, 600)).toEqual({ width: 800, height: 600 });
    expect(storedPictureSize('merchants', 1024, 2048)).toEqual({ width: 256, height: 512 });
    expect(checkPictureDimensions('merchants', 64, 64)).toBeTruthy();
    expect(checkPictureDimensions('offers', 1200, 200)).toBeNull();
    expect(checkPictureDimensions('offers', 0, 0)).toBeTruthy();
  });
});

describe('a merchant in the form', () => {
  it('asks for a name and checks the numbers and the link', () => {
    expect(merchantProblems(emptyMerchant(M)).name).toBeTruthy();
    const d = { ...merchantDraftOf(merchant()), phone: '٠١٠ ١٢٣٤-٥٦٧٨', whatsapp: 'abc', linkUrl: 'http://cafe.example' };
    const p = merchantProblems(d);
    expect(p.name).toBeUndefined();
    expect(p.phone).toBeUndefined();
    expect(p.whatsapp).toBeTruthy();
    expect(p.linkUrl).toBe('الرابط يجب أن يبدأ بـ https://');
    expect(merchantProblems({ ...d, whatsapp: '+201012345678', linkUrl: 'https://cafe.example/menu' })).toEqual({});
  });
  it('writes numbers as they are dialled', () => {
    expect(phoneDigits('٠١٠ ١٢٣٤-٥٦٧٨')).toBe('01012345678');
    expect(phoneDigits('+20 (10) 1234 5678')).toBe('+201012345678');
  });
  it('sends what the server takes, with the picture it is told', () => {
    const d = { ...merchantDraftOf(merchant({ university_id: U1, notes: ' ملاحظة ' })), name: '  كافيه   الجامعة ' };
    expect(merchantPayload(d, `merchants/${M}/a.webp`)).toEqual({
      id: M, name: 'كافيه الجامعة', category: 'food', logo_path: `merchants/${M}/a.webp`, phone: '01012345678', whatsapp: '', link_url: '',
      address: '', university_id: U1, notes: 'ملاحظة', is_active: true,
    });
    expect(merchantPayload(d, null).logo_path).toBe('');
  });
});

describe('an offer in the form', () => {
  it('starts as a coupon for one use, with no end', () => {
    const d = emptyOffer(O, new Date('2026-10-11T10:00:00Z'));
    expect(d).toMatchObject({ isNew: true, kind: 'percent', perStudentLimit: 1, totalLimit: '', couponMinutes: 10, endsLocal: '', startsLocal: '2026-10-11T13:00' });
  });
  it('accepts a complete draft', () => {
    expect(offerProblems(draft())).toEqual({});
  });
  it('says what is missing or out of range', () => {
    const p = offerProblems(draft({ merchantId: '', title: ' ', perStudentLimit: 0, totalLimit: 0, couponMinutes: 90, pin: '12', price: '12,5', valueLabel: 'x'.repeat(25) }));
    expect(Object.keys(p).sort()).toEqual(['couponMinutes', 'merchantId', 'perStudentLimit', 'pin', 'price', 'title', 'totalLimit', 'valueLabel']);
  });
  it('wants the end after the start', () => {
    expect(offerProblems(draft({ startsLocal: '2026-10-11T13:00', endsLocal: '2026-10-11T12:00' })).ends).toBe('النهاية يجب أن تكون بعد البداية.');
    expect(offerProblems(draft({ startsLocal: '2026-10-11T13:00', endsLocal: '2026-10-12T12:00' })).ends).toBeUndefined();
    expect(offerProblems(draft({ startsLocal: '' })).starts).toBeTruthy();
  });
  it('asks nothing about coupons of an advert', () => {
    expect(offerProblems(draft({ kind: 'info', perStudentLimit: '', couponMinutes: '', pin: '1' }))).toEqual({});
  });
  it('passes on the audience\'s problems', () => {
    expect(offerProblems(draft({ audience: audience({ minAttendance: 120 }) })).audience?.minAttendance).toBeTruthy();
  });
  it('reads a saved offer into the form without its PIN', () => {
    const d = offerDraftOf(offer({ total_limit: 50, ends_at: '2026-10-20T20:59:00Z', audience: { colleges: ['الهندسة'] } }));
    expect(d).toMatchObject({ isNew: false, hasPin: true, pin: '', removePin: false, totalLimit: 50, price: '1500', startsLocal: '2026-10-01T10:00', endsLocal: '2026-10-20T23:59' });
    expect(d.audience.colleges).toEqual(['الهندسة']);
  });
  it('sends times as instants and the audience cleaned', () => {
    const p = offerPayload(draft({ startsLocal: '2026-10-11T13:00', endsLocal: '2026-10-20T23:59', audience: audience({ colleges: ['الهندسة'], minRides: 8, minAttendance: 80 }) }), `offers/${O}/a.webp`);
    expect(p).toMatchObject({
      id: O, merchant_id: M, title: 'خصم على المشروبات', kind: 'percent', value_label: '20%', image_path: `offers/${O}/a.webp`,
      starts_at: '2026-10-11T10:00:00.000Z', ends_at: '2026-10-20T20:59:00.000Z', per_student_limit: 1, total_limit: '', coupon_minutes: 10,
      audience: { colleges: ['الهندسة'], min_rides: 8, min_attendance: 80, window_days: 30 }, special: false, sort: 0, price: '',
    });
  });
  it('keeps, sets or removes the PIN', () => {
    expect('pin' in offerPayload(draft())).toBe(false);
    expect(offerPayload(draft({ pin: '4821' })).pin).toBe('4821');
    expect(offerPayload(draft({ pin: '4821', removePin: true })).pin).toBe('');
    // An advert has no PIN: the server clears it by the kind.
    expect('pin' in offerPayload(draft({ kind: 'info', pin: '4821' }))).toBe(false);
  });
  it('sends an advert without limits of its own', () => {
    expect(offerPayload(draft({ kind: 'info', perStudentLimit: 5, totalLimit: 9, couponMinutes: 30 }))).toMatchObject({ per_student_limit: 1, total_limit: '', coupon_minutes: 10 });
  });
});

describe('the numbers as a workbook', () => {
  const stats: OfferStats = {
    reach: 400, seen: 120, opened: 60, coupons: 15, redeemed: 14, students_redeemed: 12,
    by_university: [{ name: 'جامعة الدلتا', seen: 100, redeemed: 11 }, { name: 'أخرى', seen: 20, redeemed: 3 }],
    by_college: [{ name: 'الهندسة', seen: 120, redeemed: 14 }], by_day: [{ day: '2026-10-02', redeemed: 14 }],
  };
  it('has the totals with their rates, then each breakdown', () => {
    const sheets = statsSheets(offer(), stats);
    expect(sheets.map((s) => s.sheet)).toEqual(['الأرقام', 'بالجامعة', 'بالكلية', 'باليوم']);
    const totals = sheets[0].rows.map((r) => sheets[0].columns.map((c) => c.value(r)));
    expect(totals).toContainEqual(['شاهدوه', 120, 0.3]);
    expect(totals).toContainEqual(['فتحوه', 60, 0.5]);
    expect(totals).toContainEqual(['طلاب استخدموه', 12, 0.1]);
    expect(totals[0]).toEqual(['العرض', 'خصم على المشروبات', null]);
    expect(sheets[1].rows).toHaveLength(2);
    expect(sheets[1].columns.map((c) => c.value(sheets[1].rows[1]))).toEqual(['أخرى', 20, 3]);
  });
});
