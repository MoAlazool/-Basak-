// The push dispatcher itself, with everything it touches passed in (fetch, the
// RPC caller, the clock, the secrets) so it runs unchanged under `deno test`.
//
// claim_push_outbox -> one FCM send per row -> complete_push_outbox, one batch
// after another until the outbox is empty or the time budget is used.
import { FcmAuthError, type FcmCredentials, type FetchLike, getAccessToken, loadCredentials, resetAccessToken, sendMessage } from './fcm.ts';
import { buildMessage, mapSendOutcome, type PushOutboxResult, type PushOutboxRow, secretMatches } from './message.ts';

export type RpcCaller = (
  name: string, params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { message?: string; code?: string } | null }>;

export interface DispatchDeps {
  rpc: RpcCaller;
  fetch: FetchLike;
  /** env FCM_SERVICE_ACCOUNT_JSON */
  serviceAccountJson: string | null | undefined;
  /** env FCM_API_BASE (optional; only to point at a fake FCM) */
  fcmApiBase?: string | null;
  now?: () => number;
  /** Rows per claim. */
  batchSize?: number;
  /** Sends in flight at once. */
  concurrency?: number;
  /** Per-request timeout. */
  timeoutMs?: number;
  /** No new claim after this much wall time. */
  budgetMs?: number;
  /** No new send after this much wall time; what is left of the batch is handed back as `retry`. */
  hardStopMs?: number;
}

export interface DispatchSummary {
  configured: boolean;
  claimed: number;
  accepted: number;
  failed: number;
  retried: number;
  invalid: number;
  batches: number;
  /** Why the loop ended early: auth_failed | claim_failed | complete_failed | time_budget. Absent = the outbox is empty. */
  stopped?: string;
  /** The credentials problem, as a short code. */
  auth_error?: string;
  /** Rows whose result could not be written back (left in `sending`; the database un-sticks them). */
  unrecorded?: number;
}

const COUNTER = { accepted: 'accepted', failed: 'failed', retry: 'retried', invalid_token: 'invalid' } as const;

function rpcError(error: unknown): string {
  const value = error as { code?: unknown; message?: unknown } | null;
  return String(value?.code ?? value?.message ?? 'error').slice(0, 80);
}

async function callRpc(rpc: RpcCaller, name: string, params: Record<string, unknown>) {
  try {
    const { data, error } = await rpc(name, params);
    return { data, error: error ? rpcError(error) : null };
  } catch (error) {
    return { data: null, error: error instanceof Error ? error.name : 'error' };
  }
}

interface BatchOutcome {
  results: PushOutboxResult[];
  codes: Map<string, number>;
  authError?: string;
}

async function sendBatch(
  rows: PushOutboxRow[], credentials: FcmCredentials, deps: DispatchDeps, now: () => number, hardStop: number,
): Promise<BatchOutcome> {
  const timeoutMs = deps.timeoutMs ?? 10_000;
  const results: PushOutboxResult[] = new Array(rows.length);
  const codes = new Map<string, number>();
  const count = (code: string) => codes.set(code, (codes.get(code) ?? 0) + 1);
  let authError: string | undefined;

  let accessToken = '';
  try {
    accessToken = await getAccessToken(credentials, deps.fetch, now, timeoutMs);
  } catch (error) {
    authError = error instanceof FcmAuthError ? error.code : 'token_error';
  }

  let next = 0;
  const worker = async () => {
    while (next < rows.length) {
      const index = next++;
      const row = rows[index];
      // Nothing is sent without credentials or after the hard stop; the row
      // goes back to the queue instead of staying in `sending`.
      const skip = authError ? `auth: ${authError}` : now() >= hardStop ? 'not_sent: time_budget' : null;
      if (skip) {
        results[index] = { id: row.id, status: 'retry', error: skip.slice(0, 200) };
        count(skip.split(':')[0]);
        continue;
      }
      try {
        const mapped = mapSendOutcome(await sendMessage(credentials, accessToken, buildMessage(row), deps.fetch, timeoutMs), row.token);
        if (mapped.authFailure) {
          authError ??= mapped.code ?? 'auth';
          resetAccessToken();
        }
        results[index] = {
          id: row.id, status: mapped.status,
          ...(mapped.message_id ? { message_id: mapped.message_id } : {}),
          ...(mapped.error ? { error: mapped.error } : {}),
        };
        if (mapped.code) count(mapped.code);
      } catch {
        results[index] = { id: row.id, status: 'retry', error: 'internal_error' };
        count('internal_error');
      }
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(deps.concurrency ?? 20, rows.length)) }, worker));
  return { results, codes, authError };
}

