import { supabase } from './supabase';
import { keys, queryClient } from './query';
import type { AdminProfile, CompanyScope } from './adminScope';

const one = <T,>(value: T | T[] | null | undefined): T | null => (Array.isArray(value) ? value[0] ?? null : value ?? null);

/** The pure part: an `admins` row with its embedded company, as the dashboard uses it. */
export function toAdminProfile(row: Record<string, any>): { profile: AdminProfile; company: CompanyScope | null } {
  const company = one<CompanyScope>(row.companies);
  return {
    profile: {
      id: row.id, email: row.email, full_name: row.full_name, role: row.role, company_id: row.company_id,
      companyName: company?.name ?? null,
    },
    company,
  };
}

const inFlight = new Map<string, Promise<AdminProfile | null>>();

/**
 * Who this user is as an admin, with their company, in ONE request. The company
 * row goes straight into the cache the workspace reads, so opening the
 * dashboard does not wait for a second and a third request in a row.
 * Callers that ask at the same moment (the sign-in form and the session
 * listener) share one request. Throws only on a failed request; `null` means
 * "not an admin".
 */
export function loadAdminProfile(userId: string): Promise<AdminProfile | null> {
  const running = inFlight.get(userId);
  if (running) return running;
  const request = (async () => {
    const { data, error } = await supabase.from('admins')
      .select('id, email, full_name, role, company_id, companies(id, name, status)').eq('id', userId).maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) return null;
    const { profile, company } = toAdminProfile(data);
    if (company) queryClient.setQueryData(keys.company(company.id, 'company'), company);
    return profile;
  })().finally(() => { inFlight.delete(userId); });
  inFlight.set(userId, request);
  return request;
}
