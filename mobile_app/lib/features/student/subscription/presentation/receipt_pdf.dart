import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/sale_catalog.dart';

/// The subscription receipt as a real, print-ready A4 document: text, one
/// table row and a total laid out for paper, right to left (board Invoice).
///
/// Every value comes from the stored receipt ([SubscriptionReceipt]): the
/// snapshot the server wrote once when the payment was approved. Nothing is
/// read from the current screen, line, price or company settings, so a receipt
/// opened next year is the receipt issued today.
class ReceiptPdf {
  // The canvas's own values. Each is dark enough on white, or light enough
  // under ink, to print in greyscale.
  static const _ink = PdfColor.fromInt(0xFF17384A);
  static const _ink2 = PdfColor.fromInt(0xFF476273);
  static const _ink3 = PdfColor.fromInt(0xFF58707F);
  static const _brand = PdfColor.fromInt(0xFF00658D);
  static const _rule = PdfColor.fromInt(0xFFC3D1DA);
  static const _ground = PdfColor.fromInt(0xFFF0F5F8);
  static const _tint = PdfColor.fromInt(0xFFE5F3FA);
  static const _success = PdfColor.fromInt(0xFF0A6B4A);

  /// The board is drawn at 96 px to the inch; paper is 72 points.
  static const _px = .75;

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// "8 أكتوبر 2026" from an ISO date or timestamp.
  static String day(String? iso) {
    final date = iso == null ? null : DateTime.tryParse(iso);
    if (date == null) return iso ?? '—';
    final local = iso!.length > 10 ? date.toLocal() : date;
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  static String money(double value) {
    final grouped = value
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '$grouped ج.م';
  }

  static String fileName(SubscriptionReceipt receipt) => 'basak-receipt-${receipt.code}.pdf';

  /// The year the receipt was issued in, for the rights line.
  static int issueYear(SubscriptionReceipt receipt) {
    final at = DateTime.tryParse(receipt.approvedAt);
    return (at == null ? DateTime.now() : at.toLocal()).year;
  }

  /// The last line of the page: the rights notice, and the issue year with
  /// the product's name. (No commercial register and no tax number are
  /// printed anywhere on the receipt.)
  static (String, String) rights(SubscriptionReceipt receipt) =>
      ('جميع الحقوق محفوظة', '© ${issueYear(receipt)} Basak.app');

  /// The same document as a picture: the first page of the PDF drawn at print
  /// quality, so the image is the receipt itself and not a photo of the screen.
  static Future<Uint8List> image(Uint8List pdf, {double dpi = 200}) async {
    await for (final page in Printing.raster(pdf, pages: const [0], dpi: dpi)) {
      return flattenOnWhite(await page.toPng());
    }
    throw Exception('تعذر تجهيز صورة الإيصال.');
  }

  /// A JPEG of [png] on a white sheet: no transparency can survive, whatever
  /// the gallery or the app it is sent to does with see-through pictures.
  static Uint8List flattenOnWhite(Uint8List png) {
    final picture = img.decodePng(png);
    if (picture == null) return png;
    final sheet = img.Image(width: picture.width, height: picture.height, numChannels: 3)
      ..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(sheet, picture);
    return img.encodeJpg(sheet, quality: 92);
  }

  /// What the student sees as the receipt's number: its reference, which does
  /// not count the company's customers.
  static String reference(SubscriptionReceipt receipt) => receipt.code;

  static Future<pw.Font> _font(String weight) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-$weight.ttf'));

  static final _arabic = RegExp(r'[؀-ۿ]');

  /// Builds the document. [logo] is the company's logo image, when it could be
  /// loaded; the receipt is complete without it.
  static Future<Uint8List> build(SubscriptionReceipt r, {Uint8List? logo}) async {
    final regular = await _font('Regular');
    final semi = await _font('SemiBold');
    final bold = await _font('Bold');
    pw.TextStyle text(double px, {PdfColor color = _ink, pw.Font? font}) =>
        pw.TextStyle(font: font ?? regular, fontSize: px * _px, color: color, lineSpacing: 1.5);
    String? filled(String? value) => (value ?? '').trim().isEmpty ? null : value!.trim();

    final doc = pw.Document(
      title: 'إيصال اشتراك ${r.code}',
      author: r.companyName,
      creator: 'Basak',
    );

    pw.Widget rtl(String value, pw.TextStyle style) =>
        pw.Text(value, textDirection: pw.TextDirection.rtl, style: style);
    // Codes, phone numbers and Latin names read left to right.
    pw.Widget ltr(String value, pw.TextStyle style) =>
        pw.Text(value, textDirection: pw.TextDirection.ltr, style: style);
    pw.Widget words(String value, pw.TextStyle style) =>
        _arabic.hasMatch(value) ? rtl(value, style) : ltr(value, style);
    // Rules are one pixel of the board; the one under the letterhead is two.
    pw.Widget rule(PdfColor color, [double px = 1]) => pw.Container(height: px * _px, color: color);

    /// "label ........ value" inside a column.
    pw.Widget fact(String label, String value, {PdfColor color = _ink, pw.Font? font}) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6 * _px),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            rtl(label, text(16, color: _ink2)),
            pw.SizedBox(width: 16 * _px),
            words(value, text(16, color: color, font: font ?? semi)),
          ]),
        );

    /// One stop of the route: its mark, its name and what it is.
    pw.Widget stop(String name, String caption, {required bool boarding}) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 9 * _px),
              child: pw.Container(
                width: 12 * _px,
                height: 12 * _px,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  color: boarding ? null : _brand,
                  border: pw.Border.all(color: _brand, width: 2 * _px),
                ),
              ),
            ),
            pw.SizedBox(width: 16 * _px),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                rtl(name, text(18, font: semi)),
                rtl(caption, text(13, color: _ink2)),
              ]),
            ),
          ],
        );

    final station = filled(r.stationName);
    final university = filled(r.universityName);
    final method = filled(r.paymentMethod);
    final address = filled(r.companyAddress);
    final companyPhone = filled(r.companyPhone);
    final studentPhone = filled(r.studentPhone);
    final line = r.lineName.trim();
    final lineTitle = line.startsWith('خط ') ? line : 'خط $line';
    final hasValidity = r.startDate != null && r.endDate != null;

    doc.addPage(pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(72 * _px),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        // Paper is white. Without this the page has no background at all, and
        // a picture made from it is see-through.
        buildBackground: (_) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: PdfColors.white)),
      ),
      build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        // ── Letterhead. The page runs right to left: the company first (right),
        //    the receipt's title and code last (left).
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) ...[
            pw.Container(
              width: 64 * _px,
              height: 64 * _px,
              padding: const pw.EdgeInsets.all(6 * _px),
              decoration: pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.circular(16 * _px)),
              child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 16 * _px),
          ],
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12 * _px),
              child: rtl(r.companyName, text(22, font: semi)),
            ),
          ),
          pw.SizedBox(width: 32 * _px),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            rtl('إيصال اشتراك', text(28, font: semi)),
            ltr(r.code, text(16, color: _brand, font: semi)),
          ]),
        ]),
        pw.SizedBox(height: 36 * _px),
        rule(_ink, 2),
        pw.SizedBox(height: 36 * _px),

        // ── Who it was issued to, and how it was paid.
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              rtl('صادر إلى', text(13, color: _ink2)),
              pw.SizedBox(height: 10 * _px),
              rtl(r.studentName, text(18, font: semi)),
              if (university != null) ...[pw.SizedBox(height: 6 * _px), rtl(university, text(16))],
              if (studentPhone != null) ...[pw.SizedBox(height: 6 * _px), ltr(studentPhone, text(16))],
            ]),
          ),
          pw.SizedBox(width: 40 * _px),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              rtl('الدفع', text(13, color: _ink2)),
              pw.SizedBox(height: 4 * _px),
              fact('تاريخ الاعتماد', day(r.approvedAt)),
              if (method != null) fact('وسيلة الدفع', method),
              fact('الحالة', 'مدفوع ومعتمد', color: _success, font: bold),
            ]),
          ),
        ]),
        pw.SizedBox(height: 36 * _px),

        // ── The route and how long it is valid.
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 28 * _px, vertical: 24 * _px),
          decoration: pw.BoxDecoration(color: _ground, borderRadius: pw.BorderRadius.circular(20 * _px)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                stop(station ?? lineTitle, station == null ? 'الخط' : 'محطة الصعود · $lineTitle', boarding: true),
                if (university != null) ...[
                  pw.SizedBox(height: 14 * _px),
                  stop(university, 'الوجهة', boarding: false),
                ],
              ]),
            ),
            if (hasValidity) ...[
              pw.SizedBox(width: 40 * _px),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                rtl('صالح من', text(13, color: _ink2)),
                rtl(day(r.startDate), text(18, font: semi)),
                pw.SizedBox(height: 10 * _px),
                rtl('إلى', text(13, color: _ink2)),
                rtl(day(r.endDate), text(18, font: semi)),
              ]),
            ],
          ]),
        ),
        pw.SizedBox(height: 36 * _px),

        // ── The charge: one row.
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          rtl('البيان', text(13, color: _ink2)),
          rtl('المبلغ', text(13, color: _ink2)),
        ]),
        pw.SizedBox(height: 12 * _px),
        rule(_ink),
        pw.SizedBox(height: 18 * _px),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              rtl('اشتراك نقل جامعي · ${r.periodLabel}', text(16, font: semi)),
              rtl(station == null ? lineTitle : '$lineTitle · محطة $station', text(14, color: _ink2)),
            ]),
          ),
          pw.SizedBox(width: 16 * _px),
          rtl(money(r.amount), text(16, font: semi)),
        ]),
        pw.SizedBox(height: 18 * _px),
        rule(_rule),
        pw.SizedBox(height: 36 * _px),

        // ── The total, under the amount column.
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Container(
            width: 300 * _px,
            padding: const pw.EdgeInsets.symmetric(horizontal: 20 * _px, vertical: 18 * _px),
            decoration: pw.BoxDecoration(color: _ground, borderRadius: pw.BorderRadius.circular(16 * _px)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                rtl('الإجمالي المدفوع', text(16, font: semi)),
                rtl(money(r.amount), text(26, font: bold)),
              ],
            ),
          ),
        ]),

        pw.Spacer(),

        // ── Footer: where the company is, and what this page is.
        rule(_rule),
        pw.SizedBox(height: 20 * _px),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (address != null) rtl(address, text(13, color: _ink2)),
              if (companyPhone != null) ltr(companyPhone, text(13, color: _ink2)),
            ]),
          ),
          pw.SizedBox(width: 32 * _px),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            // The Latin name set apart, so it cannot jump before the Arabic words.
            pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
              rtl('صدر إلكترونياً عبر', text(13, color: _ink2)),
              pw.SizedBox(width: 3),
              ltr('Basak.app', text(13, color: _ink2)),
            ]),
            rtl('ولا يحتاج إلى توقيع أو ختم.', text(13, color: _ink2)),
          ]),
        ]),
        pw.SizedBox(height: 8 * _px),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          rtl(rights(r).$1, text(11, color: _ink3)),
          pw.SizedBox(width: 4),
          ltr('·', text(11, color: _ink3)),
          pw.SizedBox(width: 4),
          ltr(rights(r).$2, text(11, color: _ink3)),
        ]),
      ]),
    ));
    return doc.save();
  }
}
