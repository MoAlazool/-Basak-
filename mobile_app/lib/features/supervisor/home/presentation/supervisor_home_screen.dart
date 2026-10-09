import 'package:flutter/material.dart';
import '../../../../core/widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../../core/widgets/greeting_header.dart';
import '../../../notifications/data/notification_feed.dart';
import '../../notifications/supervisor_notifications_screen.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../rider_counts/presentation/rider_counts_screen.dart';
import 'trip_riders_sheet.dart';

/// Tab 1 — overview of the supervisor's assigned line(s): registered students,
/// per-station breakdown, university trips and today's activity.
class SupervisorHomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenScanner;

  const SupervisorHomeScreen({super.key, required this.onOpenScanner});

  @override
  ConsumerState<SupervisorHomeScreen> createState() => _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends ConsumerState<SupervisorHomeScreen> {
  String? _selectedLineId;

  Future<void> _refresh() async {
    ref.invalidate(supervisorDashboardProvider);
    await ref.read(supervisorDashboardProvider.future);
  }

  void _push(Widget page, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: BasakUi.canvas,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: BasakUi.canvas,
          foregroundColor: BasakUi.ink,
          elevation: 0,
        ),
        body: page,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(supervisorDashboardProvider);
    return GlassScaffold(
      body: dashboard.when(
        loading: () => const BasakPage(children: [SupervisorHomeSkeleton()]),
        error: (error, _) => BasakPage(onRefresh: _refresh, children: [
          const SizedBox(height: 40),
          BasakMessageCard(
            icon: LucideIcons.wifiOff,
            title: 'تعذر تحميل بيانات الخط',
            message: 'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
            actionLabel: 'إعادة المحاولة',
            onAction: () => ref.invalidate(supervisorDashboardProvider),
          ),
        ]),
        data: (data) => _content(data),
      ),
    );
  }

  Widget _content(SupervisorDashboard data) {
    final lines = data.lines;
    final line = lines.isEmpty
        ? null
        : lines.firstWhere((l) => l.id == _selectedLineId, orElse: () => lines.first);

    return BasakPage(
      onRefresh: _refresh,
      children: [
        GreetingHeader(
          name: data.profile.fullName,
          photoUrl: ref.watch(supervisorPhotoUrlProvider).valueOrNull,
          unread: ref.watch(unreadNotificationsProvider),
          onNotifications: () => SupervisorNotificationsScreen.open(context),
        ),
        const SizedBox(height: 18),
        if (!data.profile.isActive)
          const BasakMessageCard(
            icon: LucideIcons.userX,
            title: 'الحساب موقوف',
            message: 'تم إيقاف حساب المشرف من الإدارة. تواصل مع شركتك لإعادة التفعيل.',
          )
        else if (line == null)
          const BasakMessageCard(
            icon: LucideIcons.bus,
            title: 'لا يوجد خط مسند إليك',
            message: 'ستظهر بيانات الخط والمحطات هنا بمجرد أن تسند الشركة خطاً إلى حسابك.',
          )
        else ...[
          if (lines.length > 1) _lineSelector(lines, line),
          _heroCard(line, data),
          const SizedBox(height: 14),
          BasakStatGrid(tiles: [
            BasakStatTile(
                icon: LucideIcons.users,
                value: '${line.registeredStudents}',
                label: 'طالب مشترك على الخط'),
            BasakStatTile(
                icon: LucideIcons.mapPin,
                value: '${line.stations.length}',
                label: 'محطة نشطة',
                color: const Color(0xFF6366F1)),
            BasakStatTile(
                icon: LucideIcons.calendarCheck2,
                value: '${line.confirmedToday}',
                label: 'أكدوا ركوب اليوم',
                color: const Color(0xFF07865A)),
            BasakStatTile(
                icon: LucideIcons.scanLine,
                value: '${data.totals.checkedInToday}',
                label: 'تسجيل حضور اليوم (بواسطتك)',
                color: const Color(0xFFB97812)),
          ]),
          ..._tripTimesSection(data, line),
          if (line.schedules.isNotEmpty) ...[
            const BasakSectionTitle('رحلات الجامعات على الخط'),
            _schedulesCard(line, data),
          ],
          BasakSectionTitle('الطلاب حسب المحطة',
              trailing: BasakPill('${line.registeredStudents} طالب', icon: LucideIcons.users)),
          _stationsCard(line),
          const BasakSectionTitle('إجراءات سريعة'),
          _actions(data),
        ],
      ],
    );
  }

  Widget _lineSelector(List<SupervisorLine> lines, SupervisorLine selected) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(line.name),
                    selected: line.id == selected.id,
                    onSelected: (_) => setState(() => _selectedLineId = line.id),
                    selectedColor: BasakUi.softTeal,
                    labelStyle: AppTextStyles.labelSmall.copyWith(
                        color: line.id == selected.id ? BasakUi.teal : BasakUi.muted,
                        fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
            ],
          ),
        ),
      );

  /// Prices of the subscription types the company offers right now.
  String _pricesLabel(SupervisorLine line, String? companyId) {
    final offered = companyId == null
        ? null
        : ref.watch(offeredSubscriptionTypesProvider(companyId)).valueOrNull;
    return '${[
      'ترم ${line.priceTermly.toStringAsFixed(0)}',
      if (offered?.annual ?? false) 'سنوي ${line.priceYearly.toStringAsFixed(0)}',
      if (offered?.daily ?? false) 'يومي ${line.priceDaily.toStringAsFixed(0)}',
    ].join(' · ')} ج.م';
  }

  Widget _heroCard(SupervisorLine line, SupervisorDashboard data) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: BasakUi.heroGradient,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(color: Color(0x3020698C), blurRadius: 20, offset: Offset(0, 10))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                BasakPill(line.isActive ? '●  خط نشط' : '●  خط متوقف',
                    background: const Color(0x3325D69B),
                    foreground: line.isActive ? const Color(0xFF40D0A2) : const Color(0xFFFF8E8E)),
                Text(data.profile.companyName ?? 'باصك',
                    style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 18),
            Text(line.directlyAssigned ? 'الخط المسند إليك' : 'خط من خطوط شركتك',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(LucideIcons.busFront, size: 22, color: Colors.white),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(line.name,
                      style: AppTextStyles.titleLarge.copyWith(color: Colors.white, fontSize: 19))),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.13),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(.16))),
              child: Row(children: [
                _heroMetric('${line.registeredStudents}', 'مشترك نشط'),
                _heroDivider(),
                _heroMetric('${line.confirmedToday}', 'مؤكد اليوم'),
                _heroDivider(),
                _heroMetric('${line.stations.length}', 'محطة'),
              ]),
            ),
            const SizedBox(height: 12),
            Text(
              _pricesLabel(line, data.profile.companyId),
              style: AppTextStyles.labelSmall.copyWith(color: Colors.white70),
            ),
          ],
        ),
      );

  Widget _heroMetric(String value, String label) => Expanded(
        child: Column(children: [
          Text(value,
              style: AppTextStyles.titleLarge.copyWith(color: Colors.white, fontSize: 21)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
        ]),
      );

  /// Students per trip on the selected line, grouped by the time each student
  /// chose that day: e.g. "5:00 م → 5 طلاب عائدون". Today first, then the next
  /// ride day once its vote has opened. A row opens the trip's riders.
  List<Widget> _tripTimesSection(SupervisorDashboard data, SupervisorLine line) {
    final rows = data.tripTimes.where((t) => t.lineId == line.id).toList();
    final days = rows.map((t) => DateUtils.dateOnly(t.rideDate)).toSet().toList()..sort();
    final today = DateUtils.dateOnly(data.today);
    return [
      BasakSectionTitle('الطلاب حسب موعد الرحلة',
          trailing: BasakPill('من تأكيدات الطلاب', icon: LucideIcons.clock3)),
      if (rows.isEmpty)
        const BasakMessageCard(
          icon: LucideIcons.clock3,
          title: 'لا توجد تأكيدات بعد',
          message: 'تظهر هنا أعداد الطلاب لكل موعد ذهاب وعودة بمجرد أن يؤكد الطلاب ركوبهم.',
        )
      else
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _tripDayCard(
              day == today ? 'اليوم' : (day == today.add(const Duration(days: 1)) ? 'غداً' : BasakUi.dateLabel(day)),
              rows.where((t) => DateUtils.dateOnly(t.rideDate) == day).toList(),
            ),
          ),
    ];
  }

  Widget _tripDayCard(String dayLabel, List<SupervisorTripTime> rows) {
    final departures = rows.where((t) => !t.isReturn).toList()..sort((a, b) => a.time.compareTo(b.time));
    final returns = rows.where((t) => t.isReturn).toList()..sort((a, b) => a.time.compareTo(b.time));
    Widget group(String title, IconData icon, Color color, List<SupervisorTripTime> items,
            (String, String) noun) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: AppTextStyles.labelSmall.copyWith(color: color, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Text('لا أحد', style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted))
          else
            for (final t in items) _tripTimeRow(t, dayLabel, color, noun),
        ]);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BasakUi.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(dayLabel, style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink)),
        const SizedBox(height: 10),
        group('رحلات الذهاب', LucideIcons.sunrise, const Color(0xFF07865A), departures, ('ذاهب', 'ذاهبون')),
        const Divider(height: 22),
        group('رحلات العودة', LucideIcons.sunset, const Color(0xFFB97812), returns, ('عائد', 'عائدون')),
      ]),
    );
  }

  /// [noun]: (one student, several), e.g. ('ذاهب', 'ذاهبون').
  Widget _tripTimeRow(SupervisorTripTime t, String dayLabel, Color color, (String, String) noun) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => TripRidersSheet.show(context, trip: t, dayLabel: dayLabel),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(BasakUi.time12(t.time),
                    style: AppTextStyles.bodyLarge.copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                if (t.subtitle.isNotEmpty)
                  Text(t.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(t.students == 1 ? '1 طالب ${noun.$1}' : '${t.students} طلاب ${noun.$2}',
                style: AppTextStyles.bodyMedium.copyWith(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronLeft, size: 18, color: BasakUi.muted),
          ]),
        ),
      );

  Widget _heroDivider() =>
      Container(width: 1, height: 34, color: Colors.white.withOpacity(.18));

  /// The line's trips; the pill counts today's riders on each trip by the time
  /// they chose (falls back to subscriptions on a server without per-trip counts).
  Widget _schedulesCard(SupervisorLine line, SupervisorDashboard data) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BasakUi.card(),
        child: Column(
          children: [
            for (final trip in line.schedules)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: Color(0xFFEEF0FF), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.graduationCap, size: 17, color: Color(0xFF4F46E5)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(trip.university,
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                      Text(
                          trip.returnTime.isEmpty
                              ? 'ذهاب ${BasakUi.time12(trip.departureTime)}'
                              : 'ذهاب ${BasakUi.time12(trip.departureTime)} · عودة ${BasakUi.time12(trip.returnTime)}',
                          style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
                    ]),
                  ),
                  _tripRidersPill(trip, data.ridersOnTrip(trip.id, data.today)),
                ]),
              ),
          ],
        ),
      );

  Widget _tripRidersPill(LineUniversityTrip trip, int? ridersToday) => BasakPill(
        ridersToday == null ? '${trip.registeredStudents} طالب' : '$ridersToday اليوم',
        background: const Color(0xFFEEF0FF),
        foreground: const Color(0xFF4F46E5),
        icon: ridersToday == null ? null : LucideIcons.users,
      );

  Widget _stationsCard(SupervisorLine line) {
    if (line.stations.isEmpty) {
      return const BasakMessageCard(
          icon: LucideIcons.mapPinOff,
          title: 'لا توجد محطات',
          message: 'لم تُضف محطات نشطة لهذا الخط بعد.');
    }
    final maxCount = line.stations
        .map((s) => s.registeredStudents)
        .fold<int>(1, (max, value) => value > max ? value : max);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BasakUi.card(),
      child: Column(
        children: [
          for (var i = 0; i < line.stations.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFEAF0F4)),
            _stationRow(line.stations[i], i + 1, maxCount, line.schedules.isNotEmpty),
          ],
        ],
      ),
    );
  }

  Widget _stationRow(SupervisorStation station, int order, int maxCount, bool universityTimes) {
    final share = station.registeredStudents / maxCount;
    final times = universityTimes || station.departureTimes.isEmpty
        ? 'المواعيد حسب الجامعة'
        : 'ذهاب ${station.departureTimes.map(BasakUi.time12).join('، ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
              child: Text('$order',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: BasakUi.teal, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(station.name,
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                Text(times, style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${station.registeredStudents}',
                  style: AppTextStyles.titleLarge.copyWith(color: BasakUi.teal, fontSize: 20)),
              Text('طالب', style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
            ]),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: station.registeredStudents == 0 ? 0 : share,
              minHeight: 6,
              backgroundColor: const Color(0xFFEFF5F8),
              valueColor: const AlwaysStoppedAnimation(BasakUi.teal),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            BasakPill('${station.confirmedToday} مؤكد اليوم',
                background: const Color(0xFFE7F8F0), foreground: const Color(0xFF07865A),
                icon: LucideIcons.calendarCheck2),
            const SizedBox(width: 6),
            BasakPill('${station.checkedInToday} صعد',
                background: const Color(0xFFFFF4E5), foreground: const Color(0xFFB97812),
                icon: LucideIcons.scanLine),
          ]),
        ],
      ),
    );
  }

  Widget _actions(SupervisorDashboard data) => Column(children: [
        _actionTile(
          icon: LucideIcons.scanLine,
          title: 'مسح بطاقة طالب',
          subtitle: 'تحقق من الهوية وسجّل صعود الطالب',
          onTap: widget.onOpenScanner,
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: LucideIcons.users,
          title: 'أعداد الركاب لليوم وغداً',
          subtitle: 'تفاصيل الذهاب والعودة لكل محطة ورحلة جامعة',
          onTap: () => _push(const RiderCountsScreen(), 'أعداد الركاب'),
        ),
      ]);

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int badge = 0,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BasakUi.card(),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
                child: Icon(icon, color: BasakUi.teal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
                ]),
              ),
              if (badge > 0)
                BasakPill('$badge',
                    background: const Color(0xFFFEE2E2), foreground: const Color(0xFFDC2626)),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronLeft, color: BasakUi.muted, size: 18),
            ]),
          ),
        ),
      );
}
