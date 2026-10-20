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
//     lineId     String?         the chosen line; null = the first line;
//                                [allLines] = every line together
//     isAllLines bool
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
//     .restore()                   the account's remembered line (a new launch)
//
// It stores a selection and fetches nothing. A selection that no longer exists
// in the dashboard (a line taken away) is the reader's job to ignore.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/sync/session.dart';

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

  /// [lineId] for every line of the supervisor at once.
  static const allLines = '*';

  bool get isAllLines => lineId == allLines;

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

  /// The chosen line is kept per account, so it survives closing the app.
  static const _prefix = 'basak.sup.line.';
  String? _key() {
    final id = ref.read(sessionUserIdProvider);
    return id == null ? null : '$_prefix$id';
  }

  /// Picks a line (or [SupervisorSelection.allLines]); the trip no longer
  /// applies, and the choice is remembered for this account.
  void selectLine(String lineId) {
    state = SupervisorSelection(lineId: lineId);
    _save(lineId);
  }

  Future<void> _save(String lineId) async {
    final key = _key();
    if (key == null) return;
    try {
      (await SharedPreferences.getInstance()).setString(key, lineId);
    } catch (_) {/* private storage unavailable */}
  }

  void selectTrip({required TripDirection direction, required String time, String? tripId}) =>
      state = SupervisorSelection(
          lineId: state.lineId, direction: direction, tripTime: time, tripId: tripId);

  void clearTrip() => state = SupervisorSelection(lineId: state.lineId);

  /// On launch (or a new sign-in): the account's remembered line, if any; the
  /// trip is for the day, so it starts cleared.
  Future<void> restore() async {
    final key = _key();
    String? saved;
    if (key != null) {
      try {
        saved = (await SharedPreferences.getInstance()).getString(key);
      } catch (_) {/* private storage unavailable */}
    }
    state = SupervisorSelection(lineId: saved);
  }
}

final supervisorSelectionProvider =
    NotifierProvider<SupervisorSelectionNotifier, SupervisorSelection>(
        SupervisorSelectionNotifier.new);
