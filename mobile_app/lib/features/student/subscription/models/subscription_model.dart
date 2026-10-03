import '../../lines/models/line_model.dart';

class SubscriptionModel {
  final String id;
  final String studentId;
  final String lineId;
  final String stationId;
  final String type; // termly | yearly | daily
  final String
      status; // pending_payment | pending_review | active | rejected | expired
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
  final String? supervisorPhone;
  final String? supervisorName;

  /// University whose trip this subscription rides on (scheduled lines only).
  final String? universityName;

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
    this.supervisorPhone,
    this.supervisorName,
    this.universityName,
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

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    final line = json['lines'] as Map<String, dynamic>?;
    final station = json['stations'] as Map<String, dynamic>?;
    final supervisor = line?['supervisors'] as Map<String, dynamic>?;
    // Scheduled lines: the only valid times are those of the student's university.
    final schedule = json['line_university_schedules'] as Map<String, dynamic>?;
    final university = schedule?['universities'] as Map<String, dynamic>?;
    final availableDepartureTimes = schedule != null
        ? stationTimes(schedule['departure_time'])
        : stationTimes(station?['departure_times'] ??
            json['departure_time'] ??
            station?['departure_time']);
    final availableReturnTimes = schedule != null
        ? stationTimes(schedule['return_time'])
        : stationTimes(station?['return_times'] ??
            json['return_time'] ??
            station?['return_time']);

    return SubscriptionModel(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      lineId: json['line_id'] as String,
      stationId: json['station_id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      price: (json['price'] as num).toDouble(),
      createdAt: json['created_at'] as String,
      lineName: line?['name'] as String?,
      stationName: station?['name'] as String?,
      departureTime: stationTimesLabel(json['departure_time'] ??
          station?['departure_times'] ??
          station?['departure_time']),
      returnTime: stationTimesLabel(json['return_time'] ??
          station?['return_times'] ??
          station?['return_time']),
      departureTimes: availableDepartureTimes,
      returnTimes: availableReturnTimes,
      supervisorPhone: supervisor?['phone'] as String?,
      supervisorName: supervisor?['full_name'] as String?,
      universityName: university?['name'] as String?,
      periodCode: json['period_code'] as String?,
      academicYear: (json['academic_year'] as num?)?.toInt(),
      periodLabel: json['period_label'] as String?,
      periodPhase: json['period_phase'] as String?,
    );
  }
}

/// A period the student can pay for now (get_purchasable_periods RPC).
class PurchasablePeriod {
  final String periodCode;
  final int academicYear;
  final String label;

  /// termly | yearly
  final String subscriptionType;
  final String startDate;
  final String endDate;

  /// current | upcoming
  final String phase;

  PurchasablePeriod({
    required this.periodCode,
    required this.academicYear,
    required this.label,
    required this.subscriptionType,
    required this.startDate,
    required this.endDate,
    required this.phase,
  });

  bool get isUpcoming => phase == 'upcoming';
  String get key => '$periodCode:$academicYear';

  factory PurchasablePeriod.fromJson(Map<String, dynamic> json) => PurchasablePeriod(
        periodCode: json['period_code'] as String,
        academicYear: (json['academic_year'] as num).toInt(),
        label: json['label'] as String? ?? json['name'] as String? ?? '',
        subscriptionType: json['subscription_type'] as String,
        startDate: json['start_date'] as String,
        endDate: json['end_date'] as String,
        phase: json['phase'] as String? ?? 'current',
      );
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
