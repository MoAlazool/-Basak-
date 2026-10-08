// The push dispatcher against the LOCAL stack: the real outbox functions over
// PostgREST with the service role, and a fake Google in place of FCM (nothing
// leaves this machine). The fixture is made and removed with psql by
// dispatch_local.sh, which runs this file.
//
//   SUPABASE_URL=http://127.0.0.1:54321 SERVICE_ROLE_KEY=… deno run -A dispatch_local.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { handleDispatchRequest } from '../../../functions/_shared/push/dispatch.ts';
import { fakeGoogle, fakeServiceAccountJson, fcmError } from '../../../functions/_shared/push/testing.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const service = createClient(url, Deno.env.get('SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
const rpc = (name: string, params?: Record<string, unknown>) => service.rpc(name, params);
const post = (secret?: string) =>
  new Request('http://local/push-dispatch', { method: 'POST', headers: secret ? { 'x-dispatch-secret': secret } : {} });

const results: [string, boolean, string][] = [];
const check = (name: string, ok: boolean, detail: unknown = '') => results.push([name, ok, JSON.stringify(detail)]);

// 1. No credentials: nothing is claimed, the database learns push is not set up.
let google = fakeGoogle(() => Response.json({ name: 'projects/basak-test/messages/x' }));
let response = await handleDispatchRequest(post('local-secret'), {
  secret: 'local-secret', serviceAccountJson: undefined, rpc, fetch: google.fetch,
});
let summary = await response.json();
check('without credentials nothing is sent or claimed', summary.configured === false && google.sendCalls.length === 0, summary);

// 2. A wrong secret is refused before anything else.
response = await handleDispatchRequest(post('wrong'), {
  secret: 'local-secret', serviceAccountJson: await fakeServiceAccountJson(), rpc, fetch: google.fetch,
});
check('a wrong secret is refused', response.status === 401 && google.sendCalls.length === 0, response.status);

// 3. With credentials: the token starting with "dead" is unregistered, the rest are accepted.
// deno-lint-ignore no-explicit-any
google = fakeGoogle((message: any) =>
  String(message.token).startsWith('dead')
    ? fcmError(404, 'NOT_FOUND', 'UNREGISTERED')
    : Response.json({ name: `projects/basak-test/messages/${String(message.token).slice(0, 6)}` }));
response = await handleDispatchRequest(post('local-secret'), {
  secret: 'local-secret', serviceAccountJson: await fakeServiceAccountJson(), rpc, fetch: google.fetch,
});
summary = await response.json();
check('the queue is drained: accepted and invalid counted', summary.configured === true && summary.claimed === 3
  && summary.accepted === 2 && summary.invalid === 1, summary);
const sent = google.sendCalls.map((call) => JSON.parse(call.body).message);
// deno-lint-ignore no-explicit-any
const english = sent.find((m: any) => String(m.token).startsWith('engl'));
// deno-lint-ignore no-explicit-any
const arabic = sent.find((m: any) => String(m.token).startsWith('arab'));
check('the device language picks the text', english?.notification.title === 'Your subscription is active'
  && arabic?.notification.title === 'تم تفعيل اشتراكك', [english?.notification, arabic?.notification]);
check('data carries ids only, as strings', arabic && Object.keys(arabic.data).sort().join() ===
  'category,notification_id,route,subscription_id,type' && arabic.data.type === 'subscription.approved'
  && arabic.data.route === 'subscription', arabic?.data);
check('urgent, on the category channel, with the unread count as badge', arabic?.android.priority === 'HIGH'
  && arabic?.android.notification.channel_id === 'basak_subscription' && arabic?.apns.payload.aps.badge === 1, arabic);

// 4. Nothing left: a second run claims nothing.
response = await handleDispatchRequest(post('local-secret'), {
  secret: 'local-secret', serviceAccountJson: await fakeServiceAccountJson(), rpc, fetch: google.fetch,
});
summary = await response.json();
check('a second run finds nothing to send', summary.claimed === 0, summary);

let failed = 0;
for (const [name, ok, detail] of results) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : '  ' + detail}`);
  if (!ok) failed++;
}
Deno.exit(failed ? 1 : 0);
