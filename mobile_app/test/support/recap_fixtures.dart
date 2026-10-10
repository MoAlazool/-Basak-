// Answers of `get_my_term_recap` for the students drawn on the recap boards
// (RecapPersonas and row 08), built day by day so the engine has real rides
// to measure. The term is the boards': 20 September 2026 – 14 January 2027,
// Friday off: 101 study days.
import 'package:basak_mobile/features/student/recap/recap_engine.dart';

final termStart = DateTime.utc(2026, 9, 20);
final termEnd = DateTime.utc(2027, 1, 14);

String iso(DateTime d) => d.toIso8601String().substring(0, 10);

/// Every study day (no Fridays, none of [holidays]) from [from] to [to].
List<DateTime> studyDays({DateTime? from, DateTime? to, Set<DateTime> holidays = const {}, Set<int>? weekdays}) => [
      for (var d = from ?? termStart; !d.isAfter(to ?? termEnd); d = d.add(const Duration(days: 1)))
        if (d.weekday != 5 && !holidays.contains(d) && (weekdays == null || weekdays.contains(d.weekday))) d,
    ];

/// Days of [days] whose place leaves one of [residues] when divided by [period].
List<DateTime> pick(List<DateTime> days, int period, Set<int> residues,
    {Set<int> extra = const {}, int dropLast = 0}) {
  final out = [
    for (var i = 0; i < days.length; i++)
      if (residues.contains(i % period) || extra.contains(i)) days[i],
  ];
  return out.sublist(0, out.length - dropLast);
}

const zarqaStations = ['موقف الزرقا', 'ميت الخولي', 'شرباص', 'كوبري السرو', 'السرو', 'الروضة', 'فارسكور'];

/// One answer. [departure] / [returning] give each ride its times by its
/// place among the rides; a null return time means "did not return by bus".
Map<String, dynamic> recapJson({
  required List<DateTime> rides,
  String Function(int i)? departure,
  String? Function(int i)? returning,
  String name = 'سارة أحمد',
  String? college = 'الهندسة',
  String? specialisation,
  String? university = 'جامعة المنصورة الجديدة',
  String line = 'الزرقا',
  List<String> stations = zarqaStations,
  String? stop = 'كوبري السرو',
  int stopsUsed = 1,
  List<String> departureTimes = const ['06:38', '07:23', '08:10'],
  List<String> returnTimes = const ['14:00', '15:30', '17:00'],
  int? tripMinutes = 56,
  int? Function(int i)? rideMinutes,
  DateTime? today,
  DateTime? from,
  DateTime? to,
  List<DateTime> holidays = const [],
  List<int> offWeekdays = const [5],
}) {
  final start = from ?? termStart, end = to ?? termEnd;
  final day = today ?? end;
  final until = day.isBefore(end) ? day : end;
  final rows = [
    for (var i = 0; i < rides.length; i++)
      {
        'date': iso(rides[i]),
        'weekday': rides[i].weekday,
        'departure_time': departure?.call(i) ?? '07:23',
        'return_time': returning == null ? '15:30' : returning(i),
        'returns_by_bus': returning == null || returning(i) != null,
        'line_id': 'line-1',
        'station_id': 'st-stop',
        'departure_minutes': rideMinutes?.call(i),
        'boarded_departure': true,
        'boarded_return': false,
      },
  ];
  return {
    'today': iso(day),
    'student': {
      'full_name': name,
      'first_name': name.split(' ').first,
      'university': university,
      'college': college,
      'specialisation': specialisation,
    },
    'term': {
      'code': 'first',
      'academic_year': 2026,
      'name': 'الفصل الأول',
      'label': 'الفصل الأول 2026/2027',
      'start_date': iso(start),
      'end_date': iso(end),
    },
    'range': {'from': iso(start), 'to': iso(end), 'until': iso(until)},
    'subscription': {'id': 'sub-1', 'type': 'termly', 'status': 'active'},
    'rides': rows,
    'summary': {'ride_days': rows.length},
    'line': {
      'id': 'line-1',
      'name': line,
      'stations': [
        for (var i = 0; i < stations.length; i++)
          {'id': stations[i] == stop ? 'st-stop' : 'st-$i', 'name': stations[i], 'order_index': i},
      ],
    },
    'stop': stop == null
        ? null
        : {'id': 'st-stop', 'name': stop, 'order_index': stations.indexOf(stop), 'rides': rows.length, 'stops_used': stopsUsed},
    'timetable': {'departure_times': departureTimes, 'return_times': returnTimes},
    'trip_length': {'departure_minutes': tripMinutes, 'return_minutes': null},
    'off': {'weekdays': offWeekdays, 'dates': [for (final d in holidays) iso(d)]},
  };
}

