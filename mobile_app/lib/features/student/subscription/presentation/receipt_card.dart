import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../models/sale_catalog.dart';

/// The proof of payment as the student sees, saves and shares it.
///
/// Every value comes from the stored receipt ([SubscriptionReceipt]), which the
/// server writes once at approval and never changes, so the document looks the
/// same whenever it is opened. The PDF and the image are this very card,
/// captured as drawn: Arabic is shaped by Flutter, with the app's own font.
class ReceiptCard extends StatelessWidget {
  final SubscriptionReceipt receipt;

  const ReceiptCard({super.key, required this.receipt});

  // Fixed colours: the saved document must not follow the phone's theme.
  static const _ink = Color(0xFF17384A);
  static const _muted = Color(0xFF718695);
  static const _brand = Color(0xFF00658D);
  static const _green = Color(0xFF07865A);
  static const _line = Color(0xFFE3EDF3);

  static TextStyle _text(double size, Color color, [FontWeight weight = FontWeight.w400]) =>
      TextStyle(fontFamily: 'ReadexPro', fontSize: size, color: color, fontWeight: weight, height: 1.35);

  static String money(double value) {
    final grouped = value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '$grouped ج.م';
  }

  /// "8 أكتوبر 2026" from an ISO date or timestamp.
  static String day(String? iso) {
    final date = iso == null ? null : DateTime.tryParse(iso);
    if (date == null) return iso ?? '—';
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final local = iso!.length > 10 ? date.toLocal() : date;
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  static String number(int value) => value.toString().padLeft(5, '0');

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.companyName, style: _text(17, _ink, FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('إيصال اشتراك', style: _text(12, _muted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('رقم الإيصال', style: _text(11, _muted)),
                Text(number(r.number),
                    textDirection: TextDirection.ltr, style: _text(16, _brand, FontWeight.w700)),
              ]),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
                color: const Color(0xFFE7F8F0), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(LucideIcons.circleCheck, size: 18, color: _green),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('تم اعتماد الدفع وتفعيل الاشتراك',
                      style: _text(13, _green, FontWeight.w600))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Column(children: [
              _row('الطالب', r.studentName),
              if ((r.studentPhone ?? '').isNotEmpty) _row('رقم الهاتف', r.studentPhone!, ltr: true),
              if ((r.universityName ?? '').isNotEmpty) _row('الجامعة', r.universityName!),
              _row('الخط', r.lineName),
              if ((r.stationName ?? '').isNotEmpty) _row('محطة الصعود', r.stationName!),
              _row('الفترة', r.periodLabel),
              if (r.startDate != null && r.endDate != null)
                _row('الصلاحية', 'من ${day(r.startDate)} إلى ${day(r.endDate)}'),
              if ((r.paymentMethod ?? '').isNotEmpty) _row('وسيلة الدفع', r.paymentMethod!),
              _row('تاريخ الاعتماد', day(r.approvedAt)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F6FB), borderRadius: BorderRadius.circular(13)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text('المبلغ المدفوع', style: _text(13, _ink))),
              Text(money(r.amount), style: _text(19, _brand, FontWeight.w700)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(
                color: Color(0xFFF7FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: _line))),
            child: Text('Powered by Basak',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: _text(11, _muted)),
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {bool ltr = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 104, child: Text(label, style: _text(12, _muted))),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.start,
                textDirection: ltr ? TextDirection.ltr : null,
                style: _text(13, _ink, FontWeight.w600)),
          ),
        ]),
      );
}

/// Saving and sharing the receipt shown inside a [RepaintBoundary] with [key].
class ReceiptExport {
  /// The card exactly as drawn, as a PNG (white page around it).
  static Future<Uint8List> png(GlobalKey key) async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('تعذر تجهيز الإيصال. حاول مرة أخرى.');
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw Exception('تعذر تجهيز الإيصال. حاول مرة أخرى.');
    return data.buffer.asUint8List();
  }

  /// One A4 page holding the same card.
  static Future<Uint8List> pdf(Uint8List png, {required String title}) async {
    final doc = pw.Document(title: title, creator: 'Basak');
    final image = pw.MemoryImage(png);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => pw.Align(
          alignment: pw.Alignment.topCenter,
          child: pw.Image(image, width: 380, fit: pw.BoxFit.contain)),
    ));
    return doc.save();
  }

  static String fileName(SubscriptionReceipt receipt, String extension) =>
      'basak-receipt-${ReceiptCard.number(receipt.number)}.$extension';

  /// Opens the system sheet: save to Files, print, or send. [origin] anchors
  /// the sheet on tablets.
  static Future<void> share(Uint8List bytes, String name, String mimeType, {Rect? origin}) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: name)], sharePositionOrigin: origin));
  }
}
