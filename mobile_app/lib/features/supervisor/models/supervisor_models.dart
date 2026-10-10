import '../../student/daily_ride/models/vote_settings.dart';
import '../qr_scanner/models/scanned_student_details.dart';

int _int(dynamic value) => (value as num?)?.toInt() ?? 0;
List<Map<String, dynamic>> _list(dynamic value) =>
    (value as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
/// Trimmed text, or null when missing or blank.
String? _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
List<String> _times(dynamic value) => (value as List<dynamic>? ?? const [])
    .map((time) => time.toString())
    .where((time) => time.isNotEmpty)
    .toList();

/// Result of get_supervisor_dashboard(): profile, assigned lines, totals.
class SupervisorDashboard {
  final DateTime today;
  final SupervisorProfile profile;
  final SupervisorTotals totals;
  final List<SupervisorLine> lines;

  /// Students per trip time (from ride confirmations), today and the next ride day.
  final List<SupervisorTripTime> tripTimes;

  SupervisorDashboard({
    required this.today,
    required this.profile,
    required this.totals,
    required this.lines,
    this.tripTimes = const [],
  });

  factory SupervisorDashboard.fromJson(Map<String, dynamic> json) =>
      SupervisorDashboard(
        today: DateTime.tryParse(json['today'] as String? ?? '') ?? DateTime.now(),
        profile: SupervisorProfile.fromJson(
            json['profile'] as Map<String, dynamic>? ?? const {}),
        totals: SupervisorTotals.fromJson(
            json['totals'] as Map<String, dynamic>? ?? const {}),
        lines: _list(json['lines']).map(SupervisorLine.fromJson).toList(),
        tripTimes: _list(json['trip_times']).map(SupervisorTripTime.fromJson).toList(),
      );

  /// Riders on [tripId] on [day] by the time each student chose; null when
  /// unknown ([tripId] null, or a server that does not group by trip yet).
  int? ridersOnTrip(String? tripId, DateTime day) {
    final rows = tripTimes.where((t) =>
        t.rideDate.year == day.year && t.rideDate.month == day.month && t.rideDate.day == day.day);
    if (tripId == null || rows.any((t) => t.tripId == null && !t.hasBreakdown)) return null;
    return rows.where((t) => t.tripId == tripId).fold<int>(0, (sum, t) => sum + t.students);
  }
}

/// One row of get_supervisor_dashboard().trip_times: the riders of one trip on
/// one ride day, grouped by the time each student chose that day (e.g. the
/// 6:55 departure -> 5 students). An older server sends only the first six
/// fields; the breakdown lists are then empty.
class SupervisorTripTime {
  final DateTime rideDate;
  final String lineId;
  final String lineName;

  /// 'departure' | 'return'
  final String direction;

  /// Trip start (bus leaves the origin / the university); the chosen stop time
  /// when the riders' time matches no trip.
  final String time;
  final int students;
  final String? tripId;
  final String label;

  /// The university the trip is reserved for; null = every university.
  final String? university;

  /// Stations in travel order with their riders (0 riders allowed).
  final List<TripTimeStation> stations;

  /// Riders per university, most riders first (shown for the return).
  final List<TripTimeUniversity> universities;

  /// Riders in station travel order, then by name.
  final List<TripTimeRider> riders;

  SupervisorTripTime({
    required this.rideDate,
    required this.lineId,
    required this.lineName,
    required this.direction,
    required this.time,
    required this.students,
    this.tripId,
    this.label = '',
    this.university,
    this.stations = const [],
    this.universities = const [],
    this.riders = const [],
  });

  bool get isReturn => direction == 'return';

  /// Whether the server sent the per-station / per-university breakdown.
  bool get hasBreakdown => isReturn ? universities.isNotEmpty : stations.isNotEmpty;

  /// The trip label and university, e.g. "الرحلة الأولى · جامعة المنصورة".
  String get subtitle =>
      [label, if (university != null) university!].where((x) => x.isNotEmpty).join(' · ');

  List<TripTimeRider> ridersAt(String stationId) =>
      riders.where((r) => r.stationId == stationId).toList();

  List<TripTimeRider> ridersOf(String university) =>
      riders.where((r) => r.universityName == university).toList();

  factory SupervisorTripTime.fromJson(Map<String, dynamic> json) => SupervisorTripTime(
        rideDate: DateTime.tryParse(json['ride_date'] as String? ?? '') ?? DateTime.now(),
        lineId: json['line_id'] as String? ?? '',
        lineName: json['line_name'] as String? ?? '',
        direction: json['direction'] as String? ?? 'departure',
        time: json['time'] as String? ?? '',
        students: _int(json['students']),
        tripId: json['trip_id'] as String?,
        label: (json['label'] as String? ?? '').trim(),
        university: _text(json['university']),
        stations: _list(json['stations']).map(TripTimeStation.fromJson).toList(),
        universities: _list(json['universities']).map(TripTimeUniversity.fromJson).toList(),
        riders: _list(json['riders']).map(TripTimeRider.fromJson).toList(),
      );
}

class TripTimeStation {
  final String id;
  final String name;
  final int orderIndex;

  /// Null when the trip does not stop here (a rider still boards here).
  final String? stopTime;
  final int students;

  TripTimeStation({
    required this.id,
    required this.name,
    required this.orderIndex,
    required this.stopTime,
    required this.students,
  });

  factory TripTimeStation.fromJson(Map<String, dynamic> json) => TripTimeStation(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        orderIndex: _int(json['order_index']),
        stopTime: _text(json['stop_time']),
        students: _int(json['students']),
      );
}

class TripTimeUniversity {
  final String name;
  final int students;

  TripTimeUniversity({required this.name, required this.students});

  factory TripTimeUniversity.fromJson(Map<String, dynamic> json) => TripTimeUniversity(
        name: _text(json['name']) ?? unknownUniversity,
        students: _int(json['students']),
      );
}

/// What the server calls a student without a university.
const unknownUniversity = 'غير محددة';

class TripTimeRider {
  final String id;
  final String fullName;
  final String phone;
  final String? stationId;
  final String? station;
  final String? university;

  /// The stop time the student chose at their station for this direction.
  final String? time;

  TripTimeRider({
    required this.id,
    required this.fullName,
    required this.phone,
    this.stationId,
    this.station,
    this.university,
    this.time,
  });

  /// The university group this rider is counted in.
  String get universityName => university ?? unknownUniversity;

  factory TripTimeRider.fromJson(Map<String, dynamic> json) => TripTimeRider(
        id: json['id'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        stationId: json['station_id'] as String?,
        station: _text(json['station']),
        university: _text(json['university']),
        time: _text(json['time']),
      );
}

class SupervisorProfile {
  final String id;
  final String fullName;
  final String phone;
  final bool isActive;
  final DateTime? createdAt;
  final String? companyId;
  final String? companyName;
  final bool companyActive;

  /// 'direct' = the company assigned lines to this supervisor; 'none' = no line yet.
  final String assignment;

  /// When the company's students vote (tomorrow's counts move from its opening).
  final VoteSettings vote;

  SupervisorProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.isActive,
    required this.createdAt,
    this.companyId,
    required this.companyName,
    required this.companyActive,
    required this.assignment,
    this.vote = VoteSettings.fallback,
  });

  bool get isDirectlyAssigned => assignment == 'direct';

  factory SupervisorProfile.fromJson(Map<String, dynamic> json) => SupervisorProfile(
        id: json['id'] as String? ?? '',
        fullName: json['full_name'] as String? ?? 'المشرف',
        phone: json['phone'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        companyId: json['company_id'] as String?,
        companyName: json['company_name'] as String?,
        companyActive: json['company_active'] as bool? ?? true,
        assignment: json['assignment'] as String? ?? 'none',
        vote: json['vote'] is Map
            ? VoteSettings.fromJson(Map<String, dynamic>.from(json['vote'] as Map))
            : VoteSettings.fallback,
      );
}

class SupervisorTotals {
  final int lines;
  final int registeredStudents;
  final int stations;
  final int confirmedToday;
  final int checkedInToday;

  SupervisorTotals({
    required this.lines,
    required this.registeredStudents,
    required this.stations,
    required this.confirmedToday,
    required this.checkedInToday,
  });

  factory SupervisorTotals.fromJson(Map<String, dynamic> json) => SupervisorTotals(
        lines: _int(json['lines']),
        registeredStudents: _int(json['registered_students']),
        stations: _int(json['stations']),
        confirmedToday: _int(json['confirmed_today']),
        checkedInToday: _int(json['checked_in_today']),
      );
}

class SupervisorLine {
  final String id;
  final String name;
  final bool isActive;
  final bool directlyAssigned;
  final double priceTermly;
  final double priceYearly;
  final double priceDaily;
  final int registeredStudents;
  final int confirmedToday;
  final List<LineUniversityTrip> schedules;
  final List<SupervisorStation> stations;
  final int departureTrips;
  final int returnTrips;

  /// Every active trip of the line, both directions, by start time. Empty
  /// from a server that does not list them.
  final List<LineTrip> trips;

  /// The university the line goes to; null when the company set none.
  final String? destination;

  SupervisorLine({
    required this.id,
    required this.name,
    required this.isActive,
    required this.directlyAssigned,
    required this.priceTermly,
    required this.priceYearly,
    required this.priceDaily,
    required this.registeredStudents,
    required this.confirmedToday,
    required this.schedules,
    required this.stations,
    this.departureTrips = 0,
    this.returnTrips = 0,
    this.trips = const [],
    this.destination,
  });

  List<LineTrip> tripsOf(String direction) => trips.where((t) => t.direction == direction).toList();

  factory SupervisorLine.fromJson(Map<String, dynamic> json) => SupervisorLine(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        directlyAssigned: json['directly_assigned'] as bool? ?? false,
        priceTermly: (json['price_termly'] as num?)?.toDouble() ?? 0,
        priceYearly: (json['price_yearly'] as num?)?.toDouble() ?? 0,
        priceDaily: (json['price_daily'] as num?)?.toDouble() ?? 0,
        registeredStudents: _int(json['registered_students']),
        confirmedToday: _int(json['confirmed_today']),
        schedules: _list(json['schedules']).map(LineUniversityTrip.fromJson).toList(),
        stations: _list(json['stations']).map(SupervisorStation.fromJson).toList(),
        departureTrips: _list(json['trips']).where((t) => t['direction'] == 'departure').length,
        returnTrips: _list(json['trips']).where((t) => t['direction'] == 'return').length,
        trips: _list(json['trips']).map(LineTrip.fromJson).where((t) => t.startTime.isNotEmpty).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime)),
        destination: _text(json['destination']),
      );
}

