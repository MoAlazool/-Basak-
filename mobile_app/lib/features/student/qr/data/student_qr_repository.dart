import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';

class StudentQrRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Fetch student static QR code value
  Future<String?> getStudentQrCode() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final response = await _client
        .from(SupabaseTables.students)
        .select('qr_code_value')
        .eq('id', user.id)
        .maybeSingle();

    return response?['qr_code_value'] as String?;
  }
}
