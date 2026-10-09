import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/storage/offline_cache.dart';
import '../../../../core/sync/own_changes.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/connection_strip_host.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../home/presentation/student_home_screen.dart';
import '../../qr/presentation/student_qr_screen.dart';
import '../data/subscription_repository.dart';
import '../models/payment_method_model.dart';
import '../models/sale_catalog.dart';
import '../models/subscription_draft.dart';
import '../models/subscription_model.dart';
import 'pay_screen.dart';
import 'purchase_flow.dart';
import 'receipt_card.dart';
import 'receipt_screen.dart';

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

/// Sends receipts and shows the result on this phone from the server's own
/// answer: the uploading phone never waits for the live announcement and
/// reads nothing again.
final receiptSubmitterProvider = Provider((ref) => ReceiptSubmitter(ref));

class ReceiptSubmitter {
  final Ref _ref;
  ReceiptSubmitter(this._ref);

  Future<ReceiptModel> submit({
    required ReceiptAttempt attempt,
    required Uint8List bytes,
    String? paymentMethodId,
    void Function(ReceiptPhase phase)? onPhase,
    void Function(int sent, int total)? onProgress,
  }) async {
    // The server announces the new receipt and the subscription's new status
    // to this phone too; both are already shown, so they are not read again.
    final receiptEcho = OwnChanges.begin('receipts', op: 'INSERT');
    final statusEcho = OwnChanges.begin('subscriptions', id: attempt.subscriptionId, op: 'UPDATE');
    try {
      final receipt = await _ref.read(subscriptionRepoProvider).uploadReceipt(
          attempt: attempt, fileBytes: bytes, paymentMethodId: paymentMethodId, onPhase: onPhase, onProgress: onProgress);
      receiptEcho.done(id: receipt.id, keep: const Duration(minutes: 1));
      statusEcho.done();
      _show(attempt.subscriptionId);
      return receipt;
    } catch (_) {
      receiptEcho.failed();
      statusEcho.failed();
      rethrow;
    }
  }

  /// The saved copies already hold the receipt and the new status (see
  /// SubscriptionRepository.applyReceiptSubmitted): these re-reads are
  /// answered from memory.
  void _show(String subscriptionId) {
    _ref.invalidate(currentSubscriptionProvider);
    _ref.invalidate(allSubscriptionsProvider);
    _ref.invalidate(subscriptionReceiptsProvider(subscriptionId));
    _ref.invalidate(studentQrProvider);
  }

  /// Receipt images from earlier whose outcome was never learned: adopted when
  /// the receipt turned out saved, removed otherwise.
  Future<void> settlePending() async {
    try {
      for (final subscriptionId in await _ref.read(subscriptionRepoProvider).reconcilePendingReceipts()) {
        _show(subscriptionId);
      }
    } catch (_) {
      // Nothing saved for this phone, or storage unavailable: next time.
    }
  }
}

/// The subscription a notification was about: its card opens when the
/// subscriptions tab is shown, then this is cleared.
final focusedSubscriptionProvider = StateProvider<String?>((ref) => null);

/// What the tab says about time, apart from how it is drawn.
abstract final class SubscriptionScreenWords {
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "باقي 95 يوماً", with the number's own plural.
  static String daysLeft(String? endDate, [DateTime? now]) {
    final end = DateTime.tryParse(endDate ?? '');
    if (end == null) return '';
    final days = _dateOnly(end).difference(_dateOnly(now ?? DateTime.now())).inDays;
    if (days <= 0) return 'ينتهي اليوم';
    if (days == 1) return 'باقي يوم واحد';
    if (days == 2) return 'باقي يومان';
    if (days <= 10) return 'باقي $days أيام';
    return 'باقي $days يوماً';
  }

  /// The share of the period that has passed, from 0 to 1.
  static double elapsed(String? startDate, String? endDate, [DateTime? now]) {
    final start = DateTime.tryParse(startDate ?? '');
    final end = DateTime.tryParse(endDate ?? '');
    if (start == null || end == null) return 0;
    final whole = _dateOnly(end).difference(_dateOnly(start)).inDays;
    if (whole <= 0) return 1;
    return (_dateOnly(now ?? DateTime.now()).difference(_dateOnly(start)).inDays / whole).clamp(0.0, 1.0);
  }

