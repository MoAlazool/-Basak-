import { describe, expect, it } from 'vitest';
import {
  BRAND_BUCKET, brandFileUrl, checkBrandDimensions, checkBrandFile, companyInitials, emblemUrl, isBrandPath, isSquarish, logoUrl,
  newBrandFolder, nextPath, storedSize, withBranding,
} from './branding';
import { keys, shouldPersist } from './query';
import { affectedBy } from './sync';

const A = 'a0000000-0000-4000-8000-00000000000a';
const B = 'b0000000-0000-4000-8000-00000000000b';
const BASE = 'https://proj.supabase.co';
const MB = 1024 * 1024;

describe('stored artwork paths', () => {
  it('accepts a company folder of a known kind and nothing else', () => {
    expect(isBrandPath(`${A}/logo/mf3k2a9x`)).toBe(true);
    expect(isBrandPath(`${A}/emblem/s_1-x`)).toBe(true);
    expect(isBrandPath(`${A}/banner/s1`)).toBe(true);
    for (const bad of [null, undefined, '', 42, `${A}/logo`, `${A}/logo/`, `${A}/logo/s1/master.png`, `${A}/other/s1`,
      `${A}/emblem/../logo`, `../${A}/emblem/s1`, `https://evil.test/${A}/emblem/s1`, `${A}/emblem/s1?x=1`, `${A}/emblem/s 1`,
      `not-a-uuid/emblem/s1`, `${A}/emblem/${'x'.repeat(65)}`, ` ${A}/emblem/s1`]) {
      expect(isBrandPath(bad)).toBe(false);
    }
  });
  it('tells one company from another, and a logo from an emblem', () => {
    expect(isBrandPath(`${A}/emblem/s1`, A, 'emblem')).toBe(true);
    expect(isBrandPath(`${A}/emblem/s1`, A.toUpperCase(), 'emblem')).toBe(true);
    expect(isBrandPath(`${A}/emblem/s1`, B, 'emblem')).toBe(false);
    expect(isBrandPath(`${A}/emblem/s1`, A, 'logo')).toBe(false);
    expect(isBrandPath(`${B}/logo/s1`, A)).toBe(false);
  });
  it('names every upload differently, inside the company folder', () => {
    const first = newBrandFolder(A, 'emblem', 1_700_000_000_000, 0.123456);
    expect(isBrandPath(first, A, 'emblem')).toBe(true);
    expect(newBrandFolder(A, 'emblem', 1_700_000_000_001, 0.123456)).not.toBe(first);
    expect(newBrandFolder(A, 'emblem', 1_700_000_000_000, 0.654321)).not.toBe(first);
    expect(isBrandPath(newBrandFolder(A, 'logo', 0, 0), A, 'logo')).toBe(true);
    expect(isBrandPath(newBrandFolder(B, 'banner', Date.now(), 0.999999), B, 'banner')).toBe(true);
  });
});

