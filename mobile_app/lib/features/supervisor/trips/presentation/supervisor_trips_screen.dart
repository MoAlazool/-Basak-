import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/skeleton.dart';
import '../../data/supervisor_repository.dart';
import '../../home/home_counts.dart';
import '../../home/presentation/supervisor_home_screen.dart' show supervisorClockProvider, supervisorTripDayProvider;
import '../../models/supervisor_models.dart';
import '../../selection/supervisor_selection.dart';
import 'rider_sheet.dart';
import 'trip_sheet.dart';

typedef ManifestKey = ({String lineId, String direction, String? tripId});

// Kept per trip for the session: switching direction or tab and coming back shows
// the list at once; live events and scans refresh it.
final tripManifestProvider = FutureProvider.family<TripManifest, ManifestKey>((ref, key) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(supervisorRepoProvider)
      .getTripManifest(lineId: key.lineId, direction: key.direction, tripId: key.tripId);
});

/// Tab 2 — one trip: who boarded and who has not, stop by stop. The line and
/// the trip are the ones chosen in [supervisorSelectionProvider]; with no trip
/// chosen it is the next one to leave. A trip opened from Home's card of
/// tomorrow shows who confirmed instead, from the dashboard.
class SupervisorTripsScreen extends ConsumerStatefulWidget {
  const SupervisorTripsScreen({super.key});

  @override
  ConsumerState<SupervisorTripsScreen> createState() => _SupervisorTripsScreenState();
}

class _SupervisorTripsScreenState extends ConsumerState<SupervisorTripsScreen> {
  /// The direction looked at while no trip is chosen (a direction without trips).
  String? _direction;
  final Set<String> _openStations = {};
  bool _unconfirmedOpen = false;

  DateTime get _now => ref.read(supervisorClockProvider)();

  String _directionOf(SupervisorSelection selection) =>
      selection.direction?.wire ?? _direction ?? (_now.hour < 12 ? 'departure' : 'return');

  Future<void> _refresh(ManifestKey? key) async {
    ref.invalidate(supervisorDashboardProvider);
    if (key != null) ref.invalidate(tripManifestProvider(key));
    try {
      await ref.read(supervisorDashboardProvider.future);
      if (key != null) await ref.read(tripManifestProvider(key).future);
    } catch (_) {
      // The page says so itself.
    }
  }

  void _lookAt(String direction) {
    ref.read(supervisorSelectionProvider.notifier).clearTrip();
    setState(() {
      _direction = direction;
      _openStations.clear();
    });
  }

  Future<void> _changeTrip({
    required DayCounts counts,
    required TripCount? current,
    required String direction,
    required String lineName,
    required bool today,
  }) async {
    final chosen = await TripSheet.show(context,
        counts: counts, current: current, direction: direction, lineName: lineName, now: today ? _now : null);
    if (chosen == null || !mounted) return;
    ref.read(supervisorSelectionProvider.notifier).selectTrip(
        direction: TripDirection.fromWire(chosen.direction), time: chosen.time, tripId: chosen.tripId);
    setState(() {
      _direction = null;
      _openStations.clear();
    });
  }

  String _lineName(String name) => name.startsWith('خط ') ? name : 'خط $name';

