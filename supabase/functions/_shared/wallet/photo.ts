// The student's portrait, as an identity check on the card.
//
// The original stays in the private "student-avatars" bucket. Apple gets small
// square PNGs embedded in the student's own signed pass; Google gets a small
// JPEG through the wallet-photo function (see there). Nothing here makes a
// bucket public or hands out a storage path.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { decode, Image } from 'https://deno.land/x/imagescript@1.3.0/mod.ts';

export interface PhotoRef { path: string; version: string }

const squares = new Map<string, Image | null>();

/** The photo, centre-cropped to a square, or null when it is missing or not a JPEG/PNG. */
async function loadSquare(service: SupabaseClient, photo: PhotoRef): Promise<Image | null> {
  const key = `${photo.path}|${photo.version}`;
  if (squares.has(key)) return squares.get(key)!;
  let square: Image | null = null;
  try {
    const { data, error } = await service.storage.from('student-avatars').download(photo.path);
    if (error || !data) throw error ?? new Error('no photo');
    const decoded = await decode(new Uint8Array(await data.arrayBuffer()));
    if (!(decoded instanceof Image)) throw new Error('not a still image');
    const side = Math.min(decoded.width, decoded.height);
    // Portraits are framed towards the top, so keep the upper part of tall photos.
    const top = decoded.height > decoded.width ? Math.floor((decoded.height - side) * 0.2) : 0;
    square = decoded.crop(Math.floor((decoded.width - side) / 2), top, side, side);
  } catch (error) {
    console.warn('wallet photo skipped:', String(error).slice(0, 200));
  }
  if (squares.size > 16) squares.clear();
  squares.set(key, square);
  return square;
}

/** thumbnail.png at 1x/2x/3x (90 points) for an Apple pass, or {} when there is no usable photo. */
export async function appleThumbnails(service: SupabaseClient, photo: PhotoRef | null): Promise<Record<string, Uint8Array>> {
  const square = photo ? await loadSquare(service, photo) : null;
  if (!square) return {};
  const files: Record<string, Uint8Array> = {};
  for (const [name, size] of [['thumbnail.png', 90], ['thumbnail@2x.png', 180], ['thumbnail@3x.png', 270]] as const) {
    files[name] = await square.clone().resize(size, size).encode();
  }
  return files;
}

/** A small JPEG portrait for Google Wallet's details view: never the original file. */
export async function portraitJpeg(service: SupabaseClient, photo: PhotoRef | null): Promise<Uint8Array | null> {
  const square = photo ? await loadSquare(service, photo) : null;
  return square ? await square.clone().resize(480, 480).encodeJPEG(82) : null;
}

/** True when the photo can be shown (exists and decodes). */
export async function hasUsablePhoto(service: SupabaseClient, photo: PhotoRef | null): Promise<boolean> {
  return !!photo && !!(await loadSquare(service, photo));
}
