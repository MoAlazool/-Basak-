// The image library fetches its WebAssembly from deno.land while it loads, so
// these are the only wallet tests that need the network. In the default run
// (no permissions) they are skipped and the library is never loaded; to run them:
//
//   deno test --allow-net=deno.land supabase/functions/_shared/wallet/artwork_test.ts
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';

const online = (await Deno.permissions.query({ name: 'net', host: 'deno.land' })).state === 'granted';
const test = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !online, fn });

test('a tall photo becomes a 480px square taken from its upper part; thumbnails are 90/180/270', async () => {
  const { decode, Image } = await import('https://deno.land/x/imagescript@1.3.0/mod.ts');
  const { photoSquare } = await import('./artwork.ts');
  // Red above row 300, blue below. The crop is rows 60..660, so red ends 40% down the square.
  const tall = await new Image(600, 900).fill((_x: number, y: number) => y < 300 ? 0xff0000ff : 0x0000ffff).encode();
  const square = await photoSquare(tall);
  const jpeg = await square.jpeg();
  assertEquals([jpeg[0], jpeg[1]], [0xff, 0xd8]);
  const portrait = await decode(jpeg) as InstanceType<typeof Image>;
  assertEquals([portrait.width, portrait.height], [480, 480]);
  for (const side of [90, 180, 270]) {
    const thumbnail = await decode(await square.png(side)) as InstanceType<typeof Image>;
    assertEquals([thumbnail.width, thumbnail.height], [side, side]);
  }
  const small = await decode(await square.png(90)) as InstanceType<typeof Image>;
  assert(Image.colorToRGBA(small.getPixelAt(45, 20))[0] > 200, 'upper part is red');
  assert(Image.colorToRGBA(small.getPixelAt(45, 60))[2] > 200, 'lower part is blue');
});

test('bytes that are not a picture are refused', async () => {
  const { photoSquare } = await import('./artwork.ts');
  await assertRejects(() => photoSquare(new TextEncoder().encode('not an image')));
});

test('loading the artwork module plugs the decoder into photo.ts', async () => {
  const { photoSquare } = await import('./artwork.ts');
  const { imaging } = await import('./photo.ts');
  assertEquals(imaging.square, photoSquare);
});

test('the card background is drawn once per colour, at 1x/2x/3x', async () => {
  const { decode, Image } = await import('https://deno.land/x/imagescript@1.3.0/mod.ts');
  const { appleBackground } = await import('./artwork.ts');
  const files = await appleBackground('#00658d');
  assertEquals(Object.keys(files), ['background.png', 'background@2x.png', 'background@3x.png']);
  const widths = [];
  for (const bytes of Object.values(files)) widths.push((await decode(bytes) as InstanceType<typeof Image>).width);
  assertEquals(widths, [180, 360, 540]);
  assertEquals(await appleBackground('#00658D'), files);
});

test("an Apple pass's images: icon always, the company's logo, the photo and the background, loaded together", async () => {
  const { Image } = await import('https://deno.land/x/imagescript@1.3.0/mod.ts');
  const { loadAppleImages } = await import('./apple_pass.ts');
  const { fakeSupabase } = await import('../testing/fake_supabase.ts');
  const { testCard } = await import('./testing.ts');
  const photo = await new Image(120, 120).fill(0x336699ff).encode();
  const fake = fakeSupabase({
    storage: (bucket, _method, args) => {
      const path = String(args[0]);
      if (bucket === 'student-avatars') return { data: new Blob([photo.slice().buffer]) };
      // The company uploaded only its 1x logo.
      return path.endsWith('/logo.png') ? { data: new Blob([new Uint8Array([9, 9])]) } : { error: { message: 'Object not found' } };
    },
  });
  const card = testCard({ photo: { path: 'student-9/a.png', version: 'v1' } });
  card.content.company!.logo_path = 'company-1/logo/s1';
  const images = await loadAppleImages(fake.client, card.content);
  assertEquals(Object.keys(images).sort(), [
    'background.png', 'background@2x.png', 'background@3x.png', 'icon.png', 'icon@2x.png', 'icon@3x.png',
    'logo.png', 'thumbnail.png', 'thumbnail@2x.png', 'thumbnail@3x.png',
  ]);
  assertEquals(images['logo.png'], new Uint8Array([9, 9]));
  // The logo folder and the photo were asked for before either answered.
  assertEquals(fake.timeline.slice(0, 7).every((entry) => entry.startsWith('start storage')), true);
  // The folder is remembered: a second pass of the same company downloads nothing more.
  await loadAppleImages(fake.client, card.content);
  assertEquals(fake.log.length, 7);

  // A card with no company carries the platform's own logo.
  const plain = await loadAppleImages(fakeSupabase().client, testCard({ company: null }).content);
  assert(plain['logo.png']?.length > 100 && plain['icon.png']?.length > 100);
});
