import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';

class SupervisorReceiptsRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Fetch pending receipts waiting for supervisor review
  Future<List<Map<String, dynamic>>> getPendingReceiptsQueue() async {
    final response = await _client
        .from(SupabaseTables.receipts)
        .select('''
          *,
          subscriptions(
            id, type, price, created_at,
            students(full_name, phone, university),
            lines(name),
            stations(name)
          )
        ''')
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Approve receipt: Sets receipt status to 'approved'
  /// (DB trigger automatically activates subscription and sets start/end dates)
  Future<void> approveReceipt(String receiptId) async {
    await _client.from(SupabaseTables.receipts).update({
      'status': 'approved',
    }).eq('id', receiptId);
  }

  /// Reject receipt: Sets receipt status to 'rejected'
  /// MANDATORY: written rejection reason is strictly enforced by DB constraint
  Future<void> rejectReceipt({
    required String receiptId,
    required String rejectionReason,
  }) async {
    final cleanReason = rejectionReason.trim();
    if (cleanReason.isEmpty) {
      throw Exception('سبب الرفض إلزامي ولا يمكن تركه فارغاً.');
    }

    await _client.from(SupabaseTables.receipts).update({
      'status': 'rejected',
      'rejection_reason': cleanReason,
    }).eq('id', receiptId);
  }
}
