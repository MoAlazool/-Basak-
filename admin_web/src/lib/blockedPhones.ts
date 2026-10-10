/**
 * Blocked phone numbers (table `blocked_phones`, the platform admin's alone):
 * a blocked number cannot be registered again, and the account that has it
 * cannot sign in. Read through `list_blocked_phones`, changed through
 * `block_student` / `unblock_phone`.
 */
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, STALE, unwrap } from './query';

export interface BlockedPhone {
  phone: string;
  student_id: string | null;
  full_name: string | null;
  reason: string | null;
  blocked_at: string;
  /** False once the account was deleted: the number alone stays blocked. */
  has_account: boolean;
}

export const blockedPhonesKey = keys.platform('blockedPhones');

/** The longest reason the server keeps. */
export const BLOCK_REASON_MAX = 300;

/** The blocked numbers, for the platform admin only (others never ask). */
export function useBlockedPhones(enabled: boolean) {
  return useQuery({
    queryKey: blockedPhonesKey,
    queryFn: () => unwrap<BlockedPhone[]>(supabase.rpc('list_blocked_phones')),
    enabled,
    staleTime: STALE.reference,
  });
}

/** Which students on screen are blocked: by account, or by number for a list without ids. */
export function blockedLookup(list: BlockedPhone[] | undefined) {
  const ids = new Set<string>();
  const phones = new Set<string>();
  for (const entry of list ?? []) {
    if (entry.student_id) ids.add(entry.student_id);
    phones.add(entry.phone);
  }
  return (student: { id: string; phone: string }) => ids.has(student.id) || phones.has(student.phone);
}

/** Block and unblock, each one request; the list on screen follows at once. */
export function useBlockActions() {
  const client = useQueryClient();
  const block = async (studentId: string, reason: string | null) => {
    const { error } = await supabase.rpc('block_student', { p_student_id: studentId, p_reason: reason });
    if (error) throw error;
    await client.invalidateQueries({ queryKey: blockedPhonesKey });
  };
  const unblock = async (phone: string) => {
    const { error } = await supabase.rpc('unblock_phone', { p_phone: phone });
    if (error) throw error;
    client.setQueryData<BlockedPhone[]>(blockedPhonesKey, (list) => (list ?? []).filter((entry) => entry.phone !== phone));
  };
  return { block, unblock };
}
