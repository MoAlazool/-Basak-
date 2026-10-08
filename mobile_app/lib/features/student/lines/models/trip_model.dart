import 'line_model.dart';

/// A departure or return trip of a line (line_trips + line_trip_stops).
/// Students only receive the trips that serve their university (RLS).
class TripModel {
  final String id;
  final String direction; // departure | return
  final String label;
  final String startTime; // HH:mm
  final String? arrivalTime;
  final String? universityName; // null = open to every university
  /// station id → time the trip passes that station (HH:mm).
  final Map<String, String> stops;

  const TripModel({
    required this.id,
    required this.direction,
    required this.label,
    required this.startTime,
    required this.arrivalTime,
    required this.universityName,
    required this.stops,
  });

  bool get isDeparture => direction == 'departure';

  /// A return trip saved without station times: every stop carries the start
  /// time (it serves all stations; students board at the university).
  bool get stopTimesUnset =>
      !isDeparture && stops.isNotEmpty && stops.values.every((time) => time == startTime);
  String? timeAt(String stationId) => stops[stationId];

  static String? _hhmm(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  factory TripModel.fromJson(Map<String, dynamic> json) {
    final university = json['universities'] as Map<String, dynamic>?;
    return TripModel(
      id: json['id'] as String,
      direction: json['direction'] as String? ?? 'departure',
      label: (json['label'] as String? ?? '').trim(),
      startTime: _hhmm(json['start_time']) ?? '',
      arrivalTime: _hhmm(json['arrival_time']),
      universityName: university?['name'] as String?,
      stops: {
        for (final stop in (json['line_trip_stops'] as List<dynamic>? ?? const []))
          (stop as Map<String, dynamic>)['station_id'] as String: _hhmm(stop['stop_time']) ?? '',
      },
    );
  }

  /// Stations this trip stops at, in travel order (reversed for return trips).
  List<StationModel> stopsAlong(List<StationModel> stations) {
    final ordered = isDeparture ? stations : stations.reversed.toList();
    return ordered.where((station) => stops.containsKey(station.id)).toList();
  }
}
