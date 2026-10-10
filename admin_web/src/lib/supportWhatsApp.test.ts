import { describe, expect, it } from 'vitest';
import { readableWhatsApp, whatsappDigits, whatsappLink } from './supportWhatsApp';

describe('support WhatsApp number', () => {
  it('takes an Egyptian mobile however it is written and adds the country code', () => {
    for (const input of ['01012345678', '010 1234 5678', '+20 101 234 5678', '00201012345678', '1012345678', '٠١٠١٢٣٤٥٦٧٨']) {
      expect(whatsappDigits(input)).toBe('201012345678');
    }
  });

  it('keeps another country as written, digits only', () => {
    expect(whatsappDigits('+966 50 123 4567')).toBe('966501234567');
  });

  it('an empty field clears the number; anything else that is not a number is refused', () => {
    expect(whatsappDigits('  ')).toBe('');
    expect(whatsappDigits('0101234')).toBeNull();
    expect(whatsappDigits('0123456789012345678')).toBeNull();
    expect(whatsappDigits('abc')).toBeNull();
  });

  it('reads back in groups and links to the chat', () => {
    expect(readableWhatsApp('201012345678')).toBe('+20 10 1234 5678');
    expect(readableWhatsApp('966501234567')).toBe('+966501234567');
    expect(whatsappLink('201012345678')).toBe('https://wa.me/201012345678');
  });
});
