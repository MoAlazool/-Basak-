// What the supervisor has chosen, kept across the tabs (Home, Trips, Scan).
//
// API (shared by every supervisor screen):
//
//   enum TripDirection { departure, returning }
//     .wire                      -> 'departure' | 'return' (what the server and
//                                   the models use)
//     TripDirection.fromWire(s)  -> the enum for a server string
//
//   class SupervisorSelection
//     lineId     String?         the chosen line; null = the first line
//     direction  TripDirection?  the chosen trip's direction; null = no trip
//     tripTime   String?         the chosen trip's start time as the server
//                                sends it ('06:55:00'); null = no trip
//     tripId     String?         line_trips.id of the chosen trip when known
//                                (an extra: an older server sends none)
//     tripKey    String?         '<wire direction>|<HH:mm>' of the chosen trip,
//                                null = none (derived from direction + tripTime)
//     hasTrip    bool
//     copyWith(lineId:, direction:, tripTime:, tripId:)
//
//   supervisorSelectionProvider  NotifierProvider<SupervisorSelectionNotifier,
//                                SupervisorSelection>
//     .selectLine(String lineId)   picks a line and clears the trip
//     .selectTrip({required TripDirection direction, required String time,
//                  String? tripId})
//     .clearTrip()
//     .reset()                     nothing chosen (a new sign-in)
//
// It stores a selection and fetches nothing. A selection that no longer exists
// in the dashboard (a line taken away) is the reader's job to ignore.
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A trip's direction. The models and the server use the [wire] strings.
enum TripDirection {
  departure('departure'),
  returning('return');

  const TripDirection(this.wire);

  /// 'departure' | 'return'.
  final String wire;

  static TripDirection fromWire(String? value) =>
      value == 'return' ? TripDirection.returning : TripDirection.departure;
}

/// What the supervisor has chosen, kept across tabs. Stores a selection; fetches nothing.
class SupervisorSelection {
  final String? lineId;

  /// Direction + time of the chosen trip; both null = no trip chosen.
  final TripDirection? direction;
  final String? tripTime;

  /// The chosen trip's id when the server sent one.
  final String? tripId;

  const SupervisorSelection({this.lineId, this.direction, this.tripTime, this.tripId});

  bool get hasTrip => direction != null && tripTime != null;

  /// `direction|HH:mm` of the chosen trip ('departure|07:00'), null = none.
  String? get tripKey => hasTrip ? keyOf(direction!, tripTime!) : null;

  /// The key of a trip: its direction and its start time to the minute.
  static String keyOf(TripDirection direction, String time) =>
      '${direction.wire}|${time.length >= 5 ? time.substring(0, 5) : time}';

  SupervisorSelection copyWith({
    String? lineId,
    TripDirection? direction,
    String? tripTime,
    String? tripId,
  }) =>
      SupervisorSelection(
        lineId: lineId ?? this.lineId,
        direction: direction ?? this.direction,
        tripTime: tripTime ?? this.tripTime,
        tripId: tripId ?? this.tripId,
      );

  @override
  bool operator ==(Object other) =>
      other is SupervisorSelection &&
      other.lineId == lineId &&
      other.direction == direction &&
      other.tripTime == tripTime &&
      other.tripId == tripId;

  @override
  int get hashCode => Object.hash(lineId, direction, tripTime, tripId);
}

class SupervisorSelectionNotifier extends Notifier<SupervisorSelection> {
  @override
  SupervisorSelection build() => const SupervisorSelection();

  /// Picks a line; the trip chosen on the previous line no longer applies.
  void selectLine(String lineId) => state = SupervisorSelection(lineId: lineId);

  void selectTrip({required TripDirection direction, required String time, String? tripId}) =>
      state = SupervisorSelection(
          lineId: state.lineId, direction: direction, tripTime: time, tripId: tripId);

  void clearTrip() => state = SupervisorSelection(lineId: state.lineId);

  /// Nothing chosen: the next account on this phone starts from its own first line.
  void reset() => state = const SupervisorSelection();
}

final supervisorSelectionProvider =
    NotifierProvider<SupervisorSelectionNotifier, SupervisorSelection>(
        SupervisorSelectionNotifier.new);