  Widget _header(String date) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Semantics(header: true, child: Text('الرحلات', style: context.text.display))),
          Text(date, style: context.text.label.copyWith(color: context.colors.ink3, fontWeight: FontWeight.w400)),
        ],
      );

  Widget _failed({required String title, required VoidCallback onRetry}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .08),
          ToneState(
            icon: LucideIcons.wifiOff,
            tone: BasakTone.warning,
            title: title,
            message: 'تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.',
          ),
          const SizedBox(height: BasakSpace.s16),
          BasakButton(
            label: 'إعادة المحاولة',
            icon: LucideIcons.refreshCw,
            size: BasakButtonSize.medium,
            expand: false,
            onPressed: onRetry,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(supervisorDashboardProvider);
    final data = dashboard.valueOrNull;
    final bottom = MediaQuery.paddingOf(context).bottom + BasakSpace.s24;
    final now = ref.watch(supervisorClockProvider)();

    if (data == null) {
      return BasakPage(
        bottomInset: bottom,
        onRefresh: dashboard.hasError ? () => _refresh(null) : null,
        children: [
          _header(SupervisorWords.date(now)),
          if (dashboard.hasError)
            _failed(title: 'تعذّر تحميل الرحلات', onRetry: () => ref.invalidate(supervisorDashboardProvider))
          else
            const StationRowsSkeleton(rows: 6),
        ],
      );
    }
    if (data.lines.isEmpty) {
      return BasakPage(
        bottomInset: bottom,
        onRefresh: () => _refresh(null),
        children: [
          _header(SupervisorWords.date(data.today)),
          SizedBox(height: MediaQuery.sizeOf(context).height * .08),
          EmptyState(
            page: true,
            icon: LucideIcons.bus,
            title: 'لا يوجد خط مسند إليك',
            message: 'ستظهر الرحلات والركاب هنا بمجرد أن تسند الشركة خطاً إلى حسابك.',
            actionLabel: 'تحديث',
            actionIcon: LucideIcons.refreshCw,
            onAction: () => _refresh(null),
          ),
        ],
      );
    }

    final selection = ref.watch(supervisorSelectionProvider);
    final line = data.lines.firstWhere((l) => l.id == selection.lineId, orElse: () => data.lines.first);
    final direction = _directionOf(selection);
    final day = ref.watch(supervisorTripDayProvider);
    final tomorrow = day != null && !DateUtils.isSameDay(day, data.today);
    final counts = DayCounts.of(data, line, tomorrow ? day : data.today);
    final capacity = ref.watch(lineCapacitiesProvider).valueOrNull?[line.id];

    if (tomorrow) {
      return BasakPage(
        bottomInset: bottom,
        onRefresh: () => _refresh(null),
        children: [
          _header(SupervisorWords.dayTitle(day, now)),
          ..._comingDay(data, line, counts, direction, selection, day, capacity, now),
        ],
      );
    }

    final ManifestKey key = (lineId: line.id, direction: direction, tripId: selection.tripId);
    final manifest = ref.watch(tripManifestProvider(key));
    return BasakPage(
      bottomInset: bottom,
      onRefresh: () => _refresh(key),
      children: [
        _header(SupervisorWords.date(data.today)),
        ...manifest.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const [StationRowsSkeleton(rows: 5)],
          // Never the raw exception.
          error: (_, __) => [
            _failed(title: 'تعذّر تحميل الرحلة', onRetry: () => ref.invalidate(tripManifestProvider(key))),
          ],
          data: (m) => _today(m, line, counts, capacity),
        ),
      ],
    );
  }

  /// "لا توجد رحلات عودة": the two directions to look at, and one sentence.
  List<Widget> _noTrips(SupervisorLine line, String direction, DayCounts counts) => [
        BasakSegmented<String>(
          options: const ['departure', 'return'],
          value: direction,
          label: (d) => '${SupervisorWords.directionTitle(d)} · ${counts.of(d).length}',
          onChanged: _lookAt,
        ),
        SizedBox(height: MediaQuery.sizeOf(context).height * .08),
        EmptyState(
          key: const Key('no-trips'),
          page: true,
          icon: LucideIcons.calendarX2,
          title: 'لا توجد رحلات ${SupervisorWords.direction(direction)}',
          message: '${TripSheet.noTrips(direction, _lineName(line.name))} تظهر هنا فور إضافتها.',
        ),
      ];

  Widget _stopsHead(int stops) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
        child: Row(
          children: [
            Expanded(child: Text('المحطات', style: context.text.label.copyWith(color: context.colors.ink2))),
            Text(ArabicCount.stops(stops),
                style: context.text.label.copyWith(color: context.colors.ink3, fontWeight: FontWeight.w400)),
          ],
        ),
      );

  List<Widget> _today(TripManifest m, SupervisorLine line, DayCounts counts, int? capacity) {
    final trip = m.trip;
    if (m.trips.isEmpty || trip == null) return _noTrips(line, m.direction, counts);

    final lineName = _lineName(m.lineName.isEmpty ? line.name : m.lineName);
    final current = counts.of(m.direction).where((t) => t.tripId == trip.id).firstOrNull ??
        counts.of(m.direction).where((t) => minutesOf(t.time) == minutesOf(trip.startTime)).firstOrNull;
    final total = m.totalStudents, boarded = m.checkedIn;
    final seats = CapacityNote.forTrip(total, capacity);
    final stations = m.stations.where((s) => s.stopTime != null || s.students.isNotEmpty).toList();
    // The stop the bus is at: the first one where someone has yet to board,
    // once boarding has begun.
    final begun = boarded > 0;
    final at = stations.indexWhere((s) => s.checkedIn < s.students.length);

    String boardedAt(DateTime time) => BasakUi.time12('${time.hour}:${time.minute.toString().padLeft(2, '0')}');
    String stopTime(ManifestStation s) => s.stopTime == null
        ? 'الرحلة لا تقف هنا'
        : m.stopTimesUnset
            ? 'تمر الرحلة هنا'
            : BasakUi.time12(s.stopTime);

    // Who boarded, in the order they did; then who is still awaited.
    List<ManifestStudent> boardedFirst(List<ManifestStudent> students) => [
          ...students.where((s) => s.isCheckedIn).toList()..sort((a, b) => a.checkedInAt!.compareTo(b.checkedInAt!)),
          ...students.where((s) => !s.isCheckedIn),
        ];

    void openRider(ManifestStudent s, {ManifestStation? station}) => RiderSheet.show(
          context,
          name: s.fullName,
          phone: s.phone,
          state: s.isCheckedIn
              ? 'صعد ${boardedAt(s.checkedInAt!)}'
              : station == null
                  ? 'لم يؤكّد اليوم'
                  : 'لم يصعد',
          stateTone: s.isCheckedIn
              ? BasakTone.success
              : station == null
                  ? BasakTone.neutral
                  : BasakTone.warning,
          stop: station == null
              ? s.station
              : station.stopTime == null || m.stopTimesUnset
                  ? station.name
                  : '${station.name} · ${BasakUi.time12(station.stopTime)}',
          confirmation: s.confirmed
              ? '${SupervisorWords.direction(m.direction)} ${BasakUi.time12(trip.startTime)}'
              // Boarded here although they chose another time today.
              : s.chosenTime != null
                  ? '${SupervisorWords.direction(m.direction)} ${BasakUi.time12(s.chosenTime)}'
                  : 'لم يؤكّد',
          university: s.university,
        );

    return [
      TripCard(
        key: const Key('trip-card'),
        time: BasakUi.time12(trip.startTime),
        direction: SupervisorWords.direction(m.direction),
        detail: [
          lineName,
          if ((trip.university ?? '').isNotEmpty) trip.university!,
          if (trip.arrivalTime != null)
            m.isReturn
                ? 'الوصول ${BasakUi.time12(trip.arrivalTime)}'
                : 'الوصول إلى الجامعة ${BasakUi.time12(trip.arrivalTime)}',
        ].join(' · '),
        note: seats?.text,
        noteWarns: seats?.warns ?? false,
        onChange: () => _changeTrip(
            counts: counts, current: current, direction: m.direction, lineName: lineName, today: true),
        child: total == 0
            ? const ProgressLine(sentence: 'لم يؤكّد أحد هذه الرحلة بعد', value: 0)
            : ProgressLine(
                sentence: 'صعد $boarded من $total',
                trailing: boarded >= total ? 'صعد الجميع' : 'بقي ${total - boarded}',
                value: boarded / total,
              ),
      ),
      if (stations.isNotEmpty)
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stopsHead(stations.where((s) => s.stopTime != null).length),
            const SizedBox(height: BasakSpace.s8),
            BasakCard(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, station) in stations.indexed)
                    StopRow(
                      key: Key('stop-${station.id}'),
                      name: station.name,
                      time: stopTime(station),
                      boarded: station.checkedIn,
                      expected: station.students.length,
                      state: !begun
                          ? StopState.upcoming
                          : at < 0 || i < at
                              ? StopState.done
                              : i == at
                                  ? StopState.current
                                  : StopState.upcoming,
                      isFirst: i == 0,
                      isLast: i == stations.length - 1,
                      expanded: _openStations.contains(station.id) && station.students.isNotEmpty,
                      onToggle: station.students.isEmpty
                          ? null
                          : () => setState(() => _openStations.contains(station.id)
                              ? _openStations.remove(station.id)
                              : _openStations.add(station.id)),
                      riders: [
                        for (final s in boardedFirst(station.students))
                          StopRider(
                            name: s.fullName,
                            boardedAt: s.isCheckedIn ? boardedAt(s.checkedInAt!) : null,
                            onTap: () => openRider(s, station: station),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      if (m.unconfirmed.isNotEmpty)
        DisclosureCard(
          key: const Key('unconfirmed'),
          title: 'لم يؤكّدوا اليوم · ${m.unconfirmed.length}',
          subtitle: 'مشتركون على الخط لم يحدّدوا موعدهم',
          expanded: _unconfirmedOpen,
          onToggle: () => setState(() => _unconfirmedOpen = !_unconfirmedOpen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, s) in m.unconfirmed.indexed) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
                PersonRow(name: s.fullName, caption: s.station, onTap: () => openRider(s)),
              ],
            ],
          ),
        ),
    ];
  }

  /// A trip of the next ride day: nobody has boarded, so it says who
  /// confirmed, stop by stop, from the dashboard.
  List<Widget> _comingDay(SupervisorDashboard data, SupervisorLine line, DayCounts counts, String direction,
      SupervisorSelection selection, DateTime day, int? capacity, DateTime now) {
    final lineName = _lineName(line.name);
    final trips = counts.of(direction);
    final backToToday = Center(
      child: BasakButton(
        key: const Key('back-to-today'),
        label: 'عرض رحلات اليوم',
        variant: BasakButtonVariant.quiet,
        size: BasakButtonSize.small,
        expand: false,
        onPressed: () => ref.read(supervisorTripDayProvider.notifier).state = null,
      ),
    );
    if (trips.isEmpty) return [..._noTrips(line, direction, counts), backToToday];

    final trip = trips
            .where((t) => selection.tripId != null
                ? t.tripId == selection.tripId
                : selection.tripTime != null && minutesOf(t.time) == minutesOf(selection.tripTime!))
            .firstOrNull ??
        trips.first;
    final firm = SupervisorWords.firmness(data.profile.vote, day, now);
    final seats = CapacityNote.forTrip(trip.riders, capacity);
    final breakdown = trip.breakdown;
    final stations = breakdown?.stations ?? const <TripTimeStation>[];
    final dayName = SupervisorWords.dayName(day, now);

    return [
      TripCard(
        key: const Key('trip-card'),
        time: BasakUi.time12(trip.time),
        direction: SupervisorWords.direction(trip.direction),
        detail: [lineName, if ((breakdown?.university ?? '').isNotEmpty) breakdown!.university!].join(' · '),
        note: seats?.text,
        noteWarns: seats?.warns ?? false,
        onChange: () => _changeTrip(
            counts: counts, current: trip, direction: direction, lineName: lineName, today: false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trip.riders == 0 ? 'لم يؤكّد أحد بعد' : 'أكّد ${ArabicCount.students(trip.riders)}',
              style: context.text.body.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(firm.text,
                style: context.text.label.copyWith(color: context.colors.ink3, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      if (trip.riders > 0 && stations.isEmpty)
        const EmptyState(icon: LucideIcons.users, title: 'التفاصيل غير متاحة')
      else if (stations.isNotEmpty)
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stopsHead(stations.where((s) => s.stopTime != null).length),
            const SizedBox(height: BasakSpace.s8),
            BasakCard(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, station) in stations.indexed)
                    () {
                      final riders = breakdown!.ridersAt(station.id);
                      return StopRow(
                        key: Key('stop-${station.id}'),
                        name: station.name,
                        time: station.stopTime == null ? 'الرحلة لا تقف هنا' : BasakUi.time12(station.stopTime),
                        boarded: 0,
                        expected: station.students,
                        countLabel: '${station.students}',
                        state: StopState.upcoming,
                        isFirst: i == 0,
                        isLast: i == stations.length - 1,
                        expanded: _openStations.contains(station.id) && riders.isNotEmpty,
                        onToggle: riders.isEmpty
                            ? null
                            : () => setState(() => _openStations.contains(station.id)
                                ? _openStations.remove(station.id)
                                : _openStations.add(station.id)),
                        riders: [
                          for (final r in riders)
                            StopRider(
                              name: r.fullName,
                              plain: true,
                              onTap: () => RiderSheet.show(
                                context,
                                name: r.fullName,
                                phone: r.phone,
                                stop: station.stopTime == null
                                    ? station.name
                                    : '${station.name} · ${BasakUi.time12(station.stopTime)}',
                                confirmation:
                                    '${SupervisorWords.direction(trip.direction)} ${BasakUi.time12(trip.time)}',
                                confirmationLabel: dayName == 'غداً' ? 'تأكيد الغد' : 'التأكيد',
                                university: r.university,
                              ),
                            ),
                        ],
                      );
                    }(),
                ],
              ),
            ),
          ],
        ),
      backToToday,
    ];
  }
}
