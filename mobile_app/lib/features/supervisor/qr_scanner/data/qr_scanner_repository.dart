import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/scanned_student_details.dart';

class QrScannerRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Scan QR to LOOK UP student details only.
  /// Strictly does NOT write any attendance record.
  Future<ScannedStudentDetails> lookupStudentByQr(String qrCodeUuid) async {
    final response = await _client.rpc(
      SupabaseRpcs.lookupStudentByQr,
      params: {
        'p_qr_code': qrCodeUuid.trim(),
      },
    );

    if (response == null) {
      throw Exception('لم يتم العثور على بيانات الطالب لهذا الرمز.');
    }

    return ScannedStudentDetails.fromJson(Map<String, dynamic>.from(response));
  }
}
