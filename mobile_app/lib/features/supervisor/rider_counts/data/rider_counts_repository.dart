import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/station_rider_count_model.dart';

class RiderCountsRepository {
  final SupabaseClient _client = SupabaseService.client;

  Future<List<StationRiderCountModel>> getAssignedStationRiderCounts({
    required DateTime targetDate,
  }) async {
    final assigned = await _client.rpc('get_supervisor_assigned_line_ids');
    final lineIds = (assigned as List<dynamic>)
        .map((row) => row['line_id'] as String)
        .toSet()
        .toList();
    if (lineIds.isEmpty) return const [];

    final results = await Future.wait(lineIds.map((lineId) =>
        getStationRiderCounts(lineId: lineId, targetDate: targetDate)));
    return results.expand((counts) => counts).toList()
      ..sort((a, b) {
        final byLine = a.lineName.compareTo(b.lineName);
        return byLine != 0 ? byLine : a.orderIndex.compareTo(b.orderIndex);
      });
  }

  /// Fetch live rider counts per station for a specific line and date (Today or Tomorrow)
  Future<List<StationRiderCountModel>> getStationRiderCounts({
    required String lineId,
    required DateTime targetDate,
  }) async {
    final dateStr = targetDate.toIso8601String().substring(0, 10);

    final response = await _client.rpc(
      SupabaseRpcs.getLineRiderCounts,
      params: {
        'p_line_id': lineId,
        'p_ride_date': dateStr,
      },
    );

    return (response as List<dynamic>)
        .map((e) => StationRiderCountModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
