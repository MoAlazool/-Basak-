// What the wallet functions share: secrets, the card's content, its artwork,
// and delivering a card to Apple or Google.
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { type ApplePushConfig, type AppleSigner, buildPkpass, sendPassUpdatePush } from './apple.ts';
import { appleBackground } from './artwork.ts';
import { defaultAppleImages } from './default_assets.ts';
import { type GoogleConfig, upsertClass, upsertObject } from './google.ts';
import { APPLE_LOGO_FILES, buildApplePassJson, buildGoogleClass, buildGoogleObject, type CardContent } from './pass_data.ts';
import { appleThumbnails, hasUsablePhoto } from './photo.ts';

/** Secrets are pasted as PEM; some shells store the line breaks as a literal "\n". */
function pem(name: string): string | null {
  const value = Deno.env.get(name)?.trim();
  return value ? value.replace(/\\n/g, '\n') : null;
}

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) throw new Error('إعدادات بطاقة المحفظة غير مكتملة.');
  return createClient(url, serviceKey, { auth: { persistSession: false } });
}

/** The public address of this project, as Apple, Google and phones reach it. */
export function publicBaseUrl(): string {
  return (Deno.env.get('WALLET_PUBLIC_URL') ?? Deno.env.get('SUPABASE_URL') ?? '').replace(/\/+$/, '');
}

export interface AppleConfig extends AppleSigner {
  passTypeIdentifier: string;
  teamIdentifier: string;
  webServiceURL: string;
  push: ApplePushConfig;
}

/** null until the Apple secrets are set. */
export function appleConfig(): AppleConfig | null {
  const passTypeIdentifier = Deno.env.get('APPLE_PASS_TYPE_ID')?.trim();
  const teamIdentifier = Deno.env.get('APPLE_TEAM_ID')?.trim();
  const certPem = pem('APPLE_PASS_CERT_PEM');
  const keyPem = pem('APPLE_PASS_KEY_PEM');
  const wwdrPem = pem('APPLE_WWDR_PEM');
  if (!passTypeIdentifier || !teamIdentifier || !certPem || !keyPem || !wwdrPem) return null;
  return {
    passTypeIdentifier, teamIdentifier, certPem, keyPem, wwdrPem,
    webServiceURL: `${publicBaseUrl()}/functions/v1/wallet-apple-web/`,
    push: {
      passTypeIdentifier, certPem, keyPem,
      host: Deno.env.get('APPLE_APNS_HOST')?.trim() || 'api.push.apple.com',
      caPem: pem('APPLE_APNS_CA_PEM') ?? undefined,
    },
  };
}

/** null until the Google secrets are set. */
export function googleConfig(): GoogleConfig | null {
  const issuerId = Deno.env.get('GOOGLE_WALLET_ISSUER_ID')?.trim();
  const serviceAccountEmail = Deno.env.get('GOOGLE_WALLET_SA_EMAIL')?.trim();
  const privateKeyPem = pem('GOOGLE_WALLET_SA_PRIVATE_KEY');
  if (!issuerId || !serviceAccountEmail || !privateKeyPem) return null;
  return {
    issuerId, serviceAccountEmail, privateKeyPem,
    apiBase: (Deno.env.get('GOOGLE_WALLET_API_BASE')?.trim() || 'https://walletobjects.googleapis.com/walletobjects/v1').replace(/\/+$/, ''),
    tokenUrl: Deno.env.get('GOOGLE_OAUTH_TOKEN_URL')?.trim() || 'https://oauth2.googleapis.com/token',
  };
}

export interface Card {
  content: CardContent;
  /** Fingerprint of `content`, as the database computes it. */
  hash: string;
}

/** Everything the student's card shows right now, from the one place that decides it. */
export async function loadCard(service: SupabaseClient, studentId: string): Promise<Card | null> {
  const { data, error } = await service.rpc('wallet_card_payload', { p_student_id: studentId });
  if (error) throw error;
  return data ? { content: data.content as CardContent, hash: data.hash as string } : null;
}

/**
 * Tells the database where wallet-sync lives, so its triggers can wake it.
 * The functions know their own address; a migration cannot.
 */
let syncUrlKnown = false;
export async function registerSyncUrl(service: SupabaseClient): Promise<void> {
  if (syncUrlKnown) return;
  // Triggers call from inside the platform, so the internal address is the right one.
  const url = `${(Deno.env.get('SUPABASE_URL') ?? '').replace(/\/+$/, '')}/functions/v1/wallet-sync`;
  const { error } = await service.from('wallet_runtime').update({ sync_url: url }).eq('id', true);
  if (!error) syncUrlKnown = true;
}

