import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { serviceClient } from '../_shared/clients.ts';
import { secretMatches } from '../_shared/push/message.ts';
import { renderApplePass } from '../_shared/wallet/apple_pass.ts';
import { appleConfig, loadCard } from '../_shared/wallet/runtime.ts';

// Apple Wallet's pass web service. iPhones call this directly (never the app
// or a browser), so there is no Supabase session and no CORS:
//
//   POST   v1/devices/{device}/registrations/{passType}/{serial}   register a card on a device
//   DELETE v1/devices/{device}/registrations/{passType}/{serial}   unregister it
//   GET    v1/devices/{device}/registrations/{passType}?passesUpdatedSince=tag
//   GET    v1/passes/{passType}/{serial}                           the latest version of a card
//   POST   v1/log                                                  device-side error logs
//
// A card's calls are authenticated with "Authorization: ApplePass <token>",
// the authenticationToken inside that pass. The "what changed" call carries no
// token: per Apple the device library identifier is its shared secret.
// The serial number is the student id.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const empty = (status: number) => new Response(null, { status });
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

/** The pass row for this serial when the request carries its token, else null. */
async function authorizedPass(service: SupabaseClient, request: Request, serial: string) {
  const token = request.headers.get('Authorization')?.match(/^ApplePass\s+(.+)$/i)?.[1]?.trim();
  if (!token || !UUID.test(serial)) return null;
  const { data, error } = await service
    .from('wallet_passes').select('student_id, auth_token, content_updated_at')
    .eq('student_id', serial).eq('platform', 'apple').maybeSingle();
  if (error) throw error;
  return data && secretMatches(data.auth_token, token) ? data : null;
}

/** Whole seconds, because HTTP dates carry no fractions. */
const seconds = (date: string | Date) => Math.floor(new Date(date).getTime() / 1000);

Deno.serve(async (request: Request) => {
  try {
    const config = appleConfig();
    if (!config) return empty(503);
    const url = new URL(request.url);
    const path = url.pathname.slice(Math.max(0, url.pathname.indexOf('/v1/')));
    const service = serviceClient();

    if (path === '/v1/log') {
      if (request.method !== 'POST') return empty(405);
      const body = await request.json().catch(() => ({}));
      for (const line of Array.isArray(body.logs) ? body.logs.slice(0, 20) : []) {
        console.warn('wallet device log:', String(line).slice(0, 500));
      }
      return empty(200);
    }

    const registration = path.match(/^\/v1\/devices\/([^/]+)\/registrations\/([^/]+)(?:\/([^/]+))?$/);
    if (registration) {
      const device = decodeURIComponent(registration[1]);
      if (decodeURIComponent(registration[2]) !== config.passTypeIdentifier) return empty(404);
      const serial = registration[3] ? decodeURIComponent(registration[3]) : null;

      if (!serial) {
        if (request.method !== 'GET') return empty(405);
        const since = url.searchParams.get('passesUpdatedSince');
        const { data, error } = await service.rpc('wallet_apple_updated_serials', {
          p_device_library_id: device,
          p_since: since && /^\d{1,18}$/.test(since) ? Number(since) : null,
        });
        if (error) throw error;
        return data?.serialNumbers?.length ? json(data) : empty(204);
      }

      const pass = await authorizedPass(service, request, serial);
      if (!pass) return empty(401);

      if (request.method === 'POST') {
        const body = await request.json().catch(() => ({}));
        const pushToken = String(body.pushToken ?? '').trim();
        if (!pushToken || device.length > 200 || pushToken.length > 400) return empty(400);
        const { data: created, error } = await service.rpc('wallet_apple_register', {
          p_device_library_id: device, p_push_token: pushToken, p_student_id: pass.student_id,
        });
        if (error) throw error;
        return empty(created ? 201 : 200);
      }
      if (request.method === 'DELETE') {
        // The device row goes too once it has no cards left (database trigger).
        const { error } = await service.from('wallet_apple_registrations')
          .delete().eq('device_library_id', device).eq('student_id', pass.student_id);
        if (error) throw error;
        return empty(200);
      }
      return empty(405);
    }

    const latest = path.match(/^\/v1\/passes\/([^/]+)\/([^/]+)$/);
    if (latest) {
      if (request.method !== 'GET') return empty(405);
      if (decodeURIComponent(latest[1]) !== config.passTypeIdentifier) return empty(404);
      const pass = await authorizedPass(service, request, decodeURIComponent(latest[2]));
      if (!pass) return empty(401);

      // wallet-sync moves this tag whenever what the card shows has changed.
      const modified = seconds(pass.content_updated_at);
      const since = request.headers.get('If-Modified-Since');
      if (since && !Number.isNaN(Date.parse(since)) && seconds(since) >= modified) return empty(304);

      const card = await loadCard(service, pass.student_id);
      if (!card) return empty(404);
      // Same student, serial, token and QR as before; only what the card shows is new.
      const pkpass = await renderApplePass(service, config, card.content, pass.auth_token);
      return new Response(pkpass.slice().buffer, {
        status: 200,
        headers: {
          'Content-Type': 'application/vnd.apple.pkpass',
          'Last-Modified': new Date(modified * 1000).toUTCString(),
        },
      });
    }

    return empty(404);
  } catch (error) {
    console.error('wallet-apple-web', error);
    return empty(500);
  }
});
