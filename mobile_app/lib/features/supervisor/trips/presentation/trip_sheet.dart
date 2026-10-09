import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../home/home_counts.dart';

/// Every trip of the line on a day, by direction: its time, how far away it
/// is and how many ride. Returns the trip chosen with "عرض الرحلة".
class TripSheet extends StatefulWidget {
  final DayCounts counts;

  /// The trip on screen now.
  final TripCount? current;
  final String direction;

  /// "خط الزرقا", for the sentence of a direction without trips.
  final String lineName;

  /// Null on a day that has not come: no trip is "now" or past yet.
  final DateTime? now;

  const TripSheet({
    super.key,
    required this.counts,
    required this.current,
    required this.direction,
    required this.lineName,
    required this.now,
  });

  static Future<TripCount?> show(
    BuildContext context, {
    required DayCounts counts,
    required TripCount? current,
    required String direction,
    required String lineName,
    required DateTime? now,
  }) =>
      BasakSheet.showFrame<TripCount>(
        context,
        builder: (_) =>
            TripSheet(counts: counts, current: current, direction: direction, lineName: lineName, now: now),
      );

  /// "لم تُضف الشركة رحلات عودة لخط الزرقا بعد."
  static String noTrips(String direction, String lineName) =>
      'لم تُضف الشركة رحلات ${SupervisorWords.direction(direction)} ل$lineName بعد.';

  @override
  State<TripSheet> createState() => _TripSheetState();
}

class _TripSheetState extends State<TripSheet> {
  late String _direction = widget.direction;
  late TripCount? _chosen = widget.current;

  @override
  Widget build(BuildContext context) {
    final trips = widget.counts.of(_direction);
    final now = widget.now;
    return BasakSheetFrame(
      title: 'الرحلة',
      largeTitle: true,
      header: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s16),
        child: BasakSegmented<String>(
          options: const ['departure', 'return'],
          value: _direction,
          label: (d) => '${SupervisorWords.directionTitle(d)} · ${widget.counts.of(d).length}',
          onChanged: (d) => setState(() => _direction = d),
        ),
      ),
      primary: BasakButton(
        key: const Key('trip-show'),
        label: 'عرض الرحلة',
        onPressed: _chosen == null ? null : () => Navigator.of(context).pop(_chosen),
      ),
      child: trips.isEmpty
          ? Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
              child: Text(
                TripSheet.noTrips(_direction, widget.lineName),
                style: context.text.body.copyWith(color: context.colors.ink2),
              ),
            )
          : Semantics(
              container: true,
              label: 'رحلات ${SupervisorWords.directionTitle(_direction)}',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, trip) in trips.indexed) ...[
                    if (i > 0) const SizedBox(height: BasakSpace.s6),
                    TripChoiceRow(
                      key: Key('trip-choice-${trip.direction}-${trip.time}'),
                      time: BasakUi.time12(trip.time),
                      note: now == null ? null : SupervisorWords.distance(trip.time, now),
                      riders: ArabicCount.students(trip.riders),
                      selected: _chosen != null && sameTrip(trip, _chosen!),
                      past: now != null && SupervisorWords.isPast(trip.time, now),
                      onTap: () => setState(() => _chosen = trip),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Two rows of the counts stand for one trip.
bool sameTrip(TripCount a, TripCount b) =>
    a.direction == b.direction &&
    (a.tripId != null && b.tripId != null
        ? a.tripId == b.tripId
        : minutesOf(a.time) == minutesOf(b.time) && a.tripId == b.tripId);
