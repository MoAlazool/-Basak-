import { describe, expect, it } from 'vitest';
import { blockedLookup, type BlockedPhone } from './blockedPhones';

const entry = (phone: string, studentId: string | null): BlockedPhone => ({
  phone, student_id: studentId, full_name: null, reason: null, blocked_at: '2026-10-10T10:00:00Z', has_account: studentId !== null,
});

describe('blocked students', () => {
  it('a student is blocked by their account or by their number', () => {
    const isBlocked = blockedLookup([entry('01012345678', 's-1'), entry('01155555555', null)]);
    expect(isBlocked({ id: 's-1', phone: '01099999999' })).toBe(true);
    expect(isBlocked({ id: 's-2', phone: '01155555555' })).toBe(true);
    expect(isBlocked({ id: 's-3', phone: '01099999999' })).toBe(false);
  });

  it('nothing is blocked before the list is known (or for a company admin, who never reads it)', () => {
    expect(blockedLookup(undefined)({ id: 's-1', phone: '01012345678' })).toBe(false);
  });
});
