import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/line_model.dart';

class LinesRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// 1. Lines the student can subscribe to: lines without university schedules,
  /// plus lines that serve the student's own university (with that trip time).
  Future<List<LineModel>> getAllLines() async {
    final response = await _client
        .from(SupabaseTables.lines)
        .select('*, companies(name)')
        .eq('is_active', true)
        .order('name');
    final options = await _client.rpc(SupabaseRpcs.getStudentLineOptions);
    final optionsByLine = {
      for (final row in options as List<dynamic>)
        (row as Map<String, dynamic>)['line_id'] as String: row,
    };

    return (response as List<dynamic>)
        .map((e) => LineModel.fromJson(e as Map<String, dynamic>))
        .where((line) => optionsByLine.containsKey(line.id))
        .map((line) => line.withStudentOption(optionsByLine[line.id]!))
        .toList();
  }

  /// 2. Picks a line -> sees that line's list of pickup stations ordered by order_index
  Future<List<StationModel>> getStationsForLine(String lineId) async {
    final response = await _client
        .from(SupabaseTables.stations)
        .select()
        .eq('line_id', lineId)
        .eq('is_active', true)
        .order('order_index');

    return (response as List<dynamic>)
        .map((e) => StationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
