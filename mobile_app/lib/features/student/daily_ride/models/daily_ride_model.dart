class DailyRideModel {
  final String id;
  final String studentId;
  final String rideDate;
  final bool isRiding;
  final String toggledAt;

  DailyRideModel({
    required this.id,
    required this.studentId,
    required this.rideDate,
    required this.isRiding,
    required this.toggledAt,
  });

  factory DailyRideModel.fromJson(Map<String, dynamic> json) {
    return DailyRideModel(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      rideDate: json['ride_date'] as String,
      isRiding: json['is_riding'] as bool? ?? false,
      toggledAt: json['toggled_at'] as String,
    );
  }
}
