class SubscriptionModel {
  final String id;
  final String studentId;
  final String lineId;
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
  final String? supervisorPhone;
  final String? supervisorName;

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
    this.supervisorPhone,
    this.supervisorName,
  });

  bool get isActive => status == 'active';
  bool get isPendingReview => status == 'pending_review';
  bool get isRejected => status == 'rejected';
  bool get isDaily => type == 'daily';

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    final line = json['lines'] as Map<String, dynamic>?;
    final station = json['stations'] as Map<String, dynamic>?;
    final supervisor = line?['supervisors'] as Map<String, dynamic>?;

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
      departureTime: station?['departure_time'] as String?,
      returnTime: station?['return_time'] as String?,
      supervisorPhone: supervisor?['phone'] as String?,
      supervisorName: supervisor?['full_name'] as String?,
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
