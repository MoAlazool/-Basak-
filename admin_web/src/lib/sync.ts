import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';
import { notify } from './toasts';
import { wasAppliedHere } from './recentChanges';

/** What the database announces: which row changed, never its contents. */
interface ChangeEvent { table: string; op: 'INSERT' | 'UPDATE' | 'DELETE'; id: string | null; company_id: string | null; }

/**
 * Which cached lists a change makes out of date. A table missing here is not
 * shown anywhere that needs to follow it live. Only lists that are on screen
 * are read again; the others are marked out of date and read when opened.
 */
const AFFECTS: Record<string, string[]> = {
  receipts: ['receipts', 'overview', 'students', 'reports'],
  subscriptions: ['students', 'overview', 'reports', 'receipts'],
  company_students: ['students', 'overview'],
  lines: ['lines', 'lineNames', 'periods', 'overview'],
  stations: ['lines'],
  line_trips: ['lines'],
  supervisors: ['supervisors', 'overview'],
  supervisor_lines: ['supervisorLines'],
  company_payment_methods: ['paymentMethods'],
  company_terms: ['settings', 'switches', 'periods'],
  wallet_card_settings: ['walletCard'],
  password_reset_requests: ['resetRequests'],
  companies: ['company', 'overview', 'settings', 'switches'],
  company_invites: ['invites', 'students'],
  student_correction_requests: ['corrections', 'students'],
  notifications: ['notifications'],
};

/**
 * Changes that only move the riders' numbers of the overview page. The overview
 * is also what feeds the sidebar badges, so it is always mounted; these events
 * (one per student confirmation or scan) re-read it only while that page is
 * open, and otherwise just mark it out of date for the next visit.
 */
const RIDES_ONLY = new Set(['daily_ride_status', 'supervisor_scan_events']);
const WHEN_VISIBLE = '?';

/**
 * The lists one announced change makes out of date. `own` is true when this
 * tab made the change itself and has already put the result in its cache: the
 * pending-receipts list is then left alone (everything else still follows).
 * A name ending in "?" is re-read only if its page is open.
 */
export function affectedBy(event: Pick<ChangeEvent, 'table'>, own: boolean): string[] {
  if (RIDES_ONLY.has(event.table)) return [`overview${WHEN_VISIBLE}`];
  const names = AFFECTS[event.table] ?? [];
  return own && (event.table === 'receipts' || event.table === 'subscriptions')
    ? names.filter((name) => name !== 'receipts') : names;
}

/**
 * Splits a batch into what is re-read now and what is only marked out of date.
 * `overviewOpen` says whether the overview page is the one on screen.
 */
export function planRefresh(batch: Iterable<string>, overviewOpen: boolean): { now: string[]; later: string[] } {
  const now = new Set<string>();
  const later = new Set<string>();
  for (const name of batch) {
    if (!name.endsWith(WHEN_VISIBLE)) now.add(name);
    else (overviewOpen ? now : later).add(name.slice(0, -WHEN_VISIBLE.length));
  }
  return { now: [...now], later: [...later].filter((name) => !now.has(name)) };
}

/**
 * How long to wait before refreshing: `delay` after the latest event, but never
 * more than `maxWait` after the first one of the burst (a steady stream of
 * events would otherwise postpone the refresh for ever).
 */
export function nextFlushDelay(firstAt: number, now: number, delay: number, maxWait: number): number {
  return Math.max(0, Math.min(delay, firstAt + maxWait - now));
}

/** New rows an admin should hear about, and the page that handles them. */
const ARRIVALS: Record<string, { title: string; body: string; page: string }> = {
  receipts: { title: 'إيصال دفع جديد', body: 'طالب رفع إيصالاً وينتظر المراجعة.', page: 'receipts' },
  password_reset_requests: { title: 'طلب استعادة كلمة مرور', body: 'طالب يطلب رمزاً لتغيير كلمة المرور.', page: 'students' },
  company_students: { title: 'طالب جديد', body: 'انضم طالب جديد إلى الشركة.', page: 'students' },
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
function useCoalesced(run: (names: Set<string>) => void, delay = 400, maxWait = 2000) {
  const state = useRef({ pending: new Set<string>(), timer: undefined as number | undefined, firstAt: 0, run });
  state.current.run = run;
  useEffect(() => () => window.clearTimeout(state.current.timer), []);
  return (names: string[]) => {
    if (names.length === 0) return;
    const current = state.current;
    const now = Date.now();
    if (current.pending.size === 0) current.firstAt = now;
    names.forEach((name) => current.pending.add(name));
    window.clearTimeout(current.timer);
    current.timer = window.setTimeout(() => {
      const batch = new Set(current.pending);
      current.pending.clear();
      current.run(batch);
    }, nextFlushDelay(current.firstAt, now, delay, maxWait));
  };
}

/**
 * Keeps one company's workspace current. Mounted once per open workspace and
 * unmounted with it, so moving to another company leaves this one's topic first.
 */
export function useWorkspaceSync(companyId: string) {
  const client = useQueryClient();
  const refresh = useCoalesced((names) => {
    const overviewOpen = window.location.pathname.replace(/\/+$/, '') === `/c/${companyId}`;
    const { now, later } = planRefresh(names, overviewOpen);
    // Default `refetchType: 'active'`: only lists that are mounted are read again.
    now.forEach((name) => void client.invalidateQueries({ queryKey: keys.company(companyId, name) }));
    later.forEach((name) => void client.invalidateQueries({ queryKey: keys.company(companyId, name), refetchType: 'none' }));
  });
  useTopic(`company:${companyId}`, (event) => {
    // Belt and braces: the topic is this company's, and so must the event be.
    if (event.company_id && event.company_id !== companyId) return;
    // This tab's own approval/rejection is already on screen: its echo re-reads nothing it wrote.
    refresh(affectedBy(event, wasAppliedHere(event.id)));
    // Something new for the admin to act on: say so, wherever they are.
    const arrival = event.op === 'INSERT' ? ARRIVALS[event.table] : undefined;
    if (arrival) notify({ ...arrival, to: `/c/${companyId}/${arrival.page}` });
  });
  useEffect(() => () => { void client.cancelQueries({ queryKey: keys.company(companyId) }); }, [client, companyId]);
}

/** Keeps the platform area current: its totals, the company list, and open reset requests. */
export function usePlatformSync() {
  const client = useQueryClient();
  const refresh = useCoalesced(() => { void client.invalidateQueries({ queryKey: keys.platform() }); }, 1000, 5000);
  useTopic('platform', () => refresh(['platform']));
}
