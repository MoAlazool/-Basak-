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
  });

  bool get isActive => status == 'active';
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
