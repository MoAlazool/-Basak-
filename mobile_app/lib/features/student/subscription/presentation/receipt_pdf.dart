import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_catalog.dart';

/// The subscription receipt as a real, print-ready A4 document: text, tables
/// and totals laid out for paper, right to left.
///
/// Every value comes from the stored receipt ([SubscriptionReceipt]): the
/// snapshot the server wrote once when the payment was approved. Nothing is
/// read from the current screen, line, price or company settings, so a receipt
/// opened next year is the receipt issued today.
class ReceiptPdf {
  static const _ink = PdfColor.fromInt(0xFF17384A);
  static const _muted = PdfColor.fromInt(0xFF64788A);
  static const _brand = PdfColor.fromInt(0xFF00658D);
  static const _line = PdfColor.fromInt(0xFFD5E0E8);
  static const _soft = PdfColor.fromInt(0xFFF3F7FA);
  static const _green = PdfColor.fromInt(0xFF07865A);
  static const _greenSoft = PdfColor.fromInt(0xFFE7F8F0);

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

  static String number(int value) => value.toString().padLeft(5, '0');

  static String fileName(SubscriptionReceipt receipt) => 'basak-receipt-${number(receipt.number)}.pdf';

  static Future<pw.Font> _font(String weight) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-$weight.ttf'));

