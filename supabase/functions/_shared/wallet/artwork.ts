// Everything that needs the image library.
//
// 1. The artwork drawn behind an Apple Wallet card: soft waves in the company's
//    own colour. It is decoration only - no text, no student data - and is
//    generated from the colour, so changing the semester colour changes it too.
// 2. Turning a student's photo into the small square the wallets are given
//    (Google's as a short strip). Loading this module plugs that into photo.ts.
import { decode, Image } from 'https://deno.land/x/imagescript@1.3.0/mod.ts';
import { imaging, PORTRAIT_SIDE, type Square } from './photo.ts';

const cache = new Map<string, Record<string, Uint8Array>>();

function channels(hex: string): number[] {
  const match = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim());
  return match ? [1, 2, 3].map((i) => parseInt(match[i], 16)) : [0, 101, 141];
}

const mix = (a: number[], b: number[], t: number) =>
  a.map((v, i) => v + (b[i] - v) * Math.max(0, Math.min(1, t)));

/** background.png at 1x/2x/3x (180 x 220 points), cached per colour. */
export async function appleBackground(hex: string): Promise<Record<string, Uint8Array>> {
  const key = hex.toUpperCase();
  const cached = cache.get(key);
  if (cached) return cached;

  const base = channels(key);
  const deep = mix(base, [0, 0, 0], 0.38);
  const light = mix(base, [255, 255, 255], 0.28);
  const shade = mix(base, [0, 0, 0], 0.18);
  const width = 540, height = 660;
  const art = new Image(width, height).fill((x, y) => {
    const u = x / width, v = y / height;
    let colour = mix(deep, base, u * 0.6 + v * 0.5);
    if (v > 0.62 + 0.10 * Math.sin(u * Math.PI * 1.6 + 0.4)) colour = mix(colour, light, 0.35);
    if (v > 0.78 + 0.07 * Math.sin(u * Math.PI * 2.1 + 2.0)) colour = mix(colour, shade, 0.55);
    return Image.rgbaToColor(Math.round(colour[0]), Math.round(colour[1]), Math.round(colour[2]), 255);
  });
  const files = {
    'background.png': await art.clone().resize(180, 220).encode(),
    'background@2x.png': await art.clone().resize(360, 440).encode(),
    'background@3x.png': await art.encode(),
  };
  if (cache.size > 12) cache.clear();
  cache.set(key, files);
  return files;
}

/** Google's strip: 3:1, the photo in the middle with rounded corners, the sides in the card colour. */
const STRIP_WIDTH = 960, STRIP_HEIGHT = 320, STRIP_PHOTO = 272, STRIP_CORNER = 28;

/** The photo, centre-cropped to a square of PORTRAIT_SIDE pixels. Throws when it is not a still JPEG/PNG. */
export async function photoSquare(original: Uint8Array): Promise<Square> {
  const decoded = await decode(original);
  if (!(decoded instanceof Image)) throw new Error('not a still image');
  const side = Math.min(decoded.width, decoded.height);
  // Portraits are framed towards the top, so keep the upper part of tall photos.
  const top = decoded.height > decoded.width ? Math.floor((decoded.height - side) * 0.2) : 0;
  // Only the small copy is kept: the original can be many megabytes of pixels.
  const square = decoded.crop(Math.floor((decoded.width - side) / 2), top, side, side).resize(PORTRAIT_SIDE, PORTRAIT_SIDE);
  return {
    png: (size) => square.clone().resize(size, size).encode(),
    strip: (colour) => {
      const [r, g, b] = channels(`#${colour}`);
      const photo = square.clone().resize(STRIP_PHOTO, STRIP_PHOTO).roundCorners(STRIP_CORNER);
      return new Image(STRIP_WIDTH, STRIP_HEIGHT).fill(Image.rgbaToColor(r, g, b, 255))
        .composite(photo, (STRIP_WIDTH - STRIP_PHOTO) / 2, (STRIP_HEIGHT - STRIP_PHOTO) / 2)
        .encodeJPEG(85);
    },
  };
}

imaging.square = photoSquare;
