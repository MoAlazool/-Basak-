import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../models/sale_catalog.dart';
import 'purchase_flow.dart' show formatMoney;

/// The proof of payment as the student reads it in the app: what was paid,
/// when and how, then the subscription, the student and the company, each a
/// group that opens in place.
///
/// Every value comes from the stored receipt ([SubscriptionReceipt]), which the
/// server writes once at approval and never changes, so it reads the same
/// whenever it is opened. The document to save or send is the PDF (see
/// ReceiptPdf), built from the same receipt.
class ReceiptCard extends StatelessWidget {
  final SubscriptionReceipt receipt;

  const ReceiptCard({super.key, required this.receipt});

  static String money(double value) => formatMoney(value);

  /// "8 أكتوبر 2026" from an ISO date or timestamp; [year] off: "8 أكتوبر".
  static String day(String? iso, {bool year = true}) {
    final date = iso == null ? null : DateTime.tryParse(iso);
    if (date == null) return iso ?? '—';
    final local = iso!.length > 10 ? date.toLocal() : date;
    final short = '${local.day} ${BasakUi.arabicMonths[local.month - 1]}';
    return year ? '$short ${local.year}' : short;
  }

  /// "20 سبتمبر – 14 يناير 2027": the first day without its year.
  static String span(String? from, String? to) => '${day(from, year: false)} – ${day(to)}';

  /// "الفصل الدراسي الأول 2026/2027" → "الفصل الأول 2026/2027".
  static String period(String label) => label.replaceFirst('الفصل الدراسي ', 'الفصل ');

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final colors = context.colors;
    final text = context.text;
    String? filled(String? value) => (value ?? '').trim().isEmpty ? null : value!.trim();
    final method = filled(r.paymentMethod);
    // A receipt keeps the logo it was issued under (a logo folder).
    final brand = CompanyBrand(logoPath: r.companyLogoPath);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BasakCard(
          radius: BasakRadius.sheet,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconPill(icon: LucideIcons.check, label: 'مدفوع ومعتمد', tone: BasakTone.success),
                  const SizedBox(width: BasakSpace.s12),
                  Expanded(
                    child: Text(
                      r.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.start : TextAlign.end,
                      style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BasakSpace.s10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MoneyText(money(r.amount), style: text.amount, unitSize: 16),
                        const SizedBox(height: BasakSpace.s10),
                        Text(
                          [day(r.approvedAt), if (method != null) method].join(' · '),
                          style: text.bodySmall.copyWith(color: colors.ink2),
                        ),
                      ],
                    ),
                  ),
                  // Whose receipt it is: the company's logo, when it has one.
                  if (brand.hasMark) ...[
                    const SizedBox(width: BasakSpace.s12),
                    CompanyLogo(
                      key: const Key('receipt-company-logo'),
                      name: r.companyName,
                      brand: brand,
                      size: 56,
                      radius: BasakRadius.small,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: BasakSpace.betweenCards),
        DisclosureGroup(
          sections: [
            DisclosureSection(title: 'الاشتراك', rows: [
              ('الفترة', period(r.periodLabel), false),
              if (r.startDate != null && r.endDate != null) ('الصلاحية', span(r.startDate, r.endDate), false),
              ('الخط', r.lineName, false),
              if (filled(r.stationName) != null) ('محطة الصعود', filled(r.stationName)!, false),
            ]),
            DisclosureSection(title: 'الطالب', rows: [
              ('الاسم', r.studentName, false),
              if (filled(r.studentPhone) != null) ('الهاتف', filled(r.studentPhone)!, true),
              if (filled(r.universityName) != null) ('الجامعة', filled(r.universityName)!, false),
            ]),
            DisclosureSection(title: 'الشركة', rows: [
              ('الاسم', r.companyName, false),
              if (filled(r.companyPhone) != null) ('الهاتف', filled(r.companyPhone)!, true),
              if (filled(r.companyAddress) != null) ('العنوان', filled(r.companyAddress)!, false),
            ]),
          ],
        ),
      ],
    );
  }
}

/// Handing the receipt's document to the phone: save to Files, print, or send.
class ReceiptExport {
  static String fileName(SubscriptionReceipt receipt, String extension) =>
      'basak-receipt-${receipt.code}.$extension';

  /// Opens the system sheet. [origin] anchors the sheet on tablets.
  static Future<void> share(Uint8List bytes, String name, String mimeType, {Rect? origin}) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: name)], sharePositionOrigin: origin));
  }
}