  /// "أُرسل اليوم 3:40 م", "أُرسل أمس 9:05 م", "أُرسل 3 أكتوبر".
  static String sentAt(String createdAt, [DateTime? now]) {
    final at = DateTime.tryParse(createdAt)?.toLocal();
    if (at == null) return '';
    final today = _dateOnly(now ?? DateTime.now());
    final days = today.difference(_dateOnly(at)).inDays;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = BasakUi.time12('${two(at.hour)}:${two(at.minute)}');
    if (days == 0) return 'أُرسل اليوم $time';
    if (days == 1) return 'أُرسل أمس $time';
    return 'أُرسل ${ReceiptCard.day(createdAt, year: false)}';
  }
}

/// The "اشتراكي" tab: where the student's subscription stands, and what there
/// is to do about it. Paying is a page of its own ([PayScreen]), and so is the
/// receipt ([ReceiptScreen]); the builder opens above the tabs.
class SubscriptionScreen extends ConsumerStatefulWidget {
  /// Whether this tab is the one in front. Behind another tab (and while it
  /// is built in the background at start) it shows nothing of the catalog, so
  /// it does not read it.
  final bool visible;

  /// "العودة للرئيسية" once a receipt is sent.
  final VoidCallback? onNavigateHome;

  /// The card shortcut on a pass that has nothing to ask.
  final VoidCallback? onNavigateToCard;

  const SubscriptionScreen({super.key, this.visible = true, this.onNavigateHome, this.onNavigateToCard});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  /// Past subscriptions: the latest two, or all of them.
  bool _allHistory = false;

  /// What the tab last showed of what it reads only while it is in front:
  /// the catalog (the next period, a renewal), a paid subscription's receipt,
  /// the receipts of one that is under review or was refused, and the
  /// company's payment methods (to name the one a receipt was paid with).
  SaleCatalog? _catalogShown;
  bool _catalogLoading = false;
  final Map<String, AsyncValue<SubscriptionReceipt?>> _docs = {};
  final Map<String, List<ReceiptModel>> _receipts = {};
  final Map<String, List<PaymentMethodModel>> _methods = {};

  static const _historyShown = 2;

  @override
  void initState() {
    super.initState();
    // Opened by a notification before this tab was ever built.
    _focus(ref.read(focusedSubscriptionProvider));
  }

