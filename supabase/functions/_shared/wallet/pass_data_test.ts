// deno test supabase/functions/_shared/wallet/
import { assert, assertEquals, assertNotEquals, assertThrows } from 'jsr:@std/assert@1';
import {
  appleSerialNumber, barcodeMessage, buildApplePassJson, buildGoogleClass, buildGoogleObject, type CardContent,
  cardTitle, googleClassId, googleObjectId, hexToRgb, present, termLines,
} from './pass_data.ts';

const blue = { background_color: '#1565C0', foreground_color: '#FFFFFF', label_color: '#BBDEFB', card_title: null, banner_path: null, revision: 1 };
const orange = { ...blue, background_color: '#EF6C00', label_color: '#FFE0B2' };
const companyA = { id: 'a0000000-0000-0000-0000-00000000000a', name: 'المستقبل', logo_path: 'a0000000-0000-0000-0000-00000000000a/logo/s1', contact_phone: '0100 123 4567', contact_label: 'مكتب النقل' };
const companyB = { id: 'b0000000-0000-0000-0000-00000000000b', name: 'الشعراوي', logo_path: null, contact_phone: null, contact_label: null };

const sara: CardContent = {
  student: { id: 'c0000000-0000-0000-0000-000000000001', full_name: 'سارة أحمد', qr_code_value: '11111111-2222-3333-4444-555555555555', university: 'جامعة الدلتا', college: 'الهندسة' },
  photo: { path: 'c0000000-0000-0000-0000-000000000001/avatar.jpg', version: 'v1' },
  company: companyA, theme: blue, route: { line: 'منيه النصر', station: 'المحكمه', term: 'الفصل الدراسي الأول 2026/2027' },
};
const omar: CardContent = {
  student: { id: 'c0000000-0000-0000-0000-000000000002', full_name: 'عمر خالد', qr_code_value: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', university: 'جامعة المنصورة', college: null },
  photo: null, company: companyA, theme: blue, route: { line: 'الزرقا', station: 'ميت الخولي' },
};
const apple = {
  passTypeIdentifier: 'pass.com.example.basak', teamIdentifier: 'TEAM123456',
  webServiceURL: 'https://example.supabase.co/functions/v1/wallet-apple-web/', authenticationToken: 'x'.repeat(64),
};
const google = { issuerId: '3388000000012345678', publicBaseUrl: 'https://example.supabase.co', photoUrl: null as string | null };
const modules = (c: CardContent, photoUrl: string | null = null) => buildGoogleObject(c, { ...google, photoUrl });

Deno.test('the barcode is exactly the bare QR uuid on both platforms, with the Basak credit under it', () => {
  assertEquals(buildApplePassJson(sara, apple).barcodes, [{
    format: 'PKBarcodeFormatQR', message: sara.student.qr_code_value, messageEncoding: 'iso-8859-1',
    altText: 'Powered by Basak.app',
  }]);
  assertEquals(modules(sara).barcode,
    { type: 'QR_CODE', value: sara.student.qr_code_value, alternateText: 'Powered by Basak.app' });
});

Deno.test('a QR value that is not a uuid is refused instead of issued', () => {
  assertThrows(() => barcodeMessage({ ...sara, student: { ...sara.student, qr_code_value: 'https://evil.example/x' } }));
  assertThrows(() => barcodeMessage({ ...sara, student: { ...sara.student, qr_code_value: '' } }));
});

Deno.test('identity comes from the student id only', () => {
  assertEquals(appleSerialNumber(sara), sara.student.id);
  assertEquals(buildApplePassJson(sara, apple).serialNumber, sara.student.id);
  assertEquals(modules(sara).id, `${google.issuerId}.student_${sara.student.id}`);
  assertEquals(googleObjectId(google.issuerId, sara.student), modules(sara).id);
  assertEquals(modules(sara).classId, googleClassId(google.issuerId));
});

Deno.test('the company is the brand; the platform is only attribution', () => {
  const pass = buildApplePassJson(sara, apple);
  assertEquals(pass.logoText, 'المستقبل');
  assertEquals(pass.organizationName, 'المستقبل');
  assertEquals(modules(sara).cardTitle.defaultValue.value, 'المستقبل');
  const front = JSON.stringify({ ...pass.eventTicket, backFields: [] }) + pass.logoText;
  assert(!front.includes('باصك') && !front.includes('Basak'), 'the platform must not appear on the front');
  assert(pass.eventTicket.backFields.some((f) => f.value.includes('Powered by Basak.app')));
  assert(buildGoogleClass(google.issuerId).textModulesData.some((m) => m.body.includes('Powered by Basak.app')));
});

Deno.test('a company title override replaces the company name', () => {
  assertEquals(cardTitle({ ...sara, theme: { ...blue, card_title: 'المستقبل للنقل' } }), 'المستقبل للنقل');
});

Deno.test('a student with no company gets a neutral platform card', () => {
  const neutral: CardContent = { ...sara, company: null, route: null };
  assertEquals(cardTitle(neutral), 'باصك');
  assertEquals(buildApplePassJson(neutral, apple).eventTicket.secondaryFields, []);
});

Deno.test('two students of one company: same design, different identity', () => {
  const a = buildApplePassJson(sara, apple);
  const b = buildApplePassJson(omar, apple);
  for (const key of ['backgroundColor', 'foregroundColor', 'labelColor', 'logoText', 'organizationName'] as const) {
    assertEquals(a[key], b[key]);
  }
  assertNotEquals(a.serialNumber, b.serialNumber);
  assertNotEquals(a.barcodes[0].message, b.barcodes[0].message);
  assertNotEquals(a.eventTicket.primaryFields, b.eventTicket.primaryFields);
  assertNotEquals(a.eventTicket.secondaryFields, b.eventTicket.secondaryFields);

  const ga = modules(sara);
  const gb = modules(omar);
  assertEquals(ga.hexBackgroundColor, gb.hexBackgroundColor);
  assertEquals(ga.cardTitle, gb.cardTitle);
  assertEquals(ga.logo, gb.logo);
  assertNotEquals(ga.id, gb.id);
  assertNotEquals(ga.barcode.value, gb.barcode.value);
});

Deno.test('two companies have independent designs', () => {
  const a = buildApplePassJson(sara, apple);
  const b = buildApplePassJson({ ...omar, company: companyB, theme: orange }, apple);
  assertEquals(a.backgroundColor, 'rgb(21, 101, 192)');
  assertEquals(b.backgroundColor, 'rgb(239, 108, 0)');
  assertNotEquals(a.logoText, b.logoText);
  assertEquals(modules({ ...omar, company: companyB, theme: orange }).hexBackgroundColor, '#ef6c00');
});

Deno.test('changing design, company or route never changes the identity', () => {
  const before = buildApplePassJson(sara, apple);
  const moved: CardContent = { ...sara, company: companyB, theme: orange, route: { line: 'الزرقا', station: 'دقهله' } };
  const after = buildApplePassJson(moved, apple);
  assertNotEquals(before.backgroundColor, after.backgroundColor);
  assertNotEquals(before.logoText, after.logoText);
  assertNotEquals(before.eventTicket.secondaryFields, after.eventTicket.secondaryFields);
  assertEquals(before.serialNumber, after.serialNumber);
  assertEquals(before.barcodes, after.barcodes);
  assertEquals(before.authenticationToken, after.authenticationToken);
  assertEquals(before.passTypeIdentifier, after.passTypeIdentifier);
  assertEquals(modules(sara).id, modules(moved).id);
  assertEquals(modules(sara).barcode, modules(moved).barcode);
});

Deno.test('the Apple card is an pass with name alone, then station/line, the university and the term', () => {
  const pass = buildApplePassJson(sara, apple) as Record<string, unknown> & ReturnType<typeof buildApplePassJson>;
  assert(!('storeCard' in pass) && !('generic' in pass));
  assertEquals(pass.eventTicket.primaryFields, [{ key: 'name', value: 'سارة أحمد' }]);
  // Wallet fills a row from the left, so for Arabic the first thing to read is placed last (on the right).
  assertEquals(pass.eventTicket.secondaryFields, [
    { key: 'line', label: 'الخط', value: 'منيه النصر', textAlignment: 'PKTextAlignmentLeft' },
    { key: 'station', label: 'محطة الركوب', value: 'المحكمه', textAlignment: 'PKTextAlignmentRight' },
  ]);
  // A field alone in its row is pushed to the right edge by an empty field before it.
  // The university, and beside it the term with its year on the line below.
  assertEquals(pass.eventTicket.auxiliaryFields as unknown[], [
    { key: 'term', label: 'الاشتراك', value: 'الفصل الدراسي الأول\n2026/2027', textAlignment: 'PKTextAlignmentLeft' },
    { key: 'university', label: 'الجامعة', value: 'جامعة الدلتا', textAlignment: 'PKTextAlignmentRight' },
  ]);
  assertEquals(termLines('اشتراك يومي'), 'اشتراك يومي');
  assertEquals(termLines('الاشتراك السنوي 2026/2027'), 'الاشتراك السنوي\n2026/2027');
  assertEquals(termLines(null), null);
});

Deno.test('the college is not shown on either wallet, even when the database has one', () => {
  assert(!JSON.stringify(buildApplePassJson(sara, apple)).includes('الهندسة'));
  assert(!JSON.stringify(modules(sara)).includes('الهندسة'));
  assert(!JSON.stringify(buildGoogleClass(google.issuerId)).includes('college'));
});

Deno.test('missing optional data disappears: no placeholders anywhere', () => {
  const bare: CardContent = {
    ...sara, photo: null, route: null,
    student: { ...sara.student, university: '  ', college: 'غير محدد' },
    company: { ...companyA, logo_path: null, contact_phone: null, contact_label: null },
  };
  const pass = buildApplePassJson(bare, apple);
  assertEquals(pass.eventTicket.secondaryFields, []);
  assertEquals(pass.eventTicket.auxiliaryFields, []);
  assertEquals(pass.eventTicket.backFields.map((f) => f.key), ['note', 'platform']);
  const object = modules(bare);
  assertEquals(object.textModulesData, []);
  assertEquals(object.imageModulesData, []);
  assertEquals(object.linksModuleData.uris, []);
  assert(!('logo' in object) && !('heroImage' in object));
  for (const output of [JSON.stringify(pass), JSON.stringify(object)]) {
    for (const placeholder of ['غير محدد', 'N/A', 'Unknown', 'null', 'undefined', '"-"', '—']) {
      assert(!output.includes(placeholder), `must not contain ${placeholder}`);
    }
  }
  assertEquals(present('غير محدد'), null);
  assertEquals(present('  '), null);
  assertEquals(present(' الهندسة '), 'الهندسة');
});

Deno.test('route with only a line shows only the line', () => {
  const pass = buildApplePassJson({ ...sara, route: { line: 'الزرقا', station: null } }, apple);
  assertEquals(pass.eventTicket.secondaryFields.map((f) => f.key), ['route-spacer', 'line']);
  assertEquals(pass.eventTicket.secondaryFields[1], { key: 'line', label: 'الخط', value: 'الزرقا', textAlignment: 'PKTextAlignmentRight' });
  assertEquals(modules({ ...sara, route: { line: 'الزرقا', station: null } }).textModulesData.map((m) => m.id), ['line', 'university']);
  assertEquals(modules(sara).textModulesData.map((m) => m.id), ['station', 'line', 'university', 'term']);
});

Deno.test('the company contact is on the back/details with its own label, never a default person', () => {
  const pass = buildApplePassJson(sara, apple);
  assertEquals(pass.eventTicket.backFields.find((f) => f.key === 'contact'), { key: 'contact', label: 'مكتب النقل', value: '0100 123 4567' });
  assertEquals(modules(sara).linksModuleData.uris, [{ id: 'contact', uri: 'tel:01001234567', description: 'مكتب النقل: 0100 123 4567' }]);
  const unlabelled = buildApplePassJson({ ...sara, company: { ...companyA, contact_label: null } }, apple);
  assertEquals(unlabelled.eventTicket.backFields.find((f) => f.key === 'contact')?.label, 'للتواصل');
  const front = JSON.stringify({ ...pass.eventTicket, backFields: [] });
  assert(!front.includes('0100'), 'the contact must not be on the front');
});

Deno.test('the card carries no expiry and no subscription status', () => {
  const pass = JSON.stringify(buildApplePassJson(sara, apple));
  const object = JSON.stringify(modules(sara));
  for (const key of ['expirationDate', 'relevantDate', 'locations', 'voided', 'validTimeInterval', 'subscription', 'active', 'نشط', 'منتهي']) {
    assert(!pass.includes(key), `apple pass must not contain ${key}`);
    assert(!object.replace('"state":"ACTIVE"', '').toLowerCase().includes(key.toLowerCase()), `google object must not contain ${key}`);
  }
});

Deno.test('Google: photo goes in the details view through the given link only', () => {
  const url = 'https://example.supabase.co/functions/v1/wallet-photo/' + 'f'.repeat(64) + '.jpg';
  const object = modules(sara, url);
  assertEquals(object.imageModulesData.length, 1);
  assertEquals(object.imageModulesData[0].id, 'photo');
  assertEquals(object.imageModulesData[0].mainImage.sourceUri.uri, url);
  assert(!JSON.stringify(object).includes('avatar.jpg'), 'the storage path must never be exposed');
  assert(!JSON.stringify(buildApplePassJson(sara, apple)).includes('avatar.jpg'));
});

Deno.test('Google: one shared class holds the layout and no design', () => {
  const cls = buildGoogleClass(google.issuerId);
  assertEquals(cls.id, `${google.issuerId}.basak_student_card`);
  for (const key of ['hexBackgroundColor', 'logo', 'cardTitle', 'heroImage']) assert(!(key in cls));
  const rows = JSON.stringify(cls.classTemplateInfo.cardTemplateOverride);
  for (const id of ['line', 'station', 'university', 'term']) assert(rows.includes(`object.textModulesData['${id}']`));
  assertEquals(cls.classTemplateInfo.detailsTemplateOverride.detailsItemInfos.length, 4);
});

Deno.test('Google: logo and banner come from the company folders', () => {
  const object = modules({ ...sara, theme: { ...blue, banner_path: `${companyA.id}/banner/s9` } });
  assertEquals(object.logo?.sourceUri.uri, `https://example.supabase.co/storage/v1/object/public/wallet-assets/${companyA.id}/logo/s1/google.png`);
  assertEquals(object.heroImage?.sourceUri.uri, `https://example.supabase.co/storage/v1/object/public/wallet-assets/${companyA.id}/banner/s9/google.png`);
});

Deno.test('hex colours convert to the rgb() form Apple requires', () => {
  assertEquals(hexToRgb('#00897B'), 'rgb(0, 137, 123)');
  assertThrows(() => hexToRgb('teal'));
});
