import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/media/image_optimizer.dart';
import '../../../../core/media/picker_errors.dart';
import '../../../../core/sync/session.dart';
import 'package:image_picker/image_picker.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import 'package:flutter/services.dart';
import '../models/sale_catalog.dart';
import '../models/subscription_draft.dart';
import '../models/subscription_model.dart';
import '../models/payment_method_model.dart';
import '../../home/presentation/student_home_screen.dart';
import 'purchase_flow.dart';
import 'receipt_card.dart';
import 'receipt_pdf.dart';
import '../../../../core/network/supabase_service.dart';
import 'dart:typed_data';

// These stay loaded for the session, so opening the page again is instant. They
// are refreshed when the server announces a change (SyncHub) and on app resume,
// and belong to the signed-in account only.
final paymentMethodsProvider =
    FutureProvider.family<List<PaymentMethodModel>, String>((ref, companyId) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getPaymentMethods(companyId);
});

final subscriptionReceiptsProvider =
    FutureProvider.family<List<ReceiptModel>, String>((ref, id) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getReceiptsHistory(id);
});
final allSubscriptionsProvider =
    FutureProvider<List<SubscriptionModel>>((ref) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getSubscriptions();
});

/// The receipt issued when a subscription was approved (null: none yet).
final subscriptionReceiptDocProvider =
    FutureProvider.family<SubscriptionReceipt?, String>((ref, id) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getSubscriptionReceipt(id);
});

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isUploadingReceipt = false;
  bool _isExporting = false;
  XFile? _receiptPreview;
  String? _paymentMethodId;
  /// One key per subscription card, for sharing its receipt as an image.
  final Map<String, GlobalKey> _receiptKeys = {};

  /// Cards whose details are open. A card that needs the student to act
  /// (pay, re-upload) opens by itself; the rest stay compact.
  final Set<String> _expanded = {};
  final Set<String> _collapsedByUser = {};

  /// Showing the purchase flow while the student already has subscriptions
  /// (paying the next period in advance), starting from [_buyingFrom].
  bool _buying = false;
  SubscriptionDraft _buyingFrom = const SubscriptionDraft();

  void _refreshSubscriptions() {
    ref.invalidate(currentSubscriptionProvider);
    ref.invalidate(allSubscriptionsProvider);
    // What is on sale to this student depends on what they already hold.
    ref.invalidate(saleCatalogProvider);
  }

  Future<void> _handleRefresh() async {
    _refreshSubscriptions();
    ref.invalidate(subscriptionReceiptDocProvider);
    try {
      await ref.read(allSubscriptionsProvider.future);
    } catch (_) {}
  }

  void _onCreated(SubscriptionModel created) {
    _refreshSubscriptions();
    setState(() {
      _buying = false;
      _expanded.add(created.id);
      _receiptPreview = null;
      _paymentMethodId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(created.isDaily
          ? 'تم تفعيل اشتراك اليوم. ادفع نقداً للمشرف في الباص.'
          : 'تم إنشاء طلب الاشتراك. أكمل الدفع وارفع الإيصال.'),
      backgroundColor: AppColors.success,
    ));
  }

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final picked =
          await ImagePicker().pickImage(
              source: source, imageQuality: 92, maxWidth: 2600, maxHeight: 2600);
      if (picked != null && mounted) setState(() => _receiptPreview = picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(pickerErrorMessage(e)),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _submitReceipt(String subscriptionId, {bool needsMethod = false}) async {
    final picked = _receiptPreview;
    if (picked == null || _isUploadingReceipt) return;
    if (needsMethod && _paymentMethodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختر وسيلة الدفع التي حوّلت بها أولاً.')));
      return;
    }

    setState(() => _isUploadingReceipt = true);
    try {
      // Only the optimised image is uploaded; the original stays on the phone.
      final bytes = await ImageOptimizer.receipt(await picked.readAsBytes());
      const ext = 'jpg';

      await ref.read(subscriptionRepoProvider).uploadReceipt(
            subscriptionId: subscriptionId,
            fileBytes: bytes,
            fileExtension: ext,
            paymentMethodId: _paymentMethodId,
          );
      _refreshSubscriptions();
      ref.invalidate(subscriptionReceiptsProvider(subscriptionId));
      if (mounted) {
        setState(() {
          _receiptPreview = null;
          _isUploadingReceipt = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('تم رفع صورة الإيصال بنجاح وهو الآن قيد مراجعة إدارة الشركة.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingReceipt = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(errorMessage(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// The company's logo for the PDF, when it can be loaded quickly. The
  /// receipt is complete without it, so being offline never blocks the PDF.
  Future<Uint8List?> _companyLogo(String? folder) async {
    if (folder == null || folder.isEmpty) return null;
    try {
      final url = SupabaseService.client.storage.from('wallet-assets').getPublicUrl('$folder/master.png');
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

  /// Saves or shares a receipt: as a real PDF document built from the stored
  /// receipt, or as an image of its card.
  Future<void> _exportReceipt(SubscriptionReceipt receipt, {required bool asPdf}) async {
    if (_isExporting) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _isExporting = true);
    try {
      if (asPdf) {
        final pdf = await ReceiptPdf.build(receipt, logo: await _companyLogo(receipt.companyLogoPath));
        await ReceiptExport.share(pdf, ReceiptPdf.fileName(receipt), 'application/pdf', origin: origin);
      } else {
        final key = _receiptKeys[receipt.subscriptionId];
        if (key == null) return;
        final png = await ReceiptExport.png(key);
        await ReceiptExport.share(png, ReceiptExport.fileName(receipt, 'png'), 'image/png', origin: origin);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage(e)), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(allSubscriptionsProvider);

    return GlassScaffold(
      body: ColoredBox(
        color: const Color(0xFFF5F8FD),
        child: RefreshIndicator(
          color: AppColors.teal,
          onRefresh: _handleRefresh,
          child: subsAsync.when(
            data: (subs) {
              final open = subs.where((s) => !s.isExpired).toList()
                ..sort((a, b) => (a.startDate ?? '').compareTo(b.startDate ?? ''));
              // Newest first: every past subscription keeps its own card.
              final history = subs.where((s) => s.isExpired).toList()
                ..sort((a, b) => (b.startDate ?? b.createdAt).compareTo(a.startDate ?? a.createdAt));
              if (_buying || subs.isEmpty) {
                return _buildPurchaseView(open: open, hasHistory: history.isNotEmpty);
              }
              return _buildSubscriptionsView(open: open, history: history);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(child: Text('تعذر تحميل الاشتراك: ${errorMessage(err)}')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Choosing a subscription. Nothing is saved until the review is confirmed.
  Widget _buildPurchaseView({required List<SubscriptionModel> open, bool hasHistory = false}) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PurchaseFlow(
            // A new flow each time it is opened, starting from the offered choices.
            key: ValueKey(_buyingFrom),
            initial: _buyingFrom,
            // A cash day ride is for a student with no subscription at all.
            allowDaily: open.isEmpty,
            onCancel: open.isEmpty && !hasHistory ? null : () => setState(() => _buying = false),
            onCreated: _onCreated,
          ),
        ]),
      );

  /// The student's subscriptions over time: the current one(s) first, each
  /// older one below as its own card. Cards are compact; "عرض التفاصيل" opens
  /// the full details and the receipt in place.
  Widget _buildSubscriptionsView(
      {required List<SubscriptionModel> open, required List<SubscriptionModel> history}) {
    final active = open.where((s) => s.isActive).toList();
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('اشتراكاتي', style: AppTextStyles.displayMedium),
        const SizedBox(height: 16),
        if (open.isEmpty)
          _subscribeAgainCard()
        else ...[
          _sectionLabel(open.length == 1 ? 'الاشتراك الحالي' : 'الاشتراكات الحالية'),
          for (final sub in open) _subscriptionCard(sub),
        ],
        if (active.isNotEmpty) _payNextCard(active.first),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionLabel(history.length == 1 ? 'اشتراك سابق' : 'اشتراكات سابقة'),
          for (final old in history) _subscriptionCard(old),
        ],
      ]),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 2),
        child: Text(text,
            style: AppTextStyles.titleMedium.copyWith(color: AppColors.textSecondary)),
      );

  /// Nothing running: the past stays below, and a new subscription starts here.
  Widget _subscribeAgainCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('لا يوجد اشتراك حالي', style: AppTextStyles.titleMedium),
          const SizedBox(height: 4),
          Text('اشترك من جديد لتأكيد رحلاتك واستخدام بطاقتك.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('subscribe-again'),
              onPressed: () => setState(() {
                _buyingFrom = const SubscriptionDraft();
                _buying = true;
              }),
              child: const Text('اشتراك جديد'),
            ),
          ),
        ]),
      );

  /// The words and colours of a subscription's state.
  ({String label, Color color, Color background, IconData icon}) _status(SubscriptionModel sub) {
    if (sub.status == 'expired' || (sub.isExpired && sub.isActive)) {
      return (label: 'انتهى الاشتراك', color: const Color(0xFF64788A), background: const Color(0xFFEDF1F4), icon: LucideIcons.history);
    }
    if (sub.isActive) {
      return sub.isUpcoming
          ? (label: 'مفعّل · يبدأ قريباً', color: const Color(0xFF3F51B5), background: const Color(0xFFEEF0FF), icon: LucideIcons.calendarClock)
          : (label: 'الاشتراك مفعّل', color: const Color(0xFF07865A), background: const Color(0xFFE7F8F0), icon: LucideIcons.circleCheck);
    }
    if (sub.isPendingReview) {
      return (label: 'بانتظار المراجعة', color: const Color(0xFF00658D), background: const Color(0xFFE2F3FB), icon: LucideIcons.hourglass);
    }
    if (sub.isRejected) {
      return (label: 'تم الرفض', color: const Color(0xFFB42335), background: const Color(0xFFFFECEE), icon: LucideIcons.circleX);
    }
    if (sub.isExpired) {
      return (label: 'انتهى دون دفع', color: const Color(0xFF64788A), background: const Color(0xFFEDF1F4), icon: LucideIcons.history);
    }
    return (label: 'بانتظار الدفع', color: const Color(0xFFB97812), background: const Color(0xFFFFF4E5), icon: LucideIcons.wallet);
  }

  bool _needsAction(SubscriptionModel sub) =>
      !sub.isExpired && !sub.isActive && !sub.isPendingReview;

  /// One subscription: compact by default, with its state always in view.
  Widget _subscriptionCard(SubscriptionModel sub) {
    final status = _status(sub);
    final paid = sub.isActive || sub.status == 'expired';
    // A card waiting for the student opens by itself, unless they closed it.
    final open = _expanded.contains(sub.id) || (_needsAction(sub) && !_collapsedByUser.contains(sub.id));
    return Container(
      key: Key('sub-card-${sub.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x0B17384A), blurRadius: 15, offset: Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(sub.periodName, style: AppTextStyles.titleLarge)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: status.background, borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(status.icon, size: 14, color: status.color),
                  const SizedBox(width: 5),
                  Text(status.label,
                      style: AppTextStyles.labelSmall.copyWith(color: status.color, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if ((sub.companyName ?? '').isNotEmpty) ...[
              _summaryLine(LucideIcons.building2, 'شركة النقل', sub.companyName!),
              const SizedBox(height: 10),
            ],
            _summaryLine(LucideIcons.busFront, 'الخط', sub.lineName ?? '—'),
            const SizedBox(height: 10),
            _summaryLine(LucideIcons.mapPin, 'محطة الصعود', sub.stationName ?? '—'),
            if (sub.endDate != null && !sub.isDaily) ...[
              const SizedBox(height: 10),
              _summaryLine(LucideIcons.calendarCheck2, sub.isExpired ? 'انتهى في' : 'صالح حتى',
                  ReceiptCard.day(sub.endDate)),
            ],
            const SizedBox(height: 10),
            _summaryLine(
                LucideIcons.wallet,
                sub.isDaily
                    ? 'نقداً في الباص'
                    : paid
                        ? 'المبلغ المدفوع'
                        : sub.isPendingReview
                            ? 'المبلغ'
                            : 'المبلغ المطلوب',
                formatMoney(sub.price),
                labelKey: const Key('amount-label'),
                valueKey: const Key('amount-value')),
          ]),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: Key('sub-toggle-${sub.id}'),
            onPressed: () => setState(() {
              if (open) {
                _expanded.remove(sub.id);
                _collapsedByUser.add(sub.id);
              } else {
                _expanded.add(sub.id);
                _collapsedByUser.remove(sub.id);
              }
              _receiptPreview = null;
            }),
            icon: Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18),
            label: Text(open ? 'إخفاء التفاصيل' : 'عرض التفاصيل'),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: paid ? _approvedDetails(sub) : _paymentState(sub)),
                ),
        ),
      ]),
    );
  }

  /// Approved (running or ended): the full details and the receipt, with the
  /// PDF and share actions. No amount due, no payment methods, no upload.
  List<Widget> _approvedDetails(SubscriptionModel sub) {
    final receiptAsync = sub.isDaily ? null : ref.watch(subscriptionReceiptDocProvider(sub.id));
    final receipt = receiptAsync?.valueOrNull;
    if (receipt == null) {
      return [
        const Divider(height: 18),
        if (sub.destination != null) ...[
          _summaryLine(LucideIcons.graduationCap, 'الجامعة', sub.destination!),
          const SizedBox(height: 8),
        ],
        _summaryLine(LucideIcons.calendarDays, 'فترة الاشتراك', sub.periodLabel ?? sub.periodName),
        if (sub.startDate != null) ...[
          const SizedBox(height: 8),
          _summaryLine(LucideIcons.calendarClock, 'يبدأ في', ReceiptCard.day(sub.startDate)),
        ],
        if (!sub.isDaily && receiptAsync?.isLoading != true) ...[
          const SizedBox(height: 10),
          Text('لا يوجد إيصال لهذا الاشتراك.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
        ],
      ];
    }
    final key = _receiptKeys.putIfAbsent(sub.id, GlobalKey.new);
    return [
      RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: Colors.white,
          child: Padding(padding: const EdgeInsets.all(4), child: ReceiptCard(receipt: receipt)),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          key: Key('receipt-pdf-${sub.id}'),
          onPressed: _isExporting ? null : () => _exportReceipt(receipt, asPdf: true),
          icon: const Icon(LucideIcons.receiptText, size: 18),
          label: const Text('تحميل الإيصال PDF'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: Key('receipt-image-${sub.id}'),
          onPressed: _isExporting ? null : () => _exportReceipt(receipt, asPdf: false),
          icon: const Icon(LucideIcons.image, size: 18),
          label: const Text('مشاركة كصورة'),
        ),
      ),
    ];
  }

  /// Waiting for payment, rejected, or under review. The selection is fixed:
  /// the student pays for this subscription or re-uploads its receipt.
  List<Widget> _paymentState(SubscriptionModel sub) {
    final receiptsAsync = ref.watch(subscriptionReceiptsProvider(sub.id));
    final methods = sub.companyId == null
        ? const <PaymentMethodModel>[]
        : ref.watch(paymentMethodsProvider(sub.companyId!)).valueOrNull ?? const <PaymentMethodModel>[];
    final receipts = receiptsAsync.valueOrNull ?? const <ReceiptModel>[];
    final latest = receipts.isEmpty ? null : receipts.first;
    return [
      const Divider(height: 18),
      if (sub.isPendingReview) ...[
        _statusMessage(
          icon: LucideIcons.hourglass,
          title: 'استلمنا إيصالك',
          message: 'تراجعه إدارة الشركة يدوياً، وسيصلك إشعار عند اعتماد الاشتراك.',
          color: const Color(0xFF00658D),
          background: const Color(0xFFE2F3FB),
        ),
        const SizedBox(height: 14),
        _receiptUploadCard(sub, receipts.length, latest),
      ] else ...[
        if (sub.isRejected || latest?.isRejected == true) ...[
          _statusMessage(
            icon: LucideIcons.circleX,
            title: 'تم رفض الإيصال',
            message: latest?.rejectionReason ?? 'راجع سبب الرفض مع إدارة الشركة ثم ارفع إيصالاً جديداً.',
            color: const Color(0xFFB42335),
            background: const Color(0xFFFFECEE),
          ),
          const SizedBox(height: 14),
        ],
        _paymentMethodsCard(sub),
        const SizedBox(height: 14),
        if (receiptsAsync.isLoading && !receiptsAsync.hasValue)
          const LinearProgressIndicator()
        else
          _receiptUploadCard(sub, receipts.length, latest),
        const SizedBox(height: 14),
        _paymentNotes(methods, receipts.length),
      ],
    ];
  }

  /// The payment instructions, in one short numbered block.
  Widget _paymentNotes(List<PaymentMethodModel> methods, int attempts) {
    final notes = [
      if (methods.isEmpty)
        'تواصل مع إدارة الشركة للحصول على بيانات التحويل.'
      else
        'حوّل المبلغ كاملاً بالوسيلة التي اخترتها.',
      'ارفع صورة واضحة للإيصال فيها رقم العملية والتاريخ.',
      'تُراجع الإدارة الإيصال وسيصلك إشعار عند الاعتماد.',
      if (attempts > 0 && attempts < 5) 'المتبقي ${5 - attempts} من 5 محاولات لرفع الإيصال.',
    ];

    return Container(
      key: const Key('payment-notes'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFBF2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF3E3C2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.info, size: 15, color: Color(0xFFB97812)),
          const SizedBox(width: 6),
          Text('ملاحظات الدفع',
              style: AppTextStyles.labelSmall
                  .copyWith(color: const Color(0xFF8A5A0B), fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < notes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 18,
                child: Text('${i + 1}.',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: const Color(0xFFB97812), fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text(notes[i],
                    style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF5E4A1E), height: 1.45)),
              ),
            ]),
          ),
      ]),
    );
  }

  /// "Subscribe to the next period in advance": shown only when the company
  /// allows it (the catalog then lists it), with that period's own price. It
  /// opens the flow with the same company, line and station filled in.
  Widget _payNextCard(SubscriptionModel sub) {
    final line = ref.watch(saleCatalogProvider).valueOrNull?.line(sub.lineId);
    final next = (line?.options ?? const <SaleOption>[]).where((o) => o.isUpcoming).toList();
    if (line == null || next.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('next-period'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: const Color(0xFFEEF0FF),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.calendarPlus, color: Color(0xFF3F51B5)),
          const SizedBox(width: 9),
          Expanded(
              child: Text('اشترك في الفترة القادمة من الآن',
                  style: AppTextStyles.titleMedium
                      .copyWith(color: const Color(0xFF3F51B5)))),
        ]),
        const SizedBox(height: 8),
        for (final option in next)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _buyingFrom = SubscriptionDraft(
                      companyId: line.companyId,
                      lineId: line.id,
                      stationId: line.station(sub.stationId)?.id,
                      optionKey: option.key);
                  _buying = true;
                }),
                child: Text('${option.title} · ${formatMoney(option.price)}'),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _summaryLine(IconData icon, String label, String value, {Key? labelKey, Key? valueKey}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(icon, size: 16, color: const Color(0xFF00658D)),
        const SizedBox(width: 8),
        SizedBox(
            width: 104,
            child: Text(label,
                key: labelKey,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary))),
        Expanded(
            child: Text(value,
                key: valueKey,
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
      ]);

  Widget _statusMessage(
          {required IconData icon,
          required String title,
          required String message,
          required Color color,
          required Color background}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(17)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: AppTextStyles.titleMedium.copyWith(color: color)),
                const SizedBox(height: 4),
                Text(message,
                    style: AppTextStyles.bodyMedium.copyWith(color: color))
              ]))
        ]),
      );

  /// The company's payment methods: the student picks the one they used and
  /// its transfer details appear, ready to copy. (The amount is in the summary
  /// above and the instructions are in the notes below.)
  Widget _paymentMethodsCard(SubscriptionModel sub) {
    final companyId = sub.companyId;
    if (companyId == null) return const SizedBox.shrink();
    return ref.watch(paymentMethodsProvider(companyId)).when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (methods) {
            if (methods.isEmpty) return const SizedBox.shrink();
            return Container(
              key: const Key('payment-methods'),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE4EDF3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(LucideIcons.wallet, color: Color(0xFF00658D)),
                  const SizedBox(width: 9),
                  Expanded(child: Text('اختر وسيلة الدفع', style: AppTextStyles.titleMedium)),
                ]),
                const SizedBox(height: 10),
                for (final m in methods) _paymentMethodTile(m),
              ]),
            );
          },
        );
  }

  Widget _paymentMethodTile(PaymentMethodModel m) {
    final selected = _paymentMethodId == m.id;
    final icon = switch (m.type) {
      'instapay' => LucideIcons.wallet,
      'vodafone_cash' => LucideIcons.smartphone,
      _ => LucideIcons.landmark,
    };
    return GestureDetector(
      onTap: () => setState(() => _paymentMethodId = m.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF4FB) : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xFF00658D) : const Color(0xFFE6EEF3), width: selected ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 18, color: selected ? const Color(0xFF00658D) : AppColors.textSecondary),
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: const Color(0xFF00658D)),
            const SizedBox(width: 6),
            Expanded(child: Text(m.displayName, style: AppTextStyles.titleMedium)),
            Text(m.typeLabel, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          ]),
          if (selected) ...[
            const SizedBox(height: 8),
            if (m.type == 'bank' && m.bankName != null) _payLine('البنك', m.bankName!, copy: false),
            _payLine(
                switch (m.type) { 'instapay' => 'عنوان إنستاباي', 'vodafone_cash' => 'رقم المحفظة', _ => 'رقم الحساب' },
                m.payTo),
            if (m.type == 'bank' && m.iban != null) _payLine('IBAN', m.iban!),
            if (m.accountHolder != null) _payLine('بإسم', m.accountHolder!, copy: false),
          ],
        ]),
      ),
    );
  }

  /// "label: value" with the value right beside its label (a number or an
  /// address reads left to right but still sits next to the label).
  Widget _payLine(String label, String value, {bool copy = true}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Text('$label: ', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          Flexible(
            child: Text(value,
                textDirection: copy ? TextDirection.ltr : null,
                textAlign: TextAlign.right,
                style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (copy)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'نسخ',
              icon: const Icon(LucideIcons.copy, size: 16, color: Color(0xFF00658D)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')));
              },
            ),
        ]),
      );

  Widget _receiptUploadCard(
      SubscriptionModel sub, int attempts, ReceiptModel? latest) {
    final canUpload = attempts < 5 && !sub.isPendingReview;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A17384A), blurRadius: 14, offset: Offset(0, 4))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.receiptText, color: Color(0xFF00658D)),
          const SizedBox(width: 9),
          Expanded(
              child: Text('إيصال التحويل', style: AppTextStyles.titleMedium)),
          Text(
              attempts >= 5
                  ? 'اكتملت 5 محاولات'
                  : 'محاولة ${attempts + 1} من 5',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary))
        ]),
        if (latest != null && sub.isPendingReview) ...[
          const SizedBox(height: 12),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F6FA),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(LucideIcons.fileCheck2, color: Color(0xFF07865A)),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(
                        'تم استلام الإيصال — المحاولة ${latest.attemptNumber}',
                        style: AppTextStyles.bodyMedium))
              ])),
        ] else if (_receiptPreview != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.file(File(_receiptPreview!.path),
                  height: 190, width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 8),
          Text(_receiptPreview!.name,
              style: AppTextStyles.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          TextButton.icon(
              onPressed: _isUploadingReceipt
                  ? null
                  : () => setState(() => _receiptPreview = null),
              icon: const Icon(LucideIcons.trash2, size: 17),
              label: const Text('إزالة الصورة')),
        ] else ...[
          if (attempts >= 5) ...[
            const SizedBox(height: 12),
            Text('اكتملت المحاولات الخمس. تواصل مع الإدارة لمساعدتك.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ],
          if (canUpload) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pickReceipt(ImageSource.gallery),
                      icon: const Icon(LucideIcons.image),
                      label: const Text('اختيار صورة'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pickReceipt(ImageSource.camera),
                      icon: const Icon(LucideIcons.camera),
                      label: const Text('التقاط صورة')))
            ]),
          ],
        ],
        if (_receiptPreview != null) ...[
          const SizedBox(height: 7),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                  onPressed:
                      _isUploadingReceipt
                          ? null
                          : () => _submitReceipt(sub.id,
                              needsMethod: sub.companyId != null &&
                                  (ref.read(paymentMethodsProvider(sub.companyId!)).valueOrNull?.isNotEmpty ?? false)),
                  icon: _isUploadingReceipt
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.upload),
                  label: Text(_isUploadingReceipt
                      ? 'جارٍ الإرسال...'
                      : 'إرسال الإيصال للمراجعة'))),
        ],
      ]),
    );
  }

}
