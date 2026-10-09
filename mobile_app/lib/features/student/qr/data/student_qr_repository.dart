import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/perf_trace.dart';
import '../../../../core/storage/offline_cache.dart';

class StudentPassDetails {
  final String? qrValue;
  final String? fullName;
  final String? phone;
  final String? university;
  final String? college;

  /// Where the photo is stored ('student-avatars'). A link to it is signed
  /// when it is shown (see SignedUrlCache), never saved.
  final String? profileImagePath;
  final String? lineName;
  final String? stationName;
  final String? subscriptionId;
  final String? subscriptionType;
  final String? subscriptionStatus;
  final String? paymentDate;
  final bool isOfflineCache;

  const StudentPassDetails(
      {this.qrValue,
      this.fullName,
      this.phone,
      this.university,
      this.college,
      this.profileImagePath,
      this.lineName,
      this.stationName,
      this.subscriptionId,
      this.subscriptionType,
      this.subscriptionStatus,
      this.paymentDate,
      this.isOfflineCache = false});

  /// What is saved on the device. It holds only what the server said (no
  /// links, no time stamps), so an unchanged pass compares as unchanged.
  Map<String, dynamic> toCacheJson() => {
        'qr_value': qrValue,
        'full_name': fullName,
        'phone': phone,
        'university': university,
        'college': college,
        'profile_image_path': profileImagePath,
        'line_name': lineName,
        'station_name': stationName,
        'subscription_id': subscriptionId,
        'subscription_type': subscriptionType,
        'subscription_status': subscriptionStatus,
        'payment_date': paymentDate,
      };

  factory StudentPassDetails.fromCache(Map<String, dynamic> json, {bool isOfflineCache = true}) =>
      StudentPassDetails(
        qrValue: json['qr_value'] as String?,
        fullName: json['full_name'] as String?,
        phone: json['phone'] as String?,
        university: json['university'] as String?,
        college: json['college'] as String?,
        profileImagePath: json['profile_image_path'] as String?,
        lineName: json['line_name'] as String?,
        stationName: json['station_name'] as String?,
        subscriptionId: json['subscription_id'] as String?,
        subscriptionType: json['subscription_type'] as String?,
        subscriptionStatus: json['subscription_status'] as String?,
        paymentDate: json['payment_date'] as String?,
        isOfflineCache: isOfflineCache,
      );
}

/// The requests behind the student pass, one method each (see SubscriptionGateway).
abstract class StudentPassGateway {
  String? get userId;
  Future<Map<String, dynamic>?> studentRow(String userId);
  Future<Map<String, dynamic>?> subscriptionRow(String userId, String today);
  void refreshWalletCard();
}

class SupabaseStudentPassGateway implements StudentPassGateway {
  const SupabaseStudentPassGateway();

  SupabaseClient get _client => SupabaseService.client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<Map<String, dynamic>?> studentRow(String userId) {
    PerfTrace.count('pass.student');
    return _client
        .from(SupabaseTables.students)
        .select('qr_code_value, full_name, phone, university, college, profile_image_url')
        .eq('id', userId)
        .maybeSingle();
  }

  @override
  Future<Map<String, dynamic>?> subscriptionRow(String userId, String today) async {
    PerfTrace.count('pass.subscription');
    // Awaited here so the request is sent exactly once (a Postgrest builder
    // re-sends for every listener).
    return await _client
        .from(SupabaseTables.subscriptions)
        .select('''
            id, type, status, departure_time, return_time,
            lines(name), stations(name)
          ''')
        .eq('student_id', userId)
        .inFilter('status', ['pending_payment', 'pending_review', 'active', 'rejected'])
        // The subscription running today first, then the next upcoming one.
        .or('end_date.is.null,end_date.gte.$today')
        .order('start_date', ascending: true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  /// A subscription can start or end by date alone, which nothing on the
  /// server notices. Opening this screen is a good moment to ask the server
  /// to bring the student's Wallet card up to date; it does nothing when the
  /// card is already right or the student has none. Never blocks the screen.
  @override
  void refreshWalletCard() {
    PerfTrace.count('pass.wallet_refresh');
    _client.rpc(SupabaseRpcs.walletRefreshMyCard).then((_) {}, onError: (_) {});
  }
}

class StudentQrRepository {
  final StudentPassGateway _gateway;

  StudentQrRepository({StudentPassGateway? gateway}) : _gateway = gateway ?? const SupabaseStudentPassGateway();

  /// The student's card and QR code. It never waits for the network when it
  /// has been shown before: the saved pass appears at once and is checked with
  /// the server behind it (see [OfflineCache.readThrough]).
  Future<StudentPassDetails?> getStudentPassDetails() async {
    final userId = _gateway.userId;
    if (userId == null) return null;

    try {
      final json = await OfflineCache.readThrough('student_pass', () async {
        final details = await _fetchPass(userId);
        if (details == null) return null;
        final saved = details.toCacheJson();
        // Kept under its own key too: the pass must survive anything else failing.
        await OfflineCache.saveStudentPass(saved);
        _gateway.refreshWalletCard();
        return saved;
      });
      if (json == null) return null;
      return StudentPassDetails.fromCache(Map<String, dynamic>.from(json as Map),
          isOfflineCache: OfflineCache.offlineSince.value != null);
    } catch (error) {
      // Only an unreachable server falls back to the saved pass; a refused or
      // deleted account must not keep showing a valid-looking QR.
      if (!isNetworkFailure(error)) rethrow;
      final cached = await OfflineCache.readStudentPass();
      if (cached != null && (cached['qr_value'] as String?)?.isNotEmpty == true) {
        final pass = StudentPassDetails.fromCache(cached);
        OfflineCache.markOffline(DateTime.tryParse(cached['_saved_at'] as String? ?? ''));
        return pass;
      }
      rethrow;
    }
  }

  Future<StudentPassDetails?> _fetchPass(String userId) async {
      // Independent of the student row: runs alongside it instead of after it.
      final subscriptionFuture =
          _gateway.subscriptionRow(userId, DateTime.now().toIso8601String().substring(0, 10));
      // Never left unawaited with an error if the student query fails first.
      subscriptionFuture.ignore();
      final response = await _gateway.studentRow(userId);

      if (response == null) return null;
      final subscription = await subscriptionFuture;
      final line = subscription?['lines'] as Map<String, dynamic>?;
      final station = subscription?['stations'] as Map<String, dynamic>?;
      final details = StudentPassDetails(
        qrValue: response['qr_code_value'] as String?,
        fullName: response['full_name'] as String?,
        phone: response['phone'] as String?,
        university: response['university'] as String?,
        college: response['college'] as String?,
        profileImagePath: (response['profile_image_url'] as String?)?.trim().isEmpty ?? true
            ? null
            : response['profile_image_url'] as String,
        lineName: line?['name'] as String?,
        stationName: station?['name'] as String?,
        subscriptionId: subscription?['id'] as String?,
        subscriptionType: subscription?['type'] as String?,
        subscriptionStatus: subscription?['status'] as String?,
      );
      return details;
  }
}
