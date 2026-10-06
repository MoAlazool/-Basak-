import { useEffect, useRef } from 'react';
import { supabase } from './supabase';

/**
 * Calls `onChange` when rows of `tables` change for one company (or for every
 * company when `companyId` is null, which only the platform admin may see).
 * The database applies row-level security to these feeds too, so a filter can
 * narrow what arrives but never widen it. The subscription is dropped and
 * rebuilt whenever the company changes.
 */
export function useCompanyRealtime(companyId: string | null, tables: readonly string[], onChange: () => void) {
  const latest = useRef(onChange);
  latest.current = onChange;
  const key = tables.join(',');

  useEffect(() => {
    let timer: number | undefined;
    const notify = () => {
      window.clearTimeout(timer);
      // A burst of changes (e.g. approving a receipt touches two tables) reloads once.
      timer = window.setTimeout(() => latest.current(), 250);
    };
    let channel = supabase.channel(`company-${companyId ?? 'all'}-${key}-${Math.random().toString(36).slice(2)}`);
    for (const table of key.split(',')) {
      const column = table === 'companies' ? 'id' : 'company_id';
      channel = channel.on('postgres_changes', {
        event: '*', schema: 'public', table, ...(companyId ? { filter: `${column}=eq.${companyId}` } : {}),
      }, notify);
    }
    channel.subscribe();
    return () => {
      window.clearTimeout(timer);
      void supabase.removeChannel(channel);
    };
  }, [companyId, key]);
}
