import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/line_model.dart';
import '../models/trip_model.dart';
import '../models/catalog_model.dart';

class LinesRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// 1. Lines the student can subscribe to: lines without university schedules,
  /// plus lines that serve the student's own university (with that trip time).
  Future<List<LineModel>> getAllLines() async {
    final response = await _client
        .from(SupabaseTables.lines)
        .select('*, companies(name), destination:destination_university_id(name)')
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

  /// Step 1–2 of the subscription flow: active companies → active lines that
  /// serve the student's university (server-filtered).
  Future<List<CatalogCompany>> getCatalog() async {
    final response = await _client.rpc(SupabaseRpcs.getStudentCatalog);
    return (response as List<dynamic>? ?? const [])
        .map((c) => CatalogCompany.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Trips of a line (both directions) that serve the student's university;
  /// RLS returns only those, with their stop times.
  Future<List<TripModel>> getTripsForLine(String lineId) async {
    final response = await _client
        .from('line_trips')
        .select('id, direction, label, start_time, arrival_time, universities(name), '
            'line_trip_stops(station_id, stop_time)')
        .eq('line_id', lineId)
        .eq('is_active', true)
        .order('start_time');
    return (response as List<dynamic>)
        .map((e) => TripModel.fromJson(e as Map<String, dynamic>))
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
