import { supabase } from './supabase';

// Turns one uploaded image into the exact PNG files the Wallet cards need and
// stores them, with the untouched original, in a fresh folder of the company's
// own area of the public "wallet-assets" bucket. Nothing is ever overwritten:
// each upload gets a new folder and the company simply points at the newest. Apple
// wants fixed point sizes at 1x/2x/3x inside the pass; Google fetches one
// image by URL. Resizing happens here in the browser, so the server never
// processes images. File names must match supabase/functions/_shared/wallet/pass_data.ts.

const WALLET_BUCKET = 'wallet-assets';
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

/** Uploads every size of the artwork and returns its folder, e.g. "<company id>/logo/mf3k2a9x". */
export async function uploadWalletArtwork(companyId: string, kind: 'logo' | 'banner', file: File): Promise<string> {
  const image = await loadImage(file);
  const folder = `${companyId}/${kind}/${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  const longest = Math.max(image.naturalWidth, image.naturalHeight);
  const scale = Math.min(1, MASTER.width / longest);
  const master: Variant = { ...MASTER, width: Math.round(image.naturalWidth * scale), height: Math.round(image.naturalHeight * scale) };
  for (const variant of [master, ...(kind === 'logo' ? LOGO_VARIANTS : BANNER_VARIANTS)]) {
    const { error } = await supabase.storage.from(WALLET_BUCKET)
      .upload(`${folder}/${variant.file}`, await render(image, variant), { contentType: 'image/png', cacheControl: '31536000' });
    if (error) throw new Error(`تعذر رفع الصورة: ${error.message}`);
  }
  return folder;
}

export function walletArtworkUrl(folder: string, file: string): string {
  return supabase.storage.from(WALLET_BUCKET).getPublicUrl(`${folder}/${file}`).data.publicUrl;
}
