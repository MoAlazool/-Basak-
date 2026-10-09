import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { bearerToken, requireUser, serviceClient } from '../_shared/clients.ts';
import { errorMessage, errorStatus, jsonResponse, preflight } from '../_shared/http.ts';
import { toBase64 } from '../_shared/wallet/apple.ts';
import { loadAppleImages, renderApplePass } from '../_shared/wallet/apple_pass.ts';
import '../_shared/wallet/artwork.ts'; // the picture decoder (photo check for Google, pass images for Apple)
import { buildSaveUrl } from '../_shared/wallet/google.ts';
import { googleObjectId } from '../_shared/wallet/pass_data.ts';
import {
  appleConfig, type Card, deliverGoogle, googleConfig, type GooglePassState, loadCard, loadGoogleState, markDelivered,
  newAuthToken, registerSyncUrl,
} from '../_shared/wallet/runtime.ts';

// A signed-in student asks for their own Wallet card.
//   { platform: 'apple' }  -> { pkpass: <base64 .pkpass> }
//   { platform: 'google' } -> { saveUrl: <Add to Google Wallet link> }
// The card is the student's permanent identity and QR, in the design of the
// company they ride with. It is issued with or without a subscription: whether
// the student may ride is decided when the supervisor scans the QR.

async function issueApple(service: SupabaseClient, card: Card) {
  const config = appleConfig();
  if (!config) {
    return jsonResponse({ error: 'إضافة البطاقة إلى Apple Wallet غير مفعّلة بعد.', reason: 'not_configured' }, 503);
  }
  const studentId = card.content.student.id;
  // The artwork does not depend on the token: it loads while the token is settled.
  const images = loadAppleImages(service, card.content);
  const token = (async () => {
    // The token is created once and kept, so a card that is already installed keeps updating.
    const { data: created, error: insertError } = await service.from('wallet_passes').upsert(
      {
        student_id: studentId, platform: 'apple', auth_token: newAuthToken(),
        content_hash: card.hash, company_id: card.content.company?.id ?? null,
      },
      { onConflict: 'student_id,platform', ignoreDuplicates: true },
    ).select('auth_token');
    if (insertError) throw insertError;
    if (created?.length) return created[0].auth_token as string;
    // The card existed: its token is read, and since it may also sit on other
    // devices, those are brought up to date by wallet-sync, not here.
    const [{ data: pass, error: passError }] = await Promise.all([
      service.from('wallet_passes').select('auth_token').eq('student_id', studentId).eq('platform', 'apple').single(),
      service.rpc('wallet_touch_students', { p_student_ids: [studentId] }),
    ]);
    if (passError) throw passError;
    return pass.auth_token as string;
  })();
  const [authToken, artwork] = await Promise.all([token, images]);
  return jsonResponse({ pkpass: toBase64(await renderApplePass(service, config, card.content, authToken, artwork)) });
}

async function issueGoogle(service: SupabaseClient, card: Card, state: GooglePassState | null) {
  const config = googleConfig();
  if (!config) {
    return jsonResponse({ error: 'إضافة البطاقة إلى Google Wallet غير مفعّلة بعد.', reason: 'not_configured' }, 503);
  }
  const studentId = card.content.student.id;
  // One object per student: every device of that student shows it, so it is simply brought up to date.
  await deliverGoogle(service, config, card, state);
  await markDelivered(service, studentId, 'google', card, state?.dirty_at ?? null);
  return jsonResponse({ saveUrl: await buildSaveUrl(config, googleObjectId(config.issuerId, card.content.student)) });
}

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const messages = { missing: 'سجّل الدخول أولاً.', invalid: 'جلسة الدخول غير صالحة.' };
    // Refused before the body is even read; the session itself is checked below.
    if (!bearerToken(request)) return jsonResponse({ error: messages.missing }, 401);
    const body = await request.json().catch(() => ({}));
    const platform = String(body.platform ?? '');
    if (platform !== 'apple' && platform !== 'google') {
      return jsonResponse({ error: 'نوع المحفظة غير مدعوم.' }, 400);
    }
    const user = await requireUser(request, messages);

    // Only ever the caller's own card: the id comes from the session, never from the request.
    const service = serviceClient();
    const [card, googleState] = await Promise.all([
      loadCard(service, user.id),
      platform === 'google' ? loadGoogleState(service, user.id) : null,
    ]);
    if (!card) return jsonResponse({ error: 'بطاقة المحفظة متاحة للطلاب فقط.' }, 403);

    const [response] = await Promise.all([
      platform === 'apple' ? issueApple(service, card) : issueGoogle(service, card, googleState),
      registerSyncUrl(service),
    ]);
    return response;
  } catch (error) {
    console.error('student-wallet-pass', error);
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء بطاقة المحفظة.') }, errorStatus(error));
  }
});
