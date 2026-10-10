import { describe, expect, it } from 'vitest';
import { blockedBy, blockedLookup, type BlockedPhone } from './blockedPhones';

const entry = (phone: string, studentId: string | null, company: string | null = null): BlockedPhone => ({
  phone, student_id: studentId, full_name: null, reason: null, blocked_at: '2026-10-10T10:00:00Z',
  has_account: studentId !== null, company_name: company,
});

describe('blocked students', () => {
  it('a student is blocked by their account or by their number', () => {
    const blockOf = blockedLookup([entry('01012345678', 's-1'), entry('01155555555', null)]);
    expect(blockOf({ id: 's-1', phone: '01099999999' })?.phone).toBe('01012345678');
    expect(blockOf({ id: 's-2', phone: '01155555555' })?.phone).toBe('01155555555');
    expect(blockOf({ id: 's-3', phone: '01099999999' })).toBeUndefined();
  });

  it('nothing is blocked before the list is known', () => {
    expect(blockedLookup(undefined)({ id: 's-1', phone: '01012345678' })).toBeUndefined();
  });

  it('says who blocked: a company by its name, else the platform', () => {
    expect(blockedBy(entry('01012345678', 's-1', 'المستقبل'))).toBe('المستقبل');
    expect(blockedBy(entry('01012345678', 's-1'))).toBe('إدارة المنصة');
  });
});
