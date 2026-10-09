// deno test supabase/functions/_shared/wallet/
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import forge from 'npm:node-forge@1.3.1';
import { unzipSync } from 'npm:fflate@0.8.2';
import { type AppleSigner, buildPkpass } from './apple.ts';

/** A throwaway key with a self-signed certificate, standing in for both of Apple's. */
function testSigner(name: string): AppleSigner {
  const keys = forge.pki.rsa.generateKeyPair({ bits: 1024, e: 0x10001 });
  const certificate = forge.pki.createCertificate();
  certificate.publicKey = keys.publicKey;
  certificate.serialNumber = '01';
  certificate.validity.notBefore = new Date(Date.now() - 60_000);
  certificate.validity.notAfter = new Date(Date.now() + 3_600_000);
  const subject = [{ name: 'commonName', value: name }];
  certificate.setSubject(subject);
  certificate.setIssuer(subject);
  certificate.sign(keys.privateKey, forge.md.sha256.create());
  const certPem = forge.pki.certificateToPem(certificate);
  return { certPem, keyPem: forge.pki.privateKeyToPem(keys.privateKey), wwdrPem: certPem };
}

async function sha1(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-1', bytes.slice().buffer));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** The certificate that signed the pass, and whether its signature really covers the manifest. */
function verify(files: Record<string, Uint8Array>) {
  const der = String.fromCharCode(...files.signature);
  // deno-lint-ignore no-explicit-any
  const p7 = forge.pkcs7.messageFromAsn1(forge.asn1.fromDer(der)) as any;
  const signer = p7.rawCapture;
  const attributes = forge.asn1.create(forge.asn1.Class.UNIVERSAL, forge.asn1.Type.SET, true, signer.authenticatedAttributes);
  const digest = forge.md.sha256.create().update(forge.asn1.toDer(attributes).getBytes()).digest().getBytes();
  const certificate = p7.certificates[0];
  return {
    commonName: certificate.subject.getField('CN').value as string,
    valid: certificate.publicKey.verify(digest, signer.signature) as boolean,
    // The digest of the manifest that the signed attributes carry.
    manifestDigest: forge.util.bytesToHex(
      // deno-lint-ignore no-explicit-any
      signer.authenticatedAttributes.find((a: any) => forge.asn1.derToOid(a.value[0].value) === forge.pki.oids.messageDigest)
        .value[1].value[0].value,
    ),
    expectedDigest: forge.md.sha256.create().update(new TextDecoder().decode(files['manifest.json']), 'utf8').digest().toHex(),
  };
}

const images = { 'icon.png': new Uint8Array([1, 2, 3]), 'logo.png': new Uint8Array([4, 5]) };
const first = testSigner('Pass Type ID: pass.app.basak.one');

Deno.test('a pass holds its files, a manifest of their hashes, and a signature over that manifest', async () => {
  const files = unzipSync(await buildPkpass({ serialNumber: 's1' }, images, first));
  assertEquals(Object.keys(files).sort(), ['icon.png', 'logo.png', 'manifest.json', 'pass.json', 'signature']);
  assertEquals(JSON.parse(new TextDecoder().decode(files['pass.json'])), { serialNumber: 's1' });
  const manifest = JSON.parse(new TextDecoder().decode(files['manifest.json']));
  assertEquals(Object.keys(manifest), ['pass.json', 'icon.png', 'logo.png']);
  for (const [name, hash] of Object.entries(manifest)) assertEquals(hash, await sha1(files[name]), name);
  const signature = verify(files);
  assert(signature.valid);
  assertEquals(signature.manifestDigest, signature.expectedDigest);
  assertEquals(signature.commonName, 'Pass Type ID: pass.app.basak.one');
});

Deno.test('the certificates are parsed once and still sign every later pass correctly', async () => {
  const again = unzipSync(await buildPkpass({ serialNumber: 's2' }, images, { ...first }));
  const signature = verify(again);
  assert(signature.valid);
  assertEquals(signature.manifestDigest, signature.expectedDigest);
});

Deno.test('a different certificate is never served from the remembered one', async () => {
  const second = testSigner('Pass Type ID: pass.app.basak.two');
  const files = unzipSync(await buildPkpass({ serialNumber: 's3' }, images, second));
  const signature = verify(files);
  assert(signature.valid);
  assertEquals(signature.commonName, 'Pass Type ID: pass.app.basak.two');
  // And back again.
  assertEquals(verify(unzipSync(await buildPkpass({ serialNumber: 's4' }, images, first))).commonName, 'Pass Type ID: pass.app.basak.one');
});

Deno.test('a pass without its icon is refused', async () => {
  await assertRejects(() => buildPkpass({}, { 'logo.png': new Uint8Array([1]) }, first), Error, 'icon.png');
});
