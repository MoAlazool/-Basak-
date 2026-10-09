/// The term recap, worked out from what `get_my_term_recap` returns.
///
/// Pure Dart: no Flutter, no network. [RecapData] reads the answer,
/// [TermRecap.build] measures the term against the student's own week and
/// decides the tier, the title, the pages and every sentence on them. All the
/// words come from `recap_copy.dart`; all the thresholds are in [RecapRules].
library;

import 'recap_copy.dart';

/// Every threshold the recap is built on, in one place.
abstract final class RecapRules {
  /// The banner on Home: from this long before the term ends…
  static const bannerOpensBefore = Duration(days: 14);

  /// …until this long after it.
  static const bannerStaysAfter = Duration(days: 28);

  /// 1 to this many rides: the short recap.
  static const shortRecapRides = 7;

  /// A weekday is theirs when ridden in at least a third of its weeks…
  static const ownWeekdayShare = 1 / 3;

  /// …and their week replaces the calendar's only when it holds at least
  /// this share of their rides.
  static const ownWeekHoldsRides = 2 / 3;

  /// Share of their own days: below → light rider, from [regularShare] → regular.
  static const lightShare = .30;
  static const regularShare = .60;

  /// «عمدة» needs a week of this many days.
  static const regularWeekDays = 4;

  /// A week this short, ridden this much, is «جدول على المقاس».
  static const shortWeekDays = 3;
  static const shortWeekShare = .80;

  /// Page rules.
  static const hoursPageFrom = 3;
  static const runPageFrom = 4;
  static const gapChipFrom = 5;
  static const timePageFromRides = 5;

  /// The weakest own day is joked about when at most this much of the best.
  static const weakestDayRatio = .60;

  /// The cover says "one time" when a time holds this share of the rides.
  static const coverSameTimeShare = .60;

  /// An earlier time is "a few times" when at most a quarter of the favourite.
  static const earlyTimeRatio = .25;

  /// Return page: below → rarely.
  static const rarelyReturnsShare = .25;

  /// Title patterns.
  static const firstTripShare = .60;
  static const lastTripShare = .60;
  static const sameTimeShare = .85;
  static const manyTimesCount = 4;
  static const manyTimesTopShare = .40;
  static const tripHomeShare = .50;
  static const tripHomeMinReturns = 5;
  static const longRunDays = 20;
  static const longRunShare = .95;
  static const topWeekdayRatio = 1.5;
  static const thursdayRatio = .50;
  static const manyHours = 144;
  static const midTermAfter = Duration(days: 28);

  /// The stop page draws at most this many stops on each side of theirs.
  static const stopsEachSide = 3;

  /// The engineering box: one lecture.
  static const lectureHours = 3;

  /// The week's days in the order they are drawn: Saturday first.
  static const weekOrder = [6, 7, 1, 2, 3, 4, 5];
}

/// Whether Home may show the recap's banner on [today] for a term ending [termEnd].
bool recapWindowOpen(DateTime today, DateTime? termEnd) {
  if (termEnd == null) return false;
  final day = DateTime.utc(today.year, today.month, today.day);
  final end = DateTime.utc(termEnd.year, termEnd.month, termEnd.day);
  return !day.isBefore(end.subtract(RecapRules.bannerOpensBefore)) &&
      !day.isAfter(end.add(RecapRules.bannerStaysAfter));
}

