import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/basak_ui.dart';
import '../models/line_model.dart';
import '../models/trip_model.dart';

/// Timetable of one direction: a card per trip with its start time and the
/// meeting points it passes, each with its time. Tapping a meeting point
/// selects that trip at that station.
class TripTimetable extends StatelessWidget {
  final List<TripModel> trips;
  final List<StationModel> stations;
  final String? selectedTripId;
  final String? selectedStationId;

  /// When set, only this station is selectable (return trips after the
  /// student picked their boarding station).
  final String? lockedStationId;
  final void Function(TripModel trip, StationModel station) onSelect;

  const TripTimetable({
    super.key,
    required this.trips,
    required this.stations,
    required this.onSelect,
    this.selectedTripId,
    this.selectedStationId,
    this.lockedStationId,
  });

  static const _green = Color(0xFF22C55E);
  static const _greenSoft = Color(0xFFE7F8F0);

  @override
  Widget build(BuildContext context) {
    final visible = lockedStationId == null
        ? trips
        : trips.where((t) => t.stops.containsKey(lockedStationId)).toList();
    if (visible.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BasakUi.card(),
        child: Text(
          lockedStationId == null ? 'لا توجد رحلات متاحة لجامعتك على هذا الخط.' : 'لا توجد رحلات تمر بمحطتك في هذا الاتجاه.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted),
        ),
      );
    }
    return Column(children: [for (final trip in visible) _tripCard(trip)]);
  }

  Widget _tripCard(TripModel trip) {
    final points = trip.stopsAlong(stations);
    final tripSelected = trip.id == selectedTripId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border(right: BorderSide(color: tripSelected ? _green : const Color(0xFFBBF7D0), width: 5)),
        boxShadow: const [BoxShadow(color: Color(0x0A16384A), blurRadius: 14, offset: Offset(0, 5))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _greenSoft,
                border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
              ),
              child: const Icon(LucideIcons.clock3, color: Color(0xFF15803D), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(BasakUi.time12(trip.startTime),
                    style: AppTextStyles.displayMedium.copyWith(color: BasakUi.ink, fontSize: 22)),
                Text(
                  trip.label.isNotEmpty ? trip.label : (trip.isDeparture ? 'رحلة ذهاب' : 'رحلة عودة'),
                  style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted),
                ),
              ]),
            ),
            BasakPill(
              trip.isDeparture ? 'ذهاب' : 'عودة',
              background: const Color(0xFFF1F5F9),
              foreground: BasakUi.ink,
            ),
          ]),
          if (trip.universityName != null) ...[
            const SizedBox(height: 8),
            BasakPill(trip.universityName!,
                background: const Color(0xFFEEF0FF),
                foreground: const Color(0xFF4F46E5),
                icon: LucideIcons.graduationCap),
          ],
          const Divider(height: 22, color: Color(0xFFEFF3F6)),
          Row(children: [
            const Icon(LucideIcons.bus, size: 18, color: BasakUi.teal),
            const SizedBox(width: 6),
            Expanded(
                child: Text('نقاط التجمع',
                    style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink))),
            BasakPill('${points.length} نقطة'),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < points.length; i++) _point(trip, points[i], i == 0, i == points.length - 1),
          if (trip.arrivalTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 30),
              child: Text(
                '${trip.isDeparture ? 'الوصول للجامعة' : 'الوصول'} ${BasakUi.time12(trip.arrivalTime)}',
                style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _point(TripModel trip, StationModel station, bool first, bool last) {
    final selected = trip.id == selectedTripId && station.id == selectedStationId;
    final enabled = lockedStationId == null || lockedStationId == station.id;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? () => onSelect(trip, station) : null,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline rail
              SizedBox(
                width: 24,
                child: Column(children: [
                  Expanded(child: Container(width: 2, color: first ? Colors.transparent : const Color(0xFFBBF7D0))),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected || first ? _green : Colors.white,
                      border: Border.all(color: _green, width: 2.5),
                    ),
                  ),
                  Expanded(child: Container(width: 2, color: last ? Colors.transparent : const Color(0xFFBBF7D0))),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: selected ? _greenSoft : const Color(0xFFF5F8FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? _green : Colors.transparent, width: 1.4),
                  ),
                  child: Row(children: [
                    if (selected) ...[
                      const Icon(LucideIcons.circleCheck, size: 18, color: Color(0xFF15803D)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(station.name,
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(12)),
                      child: Text(BasakUi.time12(trip.timeAt(station.id)),
                          style: AppTextStyles.labelSmall.copyWith(
                              color: const Color(0xFF15803D), fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Departure (n) | Return (n)" switch used above the timetable.
class TripDirectionTabs extends StatelessWidget {
  final bool departure;
  final int departureCount;
  final int returnCount;
  final ValueChanged<bool> onChanged;

  const TripDirectionTabs({
    super.key,
    required this.departure,
    required this.departureCount,
    required this.returnCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, int count, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: active
                    ? const [BoxShadow(color: Color(0x1016384A), blurRadius: 10, offset: Offset(0, 3))]
                    : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label,
                    style: AppTextStyles.titleMedium
                        .copyWith(color: active ? BasakUi.teal : BasakUi.muted)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: active ? BasakUi.teal : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: active ? Colors.white : BasakUi.muted, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE8F0F5), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        tab('الذهاب', departureCount, departure, () => onChanged(true)),
        tab('العودة', returnCount, !departure, () => onChanged(false)),
      ]),
    );
  }
}
