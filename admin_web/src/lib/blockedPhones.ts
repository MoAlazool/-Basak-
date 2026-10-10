/**
 * Blocked phone numbers (table `blocked_phones`): a blocked number cannot be
 * registered again, and the account that has it cannot sign in. The platform
 * admin blocks anyone; a company admin blocks the company's own students and
 * lifts only the company's own blocks. Read through `list_blocked_phones`,
 * changed through `block_student` / `unblock_phone`.
 */
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, STALE, unwrap } from './query';

export interface BlockedPhone {
  phone: string;
  student_id: string | null;
  full_name: string | null;
  /** Only for the platform admin, and for the company that blocked. */
  reason: string | null;
  blocked_at: string;
  /** False once the account was deleted: the number alone stays blocked. */
  has_account: boolean;
  /** The company that blocked; null: the platform. */
  company_id?: string | null;
  company_name?: string | null;
  /** Whether the one asking may lift it. */
  can_unblock?: boolean;
}

/** Who blocked, in words. */
export const blockedBy = (entry: BlockedPhone) => entry.company_name ?? 'إدارة المنصة';

/** The longest reason the server keeps. */
export const BLOCK_REASON_MAX = 300;

const blockedKey = (companyId: string | null) =>
  companyId ? keys.company(companyId, 'blockedPhones') : keys.platform('blockedPhones');

/**
 * The blocks a page shows: every one for the platform's pages (companyId
 * null), or those of the company's students and the company's own.
 */
export function useBlockedPhones(companyId: string | null, enabled = true) {
  return useQuery({
    queryKey: blockedKey(companyId),
    queryFn: () => unwrap<BlockedPhone[]>(supabase.rpc('list_blocked_phones', { p_company_id: companyId })),
    enabled,
    staleTime: STALE.reference,
  });
}

/** The block of a student on screen, if any: by account, or by number for a list without ids. */
export function blockedLookup(list: BlockedPhone[] | undefined) {
  const byId = new Map<string, BlockedPhone>();
  const byPhone = new Map<string, BlockedPhone>();
  for (const entry of list ?? []) {
    if (entry.student_id) byId.set(entry.student_id, entry);
    byPhone.set(entry.phone, entry);
  }
  return (student: { id: string; phone: string }): BlockedPhone | undefined =>
    byId.get(student.id) ?? byPhone.get(student.phone);
}

/**
 * Block and unblock, each one request, as the platform (companyId null) or as
 * that company. Every list of blocks on screen is read again after.
 */
export function useBlockActions(companyId: string | null) {
  const client = useQueryClient();
  const refresh = () => client.invalidateQueries({ predicate: (query) => query.queryKey.includes('blockedPhones') });
  const block = async (studentId: string, reason: string | null) => {
    const { error } = await supabase.rpc('block_student', { p_student_id: studentId, p_reason: reason, p_company_id: companyId });
    if (error) throw error;
    await refresh();
  };
  const unblock = async (phone: string) => {
    const { error } = await supabase.rpc('unblock_phone', { p_phone: phone, p_company_id: companyId });
    if (error) throw error;
    await refresh();
  };
  return { block, unblock };
}
