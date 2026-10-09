// Egyptian mobile numbers, written the one way the database stores them
// (normalize_egyptian_phone): 11 digits starting with 01.

const EASTERN_DIGITS = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';

export function normalizeEgyptianPhone(value: unknown): string {
  let digits = String(value ?? '')
    .replace(/[٠-٩۰-۹]/g, (digit) => String(EASTERN_DIGITS.indexOf(digit) % 10))
    .replace(/\D/g, '');
  if (digits.startsWith('20') && digits.length >= 12) digits = digits.substring(2);
  if (digits.length === 10 && digits.startsWith('1')) digits = `0${digits}`;
  return digits;
}

export function isEgyptianMobile(phone: string): boolean {
  return /^01[0125][0-9]{8}$/.test(phone);
}

/** Students and supervisors sign in with their phone number as this address. */
export function loginEmail(phone: string): string {
  return `${phone}@busak.app`;
}
