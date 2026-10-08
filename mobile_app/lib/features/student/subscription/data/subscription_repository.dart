import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_config.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';
import '../models/subscription_model.dart';
import '../models/payment_method_model.dart';
import '../models/sale_catalog.dart';

class SubscriptionRepository {
  final SupabaseClient _client = SupabaseService.client;

  // period_label / period_phase are computed by the database from academic_terms.
  static const _select = '''
          *, period_label, period_phase,
          lines(name, companies(name), supervisors(*), line_trips(direction, is_active, start_time)),
          student:students(university),
          stations(name, departure_times, return_times,
            line_trip_stops(stop_time, line_trips(direction, is_active, start_time))),
          departure_trip:departure_trip_id(label, start_time, universities(name)),
          return_trip:return_trip_id(start_time)
        ''';

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Every subscription of the signed-in student: current, upcoming (paid in
  /// advance or awaiting payment) and expired, newest period first.
  Future<List<SubscriptionModel>> getSubscriptions() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await OfflineCache.readThrough(
        'subscriptions',
        () => _client
            .from(SupabaseTables.subscriptions)
            .select(_select)
            .eq('student_id', user.id)
            .order('start_date', ascending: false, nullsFirst: false)
            .order('created_at', ascending: false));
    return (response as List<dynamic>)
        .map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The subscription that matters now: the one running today, otherwise the
  /// next upcoming one. Expired subscriptions are history only.
  Future<SubscriptionModel?> getCurrentSubscription() async {
    final json = await getCurrentSubscriptionJson();
    return json == null ? null : SubscriptionModel.fromJson(json);
  }

  /// [getCurrentSubscription] as the server sent it, so it can be saved for the next start.
  Future<Map<String, dynamic>?> getCurrentSubscriptionJson() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final response = await OfflineCache.readThrough(
        'subscriptions.current',
        () => _client
            .from(SupabaseTables.subscriptions)
            .select(_select)
            .eq('student_id', user.id)
            .inFilter('status',
                ['pending_payment', 'pending_review', 'active', 'rejected'])
            .or('end_date.is.null,end_date.gte.${_today()}')
            .order('start_date', ascending: true)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle());
    return response == null ? null : Map<String, dynamic>.from(response as Map);
  }

  /// Companies, lines, stations with their trip times, and the options on
  /// sale with their prices, for the signed-in student's university.
  Future<SaleCatalog> getSaleCatalog() async {
    final response = await OfflineCache.readThrough(
        'sale_catalog', () => _client.rpc(SupabaseRpcs.getSubscriptionCatalog));
    return SaleCatalog.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// The receipt issued when [subscriptionId] was approved, if any.
  Future<SubscriptionReceipt?> getSubscriptionReceipt(String subscriptionId) async {
    final row = await OfflineCache.readThrough(
        'subscription_receipt.$subscriptionId',
        () => _client
            .from('subscription_receipts')
            .select()
            .eq('subscription_id', subscriptionId)
            .maybeSingle());
    return row == null
        ? null
        : SubscriptionReceipt.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Create a subscription. Status, dates and price are set by the database:
  /// daily = cash on the bus, active for the next ride; termly / yearly =
  /// pending_payment for the chosen period until a receipt is approved.
  Future<SubscriptionModel> createSubscription({
    required String lineId,
    required String stationId,
    required String departureTime,
    String? returnTime,
    required String type, // termly | yearly | daily
    required double price,
    String? departureTripId,
    String? returnTripId,
    String? periodCode,
    int? academicYear,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل.');

    try {
      final inserted = await requireOnline(
          () => _client.from(SupabaseTables.subscriptions).insert({
        'student_id': user.id,
        'line_id': lineId,
        'station_id': stationId,
        // The database validates the trips (station + university) and owns the times.
        if (departureTripId != null) 'departure_trip_id': departureTripId,
        if (returnTripId != null) 'return_trip_id': returnTripId,
        'departure_time': departureTime,
        'return_time': returnTime,
        'type': type,
        'price': price,
        if (type != 'daily' && periodCode != null) 'period_code': periodCode,
        if (type != 'daily' && academicYear != null) 'academic_year': academicYear,
      }).select(_select).single());
      return SubscriptionModel.fromJson(inserted);
    } on PostgrestException catch (error) {
      // Messages raised by the database triggers are already in Arabic.
      throw Exception(error.message);
    }
  }

  /// Upload receipt photo to Supabase Storage and insert receipt record
  /// Active payment methods of the subscription's company (managed by the
  /// company in the dashboard; never hardcoded in the app).
  Future<List<PaymentMethodModel>> getPaymentMethods(String companyId) async {
    final rows = await OfflineCache.readThrough(
        'payment_methods.$companyId',
        () => _client
            .from('company_payment_methods')
            .select()
            .eq('company_id', companyId)
            .eq('is_active', true)
            .order('sort_order')
            .order('created_at'));
    return (rows as List<dynamic>)
        .map((e) => PaymentMethodModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ReceiptModel> uploadReceipt({
    required String subscriptionId,
    required Uint8List fileBytes,
    required String fileExtension,
    String? paymentMethodId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل.');

    // Fresh from the server: the attempt limit must not be judged on saved data.
    final previousReceipts = await requireOnline(() => _client
        .from(SupabaseTables.receipts)
        .select('id')
        .eq('subscription_id', subscriptionId));
    if (previousReceipts.length >= 5) {
      throw Exception(
          'تم استخدام المحاولات الخمس لرفع الإيصال. تواصل مع الإدارة للمساعدة.');
    }

    final ext = fileExtension.toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // receipts/{student_id}/{subscription_id}_{timestamp}.{ext} — the database
    // and the storage policies rely on this exact layout.
    final storagePath = '${user.id}/${subscriptionId}_$timestamp.$ext';
    final contentType =
        ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/$ext';

    // 1. Upload to the private bucket. No upsert: a submitted receipt must never
    // be replaced (students have no UPDATE permission on receipt images).
    await requireOnline(() =>
        _client.storage.from(SupabaseConfig.receiptsBucket).uploadBinary(
              storagePath,
              fileBytes,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            ));

    // 2. Insert receipt row (trigger sets attempt number, amount, pending_review).
    try {
      final inserted = await requireOnline(() => _client
          .from(SupabaseTables.receipts)
          .insert({
            'subscription_id': subscriptionId,
            'image_url': storagePath,
            if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
            'status': 'pending',
          })
          .select()
          .single());
      return ReceiptModel.fromJson(inserted);
    } on PostgrestException catch (error) {
      try {
        await _client.storage
            .from(SupabaseConfig.receiptsBucket)
            .remove([storagePath]);
      } catch (_) {
        // Orphaned images are harmless: only the owner and admins can read them.
      }
      throw Exception(error.message);
    }
  }

  /// Get receipts history for a subscription
  Future<List<ReceiptModel>> getReceiptsHistory(String subscriptionId) async {
    final response = await OfflineCache.readThrough(
        'receipts.$subscriptionId',
        () => _client
            .from(SupabaseTables.receipts)
            .select()
            .eq('subscription_id', subscriptionId)
            .order('attempt_number', ascending: false));

    return (response as List<dynamic>)
        .map((e) => ReceiptModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
