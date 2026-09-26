class StationRiderCountModel {
  final String stationId;
  final String stationName;
  final int orderIndex;
  final String departureTime;
  final String returnTime;
  final int ridingCount;

  StationRiderCountModel({
    required this.stationId,
    required this.stationName,
    required this.orderIndex,
    required this.departureTime,
    required this.returnTime,
    required this.ridingCount,
  });

  factory StationRiderCountModel.fromJson(Map<String, dynamic> json) {
    return StationRiderCountModel(
      stationId: json['station_id'] as String,
      stationName: json['station_name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
      departureTime: json['departure_time'] as String,
      returnTime: json['return_time'] as String,
      ridingCount: (json['riding_count'] as num?)?.toInt() ?? 0,
    );
  }
}
