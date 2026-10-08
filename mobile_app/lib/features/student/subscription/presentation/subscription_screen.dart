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

String _phaseLabel(SubscriptionModel sub) => sub.isExpired
    ? 'منتهي'
    : sub.isUpcoming
        ? 'الفترة القادمة'
        : 'الفترة الحالية';

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
  final _receiptKey = GlobalKey();

  /// Showing the purchase flow while the student already has subscriptions
  /// (paying the next period in advance), starting from [_buyingFrom].
  bool _buying = false;
  SubscriptionDraft _buyingFrom = const SubscriptionDraft();
  String? _focusedSubId;

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
      _focusedSubId = created.id;
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

  /// Saves or shares the receipt drawn on screen, as a PDF or as an image.
  Future<void> _exportReceipt(SubscriptionReceipt receipt, {required bool asPdf}) async {
    if (_isExporting) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _isExporting = true);
    try {
      final png = await ReceiptExport.png(_receiptKey);
      if (asPdf) {
        final pdf = await ReceiptExport.pdf(png, title: 'إيصال اشتراك ${ReceiptCard.number(receipt.number)}');
        await ReceiptExport.share(pdf, ReceiptExport.fileName(receipt, 'pdf'), 'application/pdf', origin: origin);
      } else {
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
              final history = subs.where((s) => s.isExpired).toList();
              if (_buying || open.isEmpty) {
                return _buildPurchaseView(open: open);
              }
              final focused = open.firstWhere((s) => s.id == _focusedSubId,
                  orElse: () => open.first);
              return _buildActiveSubDetailView(focused,
                  open: open, history: history);
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
  Widget _buildPurchaseView({required List<SubscriptionModel> open}) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PurchaseFlow(
            // A new flow each time it is opened, starting from the offered choices.
            key: ValueKey(_buyingFrom),
            initial: _buyingFrom,
            // A cash day ride is for a student with no subscription at all.
            allowDaily: open.isEmpty,
            onCancel: open.isEmpty ? null : () => setState(() => _buying = false),
            onCreated: _onCreated,
          ),
        ]),
      );

  Widget _buildActiveSubDetailView(SubscriptionModel sub,
      {required List<SubscriptionModel> open,
      required List<SubscriptionModel> history}) {
    final active = sub.isActive;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              active
                  ? 'اشتراكك مفعّل'
                  : sub.isPendingReview
                      ? 'إيصالك قيد المراجعة'
                      : 'إتمام الدفع',
              style: AppTextStyles.displayMedium),
          if (open.length > 1) ...[
            const SizedBox(height: 10),
            _periodTabs(open, sub),
          ],
          const SizedBox(height: 12),
          if (active) ..._approvedState(sub) else ..._paymentState(sub),
          // Offered once this subscription is paid, not while a payment is open.
          if (active) _payNextCard(sub),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('اشتراكات منتهية', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            for (final old in history) _historyTile(old),
          ],
        ],
      ),
    );
  }

  /// Approved: what the student holds and the proof of payment. No amount
  /// due, no payment methods, no upload.
  List<Widget> _approvedState(SubscriptionModel sub) {
    final receipt = sub.isDaily ? null : ref.watch(subscriptionReceiptDocProvider(sub.id)).valueOrNull;
    return [
      if (sub.isUpcoming)
        _statusMessage(
          icon: LucideIcons.calendarClock,
          title: 'تم دفع الفترة القادمة مقدماً',
          message: 'يبدأ اشتراكك في ${ReceiptCard.day(sub.startDate)}.',
          color: const Color(0xFF3F51B5),
          background: const Color(0xFFEEF0FF),
        ),
      if (sub.isUpcoming) const SizedBox(height: 12),
      if (receipt == null)
        _subscriptionSummary(sub)
      else ...[
        RepaintBoundary(
          key: _receiptKey,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(padding: const EdgeInsets.all(10), child: ReceiptCard(receipt: receipt)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('receipt-pdf'),
            onPressed: _isExporting ? null : () => _exportReceipt(receipt, asPdf: true),
            icon: const Icon(LucideIcons.receiptText, size: 18),
            label: const Text('تحميل الإيصال PDF'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('receipt-image'),
            onPressed: _isExporting ? null : () => _exportReceipt(receipt, asPdf: false),
            icon: const Icon(LucideIcons.image, size: 18),
            label: const Text('مشاركة كصورة'),
          ),
        ),
      ],
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
      _subscriptionSummary(sub),
      const SizedBox(height: 14),
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

  /// Every payment instruction in one place, including the company's own note
  /// for the chosen method.
  Widget _paymentNotes(List<PaymentMethodModel> methods, int attempts) {
    final chosen = methods.where((m) => m.id == _paymentMethodId).firstOrNull;
    final notes = [
      if (methods.isEmpty)
        'لم تضف شركة النقل وسائل دفع بعد. تواصل مع إدارة الشركة للحصول على بيانات التحويل.'
      else
        'اختر وسيلة الدفع وحوّل المبلغ كاملاً إلى البيانات الظاهرة تحتها.',
      'ارفع صورة واضحة للإيصال يظهر فيها رقم العملية وتاريخ التحويل.',
      'تراجع إدارة الشركة الإيصال يدوياً، وسيصلك إشعار عند اعتماد الاشتراك.',
      if ((chosen?.instructions ?? '').trim().isNotEmpty) chosen!.instructions!.trim(),
      if (attempts > 0 && attempts < 5) 'المتبقي لك ${5 - attempts} من 5 محاولات لرفع الإيصال.',
    ];
    return Container(
      key: const Key('payment-notes'),
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF9EC), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.info, size: 19, color: Color(0xFFB97812)),
          const SizedBox(width: 8),
          Text('ملاحظات الدفع',
              style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF8A5A0B))),
        ]),
        const SizedBox(height: 8),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: CircleAvatar(radius: 2.5, backgroundColor: Color(0xFFB97812))),
              const SizedBox(width: 8),
              Expanded(child: Text(note, style: AppTextStyles.bodyMedium)),
            ]),
          ),
      ]),
    );
  }

  /// Switch between the current and upcoming subscriptions.
  Widget _periodTabs(List<SubscriptionModel> open, SubscriptionModel focused) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in open)
          ChoiceChip(
            label: Text('${_phaseLabel(s)} · ${s.periodName}'),
            selected: s.id == focused.id,
            onSelected: (_) => setState(() {
              _focusedSubId = s.id;
              _receiptPreview = null;
              _paymentMethodId = null;
            }),
          ),
      ]);

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

  Widget _historyTile(SubscriptionModel s) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(LucideIcons.history, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
                '${s.periodLabel ?? s.periodName} · ${s.lineName ?? ''}',
                style: AppTextStyles.bodyMedium),
          ),
          Text('حتى ${ReceiptCard.day(s.endDate)}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      );

  /// What this subscription is: the line and the student's university, the
  /// boarding station, the period and the amount. The amount appears here only.
  Widget _subscriptionSummary(SubscriptionModel sub) {
    final active = sub.isActive;
    return Container(
        key: const Key('subscription-summary'),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0B17384A),
                  blurRadius: 15,
                  offset: Offset(0, 5))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Text(sub.boardingTitle, style: AppTextStyles.titleLarge)),
            const SizedBox(width: 8),
            _statusPill(
                active
                    ? 'نشط'
                    : sub.isPendingReview
                        ? 'قيد المراجعة'
                        : sub.isRejected
                            ? 'مرفوض'
                            : 'بانتظار الدفع',
                active)
          ]),
          const SizedBox(height: 4),
          Text('محطة الصعود',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          const Divider(height: 22),
          if (sub.destination != null) ...[
            _summaryLine(LucideIcons.graduationCap, 'الجامعة', sub.destination!),
            const SizedBox(height: 10),
          ],
          _summaryLine(LucideIcons.busFront, 'الخط', sub.lineName ?? '—'),
          if ((sub.companyName ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _summaryLine(LucideIcons.building2, 'شركة النقل', sub.companyName!),
          ],
          const SizedBox(height: 10),
          _summaryLine(LucideIcons.calendarDays, 'فترة الاشتراك', sub.periodName),
          if (active && sub.endDate != null) ...[
            const SizedBox(height: 10),
            _summaryLine(LucideIcons.calendarCheck2, 'صالح حتى', ReceiptCard.day(sub.endDate)),
          ],
          const SizedBox(height: 12),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1F6FB),
                  borderRadius: BorderRadius.circular(13)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                          active
                              ? (sub.isDaily ? 'يُدفع نقداً في الباص' : 'المبلغ المدفوع')
                              : sub.isPendingReview
                                  ? 'المبلغ'
                                  : 'المبلغ المطلوب',
                          key: const Key('amount-label'),
                          style: AppTextStyles.bodyMedium),
                    ),
                    Text(formatMoney(sub.price),
                        key: const Key('amount-value'),
                        style: AppTextStyles.titleLarge
                            .copyWith(color: const Color(0xFF00658D)))
                  ])),
        ]),
      );
  }

  Widget _summaryLine(IconData icon, String label, String value) =>
      Row(children: [
        Icon(icon, size: 17, color: const Color(0xFF00658D)),
        const SizedBox(width: 8),
        SizedBox(
            width: 96,
            child: Text(label,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style:
                    AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)))
      ]);

  Widget _statusPill(String label, bool active) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: active ? const Color(0xFFE7F8F0) : const Color(0xFFEAF4FB),
          borderRadius: BorderRadius.circular(16)),
      child: Text(label,
          style: AppTextStyles.labelSmall.copyWith(
              color: active ? const Color(0xFF07865A) : const Color(0xFF00658D),
              fontWeight: FontWeight.bold)));

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
                switch (m.type) { 'instapay' => 'عنوان InstaPay', 'vodafone_cash' => 'رقم المحفظة', _ => 'رقم الحساب' },
                m.payTo),
            if (m.type == 'bank' && m.iban != null) _payLine('IBAN', m.iban!),
            if (m.accountHolder != null) _payLine('باسم', m.accountHolder!, copy: false),
          ],
        ]),
      ),
    );
  }

  Widget _payLine(String label, String value, {bool copy = true}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Text('$label: ', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
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
