import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/line_model.dart';

class LinesRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// 1. Sees a list of all lines across all companies
  Future<List<LineModel>> getAllLines() async {
    final response = await _client
        .from(SupabaseTables.lines)
        .select('*, companies(name)')
        .eq('is_active', true)
        .order('name');

    return (response as List<dynamic>)
        .map((e) => LineModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 2. Picks a line -> sees that line's list of pickup stations ordered by order_index
  Future<List<StationModel>> getStationsForLine(String lineId) async {
    final response = await _client
        .from(SupabaseTables.stations)
        .select()
        .eq('line_id', lineId)
        .order('order_index');

    return (response as List<dynamic>)
        .map((e) => StationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
