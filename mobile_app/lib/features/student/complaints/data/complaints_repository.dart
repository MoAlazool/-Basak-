import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';

class ComplaintModel {
  final String id;
  final String studentId;
  final String title;
  final String message;
  final String status;
  final String createdAt;

  ComplaintModel({
    required this.id,
    required this.studentId,
    required this.title,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  factory ComplaintModel.fromJson(Map<String, dynamic> json) {
    return ComplaintModel(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}

class ComplaintsRepository {
  final SupabaseClient _client = SupabaseService.client;

  Future<void> submitComplaint({
    required String title,
    required String message,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل.');

    await requireOnline(() => _client.from(SupabaseTables.complaints).insert({
          'student_id': user.id,
          'title': title.trim(),
          'message': message.trim(),
        }));
  }

  Future<List<ComplaintModel>> getMyComplaints() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final response = await OfflineCache.readThrough(
        'complaints',
        () => _client
            .from(SupabaseTables.complaints)
            .select('id, student_id, title, message, status, created_at')
            .eq('student_id', user.id)
            .order('created_at', ascending: false));

    return (response as List<dynamic>)
        .map((e) => ComplaintModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
