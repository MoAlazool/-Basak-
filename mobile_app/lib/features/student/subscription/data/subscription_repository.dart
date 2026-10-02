import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_config.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/subscription_model.dart';

class SubscriptionRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Get current active or pending subscription for the logged-in student
  Future<SubscriptionModel?> getCurrentSubscription() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final response = await _client
        .from(SupabaseTables.subscriptions)
        .select('''
          *,
          lines(name, supervisors(full_name, phone)),
          stations(name, departure_times, return_times),
          line_university_schedules(departure_time, return_time, universities(name))
        ''')
        .eq('student_id', user.id)
        .inFilter('status',
            ['pending_payment', 'pending_review', 'active', 'rejected'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return SubscriptionModel.fromJson(response);
  }

  /// Create a new subscription
  /// If daily: cash-only, active immediately for today
  /// If termly / yearly: pending_payment until receipt uploaded & approved
  Future<SubscriptionModel> createSubscription({
    required String lineId,
    required String stationId,
    required String departureTime,
    required String returnTime,
    required String type, // termly | yearly | daily
    required double price,
    String? scheduleId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل.');

    final isDaily = type == 'daily';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final inserted = await _client.from(SupabaseTables.subscriptions).insert({
      'student_id': user.id,
      'line_id': lineId,
      'station_id': stationId,
      if (scheduleId != null) 'schedule_id': scheduleId,
      'departure_time': departureTime,
      'return_time': returnTime,
      'type': type,
      'price': price,
      'status': isDaily ? 'active' : 'pending_payment',
      'start_date': isDaily ? today : null,
      'end_date': isDaily ? today : null,
    }).select('''
          *,
          lines(name, supervisors(full_name, phone)),
          stations(name, departure_times, return_times),
          line_university_schedules(departure_time, return_time, universities(name))
        ''').single();

    return SubscriptionModel.fromJson(inserted);
  }

  /// Upload receipt photo to Supabase Storage and insert receipt record
  Future<ReceiptModel> uploadReceipt({
    required String subscriptionId,
    required Uint8List fileBytes,
    required String fileExtension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل.');

    final previousReceipts = await getReceiptsHistory(subscriptionId);
    if (previousReceipts.length >= 5) {
      throw Exception(
          'تم استخدام المحاولات الخمس لرفع الإيصال. تواصل مع الإدارة للمساعدة.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath =
        '${user.id}/${subscriptionId}_$timestamp.$fileExtension';
    final contentType = fileExtension.toLowerCase() == 'jpg' ||
            fileExtension.toLowerCase() == 'jpeg'
        ? 'image/jpeg'
        : 'image/${fileExtension.toLowerCase()}';

    // 1. Upload file to Storage private bucket
    await _client.storage.from(SupabaseConfig.receiptsBucket).uploadBinary(
          storagePath,
          fileBytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    // 2. Insert receipt row into receipts table
    // (Database trigger handles attempt_number calculation and updates subscription status)
    final inserted = await _client
        .from(SupabaseTables.receipts)
        .insert({
          'subscription_id': subscriptionId,
          'image_url': storagePath,
          'status': 'pending',
        })
        .select()
        .single();

    return ReceiptModel.fromJson(inserted);
  }

  /// Get receipts history for a subscription
  Future<List<ReceiptModel>> getReceiptsHistory(String subscriptionId) async {
    final response = await _client
        .from(SupabaseTables.receipts)
        .select()
        .eq('subscription_id', subscriptionId)
        .order('attempt_number', ascending: false);

    return (response as List<dynamic>)
        .map((e) => ReceiptModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
