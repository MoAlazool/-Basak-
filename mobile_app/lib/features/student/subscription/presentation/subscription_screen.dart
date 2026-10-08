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
import '../../lines/data/lines_repository.dart';
import '../../lines/models/line_model.dart';
import '../../lines/models/trip_model.dart';
import '../../lines/models/catalog_model.dart';
import '../../lines/presentation/station_picker.dart';
import '../../../../core/widgets/basak_ui.dart';
import 'package:flutter/services.dart';
import '../models/subscription_model.dart';
import '../models/payment_method_model.dart';
import '../../home/presentation/student_home_screen.dart';

final linesRepoProvider = Provider((ref) => LinesRepository());
// These stay loaded for the session, so opening the page again is instant. They
// are refreshed when the server announces a change (SyncHub) and on app resume,
// and belong to the signed-in account only.
final studentCatalogProvider = FutureProvider<List<CatalogCompany>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(linesRepoProvider).getCatalog();
});

final paymentMethodsProvider =
    FutureProvider.family<List<PaymentMethodModel>, String>((ref, companyId) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getPaymentMethods(companyId);
});

final allLinesProvider = FutureProvider<List<LineModel>>((ref) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(linesRepoProvider).getAllLines();
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
// The offered periods and the daily switch follow the company's settings, which
// send no live event to a student: autoDispose re-reads them each time the
// picker is shown, and resume / pull to refresh re-read them while it is.
final purchasablePeriodsProvider =
    FutureProvider.autoDispose.family<List<PurchasablePeriod>, String>((ref, lineId) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).getPurchasablePeriods(lineId);
});

/// Daily (cash) subscription offered by a company (platform and company switches).
final dailySubscriptionEnabledProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, companyId) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(subscriptionRepoProvider).isDailySubscriptionEnabled(companyId);
});