/// One trip of a line as get_supervisor_dashboard().lines[].trips lists it.
class LineTrip {
  final String? id;

  /// 'departure' | 'return'
  final String direction;

  /// When the bus leaves the origin (departure) or the university (return).
  final String startTime;
  final String? arrivalTime;
  final String label;

  LineTrip({this.id, required this.direction, required this.startTime, this.arrivalTime, this.label = ''});

  bool get isReturn => direction == 'return';

  factory LineTrip.fromJson(Map<String, dynamic> json) => LineTrip(
        id: json['id'] as String?,
        direction: json['direction'] as String? ?? 'departure',
        // line_trips_summary sends the start of either direction as departure_time.
        startTime: _text(json['start_time']) ?? _text(json['departure_time']) ?? '',
        arrivalTime: _text(json['arrival_time']),
        label: (json['label'] as String? ?? '').trim(),
      );
}

class LineUniversityTrip {
  /// The trip (line_trips.id); null from an older server.
  final String? id;
  final String university;
  final String departureTime;
  final String returnTime;
  final int registeredStudents;

  LineUniversityTrip({
    this.id,
    required this.university,
    required this.departureTime,
    required this.returnTime,
    required this.registeredStudents,
  });

  factory LineUniversityTrip.fromJson(Map<String, dynamic> json) => LineUniversityTrip(
        id: json['id'] as String?,
        university: json['university'] as String? ?? '',
        departureTime: json['departure_time'] as String? ?? '',
        returnTime: json['return_time'] as String? ?? '',
        registeredStudents: _int(json['registered_students']),
      );
}

