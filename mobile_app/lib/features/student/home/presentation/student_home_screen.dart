import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/sync/sync_hub.dart';
import '../../invites/invites.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../daily_ride/data/daily_ride_repository.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/models/subscription_model.dart';

final subscriptionRepoProvider = Provider((ref) => SubscriptionRepository());
final dailyRideRepoProvider = Provider((ref) => DailyRideRepository());

/// The subscription shown on the home screen: from the saved copy at once,
/// then from the server; refreshed by live events and on app resume.
class CurrentSubscriptionNotifier extends SnapshotNotifier<SubscriptionModel?> {
  @override
  String get snapshotName => 'current_subscription';
  @override
  SubscriptionModel? get signedOut => null;
  @override
  Future<Object?> fetchJson() => ref.read(subscriptionRepoProvider).getCurrentSubscriptionJson();
  @override
  SubscriptionModel? parse(Object? json) =>
      json == null ? null : SubscriptionModel.fromJson(Map<String, dynamic>.from(json as Map));
}

final currentSubscriptionProvider =
    AsyncNotifierProvider<CurrentSubscriptionNotifier, SubscriptionModel?>(CurrentSubscriptionNotifier.new);

class StudentHomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onNavigateToSubscription;
  final VoidCallback onNavigateToQr;

  const StudentHomeScreen({
    super.key,
    required this.onNavigateToSubscription,
    required this.onNavigateToQr,
  });

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  bool _isRidingToday = false;
  bool _isReturningToday = true;
  bool _isSavingRide = false;
  String? _selectedDepartureTime;
  String? _selectedReturnTime;
  DateTime? _loadedRideDate;
  Timer? _votingWindowTimer;
  Map<DateTime, bool> _weeklyRideStatuses = const {};

  static const _ink = Color(0xFF17384A);
  static const _teal = Color(0xFF00658D);
  static const _canvas = Color(0xFFEAF5FA);

  @override
  void initState() {
    super.initState();
    _loadTodayRideStatus();
    _votingWindowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final targetDate =
          ref.read(dailyRideRepoProvider).rideDateForCurrentWindow();
      final loadedDate = _loadedRideDate;
      if (loadedDate == null ||
          loadedDate.year != targetDate.year ||
          loadedDate.month != targetDate.month ||
          loadedDate.day != targetDate.day) {
        _loadTodayRideStatus();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _votingWindowTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTodayRideStatus() async {
    try {
      final rideDate =
          ref.read(dailyRideRepoProvider).rideDateForCurrentWindow();
      final saturdayOffset = (rideDate.weekday + 1) % 7;
      final saturday = DateTime(rideDate.year, rideDate.month, rideDate.day)
          .subtract(Duration(days: saturdayOffset));
      final repository = ref.read(dailyRideRepoProvider);
      final statusesFuture = repository.getRideStatusesForRange(
          saturday, saturday.add(const Duration(days: 6)));
      final detailsFuture = repository.getRideDetailsForDate(rideDate);
      final statuses = await statusesFuture;
      final details = await detailsFuture;
      if (mounted) {
        setState(() {
          _loadedRideDate = rideDate;
          _isRidingToday = details.isRiding;
          _isReturningToday = details.isReturning;
          _selectedDepartureTime = details.departureTime;
          _selectedReturnTime = details.returnTime;
          _weeklyRideStatuses = statuses;
        });
      }
    } catch (_) {
      // The dashboard stays usable when the ride-status service is offline.
    }
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(currentSubscriptionProvider);
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      ref.invalidate(studentProfileSummaryProvider(user.id));
    }
    await _loadTodayRideStatus();
    try {
      await ref.read(currentSubscriptionProvider.future);
    } catch (_) {}
  }

  Future<void> _confirmRide(SubscriptionModel sub,
      {required bool isRiding}) async {
    final repository = ref.read(dailyRideRepoProvider);
    if (!repository.isVotingOpen()) {
      _showRideMessage('التصويت متاح من الساعة ٤ مساءً حتى ٦ صباح يوم الرحلة.',
          isError: true);
      return;
    }
    final departureTimes =
        _availableTimes(sub.departureTimes, sub.departureTime);
    final returnTimes = _availableTimes(sub.returnTimes, sub.returnTime);
    final departureTime = departureTimes.contains(_selectedDepartureTime)
        ? _selectedDepartureTime
        : departureTimes.firstOrNull;
    final returnTime = returnTimes.contains(_selectedReturnTime)
        ? _selectedReturnTime
        : returnTimes.firstOrNull;
    if (isRiding && departureTime == null) {
      _showRideMessage('لا توجد مواعيد ذهاب متاحة لهذا الخط.', isError: true);
      return;
    }
    if (isRiding && _isReturningToday && returnTime == null) {
      _showRideMessage('اختر موعد العودة أو فعّل خيار عدم الركوب في العودة.',
          isError: true);
      return;
    }
    // Show the choice at once; if the server refuses, put the previous one back.
    final before = (
      riding: _isRidingToday,
      departure: _selectedDepartureTime,
      returning: _selectedReturnTime,
      week: _weeklyRideStatuses,
    );
    final rideDate = repository.rideDateForCurrentWindow();
    final rideDay = DateTime(rideDate.year, rideDate.month, rideDate.day);
    setState(() {
      _isSavingRide = true;
      _isRidingToday = isRiding;
      _selectedDepartureTime = departureTime;
      _selectedReturnTime = returnTime;
      _weeklyRideStatuses = {..._weeklyRideStatuses, rideDay: isRiding};
    });
    try {
      final result = await repository.confirmRide(
        rideDate: rideDate,
        isRiding: isRiding,
        departureTime: departureTime,
        returnTime: returnTime,
        isReturning: _isReturningToday,
      );
      if (!mounted) return;
      setState(() {
        _isRidingToday = result.isRiding;
        _isReturningToday = result.isReturning;
        _selectedDepartureTime = result.departureTime;
        _selectedReturnTime = result.returnTime;
        _isSavingRide = false;
      });
      _showRideMessage(isRiding
          ? 'تم تأكيد حضورك ومواعيد رحلتك ليوم ${_dateLabel(rideDate)}.'
          : 'تم إلغاء تأكيد الحضور.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSavingRide = false;
        _isRidingToday = before.riding;
        _selectedDepartureTime = before.departure;
        _selectedReturnTime = before.returning;
        _weeklyRideStatuses = before.week;
      });
      _showRideMessage(errorMessage(e), isError: true);
    }
  }

  List<String> _availableTimes(List<String> configured, String? fallback) {
    final values = configured.where((time) => time.trim().isNotEmpty).toList();
    if (values.isEmpty && fallback != null && fallback.trim().isNotEmpty) {
      values.addAll(fallback
          .split(RegExp(r'[,،]'))
          .map((time) => time.trim())
          .where((time) => time.isNotEmpty));
    }
    values.sort();
    return values;
  }

  String _timeLabel(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return value;
    final rawHour = int.tryParse(match.group(1)!) ?? 0;
    final minute = match.group(2)!;
    final hour = rawHour % 12 == 0 ? 12 : rawHour % 12;
    return '$hour:$minute ${rawHour < 12 ? 'ص' : 'م'}';
  }

  void _showRideMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _dateLabel(DateTime date) {
    const weekdays = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${weekdays[date.weekday - 1]}، ${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(currentSubscriptionProvider);
    // Back from the background, or reconnected: read the ride vote again.
    ref.listen(rideStatusTickProvider, (_, __) => _loadTodayRideStatus());
    final user = ref.watch(authStateProvider).user;
    final profileAsync = user == null
        ? const AsyncValue<Map<String, dynamic>?>.data(null)
        : ref.watch(studentProfileSummaryProvider(user.id));
    final name = (user?.userMetadata?['full_name'] as String?)?.trim();
    final firstName = (name == null || name.isEmpty)
        ? 'طالبنا'
        : name.split(RegExp(r'\s+')).first;
    final now = DateTime.now();

    return GlassScaffold(
      body: ColoredBox(
        color: _canvas,
        child: RefreshIndicator(
          color: _teal,
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverList.list(
                children: [
                  _header(
                      firstName,
                      now,
                      profileAsync.valueOrNull?['profile_image_signed_url']
                          as String?),
                  const SizedBox(height: 18),
                  const InvitesCard(),
                  subAsync.when(
                    loading: () => const _LoadingCard(),
                    error: (_, __) => _ErrorCard(
                        onRetry: () =>
                            ref.invalidate(currentSubscriptionProvider)),
                    data: (sub) => sub == null
                        ? _emptySubscription()
                        : _subscriptionCard(sub),
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle('تأكيد حضور الرحلة',
                      trailing: _pill(
                          ref.read(dailyRideRepoProvider).isVotingOpen()
                              ? 'مفتوح حتى ٦ ص'
                              : 'يفتح ٤ م',
                          const Color(0xFFEAF4FB),
                          _teal)),
                  const SizedBox(height: 10),
                  subAsync.valueOrNull?.isActive == true
                      ? _rideCard(subAsync.valueOrNull!)
                      : _lockedRideCard(),
                  if (subAsync.valueOrNull?.isActive == true) ...[
                    const SizedBox(height: 22),
                    _sectionTitle('مواعيد خطك'),
                    const SizedBox(height: 10),
                    _timesCard(subAsync.valueOrNull!),
                    const SizedBox(height: 22),
                    _sectionTitle('متابعة رحلات الأسبوع'),
                    const SizedBox(height: 10),
                    _weeklyRideCard(),
                  ],
                  if ((subAsync.valueOrNull?.supervisorPhone ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _sectionTitle('مشرف الحافلة',
                        trailing: _pill('متاح للخدمة', const Color(0xFFE7F8F0),
                            const Color(0xFF07865A))),
                    const SizedBox(height: 10),
                    _supervisorCard(subAsync.valueOrNull!),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _header(String firstName, DateTime now, String? avatarUrl) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('صباح الخير، $firstName',
                    style: AppTextStyles.displayMedium
                        .copyWith(color: _ink, fontSize: 23)),
                const SizedBox(height: 4),
                Text(_dateLabel(now),
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: const Color(0xFF718695))),
              ],
            ),
          ),
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            backgroundImage: avatarUrl == null ? null : avatarImage(avatarUrl),
            child: avatarUrl == null
                ? const Icon(LucideIcons.userRound, color: _teal, size: 21)
                : null,
          ),
        ],
      );

  Widget _subscriptionCard(SubscriptionModel sub) {
    final active = sub.isActive;
    final statusText = active && sub.isUpcoming
        ? 'مدفوع · يبدأ ${sub.startDate ?? ''}'
        : active
        ? 'نشط'
        : sub.isPendingReview
            ? 'قيد المراجعة'
            : sub.isRejected
                ? 'مرفوض'
                : 'بانتظار الدفع';
    final statusColor = active
        ? const Color(0xFF40D0A2)
        : sub.isRejected
            ? const Color(0xFFFF8E8E)
            : const Color(0xFFFFC66D);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF247CA2), Color(0xFF075579)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
              color: Color(0x3020698C), blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _pill('●  $statusText', const Color(0x3325D69B), statusColor),
              Text('باصك',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: Colors.white70, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 20),
          Text('المسار المخصص',
              style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(LucideIcons.busFront, size: 22, color: Colors.white),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(sub.lineName ?? 'خط الجامعة',
                      style: AppTextStyles.titleLarge
                          .copyWith(color: Colors.white, fontSize: 19))),
            ],
          ),
          const SizedBox(height: 9),
          _whiteInfo(LucideIcons.mapPin, sub.stationName ?? 'محطة الركوب'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(.13),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(.16))),
            child: Row(
              children: [
                const Icon(LucideIcons.clock3, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('موعد وصول الباص المتوقع',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: Colors.white70)),
                      const SizedBox(height: 3),
                      Text(
                          sub.departureTime == null
                              ? 'يُحدد مع المشرف'
                              : _timeLabel(sub.departureTime!),
                          style: AppTextStyles.titleLarge
                              .copyWith(color: Colors.white, fontSize: 21)),
                    ],
                  ),
                ),
                _pill(active ? 'في الموعد' : statusText,
                    Colors.white.withOpacity(.14), statusColor),
              ],
            ),
          ),
          if (active && sub.endDate != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(LucideIcons.circleCheck,
                    color: Colors.white70, size: 15),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(
                        sub.isUpcoming
                            ? 'من ${sub.startDate} حتى ${sub.endDate}'
                            : 'صالح حتى ${sub.endDate}',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: Colors.white70))),
                Text(sub.periodLabel ?? _subscriptionType(sub.type),
                    style:
                        AppTextStyles.labelSmall.copyWith(color: Colors.white)),
              ],
            ),
          ],
          if (!active) ...[
            const SizedBox(height: 13),
            Text('حالة الاشتراك ستتحدث بعد مراجعة الإيصال.',
                style:
                    AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
          ],
        ],
      ),
    );
  }

  Widget _emptySubscription() => Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: Color(0xFFE5F3FA), shape: BoxShape.circle),
                child: const Icon(LucideIcons.ticket, color: _teal)),
            const SizedBox(height: 12),
            Text('ابدأ رحلتك الجامعية',
                style: AppTextStyles.titleLarge.copyWith(color: _ink)),
            const SizedBox(height: 5),
            Text(
                'اختر خط السير ومحطة الركوب المناسبة لك، ثم أكمل طلب الاشتراك.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: const Color(0xFF718695))),
            const SizedBox(height: 15),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                    onPressed: widget.onNavigateToSubscription,
                    icon: const Icon(LucideIcons.arrowLeft, size: 18),
                    label: const Text('استعراض الاشتراكات'))),
          ],
        ),
      );

  Widget _rideCard(SubscriptionModel sub) {
    final departureTimes =
        _availableTimes(sub.departureTimes, sub.departureTime);
    final returnTimes = _availableTimes(sub.returnTimes, sub.returnTime);
    final selectedDeparture = departureTimes.contains(_selectedDepartureTime)
        ? _selectedDepartureTime
        : departureTimes.firstOrNull;
    final selectedReturn = returnTimes.contains(_selectedReturnTime)
        ? _selectedReturnTime
        : returnTimes.firstOrNull;
    final repository = ref.read(dailyRideRepoProvider);
    final isLocked = !repository.isVotingOpen();
    final rideDate = repository.rideDateForCurrentWindow();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.calendarCheck2, color: _teal, size: 19),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_dateLabel(rideDate),
                  style: AppTextStyles.titleMedium.copyWith(color: _ink))),
          _pill(
              _isRidingToday ? 'تم التأكيد' : 'لم يتم التأكيد',
              _isRidingToday
                  ? const Color(0xFFE7F8F0)
                  : const Color(0xFFF2F7FA),
              _isRidingToday
                  ? const Color(0xFF07865A)
                  : const Color(0xFF718695)),
        ]),
        const SizedBox(height: 5),
        Text(
            'اختر موعد الذهاب والعودة. التصويت من ٤ مساءً حتى ٦ صباح يوم الرحلة.',
            style: AppTextStyles.labelSmall
                .copyWith(color: const Color(0xFF718695))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: Text('موعد الذهاب',
                  style: AppTextStyles.titleMedium.copyWith(color: _ink))),
          Text('${departureTimes.length} مواعيد متاحة',
              style: AppTextStyles.labelSmall
                  .copyWith(color: const Color(0xFF718695))),
        ]),
        const SizedBox(height: 9),
        if (departureTimes.isEmpty)
          _emptyTimeMessage('لم يضف المشرف مواعيد ذهاب لهذا الخط بعد.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(departureTimes.length, (index) {
              final time = departureTimes[index];
              final selected = time == selectedDeparture;
              final label = index == 0
                  ? 'نزول مبكر'
                  : index == 1
                      ? 'نزول متأخر'
                      : 'موعد الذهاب ${index + 1}';
              return SizedBox(
                width: (MediaQuery.sizeOf(context).width - 72) / 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: isLocked
                      ? null
                      : () => setState(() => _selectedDepartureTime = time),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: selected
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFE5EDF2)),
                    ),
                    child: Row(children: [
                      Icon(
                          selected
                              ? LucideIcons.circleCheck
                              : LucideIcons.circle,
                          color: selected
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFB6C3CB),
                          size: 19),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelSmall.copyWith(
                                    color: _ink, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(_timeLabel(time),
                                style: AppTextStyles.titleMedium.copyWith(
                                    color: selected
                                        ? const Color(0xFF16834A)
                                        : _ink)),
                          ])),
                    ]),
                  ),
                ),
              );
            }),
          ),
        const SizedBox(height: 16),
        Text('موعد العودة',
            style: AppTextStyles.titleMedium.copyWith(color: _ink)),
        const SizedBox(height: 8),
        if (returnTimes.isEmpty)
          _emptyTimeMessage('لم يضف المشرف مواعيد عودة لهذا الخط بعد.')
        else
          Wrap(
            spacing: 7,
            runSpacing: 2,
            children: returnTimes.map((time) {
              final selected = time == selectedReturn;
              return ChoiceChip(
                label: Text(_timeLabel(sub.returnShown(time))),
                selected: selected,
                onSelected: isLocked
                    ? null
                    : (_) => setState(() => _selectedReturnTime = time),
                selectedColor: const Color(0xFF2E8FAE),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF526575),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                side: BorderSide(
                    color: selected
                        ? const Color(0xFF2E8FAE)
                        : const Color(0xFFE0E8EE)),
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        CheckboxListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: !_isReturningToday,
          onChanged: isLocked
              ? null
              : (value) =>
                  setState(() => _isReturningToday = !(value ?? false)),
          activeColor: _teal,
          title: Text('لا أريد الركوب في رحلة العودة',
              style: AppTextStyles.labelSmall.copyWith(color: _ink)),
        ),
        if (_isRidingToday) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F9F1),
                borderRadius: BorderRadius.circular(13)),
            child: Text(
                'حضورك مؤكد: ${_timeLabel(selectedDeparture ?? sub.departureTime ?? '')}'
                '${_isReturningToday && selectedReturn != null ? ' والعودة ${_timeLabel(sub.returnShown(selectedReturn))}' : ' بدون عودة'}',
                style: AppTextStyles.labelSmall
                    .copyWith(color: const Color(0xFF087A56))),
          ),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSavingRide ||
                    isLocked ||
                    departureTimes.isEmpty ||
                    (_isReturningToday && returnTimes.isEmpty)
                ? null
                : () => _confirmRide(sub, isRiding: true),
            icon: _isSavingRide
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.circleCheck, size: 18),
            label: Text(
                _isRidingToday ? 'تحديث تأكيد الحضور' : 'تأكيد الحضور للرحلة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB9C8CF),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
        if (isLocked)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Center(
                child: Text(
                    'التصويت مغلق الآن. يفتح من ٤ مساءً حتى ٦ صباح يوم الرحلة.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: const Color(0xFF8A6670)))),
          ),
        if (_isRidingToday && !isLocked)
          Center(
            child: TextButton(
              onPressed: _isSavingRide
                  ? null
                  : () => _confirmRide(sub, isRiding: false),
              child: const Text('إلغاء تأكيد الحضور'),
            ),
          ),
      ]),
    );
  }

  Widget _emptyTimeMessage(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(12)),
        child: Text(message,
            style: AppTextStyles.labelSmall
                .copyWith(color: const Color(0xFF8A6670))),
      );

  Widget _lockedRideCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            const Icon(LucideIcons.lockKeyhole,
                size: 21, color: Color(0xFF7D91A0)),
            const SizedBox(width: 12),
            Expanded(
                child: Text('تأكيد الرحلة متاح بعد تفعيل الاشتراك.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: const Color(0xFF718695)))),
            TextButton(
                onPressed: widget.onNavigateToSubscription,
                child: const Text('اشترك')),
          ],
        ),
      );

  Widget _timesCard(SubscriptionModel sub) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Expanded(
                child: _timeTile('موعد الذهاب', sub.departureTime ?? 'غير محدد',
                    LucideIcons.sunrise)),
            const SizedBox(width: 10),
            Expanded(
                child: _timeTile('موعد العودة', sub.returnTimeShown ?? 'غير محدد',
                    LucideIcons.sunset)),
          ],
        ),
      );

  Widget _weeklyRideCard() {
    final today = DateTime.now();
    final saturdayOffset = (today.weekday + 1) % 7;
    final saturday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: saturdayOffset));
    const labels = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
    final count = _weeklyRideStatuses.values.where((value) => value).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.calendarDays, color: _teal, size: 19),
          const SizedBox(width: 8),
          Expanded(
              child: Text('رحلات مؤكدة هذا الأسبوع',
                  style: AppTextStyles.titleMedium.copyWith(color: _ink))),
          _pill(
              '$count رحلات', const Color(0xFFE7F8F0), const Color(0xFF07865A)),
        ]),
        const SizedBox(height: 14),
        Row(
          children: List.generate(7, (index) {
            final date = saturday.add(Duration(days: index));
            final riding = _weeklyRideStatuses[date] == true;
            final isTomorrow =
                date.year == today.add(const Duration(days: 1)).year &&
                    date.month == today.add(const Duration(days: 1)).month &&
                    date.day == today.add(const Duration(days: 1)).day;
            return Expanded(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: riding
                      ? const Color(0xFFE7F8F0)
                      : const Color(0xFFF3F7FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isTomorrow ? _teal : Colors.transparent),
                ),
                child: Column(children: [
                  Text(labels[index],
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('${date.day}',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: _ink, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Icon(riding ? LucideIcons.circleCheck : LucideIcons.circle,
                      size: 15,
                      color: riding
                          ? const Color(0xFF07865A)
                          : const Color(0xFFB6C3CB)),
                ]),
              ),
            ));
          }),
        ),
      ]),
    );
  }

  Widget _timeTile(String label, String time, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFF4F8FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7EEF3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _teal, size: 19),
          const SizedBox(height: 9),
          Text(label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: const Color(0xFF718695))),
          const SizedBox(height: 3),
          Text(time, style: AppTextStyles.titleMedium.copyWith(color: _ink))
        ]),
      );

  Widget _supervisorCard(SubscriptionModel sub) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFFE5F3FA),
                child:
                    const Icon(LucideIcons.userRound, color: _teal, size: 20)),
            const SizedBox(width: 11),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(sub.supervisorName ?? 'مشرف الخط',
                      style: AppTextStyles.titleMedium.copyWith(color: _ink)),
                  SelectableText(sub.supervisorPhone ?? '',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: const Color(0xFF718695)))
                ])),
            const Icon(LucideIcons.phone, color: _teal, size: 19),
          ],
        ),
      );

  Widget _sectionTitle(String title, {Widget? trailing}) => Row(children: [
        Expanded(
            child: Text(title,
                style: AppTextStyles.titleMedium.copyWith(color: _ink))),
        if (trailing != null) trailing
      ]);

  Widget _pill(String label, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: AppTextStyles.labelSmall
                .copyWith(color: foreground, fontWeight: FontWeight.w700)),
      );

  Widget _whiteInfo(IconData icon, String value) => Row(children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Text(value,
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70))
      ]);

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAF0F4)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A16384A), blurRadius: 14, offset: Offset(0, 5))
        ],
      );

  String _subscriptionType(String type) => switch (type) {
        'yearly' => 'اشتراك سنوي',
        'daily' => 'اشتراك يومي',
        _ => 'اشتراك فصلي',
      };
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 240, child: Center(child: CircularProgressIndicator()));
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          const Text('تعذر تحميل بيانات الاشتراك'),
          TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'))
        ]),
      );
}
