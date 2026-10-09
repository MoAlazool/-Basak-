// What the wallet functions share: secrets, the card's content, and delivering
// a card to Apple or Google. (What a pass looks like is in apple_pass.ts.)
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { type ApplePushConfig, type AppleSigner, type PushResult, sendPassUpdatePush } from './apple.ts';
import { type GoogleConfig, upsertClass, upsertObject } from './google.ts';
import { buildGoogleClass, buildGoogleObject, type CardContent } from './pass_data.ts';
import { hasUsablePhoto } from './photo.ts';

/** Secrets are pasted as PEM; some shells store the line breaks as a literal "\n". */
function pem(name: string): string | null {
  const value = Deno.env.get(name)?.trim();
  return value ? value.replace(/\\n/g, '\n') : null;
}

/** The public address of this project, as Apple, Google and phones reach it. */
function publicBaseUrl(): string {
  return (Deno.env.get('WALLET_PUBLIC_URL') ?? Deno.env.get('SUPABASE_URL') ?? '').replace(/\/+$/, '');
}

export interface AppleConfig extends AppleSigner {
  passTypeIdentifier: string;
  teamIdentifier: string;
  webServiceURL: string;
  push: ApplePushConfig;
}

// Secrets do not change while an isolate lives, so each set is read and parsed once.
let appleConfigMemo: AppleConfig | null | undefined;
let googleConfigMemo: GoogleConfig | null | undefined;

/** null until the Apple secrets are set. */
export function appleConfig(): AppleConfig | null {
  if (appleConfigMemo === undefined) appleConfigMemo = readAppleConfig();
  return appleConfigMemo;
}

function readAppleConfig(): AppleConfig | null {
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

/** The service account's JSON key file, pasted whole (alternative to the e-mail + key secrets). */
function serviceAccountJson(): { client_email?: string; private_key?: string } {
  const raw = Deno.env.get('GOOGLE_WALLET_SA_JSON')?.trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    console.error('GOOGLE_WALLET_SA_JSON is not valid JSON: paste the whole key file.');
    return {};
  }
}

/** null until the Google secrets are set. */
export function googleConfig(): GoogleConfig | null {
  if (googleConfigMemo === undefined) googleConfigMemo = readGoogleConfig();
  return googleConfigMemo;
}