describe('addresses', () => {
  it('builds the public address from a stored path, in one way', () => {
    expect(brandFileUrl(`${A}/logo/s1`, 'master.png', BASE)).toBe(`${BASE}/storage/v1/object/public/${BRAND_BUCKET}/${A}/logo/s1/master.png`);
    expect(brandFileUrl(`${A}/logo/s1`, 'icon@2x.png', `${BASE}/`)).toBe(`${BASE}/storage/v1/object/public/wallet-assets/${A}/logo/s1/icon@2x.png`);
  });
  it('builds nothing from an unexpected path or file name', () => {
    expect(brandFileUrl(null, 'master.png', BASE)).toBeNull();
    expect(brandFileUrl(`https://evil.test/x.png`, 'master.png', BASE)).toBeNull();
    expect(brandFileUrl(`${A}/logo/../../x`, 'master.png', BASE)).toBeNull();
    expect(brandFileUrl(`${A}/logo/s1`, '../master.png', BASE)).toBeNull();
    expect(brandFileUrl(`${A}/logo/s1`, 'mark.svg', BASE)).toBeNull();
  });
  it('a replaced picture has a new address, so no cache can serve the old one for it', () => {
    expect(emblemUrl({ emblem_path: `${A}/emblem/old` }, 40, BASE)).not.toBe(emblemUrl({ emblem_path: `${A}/emblem/new` }, 40, BASE));
    expect(emblemUrl({ emblem_path: `${A}/emblem/old` }, 40, BASE)).not.toContain('?');
  });
  it('the logo is its master file', () => {
    expect(logoUrl({ logo_path: `${A}/logo/s1` }, BASE)).toBe(`${BASE}/storage/v1/object/public/wallet-assets/${A}/logo/s1/master.png`);
    expect(logoUrl({ emblem_path: `${A}/emblem/s1` }, BASE)).toBeNull();
    expect(logoUrl(null, BASE)).toBeNull();
  });
  it('the square mark: the emblem at the size asked, else the logo on a square, else nothing', () => {
    const both = { logo_path: `${A}/logo/l1`, emblem_path: `${A}/emblem/e1` };
    expect(emblemUrl(both, 20, BASE)).toMatch(/\/emblem\/e1\/small\.png$/);
    expect(emblemUrl(both, 64, BASE)).toMatch(/\/emblem\/e1\/small\.png$/);
    expect(emblemUrl(both, 96, BASE)).toMatch(/\/emblem\/e1\/master\.png$/);
    expect(emblemUrl({ logo_path: `${A}/logo/l1`, emblem_path: null }, 40, BASE)).toMatch(/\/logo\/l1\/google\.png$/);
    expect(emblemUrl({ logo_path: `${A}/logo/l1` }, 40, BASE)).toMatch(/\/logo\/l1\/google\.png$/);
    expect(emblemUrl({ logo_path: null, emblem_path: null }, 40, BASE)).toBeNull();
    expect(emblemUrl({}, 40, BASE)).toBeNull();
    expect(emblemUrl(undefined, 40, BASE)).toBeNull();
    // A stored value that is not a folder is never turned into an address.
    expect(emblemUrl({ emblem_path: 'https://evil.test/a.png', logo_path: `${A}/logo/l1` }, 40, BASE)).toMatch(/\/logo\/l1\/google\.png$/);
  });
});

describe('the fallback initial', () => {
  it('is the letter that tells companies apart', () => {
    expect(companyInitials('شركة النورس')).toBe('ن');
    expect(companyInitials('النورس للنقل')).toBe('ن');
    expect(companyInitials('مؤسسة الشعراوي')).toBe('ش');
    expect(companyInitials('باصك')).toBe('ب');
    expect(companyInitials('الو')).toBe('ا');
    expect(companyInitials('شركة')).toBe('ش');
  });
  it('is two initials for a Latin name', () => {
    expect(companyInitials('Nile Buses')).toBe('NB');
    expect(companyInitials('the future company')).toBe('F');
    expect(companyInitials('basak')).toBe('B');
  });
  it('never comes back empty', () => {
    for (const empty of ['', '   ', null, undefined]) expect(companyInitials(empty)).toBe('؟');
  });
});

