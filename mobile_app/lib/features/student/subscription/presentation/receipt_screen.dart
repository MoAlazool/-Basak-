import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/skeleton.dart';
import '../models/sale_catalog.dart';
import 'receipt_card.dart';
import 'receipt_pdf.dart';
import 'subscription_screen.dart';

/// The receipt of one subscription, on its own page: the receipt as issued,
/// and under it the three ways to take it out of the app — the PDF, a picture
/// in the phone's photos, or the share sheet.
class ReceiptScreen extends ConsumerStatefulWidget {
  final String subscriptionId;

  const ReceiptScreen({super.key, required this.subscriptionId});

  static Future<void> open(BuildContext context, String subscriptionId) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(subscriptionId: subscriptionId)));

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

enum _Export { pdf, image, share }

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  _Export? _exporting;

  /// The company's logo for the PDF, when it can be loaded quickly. The
  /// receipt is complete without it, so being offline never blocks the PDF.
  Future<Uint8List?> _companyLogo(String? folder) async {
    // The one rule for a company picture's address (and its guard).
    final url = CompanyBrand.logoFileUrl(folder);
    if (url == null) return null;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 6))) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  /// The receipt as a real PDF document built from the stored receipt: opened
  /// in the share sheet as a PDF or as a picture of it, or saved straight to
  /// the phone's photos as that picture.
  Future<void> _export(SubscriptionReceipt receipt, _Export how) async {
    if (_exporting != null) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = how);
    try {
      final pdf = await ReceiptPdf.build(receipt, logo: await _companyLogo(receipt.companyLogoPath));
      switch (how) {
        case _Export.pdf:
          await ReceiptExport.share(pdf, ReceiptPdf.fileName(receipt), 'application/pdf', origin: origin);
        case _Export.share:
          await ReceiptExport.share(
              await ReceiptPdf.image(pdf), ReceiptExport.fileName(receipt, 'jpg'), 'image/jpeg',
              origin: origin);
        case _Export.image:
          // No sheet and no file to deal with: it goes to the photo library.
          if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
            throw Exception('اسمح للتطبيق بحفظ الصور من إعدادات الهاتف ثم أعد المحاولة.');
          }
          await Gal.putImageBytes(await ReceiptPdf.image(pdf), name: 'basak-receipt-${receipt.code}');
          if (mounted) BasakToast.show(context, 'تم حفظ الإيصال في الاستوديو.');
      }
    } on GalException catch (e) {
      if (mounted) {
        BasakToast.show(
            context,
            e.type == GalExceptionType.accessDenied
                ? 'اسمح للتطبيق بحفظ الصور من إعدادات الهاتف ثم أعد المحاولة.'
                : 'تعذر حفظ الصورة في الاستوديو. حاول مرة أخرى.',
            kind: BasakToastKind.failure);
      }
    } catch (e) {
      if (mounted) BasakToast.show(context, errorMessage(e), kind: BasakToastKind.failure);
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.subscriptionId;
    final async = ref.watch(subscriptionReceiptDocProvider(id));
    final receipt = async.valueOrNull;
    final busy = _exporting != null;

    final List<Widget> children;
    if (receipt != null) {
      children = [ReceiptCard(receipt: receipt)];
    } else if (async.isLoading) {
      children = const [_ReceiptSkeleton()];
    } else if (async.hasError) {
      children = [
        InlineError(
          message: 'تعذّر تحميل الإيصال',
          onRetry: () => ref.invalidate(subscriptionReceiptDocProvider(id)),
        ),
      ];
    } else {
      children = const [
        BasakCard(
          child: EmptyState(icon: LucideIcons.receiptText, title: 'لا يوجد إيصال لهذا الاشتراك.'),
        ),
      ];
    }

    return Scaffold(
      backgroundColor: context.colors.ground,
      body: BasakPage(
        header: const BasakBackHeader(title: 'الإيصال', inlineTitle: true),
        dock: receipt == null
            ? null
            : BasakDock(
                child: Row(
                  children: [
                    Expanded(
                      child: BasakButton(
                        key: Key('receipt-pdf-$id'),
                        label: 'تنزيل PDF',
                        icon: LucideIcons.download,
                        loading: _exporting == _Export.pdf,
                        onPressed: busy ? null : () => _export(receipt, _Export.pdf),
                      ),
                    ),
                    const SizedBox(width: BasakSpace.s10),
                    SquareIconButton(
                      key: Key('receipt-image-$id'),
                      icon: LucideIcons.image,
                      label: 'حفظ كصورة',
                      onPressed: busy ? null : () => _export(receipt, _Export.image),
                    ),
                    const SizedBox(width: BasakSpace.s10),
                    SquareIconButton(
                      key: Key('receipt-share-$id'),
                      icon: LucideIcons.share2,
                      label: 'مشاركة',
                      onPressed: busy ? null : () => _export(receipt, _Export.share),
                    ),
                  ],
                ),
              ),
        children: children,
      ),
    );
  }
}

/// The receipt's shape while it is read for the first time.
class _ReceiptSkeleton extends StatelessWidget {
  const _ReceiptSkeleton();

  @override
  Widget build(BuildContext context) => const Skeleton(
        child: Column(
          children: [
            SkeletonCard(
              radius: BasakRadius.sheet,
              padding: EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s20, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Bone(width: 110, height: 26, radius: BasakRadius.full), Spacer(), Bone(width: 90)]),
                  SizedBox(height: BasakSpace.s16),
                  Bone(width: 150, height: 32),
                  SizedBox(height: BasakSpace.s16),
                  Bone(width: 170),
                ],
              ),
            ),
            SizedBox(height: BasakSpace.betweenCards),
            SkeletonCard(
              padding: EdgeInsetsDirectional.all(BasakSpace.s18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone(width: 90, height: 16),
                  SizedBox(height: BasakSpace.s18),
                  Bone(height: 12),
                  SizedBox(height: BasakSpace.s14),
                  Bone(height: 12),
                  SizedBox(height: BasakSpace.s14),
                  Bone(width: 200, height: 12),
                ],
              ),
            ),
          ],
        ),
      );
}
