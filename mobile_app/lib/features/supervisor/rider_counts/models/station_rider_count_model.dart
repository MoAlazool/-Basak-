class StationRiderCountModel {
  final String lineId;
  final String lineName;
  final String stationId;
  final String stationName;
  final int orderIndex;
  final String departureTime;
  final String returnTime;
  final int ridingCount;
  final int returningCount;

  /// University trip this row belongs to (null for station-time lines).
  final String? universityName;

  StationRiderCountModel({
    required this.lineId,
    required this.lineName,
    required this.stationId,
    required this.stationName,
    required this.orderIndex,
    required this.departureTime,
    required this.returnTime,
    required this.ridingCount,
    required this.returningCount,
    this.universityName,
  });

  factory StationRiderCountModel.fromJson(Map<String, dynamic> json) {
    return StationRiderCountModel(
      lineId: json['line_id'] as String? ?? '',
      lineName: json['line_name'] as String? ?? '',
      stationId: json['station_id'] as String,
      stationName: json['station_name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
      departureTime: json['departure_time'] as String? ?? '',
      returnTime: json['return_time'] as String? ?? '',
      ridingCount: (json['riding_count'] as num?)?.toInt() ?? 0,
      returningCount: (json['returning_count'] as num?)?.toInt() ?? 0,
      universityName: json['university_name'] as String?,
    );
  }
}