describe('what may be uploaded', () => {
  it('PNG, JPG and WebP up to 5 MB', () => {
    for (const type of ['image/png', 'image/jpeg', 'image/webp']) expect(checkBrandFile({ type, size: 300_000 })).toBeNull();
    expect(checkBrandFile({ type: 'image/png', size: 5 * MB })).toBeNull();
  });
  it('refuses SVG by name, other types, empty and oversized files', () => {
    expect(checkBrandFile({ type: 'image/svg+xml', size: 2000 })).toContain('SVG');
    for (const type of ['image/gif', 'application/pdf', 'text/html', '']) expect(checkBrandFile({ type, size: 2000 })).toBeTruthy();
    expect(checkBrandFile({ type: 'image/png', size: 0 })).toBeTruthy();
    expect(checkBrandFile({ type: 'image/png', size: 5 * MB + 1 })).toBeTruthy();
  });
  it('a logo may be wide, but not tiny and not a ribbon', () => {
    expect(checkBrandDimensions('logo', 1600, 500)).toBeNull();
    expect(checkBrandDimensions('logo', 300, 300)).toBeNull();
    expect(checkBrandDimensions('logo', 120, 40)).toBeNull();
    expect(checkBrandDimensions('logo', 100, 60)).toBeTruthy();
    expect(checkBrandDimensions('logo', 2000, 200)).toBeTruthy();
    expect(checkBrandDimensions('logo', 0, 0)).toBeTruthy();
  });
  it('an emblem needs 128 pixels on its shorter side', () => {
    expect(checkBrandDimensions('emblem', 512, 512)).toBeNull();
    expect(checkBrandDimensions('emblem', 128, 400)).toBeNull();
    expect(checkBrandDimensions('emblem', 127, 512)).toBeTruthy();
    expect(checkBrandDimensions('emblem', Number.NaN, 512)).toBeTruthy();
  });
  it('a logo is stored at most 1024 on its longer side, in its own shape, never enlarged', () => {
    expect(storedSize('logo', 4096, 1024)).toEqual({ width: 1024, height: 256 });
    expect(storedSize('logo', 1000, 3000)).toEqual({ width: 341, height: 1024 });
    expect(storedSize('logo', 640, 200)).toEqual({ width: 640, height: 200 });
    expect(storedSize('logo', 1024, 1024)).toEqual({ width: 1024, height: 1024 });
  });
  it('an emblem is always stored as a 512 square', () => {
    expect(storedSize('emblem', 4096, 1024)).toEqual({ width: 512, height: 512 });
    expect(storedSize('emblem', 200, 200)).toEqual({ width: 512, height: 512 });
  });
  it('knows a square when it sees one', () => {
    expect(isSquarish(512, 512)).toBe(true);
    expect(isSquarish(512, 540)).toBe(true);
    expect(isSquarish(512, 700)).toBe(false);
    expect(isSquarish(0, 0)).toBe(false);
  });
});

describe('saving', () => {
  it('keeps, removes or replaces each mark on its own', () => {
    expect(nextPath(`${A}/logo/l1`, undefined)).toBe(`${A}/logo/l1`);
    expect(nextPath(undefined, undefined)).toBeNull();
    expect(nextPath(`${A}/logo/l1`, null)).toBeNull();
    expect(nextPath(`${A}/logo/l1`, `${A}/logo/l2`)).toBe(`${A}/logo/l2`);
    expect(nextPath(null, `${A}/emblem/e1`)).toBe(`${A}/emblem/e1`);
  });
  it('puts the saved marks into that company\'s numbers and nobody else\'s', () => {
    const numbers = { company: { id: A, name: 'أ', logo_path: `${A}/logo/l1`, emblem_path: null as string | null }, members: 7 };
    const saved = { company_id: A, logo_path: null, emblem_path: `${A}/emblem/e1` };
    expect(withBranding(numbers, saved)).toEqual({ company: { id: A, name: 'أ', logo_path: null, emblem_path: `${A}/emblem/e1` }, members: 7 });
    const other = { company: { id: B, name: 'ب' }, members: 3 };
    expect(withBranding(other, saved)).toBe(other);
    expect(numbers.company.logo_path).toBe(`${A}/logo/l1`);
  });
  it('the marks live in the company\'s own cache entry, and the platform\'s list in the platform\'s', () => {
    expect(keys.company(A, 'overview')).toEqual(['c', A, 'overview']);
    expect(keys.company(A, 'overview')).not.toEqual(keys.company(B, 'overview'));
    expect(keys.platform('overview')[0]).toBe('platform');
    expect(shouldPersist(keys.company(A, 'overview'))).toBe(true);
  });
  it('a change to the company row refreshes its numbers (the marks) and the Wallet card page (the logo)', () => {
    expect(affectedBy({ table: 'companies' })).toEqual(expect.arrayContaining(['overview', 'walletCard']));
    expect(affectedBy({ table: 'companies' }, ['company', 'overview', 'settings', 'switches', 'vote'])).toEqual(['walletCard']);
  });
});
