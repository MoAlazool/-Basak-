/**
 * A profile photo as stored: the centred square of the picture, at most
 * `size` pixels, as JPEG (a phone photo of several MB becomes ~50 KB).
 */
export async function squareJpeg(file: File, size = 512): Promise<Blob> {
  if (!file.type.startsWith('image/')) throw new Error('اختر ملف صورة.');
  const bitmap = await createImageBitmap(file);
  const side = Math.min(bitmap.width, bitmap.height);
  const out = Math.min(size, side);
  const canvas = document.createElement('canvas');
  canvas.width = out;
  canvas.height = out;
  const context = canvas.getContext('2d');
  if (!context) throw new Error('تعذر تجهيز الصورة.');
  context.drawImage(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side, 0, 0, out, out);
  bitmap.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('تعذر تجهيز الصورة.'))), 'image/jpeg', 0.85));
}
