import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';
import { notify } from './toasts';
import { appliedLists } from './recentChanges';

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
  // 'walletCard': the card's design page shows the company's logo, which is also set from the identity card.
  companies: ['company', 'overview', 'settings', 'switches', 'vote', 'walletCard'],
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
 * The lists one announced change makes out of date. `applied` names the lists
 * this tab has already brought up to date for that very row (its own approval
 * has left the receipts queue and replaced the overview numbers): those are
 * left alone, everything else still follows. A name ending in "?" is re-read
 * only if its page is open.
 */
export function affectedBy(event: Pick<ChangeEvent, 'table'>, applied: readonly string[] = []): string[] {
  const names = RIDES_ONLY.has(event.table) ? [`overview${WHEN_VISIBLE}`] : AFFECTS[event.table] ?? [];
  return applied.length === 0 ? names
    : names.filter((name) => !applied.includes(name.endsWith(WHEN_VISIBLE) ? name.slice(0, -WHEN_VISIBLE.length) : name));
}

/** Every list a burst of changes makes out of date, each once. `appliedFor` answers per row id. */
export function affectedByAll(events: readonly Pick<ChangeEvent, 'table' | 'id'>[], appliedFor: (id: string | null) => readonly string[]): string[] {
  return [...new Set(events.flatMap((event) => affectedBy(event, appliedFor(event.id))))];
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

/**
 * A burst of events (approving a receipt touches three tables) is handled once,
 * a moment after the last one. The wait also lets the answer to this tab's own
 * write arrive first, so its announcement is recognised as already applied.
 */
function useCoalesced<T>(run: (items: T[]) => void, delay = 400, maxWait = 2000) {
  const state = useRef({ pending: [] as T[], timer: undefined as number | undefined, firstAt: 0, run });
  state.current.run = run;
  useEffect(() => () => window.clearTimeout(state.current.timer), []);
  return (item: T) => {
    const current = state.current;
    const now = Date.now();
    if (current.pending.length === 0) current.firstAt = now;
    current.pending.push(item);
    window.clearTimeout(current.timer);
    current.timer = window.setTimeout(() => {
      const batch = current.pending;
      current.pending = [];
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
  const refresh = useCoalesced<ChangeEvent>((events) => {
    const overviewOpen = window.location.pathname.replace(/\/+$/, '') === `/c/${companyId}`;
    const { now, later } = planRefresh(affectedByAll(events, appliedLists), overviewOpen);
    // Default `refetchType: 'active'`: only lists that are mounted are read again.
    now.forEach((name) => void client.invalidateQueries({ queryKey: keys.company(companyId, name) }));
    later.forEach((name) => void client.invalidateQueries({ queryKey: keys.company(companyId, name), refetchType: 'none' }));
  });
  useTopic(`company:${companyId}`, (event) => {
    // Belt and braces: the topic is this company's, and so must the event be.
    if (event.company_id && event.company_id !== companyId) return;
    refresh(event);
    // Something new for the admin to act on: say so, wherever they are.
    const arrival = event.op === 'INSERT' ? ARRIVALS[event.table] : undefined;
    if (arrival) notify({ ...arrival, to: `/c/${companyId}/${arrival.page}` });
  });
  useEffect(() => () => { void client.cancelQueries({ queryKey: keys.company(companyId) }); }, [client, companyId]);
}

/**
 * What a change means for the platform admin's pages. A table missing here
 * refreshes everything of the platform (better once too often than a stale page).
 */
const PLATFORM_AFFECTS: Record<string, string[]> = {
  receipts: ['overview'],
  subscriptions: ['overview', 'students'],
  company_students: ['overview', 'students'],
  companies: ['overview', 'companyNames', 'companyAdmins', 'students'],
  student_correction_requests: ['corrections', 'students'],
  password_reset_requests: ['resetRequests'],
  notifications: ['notifications'],
};

/**
 * The platform lists a burst of changes makes out of date; `null` means all of
 * them. As in a workspace, a list this tab already brought up to date for a row
 * (its own cancelled or deleted notification) is left alone.
 */
export function platformAffectedBy(
  events: readonly Pick<ChangeEvent, 'table' | 'id'>[], appliedFor: (id: string | null) => readonly string[] = () => [],
): string[] | null {
  const names = new Set<string>();
  for (const event of events) {
    const lists = PLATFORM_AFFECTS[event.table];
    if (!lists) return null;
    const applied = appliedFor(event.id);
    lists.forEach((name) => { if (!applied.includes(name)) names.add(name); });
  }
  return [...names];
}

/** Keeps the platform area current: its totals, the company list, the accounts and open requests. */
export function usePlatformSync() {
  const client = useQueryClient();
  const refresh = useCoalesced<ChangeEvent>((events) => {
    const names = platformAffectedBy(events, appliedLists);
    if (names === null) void client.invalidateQueries({ queryKey: keys.platform() });
    else names.forEach((name) => void client.invalidateQueries({ queryKey: keys.platform(name) }));
  }, 1000, 5000);
  useTopic('platform', refresh);
}
