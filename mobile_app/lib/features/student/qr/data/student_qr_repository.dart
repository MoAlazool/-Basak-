import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/storage/offline_cache.dart';

class StudentPassDetails {
  final String? qrValue;
  final String? fullName;
  final String? phone;
  final String? university;
  final String? college;
  final String? profileImageUrl;
  final String? lineName;
  final String? stationName;
  final String? subscriptionType;
  final String? subscriptionStatus;
  final String? paymentDate;
  final bool isOfflineCache;
  final String? cachedAt;

  const StudentPassDetails(
      {this.qrValue,
      this.fullName,
      this.phone,
      this.university,
      this.college,
      this.profileImageUrl,
      this.lineName,
      this.stationName,
      this.subscriptionType,
      this.subscriptionStatus,
      this.paymentDate,
      this.isOfflineCache = false,
      this.cachedAt});

  Map<String, dynamic> toCacheJson() => {
        'qr_value': qrValue,
        'full_name': fullName,
        'phone': phone,
        'university': university,
        'college': college,
        'line_name': lineName,
        'station_name': stationName,
        'subscription_type': subscriptionType,
        'subscription_status': subscriptionStatus,
        'payment_date': paymentDate,
        'cached_at': DateTime.now().toIso8601String(),
      };

  factory StudentPassDetails.fromCache(Map<String, dynamic> json) =>
      StudentPassDetails(
        qrValue: json['qr_value'] as String?,
        fullName: json['full_name'] as String?,
        phone: json['phone'] as String?,
        university: json['university'] as String?,
        college: json['college'] as String?,
        lineName: json['line_name'] as String?,
        stationName: json['station_name'] as String?,
        subscriptionType: json['subscription_type'] as String?,
        subscriptionStatus: json['subscription_status'] as String?,
        paymentDate: json['payment_date'] as String?,
        isOfflineCache: true,
        cachedAt: json['cached_at'] as String?,
      );
}

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

  Future<StudentPassDetails?> getStudentPassDetails() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _client
          .from(SupabaseTables.students)
          .select(
              'qr_code_value, full_name, phone, university, college, profile_image_url')
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) return null;
      String? profileImageUrl;
      final imagePath = response['profile_image_url'] as String?;
      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          final signed = await _client.storage
              .from('student-avatars')
              .createSignedUrl(imagePath, 600);
          profileImageUrl = signed;
        } catch (_) {
          // The QR and core pass details remain available if the image service
          // is offline or the avatar URL cannot be refreshed.
        }
      }

      final subscription = await _client
          .from(SupabaseTables.subscriptions)
          .select('''
            id, type, status, departure_time, return_time,
            lines(name), stations(name)
          ''')
          .eq('student_id', user.id)
          .inFilter('status', ['pending_payment', 'pending_review', 'active', 'rejected'])
          // The subscription running today first, then the next upcoming one.
          .or('end_date.is.null,end_date.gte.${DateTime.now().toIso8601String().substring(0, 10)}')
          .order('start_date', ascending: true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final line = subscription?['lines'] as Map<String, dynamic>?;
      final station = subscription?['stations'] as Map<String, dynamic>?;
      final details = StudentPassDetails(
        qrValue: response['qr_code_value'] as String?,
        fullName: response['full_name'] as String?,
        phone: response['phone'] as String?,
        university: response['university'] as String?,
        college: response['college'] as String?,
        profileImageUrl: profileImageUrl,
        lineName: line?['name'] as String?,
        stationName: station?['name'] as String?,
        subscriptionType: subscription?['type'] as String?,
        subscriptionStatus: subscription?['status'] as String?,
      );
      await OfflineCache.saveStudentPass(details.toCacheJson());
      return details;
    } catch (_) {
      final cached = await OfflineCache.readStudentPass();
      if (cached != null && (cached['qr_value'] as String?)?.isNotEmpty == true) {
        return StudentPassDetails.fromCache(cached);
      }
      rethrow;
    }
  }
}
