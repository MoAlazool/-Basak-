import '../../lines/models/line_model.dart';

class SubscriptionModel {
  final String id;
  final String studentId;
  final String lineId;
  final String? companyId;
  final String stationId;
  final String type; // termly | yearly | daily
  final String status; // pending_payment | pending_review | active | rejected | expired
  final String? startDate;
  final String? endDate;
  final double price;
  final String createdAt;
  final String? lineName;
  final String? stationName;
  final String? departureTime;
  final String? returnTime;
  final List<String> departureTimes;
  final List<String> returnTimes;

  /// Start time (HH:mm, when the bus leaves the university) of the return trip
  /// behind each return stop time at the student's station. Students board the
  /// return bus at the university, so that is the time they are shown; the
  /// stop time stays the value saved and checked by the server.
  final Map<String, String> returnStartTimes;
  final String? supervisorPhone;
  final String? supervisorName;

  /// The supervisor's photo in 'supervisor-avatars', if the company added one.
  final String? supervisorPhotoPath;

  /// University whose trip this subscription rides on (scheduled lines only).
  final String? universityName;

  /// The student's own university: where the line takes them.
  final String? studentUniversity;
  final String? companyName;

  /// Semester / annual period (configured centrally in academic_terms).
  final String? periodCode;
  final int? academicYear;

  /// e.g. "الفصل الدراسي الثاني 2026/2027" (server computed field).
  final String? periodLabel;

  /// current | upcoming | expired (server computed field, Cairo date).
  final String? periodPhase;

  SubscriptionModel({
    required this.id,
    required this.studentId,
    required this.lineId,
    this.companyId,
    required this.stationId,
    required this.type,
    required this.status,
    this.startDate,
    this.endDate,
    required this.price,
    required this.createdAt,
    this.lineName,
    this.stationName,
    this.departureTime,
    this.returnTime,
    this.departureTimes = const [],
    this.returnTimes = const [],
    this.returnStartTimes = const {},
    this.supervisorPhone,
    this.supervisorName,
    this.supervisorPhotoPath,
    this.universityName,
    this.studentUniversity,
    this.companyName,
    this.periodCode,
    this.academicYear,
    this.periodLabel,
    this.periodPhase,
  });

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired' || periodPhase == 'expired';
  bool get isUpcoming => !isExpired && periodPhase == 'upcoming';
  bool get isCurrent => !isExpired && !isUpcoming;
  bool get isPendingReview => status == 'pending_review';
  bool get isRejected => status == 'rejected';
  bool get isDaily => type == 'daily';

  /// The main title on every screen: where the student boards. The line and
  /// the university are shown under it, each on its own row, so a long line
  /// name never becomes the headline.
  String get boardingTitle {
    final station = (stationName ?? '').trim();
    return station.isNotEmpty ? station : ((lineName ?? '').trim().isNotEmpty ? lineName!.trim() : 'اشتراكي');
  }

  /// The student's own university: where the line takes them.
  String? get destination {
    final name = (studentUniversity ?? universityName ?? '').trim();
    return name.isEmpty ? null : name;
  }

  /// "الفصل الأول", "الفصلان معاً" ... without the year.
  String get periodName => switch (periodCode) {
        'first' => 'الفصل الأول',
        'second' => 'الفصل الثاني',
        'both' || 'annual' => 'الفصلان معاً',
        'summer' => 'الفصل الصيفي',
        _ => type == 'daily' ? 'اشتراك يومي' : (periodLabel ?? 'اشتراك'),
      };

  /// A return stop [time] as shown to the student: its trip's start time.
  String returnShown(String time) => returnStartTimes[_hhmm(time)] ?? time;

  /// [returnTime] as shown to the student (each time replaced by its trip's start).
  String? get returnTimeShown => returnTime == null || returnTime!.trim().isEmpty
      ? returnTime
      : returnTime!.split(RegExp(r'[,،]')).map((t) => returnShown(t.trim())).join('، ');