function decodeBase64(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

// Artwork folders are revision-stamped and never rewritten, so they cache well.
const folderCache = new Map<string, Record<string, Uint8Array>>();

async function downloadFolder(service: SupabaseClient, folder: string, files: string[]) {
  const cached = folderCache.get(folder);
  if (cached) return cached;
  const images: Record<string, Uint8Array> = {};
  await Promise.all(files.map(async (file) => {
    const { data, error } = await service.storage.from('wallet-assets').download(`${folder}/${file}`);
    if (!error && data) images[file] = new Uint8Array(await data.arrayBuffer());
  }));
  if (folderCache.size > 16) folderCache.clear();
  folderCache.set(folder, images);
  return images;
}

/**
 * The images inside the .pkpass. The logo is the company's; a company without
 * one shows its name as text; only a card with no company carries the
 * platform's logo. The small notification icon always exists (Apple requires it).
 */
export async function loadAppleImages(service: SupabaseClient, content: CardContent) {
  const images: Record<string, Uint8Array> = {};
  for (const [name, value] of Object.entries(defaultAppleImages)) {
    if (name.startsWith('icon') || !content.company) images[name] = decodeBase64(value);
  }
  if (content.company?.logo_path) {
    Object.assign(images, await downloadFolder(service, content.company.logo_path, APPLE_LOGO_FILES));
  }
  Object.assign(images, await appleThumbnails(service, content.photo));
  Object.assign(images, await appleBackground(content.theme.background_color));
  return images;
}

/** The student's pass as it should look now. Same serial, token and QR every time. */
export async function renderApplePass(
  service: SupabaseClient, config: AppleConfig, content: CardContent, authenticationToken: string,
): Promise<Uint8Array> {
  const passJson = buildApplePassJson(content, {
    passTypeIdentifier: config.passTypeIdentifier,
    teamIdentifier: config.teamIdentifier,
    webServiceURL: config.webServiceURL,
    authenticationToken,
  });
  return buildPkpass(passJson, await loadAppleImages(service, content), config);
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export const newAuthToken = randomToken;

/**
 * The link Google uses to fetch the student's portrait: this project's
 * wallet-photo function plus a 256-bit random token. A new photo gets a new
 * token, so an old link stops working; no photo means no link.
 */
async function googlePhotoUrl(service: SupabaseClient, studentId: string, content: CardContent): Promise<string | null> {
  const usable = await hasUsablePhoto(service, content.photo);
  const { data: row, error } = await service.from('wallet_passes')
    .select('photo_token, photo_version').eq('student_id', studentId).eq('platform', 'google').maybeSingle();
  if (error) throw error;
  const version = usable ? content.photo!.version : null;
  let token = row?.photo_token ?? null;
  if (!usable) token = null;
  else if (!token || row?.photo_version !== version) token = randomToken();
  if (row && (token !== row.photo_token || version !== row.photo_version)) {
    const { error: saveError } = await service.from('wallet_passes')
      .update({ photo_token: token, photo_version: version }).eq('student_id', studentId).eq('platform', 'google');
    if (saveError) throw saveError;
  }
  return token ? `${publicBaseUrl()}/functions/v1/wallet-photo/${token}.jpg` : null;
}

let classReady = '';

/** Creates or replaces the student's Google object with the current content (same object id). */
export async function deliverGoogle(service: SupabaseClient, config: GoogleConfig, card: Card): Promise<void> {
  if (classReady !== config.issuerId) {
    await upsertClass(config, buildGoogleClass(config.issuerId));
    classReady = config.issuerId;
  }
  // The row must exist first: it is where the photo token is kept.
  const { error: rowError } = await service.from('wallet_passes').upsert(
    { student_id: card.content.student.id, platform: 'google' },
    { onConflict: 'student_id,platform', ignoreDuplicates: true },
  );
  if (rowError) throw rowError;
  const photoUrl = await googlePhotoUrl(service, card.content.student.id, card.content);
  await upsertObject(config, buildGoogleObject(card.content, {
    issuerId: config.issuerId, publicBaseUrl: publicBaseUrl(), photoUrl,
  }));
}

/**
 * Tells every device holding the student's pass that it changed. The devices
 * then fetch the new version themselves. Returns how many pushes failed.
 */
export async function pushAppleDevices(service: SupabaseClient, config: AppleConfig, studentId: string): Promise<number> {
  const { data: registrations, error } = await service.from('wallet_apple_registrations')
    .select('device_library_id, wallet_apple_devices(push_token)').eq('student_id', studentId);
  if (error) throw error;
  let failures = 0;
  for (const registration of registrations ?? []) {
    // deno-lint-ignore no-explicit-any
    const pushToken = (registration as any).wallet_apple_devices?.push_token as string | undefined;
    if (!pushToken) continue;
    const result = await sendPassUpdatePush(pushToken, config.push);
    if (result.invalidToken) {
      // Apple: "Delete a device if APNs returns an error that the push token is invalid."
      await service.from('wallet_apple_devices').delete().eq('device_library_id', registration.device_library_id);
    } else if (!result.ok) {
      failures += 1;
      console.warn('wallet push failed', result.status, result.reason);
    }
  }
  return failures;
}

/** Records that the wallet now shows `card` (and moves Apple's last-update tag). */
export async function markDelivered(
  service: SupabaseClient, studentId: string, platform: 'apple' | 'google', card: Card, claimedDirtyAt: string | null,
): Promise<void> {
  const { error } = await service.from('wallet_passes').update({
    content_hash: card.hash,
    company_id: card.content.company?.id ?? null,
    content_updated_at: new Date().toISOString(),
    last_error: null,
    claimed_at: null,
  }).eq('student_id', studentId).eq('platform', platform);
  if (error) throw error;
  // Leave the card queued if it changed again while this delivery was running.
  const clear = service.from('wallet_passes').update({ dirty_at: null })
    .eq('student_id', studentId).eq('platform', platform);
  const { error: clearError } = await (claimedDirtyAt ? clear.eq('dirty_at', claimedDirtyAt) : clear.is('dirty_at', null));
  if (clearError) throw clearError;
}