class SupervisorStation {
  final String id;
  final String name;
  final int orderIndex;
  final List<String> departureTimes;
  final List<String> returnTimes;
  final int registeredStudents;
  final int confirmedToday;
  final int checkedInToday;

  SupervisorStation({
    required this.id,
    required this.name,
    required this.orderIndex,
    required this.departureTimes,
    required this.returnTimes,
    required this.registeredStudents,
    required this.confirmedToday,
    required this.checkedInToday,
  });

  factory SupervisorStation.fromJson(Map<String, dynamic> json) => SupervisorStation(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        orderIndex: _int(json['order_index']),
        departureTimes: _times(json['departure_times']),
        returnTimes: _times(json['return_times']),
        registeredStudents: _int(json['registered_students']),
        confirmedToday: _int(json['confirmed_today']),
        checkedInToday: _int(json['checked_in_today']),
      );
}

/// Outcome of supervisor_check_in_student().
enum CheckInOutcome {
  checkedIn,
  alreadyCheckedIn,
  noActiveSubscription,
  outsideAssignedLines,
  notFound,
  offlineLookup;

  static CheckInOutcome fromResult(String? value) => switch (value) {
        'checked_in' => CheckInOutcome.checkedIn,
        'already_checked_in' => CheckInOutcome.alreadyCheckedIn,
        'no_active_subscription' => CheckInOutcome.noActiveSubscription,
        'outside_assigned_lines' => CheckInOutcome.outsideAssignedLines,
        _ => CheckInOutcome.notFound,
      };