/** One invocation: drains the outbox as far as time and credentials allow. Never throws. */
export async function runDispatch(deps: DispatchDeps): Promise<DispatchSummary> {
  const now = deps.now ?? Date.now;
  const summary: DispatchSummary = { configured: false, claimed: 0, accepted: 0, failed: 0, retried: 0, invalid: 0, batches: 0 };

  const credentials = await loadCredentials(deps.serviceAccountJson, deps.fcmApiBase).catch(() => null);
  const flag = await callRpc(deps.rpc, 'set_push_configured', { p_configured: credentials !== null });
  if (flag.error) console.error('push-dispatch set_push_configured failed', flag.error);
  if (!credentials) return summary;
  summary.configured = true;

  const started = now();
  const deadline = started + (deps.budgetMs ?? 20_000);
  const hardStop = started + (deps.hardStopMs ?? 45_000);
  const limit = deps.batchSize ?? 200;

  while (true) {
    if (now() >= deadline) {
      summary.stopped = 'time_budget';
      break;
    }
    const claim = await callRpc(deps.rpc, 'claim_push_outbox', { p_limit: limit });
    if (claim.error) {
      console.error('push-dispatch claim failed', claim.error);
      summary.stopped = 'claim_failed';
      break;
    }
    const rows = (Array.isArray(claim.data) ? claim.data : []) as PushOutboxRow[];
    if (rows.length === 0) break;
    summary.batches += 1;
    summary.claimed += rows.length;

    let batch: BatchOutcome;
    try {
      batch = await sendBatch(rows, credentials, deps, now, hardStop);
    } catch {
      // Not expected (sendBatch catches per row), but a claimed row is never left behind.
      batch = {
        results: rows.map((row) => ({ id: row.id, status: 'retry' as const, error: 'internal_error' })),
        codes: new Map([['internal_error', rows.length]]),
      };
    }
    for (const result of batch.results) summary[COUNTER[result.status]] += 1;
    if (batch.codes.size) console.warn('push-dispatch batch errors', JSON.stringify(Object.fromEntries(batch.codes)));

    let complete = await callRpc(deps.rpc, 'complete_push_outbox', { p_results: batch.results });
    if (complete.error) complete = await callRpc(deps.rpc, 'complete_push_outbox', { p_results: batch.results });
    if (complete.error) {
      console.error('push-dispatch complete failed', complete.error, 'rows', rows.length);
      summary.unrecorded = (summary.unrecorded ?? 0) + rows.length;
      summary.stopped = 'complete_failed';
    }
    if (batch.authError) {
      console.error('push-dispatch credentials refused', batch.authError);
      summary.auth_error = batch.authError;
      summary.stopped = 'auth_failed';
    }
    if (summary.stopped) break;
  }
  return summary;
}

export interface HandlerDeps extends DispatchDeps {
  /** env PUSH_DISPATCH_SECRET */
  secret: string | null | undefined;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { 'Content-Type': 'application/json' } });
}

/**
 * The HTTP entry. Only the database (pg_net) and a cron call it, both with the
 * shared secret; there is no browser caller, so no CORS.
 */
export async function handleDispatchRequest(request: Request, deps: HandlerDeps): Promise<Response> {
  if (!secretMatches(deps.secret, request.headers.get('x-dispatch-secret'))) return json({ error: 'unauthorized' }, 401);
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  try {
    const summary = await runDispatch(deps);
    console.log('push-dispatch', JSON.stringify(summary));
    return json(summary);
  } catch (error) {
    console.error('push-dispatch failed', error instanceof Error ? error.name : 'error');
    return json({ error: 'internal_error' }, 500);
  }
}