  /// Builds the document. [logo] is the company's logo image, when it could be
  /// loaded; the receipt is complete without it.
  static Future<Uint8List> build(SubscriptionReceipt r, {Uint8List? logo}) async {
    final regular = await _font('Regular');
    final semi = await _font('SemiBold');
    final bold = await _font('Bold');
    pw.TextStyle text(double size, {PdfColor color = _ink, pw.Font? font}) =>
        pw.TextStyle(font: font ?? regular, fontSize: size, color: color, lineSpacing: 1.5);

    final doc = pw.Document(
      title: 'إيصال اشتراك ${number(r.number)}',
      author: r.companyName,
      creator: 'Basak',
    );

    pw.Widget cell(String value, {bool head = false, pw.TextAlign align = pw.TextAlign.right, pw.Font? font, double size = 10.5}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: pw.Text(value,
              textAlign: align,
              textDirection: pw.TextDirection.rtl,
              style: text(size, color: head ? _muted : _ink, font: font ?? (head ? regular : semi))),
        );

    /// A titled block of "label : value" rows.
    pw.Widget block(String title, List<(String, String?)> rows) {
      final shown = rows.where((row) => (row.$2 ?? '').trim().isNotEmpty).toList();
      return pw.Container(
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: .8), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const pw.BoxDecoration(
                color: _soft,
                borderRadius: pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(6), topRight: pw.Radius.circular(6))),
            child: pw.Text(title, textDirection: pw.TextDirection.rtl, style: text(10.5, color: _brand, font: bold)),
          ),
          pw.Table(
            columnWidths: const {0: pw.FlexColumnWidth(1.9), 1: pw.FlexColumnWidth(1.25)},
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: .5)),
            children: [
              for (final row in shown)
                // Columns are listed left to right: the value, then its label on the right.
                pw.TableRow(children: [cell(row.$2!.trim()), cell(row.$1, head: true)]),
            ],
          ),
        ]),
      );
    }

    final legal = [
      if ((r.companyCommercialRegister ?? '').isNotEmpty) 'سجل تجاري: ${r.companyCommercialRegister}',
      if ((r.companyTaxNumber ?? '').isNotEmpty) 'رقم التسجيل الضريبي: ${r.companyTaxNumber}',
    ];
    final validity = r.startDate != null && r.endDate != null ? 'من ${day(r.startDate)} إلى ${day(r.endDate)}' : null;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 32),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        // ── Letterhead. The page runs right to left: the company first (right),
        //    the receipt box last (left).
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) ...[
            pw.Container(
              width: 58,
              height: 58,
              child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(r.companyName, textDirection: pw.TextDirection.rtl, style: text(19, font: bold)),
            pw.Text('خدمة نقل طلاب الجامعات', textDirection: pw.TextDirection.rtl, style: text(10, color: _muted)),
            if ((r.companyAddress ?? '').isNotEmpty)
              pw.Text(r.companyAddress!, textDirection: pw.TextDirection.rtl, style: text(9.5, color: _muted)),
            if ((r.companyPhone ?? '').isNotEmpty)
              pw.Text('هاتف: ${r.companyPhone}', textDirection: pw.TextDirection.rtl, style: text(9.5, color: _muted)),
          ]),
          pw.Spacer(),
          pw.Container(
            width: 168,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _brand, width: 1), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Text('إيصال اشتراك',
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl,
                  style: text(15, color: _brand, font: bold)),
              pw.SizedBox(height: 6),
              pw.Divider(color: _line, height: 1, thickness: .6),
              pw.SizedBox(height: 6),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(number(r.number), style: text(11, font: bold)),
                pw.Text('رقم الإيصال', textDirection: pw.TextDirection.rtl, style: text(9.5, color: _muted)),
              ]),
              pw.SizedBox(height: 3),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(day(r.approvedAt), textDirection: pw.TextDirection.rtl, style: text(10, font: semi)),
                pw.Text('التاريخ', textDirection: pw.TextDirection.rtl, style: text(9.5, color: _muted)),
              ]),
            ]),
          ),
        ]),
        pw.SizedBox(height: 14),
        pw.Container(height: 2, color: _brand),
        pw.SizedBox(height: 16),

        // ── Who paid, and for what.
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: block('بيانات الاشتراك', [
              ('الخط', r.lineName),
              ('محطة الصعود', r.stationName),
              ('فترة الاشتراك', r.periodLabel),
              ('الصلاحية', validity),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: block('بيانات الطالب', [
              ('الاسم', r.studentName),
              ('رقم الهاتف', r.studentPhone),
              ('الجامعة', r.universityName),
            ]),
          ),
        ]),
        pw.SizedBox(height: 16),

        // ── The charge.
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: .8),
          columnWidths: const {0: pw.FixedColumnWidth(120), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(34)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: _soft), children: [
              cell('المبلغ', head: true, align: pw.TextAlign.center, font: bold),
              cell('البيان', head: true, font: bold),
              cell('م', head: true, align: pw.TextAlign.center, font: bold),
            ]),
            pw.TableRow(children: [
              cell(money(r.amount), align: pw.TextAlign.center),
              cell('اشتراك نقل جامعي — ${r.periodLabel}'
                  '${(r.stationName ?? '').isEmpty ? '' : '\nخط ${r.lineName} · محطة ${r.stationName}'}'),
              cell('1', align: pw.TextAlign.center),
            ]),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          // Payment facts, on the right.
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: pw.BoxDecoration(color: _greenSoft, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Text('مدفوع — تم اعتماد الدفع وتفعيل الاشتراك',
                  textDirection: pw.TextDirection.rtl, style: text(10, color: _green, font: bold)),
            ),
            pw.SizedBox(height: 8),
            if ((r.paymentMethod ?? '').isNotEmpty)
              // Label and value apart: a Latin name (InstaPay) must not jump before the label.
              pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                pw.Text('وسيلة الدفع:', textDirection: pw.TextDirection.rtl, style: text(10.5)),
                pw.SizedBox(width: 4),
                pw.Text(r.paymentMethod!, textDirection: pw.TextDirection.rtl, style: text(10.5, font: semi)),
              ]),
            pw.Text('تاريخ الاعتماد: ${day(r.approvedAt)}', textDirection: pw.TextDirection.rtl, style: text(10.5)),
          ]),
          pw.Spacer(),
          // Total, on the left under the amount column.
          pw.Container(
            width: 210,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _brand, width: 1), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text(money(r.amount), textDirection: pw.TextDirection.rtl, style: text(10.5, font: semi)),
                  pw.Text('قيمة الاشتراك', textDirection: pw.TextDirection.rtl, style: text(10, color: _muted)),
                ]),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: const pw.BoxDecoration(
                    color: _brand,
                    borderRadius: pw.BorderRadius.only(
                        bottomLeft: pw.Radius.circular(5), bottomRight: pw.Radius.circular(5))),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text(money(r.amount),
                      textDirection: pw.TextDirection.rtl, style: text(14, color: PdfColors.white, font: bold)),
                  pw.Text('الإجمالي المدفوع',
                      textDirection: pw.TextDirection.rtl, style: text(11, color: PdfColors.white, font: semi)),
                ]),
              ),
            ]),
          ),
        ]),

        pw.Spacer(),

        // ── Footer.
        pw.Divider(color: _line, height: 1, thickness: .8),
        pw.SizedBox(height: 8),
        if (legal.isNotEmpty)
          pw.Text(legal.join('   ·   '),
              textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl, style: text(9, color: _muted)),
        pw.Text('هذا الإيصال صادر إلكترونياً ولا يحتاج إلى توقيع أو ختم.',
            textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl, style: text(9, color: _muted)),
        pw.SizedBox(height: 4),
        pw.Text('Powered by Basak',
            textAlign: pw.TextAlign.center, style: text(7.5, color: const PdfColor.fromInt(0xFF9AAAB7))),
      ]),
    ));
    return doc.save();
  }
}