  bool get isSuccess => this == checkedIn;
}

/// The student's ride vote for the day, as seen when scanning their card.
class RideVote {
  final bool isRiding;
  final bool isReturning;
  final String? departureTime;
  final String? returnTime;

  const RideVote({
    required this.isRiding,
    required this.isReturning,
    this.departureTime,
    this.returnTime,
  });

  factory RideVote.fromJson(Map<String, dynamic> json) => RideVote(
        isRiding: json['is_riding'] as bool? ?? false,
        isReturning: json['is_returning'] as bool? ?? false,
        departureTime: json['departure_time'] as String?,
        returnTime: json['return_time'] as String?,
      );
}

class CheckInResult {
  final CheckInOutcome outcome;

  /// Server explanation, e.g. "تم تسجيل الطالب في رحلة الذهاب."
  final String? message;
  final String direction;
  final DateTime? checkedInAt;
  final bool? confirmedRideToday;

  /// The day's vote; null when the student did not vote.
  final RideVote? rideVote;

  /// Whether the server reported the vote (older servers send only
  /// [confirmedRideToday]).
  final bool hasRideVote;
  final ScannedStudentDetails? student;

  /// The platform or a company blocked this student. The scan is not refused
  /// for it; the supervisor is told (older servers never say so).
  final bool blocked;

  /// The student's photo in 'student-avatars', when the scan shows their
  /// details: the supervisor compares it with the face in front of them.
  final String? photoPath;

