import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';
import '../models/scanned_student_details.dart';

class QrScannerRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Scan QR to LOOK UP student details only.
  /// Strictly does NOT write any attendance record.
  Future<ScannedStudentDetails> lookupStudentByQr(String qrCodeUuid) async {
    final qr = qrCodeUuid.trim();
    try {
      final response = await _client.rpc(
        SupabaseRpcs.lookupStudentByQr,
        params: {'p_qr_code': qr},
      );

      if (response == null) {
        throw Exception('لم يتم العثور على بيانات الطالب لهذا الرمز.');
      }
      final details = Map<String, dynamic>.from(response);
      final me = _client.auth.currentUser?.id;
      if (me != null) await OfflineCache.saveStudentLookup(me, qr, details);
      return ScannedStudentDetails.fromJson(details);
    } catch (error) {
      if (!isNetworkFailure(error)) rethrow;
      final me = _client.auth.currentUser?.id;
      final cached = me == null ? null : await OfflineCache.readStudentLookup(me, qr);
      if (cached != null) {
        return ScannedStudentDetails.fromJson(cached, isOfflineCache: true);
      }
      rethrow;
    }
  }
}
