// The signed Apple pass as it should look now: its images and the .pkpass itself.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { buildPkpass } from './apple.ts';
import { appleBackground } from './artwork.ts';
import { defaultAppleImages } from './default_assets.ts';
import { APPLE_LOGO_FILES, buildApplePassJson, type CardContent } from './pass_data.ts';
import { appleThumbnails } from './photo.ts';
import type { AppleConfig } from './runtime.ts';

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

// The built-in artwork, decoded once per isolate.
let builtInImages: Record<string, Uint8Array> | undefined;
function defaultImages(): Record<string, Uint8Array> {
  return builtInImages ??= Object.fromEntries(Object.entries(defaultAppleImages).map(
    ([name, value]) => [name, Uint8Array.from(atob(value), (char) => char.charCodeAt(0))],
  ));
}

/**
 * The images inside the .pkpass. The logo is the company's; a company without
 * one shows its name as text; only a card with no company carries the
 * platform's logo. The small notification icon always exists (Apple requires it).
 */
export async function loadAppleImages(service: SupabaseClient, content: CardContent) {
  const images: Record<string, Uint8Array> = {};
  for (const [name, bytes] of Object.entries(defaultImages())) {
    if (name.startsWith('icon') || !content.company) images[name] = bytes;
  }
  // Three independent pieces, fetched or drawn at once; later ones win on a name clash.
  const [logo, thumbnails, background] = await Promise.all([
    content.company?.logo_path ? downloadFolder(service, content.company.logo_path, APPLE_LOGO_FILES) : {},
    appleThumbnails(service, content.photo),
    appleBackground(content.theme.background_color),
  ]);
  return Object.assign(images, logo, thumbnails, background);
}

/**
 * The student's pass as it should look now. Same serial, token and QR every
 * time. `images` may be passed when the caller started loading them earlier.
 */
export async function renderApplePass(
  service: SupabaseClient, config: AppleConfig, content: CardContent, authenticationToken: string,
  images?: Record<string, Uint8Array>,
): Promise<Uint8Array> {
  const passJson = buildApplePassJson(content, {
    passTypeIdentifier: config.passTypeIdentifier,
    teamIdentifier: config.teamIdentifier,
    webServiceURL: config.webServiceURL,
    authenticationToken,
  });
  return buildPkpass(passJson, images ?? await loadAppleImages(service, content), config);
}
