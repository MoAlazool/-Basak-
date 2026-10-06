// The artwork drawn behind an Apple Wallet card: soft waves in the company's
// own colour. It is decoration only - no text, no student data - and is
// generated from the colour, so changing the semester colour changes it too.
import { Image } from 'https://deno.land/x/imagescript@1.3.0/mod.ts';

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
