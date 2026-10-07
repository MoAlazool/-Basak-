/// When students may confirm a ride and how often the app reminds those who
/// have not, as set in the dashboard by the company (or the platform).
///
/// The vote for a ride day opens at [opensAt] on the day before and closes at
/// the first [closesAt] after that: on the ride day when it is not later than
/// [opensAt] (16:00 → 06:00), otherwise the same evening (12:00 → 22:00).
/// The database applies the same rule (vote_window()).
class VoteSettings {
  /// Minutes after midnight.
  final int opensAt;
  final int closesAt;

  /// Minutes between reminders; 0 = no reminders.
  final int reminderMinutes;

  /// Ride days without reminders: weekdays (DateTime.weekday, 1 = Monday)
  /// such as Friday, and dates such as official holidays.
  final Set<int> offWeekdays;
  final Set<DateTime> offDates;

  const VoteSettings({
    required this.opensAt,
    required this.closesAt,
    this.reminderMinutes = 0,
    this.offWeekdays = const {},
    this.offDates = const {},
  });

  /// Until the server answers: the original 4 PM → 6 AM, no reminders.
  static const fallback = VoteSettings(opensAt: 16 * 60, closesAt: 6 * 60);

  factory VoteSettings.fromJson(Map<String, dynamic> json) => VoteSettings(
        opensAt: _minutes(json['opens_at']) ?? fallback.opensAt,
        closesAt: _minutes(json['closes_at']) ?? fallback.closesAt,
        reminderMinutes: (json['reminder_minutes'] as num?)?.toInt() ?? 0,
        offWeekdays: {
          for (final day in json['off_weekdays'] as List? ?? const [])
            if (day is num) day.toInt(),
        },
        offDates: {
          for (final date in json['off_dates'] as List? ?? const [])
            if (DateTime.tryParse('$date') case final parsed?)
              DateTime(parsed.year, parsed.month, parsed.day),
        },
      );

  static int? _minutes(Object? hhmm) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${hhmm ?? ''}');
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  bool get closesOnRideDay => closesAt <= opensAt;

  /// The ride day whose vote is open now, or closed most recently:
  /// tomorrow from [opensAt] on, otherwise today.
  DateTime rideDateFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return now.hour * 60 + now.minute >= opensAt
        ? DateTime(today.year, today.month, today.day + 1)
        : today;
  }

  /// When the vote for [rideDate] opens and closes.
  ({DateTime opens, DateTime closes}) windowFor(DateTime rideDate) {
    final dayBefore = DateTime(rideDate.year, rideDate.month, rideDate.day - 1);
    final closeDay = closesOnRideDay
        ? DateTime(rideDate.year, rideDate.month, rideDate.day)
        : dayBefore;
    return (opens: _at(dayBefore, opensAt), closes: _at(closeDay, closesAt));
  }

  bool isOpenAt(DateTime now) {
    final window = windowFor(rideDateFor(now));
    return !now.isBefore(window.opens) && now.isBefore(window.closes);
  }

  /// Whether the app reminds students about [rideDate] at all.
  bool remindsFor(DateTime rideDate) =>
      reminderMinutes > 0 &&
      !offWeekdays.contains(rideDate.weekday) &&
      !offDates.contains(DateTime(rideDate.year, rideDate.month, rideDate.day));

  /// The reminders for [rideDate]: as its vote opens, then every
  /// [reminderMinutes] until it closes. None on a day off.
  List<DateTime> reminderTimesFor(DateTime rideDate) {
    if (!remindsFor(rideDate)) return const [];
    final window = windowFor(rideDate);
    return [
      for (var at = window.opens;
          at.isBefore(window.closes);
          at = at.add(Duration(minutes: reminderMinutes)))
        at,
    ];
  }

  static DateTime _at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  /// "٤ م" or, with [long], "٤ مساءً"; "٦:٣٠ ص".
  static String clock(int minutes, {bool long = false}) {
    final hour = minutes ~/ 60, minute = minutes % 60;
    final digits = '${hour % 12 == 0 ? 12 : hour % 12}'
        '${minute > 0 ? ':${minute.toString().padLeft(2, '0')}' : ''}';
    final suffix = long
        ? (hour < 12 ? 'صباحاً' : (hour < 13 ? 'ظهراً' : 'مساءً'))
        : (hour < 12 ? 'ص' : 'م');
    return '${_arabicDigits(digits)} $suffix';
  }

  static String _arabicDigits(String text) => text.replaceAllMapped(
      RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m.group(0)!)]);

  String get opensLabel => clock(opensAt);
  String get closesLabel => clock(closesAt);

  /// "التصويت من ٤ مساءً في اليوم السابق حتى ٦ صباحاً يوم الرحلة."
  String get windowSentence => closesOnRideDay
      ? 'التصويت من ${clock(opensAt, long: true)} في اليوم السابق حتى ${clock(closesAt, long: true)} يوم الرحلة.'
      : 'التصويت من ${clock(opensAt, long: true)} حتى ${clock(closesAt, long: true)} في اليوم السابق للرحلة.';

  @override
  bool operator ==(Object other) =>
      other is VoteSettings &&
      other.opensAt == opensAt &&
      other.closesAt == closesAt &&
      other.reminderMinutes == reminderMinutes &&
      other.offWeekdays.length == offWeekdays.length &&
      other.offWeekdays.containsAll(offWeekdays) &&
      other.offDates.length == offDates.length &&
      other.offDates.containsAll(offDates);

  @override
  int get hashCode => Object.hash(opensAt, closesAt, reminderMinutes,
      Object.hashAllUnordered(offWeekdays), Object.hashAllUnordered(offDates));
}
