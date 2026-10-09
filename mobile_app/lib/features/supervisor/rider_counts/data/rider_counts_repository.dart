import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';
import '../models/station_rider_count_model.dart';

/// The requests behind the rider counts, one method each (replaced in tests).
abstract class RiderCountsGateway {
  /// The supervisor's lines: rows of `{line_id}`.
  Future<dynamic> assignedLineIds();

  /// The counts of every line in [lineIds] on [date], in one request: an
  /// object `{line id: that line's rows}`. Throws [LinesRiderCountsUnavailable]
  /// when the database has no such function yet.
  Future<dynamic> countsForLines(List<String> lineIds, String date);

  /// The counts of one line on [date] (what [countsForLines] holds per line).
  Future<dynamic> countsForLine(String lineId, String date);
}

/// The database is older than `get_lines_rider_counts`.
class LinesRiderCountsUnavailable implements Exception {
  const LinesRiderCountsUnavailable();
}

class SupabaseRiderCountsGateway implements RiderCountsGateway {
  const SupabaseRiderCountsGateway();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<dynamic> assignedLineIds() => _client.rpc('get_supervisor_assigned_line_ids');

  @override
  Future<dynamic> countsForLines(List<String> lineIds, String date) async {
    try {
      return await _client
          .rpc(SupabaseRpcs.getLinesRiderCounts, params: {'p_line_ids': lineIds, 'p_ride_date': date});
    } on PostgrestException catch (error) {
      // PGRST202: not in the schema cache; 42883: undefined function.
      if (error.code == 'PGRST202' || error.code == '42883' || error.code == '404') {
        throw const LinesRiderCountsUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<dynamic> countsForLine(String lineId, String date) =>
      _client.rpc(SupabaseRpcs.getLineRiderCounts, params: {'p_line_id': lineId, 'p_ride_date': date});
}

class RiderCountsRepository {
  final RiderCountsGateway _gateway;

  /// Asked once per run of the app, not on every refresh.
  bool _batchMissing = false;

  RiderCountsRepository({RiderCountsGateway? gateway}) : _gateway = gateway ?? const SupabaseRiderCountsGateway();

  /// Live rider counts per station on [targetDate], for every line of the
  /// supervisor, in one request.
  ///
  /// [lineIds] are the supervisor's lines when the caller already knows them
  /// (the dashboard lists them); otherwise they are asked for first. On a
  /// database without `get_lines_rider_counts` the lines are read one by one,
  /// side by side, as before.
  Future<List<StationRiderCountModel>> getAssignedStationRiderCounts({
    required DateTime targetDate,
    List<String>? lineIds,
  }) async {
    final ids = (lineIds ?? await _assignedLineIds()).toSet().toList()..sort();
    if (ids.isEmpty) return const [];
    final date = targetDate.toIso8601String().substring(0, 10);

    final byLine = await OfflineCache.readThrough('rider_counts.$date.${ids.join(',')}', () => _fetch(ids, date));
    return [
      for (final rows in (byLine as Map).values)
        for (final row in rows as List? ?? const [])
          StationRiderCountModel.fromJson(Map<String, dynamic>.from(row as Map)),
    ]..sort((a, b) {
        final byName = a.lineName.compareTo(b.lineName);
        return byName != 0 ? byName : a.orderIndex.compareTo(b.orderIndex);
      });
  }

  Future<List<String>> _assignedLineIds() async {
    final assigned = await OfflineCache.readThrough('supervisor.line_ids', _gateway.assignedLineIds);
    return [for (final row in assigned as List<dynamic>) row['line_id'] as String];
  }

  /// `{line id: rows}`, however the database can answer it.
  Future<Map<String, dynamic>> _fetch(List<String> ids, String date) async {
    if (!_batchMissing) {
      try {
        final response = await _gateway.countsForLines(ids, date);
        return {
          for (final entry in (response as Map? ?? const {}).entries) '${entry.key}': entry.value ?? const [],
        };
      } on LinesRiderCountsUnavailable {
        _batchMissing = true;
      }
    }
    final perLine = await Future.wait([for (final id in ids) _gateway.countsForLine(id, date)]);
    return {for (final (i, id) in ids.indexed) id: perLine[i] ?? const []};
  }
}
