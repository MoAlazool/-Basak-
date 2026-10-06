import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/session.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../student/lines/presentation/trip_timetable.dart' show TripDirectionTabs;
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../qr_scanner/presentation/supervisor_qr_scanner_screen.dart';

typedef ManifestKey = ({String lineId, String direction, String? tripId});

// Kept per trip for the session: switching direction or tab and coming back shows
// the list at once; live events and scans refresh it.
final tripManifestProvider = FutureProvider.family<TripManifest, ManifestKey>((ref, key) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(supervisorRepoProvider)
      .getTripManifest(lineId: key.lineId, direction: key.direction, tripId: key.tripId);
});

/// Going / Return trips of the supervisor's line: one flow for both directions.
/// Route in travel order, students per station, who is checked in, and a
/// scanner pinned to the selected trip.
class SupervisorTripsScreen extends ConsumerStatefulWidget {
  const SupervisorTripsScreen({super.key});

  @override
  ConsumerState<SupervisorTripsScreen> createState() => _SupervisorTripsScreenState();
}

class _SupervisorTripsScreenState extends ConsumerState<SupervisorTripsScreen> {
  String? _lineId;
  bool _going = DateTime.now().hour < 12;
  final Map<bool, String?> _tripByDirection = {true: null, false: null};
  final Set<String> _openStations = {};

  ManifestKey? _key(List<SupervisorLine> lines) {
    if (lines.isEmpty) return null;
    final lineId = lines.any((l) => l.id == _lineId) ? _lineId! : lines.first.id;
    return (lineId: lineId, direction: _going ? 'departure' : 'return', tripId: _tripByDirection[_going]);
  }

  Future<void> _refresh(ManifestKey key) async {
    ref.invalidate(tripManifestProvider(key));
    await ref.read(tripManifestProvider(key).future);
  }

