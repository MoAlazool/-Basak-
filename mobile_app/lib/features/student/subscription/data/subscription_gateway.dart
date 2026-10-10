import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_config.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/perf_trace.dart';
import '../../../../core/network/supabase_service.dart';
import 'receipt_image_upload.dart';

/// Every request the subscription screens make, one method per request, so
/// the repository's rules can be tested (and its requests counted) without a
/// server.
abstract class SubscriptionGateway {
  String? get userId;
  Future<List<dynamic>> subscriptions(String userId);
  Future<Map<String, dynamic>?> currentSubscription(String userId, String today);
  Future<dynamic> saleCatalog();
  Future<Map<String, dynamic>?> receiptDoc(String subscriptionId);
  Future<Map<String, dynamic>> insertSubscription(Map<String, dynamic> row);
  Future<List<dynamic>> paymentMethods(String companyId);
  Future<List<dynamic>> receipts(String subscriptionId);

  /// Stores the image at [path], replacing what an earlier try of the same
  /// submission left there. [onProgress] is told how much has been sent, when
  /// that can be known.
  Future<void> uploadReceiptImage(String path, Uint8List bytes, {void Function(int sent, int total)? onProgress});
  Future<Map<String, dynamic>> insertReceipt(Map<String, dynamic> row);
  Future<void> removeReceiptImage(String path);

  /// The receipt whose image is [path], if one was saved.
  Future<Map<String, dynamic>?> receiptByPath(String path);
}

/// What ReceiptModel reads.
const receiptColumns =
    'id, subscription_id, image_url, status, rejection_reason, attempt_number, reviewed_by, created_at, reviewed_at, '
    'payment_method_id';

class SupabaseSubscriptionGateway implements SubscriptionGateway {
  const SupabaseSubscriptionGateway();

  SupabaseClient get _client => SupabaseService.client;

  // period_label / period_phase are computed by the database from academic_terms.
  // Only what SubscriptionModel reads.
  static const _select = '''
          id, student_id, line_id, company_id, station_id, type, status, start_date, end_date, price, created_at,
          departure_time, return_time, period_code, academic_year, period_label, period_phase,
          lines(name, companies(id, name, logo_path, emblem_path), supervisors(full_name, phone, profile_image_url),
            line_trips(direction, is_active, start_time)),
          student:students(university),
          stations(name, departure_times, return_times,
            line_trip_stops(stop_time, line_trips(direction, is_active, start_time))),
          departure_trip:departure_trip_id(label, start_time, universities(name)),
          return_trip:return_trip_id(start_time)
        ''';

  /// The same read for a database that does not have the branding columns
  /// yet: the company by its name alone, as before.
  static final _selectWithoutBrand =
      _select.replaceFirst('companies(id, name, logo_path, emblem_path)', 'companies(name)');

  /// Runs [read] with the branding columns; where the database does not know
  /// them (an unknown column: nothing was read or written), runs it again
  /// without. A subscription is never held back for a logo.
  static Future<T> _branded<T>(Future<T> Function(String select) read) async {
    try {
      return await read(_select);
    } on PostgrestException catch (error) {
      if (!isUnknownColumn(error.code, error.message)) rethrow;
      return read(_selectWithoutBrand);
    }
  }

  /// Postgres' 42703 (PostgREST passes it on), or its words.
  static bool isUnknownColumn(String? code, String message) =>
      code == '42703' || (message.contains('column') && message.contains('does not exist'));

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<List<dynamic>> subscriptions(String userId) {
    PerfTrace.count('subscriptions.all');
    return _branded((select) => _client
        .from(SupabaseTables.subscriptions)
        .select(select)
        .eq('student_id', userId)
        .order('start_date', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false));
  }

  @override
  Future<Map<String, dynamic>?> currentSubscription(String userId, String today) {
    PerfTrace.count('subscriptions.current');
    return _branded((select) => _client
        .from(SupabaseTables.subscriptions)
        .select(select)
        .eq('student_id', userId)
        .inFilter('status', ['pending_payment', 'pending_review', 'active', 'rejected'])
        .or('end_date.is.null,end_date.gte.$today')
        .order('start_date', ascending: true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle());
  }

  @override
  Future<dynamic> saleCatalog() {
    PerfTrace.count('sale_catalog');
    return _client.rpc(SupabaseRpcs.getSubscriptionCatalog);
  }

  @override
  Future<Map<String, dynamic>?> receiptDoc(String subscriptionId) {
    PerfTrace.count('subscription_receipt');
    return _client
        .from('subscription_receipts')
        // Every column a student may read (the running number is not one).
        .select('subscription_id, receipt_code, company_name, student_name, student_phone, university_name, '
            'line_name, station_name, period_label, start_date, end_date, amount, payment_method, approved_at, '
            'company_phone, company_address, company_commercial_register, company_tax_number, company_logo_path')
        .eq('subscription_id', subscriptionId)
        .maybeSingle();
  }

  @override
  Future<Map<String, dynamic>> insertSubscription(Map<String, dynamic> row) {
    PerfTrace.count('subscriptions.insert');
    return _branded((select) => _client.from(SupabaseTables.subscriptions).insert(row).select(select).single());
  }

  @override
  Future<List<dynamic>> paymentMethods(String companyId) {
    PerfTrace.count('payment_methods');
    return _client
        .from('company_payment_methods')
        .select('id, method_type, display_name, account_holder, instapay_address, wallet_phone, bank_name, '
            'bank_account_number, iban, instructions')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('sort_order')
        .order('created_at');
  }

  @override
  Future<List<dynamic>> receipts(String subscriptionId) {
    PerfTrace.count('receipts.list');
    return _client
        .from(SupabaseTables.receipts)
        .select(receiptColumns)
        .eq('subscription_id', subscriptionId)
        .order('attempt_number', ascending: false);
  }

  @override
  Future<void> uploadReceiptImage(String path, Uint8List bytes, {void Function(int sent, int total)? onProgress}) {
    PerfTrace.count('receipts.upload');
    return ReceiptImageUpload(_client).send(path, bytes, onProgress: onProgress);
  }

  @override
  Future<Map<String, dynamic>> insertReceipt(Map<String, dynamic> row) {
    PerfTrace.count('receipts.insert');
    return _client.from(SupabaseTables.receipts).insert(row).select(receiptColumns).single();
  }

  @override
  Future<void> removeReceiptImage(String path) async {
    PerfTrace.count('receipts.remove_image');
    await _client.storage.from(SupabaseConfig.receiptsBucket).remove([path]);
  }

  @override
  Future<Map<String, dynamic>?> receiptByPath(String path) {
    PerfTrace.count('receipts.by_path');
    return _client.from(SupabaseTables.receipts).select(receiptColumns).eq('image_url', path).limit(1).maybeSingle();
  }
}
