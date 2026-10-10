import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_pdf.dart';

const full = SubscriptionReceipt(
  subscriptionId: 'sub1', code: '26-7F3A9C2E', companyName: 'المستقبل للنقل الجامعي', studentName: 'محمد عادل إبراهيم السيد',
  studentPhone: '01055512301', universityName: 'جامعة الدلتا للعلوم والتكنولوجيا', lineName: 'منيه النصر',
  stationName: 'البجلات', periodLabel: 'الفصل الدراسي الأول 2026/2027', startDate: '2026-09-05', endDate: '2027-01-30',
  amount: 8000, paymentMethod: 'InstaPay', approvedAt: '2026-10-08T10:00:00Z',
  companyPhone: '01012345678', companyAddress: 'المنصورة، شارع الجامعة، برج النور',
  companyCommercialRegister: '123456', companyTaxNumber: '987-654-321',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the receipt is a real PDF document built from the stored receipt alone', () async {
    final bytes = await ReceiptPdf.build(full);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    final body = String.fromCharCodes(bytes);
    // Text set in an embedded font, not a picture of the screen.
    expect(body.contains('/FontFile2'), isTrue);
    expect(body.contains('/Subtype /Image'), isFalse);
    expect(ReceiptPdf.fileName(full), 'basak-receipt-26-7F3A9C2E.pdf');
    final out = Platform.environment['RENDER_DIR'];
    if (out != null) File('$out/receipt.pdf').writeAsBytesSync(bytes);
  });

  test('a company with no address, phone or logo still gets a complete receipt', () async {
    const plain = SubscriptionReceipt(
      subscriptionId: 's', code: '26-AAAA0001', companyName: 'المستقبل', studentName: 'طالب', lineName: 'منيه النصر',
      periodLabel: 'الفصل الدراسي الأول 2026/2027', amount: 8000, approvedAt: '2026-10-08T10:00:00Z');
    final bytes = await ReceiptPdf.build(plain);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('the commercial register and the tax number are not printed', () async {
    // The same receipt, with and without them: the page drawn is the same.
    const without = SubscriptionReceipt(
      subscriptionId: 'sub1', code: '26-7F3A9C2E', companyName: 'المستقبل للنقل الجامعي',
      studentName: 'محمد عادل إبراهيم السيد', studentPhone: '01055512301',
      universityName: 'جامعة الدلتا للعلوم والتكنولوجيا', lineName: 'منيه النصر', stationName: 'البجلات',
      periodLabel: 'الفصل الدراسي الأول 2026/2027', startDate: '2026-09-05', endDate: '2027-01-30',
      amount: 8000, paymentMethod: 'InstaPay', approvedAt: '2026-10-08T10:00:00Z',
      companyPhone: '01012345678', companyAddress: 'المنصورة، شارع الجامعة، برج النور',
    );
    final a = await ReceiptPdf.build(full);
    final b = await ReceiptPdf.build(without);
    String pages(List<int> bytes) =>
        String.fromCharCodes(bytes).replaceAll(RegExp(r'/(CreationDate|ModDate) ?\([^)]*\)|/ID ?\[[^\]]*\]'), '');
    expect(pages(a), pages(b));
  });

  test('the last line carries the rights notice and the year the receipt was issued', () {
    expect(ReceiptPdf.rights(full), ('جميع الحقوق محفوظة', '© 2026 Basak.app'));
    const later = SubscriptionReceipt(
      subscriptionId: 's', code: '27-AAAA0001', companyName: 'المستقبل', studentName: 'طالب', lineName: 'منيه النصر',
      periodLabel: 'الفصل الدراسي الثاني 2026/2027', amount: 8000, approvedAt: '2027-02-10T10:00:00Z');
    expect(ReceiptPdf.rights(later).$2, '© 2027 Basak.app');
  });

  test('a picture of the receipt is on white, never see-through', () {
    // A see-through picture with one dark pixel, as the PDF renderer would hand over.
    final clear = img.Image(width: 4, height: 4, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 0));
    clear.setPixelRgba(1, 1, 20, 40, 60, 255);
    final flat = img.decodeJpg(ReceiptPdf.flattenOnWhite(img.encodePng(clear)))!;
    expect(flat.numChannels, 3, reason: 'no transparency left');
    final corner = flat.getPixel(3, 3);
    expect([corner.r, corner.g, corner.b].every((v) => v > 235), isTrue, reason: 'the empty page is white');
    expect(flat.getPixel(1, 1).r < 120, isTrue, reason: 'what was drawn is still there');
  });

  test('amounts and dates read naturally', () {
    expect(ReceiptPdf.money(8000), '8,000 ج.م');
    expect(ReceiptPdf.money(15000), '15,000 ج.م');
    expect(ReceiptPdf.money(50), '50 ج.م');
    expect(ReceiptPdf.day('2027-01-30'), '30 يناير 2027');
  });
}
