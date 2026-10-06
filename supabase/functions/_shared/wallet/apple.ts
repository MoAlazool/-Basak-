// Builds a signed Apple Wallet pass (.pkpass) and sends pass-update pushes.
import forge from 'npm:node-forge@1.3.1';
import { zipSync } from 'npm:fflate@0.8.2';

export interface AppleSigner {
  /** Pass Type ID certificate (PEM). */
  certPem: string;
  /** Its private key (PEM, unencrypted). */
  keyPem: string;
  /** Apple Worldwide Developer Relations intermediate certificate (PEM). */
  wwdrPem: string;
}

async function sha1Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-1', bytes.slice().buffer));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * pass.json + images -> manifest.json (SHA-1 of every file) -> detached
 * PKCS#7 signature of the manifest -> zip. `images` maps file names such as
 * "icon.png" / "logo@2x.png" / "strip.png" to PNG bytes.
 */
export async function buildPkpass(
  passJson: unknown, images: Record<string, Uint8Array>, signer: AppleSigner,
): Promise<Uint8Array> {
  if (!images['icon.png']) throw new Error('A pass needs icon.png.');
  const files: Record<string, Uint8Array> = {
    'pass.json': new TextEncoder().encode(JSON.stringify(passJson)),
    ...images,
  };

  const manifest: Record<string, string> = {};
  for (const [name, bytes] of Object.entries(files)) manifest[name] = await sha1Hex(bytes);
  const manifestText = JSON.stringify(manifest);

  const certificate = forge.pki.certificateFromPem(signer.certPem);
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(manifestText, 'utf8');
  p7.addCertificate(certificate);
  p7.addCertificate(forge.pki.certificateFromPem(signer.wwdrPem));
  p7.addSigner({
    key: forge.pki.privateKeyFromPem(signer.keyPem),
    certificate,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() },
    ],
  });
  p7.sign({ detached: true });
  const signature = forge.asn1.toDer(p7.toAsn1()).getBytes();

  return zipSync({
    ...files,
    'manifest.json': new TextEncoder().encode(manifestText),
    signature: Uint8Array.from(signature, (char: string) => char.charCodeAt(0)),
  });
}

export function toBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

// ---------------------------------------------------------------------------
// Pass update notifications
// ---------------------------------------------------------------------------

export interface ApplePushConfig {
  passTypeIdentifier: string;
  certPem: string;
  keyPem: string;
  /** api.push.apple.com in production (pass pushes only work there). */
  host: string;
  /** Extra CA (PEM) for the test double of APNs; never set in production. */
  caPem?: string;
}

export interface PushResult {
  ok: boolean;
  /** The token is dead: forget the device. */
  invalidToken: boolean;
  status: number;
  reason: string;
}

// deno-lint-ignore no-explicit-any
let pushClient: { key: string; client: any } | null = null;

/**
 * Tells one device that its pass changed. Per Apple: same certificate and key
 * that signed the pass, the device's push token, and an empty JSON payload.
 * The device then asks the web service which passes changed and fetches them.
 */
export async function sendPassUpdatePush(pushToken: string, config: ApplePushConfig): Promise<PushResult> {
  const cacheKey = `${config.host}\n${config.certPem}`;
  if (pushClient?.key !== cacheKey) {
    // deno-lint-ignore no-explicit-any
    const client = (Deno as any).createHttpClient({
      cert: config.certPem,
      key: config.keyPem,
      ...(config.caPem ? { caCerts: [config.caPem] } : {}),
    });
    pushClient = { key: cacheKey, client };
  }
  try {
    const response = await fetch(`https://${config.host}/3/device/${encodeURIComponent(pushToken)}`, {
      method: 'POST',
      headers: { 'apns-topic': config.passTypeIdentifier, 'content-type': 'application/json' },
      body: '{}',
      client: pushClient.client,
      // deno-lint-ignore no-explicit-any
    } as any);
    const text = await response.text();
    let reason = '';
    try { reason = String(JSON.parse(text).reason ?? ''); } catch { reason = text.slice(0, 120); }
    return {
      ok: response.ok,
      invalidToken: response.status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered',
      status: response.status,
      reason,
    };
  } catch (error) {
    return { ok: false, invalidToken: false, status: 0, reason: String(error).slice(0, 200) };
  }
}