  static String _hhmm(Object? value) {
    final text = value?.toString() ?? '';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    final line = json['lines'] as Map<String, dynamic>?;
    final station = json['stations'] as Map<String, dynamic>?;
    final supervisor = line?['supervisors'] as Map<String, dynamic>?;
    // Times the student may ride from their station: stop times of the active
    // trips that serve their university (RLS filters the trips), plus their own.
    final trip = json['departure_trip'] as Map<String, dynamic>?;
    final university = trip?['universities'] as Map<String, dynamic>?;
    final stops = (station?['line_trip_stops'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((stop) => (stop['line_trips'] as Map<String, dynamic>?)?['is_active'] == true)
        .toList();
    List<String> stopTimes(String direction, dynamic own) => stationTimes([
          ...stops
              .where((stop) =>
                  (stop['line_trips'] as Map<String, dynamic>?)?['direction'] == direction)
              .map((stop) => stop['stop_time']),
          if (own != null) own,
        ]).toSet().toList();
    final availableDepartureTimes = stops.isNotEmpty
        ? stopTimes('departure', json['departure_time'])
        : stationTimes(station?['departure_times'] ?? json['departure_time']);
    // The way back starts at the university: its times are the return trips'
    // own times (the trips this student may ride; RLS filters them).
    final returnTrips = (line?['line_trips'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((t) => t['direction'] == 'return' && t['is_active'] == true)
        .toList();
    final availableReturnTimes = returnTrips.isNotEmpty
        ? (stationTimes([
            ...returnTrips.map((t) => t['start_time']),
            if (json['return_time'] != null) json['return_time'],
          ]).toSet().toList()
          ..sort())
        : stops.isNotEmpty
            ? stopTimes('return', json['return_time'])
            : stationTimes(station?['return_times'] ?? json['return_time']);
    final returnStartTimes = <String, String>{
      for (final stop in stops)
        if ((stop['line_trips'] as Map<String, dynamic>?)?['direction'] == 'return' &&
            stop['stop_time'] != null &&
            (stop['line_trips'] as Map<String, dynamic>?)?['start_time'] != null)
          _hhmm(stop['stop_time']):
              _hhmm((stop['line_trips'] as Map<String, dynamic>)['start_time']),
    };
    // The student's own return trip decides their saved time.
    final ownReturnStart = (json['return_trip'] as Map<String, dynamic>?)?['start_time'];
    if (ownReturnStart != null && json['return_time'] != null) {
      returnStartTimes[_hhmm(json['return_time'])] = _hhmm(ownReturnStart);
    }

    return SubscriptionModel(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      lineId: json['line_id'] as String,
      companyId: json['company_id'] as String?,
      stationId: json['station_id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      price: (json['price'] as num).toDouble(),
      createdAt: json['created_at'] as String,
      lineName: line?['name'] as String?,
      stationName: station?['name'] as String?,
      departureTime: stationTimesLabel(
          json['departure_time'] ?? station?['departure_times'] ?? station?['departure_time']),
      returnTime: stationTimesLabel(
          json['return_time'] ?? station?['return_times'] ?? station?['return_time']),
      departureTimes: availableDepartureTimes,
      returnTimes: availableReturnTimes,
      returnStartTimes: returnStartTimes,
      supervisorPhone: supervisor?['phone'] as String?,
      supervisorName: supervisor?['full_name'] as String?,
      supervisorPhotoPath: supervisor?['profile_image_url'] as String?,
      universityName: university?['name'] as String?,
      studentUniversity: (json['student'] as Map?)?['university'] as String?,
      companyName: (line?['companies'] as Map?)?['name'] as String?,
      periodCode: json['period_code'] as String?,
      academicYear: (json['academic_year'] as num?)?.toInt(),
      periodLabel: json['period_label'] as String?,
      periodPhase: json['period_phase'] as String?,
    );
  }
}

class ReceiptModel {
  final String id;
  final String subscriptionId;
  final String imageUrl;
  final String status; // pending | approved | rejected
  final String? rejectionReason;
  final int attemptNumber; // 1 to 5
  final String? reviewedBy;
  final String createdAt;
  final String? reviewedAt;

  ReceiptModel({
    required this.id,
    required this.subscriptionId,
    required this.imageUrl,
    required this.status,
    this.rejectionReason,
    required this.attemptNumber,
    this.reviewedBy,
    required this.createdAt,
    this.reviewedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get canReupload => isRejected && attemptNumber < 5;

  factory ReceiptModel.fromJson(Map<String, dynamic> json) {
    return ReceiptModel(
      id: json['id'] as String,
      subscriptionId: json['subscription_id'] as String,
      imageUrl: json['image_url'] as String,
      status: json['status'] as String,
      rejectionReason: json['rejection_reason'] as String?,
      attemptNumber: json['attempt_number'] as int? ?? 1,
      reviewedBy: json['reviewed_by'] as String?,
      createdAt: json['created_at'] as String,
      reviewedAt: json['reviewed_at'] as String?,
    );
  }
}
