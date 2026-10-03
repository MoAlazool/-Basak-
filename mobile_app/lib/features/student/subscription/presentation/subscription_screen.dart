import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../lines/data/lines_repository.dart';
import '../../lines/models/line_model.dart';
import '../models/subscription_model.dart';
import '../../home/presentation/student_home_screen.dart';

final linesRepoProvider = Provider((ref) => LinesRepository());
final allLinesProvider = FutureProvider<List<LineModel>>((ref) async {
  return ref.watch(linesRepoProvider).getAllLines();
});
final subscriptionReceiptsProvider =
    FutureProvider.family<List<ReceiptModel>, String>((ref, id) async {
  return ref.watch(subscriptionRepoProvider).getReceiptsHistory(id);
});
final allSubscriptionsProvider =
    FutureProvider<List<SubscriptionModel>>((ref) async {
  return ref.watch(subscriptionRepoProvider).getSubscriptions();
});
final purchasablePeriodsProvider =
    FutureProvider.family<List<PurchasablePeriod>, String>((ref, lineId) async {
  return ref.watch(subscriptionRepoProvider).getPurchasablePeriods(lineId);
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
  LineModel? _selectedLine;
  StationModel? _selectedStation;
  String? _selectedDepartureTime;
  String? _selectedReturnTime;
  List<StationModel> _stations = [];
  String _selectedType = 'termly'; // termly | yearly | daily
  bool _isLoadingStations = false;
  bool _isSubmitting = false;
  bool _isUploadingReceipt = false;
  XFile? _receiptPreview;

  /// Showing the purchase flow while the student already has subscriptions
  /// (e.g. paying the next semester in advance).
  bool _buying = false;
  PurchasablePeriod? _selectedPeriod;
  String? _focusedSubId;

  void _refreshSubscriptions() {
    ref.invalidate(currentSubscriptionProvider);
    ref.invalidate(allSubscriptionsProvider);
  }

  List<String> _departureChoices() => _selectedLine?.hasUniversitySchedule == true
      ? [_selectedLine!.scheduleDepartureTime!]
      : _selectedStation?.departureTimes ?? const [];

  List<String> _returnChoices() => _selectedLine?.hasUniversitySchedule == true
      ? [_selectedLine!.scheduleReturnTime!]
      : _selectedStation?.returnTimes ?? const [];

  String _stationDeparture(StationModel st) =>
      _selectedLine?.hasUniversitySchedule == true
          ? _selectedLine!.scheduleDepartureTime!
          : st.departureTime;

  String _stationReturn(StationModel st) =>
      _selectedLine?.hasUniversitySchedule == true
          ? _selectedLine!.scheduleReturnTime!
          : st.returnTime;

  Future<void> _onLineSelected(LineModel line) async {
    setState(() {
      _selectedLine = line;
      _selectedPeriod = null;
      _selectedStation = null;
      _selectedDepartureTime = null;
      _selectedReturnTime = null;
      _isLoadingStations = true;
    });

    try {
      final stations =
          await ref.read(linesRepoProvider).getStationsForLine(line.id);
      if (mounted) {
        setState(() {
          _stations = stations;
          _isLoadingStations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStations = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر تحميل المحطات: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _createSubscription() async {
    if (_selectedLine == null ||
        _selectedStation == null ||
        _selectedDepartureTime == null ||
        _selectedReturnTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اختر الخط والمحطة وموعدي الذهاب والعودة.')),
      );
      return;
    }
    if (_selectedType != 'daily' && _selectedPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر فترة الاشتراك (الفصل الدراسي).')),
      );
      return;
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
            stationId: _selectedStation!.id,
            departureTime: _selectedDepartureTime!,
            returnTime: _selectedReturnTime!,
            type: _selectedType,
            price: price,
            scheduleId: _selectedLine!.scheduleId,
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
              content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final picked =
          await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (picked != null && mounted) setState(() => _receiptPreview = picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر فتح الصور أو الكاميرا: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _submitReceipt(String subscriptionId) async {
    final picked = _receiptPreview;
    if (picked == null || _isUploadingReceipt) return;

    setState(() => _isUploadingReceipt = true);
    try {
      final history = await ref
          .read(subscriptionRepoProvider)
          .getReceiptsHistory(subscriptionId);
      if (history.length >= 5) {
        throw Exception(
            'وصلت إلى الحد الأقصى لرفع الإيصالات (5 محاولات). تواصل مع الإدارة للمساعدة.');
      }

      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';

      await ref.read(subscriptionRepoProvider).uploadReceipt(
            subscriptionId: subscriptionId,
            fileBytes: bytes,
            fileExtension: ext,
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
              content: Text(e.toString()), backgroundColor: AppColors.error),
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
          error: (err, _) => Center(child: Text('تعذر تحميل الاشتراك: $err')),
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
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _progressHeader(active ? 3 : 2),
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
            _bankTransferCard(sub),
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

  Widget _progressHeader(int step) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE3EDF3))),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('الخطوة $step من 3',
                style: AppTextStyles.labelSmall.copyWith(
                    color: const Color(0xFF00658D),
                    fontWeight: FontWeight.bold)),
            Text(step == 3 ? 'مكتمل' : 'متبقي ${3 - step} خطوة',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary))
          ]),
          const SizedBox(height: 13),
          Row(children: [
            for (var i = 1; i <= 3; i++) ...[
              CircleAvatar(
                  radius: 15,
                  backgroundColor: i <= step
                      ? const Color(0xFF00658D)
                      : const Color(0xFFE7EEF4),
                  child: Icon(i < step ? LucideIcons.check : LucideIcons.circle,
                      size: 15,
                      color:
                          i <= step ? Colors.white : AppColors.textSecondary)),
              if (i < 3)
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
            Text('المسار والمحطة', style: AppTextStyles.labelSmall),
            Text('التسجيل والدفع', style: AppTextStyles.labelSmall),
            Text('الموافقة', style: AppTextStyles.labelSmall)
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
          _summaryLine(LucideIcons.clock3, 'الذهاب / العودة',
              '${sub.departureTime ?? '—'}  /  ${sub.returnTime ?? '—'}'),
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

  Widget _bankTransferCard(SubscriptionModel sub) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4EDF3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.landmark, color: Color(0xFF00658D)),
            const SizedBox(width: 9),
            Text('تعليمات التحويل', style: AppTextStyles.titleMedium)
          ]),
          const SizedBox(height: 10),
          Text(
              'أكمل التحويل إلى بيانات الحساب التي زودتك بها إدارة الجامعة، ثم أرفق صورة واضحة للإيصال.',
              style: AppTextStyles.bodyMedium),
          const SizedBox(height: 10),
          Text('المبلغ: ${sub.price.toStringAsFixed(0)} ج.م',
              style: AppTextStyles.titleMedium
                  .copyWith(color: const Color(0xFF00658D))),
          const SizedBox(height: 5),
          Text('بيانات التحويل البنكي تُدار من إدارة الجامعة.',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
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
                      _isUploadingReceipt ? null : () => _submitReceipt(sub.id),
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
          _progressHeader(1),
          const SizedBox(height: 18),
          Text('اشتراكي الجامعي',
              style: AppTextStyles.displayMedium
                  .copyWith(color: const Color(0xFF17384A))),
          const SizedBox(height: 4),
          Text('اختر خط سير حافلتك ومحطة الصعود المناسبة لك.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: const Color(0xFF718695))),
          const SizedBox(height: 18),

          // 1. Pick Line
          Text('مسارات الحافلات المتاحة',
              style: AppTextStyles.titleMedium
                  .copyWith(color: const Color(0xFF17384A))),
          const SizedBox(height: 8),
          linesAsync.when(
            data: (lines) => Column(
              children: lines.map((line) {
                final isSelected = _selectedLine?.id == line.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => _onLineSelected(line),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? const Color(0xFFEAF4FB) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00658D)
                              : const Color(0xFFE6EEF3),
                          width: isSelected ? 1.6 : 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x0817384A),
                              blurRadius: 12,
                              offset: Offset(0, 4))
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? LucideIcons.checkCircle
                                : LucideIcons.circle,
                            color: isSelected
                                ? const Color(0xFF00658D)
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.name,
                                    style: AppTextStyles.titleMedium.copyWith(
                                        color: const Color(0xFF17384A))),
                                Text(
                                  line.companyName ?? 'شركة النقل',
                                  style: AppTextStyles.labelSmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                                if (line.hasUniversitySchedule)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${line.universityName ?? 'جامعتك'} ← ذهاب ${line.scheduleDepartureTime} · عودة ${line.scheduleReturnTime}',
                                      style: AppTextStyles.labelSmall.copyWith(
                                          color: const Color(0xFF3F51B5),
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(line.priceTermly.toStringAsFixed(0),
                                    style: AppTextStyles.titleLarge.copyWith(
                                        color: const Color(0xFF00658D))),
                                Text('ج.م / ترم',
                                    style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.textSecondary))
                              ]),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('خطأ: $err'),
          ),

          // 2. Pick Station
          if (_selectedLine != null) ...[
            const SizedBox(height: 20),
            Text('محطة الصعود المحددة',
                style: AppTextStyles.titleMedium
                    .copyWith(color: const Color(0xFF17384A))),
            const SizedBox(height: 8),
            if (_isLoadingStations)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: _stations.map((st) {
                  final isSelected = _selectedStation?.id == st.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selectedStation = st;
                        // Scheduled lines: the university trip time is fixed.
                        _selectedDepartureTime =
                            _selectedLine?.scheduleDepartureTime;
                        _selectedReturnTime = _selectedLine?.scheduleReturnTime;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFEAF4FB)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00658D)
                                  : const Color(0xFFE6EEF3),
                              width: isSelected ? 1.5 : 1),
                        ),
                        child: Row(children: [
                          Icon(
                              isSelected
                                  ? LucideIcons.circleCheck
                                  : LucideIcons.mapPin,
                              color: isSelected
                                  ? const Color(0xFF00658D)
                                  : AppColors.textSecondary,
                              size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(st.name,
                                  style: AppTextStyles.bodyLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                    'ذهاب ${_stationDeparture(st).isEmpty ? 'غير محدد' : _stationDeparture(st)}',
                                    style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.textSecondary)),
                                Text(
                                    'عودة ${_stationReturn(st).isEmpty ? 'غير محدد' : _stationReturn(st)}',
                                    style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.textSecondary))
                              ]),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              ),

            if (_selectedStation != null) ...[
              const SizedBox(height: 16),
              _buildTimePicker(
                title: _selectedLine!.hasUniversitySchedule
                    ? 'معاد الذهاب لجامعتك'
                    : 'اختار معاد الذهاب',
                choices: _departureChoices(),
                selected: _selectedDepartureTime,
                onSelected: (value) =>
                    setState(() => _selectedDepartureTime = value),
                color: const Color(0xFF18885B),
              ),
              const SizedBox(height: 12),
              _buildTimePicker(
                title: _selectedLine!.hasUniversitySchedule
                    ? 'معاد العودة لجامعتك'
                    : 'اختار معاد العودة',
                choices: _returnChoices(),
                selected: _selectedReturnTime,
                onSelected: (value) =>
                    setState(() => _selectedReturnTime = value),
                color: const Color(0xFFB97812),
              ),
            ],

            // 3. Subscription Type & Pricing
            const SizedBox(height: 20),
            Text('نوع الاشتراك',
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

  Widget _buildTimePicker({
    required String title,
    required List<String> choices,
    required String? selected,
    required ValueChanged<String> onSelected,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EEF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleMedium.copyWith(color: color)),
          const SizedBox(height: 8),
          if (choices.isEmpty)
            const Text(
                'لا توجد مواعيد متاحة لهذه المحطة. تواصل مع الإدارة لتحديث الجدول.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: choices.map((time) {
                final isSelected = selected == time;
                return ChoiceChip(
                  label: Text(time),
                  selected: isSelected,
                  onSelected: (_) => onSelected(time),
                  selectedColor: color.withOpacity(0.16),
                  labelStyle: TextStyle(
                    color: isSelected ? color : AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// Subscription types and periods come from the database: the annual card
  /// only appears when the company/global switch enables it, and only periods
  /// payable now (current or next) that the student does not already hold.
  Widget _typeAndPeriodPicker(LineModel line, List<SubscriptionModel> open) {
    final periodsAsync = ref.watch(purchasablePeriodsProvider(line.id));
    return periodsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('تعذر تحميل فترات الاشتراك: $e'),
      data: (all) {
        final periods =
            all.where((p) => !open.any((s) => _overlaps(p, s))).toList();
        final annualOffered = periods.any((p) => p.subscriptionType == 'yearly');
        if (_selectedType == 'yearly' && !annualOffered) {
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
            if (!_buying) ...[
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