TermRecap? recapOf(Map<String, dynamic> json, {String key = 'student-1'}) =>
    TermRecap.build(RecapData.tryParse(json)!, studentKey: key);

/// A student key whose draw gives the [index]-th title of a bank of [count].
String keyDrawing(String pattern, int index, int count) {
  for (var i = 0;; i++) {
    if (recapDraw('student-$i|$pattern', count) == index) return 'student-$i';
  }
}

// ---------------------------------------------------------------- the nine

/// Sara · Engineering · the regular of row 08: 62 of 101, Sunday 13 and
/// Thursday 7, a run of 14, an absence of 9 in the middle, 41 rides at 7:23
/// and 3 at 6:38, 55 returns, 109 hours.
Map<String, dynamic> sara() {
  // Weeks start on Saturday; week 0 holds 20–24 September.
  const missed = <int, Set<int>>{
    6: {2, 4, 7, 8, 9, 10, 16},
    7: {6, 8, 9, 11},
    1: {3, 8, 9, 14, 16},
    2: {2, 5, 8, 11, 14, 16},
    3: {1, 4, 6, 8, 10, 15, 16},
    4: {0, 1, 3, 5, 6, 8, 10, 11, 15, 16},
  };
  final firstSaturday = DateTime.utc(2026, 9, 19);
  final rides = [
    for (final d in studyDays())
      if (!missed[d.weekday]!.contains(d.difference(firstSaturday).inDays ~/ 7)) d,
  ];
  return recapJson(
    rides: rides,
    departure: (i) => i < 3 ? '06:38' : i < 44 ? '07:23' : '08:10',
    returning: (i) => i < 7 ? null : i < 47 ? '15:30' : '14:00',
  );
}

/// Yousef · Medicine · 71 of 96, 58 on the first trip 6:15.
Map<String, dynamic> yousef() => recapJson(
      name: 'يوسف طارق',
      college: 'الطب',
      rides: pick(studyDays(from: DateTime.utc(2026, 9, 26)), 4, {0, 1, 2}, dropLast: 1),
      departure: (i) => i < 58 ? '06:15' : '07:00',
      returning: (i) => '15:00',
      departureTimes: const ['06:15', '07:00', '07:45'],
      returnTimes: const ['14:00', '15:00', '16:30'],
      tripMinutes: 41,
    );

/// Nada · Computer science · 52 of 98, 38 returns on the last bus 5:30.
Map<String, dynamic> nada() => recapJson(
      name: 'ندى إبراهيم',
      college: 'الحاسبات والمعلومات',
      line: 'دمياط الجديدة',
      rides: pick(studyDays(from: DateTime.utc(2026, 9, 23)), 7, {0, 2, 3, 5}, dropLast: 4),
      departure: (i) => '07:45',
      returning: (i) => i < 38 ? '17:30' : i < 45 ? '15:00' : null,
      departureTimes: const ['07:00', '07:45', '08:30'],
      returnTimes: const ['14:00', '15:00', '17:30'],
      tripMinutes: 50,
    );

