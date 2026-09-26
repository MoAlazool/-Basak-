class ScannedStudentDetails {
  final String id;
  final String fullName;
  final String phone;
  final String university;
  final String? subscriptionType;
  final String? subscriptionStatus;
  final String? lineName;
  final String? stationName;
  final String? departureTime;
  final String? returnTime;
  final String? paymentDate;
  final bool todayRideStatus;

  ScannedStudentDetails({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.university,
    this.subscriptionType,
    this.subscriptionStatus,
    this.lineName,
    this.stationName,
    this.departureTime,
    this.returnTime,
    this.paymentDate,
    required this.todayRideStatus,
  });

  bool get hasActiveSubscription => subscriptionStatus == 'active';

  factory ScannedStudentDetails.fromJson(Map<String, dynamic> json) {
    final sub = json['subscription'] as Map<String, dynamic>?;

    return ScannedStudentDetails(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      university: json['university'] as String,
      subscriptionType: sub?['type'] as String?,
      subscriptionStatus: sub?['status'] as String?,
      lineName: sub?['line_name'] as String?,
      stationName: sub?['station_name'] as String?,
      departureTime: sub?['departure_time'] as String?,
      returnTime: sub?['return_time'] as String?,
      paymentDate: sub?['payment_date'] as String?,
      todayRideStatus: json['today_ride_status'] as bool? ?? false,
    );
  }
}