  CheckInResult({
    required this.outcome,
    this.message,
    required this.direction,
    this.checkedInAt,
    this.confirmedRideToday,
    this.rideVote,
    this.hasRideVote = false,
    this.student,
    this.blocked = false,
    this.photoPath,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) => CheckInResult(
        outcome: CheckInOutcome.fromResult(json['result'] as String?),
        message: json['message'] as String?,
        direction: json['direction'] as String? ?? 'departure',
        checkedInAt: DateTime.tryParse(json['checked_in_at'] as String? ?? '')?.toLocal(),
        confirmedRideToday: json['confirmed_ride_today'] as bool?,
        rideVote: json['ride_vote'] is Map
            ? RideVote.fromJson(Map<String, dynamic>.from(json['ride_vote'] as Map))
            : null,
        hasRideVote: json.containsKey('ride_vote'),
        student: json['student'] is Map
            ? ScannedStudentDetails.fromJson(Map<String, dynamic>.from(json['student'] as Map))
            : null,
        blocked: json['blocked'] == true,
        photoPath: json['photo'] is String && (json['photo'] as String).trim().isNotEmpty ? json['photo'] as String : null,
      );
}

/// Result of get_supervisor_monthly_summary().
class SupervisorMonthlySummary {
  final DateTime month;
  final int checkins;
  final int departureCheckins;
  final int returnCheckins;
  final int uniqueStudents;
  final int scans;
  final int duplicateScans;
  final int rejectedScans;
  final int activeDays;
  final int confirmedRides;
  final List<DailyActivity> days;
  final List<StationActivity> stations;

  SupervisorMonthlySummary({
    required this.month,
    required this.checkins,
    required this.departureCheckins,
    required this.returnCheckins,
    required this.uniqueStudents,
    required this.scans,
    required this.duplicateScans,
    required this.rejectedScans,
    required this.activeDays,
    required this.confirmedRides,
    required this.days,
    required this.stations,
  });

  /// Departure check-ins against rides students confirmed in the app.
  double? get attendanceRate =>
      confirmedRides == 0 ? null : (departureCheckins / confirmedRides).clamp(0, 1).toDouble();

  factory SupervisorMonthlySummary.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return SupervisorMonthlySummary(
      month: DateTime.tryParse(json['month'] as String? ?? '') ?? DateTime.now(),
      checkins: _int(totals['checkins']),
      departureCheckins: _int(totals['departure_checkins']),
      returnCheckins: _int(totals['return_checkins']),
      uniqueStudents: _int(totals['unique_students']),
      scans: _int(totals['scans']),
      duplicateScans: _int(totals['duplicate_scans']),
      rejectedScans: _int(totals['rejected_scans']),
      activeDays: _int(totals['active_days']),
      confirmedRides: _int(totals['confirmed_rides']),
      days: _list(json['days']).map(DailyActivity.fromJson).toList(),
      stations: _list(json['stations']).map(StationActivity.fromJson).toList(),
    );
  }
}

class DailyActivity {
  final DateTime date;
  final int checkins;
  final int departure;
  final int returning;
  final int scans;
  final int confirmed;

  DailyActivity({
    required this.date,
    required this.checkins,
    required this.departure,
    required this.returning,
    required this.scans,
    required this.confirmed,
  });

  factory DailyActivity.fromJson(Map<String, dynamic> json) => DailyActivity(
        date: DateTime.parse(json['date'] as String),
        checkins: _int(json['checkins']),
        departure: _int(json['departure']),
        returning: _int(json['return']),
        scans: _int(json['scans']),
        confirmed: _int(json['confirmed']),
      );
}

class StationActivity {
  final String station;
  final String line;
  final int checkins;

  StationActivity({required this.station, required this.line, required this.checkins});

  factory StationActivity.fromJson(Map<String, dynamic> json) => StationActivity(
        station: json['station'] as String? ?? '',
        line: json['line'] as String? ?? '',
        checkins: _int(json['checkins']),
      );
}


/// Result of get_supervisor_trip_manifest(): one Going or Return trip of a line
/// with its stations in travel order and the students at each station.
class TripManifest {
  final String lineId;
  final String lineName;
  final String originName;
  final String? destination;
  final String direction; // departure | return
  final List<ManifestTripOption> trips;
  final ManifestTripOption? trip;
  final List<ManifestStation> stations;

  /// Students subscribed to the line who have not answered today's ride vote
  /// (and are not checked in for this direction).
  final List<ManifestStudent> unconfirmed;

  TripManifest({
    required this.lineId,
    required this.lineName,
    required this.originName,
    required this.destination,
    required this.direction,
    required this.trips,
    required this.trip,
    required this.stations,
    this.unconfirmed = const [],
  });

