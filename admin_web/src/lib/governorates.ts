/**
 * The governorates a company serves (tables `governorates`, the fixed list of
 * Egypt's 27, and `company_governorates`). A student picks theirs first in the
 * app and sees only the companies that serve it; a company that has set none
 * shows under every governorate. Set through `set_company_governorates`, by
 * the platform admin or the company's own admins.
 */
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, unwrap } from './query';

export interface Governorate { code: string; name: string; sort_order: number }

const listKey = keys.shared('governorates');
const companyKey = (companyId: string) => keys.company(companyId, 'governorates');

/** The 27, in the order they are listed. They never change: read once. */
export function useGovernorates() {
  return useQuery({
    queryKey: listKey,
    queryFn: () => unwrap<Governorate[]>(supabase.from('governorates').select('code, name, sort_order').order('sort_order')),
    staleTime: Infinity,
  });
}

/** The codes the company serves. */
export function useCompanyGovernorates(companyId: string | null) {
  return useQuery({
    queryKey: companyKey(companyId ?? ''),
    queryFn: async () => (await unwrap<{ governorate_code: string }[]>(
      supabase.from('company_governorates').select('governorate_code').eq('company_id', companyId!),
    )).map((row) => row.governorate_code),
    enabled: !!companyId,
  });
}

/** Saves the company's governorates; the server answers them as stored. */
export function useSaveCompanyGovernorates(companyId: string) {
  const client = useQueryClient();
  return async (codes: string[]) => {
    const { data, error } = await supabase.rpc('set_company_governorates', { p_company_id: companyId, p_codes: codes });
    if (error) throw error;
    client.setQueryData(companyKey(companyId), (data as string[] | null) ?? []);
  };
}

/** Whether two choices are the same set (order does not matter). */
export function sameCodes(a: readonly string[], b: readonly string[]): boolean {
  if (a.length !== b.length) return false;
  const set = new Set(a);
  return b.every((code) => set.has(code));
}

/** The chosen ones by name, in list order: "الدقهلية، دمياط". */
export function governorateNames(list: readonly Governorate[], codes: readonly string[]): string {
  const chosen = new Set(codes);
  return list.filter((g) => chosen.has(g.code)).map((g) => g.name).join('، ');
}
