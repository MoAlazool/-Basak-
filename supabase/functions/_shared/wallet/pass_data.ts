// Pure builders for the student Wallet card (no I/O, no secrets).
//
// Input is one CardContent object, produced by the database function
// wallet_card_content(): the student's identity, the company whose branding
// the card carries, that company's design, and - only for an approved
// subscription - the line and pickup station.
//
//   student  -> serial number / object id, name, QR        (never changes)
//   company  -> logo, name, contact                         (same for all its students)
//   theme    -> colours, title, banner                      (same for all its students)
//   route    -> line + pickup station                       (approved subscription only)
//
// Anything optional that is missing is left out entirely: no placeholders.

export interface CardContent {
  student: {
    id: string;
    full_name: string;
    /** students.qr_code_value: the permanent UUID the supervisor scans. */
    qr_code_value: string;
    university: string | null;
    college: string | null;
  };
  photo: { path: string; version: string } | null;
  company: {
    id: string;
    name: string;
    logo_path: string | null;
    contact_phone: string | null;
    contact_label: string | null;
  } | null;
  theme: {
    background_color: string; // #RRGGBB
    foreground_color: string; // Apple only
    label_color: string; // Apple only
    card_title: string | null;
    banner_path: string | null; // Google only
    revision: number;
  };
  /** From the approved subscription only: where the student rides, and for which term. */
  route: { line: string | null; station: string | null; term?: string | null } | null;
}

export const ASSET_BUCKET = 'wallet-assets';
export const APPLE_LOGO_FILES = ['icon.png', 'icon@2x.png', 'icon@3x.png', 'logo.png', 'logo@2x.png', 'logo@3x.png'];
export const GOOGLE_ASSET_FILE = 'google.png';

/** The platform's own name: the main brand only on a card with no company. */
export const PLATFORM_NAME = 'باصك';
const CARD_KIND = 'بطاقة نقل طلاب';
const VALIDITY_NOTE = 'هذه البطاقة للتعريف بالطالب. صلاحية الاشتراك يتحقق منها المشرف عند مسح الرمز.';
const POWERED_BY = 'تشغيل منصة باصك · Powered by Basak.app';
/**
 * The credit printed under the QR code on both wallets. Latin only: Apple
 * draws this line in the barcode's own encoding (ISO-8859-1).
 */
export const BARCODE_CREDIT = 'Powered by Basak.app';
const DEFAULT_CONTACT_LABEL = 'للتواصل';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MISSING = new Set(['', 'غير محدد', '-', '—', 'n/a', 'unknown']);

/** A value worth printing, or null. "غير محدد" is the database's way of saying "not set". */
export function present(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return MISSING.has(text.toLowerCase()) ? null : text;
}

/** The QR payload: exactly the UUID text, because the check-in RPC casts it to uuid. */
export function barcodeMessage(content: CardContent): string {
  const value = String(content.student.qr_code_value ?? '').trim();
  if (!UUID.test(value)) throw new Error('رمز الطالب غير صالح.');
  return value;
}

export function hexToRgb(hex: string): string {
  const match = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim());
  if (!match) throw new Error(`Invalid colour: ${hex}`);
  return `rgb(${parseInt(match[1], 16)}, ${parseInt(match[2], 16)}, ${parseInt(match[3], 16)})`;
}

export function assetUrl(publicBaseUrl: string, folder: string, file: string): string {
  return `${publicBaseUrl.replace(/\/+$/, '')}/storage/v1/object/public/${ASSET_BUCKET}/${folder}/${file}`;
}

/** The big name on the card: the company (or its chosen title); the platform only when there is no company. */
export function cardTitle(content: CardContent): string {
  return present(content.theme.card_title) ?? present(content.company?.name) ?? PLATFORM_NAME;
}

function contact(content: CardContent): { label: string; phone: string } | null {
  const phone = present(content.company?.contact_phone);
  return phone ? { label: present(content.company?.contact_label) ?? DEFAULT_CONTACT_LABEL, phone } : null;
}

// ---------------------------------------------------------------------------
// Apple Wallet: artwork behind the card, a portrait slot, and the QR
// ---------------------------------------------------------------------------

/** The pass serial number is the student id: it survives every change of company, design or route. */
export function appleSerialNumber(content: CardContent): string {
  return content.student.id;
}

