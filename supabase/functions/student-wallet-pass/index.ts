import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, errorMessage, jsonResponse } from '../_shared/admin-auth.ts';
import { toBase64 } from '../_shared/wallet/apple.ts';
import { buildSaveUrl } from '../_shared/wallet/google.ts';
import { googleObjectId } from '../_shared/wallet/pass_data.ts';
import {
  appleConfig, type Card, deliverGoogle, googleConfig, loadCard, markDelivered, newAuthToken, registerSyncUrl,
  renderApplePass,
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
  // The token is created once and kept, so a card that is already installed keeps updating.
  const { data: created, error: insertError } = await service.from('wallet_passes').upsert(
    {
      student_id: studentId, platform: 'apple', auth_token: newAuthToken(),
      content_hash: card.hash, company_id: card.content.company?.id ?? null,
    },
    { onConflict: 'student_id,platform', ignoreDuplicates: true },
  ).select('student_id');
  if (insertError) throw insertError;
  const { data: pass, error: passError } = await service
    .from('wallet_passes').select('auth_token').eq('student_id', studentId).eq('platform', 'apple').single();
  if (passError) throw passError;

  const pkpass = await renderApplePass(service, config, card.content, pass.auth_token);
  // An existing card may also sit on other devices: those are updated by wallet-sync, not here.
  if (!created?.length) await service.rpc('wallet_touch_students', { p_student_ids: [studentId] });
  return jsonResponse({ pkpass: toBase64(pkpass) });
}

async function issueGoogle(service: SupabaseClient, card: Card) {
  const config = googleConfig();
  if (!config) {
    return jsonResponse({ error: 'إضافة البطاقة إلى Google Wallet غير مفعّلة بعد.', reason: 'not_configured' }, 503);
  }
  const studentId = card.content.student.id;
  const { data: before } = await service.from('wallet_passes')
    .select('dirty_at').eq('student_id', studentId).eq('platform', 'google').maybeSingle();
  // One object per student: every device of that student shows it, so it is simply brought up to date.
  await deliverGoogle(service, config, card);
  await markDelivered(service, studentId, 'google', card, before?.dirty_at ?? null);
  return jsonResponse({ saveUrl: await buildSaveUrl(config, googleObjectId(config.issuerId, card.content.student)) });
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!token) return jsonResponse({ error: 'سجّل الدخول أولاً.' }, 401);
    const body = await request.json().catch(() => ({}));
    const platform = String(body.platform ?? '');
    if (platform !== 'apple' && platform !== 'google') {
      return jsonResponse({ error: 'نوع المحفظة غير مدعوم.' }, 400);
    }

    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) throw new Error('إعدادات بطاقة المحفظة غير مكتملة.');

    const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) return jsonResponse({ error: 'جلسة الدخول غير صالحة.' }, 401);

    // Only ever the caller's own card: the id comes from the session, never from the request.
    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const card = await loadCard(service, user.id);
    if (!card) return jsonResponse({ error: 'بطاقة المحفظة متاحة للطلاب فقط.' }, 403);
    await registerSyncUrl(service);

    return platform === 'apple' ? await issueApple(service, card) : await issueGoogle(service, card);
  } catch (error) {
    console.error('student-wallet-pass', error);
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء بطاقة المحفظة.') }, 400);
  }
});