DateTime? _date(Object? value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${value ?? ''}');
  if (match == null) return null;
  return DateTime.utc(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
}

String? _text(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

String? _time(Object? value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${value ?? ''}');
  if (match == null) return null;
  return '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}');

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : const {};

/// One confirmed ride day.
class RecapRide {
  final DateTime date;

  /// "HH:MM", when a time was chosen.
  final String? departure;
  final String? returnTime;
  final bool returns;

  /// Stop to arrival on the way there, when the timetable still has that trip.
  final int? minutes;

  const RecapRide({required this.date, this.departure, this.returnTime, this.returns = false, this.minutes});

  int get weekday => date.weekday;
}

/// The RPC's answer, read defensively: anything missing is simply unknown.
class RecapData {
  final DateTime today;
  final String? firstName;
  final String? university;
  final String? college;
  final String? specialisation;
  final String? termName;
  final int? academicYear;
  final DateTime from;
  final DateTime to;
  final DateTime until;
  final DateTime? termEnd;
  final String? subscriptionId;
  final List<RecapRide> rides;
  final String? lineName;

  /// The line's stops, in order.
  final List<String> stations;
  final String? stopName;

  /// The stop's place in [stations] (0-based), when it is among them.
  final int? stopIndex;
  final int stopRides;
  final int stopsUsed;
  final List<String> departureTimes;
  final List<String> returnTimes;
  final int? typicalMinutes;
  final Set<int> offWeekdays;
  final Set<DateTime> offDates;

  const RecapData({
    required this.today,
    required this.from,
    required this.to,
    required this.until,
    required this.rides,
    this.termEnd,
    this.firstName,
    this.university,
    this.college,
    this.specialisation,
    this.termName,
    this.academicYear,
    this.subscriptionId,
    this.lineName,
    this.stations = const [],
    this.stopName,
    this.stopIndex,
    this.stopRides = 0,
    this.stopsUsed = 0,
    this.departureTimes = const [],
    this.returnTimes = const [],
    this.typicalMinutes,
    this.offWeekdays = const {5},
    this.offDates = const {},
  });

  /// Null when [json] is not an answer of `get_my_term_recap`.
  static RecapData? tryParse(Object? json) {
    if (json is! Map) return null;
    final root = _map(json);
    if (root['rides'] is! List) return null;

    final rides = <DateTime, RecapRide>{};
    for (final row in root['rides'] as List) {
      final r = _map(row);
      final date = _date(r['date']);
      if (date == null) continue;
      final returns = r['returns_by_bus'] == true;
      rides[date] = RecapRide(
        date: date,
        departure: _time(r['departure_time']),
        returnTime: returns ? _time(r['return_time']) : null,
        returns: returns,
        minutes: (_int(r['departure_minutes']) ?? 0) > 0 ? _int(r['departure_minutes']) : null,
      );
    }
    final list = rides.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    final student = _map(root['student']);
    final term = _map(root['term']);
    final range = _map(root['range']);
    final line = _map(root['line']);
    final stop = _map(root['stop']);
    final timetable = _map(root['timetable']);
    final off = _map(root['off']);

    final today = _date(root['today']) ??
        (list.isEmpty ? DateTime.utc(1970) : list.last.date);
    final from = _date(range['from']) ?? _date(term['start_date']) ?? (list.isEmpty ? today : list.first.date);
    final to = _date(range['to']) ?? _date(term['end_date']) ?? today;
    var until = _date(range['until']) ?? (to.isBefore(today) ? to : today);
    if (until.isBefore(from)) until = from;

    final stations = <({String? id, String name})>[
      for (final s in line['stations'] as List? ?? const [])
        if (_text(_map(s)['name']) != null) (id: _map(s)['id']?.toString(), name: _text(_map(s)['name'])!),
    ];
    final stopName = _text(stop['name']);
    final stopId = stop['id']?.toString();
    var stopIndex = stopId == null ? -1 : stations.indexWhere((s) => s.id == stopId);
    if (stopIndex < 0 && stopName != null) stopIndex = stations.indexWhere((s) => s.name == stopName);

    List<String> times(Object? value) =>
        ({for (final t in value as List? ?? const []) if (_time(t) != null) _time(t)!}.toList())..sort();

    final fullName = _text(student['full_name']);
    final typical = _int(_map(root['trip_length'])['departure_minutes']);
    return RecapData(
      today: today,
      from: from,
      to: to.isBefore(from) ? from : to,
      until: until,
      termEnd: _date(term['end_date']),
      rides: list,
      firstName: _text(student['first_name']) ?? fullName?.split(RegExp(r'\s+')).first,
      university: _text(student['university']),
      college: _text(student['college']),
      specialisation: _text(student['specialisation']),
      termName: _text(term['name']) ?? _text(term['label']),
      academicYear: _int(term['academic_year']),
      subscriptionId: _text(_map(root['subscription'])['id']),
      lineName: _text(line['name']),
      stations: [for (final s in stations) s.name],
      stopName: stopName,
      stopIndex: stopIndex < 0 ? null : stopIndex,
      stopRides: _int(stop['rides']) ?? 0,
      stopsUsed: _int(stop['stops_used']) ?? 0,
      departureTimes: times(timetable['departure_times']),
      returnTimes: times(timetable['return_times']),
      typicalMinutes: (typical ?? 0) > 0 ? typical : null,
      offWeekdays: {
        for (final w in off['weekdays'] as List? ?? const [])
          if ((_int(w) ?? 0) >= 1 && (_int(w) ?? 0) <= 7) _int(w)!,
      },
      offDates: {
        for (final d in off['dates'] as List? ?? const [])
          if (_date(d) != null) _date(d)!,
      },
    );
  }
}

/// How much they rode, on their own days.
enum RecapTier { none, short, light, standard, regular }

enum RecapPageKind { cover, hours, days, shape, run, time, back, stop, college, title, share, short }

/// One bar of the days page.
class RecapBar {
  final int weekday;
  final String letter;
  final int count;

  /// One of their own days; the others are drawn as an empty slot.
  final bool own;

  /// Drawn solid.
  final bool strong;

  /// 0 to 1, against the tallest bar.
  final double height;

  const RecapBar({
    required this.weekday,
    required this.letter,
    required this.count,
    required this.own,
    required this.strong,
    required this.height,
  });
}

/// A cell of the term's grid: no dot, a day not ridden, a ride.
enum RecapCell { none, off, on }

/// One week of the term: a cell per study weekday.
class RecapWeek {
  final DateTime start;

  /// Said beside the first week of each month.
  final String? month;
  final List<RecapCell> cells;

  const RecapWeek({required this.start, required this.cells, this.month});
}

/// One number on the poster.
class RecapStat {
  final String value;
  final String label;

  /// A time or a percentage: drawn left to right.
  final bool ltr;

  const RecapStat(this.value, this.label, {this.ltr = false});
}

/// One page of the story, ready to draw: every string is final.
class RecapPage {
  final RecapPageKind kind;
  final String kicker;

  /// The big number ("109", "7:23") and what follows it on its line ("ص").
  final String? numeral;
  final String? numeralSuffix;

  /// Under the number ("ساعة في الباص").
  final String? unit;

  /// A headline in place of a number ("يا هندسة", the title).
  final String? headline;

  /// The sentences, the main one first.
  final List<String> lines;
  final String? chip;
  final String? footnote;

  /// The link at the foot of the cover and the title page.
  final String? cta;
  final String? boxTitle;
  final String? boxBody;

  const RecapPage({
    required this.kind,
    this.kicker = '',
    this.numeral,
    this.numeralSuffix,
    this.unit,
    this.headline,
    this.lines = const [],
    this.chip,
    this.footnote,
    this.cta,
    this.boxTitle,
    this.boxBody,
  });
}

/// A clock time split as it is drawn: "7:23" and "ص".
class RecapClock {
  final String digits;
  final String suffix;

  const RecapClock(this.digits, this.suffix);

  factory RecapClock.of(String hhmm) {
    final parts = hhmm.split(':');
    final raw = int.tryParse(parts.first) ?? 0;
    final hour = raw % 12 == 0 ? 12 : raw % 12;
    return RecapClock('$hour:${parts.length > 1 ? parts[1] : '00'}', raw < 12 ? RecapCopy.am : RecapCopy.pm);
  }

  String get full => '$digits $suffix';
}

/// A count with its noun: "يوم واحد", "يومين", "8 أيام", "62 يوم".
String recapCount(int n, String noun) {
  final forms = RecapCopy.nouns[noun];
  if (forms == null) return '$n $noun';
  if (n == 1) return forms.one;
  if (n == 2) return forms.two;
  if (n >= 3 && n <= 10) return '$n ${forms.few}';
  return '$n ${forms.many}';
}

final _placeholder = RegExp(r'\{([^{}]+)\}');
final _nounAfter = RegExp('^ (${RecapCopy.nouns.keys.join('|')})(?![\\u0621-\\u064A])');

/// Fills [template] from [vars]. A whole number followed by a noun the copy
/// knows takes that noun's form. Null when the sentence is empty or names
/// something that is not known: it is then left out.
String? recapFill(String template, Map<String, Object?> vars) {
  if (template.trim().isEmpty) return null;
  final out = StringBuffer();
  var at = 0;
  for (final match in _placeholder.allMatches(template)) {
    if (match.start < at) continue;
    out.write(template.substring(at, match.start));
    at = match.end;
    final value = vars[match.group(1)];
    if (value == null) return null;
    if (value is int) {
      final noun = _nounAfter.firstMatch(template.substring(at));
      if (noun != null) {
        out.write(recapCount(value, noun.group(1)!));
        at += noun.end;
        continue;
      }
    }
    out.write(value);
  }
  out.write(template.substring(at));
  return out.toString();
}

/// A fixed draw: the same [key] always gives the same number.
int recapDraw(String key, int count) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return count <= 0 ? 0 : hash % count;
}

final _notLetters = RegExp(r'[^a-z\u0621-\u064A]+');

/// ال، وال، بال، لل — when at least two letters are left.
final _article = RegExp(r'^(\u0648\u0627\u0644|\u0628\u0627\u0644|\u0644\u0644|\u0627\u0644)(?=.{2,})');

String _normal(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');

List<String> _words(String text) =>
    [for (final raw in _normal(text).split(_notLetters)) if (raw.isNotEmpty) raw];

/// A word as written and without its article ("والمعلومات" → "معلومات").
Iterable<String> _forms(String word) sync* {
  yield word;
  var bare = word;
  for (var i = 0; i < 2; i++) {
    final next = bare.replaceFirst(_article, '');
    if (next == bare) break;
    yield bare = next;
  }
}

/// The family whose keywords are whole words of the specialisation, else of
/// the college. Null: no line of its own.
RecapFamily? recapFamilyFor({String? college, String? specialisation}) {
  for (final source in [specialisation, college]) {
    if (source == null || source.trim().isEmpty) continue;
    final words = {for (final word in _words(source)) ..._forms(word)};
    for (final family in RecapCopy.families) {
      for (final keyword in family.keywords) {
        final needed = _words(keyword);
        if (needed.isNotEmpty && needed.every(words.contains)) return family;
      }
    }
  }
  return null;
}

/// «خط الزرقا», whether the line is stored with its «خط» or without.
String? recapLineTitle(String? name) {
  final line = (name ?? '').trim();
  if (line.isEmpty) return null;
  return line.startsWith(RecapCopy.linePrefix) ? line : '${RecapCopy.linePrefix}$line';
}

/// The recap of one student's term.
class TermRecap {
  final RecapData data;
  final RecapTier tier;

  /// Confirmed ride days.
  final int rideDays;

  /// The study weekdays (Saturday first) and which of them are theirs.
  final List<int> studyWeekdays;
  final Set<int> ownWeekdays;

  /// Their week is shorter than the calendar's.
  final bool ownWeek;

  /// Their own days since the first ride, how many they rode, and the rides
  /// on other days.
  final int ownTotal;
  final int ownRidden;
  final int extraRides;
  final Map<int, int> weekdayCounts;
  final int? bestWeekday;
  final int? weakestWeekday;
  final int longestRun;
  final int longestGap;
  final bool gapInTheMiddle;
  final String? favouriteTime;
  final int favouriteTimeRides;
  final int distinctTimes;
  final int returnDays;
  final String? favouriteReturn;

  /// Approximate hours on the bus; null when no trip length is known.
  final int? hours;
  final RecapPattern pattern;

  /// May hold a line break ("عمدة\nكوبري السرو").
  final String title;
  final String titleWhy;
  final RecapFamily? family;

  /// The specialisation's line, when there is one that can be said.
  final String? line;

  /// 0 to 4: the poster's colours.
  final int theme;
  final List<RecapBar> bars;
  final List<RecapWeek> weeks;
  final List<RecapStat> stats;
  final List<RecapPage> pages;

  /// The stop page: the stops drawn before and after theirs.
  final List<String> stopsBefore;
  final List<String> stopsAfter;

  const TermRecap._({
    required this.data,
    required this.tier,
    required this.rideDays,
    required this.studyWeekdays,
    required this.ownWeekdays,
    required this.ownWeek,
    required this.ownTotal,
    required this.ownRidden,
    required this.extraRides,
    required this.weekdayCounts,
    required this.bestWeekday,
    required this.weakestWeekday,
    required this.longestRun,
    required this.longestGap,
    required this.gapInTheMiddle,
    required this.favouriteTime,
    required this.favouriteTimeRides,
    required this.distinctTimes,
    required this.returnDays,
    required this.favouriteReturn,
    required this.hours,
    required this.pattern,
    required this.title,
    required this.titleWhy,
    required this.family,
    required this.line,
    required this.theme,
    required this.bars,
    required this.weeks,
    required this.stats,
    required this.pages,
    required this.stopsBefore,
    required this.stopsAfter,
  });

  /// Share of their own days ridden, 0 to 1.
  double get attendance => ownTotal == 0 ? 0 : (ownRidden / ownTotal).clamp(0, 1).toDouble();

  /// 91 for 41 of 45.
  int get attendancePercent => (attendance * 100).round();

  bool get isShort => tier == RecapTier.short;

  /// "الفصل الأول".
  String? get termName => data.termName;

  /// "2026 / 2027" on the cover, "2026/27" on the poster.
  String? get yearsLong => data.academicYear == null ? null : '${data.academicYear} / ${data.academicYear! + 1}';
  String? get yearsShort => data.academicYear == null
      ? null
      : '${data.academicYear}/${((data.academicYear! + 1) % 100).toString().padLeft(2, '0')}';

  /// «خط الزرقا».
  String? get lineTitle => recapLineTitle(data.lineName);

  /// The poster's foot: "سارة · خط الزرقا".
  String get signature =>
      [data.firstName, lineTitle].whereType<String>().join(RecapCopy.posterSeparator);

  /// "62 يوم من 101".
  String get patternCount => recapFill(
        isShort ? RecapCopy.posterPatternCountShort : RecapCopy.posterPatternCount,
        {'ي': isShort ? rideDays : ownRidden, 'من': ownTotal},
      )!;

  /// Under «ملخّص ترمك جاهز» on Home.
  String get bannerLine =>
      recapFill(RecapCopy.bannerHours, {'س': (hours ?? 0) >= RecapRules.hoursPageFrom ? hours : null}) ??
      recapFill(RecapCopy.bannerDays, {'ي': rideDays})!;

  /// Whether Home shows the banner on [today] (the server's day by default).
  bool bannerOpen([DateTime? today]) => recapWindowOpen(today ?? data.today, data.termEnd ?? data.to);

  /// Null with no rides at all: no recap, and no banner.
  /// [studentKey] fixes the draw of the title and of the poster's colours.
  static TermRecap? build(RecapData data, {required String studentKey}) {
    final rides = data.rides;
    if (rides.isEmpty) return null;
    final rideDays = rides.length;
    final ridden = {for (final r in rides) r.date};
    final first = rides.first.date, last = rides.last.date;
    final until = data.until.isBefore(last) ? last : data.until;

    // ---- the week
    var study = [for (final w in RecapRules.weekOrder) if (!data.offWeekdays.contains(w)) w];
    if (study.isEmpty) study = RecapRules.weekOrder;
    bool studyDay(DateTime d) =>
        study.contains(d.weekday) && (!data.offDates.contains(d) || ridden.contains(d));
    Iterable<DateTime> days(DateTime a, DateTime b) sync* {
      for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) {
        yield d;
      }
    }

    final counts = {for (final w in study) w: 0};
    for (final r in rides) {
      if (counts.containsKey(r.weekday)) counts[r.weekday] = counts[r.weekday]! + 1;
    }
    final occurrences = {for (final w in study) w: 0};
    for (final d in days(first, until)) {
      if (studyDay(d)) occurrences[d.weekday] = occurrences[d.weekday]! + 1;
    }
    var own = {
      for (final w in study)
        if (counts[w]! > 0 && counts[w]! >= occurrences[w]! * RecapRules.ownWeekdayShare) w,
    };
    final onOwn = own.fold<int>(0, (sum, w) => sum + counts[w]!);
    if (own.isEmpty || onOwn < rideDays * RecapRules.ownWeekHoldsRides) own = study.toSet();
    final ownWeek = own.length < study.length;
    bool ownDay(DateTime d) => own.contains(d.weekday) && studyDay(d);

    final ownTotal = days(first, until).where(ownDay).length;
    final ownRidden = rides.where((r) => ownDay(r.date)).length;
    final extra = rideDays - ownRidden;
    final share = ownTotal == 0 ? 0.0 : ownRidden / ownTotal;

    final tier = rideDays <= RecapRules.shortRecapRides
        ? RecapTier.short
        : share < RecapRules.lightShare
            ? RecapTier.light
            : share < RecapRules.regularShare
                ? RecapTier.standard
                : RecapTier.regular;

    // ---- weekdays: the earlier one wins a tie
    final ownOrdered = [for (final w in study) if (own.contains(w)) w];
    int? best, weakest;
    for (final w in ownOrdered) {
      if (best == null || counts[w]! > counts[best]!) best = w;
      if (weakest == null || counts[w]! < counts[weakest]!) weakest = w;
    }
    // A light rider's days are too few to tease one of them.
    if (tier == RecapTier.light ||
        weakest == best ||
        best == null ||
        weakest == null ||
        counts[weakest]! > counts[best]! * RecapRules.weakestDayRatio) {
      weakest = null;
    }

    // ---- runs and gaps, in their own days, between the first and last ride
    var run = 0, gap = 0, longestRun = 0, longestGap = 0;
    DateTime? gapStart, longestGapStart, longestGapEnd;
    for (final d in days(first, last)) {
      if (!ownDay(d)) continue;
      if (ridden.contains(d)) {
        run++;
        gap = 0;
        if (run > longestRun) longestRun = run;
      } else {
        if (gap == 0) gapStart = d;
        gap++;
        run = 0;
        if (gap > longestGap) {
          longestGap = gap;
          longestGapStart = gapStart;
          longestGapEnd = d;
        }
      }
    }
    var gapInTheMiddle = false;
    if (longestGap >= RecapRules.gapChipFrom && longestGapStart != null && longestGapEnd != null) {
      final span = data.to.difference(data.from).inDays;
      if (span > 0) {
        final middle = longestGapStart.difference(data.from).inDays +
            longestGapEnd.difference(longestGapStart).inDays / 2;
        gapInTheMiddle = middle / span >= .25 && middle / span <= .75;
      }
    }

    // ---- times: the earlier one wins a tie
    Map<String, int> tally(Iterable<String?> values) {
      final out = <String, int>{};
      for (final v in values) {
        if (v != null) out[v] = (out[v] ?? 0) + 1;
      }
      return out;
    }

    String? top(Map<String, int> tallied) {
      String? winner;
      for (final t in tallied.keys.toList()..sort()) {
        if (winner == null || tallied[t]! > tallied[winner]!) winner = t;
      }
      return winner;
    }

    final going = tally(rides.map((r) => r.departure));
    final timed = going.values.fold<int>(0, (a, b) => a + b);
    final favourite = top(going);
    final favouriteRides = favourite == null ? 0 : going[favourite]!;
    final returnDays = rides.where((r) => r.returns).length;
    final coming = tally(rides.where((r) => r.returns).map((r) => r.returnTime));
    final favouriteReturn = top(coming);

    // ---- hours: the way back mirrors the way there
    var minutes = 0;
    for (final r in rides) {
      final leg = r.minutes ?? data.typicalMinutes;
      if (leg != null) minutes += leg * (r.returns ? 2 : 1);
    }
    final hours = minutes == 0 ? null : (minutes / 60).round();
    final hoursShown = (hours ?? 0) >= RecapRules.hoursPageFrom ? hours : null;

    // ---- the specialisation
    final family = recapFamilyFor(college: data.college, specialisation: data.specialisation);
    final lineTitle = recapLineTitle(data.lineName);
    final base = <String, Object?>{
      'ي': rideDays,
      'س': hoursShown,
      'من': ownTotal,
      'المحطة': data.stopName,
      'الخط': lineTitle,
      'الجامعة': data.university,
      'اليوم': best == null ? null : RecapCopy.weekdayNames[best],
      'الترم': data.termName,
    };
    final line = family != null
        ? recapFill(family.line, base)
        : data.college == null
            ? recapFill(RecapCopy.noCollegeLine, base)
            : null;

    // ---- the title
    final firstGoing = data.departureTimes.length >= 2 ? data.departureTimes.first : null;
    final lastGoing = data.departureTimes.length >= 2 ? data.departureTimes.last : null;
    final firstHome = data.returnTimes.length >= 2 ? data.returnTimes.first : null;
    final lastHome = data.returnTimes.length >= 2 ? data.returnTimes.last : null;
    int at(Map<String, int> tallied, String? time) => time == null ? 0 : tallied[time] ?? 0;
    final others = [for (final w in study) if (w != 4 && own.contains(w)) counts[w]!];
    final ranked = [for (final w in ownOrdered) counts[w]!]..sort((a, b) => b.compareTo(a));

    bool fits(RecapPattern p) => switch (p) {
          RecapPattern.guest => rideDays <= RecapRules.shortRecapRides,
          RecapPattern.midTerm => !first.isBefore(data.from.add(RecapRules.midTermAfter)),
          RecapPattern.longRun => longestRun >= RecapRules.longRunDays ||
              (share >= RecapRules.longRunShare && ownTotal > RecapRules.shortRecapRides),
          RecapPattern.manyHours => (hours ?? 0) >= RecapRules.manyHours,
          RecapPattern.shortWeek =>
            ownWeek && own.length <= RecapRules.shortWeekDays && share >= RecapRules.shortWeekShare,
          RecapPattern.thursdayOff => study.contains(4) &&
              others.length >= 3 &&
              counts[4]! <= RecapRules.thursdayRatio * others.reduce((a, b) => a + b) / others.length,
          RecapPattern.topWeekday =>
            ranked.length >= 3 && ranked[1] > 0 && ranked[0] >= ranked[1] * RecapRules.topWeekdayRatio,
          RecapPattern.rarelyReturns => returnDays < rideDays * RecapRules.rarelyReturnsShare,
          RecapPattern.firstTripGoing => timed > 0 && at(going, firstGoing) >= timed * RecapRules.firstTripShare,
          RecapPattern.lastTripGoing => timed > 0 && at(going, lastGoing) >= timed * RecapRules.lastTripShare,
          RecapPattern.lastTripHome => returnDays >= RecapRules.tripHomeMinReturns &&
              at(coming, lastHome) >= returnDays * RecapRules.tripHomeShare,
          RecapPattern.firstTripHome => returnDays >= RecapRules.tripHomeMinReturns &&
              at(coming, firstHome) >= returnDays * RecapRules.tripHomeShare,
          RecapPattern.manyTimes => going.length >= RecapRules.manyTimesCount &&
              favouriteRides <= timed * RecapRules.manyTimesTopShare,
          RecapPattern.sameTime => timed > RecapRules.shortRecapRides &&
              data.departureTimes.length != 1 &&
              favouriteRides >= timed * RecapRules.sameTimeShare,
          RecapPattern.regular => share >= RecapRules.regularShare && own.length >= RecapRules.regularWeekDays,
          RecapPattern.fallback => true,
        };
    final pattern = RecapPattern.values.firstWhere(fits);

    final ownNames = [for (final w in ownOrdered) RecapCopy.weekdayNames[w]!];
    final why = <String, Object?>{
      ...base,
      'ي': rideDays,
      'الأيام': ownNames.join(RecapCopy.and),
      'الشهر': RecapCopy.months[first.month - 1],
      ...switch (pattern) {
        RecapPattern.firstTripGoing => {
            'ن': at(going, firstGoing),
            'الوقت': firstGoing == null ? null : RecapClock.of(firstGoing).digits,
          },
        RecapPattern.lastTripGoing => {
            'ن': at(going, lastGoing),
            'الوقت': lastGoing == null ? null : RecapClock.of(lastGoing).digits,
          },
        RecapPattern.sameTime => {
            'ن': favouriteRides,
            'الوقت': favourite == null ? null : RecapClock.of(favourite).digits,
          },
        RecapPattern.manyTimes => {'ن': going.length},
        RecapPattern.lastTripHome => {
            'ن': at(coming, lastHome),
            'الوقت': lastHome == null ? null : RecapClock.of(lastHome).digits,
          },
        RecapPattern.firstTripHome => {
            'ن': at(coming, firstHome),
            'الوقت': firstHome == null ? null : RecapClock.of(firstHome).digits,
          },
        RecapPattern.rarelyReturns => {'ن': returnDays == 0 ? null : returnDays},
        RecapPattern.regular || RecapPattern.midTerm || RecapPattern.shortWeek => {'ي': ownRidden},
        _ => const <String, Object?>{},
      },
    };
    final bank = RecapCopy.titles[pattern] ?? RecapCopy.titles[RecapPattern.fallback]!;
    var title = '';
    final drawn = recapDraw('$studentKey|${pattern.name}', bank.titles.length);
    for (var i = 0; i < bank.titles.length && title.isEmpty; i++) {
      // A title that names something unknown passes its turn to the next.
      title = recapFill(bank.titles[(drawn + i) % bank.titles.length], why) ?? '';
    }
    final plain = recapFill(RecapCopy.titleWhyPlain, {...base, 'ي': ownRidden})!;
    final posterWhy = recapFill(bank.posterWhy, why) ?? plain;
    final pageWhy = recapFill(bank.pageWhy, why) ?? posterWhy;

    // ---- the days page's bars
    final tallest = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final allStrong = own.length <= RecapRules.shortWeekDays && ownWeek;
    final bars = [
      for (final w in study)
        RecapBar(
          weekday: w,
          letter: RecapCopy.weekdayLetters[w]!,
          count: counts[w]!,
          own: own.contains(w),
          strong: own.contains(w) && (allStrong || w == best),
          height: tallest == 0 ? 0 : counts[w]! / tallest,
        ),
    ];

    // ---- the term, week by week
    DateTime weekStart(DateTime d) => d.subtract(Duration(days: (d.weekday - RecapRules.weekOrder.first) % 7));
    final weeks = <RecapWeek>[];
    int? month;
    for (var start = weekStart(data.from); !start.isAfter(data.to); start = start.add(const Duration(days: 7))) {
      final cells = <RecapCell>[];
      DateTime? firstInTerm;
      for (final w in study) {
        final d = start.add(Duration(days: (w - RecapRules.weekOrder.first) % 7));
        final inTerm = !d.isBefore(data.from) && !d.isAfter(data.to);
        if (inTerm) firstInTerm ??= d;
        cells.add(ridden.contains(d)
            ? RecapCell.on
            : inTerm && studyDay(d) && own.contains(w)
                ? RecapCell.off
                : RecapCell.none);
      }
      final label = firstInTerm != null && firstInTerm.month != month ? RecapCopy.months[firstInTerm.month - 1] : null;
      if (firstInTerm != null) month = firstInTerm.month;
      weeks.add(RecapWeek(start: start, cells: cells, month: label));
    }

    // ---- the poster's numbers
    final clock = favourite == null ? null : RecapClock.of(favourite);
    final returnClock = favouriteReturn == null ? null : RecapClock.of(favouriteReturn);
    final short = tier == RecapTier.short;
    final stats = <RecapStat>[
      if (short) ...[
        RecapStat(recapCount(rideDays, 'مرة'), RecapCopy.statRides),
        if (best != null) RecapStat(RecapCopy.weekdayNames[best]!, RecapCopy.statBestDay),
      ] else if (pattern == RecapPattern.shortWeek) ...[
        RecapStat('$rideDays', RecapCopy.statDays),
        RecapStat(recapCount(own.length, 'يوم'), RecapCopy.statWeek),
        RecapStat('${(share.clamp(0, 1) * 100).round()}%', RecapCopy.statShare, ltr: true),
      ] else ...[
        if (hoursShown != null) RecapStat('$hoursShown', RecapCopy.statHours),
        RecapStat('$rideDays', RecapCopy.statDays),
        if (pattern == RecapPattern.rarelyReturns && returnDays > 0)
          RecapStat(recapCount(returnDays, 'مرة'), RecapCopy.statReturns)
        else if ((pattern == RecapPattern.lastTripHome || pattern == RecapPattern.firstTripHome) &&
            returnClock != null)
          RecapStat(returnClock.full, RecapCopy.statReturnTime)
        else if (pattern == RecapPattern.manyTimes)
          RecapStat('${going.length}', RecapCopy.statTimes)
        else if (clock != null)
          RecapStat(clock.full, RecapCopy.statTime),
      ],
    ];

    // ---- the stop page
    final index = data.stopIndex;
    final before = index == null
        ? const <String>[]
        : data.stations.sublist((index - RecapRules.stopsEachSide).clamp(0, index), index);
    final after = index == null
        ? const <String>[]
        : data.stations
            .sublist(index + 1, (index + 1 + RecapRules.stopsEachSide).clamp(index + 1, data.stations.length));

    // ---- the pages
    String join(List<String?> parts) => parts.whereType<String>().join(' ');
    String unit(int n, String many, String few) => n >= 3 && n <= 10 ? few : many;

    final sameTimeOnCover = timed > 0 && favouriteRides >= timed * RecapRules.coverSameTimeShare;
    final coverParts = [
      recapFill(RecapCopy.coverHours, base),
      recapFill(RecapCopy.coverDays, base),
      if (sameTimeOnCover) recapFill(RecapCopy.coverSameTime, base),
    ].whereType<String>().toList();
    final cover = RecapPage(
      kind: RecapPageKind.cover,
      kicker: data.termName ?? '',
      headline: RecapCopy.coverHeadline,
      lines: [if (!short && coverParts.isNotEmpty) coverParts.join(RecapCopy.coverJoin) + RecapCopy.coverEnd],
      cta: RecapCopy.coverCta,
    );
    const share_ = RecapPage(kind: RecapPageKind.share);

    final List<RecapPage> pages;
    if (short) {
      pages = [
        cover,
        RecapPage(
          kind: RecapPageKind.short,
          kicker: data.termName ?? '',
          numeral: '$rideDays',
          unit: unit(rideDays, RecapCopy.shortUnit, RecapCopy.shortUnitFew),
          lines: [RecapCopy.shortLine, if (line != null) line],
          chip: recapFill(RecapCopy.shortChip, {'اللقب': title.replaceAll('\n', ' ')}),
        ),
        share_,
      ];
    } else {
      // Hours, compared by range.
      String? compared;
      if (hoursShown != null) {
        final halves = (hoursShown / 12).round();
        final whole = halves ~/ 2;
        final length = (whole == 1 && halves.isOdd ? 'يوم' : recapCount(whole, 'يوم')) +
            (halves.isOdd ? RecapCopy.andHalf : '');
        compared = hoursShown < 10
            ? RecapCopy.hoursUnder10
            : hoursShown < 24
                ? RecapCopy.hours10to24
                : hoursShown < 72
                    ? recapFill(RecapCopy.hours1to3Days, {'مدة': length})
                    : hoursShown <= RecapRules.manyHours
                        ? recapFill(RecapCopy.hours3to6Days, {'مدة': length})
                        : RecapCopy.hoursOver6Days;
      }

      // The days page.
      final shortWeek = ownWeek && own.length <= RecapRules.shortWeekDays;
      final ownShare = join([
        recapFill(RecapCopy.daysOwnShare, {'ن': '$ownRidden', 'من': ownTotal}),
        if (ownRidden < ownTotal) RecapCopy.daysOwnShareRest,
      ]);
      final bonus = extra > 0 ? recapFill(RecapCopy.daysBonus, {'ن': extra}) : null;
      final tierLine = tier == RecapTier.light
          ? RecapCopy.daysLightRider
          : tier == RecapTier.regular
              ? RecapCopy.daysRegular
              : null;
      final daysLines = shortWeek
          ? [recapFill(RecapCopy.daysShortWeek, {'ن': own.length}), ownShare, bonus]
          : [
              join([
                recapFill(RecapCopy.daysBest, base),
                if (weakest != null) recapFill(RecapCopy.daysWeakest, {'الأضعف': RecapCopy.weekdayNames[weakest]}),
              ]),
              // One joke about the week at a time.
              bonus ?? (weakest == null ? recapFill(tierLine ?? '', base) : null),
            ];

      // An earlier time, caught a few times.
      String? early;
      if (favourite != null) {
        final earlier = (going.keys.where((t) => t.compareTo(favourite) < 0).toList()..sort());
        if (earlier.isNotEmpty && going[earlier.first]! <= favouriteRides * RecapRules.earlyTimeRatio) {
          early = recapFill(RecapCopy.timeEarly,
              {'ن': going[earlier.first], 'الوقت': RecapClock.of(earlier.first).digits});
        }
      }

      final returnChip =
          returnClock == null ? null : recapFill(RecapCopy.returnChip, {'الوقت': returnClock.full});
      final skipped = rideDays - returnDays;
      final back = returnDays == 0
          ? const RecapPage(
              kind: RecapPageKind.back,
              kicker: RecapCopy.returnKicker,
              headline: RecapCopy.returnNeverHeadline,
              lines: [RecapCopy.returnNeverLine],
            )
          : RecapPage(
              kind: RecapPageKind.back,
              kicker: RecapCopy.returnKicker,
              numeral: '$returnDays',
              unit: unit(returnDays, RecapCopy.returnUnit, RecapCopy.returnUnitFew),
              lines: [
                if (returnDays < rideDays * RecapRules.rarelyReturnsShare)
                  recapFill(RecapCopy.returnRarely, {'ي': rideDays, 'ن': '$returnDays'})
                else if (skipped > 0)
                  recapFill(RecapCopy.returnSkipped, {'ن': skipped}),
              ].whereType<String>().toList(),
              chip: returnChip,
            );

      final stopChip = index == null
          ? null
          : join([
              recapFill(RecapCopy.stopChip, {'ن': '${index + 1}', 'ن2': '${data.stations.length}'}),
            ]) +
              (recapFill(RecapCopy.stopChipTo, base) ?? '');

      final entered = recapFill(RecapCopy.collegeEntered, base);
      final boxed = family == null ? null : recapFill(family.boxTitle, {...base, 'ن': hoursShown == null ? null : hoursShown ~/ RecapRules.lectureHours});
      final college = family != null
          ? RecapPage(
              kind: RecapPageKind.college,
              kicker: RecapCopy.collegeKicker,
              headline: recapFill(RecapCopy.collegeHeadline, {'الكلية': family.call}),
              boxTitle: boxed ?? line,
              boxBody: boxed == null ? null : recapFill(family.boxBody, base),
              lines: [if (entered != null) entered],
            )
          : data.university == null
              ? null
              : RecapPage(
                  kind: RecapPageKind.college,
                  kicker: RecapCopy.universityKicker,
                  headline: data.university,
                  boxTitle: line,
                  lines: [if (entered != null) entered],
                );

      pages = [
        cover,
        if (hoursShown != null)
          RecapPage(
            kind: RecapPageKind.hours,
            kicker: RecapCopy.hoursKicker,
            numeral: '$hoursShown',
            unit: unit(hoursShown, RecapCopy.hoursUnit, RecapCopy.hoursUnitFew),
            lines: [compared, recapFill(family?.hoursTail ?? '', base)].whereType<String>().toList(),
            footnote: RecapCopy.hoursFootnote,
          ),
        RecapPage(
          kind: RecapPageKind.days,
          kicker: shortWeek ? RecapCopy.daysKickerShortWeek : RecapCopy.daysKicker,
          numeral: '$rideDays',
          unit: unit(rideDays, RecapCopy.daysUnit, RecapCopy.daysUnitFew),
          lines: daysLines.whereType<String>().where((l) => l.isNotEmpty).toList(),
        ),
        RecapPage(
          kind: RecapPageKind.shape,
          kicker: RecapCopy.shapeKicker,
          lines: [join([RecapCopy.shapeLine, if (gapInTheMiddle) RecapCopy.shapeMidGap])],
          footnote: recapFill(RecapCopy.shapeLabel, {'ي': ownRidden, 'من': ownTotal}),
        ),
        if (longestRun >= RecapRules.runPageFrom)
          RecapPage(
            kind: RecapPageKind.run,
            kicker: RecapCopy.runKicker,
            numeral: '$longestRun',
            unit: unit(longestRun, RecapCopy.runUnit, RecapCopy.runUnitFew),
            lines: const [RecapCopy.runLine],
            chip: longestGap >= RecapRules.gapChipFrom ? recapFill(RecapCopy.runGapChip, {'ن': longestGap}) : null,
          ),
        if (clock != null && timed >= RecapRules.timePageFromRides)
          RecapPage(
            kind: RecapPageKind.time,
            kicker: going.length == 1 ? RecapCopy.timeKickerOnly : RecapCopy.timeKicker,
            numeral: clock.digits,
            numeralSuffix: clock.suffix,
            unit: recapFill(RecapCopy.timeUnit, {'ن': favouriteRides}),
            lines: [RecapCopy.timeLine, if (early != null) early],
          ),
        back,
        if (data.stopName != null)
          RecapPage(
            kind: RecapPageKind.stop,
            kicker: recapFill(data.stopsUsed > 1 ? RecapCopy.stopKickerMostUsed : RecapCopy.stopKicker, base) ?? '',
            headline: data.stopName,
            lines: [
              recapFill(RecapCopy.stopLine, {'ن': data.stopRides > 0 ? data.stopRides : rideDays}),
            ].whereType<String>().toList(),
            chip: stopChip,
          ),
        if (college != null) college,
        RecapPage(
          kind: RecapPageKind.title,
          kicker: RecapCopy.titleKicker,
          headline: title,
          lines: [pageWhy],
          cta: RecapCopy.titleCta,
        ),
        share_,
      ];
    }

    return TermRecap._(
      data: data,
      tier: tier,
      rideDays: rideDays,
      studyWeekdays: study,
      ownWeekdays: own,
      ownWeek: ownWeek,
      ownTotal: ownTotal,
      ownRidden: ownRidden,
      extraRides: extra,
      weekdayCounts: counts,
      bestWeekday: best,
      weakestWeekday: weakest,
      longestRun: longestRun,
      longestGap: longestGap,
      gapInTheMiddle: gapInTheMiddle,
      favouriteTime: favourite,
      favouriteTimeRides: favouriteRides,
      distinctTimes: going.length,
      returnDays: returnDays,
      favouriteReturn: favouriteReturn,
      hours: hours,
      pattern: pattern,
      title: title,
      titleWhy: posterWhy,
      family: family,
      line: line,
      theme: recapDraw('$studentKey|theme', 5),
      bars: bars,
      weeks: weeks,
      stats: stats,
      pages: pages,
      stopsBefore: before,
      stopsAfter: after,
    );
  }
}