  bool get isReturn => direction == 'return';

  /// A return trip saved without station times: every stop carries the start time.
  bool get stopTimesUnset {
    final times = stations.map((s) => s.stopTime).whereType<String>().toList();
    String hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;
    return isReturn &&
        trip != null &&
        times.isNotEmpty &&
        times.every((t) => hhmm(t) == hhmm(trip!.startTime));
  }

  List<ManifestStudent> get students => [for (final s in stations) ...s.students];
  int get totalStudents => students.length;
  int get checkedIn => students.where((s) => s.isCheckedIn).length;
  int get confirmed => students.where((s) => s.confirmed).length;

  /// Start → stops → end in travel order (Return starts at the university).
  List<String> get routeNames {
    final stops = stations.where((s) => s.stopTime != null).map((s) => s.name).toList();
    final start = isReturn ? (destination ?? 'الجامعة') : originName;
    final end = isReturn ? originName : (destination ?? 'الجامعة');
    return [start, ...stops, end];
  }

  factory TripManifest.fromJson(Map<String, dynamic> json) {
    final line = json['line'] as Map<String, dynamic>? ?? const {};
    return TripManifest(
      lineId: line['id'] as String? ?? '',
      lineName: line['name'] as String? ?? '',
      originName: line['origin_name'] as String? ?? '',
      destination: line['destination'] as String?,
      direction: json['direction'] as String? ?? 'departure',
      trips: _list(json['trips']).map(ManifestTripOption.fromJson).toList(),
      trip: json['trip'] is Map
          ? ManifestTripOption.fromJson(Map<String, dynamic>.from(json['trip'] as Map))
          : null,
      stations: _list(json['stations']).map(ManifestStation.fromJson).toList(),
      unconfirmed: _list(json['unconfirmed']).map(ManifestStudent.fromJson).toList(),
    );
  }
}

class ManifestTripOption {
  final String id;
  final String label;
  final String startTime;
  final String? arrivalTime;
  final String? university;
  final int students;

  ManifestTripOption({
    required this.id,
    required this.label,
    required this.startTime,
    required this.arrivalTime,
    required this.university,
    required this.students,
  });

  factory ManifestTripOption.fromJson(Map<String, dynamic> json) => ManifestTripOption(
        id: json['id'] as String,
        label: (json['label'] as String? ?? '').trim(),
        startTime: json['start_time'] as String? ?? '',
        arrivalTime: json['arrival_time'] as String?,
        university: json['university'] as String?,
        students: _int(json['students']),
      );
}

class ManifestStation {
  final String id;
  final String name;
  final String? stopTime;
  final List<ManifestStudent> students;

  ManifestStation(
      {required this.id, required this.name, required this.stopTime, required this.students});

  int get checkedIn => students.where((s) => s.isCheckedIn).length;

  factory ManifestStation.fromJson(Map<String, dynamic> json) => ManifestStation(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        stopTime: json['stop_time'] as String?,
        students: _list(json['students']).map(ManifestStudent.fromJson).toList(),
      );
}

class ManifestStudent {
  final String id;
  final String fullName;
  final String phone;
  final String? university;
  final bool confirmed;
  final DateTime? checkedInAt;

  /// The stop time the student chose today for this direction; null when they
  /// did not confirm.
  final String? chosenTime;

  /// The student's boarding station (sent for the unconfirmed list).
  final String? station;

  ManifestStudent({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.university,
    required this.confirmed,
    required this.checkedInAt,
    this.chosenTime,
    this.station,
  });

  bool get isCheckedIn => checkedInAt != null;

  factory ManifestStudent.fromJson(Map<String, dynamic> json) => ManifestStudent(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        university: json['university'] as String?,
        confirmed: json['confirmed'] as bool? ?? false,
        checkedInAt: DateTime.tryParse(json['checked_in_at'] as String? ?? '')?.toLocal(),
        chosenTime: _text(json['chosen_time']),
        station: _text(json['station']),
      );
}
