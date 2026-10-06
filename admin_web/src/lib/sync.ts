import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';

/** What the database announces: which row changed, never its contents. */
interface ChangeEvent { table: string; op: 'INSERT' | 'UPDATE' | 'DELETE'; id: string | null; company_id: string | null; }

/**
 * Which cached lists a change makes out of date. A table missing here is not
 * shown anywhere that needs to follow it live.
 */
const AFFECTS: Record<string, string[]> = {
  receipts: ['receipts', 'overview', 'students', 'reports'],
  subscriptions: ['students', 'overview', 'reports', 'receipts'],
  company_students: ['students', 'overview'],
  daily_ride_status: ['overview'],
  supervisor_scan_events: ['overview'],
  lines: ['lines', 'overview', 'supervisors', 'lineOptions'],
  stations: ['lines', 'lineOptions'],
  line_trips: ['lines', 'lineOptions'],
  supervisors: ['supervisors', 'lines', 'overview'],
  supervisor_lines: ['supervisors', 'lines'],
  company_payment_methods: ['paymentMethods'],
  company_terms: ['settings', 'lineOptions'],
  wallet_card_settings: ['walletCard'],
  password_reset_requests: ['resetRequests'],
  companies: ['company', 'overview', 'settings'],
  company_invites: ['invites', 'students'],
  student_correction_requests: ['corrections', 'students'],
};

/** Joins a private topic. The database refuses listeners the topic is not meant for. */
function useTopic(topic: string | null, onChange: (event: ChangeEvent) => void) {
  const handler = useRef(onChange);
  handler.current = onChange;
  useEffect(() => {
    if (!topic) return;
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let cancelled = false;
    void supabase.auth.getSession().then(async ({ data: { session } }) => {
      if (cancelled || !session) return;
      await supabase.realtime.setAuth(session.access_token);
      if (cancelled) return;
      channel = supabase.channel(topic, { config: { private: true } })
        .on('broadcast', { event: 'change' }, (message) => handler.current(message.payload as ChangeEvent));
      channel.subscribe();
    });
    return () => {
      cancelled = true;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [topic]);
}

/** A burst of events (approving a receipt touches three tables) refreshes each list once. */
function useCoalesced(run: (names: Set<string>) => void, delay = 400) {
  const state = useRef({ pending: new Set<string>(), timer: undefined as number | undefined, run });
  state.current.run = run;
  useEffect(() => () => window.clearTimeout(state.current.timer), []);
  return (names: string[]) => {
    const current = state.current;
    names.forEach((name) => current.pending.add(name));
    window.clearTimeout(current.timer);
    current.timer = window.setTimeout(() => {
      const batch = new Set(current.pending);
      current.pending.clear();
      current.run(batch);
    }, delay);
  };
}

/**
 * Keeps one company's workspace current. Mounted once per open workspace and
 * unmounted with it, so moving to another company leaves this one's topic first.
 */
export function useWorkspaceSync(companyId: string) {
  const client = useQueryClient();
  const refresh = useCoalesced((names) => {
    names.forEach((name) => void client.invalidateQueries({ queryKey: keys.company(companyId, name) }));
  });
  useTopic(`company:${companyId}`, (event) => {
    // Belt and braces: the topic is this company's, and so must the event be.
    if (event.company_id && event.company_id !== companyId) return;
    refresh(AFFECTS[event.table] ?? []);
  });
  useEffect(() => () => { void client.cancelQueries({ queryKey: keys.company(companyId) }); }, [client, companyId]);
}

/** Keeps the platform area current: its totals, the company list, and open reset requests. */
export function usePlatformSync() {
  const client = useQueryClient();
  const refresh = useCoalesced(() => { void client.invalidateQueries({ queryKey: keys.platform() }); }, 1000);
  useTopic('platform', () => refresh(['platform']));
}