function readGoogleConfig(): GoogleConfig | null {
  const issuerId = Deno.env.get('GOOGLE_WALLET_ISSUER_ID')?.trim();
  const keyFile = serviceAccountJson();
  const serviceAccountEmail = Deno.env.get('GOOGLE_WALLET_SA_EMAIL')?.trim() || keyFile.client_email?.trim();
  const privateKeyPem = pem('GOOGLE_WALLET_SA_PRIVATE_KEY') ?? keyFile.private_key?.replace(/\\n/g, '\n') ?? null;
  if (!issuerId || !serviceAccountEmail || !privateKeyPem) return null;
  return {
    issuerId, serviceAccountEmail, privateKeyPem,
    apiBase: (Deno.env.get('GOOGLE_WALLET_API_BASE')?.trim() || 'https://walletobjects.googleapis.com/walletobjects/v1').replace(/\/+$/, ''),
    tokenUrl: Deno.env.get('GOOGLE_OAUTH_TOKEN_URL')?.trim() || 'https://oauth2.googleapis.com/token',
    publicBaseUrl: publicBaseUrl(),
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

/** 256 random bits, as hex: a pass's authentication token, or a photo link's token. */
export function newAuthToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** What is already recorded about a student's Google card (its wallet_passes row). */
export interface GooglePassState {
  photo_token: string | null;
  photo_version: string | null;
  /** Set once the object has been written to Google. */
  content_hash: string | null;
  dirty_at: string | null;
}

/** null when the student has no Google card yet. */
export async function loadGoogleState(service: SupabaseClient, studentId: string): Promise<GooglePassState | null> {
  const { data, error } = await service.from('wallet_passes')
    .select('photo_token, photo_version, content_hash, dirty_at')
    .eq('student_id', studentId).eq('platform', 'google').maybeSingle();
  if (error) throw error;
  return data;
}

/**
 * The link Google uses to fetch the student's portrait: this project's
 * wallet-photo function plus a 256-bit random token. A new photo gets a new
 * token, so an old link stops working; no photo means no link. The token is
 * saved before Google is given the link.
 */
async function googlePhotoUrl(
  service: SupabaseClient, config: GoogleConfig, card: Card, state: GooglePassState | null,
): Promise<string | null> {
  const photo = card.content.photo;
  let token: string | null = null;
  if (photo && state?.photo_token && state.photo_version === photo.version) {
    // This exact file was checked when its token was made: nothing to download.
    token = state.photo_token;
  } else if (await hasUsablePhoto(service, photo)) {
    token = newAuthToken();
  }
  const version = token ? photo!.version : null;

  const key = { student_id: card.content.student.id, platform: 'google' };
  if (!state) {
    // The card's row is created here, with the token already in it.
    const { error } = await service.from('wallet_passes')
      .upsert({ ...key, photo_token: token, photo_version: version }, { onConflict: 'student_id,platform' });
    if (error) throw error;
  } else if (token !== state.photo_token || version !== state.photo_version) {
    const { error } = await service.from('wallet_passes')
      .update({ photo_token: token, photo_version: version }).eq('student_id', key.student_id).eq('platform', 'google');
    if (error) throw error;
  }
  return token ? `${config.publicBaseUrl}/functions/v1/wallet-photo/${token}.jpg` : null;
}

let classReady: { issuerId: string; done: Promise<void> } | null = null;

/** The shared class is written once per isolate; cards delivered meanwhile wait for that one write. */
function ensureGoogleClass(config: GoogleConfig): Promise<void> {
  if (classReady?.issuerId === config.issuerId) return classReady.done;
  // It exists from the first card ever issued, so replacing it is tried first.
  const entry = { issuerId: config.issuerId, done: upsertClass(config, buildGoogleClass(config.issuerId), true) };
  entry.done.catch(() => { if (classReady === entry) classReady = null; });
  classReady = entry;
  return entry.done;
}

/**
 * Creates or replaces the student's Google object with the current content
 * (same object id). `state` is the card's wallet_passes row as the caller
 * already holds it, or null when there is none yet.
 */
export async function deliverGoogle(
  service: SupabaseClient, config: GoogleConfig, card: Card, state: GooglePassState | null,
): Promise<void> {
  const [photoUrl] = await Promise.all([googlePhotoUrl(service, config, card, state), ensureGoogleClass(config)]);
  await upsertObject(config, buildGoogleObject(card.content, {
    issuerId: config.issuerId, publicBaseUrl: config.publicBaseUrl, photoUrl,
  }), !!state?.content_hash);
}

export interface AppleDevice { device_library_id: string; push_token: string }

/** The devices holding each student's Apple pass, in one query for the whole batch. */
export async function loadAppleDevices(service: SupabaseClient, studentIds: string[]): Promise<Map<string, AppleDevice[]>> {
  const byStudent = new Map<string, AppleDevice[]>();
  if (studentIds.length === 0) return byStudent;
  const { data, error } = await service.from('wallet_apple_registrations')
    .select('student_id, device_library_id, wallet_apple_devices(push_token)').in('student_id', studentIds);
  if (error) throw error;
  for (const row of data ?? []) {
    // deno-lint-ignore no-explicit-any
    const pushToken = (row as any).wallet_apple_devices?.push_token as string | undefined;
    if (!pushToken) continue;
    const devices = byStudent.get(row.student_id) ?? [];
    devices.push({ device_library_id: row.device_library_id, push_token: pushToken });
    byStudent.set(row.student_id, devices);
  }
  return byStudent;
}

/**
 * Tells every device holding a pass that it changed, all at once. The devices
 * then fetch the new version themselves. Returns how many pushes failed.
 * `send` is only replaced by tests.
 */
export async function pushAppleDevices(
  service: SupabaseClient, config: AppleConfig, devices: AppleDevice[],
  send: (pushToken: string, config: ApplePushConfig) => Promise<PushResult> = sendPassUpdatePush,
): Promise<number> {
  const results = await Promise.all(devices.map((device) => send(device.push_token, config.push)));
  const dead: string[] = [];
  let failures = 0;
  results.forEach((result, index) => {
    if (result.invalidToken) {
      dead.push(devices[index].device_library_id);
    } else if (!result.ok) {
      failures += 1;
      console.warn('wallet push failed', result.status, result.reason);
    }
  });
  // Apple: "Delete a device if APNs returns an error that the push token is invalid."
  if (dead.length) await service.from('wallet_apple_devices').delete().in('device_library_id', dead);
  return failures;
}

/** Records that the wallet now shows `card` (and moves Apple's last-update tag). */
export async function markDelivered(
  service: SupabaseClient, studentId: string, platform: 'apple' | 'google', card: Card, claimedDirtyAt: string | null,
): Promise<void> {
  const shown = {
    content_hash: card.hash,
    company_id: card.content.company?.id ?? null,
    content_updated_at: new Date().toISOString(),
    last_error: null,
    claimed_at: null,
  };
  if (claimedDirtyAt) {
    // Usual case, one write: the card is still queued exactly as it was claimed, so it leaves the queue too.
    const { data, error } = await service.from('wallet_passes').update({ ...shown, dirty_at: null })
      .eq('student_id', studentId).eq('platform', platform).eq('dirty_at', claimedDirtyAt).select('student_id');
    if (error) throw error;
    if (data?.length) return;
  }
  // Not queued, or it changed again while this delivery was running: it stays queued as it is.
  const { error } = await service.from('wallet_passes').update(shown).eq('student_id', studentId).eq('platform', platform);
  if (error) throw error;
}
