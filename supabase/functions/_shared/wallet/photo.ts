// The student's portrait, as an identity check on the card.
//
// The original stays in the private "student-avatars" bucket. Apple gets small
// square PNGs embedded in the student's own signed pass; Google gets a short
// JPEG strip through the wallet-photo function (see there). Nothing here makes a
// bucket public or hands out a storage path.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface PhotoRef { path: string; version: string }

/** The square every copy is cut from; nothing handed out is larger. */
export const PORTRAIT_SIDE = 480;

/** The card colour when a photo link carries none (links made before the strip; the database default). */
export const DEFAULT_STRIP_COLOUR = '00658d';

/** A card colour as a photo link carries it ('#00658D' -> '00658d'), or null when it is not one. */
export function photoLinkColour(hex: string | null | undefined): string | null {
  const match = /^#?([0-9a-f]{6})$/i.exec(String(hex ?? '').trim());
  return match ? match[1].toLowerCase() : null;
}

/** A few entries of at most PORTRAIT_SIDE x PORTRAIT_SIDE pixels each: bounded memory per isolate. */
function remember<T>(cache: Map<string, T>, key: string, value: T): T {
  if (cache.size > 16) cache.clear();
  cache.set(key, value);
  return value;
}

/** A square copy of a photo, PORTRAIT_SIDE pixels wide, ready to be handed out in the sizes the wallets want. */
export interface Square {
  png(side: number): Promise<Uint8Array>;
  /** Google's picture: a short JPEG strip, the photo in the middle on the card colour ('00658d'). */
  strip(colour: string): Promise<Uint8Array>;
}

/**
 * The picture work itself: bytes in, small square out (throws when the bytes
 * are not a still JPEG/PNG). It lives in artwork.ts with the image library and
 * is plugged in when that module loads, so everything in this file - who gets
 * a photo, what is cached, which token is valid - runs and is tested without
 * the library (which fetches its WebAssembly from deno.land as it loads).
 */
export const imaging: { square: ((original: Uint8Array) => Promise<Square>) | null } = { square: null };

const cacheKey = (photo: PhotoRef) => `${photo.path}|${photo.version}`;
const squares = new Map<string, Promise<Square | null>>();
const jpegs = new Map<string, Uint8Array>();

async function downloadSquare(service: SupabaseClient, photo: PhotoRef): Promise<Square | null> {
  // A function that forgot to load artwork.ts must fail loudly, not quietly issue cards without photos.
  const square = imaging.square;
  if (!square) throw new Error('The picture decoder is not loaded: import _shared/wallet/artwork.ts.');
  try {
    const { data, error } = await service.storage.from('student-avatars').download(photo.path);
    if (error || !data) throw error ?? new Error('no photo');
    return await square(new Uint8Array(await data.arrayBuffer()));
  } catch (error) {
    console.warn('wallet photo skipped:', String(error).slice(0, 200));
    return null;
  }
}

/**
 * The photo as a small square, or null when it is missing or not a JPEG/PNG.
 * Downloaded and decoded once per photo version; requests that arrive
 * meanwhile wait for the same download.
 */
function loadSquare(service: SupabaseClient, photo: PhotoRef): Promise<Square | null> {
  const key = cacheKey(photo);
  return squares.get(key) ?? remember(squares, key, downloadSquare(service, photo));
}

/** thumbnail.png at 1x/2x/3x (90 points) for an Apple pass, or {} when there is no usable photo. */
export async function appleThumbnails(service: SupabaseClient, photo: PhotoRef | null): Promise<Record<string, Uint8Array>> {
  const square = photo ? await loadSquare(service, photo) : null;
  if (!square) return {};
  const files: Record<string, Uint8Array> = {};
  for (const [name, size] of [['thumbnail.png', 90], ['thumbnail@2x.png', 180], ['thumbnail@3x.png', 270]] as const) {
    files[name] = await square.png(size);
  }
  return files;
}

/**
 * The photo for Google Wallet's details view, which shows a picture at the full
 * width of the screen: a short strip with the photo in the middle on the card
 * colour, so the card stays short. Never the original file. Encoded once per
 * photo version and colour.
 */
export async function portraitJpeg(service: SupabaseClient, photo: PhotoRef | null, colour: string): Promise<Uint8Array | null> {
  if (!photo) return null;
  const key = `${cacheKey(photo)}|${colour}`;
  const cached = jpegs.get(key);
  if (cached) return cached;
  const square = await loadSquare(service, photo);
  return square ? remember(jpegs, key, await square.strip(colour)) : null;
}

/** True when the photo can be shown (exists and decodes). */
export async function hasUsablePhoto(service: SupabaseClient, photo: PhotoRef | null): Promise<boolean> {
  return !!photo && !!(await loadSquare(service, photo));
}

/**
 * The portrait behind a wallet-photo link, or null when the token is unknown
 * (wrong, replaced by a newer photo, or gone with the card or the account) or
 * the student no longer has a usable photo.
 *
 * The token is checked against the database on every request; only the
 * picture work is remembered. One query finds the card and the photo's path,
 * without working out the whole card.
 */
export async function portraitForToken(
  service: SupabaseClient, token: string, colour = DEFAULT_STRIP_COLOUR,
): Promise<Uint8Array | null> {
  const { data: pass, error } = await service.from('wallet_passes')
    .select('photo_version, student:students(profile_image_url)')
    .eq('photo_token', token).eq('platform', 'google').maybeSingle();
  if (error) throw error;
  const path = String((pass?.student as { profile_image_url?: string | null } | null)?.profile_image_url ?? '').trim();
  if (!pass || !path) return null;
  // The version is the one this token was issued for (wallet-sync replaces the token with the photo).
  return portraitJpeg(service, { path, version: String(pass.photo_version ?? '') }, colour);
}
