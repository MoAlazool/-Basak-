import { supabase } from './supabase';
import { BRAND_BUCKET, isBrandPath, newBrandFolder, storedSize } from './branding';

// Turns one uploaded image into the exact PNG files the Wallet cards need and
// stores them, with the untouched original, in a fresh folder of the company's
// own area of the public "wallet-assets" bucket. Nothing is ever overwritten:
// each upload gets a new folder and the company simply points at the newest. Apple
// wants fixed point sizes at 1x/2x/3x inside the pass; Google fetches one
// image by URL. Resizing happens here in the browser, so the server never
// processes images. File names must match supabase/functions/_shared/wallet/pass_data.ts.
//
// The company's emblem (lib/branding.ts) is stored the same way, in the same bucket.

const WALLET_BUCKET = BRAND_BUCKET;
export const ACCEPTED_IMAGES = 'image/png,image/jpeg,image/webp';
const MAX_SOURCE_BYTES = 5 * 1024 * 1024;

// 'height': keep the height and let the width follow the image, up to the given width.
type Fit = 'contain' | 'cover' | 'height';
interface Variant { file: string; width: number; height: number; fit: Fit; }

const scales = (name: string, width: number, height: number, fit: Fit): Variant[] => [1, 2, 3].map((scale) => ({
  file: scale === 1 ? `${name}.png` : `${name}@${scale}x.png`, width: width * scale, height: height * scale, fit,
}));

const LOGO_VARIANTS: Variant[] = [
  ...scales('icon', 29, 29, 'contain'),
  ...scales('logo', 160, 50, 'height'),
  { file: 'google.png', width: 660, height: 660, fit: 'contain' },
];
// The banner is a Google Wallet feature only: Apple's ID-style pass has none.
const BANNER_VARIANTS: Variant[] = [{ file: 'google.png', width: 1032, height: 336, fit: 'cover' }];
/** The original, kept as uploaded (re-encoded as PNG, at most 1024px on its longer side). */
const MASTER: Variant = { file: 'master.png', width: 1024, height: 1024, fit: 'contain' };
/** The emblem: the whole picture centred on a square, at the size avatars need and at full size. */
const EMBLEM_VARIANTS: Variant[] = [
  { file: 'master.png', width: 512, height: 512, fit: 'contain' },
  { file: 'small.png', width: 128, height: 128, fit: 'contain' },
];

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => { URL.revokeObjectURL(url); resolve(image); };
    image.onerror = () => { URL.revokeObjectURL(url); reject(new Error('تعذر قراءة الصورة. اختر ملف PNG أو JPG أو WebP.')); };
    image.src = url;
  });
}

function render(image: HTMLImageElement, variant: Variant): Promise<Blob> {
  const canvas = document.createElement('canvas');
  canvas.width = variant.fit === 'height'
    ? Math.min(variant.width, Math.max(1, Math.round(variant.height * image.naturalWidth / image.naturalHeight)))
    : variant.width;
  canvas.height = variant.height;
  const context = canvas.getContext('2d');
  if (!context) throw new Error('المتصفح لا يدعم معالجة الصور.');
  const ratio = variant.fit === 'cover'
    ? Math.max(canvas.width / image.naturalWidth, canvas.height / image.naturalHeight)
    : Math.min(canvas.width / image.naturalWidth, canvas.height / image.naturalHeight);
  const width = image.naturalWidth * ratio;
  const height = image.naturalHeight * ratio;
  context.imageSmoothingQuality = 'high';
  context.drawImage(image, (canvas.width - width) / 2, (canvas.height - height) / 2, width, height);
  return new Promise((resolve, reject) => canvas.toBlob(
    (blob) => (blob ? resolve(blob) : reject(new Error('تعذر تجهيز الصورة.'))), 'image/png'));
}

export function validateImage(file: File): string | null {
  if (!ACCEPTED_IMAGES.split(',').includes(file.type)) return 'اختر صورة بصيغة PNG أو JPG أو WebP.';
  if (file.size > MAX_SOURCE_BYTES) return 'حجم الصورة يجب ألا يزيد عن 5 ميجابايت.';
  return null;
}

/** The picture's own size, read without uploading anything. */
export async function imageSize(file: File): Promise<{ width: number; height: number }> {
  const image = await loadImage(file);
  return { width: image.naturalWidth, height: image.naturalHeight };
}

/**
 * Uploads every size of the artwork and returns its folder, e.g. "<company id>/logo/mf3k2a9x".
 * A new folder every time: nothing already published is ever replaced in place.
 * If a file fails, what was uploaded of this folder is removed again.
 */
export async function uploadWalletArtwork(companyId: string, kind: 'logo' | 'banner' | 'emblem', file: File): Promise<string> {
  const image = await loadImage(file);
  const folder = newBrandFolder(companyId, kind);
  const master: Variant = { ...MASTER, ...storedSize('logo', image.naturalWidth, image.naturalHeight) };
  const variants = kind === 'emblem' ? EMBLEM_VARIANTS : [master, ...(kind === 'logo' ? LOGO_VARIANTS : BANNER_VARIANTS)];
  for (const variant of variants) {
    const { error } = await supabase.storage.from(WALLET_BUCKET)
      .upload(`${folder}/${variant.file}`, await render(image, variant), { contentType: 'image/png', cacheControl: '31536000' });
    if (error) {
      void removeArtworkFolders([folder]);
      throw new Error(`تعذر رفع الصورة: ${error.message}`);
    }
  }
  return folder;
}

/**
 * Removes the files of folders nothing shows any more (a replaced emblem, an
 * upload that was never saved). Best effort and never thrown: the database
 * refuses to delete a folder still in use (the current marks, the Wallet
 * banner, a logo printed on an issued receipt), whoever asks.
 */
export async function removeArtworkFolders(folders: readonly (string | null | undefined)[]): Promise<void> {
  for (const folder of folders) {
    if (!isBrandPath(folder)) continue;
    try {
      const { data } = await supabase.storage.from(WALLET_BUCKET).list(folder, { limit: 100 });
      const names = (data ?? []).map((entry) => `${folder}/${entry.name}`);
      if (names.length > 0) await supabase.storage.from(WALLET_BUCKET).remove(names);
    } catch { /* left for a later clean-up */ }
  }
}

export function walletArtworkUrl(folder: string, file: string): string {
  return supabase.storage.from(WALLET_BUCKET).getPublicUrl(`${folder}/${file}`).data.publicUrl;
}