  /// A notification was about a subscription: the tab shows it at its top, so
  /// there is nothing to open — the request is only taken off.
  void _focus(String? subscriptionId) {
    if (subscriptionId == null) return;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(focusedSubscriptionProvider.notifier).state = null;
    });
  }

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
    // What is on sale changed with the new subscription. Marked stale once
    // the purchase flow is off screen, so it is read again only by whatever
    // shows it next (the "next period" card, or the flow when it is reopened).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(saleCatalogProvider);
    });
    // Already on screen: subscriptionCreatorProvider applied the server's answer.
    BasakToast.show(
        context,
        created.isDaily
            ? 'تم تفعيل اشتراك اليوم. ادفع نقداً للمشرف في الباص.'
            : 'تم إنشاء طلب الاشتراك. أكمل الدفع وارفع الإيصال.');
    // "تأكيد والانتقال للدفع": the next thing to do is on the pay page.
    if (!created.isDaily) _pay(created);
  }

  void _pay(SubscriptionModel sub) => PayScreen.open(context, sub, onGoHome: widget.onNavigateHome);

  /// The builder, above the tabs, starting from [initial].
  Future<void> _subscribe({SubscriptionDraft initial = const SubscriptionDraft(), required bool allowDaily}) async {
    final created = await PurchaseFlowPage.open(context, initial: initial, allowDaily: allowDaily);
    if (created != null && mounted) _onCreated(created);
  }

  static BasakStatus _statusOf(SubscriptionModel sub) {
    if (sub.isExpired) return BasakStatus.expired;
    if (sub.isActive) return sub.isUpcoming ? BasakStatus.upcoming : BasakStatus.active;
    if (sub.isPendingReview) return BasakStatus.pendingReview;
    if (sub.isRejected) return BasakStatus.rejected;
    return BasakStatus.pendingPayment;
  }

  /// "2026 / 2027".
  static String? _year(SubscriptionModel sub) =>
      sub.academicYear == null ? null : '${sub.academicYear} / ${sub.academicYear! + 1}';

  /// "الزرقا · كوبري السرو".
  static String _lineAndStation(SubscriptionModel sub) =>
      [(sub.lineName ?? '').trim(), (sub.stationName ?? '').trim()].where((s) => s.isNotEmpty).join(' · ');

  static String? _withoutTitle(String? university) {
    final name = (university ?? '').trim().replaceFirst(RegExp(r'^(جامعة|جامعه)\s+'), '');
    return name.isEmpty ? null : name;
  }

  static String _lineTitle(SubscriptionModel sub) {
    final line = (sub.lineName ?? '').trim();
    if (line.isEmpty) return 'الخط';
    return line.startsWith('خط ') ? line : 'خط $line';
  }

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(allSubscriptionsProvider);
    ref.listen(focusedSubscriptionProvider, (_, id) => _focus(id));
    final subs = subsAsync.valueOrNull;

    if (subs == null) {
      if (subsAsync.hasError) {
        final offline = isNetworkFailure(subsAsync.error!);
        return BasakPage(
          onRefresh: _handleRefresh,
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * .14),
            PageError(
              icon: offline ? LucideIcons.wifiOff : LucideIcons.triangleAlert,
              title: offline ? 'لا يوجد اتصال' : 'تعذر تحميل الاشتراك',
              message: offline
                  ? 'نحتاج الإنترنت مرة واحدة لتحميل بياناتك. بعدها تعمل بطاقتك واشتراكك بدون اتصال.'
                  : errorMessage(subsAsync.error!),
              onAction: () => ref.invalidate(allSubscriptionsProvider),
            ),
          ],
        );
      }
      // A true first load, with nothing saved: the page's own shape.
      return ColoredBox(
        color: context.colors.ground,
        child: const SafeArea(
          bottom: false,
          child: SingleChildScrollView(physics: NeverScrollableScrollPhysics(), child: SubscriptionsSkeleton()),
        ),
      );
    }

    // No subscription, ever: the tab is the builder.
    if (subs.isEmpty) {
      return PurchaseFlow(
        visible: widget.visible,
        onCreated: _onCreated,
      );
    }

    final open = subs.where((s) => !s.isExpired).toList()
      ..sort((a, b) => (a.startDate ?? '').compareTo(b.startDate ?? ''));
    // Newest first.
    final history = subs.where((s) => s.isExpired).toList()
      ..sort((a, b) => (b.startDate ?? b.createdAt).compareTo(a.startDate ?? a.createdAt));
    final running = open.where((s) => s.isActive && !s.isDaily).toList();

    // The catalog is the largest read of the app: only while the tab is in
    // front, and only when something here shows it.
    final needsCatalog = running.isNotEmpty || open.isEmpty;
    if (widget.visible && needsCatalog) {
      final catalog = ref.watch(saleCatalogProvider);
      _catalogShown = catalog.valueOrNull ?? _catalogShown;
      _catalogLoading = catalog.isLoading && !catalog.hasValue;
    }

    return BasakPage(
      onRefresh: _handleRefresh,
      // Clear of the floating tab bar, whose height the shell reports here.
      bottomInset: MediaQuery.paddingOf(context).bottom + BasakSpace.s24,
      children: [
        Semantics(header: true, child: Text('اشتراكي', style: context.text.display)),
        for (final sub in open) ..._current(sub),
        if (open.isEmpty) _ended(history.first),
        if (running.isNotEmpty) ..._nextPeriod(running.first),
        if (history.isNotEmpty) _history(history),
      ],
    );
  }

  // ── The subscription that counts now ───────────────────────────────

  List<Widget> _current(SubscriptionModel sub) {
    final status = _statusOf(sub);
    final money = formatMoney(sub.price);
    final company = (sub.companyName ?? '').trim();
    final key = Key('sub-card-${sub.id}');
    final route = [
      if (_lineAndStation(sub).isNotEmpty) InfoRow(label: 'الخط والمحطة', value: _lineAndStation(sub)),
      if (company.isNotEmpty) InfoRow(label: 'الشركة', value: company),
    ];
    const amountLabel = Key('amount-label');
    const amountValue = Key('amount-value');

    switch (status) {
      case BasakStatus.pendingPayment:
        return [
          PeriodCard(
            key: key,
            status: status,
            meta: _year(sub),
            metaLtr: true,
            title: sub.periodName,
            footer: AmountAction(
              caption: 'المبلغ المطلوب',
              money: money,
              actionLabel: 'ادفع الآن',
              onAction: () => _pay(sub),
              captionKey: amountLabel,
              moneyKey: amountValue,
              actionKey: Key('pay-now-${sub.id}'),
            ),
          ),
          if (route.isNotEmpty) InfoRows(rows: route),
        ];

      case BasakStatus.rejected:
        final receipts = _receiptsOf(sub);
        final latest = receipts == null || receipts.isEmpty ? null : receipts.first;
        final reason = (latest?.rejectionReason ?? '').trim();
        final attempts = receipts?.length ?? 0;
        final line = _lineTitle(sub);
        return [
          PassCard(
            key: key,
            status: status,
            period: sub.periodName,
            from: sub.boardingTitle,
            to: _withoutTitle(sub.destination) ?? line,
            toCaption: company.isEmpty ? line : '$line · $company',
            footer: PassAction(
              caption: attempts >= 1 && attempts < PayScreen.maxAttempts
                  ? 'المحاولة ${attempts + 1} من ${PayScreen.maxAttempts}'
                  : 'المبلغ المطلوب',
              value: reason.isNotEmpty ? reason : money,
              actionLabel: 'إيصال جديد',
              onAction: () => _pay(sub),
            ),
          ),
          InfoRows(rows: [
            InfoRow(label: 'المبلغ المطلوب', value: money, labelKey: amountLabel, valueKey: amountValue),
          ]),
        ];

      case BasakStatus.pendingReview:
        final receipts = _receiptsOf(sub);
        final latest = receipts == null || receipts.isEmpty ? null : receipts.first;
        final method = _methodName(sub, latest);
        return [
          PeriodCard(
            key: key,
            status: status,
            meta: _year(sub),
            metaLtr: true,
            title: sub.periodName,
            note: latest == null ? null : SubscriptionScreenWords.sentAt(latest.createdAt),
          ),
          InfoRows(rows: [
            ...route,
            InfoRow(label: 'المبلغ', value: money, labelKey: amountLabel, valueKey: amountValue),
            if (method != null) InfoRow(label: 'طريقة الدفع', value: method),
          ]),
        ];

      case BasakStatus.upcoming:
        final starts = DateTime.tryParse(sub.startDate ?? '');
        final line = _lineTitle(sub);
        final receipt = _receiptRow(sub);
        return [
          PassCard(
            key: key,
            status: status,
            period: starts == null
                ? sub.periodName
                : '${sub.periodName} · ${starts.day} ${BasakUi.arabicMonths[starts.month - 1]}',
            from: sub.boardingTitle,
            to: _withoutTitle(sub.destination) ?? line,
            footer: PassStub(line: line, company: company, onShowCard: widget.onNavigateToCard, onInk: false),
          ),
          if (receipt != null) InfoRows(rows: [receipt]),
        ];

      case BasakStatus.active || BasakStatus.expired:
        if (sub.isDaily) {
          return [
            PeriodCard(key: key, status: BasakStatus.active, title: sub.periodName),
            InfoRows(rows: [
              ...route,
              InfoRow(label: 'نقداً في الباص', value: money, labelKey: amountLabel, valueKey: amountValue),
            ]),
          ];
        }
        final receipt = _receiptRow(sub);
        return [
          // Offline, the pass says how old what it shows is.
          ValueListenableBuilder<DateTime?>(
            key: key,
            valueListenable: OfflineCache.offlineSince,
            builder: (context, offlineSince, _) => PeriodCard(
              status: BasakStatus.active,
              meta: offlineSince == null ? _year(sub) : 'آخر تحديث ${ConnectionStripHost.dataTime(offlineSince)}',
              metaLtr: offlineSince == null,
              title: sub.periodName,
              note: sub.endDate == null ? null : SubscriptionScreenWords.daysLeft(sub.endDate),
              bar: sub.startDate == null || sub.endDate == null
                  ? null
                  : ValidityBar(
                      elapsed: SubscriptionScreenWords.elapsed(sub.startDate, sub.endDate),
                      from: ReceiptCard.day(sub.startDate, year: false),
                      to: ReceiptCard.day(sub.endDate),
                    ),
            ),
          ),
          InfoRows(rows: [...route, if (receipt != null) receipt]),
        ];
    }
  }

  /// The receipts of a subscription under review or refused: when the last
  /// one was sent, why it was refused. Read only while the tab is in front.
  List<ReceiptModel>? _receiptsOf(SubscriptionModel sub) {
    if (widget.visible) {
      final read = ref.watch(subscriptionReceiptsProvider(sub.id)).valueOrNull;
      if (read != null) _receipts[sub.id] = read;
    }
    return _receipts[sub.id];
  }

  /// The name of the method a receipt was paid with.
  String? _methodName(SubscriptionModel sub, ReceiptModel? receipt) {
    final companyId = sub.companyId;
    if (receipt?.paymentMethodId == null || companyId == null) return null;
    if (widget.visible) {
      final read = ref.watch(paymentMethodsProvider(companyId)).valueOrNull;
      if (read != null) _methods[companyId] = read;
    }
    return _methods[companyId]?.where((m) => m.id == receipt!.paymentMethodId).firstOrNull?.displayName;
  }

  /// "الإيصال" as a row that opens it, with its code once it is known.
  InfoRow? _receiptRow(SubscriptionModel sub) {
    if (sub.isDaily) return null;
    if (widget.visible) _docs[sub.id] = ref.watch(subscriptionReceiptDocProvider(sub.id));
    final doc = _docs[sub.id];
    void open() => ReceiptScreen.open(context, sub.id);
    final key = Key('receipt-row-${sub.id}');
    final receipt = doc?.valueOrNull;
    if (receipt != null) {
      return InfoRow(key: key, label: 'الإيصال', value: receipt.code, ltrValue: true, onTap: open);
    }
    if (doc != null && doc.hasError) {
      return InfoRow(
        key: key,
        label: 'تعذّر تحميل الإيصال',
        onRetry: () => ref.invalidate(subscriptionReceiptDocProvider(sub.id)),
      );
    }
    if (doc != null && doc.hasValue) return InfoRow(key: key, label: 'لا يوجد إيصال لهذا الاشتراك.');
    return InfoRow(key: key, label: 'الإيصال', onTap: open);
  }

  // ── What comes next ────────────────────────────────────────────────

  /// "Subscribe to the next period in advance": shown only when the company
  /// allows it (the catalog then lists it), with that period's own price. It
  /// opens the builder with the same company, line and station filled in.
  List<Widget> _nextPeriod(SubscriptionModel sub) {
    final line = _catalogShown?.line(sub.lineId);
    if (line == null) {
      if (!_catalogLoading) return const [];
      // Its shape while what is on sale is read for the first time.
      return const [
        Skeleton(
          child: SkeletonCard(
            padding: EdgeInsetsDirectional.all(BasakSpace.s18),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Bone(width: 150, height: 16),
                  SizedBox(height: BasakSpace.s10),
                  Bone(width: 190, height: 12),
                ]),
              ),
              SizedBox(width: BasakSpace.s12),
              Bone(width: 76, height: 44, radius: BasakRadius.small),
            ]),
          ),
        ),
      ];
    }
    final next = line.options.where((o) => o.isUpcoming).toList();
    if (next.isEmpty) return const [];
    return [
      Column(
        key: const Key('next-period'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < next.length; i++) ...[
            if (i > 0) const SizedBox(height: BasakSpace.s10),
            OfferCard(
              title: '${next[i].title} متاح الآن',
              subtitle: 'نفس الخط والمحطة · ${formatMoney(next[i].price)}',
              actionLabel: 'اشترك',
              onAction: () => _subscribe(
                initial: SubscriptionDraft(
                    companyId: line.companyId,
                    lineId: line.id,
                    stationId: line.station(sub.stationId)?.id,
                    optionKey: next[i].key),
                // A student who already holds a subscription is not offered a cash day ride.
                allowDaily: false,
              ),
            ),
          ],
        ],
      ),
    ];
  }

  /// Nothing running: the last subscription, ended, and the same line and
  /// station for the period now on sale — or, when that is not offered, a new
  /// subscription from the start.
  Widget _ended(SubscriptionModel last) {
    final colors = context.colors;
    final text = context.text;
    final line = _catalogShown?.line(last.lineId);
    final station = line?.station(last.stationId);
    // The period that starts first; a single term before the two together.
    final options = [...?line?.options]..sort((a, b) {
        final byStart = a.startDate.compareTo(b.startDate);
        return byStart != 0 ? byStart : a.endDate.compareTo(b.endDate);
      });
    final offer = station == null ? null : options.firstOrNull;
    final paid = last.status == 'expired' || last.isActive;

    return BasakCard(
      radius: BasakRadius.sheet,
      padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const StatusChip(BasakStatus.expired),
              const SizedBox(width: BasakSpace.s12),
              if (last.endDate != null)
                Expanded(
                  child: Text(ReceiptCard.day(last.endDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                ),
            ],
          ),
          const SizedBox(height: BasakSpace.s16),
          Text('انتهى ${last.periodName}', style: text.title),
          if (!paid) Text('انتهى دون دفع', style: text.bodySmall.copyWith(color: colors.ink2)),
          const SizedBox(height: BasakSpace.s16),
          if (offer != null && line != null) ...[
            OfferSummary(
              caption: '${offer.title} · نفس الخط والمحطة',
              value: '${line.name} · ${station!.name}',
              money: formatMoney(offer.price),
            ),
            const SizedBox(height: BasakSpace.s16),
            BasakButton(
              key: const Key('renew'),
              label: 'جدّد الاشتراك',
              onPressed: () => _subscribe(
                initial: SubscriptionDraft(
                    companyId: line.companyId, lineId: line.id, stationId: station.id, optionKey: offer.key),
                allowDaily: true,
              ),
            ),
            const SizedBox(height: BasakSpace.s2),
            SheetLink(
              key: const Key('subscribe-again'),
              label: 'اختر خطاً أو محطة أخرى',
              onTap: () => _subscribe(allowDaily: true),
            ),
          ] else ...[
            Text('لا يوجد اشتراك حالي', style: text.body.copyWith(color: colors.ink2)),
            const SizedBox(height: BasakSpace.s16),
            BasakButton(
              key: const Key('subscribe-again'),
              label: 'اشتراك جديد',
              onPressed: () => _subscribe(allowDaily: true),
            ),
          ],
        ],
      ),
    );
  }

  // ── The past ───────────────────────────────────────────────────────

  /// Past subscriptions as quiet rows, newest first: the latest two, then all
  /// of them on request. A paid one opens its receipt.
  Widget _history(List<SubscriptionModel> history) {
    final shown = _allHistory ? history : history.take(_historyShown).toList();
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s4, BasakSpace.s8, BasakSpace.s4, BasakSpace.s10),
          child: Text(history.length == 1 ? 'اشتراك سابق' : 'اشتراكات سابقة',
              style: text.bodySmall.copyWith(color: context.colors.ink2, fontWeight: FontWeight.w500)),
        ),
        InfoRows(
          rows: [
            for (final old in shown)
              InfoRow(
                key: Key('sub-card-${old.id}'),
                label: old.isDaily || old.academicYear == null
                    ? old.periodName
                    : '${old.periodName} ${old.academicYear}/${old.academicYear! + 1}',
                caption: [
                  old.status == 'expired' || old.isActive
                      ? (old.endDate == null ? 'انتهى' : 'انتهى ${ReceiptCard.day(old.endDate)}')
                      : 'انتهى دون دفع',
                  if ((old.lineName ?? '').trim().isNotEmpty) old.lineName!.trim(),
                ].join(' · '),
                onTap: !old.isDaily && (old.status == 'expired' || old.isActive)
                    ? () => ReceiptScreen.open(context, old.id)
                    : null,
              ),
          ],
          footer: history.length <= _historyShown || _allHistory
              ? null
              : BasakButton(
                  key: const Key('history-all'),
                  label: 'عرض كل الاشتراكات السابقة · ${history.length}',
                  variant: BasakButtonVariant.quiet,
                  size: BasakButtonSize.small,
                  onPressed: () => setState(() => _allHistory = true),
                ),
        ),
      ],
    );
  }
}
