// deno test supabase/functions/_shared/wallet/
// (The real decoder is checked in artwork_test.ts, which needs the network.)
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { fakeSupabase } from '../testing/fake_supabase.ts';
import { appleThumbnails, hasUsablePhoto, portraitForToken } from './photo.ts';
import { fakeImaging } from './testing.ts';

const TOKEN = 'b'.repeat(64);
const text = (bytes: Uint8Array | null) => bytes && new TextDecoder().decode(bytes);

/** A project with one Google card whose token is TOKEN, and that student's photo in storage. */
function project(path: string | null, version = 'v1', file = 'photo-a') {
  return fakeSupabase({
    db: (call) => ({
      data: call.filters.photo_token === TOKEN ? { photo_version: version, student: { profile_image_url: path } } : null,
    }),
    storage: (_bucket, method, args) => {
      assertEquals([method, args[0]], ['download', path]);
      return { data: new Blob([file]) };
    },
  });
}

Deno.test('a known token gets the photo strip, found with one query and no card computation', async () => {
  const pictures = fakeImaging();
  try {
    const fake = project('student-1/a.png');
    assertEquals(text(await portraitForToken(fake.client, TOKEN)), 'strip 00658d of photo-a');
    assertEquals(fake.log, ['select wallet_passes', 'storage student-avatars.download']);
    assertEquals(fake.db[0].filters, { photo_token: TOKEN, platform: 'google' });
    assertEquals(fake.db[0].columns, 'photo_version, student:students(profile_image_url)');
  } finally { pictures.restore(); }
});

Deno.test('the same photo is served again without downloading or decoding, but the token is still checked', async () => {
  const pictures = fakeImaging();
  try {
    const fake = project('student-2/a.png');
    const first = await portraitForToken(fake.client, TOKEN);
    assertEquals(await portraitForToken(fake.client, TOKEN), first);
    assertEquals(fake.log, ['select wallet_passes', 'storage student-avatars.download', 'select wallet_passes']);
    assertEquals(pictures.decoded(), 1);
  } finally { pictures.restore(); }
});

Deno.test("the strip takes the link's colour, and each colour is drawn once from one download", async () => {
  const pictures = fakeImaging();
  try {
    const fake = project('student-8/a.png');
    assertEquals(text(await portraitForToken(fake.client, TOKEN, 'aa3322')), 'strip aa3322 of photo-a');
    assertEquals(text(await portraitForToken(fake.client, TOKEN, 'aa3322')), 'strip aa3322 of photo-a');
    assertEquals(text(await portraitForToken(fake.client, TOKEN, '112233')), 'strip 112233 of photo-a');
    assertEquals([fake.count('storage student-avatars.download'), pictures.decoded()], [1, 1]);
  } finally { pictures.restore(); }
});

Deno.test('a new version of the photo is fetched afresh', async () => {
  const pictures = fakeImaging();
  try {
    await portraitForToken(project('student-3/a.png', 'v1').client, TOKEN);
    const next = project('student-3/a.png', 'v2', 'photo-b');
    assertEquals(text(await portraitForToken(next.client, TOKEN)), 'strip 00658d of photo-b');
    assertEquals(next.count('storage student-avatars.download'), 1);
  } finally { pictures.restore(); }
});

Deno.test('an unknown token, or a student without a photo, gets nothing and storage is never touched', async () => {
  const unknown = project('student-4/a.png');
  assertEquals(await portraitForToken(unknown.client, 'c'.repeat(64)), null);
  assertEquals(unknown.log, ['select wallet_passes']);

  for (const path of [null, '  ']) {
    const fake = project(path);
    assertEquals(await portraitForToken(fake.client, TOKEN), null);
    assertEquals(fake.log, ['select wallet_passes']);
  }
});

Deno.test('a file that is not a picture, or cannot be downloaded, is no photo', async () => {
  const pictures = fakeImaging();
  const quiet = console.warn;
  console.warn = () => {};
  try {
    assertEquals(await portraitForToken(project('student-5/a.pdf', 'v1', 'a pdf').client, TOKEN), null);
    const missing = fakeSupabase({ storage: () => ({ error: { message: 'Object not found' } }) });
    assertEquals(await hasUsablePhoto(missing.client, { path: 'student-5/gone.png', version: 'v1' }), false);
    assertEquals(pictures.decoded(), 1);
  } finally { console.warn = quiet; pictures.restore(); }
});

Deno.test("Apple's thumbnails come from one download, even when asked for twice at once", async () => {
  const pictures = fakeImaging();
  try {
    const fake = project('student-6/a.png');
    const photo = { path: 'student-6/a.png', version: 'v1' };
    const [files] = await Promise.all([appleThumbnails(fake.client, photo), appleThumbnails(fake.client, photo)]);
    assertEquals(fake.count('storage student-avatars.download'), 1);
    assertEquals(Object.fromEntries(Object.entries(files).map(([name, bytes]) => [name, text(bytes)])), {
      'thumbnail.png': 'png 90 of photo-a', 'thumbnail@2x.png': 'png 180 of photo-a', 'thumbnail@3x.png': 'png 270 of photo-a',
    });
    assertEquals(await appleThumbnails(fake.client, null), {});
  } finally { pictures.restore(); }
});

Deno.test('without the picture decoder a photo is an error, not a card quietly issued without one', async () => {
  const fake = project('student-7/a.png');
  await assertRejects(() => portraitForToken(fake.client, TOKEN), Error, 'artwork.ts');
});
