import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/presentation/receipt_pdf.dart';

const full = SubscriptionReceipt(
  subscriptionId: 'sub1', number: 7, companyName: 'المستقبل للنقل الجامعي', studentName: 'محمد عادل إبراهيم السيد',
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
    expect(ReceiptPdf.fileName(full), 'basak-receipt-00007.pdf');
    final out = Platform.environment['RENDER_DIR'];
    if (out != null) File('$out/receipt.pdf').writeAsBytesSync(bytes);
  });

  test('a company with no legal details or logo still gets a complete receipt', () async {
    const plain = SubscriptionReceipt(
      subscriptionId: 's', number: 1, companyName: 'المستقبل', studentName: 'طالب', lineName: 'منيه النصر',
      periodLabel: 'الفصل الدراسي الأول 2026/2027', amount: 8000, approvedAt: '2026-10-08T10:00:00Z');
    final bytes = await ReceiptPdf.build(plain);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });

  test('amounts and dates read naturally', () {
    expect(ReceiptPdf.money(8000), '8,000 ج.م');
    expect(ReceiptPdf.money(15000), '15,000 ج.م');
    expect(ReceiptPdf.money(50), '50 ج.م');
    expect(ReceiptPdf.day('2027-01-30'), '30 يناير 2027');
  });
}