/// Karim · Accounting · 44 of 99, back by bus 6 times.
Map<String, dynamic> karim() => recapJson(
      name: 'كريم محمد',
      college: 'التجارة',
      specialisation: 'محاسبة',
      rides: pick(studyDays(from: DateTime.utc(2026, 9, 22)), 5, {0, 2}, extra: {1, 26, 51, 76}),
      departure: (i) => '08:10',
      returning: (i) => i < 6 ? '15:30' : null,
    );

/// Menna · English · 39 of 97, five different times.
Map<String, dynamic> menna() => recapJson(
      name: 'منة الله عادل',
      college: 'الآداب',
      specialisation: 'لغة إنجليزية',
      line: 'السنبلاوين',
      rides: pick(studyDays(from: DateTime.utc(2026, 9, 24)), 5, {0, 2}),
      departure: (i) => const ['07:00', '07:30', '08:00', '08:30', '09:00'][i % 5],
      returning: (i) => '15:00',
      departureTimes: const ['07:00', '07:30', '08:00', '08:30', '09:00'],
      returnTimes: const ['14:00', '15:00', '16:30'],
    );

/// Omar · Law · 6 rides: the short recap.
Map<String, dynamic> omar() => recapJson(
      name: 'عمر خالد',
      college: 'الحقوق',
      rides: [
        DateTime.utc(2026, 9, 27),
        DateTime.utc(2026, 10, 11),
        DateTime.utc(2026, 10, 14),
        DateTime.utc(2026, 11, 8),
        DateTime.utc(2026, 11, 24),
        DateTime.utc(2026, 12, 19),
      ],
    );

/// Mariam · Pharmacy · Sunday, Tuesday, Thursday: 41 of 45 (six of her days
/// were official holidays).
Map<String, dynamic> mariam() {
  final holidays = [
    DateTime.utc(2026, 10, 4), DateTime.utc(2026, 10, 6), DateTime.utc(2026, 10, 8),
    DateTime.utc(2027, 1, 3), DateTime.utc(2027, 1, 5), DateTime.utc(2027, 1, 7),
  ];
  final hers = studyDays(holidays: holidays.toSet(), weekdays: {7, 2, 4});
  List<DateTime> on(int weekday) => hers.where((d) => d.weekday == weekday).toList();
  final missed = {on(7)[3], on(4)[6], on(2)[9], on(4)[12]}; // a Sunday, a Tuesday, two Thursdays
  return recapJson(
    name: 'مريم حسن',
    college: 'الصيدلة',
    rides: [for (final d in hers) if (!missed.contains(d)) d],
    holidays: holidays,
  );
}

/// Ahmed · Physics · first ride in November: 31 of 36.
Map<String, dynamic> ahmed() {
  final today = DateTime.utc(2026, 12, 12);
  final days = studyDays(from: DateTime.utc(2026, 11, 1), to: today);
  const missed = {6, 13, 20, 27, 33};
  return recapJson(
    name: 'أحمد سامي',
    college: 'العلوم',
    specialisation: 'فيزياء',
    today: today,
    rides: [for (var i = 0; i < days.length; i++) if (!missed.contains(i)) days[i]],
    departure: (i) => i % 4 == 0 ? '07:00' : '07:45',
    departureTimes: const ['07:00', '07:45', '08:30'],
  );
}

/// Hadeer · Education · 49 of 94, 47 at 7:45.
Map<String, dynamic> hadeer() => recapJson(
      name: 'هدير محمود',
      college: 'التربية',
      line: 'خط دمياط الجديدة',
      rides: pick(studyDays(from: DateTime.utc(2026, 9, 28)), 7, {0, 2, 4, 5}, dropLast: 5),
      departure: (i) => i == 10 || i == 30 ? '07:00' : '07:45',
      returning: (i) => '15:00',
      departureTimes: const ['07:00', '07:45', '08:30'],
      returnTimes: const ['14:00', '15:00', '16:30'],
      tripMinutes: 50,
    );
