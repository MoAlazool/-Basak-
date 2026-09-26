import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/station_rider_count_model.dart';

class RiderCountsRepository {
  final SupabaseClient _client = SupabaseService.client;

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
