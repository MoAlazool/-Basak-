import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';

class SupervisorReceiptsRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Fetch pending receipts waiting for supervisor review
  Future<List<Map<String, dynamic>>> getPendingReceiptsQueue() async {
    final response = await _client.from(SupabaseTables.receipts).select('''
          *,
          subscriptions(
            id, type, price, created_at,
            students(full_name, phone, university),
            lines(name),
            stations(name)
          )
        ''').eq('status', 'pending').order('created_at', ascending: true);

    final receipts = List<Map<String, dynamic>>.from(response);
    if (receipts.isEmpty) return receipts;
    final paths =
        receipts.map((receipt) => receipt['image_url'] as String).toList();
    final signed =
        await _client.storage.from('receipts').createSignedUrls(paths, 600);
    for (var i = 0; i < receipts.length; i++) {
      receipts[i]['signed_image_url'] = signed[i].signedUrl;
    }
    return receipts;
  }

  /// Approve receipt: Sets receipt status to 'approved'
  /// (DB trigger automatically activates subscription and sets start/end dates)
  Future<void> approveReceipt(String receiptId) async {
    final updated = await _client
        .from(SupabaseTables.receipts)
        .update({
          'status': 'approved',
        })
        .eq('id', receiptId)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw Exception(
          'لم يتم اعتماد الإيصال. تحقق من صلاحية الخط ثم أعد المحاولة.');
    }
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

    final updated = await _client
        .from(SupabaseTables.receipts)
        .update({
          'status': 'rejected',
          'rejection_reason': cleanReason,
        })
        .eq('id', receiptId)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw Exception(
          'لم يتم رفض الإيصال. تحقق من صلاحية الخط ثم أعد المحاولة.');
    }
  }
}
