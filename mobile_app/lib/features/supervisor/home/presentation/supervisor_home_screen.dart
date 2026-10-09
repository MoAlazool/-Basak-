import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/connection_strip_host.dart';
import '../../../../core/widgets/greeting_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../notifications/data/notification_feed.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../notifications/supervisor_notifications_screen.dart';
import '../../selection/supervisor_selection.dart';
import '../home_counts.dart';
import 'line_sheet.dart';

/// The time the supervisor's screens go by: which trip is next, which have
/// passed, how firm a day's numbers are. Replaced in tests.
final supervisorClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Hands the day's counts to the phone's share sheet, as text. Replaced in tests.
final shareCountsProvider = Provider<Future<void> Function(String text)>(
    (ref) => (text) async => SharePlus.instance.share(ShareParams(text: text)));

/// The day Trips shows a trip of: null is today (who boarded); the next ride
/// day shows who confirmed, since nobody has boarded yet. Set when a trip is
/// opened from Home's card of that day.
final supervisorTripDayProvider = StateProvider<DateTime?>((ref) => null);

/// Tab 1 — the numbers the buses are planned on: how many go and how many
/// return, per trip, today and tomorrow. Everything comes from
/// [supervisorDashboardProvider]; the seats of a bus from [lineCapacitiesProvider].
class SupervisorHomeScreen extends ConsumerStatefulWidget {
  /// A trip was chosen (it is in [supervisorSelectionProvider]): show Trips.
  final VoidCallback onOpenTrips;

  const SupervisorHomeScreen({super.key, required this.onOpenTrips});

  @override
  ConsumerState<SupervisorHomeScreen> createState() => _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends ConsumerState<SupervisorHomeScreen> {
  /// 0 today, 1 tomorrow; null until the first numbers decide where to open.
  int? _day;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // "Next" and "past" follow the clock while the screen stays open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(supervisorDashboardProvider);
    ref.invalidate(lineCapacitiesProvider);
    try {
      await ref.read(supervisorDashboardProvider.future);
    } catch (_) {
      // The page says so itself.
    }
  }

  void _openTrip(TripCount trip, {required bool today, required DateTime day}) {
    ref.read(supervisorSelectionProvider.notifier).selectTrip(
        direction: TripDirection.fromWire(trip.direction), time: trip.time, tripId: trip.tripId);
    ref.read(supervisorTripDayProvider.notifier).state = today ? null : day;
    widget.onOpenTrips();
  }

