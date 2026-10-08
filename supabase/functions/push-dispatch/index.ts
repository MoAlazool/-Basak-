import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { handleDispatchRequest } from '../_shared/push/dispatch.ts';

// Sends the queued push notifications (push_outbox) through FCM HTTP v1.
//
// Callers: the database, right after it queues rows (pg_net), and a cron that
// picks up retries. Both prove who they are with x-dispatch-secret; a Supabase
// JWT is neither needed nor accepted.
//
// Secrets: PUSH_DISPATCH_SECRET, FCM_SERVICE_ACCOUNT_JSON (the Firebase
// service-account key file, pasted whole). Without the second one nothing is
// claimed and the database is told push is not configured.
//
// The work itself is in _shared/push/dispatch.ts, where it is tested.

Deno.serve((request: Request) => {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const secret = Deno.env.get('PUSH_DISPATCH_SECRET');
  if (!url || !serviceKey) {
    console.error('push-dispatch: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
    return new Response(JSON.stringify({ error: 'not_configured' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  return handleDispatchRequest(request, {
    secret,
    serviceAccountJson: Deno.env.get('FCM_SERVICE_ACCOUNT_JSON'),
    fcmApiBase: Deno.env.get('FCM_API_BASE'),
    rpc: (name, params) => service.rpc(name, params),
    fetch: (input, init) => fetch(input, init),
  });
});
