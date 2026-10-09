import '../../../core/ui/arabic_count.dart';
import '../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../student/daily_ride/models/vote_settings.dart';
import '../models/supervisor_models.dart';

/// What the supervisor's Home and Trips say, apart from how it is drawn: the
/// riders of every trip of a line on a day, and the words around them.
/// Everything here is read from the dashboard already in memory.

String _hhmm(String time) => time.length >= 5 ? time.substring(0, 5) : time;

/// Minutes after midnight of "07:15:00"; null when it is not a time.
int? minutesOf(String time) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time);
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

/// One trip of a line on a day and how many ride it.
class TripCount {
  /// 'departure' | 'return'
  final String direction;

  /// The trip's start as the server sends it ("07:00:00").
  final String time;

  /// line_trips.id; null for riders whose time matches no trip, and from an
  /// older server.
  final String? tripId;
  final int riders;

  /// The riders by stop, by university and by name, when anyone rides and the
  /// server sent them.
  final SupervisorTripTime? breakdown;

  const TripCount({
    required this.direction,
    required this.time,
    required this.tripId,
    required this.riders,
    this.breakdown,
  });

  bool get isReturn => direction == 'return';
}

/// The numbers of one line on one day: every trip of both directions with its
/// riders, trips nobody rides included.
class DayCounts {
  final DateTime day;
  final List<TripCount> going;
  final List<TripCount> returning;

  const DayCounts({required this.day, required this.going, required this.returning});

  int get goingTotal => going.fold(0, (sum, t) => sum + t.riders);
  int get returningTotal => returning.fold(0, (sum, t) => sum + t.riders);
  bool get isEmpty => goingTotal == 0 && returningTotal == 0;

  List<TripCount> of(String direction) => direction == 'return' ? returning : going;

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// The trips of [line] on [day]: the line's own trips (0 riders allowed),
  /// each with the riders who chose it, then any time riders chose that
  /// matches no trip. By time.
  factory DayCounts.of(SupervisorDashboard data, SupervisorLine line, DateTime day) {
    final rows = data.tripTimes.where((t) => t.lineId == line.id && _sameDay(t.rideDate, day)).toList();
    List<TripCount> side(String direction) {
      final left = rows.where((r) => r.direction == direction).toList();
      final trips = <TripCount>[];
      for (final trip in line.tripsOf(direction)) {
        final index = left.indexWhere((r) => trip.id != null && r.tripId != null
            ? r.tripId == trip.id
            : r.tripId == null && _hhmm(r.time) == _hhmm(trip.startTime));
        final row = index < 0 ? null : left.removeAt(index);
        trips.add(TripCount(
            direction: direction, time: trip.startTime, tripId: trip.id, riders: row?.students ?? 0, breakdown: row));
      }
      for (final row in left) {
        trips.add(TripCount(
            direction: direction, time: row.time, tripId: row.tripId, riders: row.students, breakdown: row));
      }
      return trips..sort((a, b) => _hhmm(a.time).compareTo(_hhmm(b.time)));
    }

    return DayCounts(day: DateTime(day.year, day.month, day.day), going: side('departure'), returning: side('return'));
  }
}

/// What is said about one bus's seats on a trip. Null: nothing to say.
class CapacityNote {
  final String text;

  /// More riders than one bus takes.
  final bool warns;

  const CapacityNote(this.text, {required this.warns});

  /// From this share of the seats on, a row says how full the bus is.
  static const nearlyFull = .8;

  /// How many buses of [capacity] seats [riders] need.
  static int busesFor(int riders, int capacity) => capacity <= 0 ? 1 : (riders / capacity).ceil();

  /// On a row of Home: silent while the bus has room, "45 من 50" once it is
  /// nearly full, "يحتاج باصين" when one bus is not enough.
  static CapacityNote? forRow(int riders, int? capacity) {
    if (capacity == null || capacity <= 0 || riders <= 0) return null;
    if (riders > capacity) {
      return CapacityNote('يحتاج ${ArabicCount.buses(busesFor(riders, capacity), oblique: true)}', warns: true);
    }
    if (riders >= capacity * nearlyFull) return CapacityNote('$riders من $capacity', warns: false);
    return null;
  }

