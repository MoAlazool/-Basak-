import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretMatches } from '../_shared/push/message.ts';

// Removes receipt images that no receipt uses and that are more than a day old
// (a submission that failed and could not clean up after itself). The database
// lists them (orphan_receipt_images); they are removed through the Storage API,
// the only supported way to delete an object.
//
// Caller: the database once a day (pg_net), with the same x-dispatch-secret as
// push-dispatch (PUSH_DISPATCH_SECRET). A Supabase JWT is neither needed nor accepted.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (request: Request) => {
  if (!secretMatches(Deno.env.get('PUSH_DISPATCH_SECRET'), request.headers.get('x-dispatch-secret'))) {
    return json({ error: 'unauthorized' }, 401);
  }
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 500);
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });

  let removed = 0;
  // A few rounds at most: the list shrinks as objects go.
  for (let round = 0; round < 5; round++) {
    const { data, error } = await service.rpc('orphan_receipt_images', { p_limit: 200 });
    if (error) return json({ removed, error: error.message.slice(0, 200) }, 500);
    const paths = (data ?? []) as string[];
    if (paths.length === 0) break;
    const { data: gone, error: removeError } = await service.storage.from('receipts').remove(paths);
    if (removeError) return json({ removed, error: removeError.message.slice(0, 200) }, 500);
    removed += gone?.length ?? 0;
    // Nothing went although something was listed: stop rather than spin.
    if (!gone?.length) break;
  }
  console.log('storage-cleanup', JSON.stringify({ removed }));
  return json({ removed });
});