export interface ApplePassOptions {
  passTypeIdentifier: string;
  teamIdentifier: string;
  /** Must end with "/": Wallet appends "v1/..." to it. */
  webServiceURL: string;
  authenticationToken: string;
}

/** "الفصل الدراسي الأول 2026/2027" -> the term's name, with the academic year on the line below it. */
export function termLines(term: string | null | undefined): string | null {
  const text = present(term);
  if (!text) return null;
  const match = /^(.*\S)\s+(\d{4}\s*\/\s*\d{4})$/.exec(text);
  return match ? `${match[1]}\n${match[2]}` : text;
}

/**
 * One row of the pass front, for right-to-left reading.
 *
 * Wallet always fills a row from the left and does not mirror it for Arabic
 * (checked with the phone in Arabic and in English, with and without Arabic
 * string tables). So the order is set here: the field to read first is placed
 * last, which puts it on the right, flush with the right edge like the card's
 * title above it. A field that is alone in its row would otherwise sit on the
 * left, so an empty field is put before it to push it to the right.
 * Explicit alignment also keeps a Latin value (a name, "Line 3") tidy.
 */
function rtlRow(
  row: string, fields: { key: string; label: string; value: string | null | undefined }[], line?: number,
) {
  const shown = fields.flatMap((f) => {
    const value = present(f.value);
    return value ? [{ key: f.key, label: f.label, value }] : [];
  });
  if (shown.length === 0) return [];
  const stacked = line === undefined ? {} : { row: line };
  const first = { ...shown[0], textAlignment: 'PKTextAlignmentRight', ...stacked };
  return shown.length === 1
    ? [{ key: `${row}-spacer`, value: '\u00A0', ...stacked }, first]
    : [{ ...shown[1], textAlignment: 'PKTextAlignmentLeft', ...stacked }, first];
}

export function buildApplePassJson(content: CardContent, options: ApplePassOptions) {
  const title = cardTitle(content);
  const reach = contact(content);
  return {
    formatVersion: 1,
    passTypeIdentifier: options.passTypeIdentifier,
    teamIdentifier: options.teamIdentifier,
    serialNumber: appleSerialNumber(content),
    webServiceURL: options.webServiceURL,
    authenticationToken: options.authenticationToken,
    organizationName: title,
    description: `${CARD_KIND} - ${title}`,
    logoText: title,
    backgroundColor: hexToRgb(content.theme.background_color),
    foregroundColor: hexToRgb(content.theme.foreground_color),
    labelColor: hexToRgb(content.theme.label_color),
    sharingProhibited: true,
    // "Event ticket" is the pass style that draws artwork behind the whole
    // card AND has a portrait slot; nothing about it is specific to events.
    eventTicket: {
      // The one line still visible when cards are stacked.
      headerFields: [{ key: 'kind', label: 'بطاقة', value: 'نقل طلاب' }],
      // The name stands alone beside the photo: a label there cannot be aligned
      // with an Arabic name, and the photo already says whose card this is.
      primaryFields: [{ key: 'name', value: content.student.full_name.trim() }],
      // Where the student boards comes first: it is what the supervisor checks.
      secondaryFields: rtlRow('route', [
        { key: 'station', label: 'محطة الركوب', value: content.route?.station },
        { key: 'line', label: 'الخط', value: content.route?.line },
      ]),
      // One quiet row, so the student's name stays the largest thing on the
      // card: the university (the app does not record a college) and, beside
      // it, the term of the approved subscription with its year underneath.
      auxiliaryFields: rtlRow('study', [
        { key: 'university', label: 'الجامعة', value: content.student.university },
        { key: 'term', label: 'الاشتراك', value: termLines(content.route?.term) },
      ]),
      backFields: [
        { key: 'note', label: 'تنبيه', value: VALIDITY_NOTE },
        ...(reach ? [{ key: 'contact', label: reach.label, value: reach.phone }] : []),
        { key: 'platform', label: 'المنصة', value: POWERED_BY },
      ],
    },
    barcodes: [{
      format: 'PKBarcodeFormatQR',
      message: barcodeMessage(content),
      messageEncoding: 'iso-8859-1',
      altText: BARCODE_CREDIT,
    }],
  };
}