  Future<void> _scan(TripManifest m, ManifestKey key) async {
    final trip = m.trip;
    if (trip == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text('${m.isReturn ? 'العودة' : 'الذهاب'} · ${BasakUi.time12(trip.startTime)}'),
          backgroundColor: BasakUi.canvas,
          foregroundColor: BasakUi.ink,
          elevation: 0,
        ),
        body: SupervisorQrScannerScreen(
          direction: m.direction,
          tripId: trip.id,
          tripLabel: BasakUi.time12(trip.startTime),
        ),
      ),
    ));
    ref.invalidate(tripManifestProvider(key));
    ref.invalidate(supervisorDashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(supervisorDashboardProvider);
    return GlassScaffold(
      body: dashboard.when(
        loading: () => const BasakPage(children: [BasakLoadingCard(height: 420)]),
        error: (_, __) => BasakPage(children: [
          const SizedBox(height: 40),
          BasakMessageCard(
            icon: LucideIcons.wifiOff,
            title: 'تعذر تحميل الرحلات',
            message: 'تحقق من الاتصال بالإنترنت ثم أعد المحاولة.',
            actionLabel: 'إعادة المحاولة',
            onAction: () => ref.invalidate(supervisorDashboardProvider),
          ),
        ]),
        data: (data) {
          final key = _key(data.lines);
          if (key == null) {
            return const BasakPage(children: [
              BasakPageHeader(title: 'الرحلات', subtitle: 'الذهاب والعودة'),
              SizedBox(height: 18),
              BasakMessageCard(
                icon: LucideIcons.bus,
                title: 'لا يوجد خط مسند إليك',
                message: 'ستظهر رحلات الذهاب والعودة بمجرد إسناد خط لحسابك.',
              ),
            ]);
          }
          final manifest = ref.watch(tripManifestProvider(key));
          return BasakPage(
            onRefresh: () => _refresh(key),
            children: [
              BasakPageHeader(title: 'الرحلات', subtitle: BasakUi.dateLabel(data.today)),
              const SizedBox(height: 14),
              if (data.lines.length > 1) ...[
                _lineChips(data.lines, key.lineId),
                const SizedBox(height: 10),
              ],
              TripDirectionTabs(
                departure: _going,
                departureCount: data.lines.firstWhere((l) => l.id == key.lineId).departureTrips,
                returnCount: data.lines.firstWhere((l) => l.id == key.lineId).returnTrips,
                onChanged: (going) => setState(() {
                  _going = going;
                  _openStations.clear();
                }),
              ),
              const SizedBox(height: 14),
              manifest.when(
                loading: () => const BasakLoadingCard(height: 300),
                error: (e, _) => BasakMessageCard(
                  icon: LucideIcons.triangleAlert,
                  title: 'تعذر تحميل الرحلة',
                  message: '$e',
                  actionLabel: 'إعادة المحاولة',
                  onAction: () => ref.invalidate(tripManifestProvider(key)),
                ),
                data: (m) => _content(m, key),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _lineChips(List<SupervisorLine> lines, String selected) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(line.name),
                selected: line.id == selected,
                onSelected: (_) => setState(() {
                  _lineId = line.id;
                  _tripByDirection.updateAll((_, __) => null);
                  _openStations.clear();
                }),
              ),
            ),
        ]),
      );

  Widget _content(TripManifest m, ManifestKey key) {
    if (m.trips.isEmpty || m.trip == null) {
      return BasakMessageCard(
        icon: LucideIcons.calendarX2,
        title: m.isReturn ? 'لا توجد رحلات عودة' : 'لا توجد رحلات ذهاب',
        message: 'أضف رحلات لهذا الخط من لوحة التحكم (صفحة الخطوط).',
      );
    }
    final trip = m.trip!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trip / time selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final option in m.trips)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  avatar: Icon(LucideIcons.clock3,
                      size: 16, color: option.id == trip.id ? BasakUi.teal : BasakUi.muted),
                  label: Text('${BasakUi.time12(option.startTime)} · ${option.students}'),
                  selected: option.id == trip.id,
                  selectedColor: BasakUi.softTeal,
                  onSelected: (_) => setState(() {
                    _tripByDirection[_going] = option.id;
                    _openStations.clear();
                  }),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        _hero(m, trip),
        const SizedBox(height: 12),
        BasakStatGrid(tiles: [
          BasakStatTile(icon: LucideIcons.users, value: '${m.totalStudents}', label: 'طالب على الرحلة'),
          BasakStatTile(
              icon: LucideIcons.userCheck,
              value: '${m.checkedIn}',
              label: 'تم تسجيلهم',
              color: const Color(0xFF07865A)),
          BasakStatTile(
              icon: LucideIcons.userX,
              value: '${m.totalStudents - m.checkedIn}',
              label: 'لم يُسجَّلوا بعد',
              color: const Color(0xFFB97812)),
          BasakStatTile(
              icon: LucideIcons.calendarCheck2,
              value: '${m.confirmed}',
              label: m.isReturn ? 'أكدوا العودة اليوم' : 'أكدوا الذهاب اليوم',
              color: const Color(0xFF6366F1)),
        ]),
        BasakSectionTitle('المحطات (${m.isReturn ? 'من الجامعة' : 'إلى الجامعة'})',
            trailing: BasakPill('${m.stations.where((s) => s.stopTime != null).length} محطة',
                icon: LucideIcons.mapPin)),
        for (final station in m.stations.where((s) => s.stopTime != null || s.students.isNotEmpty))
          _station(station),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: BasakUi.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: () => _scan(m, key),
          icon: const Icon(LucideIcons.scanLine),
          label: Text('مسح QR لرحلة ${m.isReturn ? 'العودة' : 'الذهاب'} ${BasakUi.time12(trip.startTime)}'),
        ),
      ],
    );
  }

  Widget _hero(TripManifest m, ManifestTripOption trip) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: BasakUi.heroGradient,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x3020698C), blurRadius: 20, offset: Offset(0, 10))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BasakPill(m.isReturn ? 'العودة' : 'الذهاب',
                background: Colors.white.withOpacity(.16),
                foreground: Colors.white,
                icon: m.isReturn ? LucideIcons.sunset : LucideIcons.sunrise),
            const Spacer(),
            Text(m.lineName, style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
          ]),
          const SizedBox(height: 12),
          Text(BasakUi.time12(trip.startTime),
              style: AppTextStyles.displayMedium.copyWith(color: Colors.white, fontSize: 32)),
          if (trip.label.isNotEmpty || trip.university != null)
            Text([trip.label, if (trip.university != null) trip.university!].where((x) => x.isNotEmpty).join(' · '),
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
          const SizedBox(height: 12),
          // Route in travel order
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 6,
            children: [
              for (var i = 0; i < m.routeNames.length; i++) ...[
                if (i > 0) const Icon(LucideIcons.arrowLeft, size: 14, color: Colors.white70),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(i == 0 || i == m.routeNames.length - 1 ? .22 : .12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(m.routeNames[i],
                      style: AppTextStyles.labelSmall.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          if (trip.arrivalTime != null) ...[
            const SizedBox(height: 10),
            Text('الوصول ${BasakUi.time12(trip.arrivalTime)}',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
          ],
        ]),
      );

  Widget _station(ManifestStation station) {
    final open = _openStations.contains(station.id);
    final done = station.students.isNotEmpty && station.checkedIn == station.students.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BasakUi.card(),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => open ? _openStations.remove(station.id) : _openStations.add(station.id)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: done ? const Color(0xFFE7F8F0) : BasakUi.softTeal, shape: BoxShape.circle),
                child: Icon(done ? LucideIcons.circleCheck : LucideIcons.mapPin,
                    size: 18, color: done ? const Color(0xFF07865A) : BasakUi.teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(station.name,
                      style: AppTextStyles.bodyLarge.copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                  Text(station.stopTime == null ? 'الرحلة لا تقف هنا' : BasakUi.time12(station.stopTime),
                      style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
                ]),
              ),
              BasakPill('${station.checkedIn}/${station.students.length}',
                  background: done ? const Color(0xFFE7F8F0) : const Color(0xFFF1F5F9),
                  foreground: done ? const Color(0xFF07865A) : BasakUi.ink,
                  icon: LucideIcons.users),
              const SizedBox(width: 4),
              Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: BasakUi.muted),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: station.students.isEmpty
                ? Text('لا يوجد طلاب على هذه المحطة في هذه الرحلة.',
                    style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted))
                : Column(children: [for (final s in station.students) _student(s)]),
          ),
      ]),
    );
  }

  Widget _student(ManifestStudent s) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: s.isCheckedIn ? const Color(0xFFF0FBF5) : const Color(0xFFF7F9FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(s.isCheckedIn ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 18, color: s.isCheckedIn ? const Color(0xFF07865A) : BasakUi.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.fullName,
                  style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
              Text(s.phone, textDirection: TextDirection.ltr,
                  style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              s.isCheckedIn
                  ? 'سُجّل ${BasakUi.time12('${s.checkedInAt!.hour}:${s.checkedInAt!.minute.toString().padLeft(2, '0')}')}'
                  : 'لم يُسجَّل',
              style: AppTextStyles.labelSmall.copyWith(
                  color: s.isCheckedIn ? const Color(0xFF07865A) : const Color(0xFFB97812),
                  fontWeight: FontWeight.w700),
            ),
            if (s.confirmed)
              Text('أكد في التطبيق', style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted, fontSize: 10)),
          ]),
        ]),
      );
}