  /// On the trip card: always said once the company set the seats.
  static CapacityNote? forTrip(int riders, int? capacity) {
    if (capacity == null || capacity <= 0) return null;
    if (riders > capacity) {
      return CapacityNote(
          'يحتاج ${ArabicCount.buses(busesFor(riders, capacity), oblique: true)} · الباص $capacity مقعداً',
          warns: true);
    }
    return CapacityNote('مقاعد الباص: $riders من $capacity', warns: false);
  }
}

abstract final class SupervisorWords {
  /// "الأحد 11 أكتوبر".
  static String date(DateTime day) =>
      '${BasakUi.arabicWeekdays[day.weekday - 1]} ${day.day} ${BasakUi.arabicMonths[day.month - 1]}';

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// "اليوم", "غداً", or nothing for any other day.
  static String? dayName(DateTime day, DateTime now) {
    if (_sameDay(day, now)) return 'اليوم';
    if (_sameDay(day, DateTime(now.year, now.month, now.day + 1))) return 'غداً';
    return null;
  }

  /// "اليوم · الأحد 11 أكتوبر".
  static String dayTitle(DateTime day, DateTime now) => [dayName(day, now), date(day)].whereType<String>().join(' · ');

  static String _clock(DateTime at) => BasakUi.time12('${at.hour}:${at.minute.toString().padLeft(2, '0')}');

  /// How firm the numbers of [day] are, from the company's vote window:
  /// closed ("نهائي · أُغلق التأكيد 6:00 ص"), open ("التأكيد مفتوح حتى 6:00 ص")
  /// or not open yet.
  static ({String text, bool isFinal}) firmness(VoteSettings vote, DateTime day, DateTime now) {
    final window = vote.windowFor(day);
    if (!now.isBefore(window.closes)) return (text: 'نهائي · أُغلق التأكيد ${_clock(window.closes)}', isFinal: true);
    if (now.isBefore(window.opens)) return (text: 'يفتح التأكيد ${_clock(window.opens)}', isFinal: false);
    return (text: 'التأكيد مفتوح حتى ${_clock(window.closes)}', isFinal: false);
  }

  /// "سيركب 107 من 124 مشتركاً" once the numbers are final, "أكّد 64 من 124
  /// مشتركاً حتى الآن" while students may still answer.
  static String shareSentence(int riders, int subscribers, {required bool isFinal}) {
    final of = ArabicCount.subscribers(subscribers, oblique: true);
    return isFinal ? 'سيركب $riders من $of' : 'أكّد $riders من $of حتى الآن';
  }

  /// "في 5 رحلات".
  static String inTrips(int trips) => trips == 0 ? 'لا رحلات' : 'في ${ArabicCount.trips(trips, oblique: true)}';

  static String direction(String direction) => direction == 'return' ? 'عودة' : 'ذهاب';
  static String directionTitle(String direction) => direction == 'return' ? 'العودة' : 'الذهاب';

  /// The day's counts as text, for the company and the drivers.
  static String shareText({
    required String lineName,
    required String dayTitle,
    required String firmness,
    required DayCounts counts,
  }) {
    String rows(List<TripCount> trips) =>
        trips.isEmpty ? '—' : trips.map((t) => '${BasakUi.time12(t.time)}: ${t.riders}').join('\n');
    return [
      'أعداد الركاب · $lineName',
      dayTitle,
      firmness,
      '',
      'الذهاب: ${counts.goingTotal}',
      rows(counts.going),
      '',
      'العودة: ${counts.returningTotal}',
      rows(counts.returning),
    ].join('\n');
  }

  /// How far [time] is from now, for the trip sheet: "مضى موعدها", "الآن"
  /// (it leaves within [nowWindow] minutes, or left less than that ago), "بعد 27
  /// دقيقة" within the hour, nothing further away.
  static String? distance(String time, DateTime now) {
    final at = minutesOf(time);
    if (at == null) return null;
    final delta = at - (now.hour * 60 + now.minute);
    if (delta < -nowWindow) return 'مضى موعدها';
    if (delta <= nowWindow) return 'الآن';
    if (delta < 60) return 'بعد ${ArabicCount.minutes(delta)}';
    return null;
  }

  /// A trip is "now" from this many minutes before it leaves to as many after
  /// (the bus is still on its stops); only then is its time past.
  static const nowWindow = 20;

  /// Its time has passed, by the clock: it left more than [nowWindow] ago.
  static bool isPast(String time, DateTime now) {
    final at = minutesOf(time);
    return at != null && at < now.hour * 60 + now.minute - nowWindow;
  }
}
