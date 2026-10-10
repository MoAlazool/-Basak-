/**
 * The platform's WhatsApp number for students who forgot their password (the
 * app's "enter the code" screen opens a chat with it). Stored as WhatsApp wants
 * it: country code first, digits only. Same rules as `save_support_whatsapp`,
 * which checks them again.
 */

const ARABIC_DIGITS = '٠١٢٣٤٥٦٧٨٩';

/**
 * '010 1234 5678', '+20 101 234 5678', '٠١٠١٢٣٤٥٦٧٨' → '201012345678'; '' for an
 * empty field (no number: the app shows no button); null when it is not a number.
 */
export function whatsappDigits(input: string): string | null {
  if (input.trim() === '') return '';
  let digits = input.replace(/[٠-٩]/g, (d) => String(ARABIC_DIGITS.indexOf(d))).replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (/^01[0125]\d{8}$/.test(digits)) digits = `2${digits}`;
  if (/^1[0125]\d{8}$/.test(digits)) digits = `20${digits}`; // the same without its 0
  return /^[1-9]\d{7,14}$/.test(digits) ? digits : null;
}

/** What the admin reads: '+20 10 1234 5678' for an Egyptian mobile, '+' and the digits otherwise. */
export function readableWhatsApp(digits: string): string {
  const egypt = /^20(1[0125])(\d{4})(\d{4})$/.exec(digits);
  return egypt ? `+20 ${egypt[1]} ${egypt[2]} ${egypt[3]}` : `+${digits}`;
}

/** The chat the app opens, to try it from the dashboard. */
export const whatsappLink = (digits: string) => `https://wa.me/${digits}`;