// ---------------------------------------------------------------------------
// Google Wallet: Generic pass
// ---------------------------------------------------------------------------

/** One class for the whole platform: it holds layout only, never a design. */
export function googleClassId(issuerId: string): string {
  return `${issuerId}.basak_student_card`;
}

/** One object per student, derived from the student id only. */
export function googleObjectId(issuerId: string, student: { id: string }): string {
  return `${issuerId}.student_${student.id}`;
}

const localized = (value: string) => ({ defaultValue: { language: 'ar', value } });
const fieldRef = (path: string) => ({ firstValue: { fields: [{ fieldPath: path }] } });

/**
 * The shared class. Google's Generic class cannot hold colours, the logo or
 * the title - those live on every object - so this defines only where things
 * go. Rows and items whose value is missing collapse by themselves.
 */
export function buildGoogleClass(issuerId: string) {
  return {
    id: googleClassId(issuerId),
    multipleDevicesAndHoldersAllowedStatus: 'ONE_USER_ALL_DEVICES',
    textModulesData: [
      { id: 'note', header: 'تنبيه', body: VALIDITY_NOTE },
      { id: 'platform', header: 'المنصة', body: POWERED_BY },
    ],
    classTemplateInfo: {
      cardTemplateOverride: {
        cardRowTemplateInfos: [
          { twoItems: { startItem: fieldRef("object.textModulesData['station']"), endItem: fieldRef("object.textModulesData['line']") } },
          { oneItem: { item: fieldRef("object.textModulesData['university']") } },
          { oneItem: { item: fieldRef("object.textModulesData['term']") } },
        ],
      },
      // Below the card: the photo first, for a visual identity check.
      detailsTemplateOverride: {
        detailsItemInfos: [
          { item: fieldRef("object.imageModulesData['photo']") },
          { item: fieldRef("object.linksModuleData.uris['contact']") },
          { item: fieldRef("class.textModulesData['note']") },
          { item: fieldRef("class.textModulesData['platform']") },
        ],
      },
    },
  };
}

export interface GoogleObjectOptions {
  issuerId: string;
  /** Where the project's public storage lives. */
  publicBaseUrl: string;
  /** Unguessable link to the student's portrait, or null when there is no photo. */
  photoUrl: string | null;
}

export function buildGoogleObject(content: CardContent, options: GoogleObjectOptions) {
  const title = cardTitle(content);
  const text = (id: string, header: string, value: string | null | undefined) => {
    const body = present(value);
    return body ? [{ id, header, body }] : [];
  };
  const image = (uri: string, description: string) => ({
    sourceUri: { uri }, contentDescription: localized(description),
  });
  const reach = contact(content);
  const logoFolder = content.company?.logo_path;
  return {
    id: googleObjectId(options.issuerId, content.student),
    classId: googleClassId(options.issuerId),
    state: 'ACTIVE',
    genericType: 'GENERIC_TYPE_UNSPECIFIED',
    cardTitle: localized(title),
    subheader: localized(CARD_KIND),
    header: localized(content.student.full_name.trim()),
    hexBackgroundColor: content.theme.background_color.toLowerCase(),
    ...(logoFolder ? { logo: image(assetUrl(options.publicBaseUrl, logoFolder, GOOGLE_ASSET_FILE), title) } : {}),
    ...(content.theme.banner_path
      ? { heroImage: image(assetUrl(options.publicBaseUrl, content.theme.banner_path, GOOGLE_ASSET_FILE), title) } : {}),
    textModulesData: [
      ...text('station', 'محطة الركوب', content.route?.station),
      ...text('line', 'الخط', content.route?.line),
      ...text('university', 'الجامعة', content.student.university),
      ...text('term', 'الاشتراك', content.route?.term),
    ],
    imageModulesData: options.photoUrl
      ? [{ id: 'photo', mainImage: image(options.photoUrl, content.student.full_name.trim()) }] : [],
    linksModuleData: {
      uris: reach
        ? [{ id: 'contact', uri: `tel:${reach.phone.replace(/[^0-9+]/g, '')}`, description: `${reach.label}: ${reach.phone}` }] : [],
    },
    barcode: { type: 'QR_CODE', value: barcodeMessage(content), alternateText: BARCODE_CREDIT },
  };
}
