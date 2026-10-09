// Test helper only (imported by *_test.ts): a Supabase client that never
// touches the network. Every database, Auth, RPC and Storage call is recorded
// and answered by the handlers the test supplies.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface Reply {
  data?: unknown;
  error?: { message: string; code?: string; status?: number } | null;
  count?: number | null;
}

export interface DbCall {
  table: string;
  op: 'select' | 'insert' | 'update' | 'upsert' | 'delete';
  /** The select list (also set when a write asks for rows back). */
  columns?: string;
  values?: unknown;
  options?: unknown;
  /** Filters as written, e.g. { id: 'x', 'in:id': [...], 'is:dirty_at': null }. */
  filters: Record<string, unknown>;
}

export interface Handlers {
  db?: (call: DbCall) => Reply | Promise<Reply>;
  rpc?: (name: string, params: Record<string, unknown>) => Reply | Promise<Reply>;
  /** auth.getUser(token) */
  getUser?: (token: string) => Reply;
  /** auth.admin.<method>(...args) */
  authAdmin?: (method: string, args: unknown[]) => Reply | Promise<Reply>;
  /** storage.from(bucket).<method>(...args) */
  storage?: (bucket: string, method: string, args: unknown[]) => Reply | Promise<Reply>;
}

export interface FakeSupabase {
  client: SupabaseClient;
  /** Every call in the order it started: "select lines", "rpc x", "auth.admin.createUser", "storage receipts.list". */
  log: string[];
  /** "start <call>" / "end <call>" in the order they happened: shows what ran at the same time. */
  timeline: string[];
  db: DbCall[];
  /** Calls of one kind, e.g. count('insert students'). */
  count(entry: string): number;
}

const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

export function fakeSupabase(handlers: Handlers = {}): FakeSupabase {
  const log: string[] = [];
  const timeline: string[] = [];
  const db: DbCall[] = [];

  // Every answer arrives one timer tick later, like a network reply would:
  // calls started together are all "in flight" before the first one ends.
  async function answer(name: string, produce: () => Reply | Promise<Reply> | undefined): Promise<Required<Reply>> {
    log.push(name);
    timeline.push(`start ${name}`);
    await tick();
    const reply = (await produce()) ?? {};
    timeline.push(`end ${name}`);
    return { data: reply.data ?? null, error: reply.error ?? null, count: reply.count ?? null };
  }

  function query(table: string) {
    const call: DbCall = { table, op: 'select', filters: {} };
    const filter = (prefix: string) => (column: string, ...rest: unknown[]) => {
      call.filters[`${prefix}${column}`] = rest.length > 1 ? rest : rest[0];
      return builder;
    };
    const write = (op: DbCall['op']) => (values?: unknown, options?: unknown) => {
      call.op = op;
      call.values = values;
      call.options = options;
      return builder;
    };
    // deno-lint-ignore no-explicit-any
    const builder: any = {
      select(columns = '*', options?: unknown) {
        call.columns = columns;
        if (options) call.options = options;
        return builder;
      },
      insert: write('insert'),
      update: write('update'),
      upsert: write('upsert'),
      delete: write('delete'),
      eq: filter(''),
      in: filter('in:'),
      is: filter('is:'),
      not: filter('not:'),
      maybeSingle: () => builder,
      single: () => builder,
      then(resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) {
        db.push(call);
        return answer(`${call.op} ${table}`, () => handlers.db?.(call)).then(resolve, reject);
      },
    };
    return builder;
  }

  const admin = new Proxy({}, {
    get: (_target, method: string) => (...args: unknown[]) =>
      answer(`auth.admin.${method}`, () => handlers.authAdmin?.(method, args))
        .then(({ data, error }) => ({ data: data ?? { user: null }, error })),
  });

  const client = {
    from: query,
    rpc: (name: string, params: Record<string, unknown> = {}) => answer(`rpc ${name}`, () => handlers.rpc?.(name, params)),
    auth: {
      admin,
      getUser: (token: string) =>
        answer('auth.getUser', () => handlers.getUser?.(token))
          .then(({ data, error }) => ({ data: { user: data ?? null }, error })),
    },
    storage: {
      from: (bucket: string) => new Proxy({}, {
        get: (_target, method: string) => (...args: unknown[]) =>
          answer(`storage ${bucket}.${method}`, () => handlers.storage?.(bucket, method, args)),
      }),
    },
  } as unknown as SupabaseClient;

  return { client, log, timeline, db, count: (entry) => log.filter((item) => item === entry).length };
}

/** A request as the dashboard or the app sends it. */
export function post(body: unknown, token: string | null = 'session-token'): Request {
  return new Request('http://local/fn', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
}