/// A period overlaps an open subscription (the database refuses those).
bool _overlaps(PurchasablePeriod p, SubscriptionModel s) {
  final start = s.startDate, end = s.endDate;
  if (start == null || end == null) return true;
  return !(p.endDate.compareTo(start) < 0 || p.startDate.compareTo(end) > 0);
}

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
  CatalogCompany? _selectedCompany;
  LineModel? _selectedLine;
  StationModel? _selectedStation;
  List<StationModel> _stations = [];
  List<TripModel> _trips = [];
  String _selectedType = 'termly'; // termly | yearly | daily
  bool _isLoadingStations = false;
  bool _isSubmitting = false;
  bool _isUploadingReceipt = false;
  XFile? _receiptPreview;
  String? _paymentMethodId;

  /// Showing the purchase flow while the student already has subscriptions
  /// (e.g. paying the next semester in advance).
  bool _buying = false;
  PurchasablePeriod? _selectedPeriod;
  String? _focusedSubId;

  void _refreshSubscriptions() {
    ref.invalidate(currentSubscriptionProvider);
    ref.invalidate(allSubscriptionsProvider);
  }

  Future<void> _handleRefresh() async {
    _refreshSubscriptions();
    ref.invalidate(allLinesProvider);
    ref.invalidate(studentCatalogProvider);
    ref.invalidate(purchasablePeriodsProvider);
    ref.invalidate(dailySubscriptionEnabledProvider);
    try {
      await ref.read(allSubscriptionsProvider.future);
    } catch (_) {}
  }

  /// The earliest trip of a direction that stops at [station] (trips arrive
  /// sorted by start time). The student only picks where they board and
  /// chooses the ride times day by day on the home screen; the subscription
  /// still records a trip of each direction, which the database requires.
  TripModel? _firstTripAt(StationModel station, {required bool departure}) => _trips
      .where((trip) => trip.isDeparture == departure && trip.stops.containsKey(station.id))
      .firstOrNull;

  /// Stations a departure trip open to the student stops at, in route order.
  List<StationModel> get _boardingStations =>
      _stations.where((station) => _firstTripAt(station, departure: true) != null).toList();

  Future<void> _onLineSelected(LineModel line) async {
    setState(() {
      _selectedLine = line;
      _selectedPeriod = null;
      _selectedStation = null;
      _trips = [];
      _isLoadingStations = true;
    });

    try {
      final repo = ref.read(linesRepoProvider);
      final results = await Future.wait(
          [repo.getStationsForLine(line.id), repo.getTripsForLine(line.id)]);
      final stations = results[0] as List<StationModel>;
      final trips = results[1] as List<TripModel>;
      if (mounted) {
        setState(() {
          _stations = stations;
          _trips = trips;
          _isLoadingStations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStations = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل المحطات: ${errorMessage(e)}'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _createSubscription() async {
    final station = _selectedStation;
    final departureTrip =
        station == null ? null : _firstTripAt(station, departure: true);
    if (_selectedLine == null || station == null || departureTrip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الخط ومحطة الصعود.')),
      );
      return;
    }
    final returnTrip = _firstTripAt(station, departure: false);
    if (_selectedType != 'daily' && _selectedPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر فترة الاشتراك (الفصل الدراسي).')),
      );
      return;
    }
    if (_selectedType == 'daily') {
      // The company may have switched it off since the picker was shown.
      final offered = await ref
          .refresh(dailySubscriptionEnabledProvider(_selectedLine!.companyId).future)
          .catchError((_) => true); // offline: the server decides
      if (!offered) {
        if (!mounted) return;
        setState(() => _selectedType = 'termly');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('الاشتراك اليومي غير متاح حالياً لدى هذه الشركة.')));
        return;
      }
    }

    setState(() => _isSubmitting = true);

    double price = _selectedType == 'yearly'
        ? _selectedLine!.priceYearly
        : _selectedType == 'termly'
            ? _selectedLine!.priceTermly
            : _selectedLine!.priceDaily;

    try {
      final created = await ref.read(subscriptionRepoProvider).createSubscription(
            lineId: _selectedLine!.id,
            stationId: station.id,
            departureTime: departureTrip.timeAt(station.id)!,
            returnTime: returnTrip?.timeAt(station.id),
            type: _selectedType,
            price: price,
            departureTripId: departureTrip.id,
            returnTripId: returnTrip?.id,
            period: _selectedType == 'daily' ? null : _selectedPeriod,
          );
      _refreshSubscriptions();
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _buying = false;
          _focusedSubId = created.id;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء طلب الاشتراك بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(errorMessage(e)), backgroundColor: AppColors.error),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(allSubscriptionsProvider);
    final linesAsync = ref.watch(allLinesProvider);

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
                return _buildSubscriptionSelectionView(linesAsync, open: open);
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

  Widget _buildActiveSubDetailView(SubscriptionModel sub,
      {required List<SubscriptionModel> open,
      required List<SubscriptionModel> history}) {
    final receiptsAsync = ref.watch(subscriptionReceiptsProvider(sub.id));
    final active = sub.isActive;
    final pendingReview = sub.isPendingReview;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _progressHeader(4),
          const SizedBox(height: 18),
          Text(active ? 'اشتراكك الجامعي' : 'إتمام الاشتراك',
              style: AppTextStyles.displayMedium),
          if (open.length > 1) ...[
            const SizedBox(height: 10),
            _periodTabs(open, sub),
          ],
          const SizedBox(height: 12),
          _subscriptionSummary(sub, active),
          const SizedBox(height: 14),
          if (active && sub.isUpcoming)
            _statusMessage(
              icon: LucideIcons.calendarClock,
              title: 'تم دفع الفترة القادمة مقدماً',
              message:
                  'يبدأ اشتراكك في ${sub.startDate ?? '—'} وينتهي في ${sub.endDate ?? '—'}.',
              color: const Color(0xFF3F51B5),
              background: const Color(0xFFEEF0FF),
            )
          else if (active)
            _statusMessage(
              icon: LucideIcons.circleCheck,
              title: 'تم اعتماد الاشتراك وتفعيله',
              message:
                  'اشتراكك نشط من ${sub.startDate ?? 'تاريخ التفعيل'} حتى ${sub.endDate ?? 'نهاية المدة'}.',
              color: const Color(0xFF07865A),
              background: const Color(0xFFE7F8F0),
            )
          else if (pendingReview)
            _statusMessage(
              icon: LucideIcons.hourglass,
              title: 'إيصالك قيد المراجعة',
              message:
                  'سنرسل لك إشعاراً عند اعتماد الاشتراك. مراجعة الإيصال تتم يدوياً.',
              color: const Color(0xFF00658D),
              background: const Color(0xFFE2F3FB),
            )
          else
            _paymentMethodsCard(sub),
          if (!active) ...[
            const SizedBox(height: 14),
            receiptsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => _receiptUploadCard(sub, 0, null),
              data: (receipts) {
                final latest = receipts.isEmpty ? null : receipts.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sub.isRejected)
                      _statusMessage(
                        icon: LucideIcons.circleX,
                        title: 'تم رفض الإيصال',
                        message: latest?.rejectionReason ??
                            'راجع سبب الرفض مع مشرف الخط قبل إعادة الرفع.',
                        color: const Color(0xFFB42335),
                        background: const Color(0xFFFFECEE),
                      ),
                    const SizedBox(height: 14),
                    _receiptUploadCard(sub, receipts.length, latest),
                  ],
                );
              },
            ),
          ],
          _payNextCard(sub, open),
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

  /// Switch between the current and upcoming subscriptions.
  Widget _periodTabs(List<SubscriptionModel> open, SubscriptionModel focused) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in open)
          ChoiceChip(
            label: Text('${_phaseLabel(s)} · ${s.periodLabel ?? _typeLabel(s.type)}'),
            selected: s.id == focused.id,
            onSelected: (_) => setState(() {
              _focusedSubId = s.id;
              _receiptPreview = null;
            }),
          ),
      ]);

  /// "Pay the next semester in advance" when such a period is payable and not
  /// already covered by an open subscription.
  Widget _payNextCard(SubscriptionModel sub, List<SubscriptionModel> open) {
    final periodsAsync = ref.watch(purchasablePeriodsProvider(sub.lineId));
    final next = (periodsAsync.valueOrNull ?? const <PurchasablePeriod>[])
        .where((p) => p.isUpcoming && !open.any((s) => _overlaps(p, s)))
        .toList();
    if (next.isEmpty) return const SizedBox.shrink();
    return Container(
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
              child: Text('ادفع الفترة القادمة مقدماً',
                  style: AppTextStyles.titleMedium
                      .copyWith(color: const Color(0xFF3F51B5)))),
        ]),
        const SizedBox(height: 6),
        Text(next.map((p) => '${p.label} (${p.startDate} ← ${p.endDate})').join('\n'),
            style: AppTextStyles.bodyMedium),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _buying = true;
              _selectedType = next.first.subscriptionType;
              _selectedPeriod = null;
            }),
            icon: const Icon(LucideIcons.arrowLeft),
            label: const Text('اشترك في الفترة القادمة'),
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
                '${s.periodLabel ?? _typeLabel(s.type)} · ${s.lineName ?? ''}',
                style: AppTextStyles.bodyMedium),
          ),
          Text('${s.startDate ?? ''} ← ${s.endDate ?? ''}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      );

  /// Subscription flow position (1 company, 2 line & station, 3 period, 4 payment).
  int get _selectionStep => _selectedCompany == null
      ? 1
      : (_selectedLine == null || _selectedStation == null)
          ? 2
          : 3;

  Widget _progressHeader(int step) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE3EDF3))),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('الخطوة $step من 4',
                style: AppTextStyles.labelSmall.copyWith(
                    color: const Color(0xFF00658D),
                    fontWeight: FontWeight.bold)),
            Text(step == 4 ? 'الدفع والموافقة' : 'متبقي ${4 - step} خطوات',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary))
          ]),
          const SizedBox(height: 13),
          Row(children: [
            for (var i = 1; i <= 4; i++) ...[
              CircleAvatar(
                  radius: 15,
                  backgroundColor: i <= step
                      ? const Color(0xFF00658D)
                      : const Color(0xFFE7EEF4),
                  child: Icon(i < step ? LucideIcons.check : LucideIcons.circle,
                      size: 15,
                      color:
                          i <= step ? Colors.white : AppColors.textSecondary)),
              if (i < 4)
                Expanded(
                    child: Container(
                        height: 2,
                        color: i < step
                            ? const Color(0xFF00658D)
                            : const Color(0xFFE7EEF4))),
            ]
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('الشركة', style: AppTextStyles.labelSmall),
            Text('الخط والمحطة', style: AppTextStyles.labelSmall),
            Text('الفترة', style: AppTextStyles.labelSmall),
            Text('الدفع', style: AppTextStyles.labelSmall)
          ]),
        ]),
      );

  Widget _subscriptionSummary(SubscriptionModel sub, bool active) => Container(
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
          Row(children: [
            Expanded(
                child: Text(sub.lineName ?? 'مسار الجامعة',
                    style: AppTextStyles.titleLarge)),
            _statusPill(
                active
                    ? 'نشط'
                    : sub.isPendingReview
                        ? 'قيد التدقيق'
                        : sub.isRejected
                            ? 'مرفوض'
                            : 'بانتظار الدفع',
                active)
          ]),
          const SizedBox(height: 8),
          Text(
              sub.periodLabel != null
                  ? '${sub.periodLabel} · ${_phaseLabel(sub)}'
                  : _typeLabel(sub.type),
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
          if (sub.startDate != null && sub.endDate != null)
            Text('من ${sub.startDate} إلى ${sub.endDate}',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
          const Divider(height: 22),
          _summaryLine(LucideIcons.mapPin, 'محطة الصعود',
              sub.stationName ?? 'غير محددة'),
          const SizedBox(height: 10),
          _summaryLine(LucideIcons.clock3, 'مواعيد الذهاب والعودة',
              'تختارها يومياً من الرئيسية'),
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
                    Text('المبلغ المطلوب', style: AppTextStyles.bodyMedium),
                    Text('${sub.price.toStringAsFixed(0)} ج.م',
                        style: AppTextStyles.titleLarge
                            .copyWith(color: const Color(0xFF00658D)))
                  ])),
        ]),
      );

  Widget _summaryLine(IconData icon, String label, String value) =>
      Row(children: [
        Icon(icon, size: 17, color: const Color(0xFF00658D)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary))),
        Text(value,
            style:
                AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600))
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

  /// The company's payment methods: the student picks the one they used,
  /// copies the payment details and then uploads the receipt.
  Widget _paymentMethodsCard(SubscriptionModel sub) {
    final companyId = sub.companyId;
    if (companyId == null) return _paymentFallback(sub);
    return ref.watch(paymentMethodsProvider(companyId)).when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => _paymentFallback(sub),
          data: (methods) {
            if (methods.isEmpty) return _paymentFallback(sub);
            return Container(
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
                  Text('${sub.price.toStringAsFixed(0)} ج.م',
                      style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF00658D))),
                ]),
                const SizedBox(height: 10),
                for (final m in methods) _paymentMethodTile(m),
                const SizedBox(height: 4),
                Text('حوّل المبلغ كاملاً ثم ارفع صورة واضحة للإيصال بالأسفل.',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
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
            if ((m.instructions ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(m.instructions!, style: AppTextStyles.bodyMedium),
              ),
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

  /// No payment method configured by the company yet.
  Widget _paymentFallback(SubscriptionModel sub) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4EDF3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.landmark, color: Color(0xFF00658D)),
            const SizedBox(width: 9),
            Text('تعليمات الدفع', style: AppTextStyles.titleMedium)
          ]),
          const SizedBox(height: 10),
          Text('لم تضف شركة النقل وسائل دفع بعد. تواصل مع إدارة الشركة للحصول على بيانات التحويل، ثم أرفق صورة الإيصال.',
              style: AppTextStyles.bodyMedium),
          const SizedBox(height: 10),
          Text('المبلغ: ${sub.price.toStringAsFixed(0)} ج.م',
              style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF00658D))),
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
          const SizedBox(height: 12),
          Text(
              attempts >= 5
                  ? 'اكتملت المحاولات الخمس. تواصل مع الإدارة لمساعدتك.'
                  : 'ارفع صورة واضحة يظهر فيها رقم العملية وتاريخ التحويل.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
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

  String _typeLabel(String type) => switch (type) {
        'yearly' => 'اشتراك سنوي',
        'daily' => 'اشتراك يومي نقدي',
        _ => 'اشتراك فصلي',
      };

  Widget _buildSubscriptionSelectionView(AsyncValue<List<LineModel>> linesAsync,
      {required List<SubscriptionModel> open}) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (open.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _buying = false),
                icon: const Icon(LucideIcons.arrowRight, size: 18),
                label: const Text('العودة إلى اشتراكاتي'),
              ),
            ),
          _progressHeader(_selectionStep),
          const SizedBox(height: 18),
          Text('اشتراكي الجامعي',
              style: AppTextStyles.displayMedium
                  .copyWith(color: const Color(0xFF17384A))),
          const SizedBox(height: 4),
          Text('اختر خط سير حافلتك ومحطة الصعود المناسبة لك.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: const Color(0xFF718695))),
          const SizedBox(height: 18),

          // 1. Company → 2. Line (only active, serving the student's university)
          ref.watch(studentCatalogProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('تعذر تحميل الشركات: ${errorMessage(err)}'),
            data: (companies) => companies.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BasakUi.card(),
                    child: Column(children: [
                      Text('لا توجد حالياً شركات أو خطوط متاحة لجامعتك.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      TextButton.icon(
                        onPressed: () => ref.invalidate(studentCatalogProvider),
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text('تحديث'),
                      ),
                    ]),
                  )
                : _selectedCompany == null
                    ? _companyStep(companies)
                    : _lineStep(_selectedCompany!),
          ),

          // 2. Pick the boarding station (the ride times are chosen daily)
          if (_selectedLine != null) ...[
            const SizedBox(height: 20),
            Text('اختر محطة الصعود',
                style: AppTextStyles.titleMedium
                    .copyWith(color: const Color(0xFF17384A))),
            const SizedBox(height: 4),
            Text(
                'المحطة التي ستركب منها. موعد الذهاب والعودة تختاره يومياً من الرئيسية.',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            if (_isLoadingStations)
              const Center(child: CircularProgressIndicator())
            else
              StationPicker(
                stations: _boardingStations,
                selectedStationId: _selectedStation?.id,
                onSelect: (station) => setState(() => _selectedStation = station),
              ),

            // 3. Subscription Type & Pricing
            const SizedBox(height: 20),
            Text('٣. اختر فترة الاشتراك',
                style: AppTextStyles.titleMedium
                    .copyWith(color: const Color(0xFF17384A))),
            const SizedBox(height: 8),
            _typeAndPeriodPicker(_selectedLine!, open),

            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00658D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isSubmitting ? null : _createSubscription,
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('الذهاب للدفع'),
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _stepTitle(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF17384A)))),
          if (trailing != null) trailing,
        ]),
      );

  Widget _companyStep(List<CatalogCompany> companies) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepTitle('١. اختر شركة النقل'),
          for (final company in companies)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() {
                  _selectedCompany = company;
                  _selectedLine = null;
                  _selectedStation = null;
                }),
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: BasakUi.card(radius: 18),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.building2, color: BasakUi.teal),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(company.name,
                            style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF17384A))),
                        Text('${company.lines.length} خط متاح لجامعتك',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                      ]),
                    ),
                    const Icon(LucideIcons.chevronLeft, color: AppColors.textSecondary),
                  ]),
                ),
              ),
            ),
        ],
      );

  Widget _lineStep(CatalogCompany company) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepTitle('٢. اختر الخط',
              trailing: TextButton.icon(
                onPressed: () => setState(() {
                  _selectedCompany = null;
                  _selectedLine = null;
                  _selectedStation = null;
                }),
                icon: const Icon(LucideIcons.building2, size: 16),
                label: Text('${company.name} · تغيير'),
              )),
          for (final line in company.lines) _catalogLineCard(line),
        ],
      );

  Widget _catalogLineCard(CatalogLine line) {
    final selected = _selectedLine?.id == line.id;
    String times(List<String> values) => values.map(BasakUi.time12).join('، ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _onLineSelected(line.toLineModel()),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF4FB) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? const Color(0xFF00658D) : const Color(0xFFE6EEF3),
                width: selected ? 1.6 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(selected ? LucideIcons.circleCheck : LucideIcons.busFront,
                  color: selected ? const Color(0xFF00658D) : AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(line.name,
                    style: AppTextStyles.titleMedium.copyWith(color: const Color(0xFF17384A))),
              ),
              Text('${line.priceTermly.toStringAsFixed(0)} ج.م / ترم',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: const Color(0xFF00658D), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text('${line.originName} ← ${line.destination ?? 'الجامعة'}',
                style: AppTextStyles.labelSmall.copyWith(
                    color: const Color(0xFF3F51B5), fontWeight: FontWeight.w700)),
            if (line.universities.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('يخدم: ${line.universities.join('، ')}',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
            ],
            if (line.stations.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('المحطات: ${line.stations.join(' ← ')}',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (line.departureTimes.isNotEmpty)
                BasakPill('ذهاب ${times(line.departureTimes)}',
                    background: const Color(0xFFE7F8F0),
                    foreground: const Color(0xFF15803D),
                    icon: LucideIcons.sunrise),
              if (line.returnTimes.isNotEmpty)
                BasakPill('عودة ${times(line.returnTimes)}',
                    background: const Color(0xFFFFF4E5),
                    foreground: const Color(0xFFB97812),
                    icon: LucideIcons.sunset),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _typeAndPeriodPicker(LineModel line, List<SubscriptionModel> open) {
    final periodsAsync = ref.watch(purchasablePeriodsProvider(line.id));
    return periodsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('تعذر تحميل فترات الاشتراك: ${errorMessage(e)}'),
      data: (all) {
        final periods =
            all.where((p) => !open.any((s) => _overlaps(p, s))).toList();
        final annualOffered = periods.any((p) => p.subscriptionType == 'yearly');
        final dailyOffered = ref.watch(dailySubscriptionEnabledProvider(line.companyId)).valueOrNull ?? false;
        if ((_selectedType == 'yearly' && !annualOffered) ||
            (_selectedType == 'daily' && !dailyOffered)) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => mounted ? setState(() => _selectedType = 'termly') : null);
        }
        final forType =
            periods.where((p) => p.subscriptionType == _selectedType).toList();
        if (_selectedType != 'daily' &&
            (_selectedPeriod == null ||
                !forType.any((p) => p.key == _selectedPeriod!.key)) &&
            forType.isNotEmpty) {
          final preferred = _buying
              ? forType.firstWhere((p) => p.isUpcoming, orElse: () => forType.first)
              : forType.first;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => mounted ? setState(() => _selectedPeriod = preferred) : null);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _buildTypeCard('termly', 'ترم (فصلي)', line.priceTermly),
            if (annualOffered) ...[
              const SizedBox(width: 10),
              _buildTypeCard('yearly', 'سنوي (فصلان)', line.priceYearly),
            ],
            if (!_buying && dailyOffered) ...[
              const SizedBox(width: 10),
              _buildTypeCard('daily', 'يومي (كاش)', line.priceDaily),
            ],
          ]),
          if (_selectedType != 'daily') ...[
            const SizedBox(height: 16),
            Text('فترة الاشتراك',
                style: AppTextStyles.titleMedium
                    .copyWith(color: const Color(0xFF17384A))),
            const SizedBox(height: 8),
            if (forType.isEmpty)
              const Text('لا توجد فترة متاحة للدفع الآن لهذا النوع.')
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in forType)
                  ChoiceChip(
                    label: Text(
                        '${p.label}${p.isUpcoming ? ' · دفع مقدم' : ''}\n${p.startDate} ← ${p.endDate}'),
                    selected: _selectedPeriod?.key == p.key,
                    onSelected: (_) => setState(() => _selectedPeriod = p),
                  ),
              ]),
          ],
        ]);
      },
    );
  }

  Widget _buildTypeCard(String typeKey, String label, double price) {
    final isSelected = _selectedType == typeKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedType = typeKey;
          _selectedPeriod = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEAF4FB) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isSelected
                      ? const Color(0xFF00658D)
                      : const Color(0xFFE6EEF3),
                  width: isSelected ? 1.5 : 1)),
          child: Column(children: [
            Text(label,
                style: AppTextStyles.labelSmall
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${price.toStringAsFixed(0)} ج.م',
                style: AppTextStyles.titleMedium
                    .copyWith(color: const Color(0xFF00658D)))
          ]),
        ),
      ),
    );
  }
}
