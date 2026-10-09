import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAdmin } from '../_shared/admin-auth.ts';
import { serviceClient } from '../_shared/clients.ts';
import { errorMessage, errorStatus, HttpError, jsonResponse, preflight } from '../_shared/http.ts';
import { secretMatches } from '../_shared/push/message.ts';
import '../_shared/wallet/artwork.ts'; // the picture decoder: a new photo is checked before Google is given its link
import {
  type AppleDevice, appleConfig, type Card, deliverGoogle, googleConfig, type GooglePassState, loadAppleDevices, loadCard,
  markDelivered, pushAppleDevices, registerSyncUrl,
} from '../_shared/wallet/runtime.ts';

// Brings installed Wallet cards up to date. The database marks a card as out
// of date (wallet_passes.dirty_at) whenever what it should show changes; this
// function delivers one batch of those and reports how many are left.
//
// Two callers:
//   * The database itself, right after a change (a subscription approved, a
//     line renamed, a student scanned ...). It proves who it is with a secret
//     that only the database and this function can read. It may deliver any
//     card and keeps going until the queue is empty.
//   * The dashboard, after a company saves its design, to show progress. A
//     company admin can only ever deliver their own company's cards; the super
//     admin names the company.
//
//   Google: the student's object is rewritten with the current content (same id).
//   Apple:  the pass is marked as changed and every device holding it gets an
//           empty push; the device then fetches the new version itself.

const BATCH = 20;

/** A claimed wallet_passes row (wallet_claim_dirty returns the whole row). */
interface DirtyPass extends GooglePassState {
  student_id: string;
  platform: 'apple' | 'google';
}

/** What a batch loads once and its passes share. */
interface BatchContext {
  /** A student with both an Apple and a Google card is worked out once. */
  card(studentId: string): Promise<Card | null>;
  /** The devices of every Apple pass in the batch, from one query. */
  appleDevices: Promise<Map<string, AppleDevice[]>>;
}

function batchContext(service: SupabaseClient, batch: DirtyPass[]): BatchContext {
  const cards = new Map<string, Promise<Card | null>>();
  const appleDevices = loadAppleDevices(
    service, batch.filter((pass) => pass.platform === 'apple').map((pass) => pass.student_id),
  );
  // Looked at only by the Apple passes; a failure must not surface as an unhandled rejection.
  appleDevices.catch(() => {});
  return {
    card(studentId) {
      let card = cards.get(studentId);
      if (!card) cards.set(studentId, card = loadCard(service, studentId));
      return card;
    },
    appleDevices,
  };
}

async function deliver(service: SupabaseClient, pass: DirtyPass, context: BatchContext): Promise<number> {
  const card = await context.card(pass.student_id);
  if (!card) {
    // The student is gone; so is the card.
    await service.from('wallet_passes').delete().eq('student_id', pass.student_id).eq('platform', pass.platform);
    return 0;
  }
  if (pass.platform === 'google') {
    const google = googleConfig();
    if (!google) throw new Error('Google Wallet غير مفعّل.');
    await deliverGoogle(service, google, card, pass);
    await markDelivered(service, pass.student_id, 'google', card, pass.dirty_at);
    return 0;
  }
  const apple = appleConfig();
  if (!apple) throw new Error('Apple Wallet غير مفعّل.');
  // Mark first: a device that asks "what changed?" must already see this card.
  await markDelivered(service, pass.student_id, 'apple', card, pass.dirty_at);
  return pushAppleDevices(service, apple, (await context.appleDevices).get(pass.student_id) ?? []);
}

async function pendingCount(service: SupabaseClient, companyId: string | null): Promise<number> {
  let query = service.from('wallet_passes').select('student_id', { count: 'exact', head: true }).not('dirty_at', 'is', null);
  if (companyId) query = query.eq('company_id', companyId);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const body = await request.json().catch(() => ({}));
    const secret = request.headers.get('x-wallet-sync-secret');
    let service: SupabaseClient;
    let companyId: string | null;
    let fromDatabase = false;

    if (secret) {
      service = serviceClient();
      const { data: runtime, error } = await service.from('wallet_runtime').select('sync_secret').eq('id', true).single();
      if (error) throw error;
      if (!secretMatches(runtime.sync_secret, secret)) throw new HttpError(401, 'غير مصرح.');
      companyId = null;
      fromDatabase = true;
    } else {
      const context = await requireAdmin(request);
      service = context.serviceClient;
      companyId = context.admin.role === 'company_admin'
        ? context.admin.company_id
        : String(body.companyId ?? '').trim() || null;
      if (!companyId) throw new HttpError(400, 'اختر الشركة.');
    }
    // The caller is known and scoped from here on.
    const [{ data, error }] = await Promise.all([
      service.rpc('wallet_claim_dirty', { p_company_id: companyId, p_limit: BATCH }),
      registerSyncUrl(service),
    ]);
    if (error) throw error;
    const batch = (data ?? []) as DirtyPass[];
    const context = batchContext(service, batch);

    let updated = 0;
    let pushFailures = 0;
    const errors: string[] = [];
    await Promise.all(batch.map(async (pass) => {
      try {
        pushFailures += await deliver(service, pass, context);
        updated += 1;
      } catch (error) {
        const message = errorMessage(error, 'تعذر تحديث بطاقة.');
        errors.push(message);
        // Stays queued; it is retried after the claim expires.
        await service.from('wallet_passes').update({ last_error: message.slice(0, 500) })
          .eq('student_id', pass.student_id).eq('platform', pass.platform);
      }
    }));

    const remaining = await pendingCount(service, companyId);
    const done = batch.length < BATCH;
    // Called by the database: nobody is waiting to call again, so continue by
    // itself while there is progress to make.
    if (fromDatabase && !done && updated > 0 && Number(body.depth ?? 0) < 500) {
      const next = fetch(`${(Deno.env.get('SUPABASE_URL') ?? '').replace(/\/+$/, '')}/functions/v1/wallet-sync`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-wallet-sync-secret': secret! },
        body: JSON.stringify({ depth: Number(body.depth ?? 0) + 1 }),
      }).then((response) => response.body?.cancel()).catch((error) => console.warn('wallet-sync continue failed', error));
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(next);
    }

    return jsonResponse({
      updated,
      failed: errors.length,
      pushFailures,
      // Cards of this scope still out of date (failed ones included).
      remaining,
      done,
      errors: [...new Set(errors)].slice(0, 3),
    });
  } catch (error) {
    console.error('wallet-sync', error);
    return jsonResponse({ error: errorMessage(error, 'تعذر تحديث بطاقات المحفظة.') }, errorStatus(error));
  }
});