  Future<void> _share(String text) async {
    try {
      await ref.read(shareCountsProvider)(text);
    } catch (_) {
      if (mounted) BasakToast.show(context, 'تعذرت المشاركة على هذا الجهاز.', kind: BasakToastKind.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(supervisorDashboardProvider);
    final data = dashboard.valueOrNull;
    final bottom = MediaQuery.paddingOf(context).bottom + BasakSpace.s24;

    if (data == null && !dashboard.hasError) {
      return const BasakPage(children: [SupervisorHomeSkeleton()]);
    }

    final List<Widget> body;
    if (data == null) {
      body = [
        SizedBox(height: MediaQuery.sizeOf(context).height * .12),
        const ToneState(
          icon: LucideIcons.wifiOff,
          tone: BasakTone.warning,
          title: 'تعذّر تحميل بيانات الخط',
          message: 'تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.',
        ),
        Center(
          child: BasakButton(
            label: 'إعادة المحاولة',
            icon: LucideIcons.refreshCw,
            size: BasakButtonSize.medium,
            expand: false,
            onPressed: () => ref.invalidate(supervisorDashboardProvider),
          ),
        ),
      ];
    } else if (data.lines.isEmpty) {
      body = [
        SizedBox(height: MediaQuery.sizeOf(context).height * .12),
        EmptyState(
          page: true,
          icon: LucideIcons.bus,
          title: 'لا يوجد خط مسند إليك',
          message: 'ستظهر الرحلات والركاب هنا بمجرد أن تسند الشركة خطاً إلى حسابك.',
          actionLabel: 'تحديث',
          actionIcon: LucideIcons.refreshCw,
          onAction: _refresh,
        ),
      ];
    } else {
      body = _content(data);
    }

    return BasakPage(
      onRefresh: _refresh,
      // Clear of the floating tab bar, whose height the shell reports here.
      bottomInset: bottom,
      children: [
        // The greeting and the bell stay in every state, errors included.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GreetingHeader(
              name: data == null ? 'المشرف' : GreetingHeader.firstTwoNames(data.profile.fullName),
              photoUrl: ref.watch(supervisorPhotoUrlProvider).valueOrNull,
              unread: ref.watch(unreadNotificationsProvider),
              onNotifications: () => SupervisorNotificationsScreen.open(context),
            ),
            // Saved numbers on screen: said here, with what it means at the door.
            ConnectionStripHost(
              onRetry: _refresh,
              note: 'المسح لا يسجّل الصعود الآن',
              padding: const EdgeInsetsDirectional.only(top: BasakSpace.s12),
            ),
          ],
        ),
        ...body,
      ],
    );
  }

  List<Widget> _content(SupervisorDashboard data) {
    final colors = context.colors;
    final text = context.text;
    final now = ref.watch(supervisorClockProvider)();
    final selection = ref.watch(supervisorSelectionProvider);
    final lines = data.lines;
    final line = lines.firstWhere((l) => l.id == selection.lineId, orElse: () => lines.first);
    final capacity = ref.watch(lineCapacitiesProvider).valueOrNull?[line.id];
    final vote = data.profile.vote;

    final days = [data.today, DateTime(data.today.year, data.today.month, data.today.day + 1)];
    // Opens on tomorrow once tomorrow's confirmation has opened.
    _day ??= DateUtils.isSameDay(vote.rideDateFor(now), days[1]) ? 1 : 0;
    final index = _day!;
    final counts = [for (final day in days) DayCounts.of(data, line, day)];
    final lineName = line.name.startsWith('خط ') ? line.name : 'خط ${line.name}';

    Widget hero(int i) {
      final day = days[i];
      final firm = SupervisorWords.firmness(vote, day, now);
      final title = SupervisorWords.dayTitle(day, now);
      final c = counts[i];
      return CountsHero(
        key: Key('counts-hero-$i'),
        day: title,
        firmness: firm.text,
        isFinal: firm.isFinal,
        going: c.goingTotal,
        goingTrips: SupervisorWords.inTrips(c.going.length),
        returning: c.returningTotal,
        returningTrips: SupervisorWords.inTrips(c.returning.length),
        shareSentence: SupervisorWords.shareSentence(c.goingTotal, line.registeredStudents, isFinal: firm.isFinal),
        share: line.registeredStudents == 0 ? 0 : c.goingTotal / line.registeredStudents,
        onShare: () => _share(SupervisorWords.shareText(
            lineName: lineName, dayTitle: title, firmness: firm.text, counts: c)),
      );
    }

    final shown = counts[index];
    final isToday = DateUtils.isSameDay(days[index], now);
    // The next trip to leave, of either direction: today's card only.
    TripCount? next;
    if (isToday) {
      for (final trip in [...shown.going, ...shown.returning]) {
        if (SupervisorWords.isPast(trip.time, now)) continue;
        if (next == null || (minutesOf(trip.time) ?? 0) < (minutesOf(next.time) ?? 0)) next = trip;
      }
    }

    Widget column(String direction, List<TripCount> trips) {
      final busiest = trips.fold<int>(0, (max, t) => t.riders > max ? t.riders : max);
      return BarList(
        key: Key('trips-$direction'),
        title: SupervisorWords.directionTitle(direction),
        trailing: trips.isEmpty ? null : ArabicCount.trips(trips.length),
        rows: [
          if (trips.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s8, BasakSpace.s4, BasakSpace.s8, BasakSpace.s8),
              child: Text('لا رحلات بعد', style: text.caption.copyWith(color: colors.ink3)),
            ),
          for (final trip in trips)
            () {
              final note = CapacityNote.forRow(trip.riders, capacity);
              return BarRow(
                key: Key('trip-$direction-${trip.time}'),
                time: BasakUi.time12(trip.time),
                count: trip.riders,
                share: busiest == 0 ? 0 : trip.riders / busiest,
                state: identical(trip, next)
                    ? BarRowState.next
                    : isToday && SupervisorWords.isPast(trip.time, now)
                        ? BarRowState.past
                        : BarRowState.upcoming,
                note: note?.text,
                noteWarns: note?.warns ?? false,
                onTap: () => _openTrip(trip, today: index == 0, day: days[index]),
              );
            }(),
        ],
      );
    }

    final noTrips = shown.going.isEmpty && shown.returning.isEmpty;

    return [
      if (lines.length > 1 || !line.isActive)
        LineSwitchRow(
          key: const Key('line-row'),
          name: lineName,
          caption: [
            if ((data.profile.companyName ?? '').isNotEmpty) data.profile.companyName!,
            if (lines.length > 1) '${lines.indexOf(line) + 1} من ${ArabicCount.lines(lines.length, oblique: true)}',
          ].join(' · '),
          tag: line.isActive ? null : 'خط متوقف',
          onTap: lines.length > 1 ? () => SupervisorLineSheet.show(context) : null,
        ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The day is changed by swiping the card; the other day peeks in.
          PeekPager(
            index: index,
            onChanged: (i) => setState(() => _day = i),
            children: [hero(0), hero(1)],
          ),
          SizedBox(
            height: 34,
            child: OverflowBox(
              maxHeight: 48,
              child: PagerDots(
                count: 2,
                index: index,
                labels: const ['اليوم', 'غداً'],
                onTap: (i) => setState(() => _day = i),
              ),
            ),
          ),
          if (noTrips)
            const BasakCard(
              child: EmptyState(
                icon: LucideIcons.clock3,
                title: 'لا توجد تأكيدات بعد',
                message: 'تظهر هنا أعداد الطلاب لكل موعد ذهاب وعودة بمجرد أن يؤكّد الطلاب ركوبهم.',
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: column('departure', shown.going)),
                const SizedBox(width: BasakSpace.s8),
                Expanded(child: column('return', shown.returning)),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s4, BasakSpace.s8, BasakSpace.s4, 0),
              child: Text(
                shown.isEmpty ? 'لا توجد تأكيدات بعد' : 'اضغط أي رحلة لعرض ركابها ومحطاتها.',
                style: text.caption.copyWith(color: colors.ink3),
              ),
            ),
          ],
        ],
      ),
      EntryRow(
        key: const Key('send-entry'),
        icon: LucideIcons.megaphone,
        title: 'إشعار للطلاب',
        subtitle: 'لكل الخط أو لركاب رحلة واحدة',
        onTap: () => SupervisorSendScreen.open(context, ref),
      ),
    ];
  }
}
