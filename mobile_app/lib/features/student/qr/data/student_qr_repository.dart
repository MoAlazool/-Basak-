import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/media/company_brand.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/perf_trace.dart';
import '../../../../core/storage/offline_cache.dart';
import '../../subscription/models/subscription_model.dart';

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

  /// current | upcoming | expired, as the server dated the subscription's period.
  final String? periodPhase;

  /// "الفصل الأول": the period without its year.
  final String? periodName;
  final int? academicYear;
  final String? startDate;
  final String? endDate;
  final String? companyName;

  /// The company's logo and emblem (none in a pass saved before they were read).
  final CompanyBrand companyBrand;

  /// The return trip's start time behind each return stop time (see
  /// SubscriptionModel.returnStartTimes): the time a student is shown.
  final Map<String, String> returnStartTimes;
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
      this.periodPhase,
      this.periodName,
      this.academicYear,
      this.startDate,
      this.endDate,
      this.companyName,
      this.companyBrand = CompanyBrand.none,
      this.returnStartTimes = const {},
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
        'period_phase': periodPhase,
        'period_name': periodName,
        'academic_year': academicYear,
        'start_date': startDate,
        'end_date': endDate,
        'company_name': companyName,
        'company_logo_path': companyBrand.logoPath,
        'company_emblem_path': companyBrand.emblemPath,
        'return_start_times': returnStartTimes,
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
        periodPhase: json['period_phase'] as String?,
        periodName: json['period_name'] as String?,
        academicYear: (json['academic_year'] as num?)?.toInt(),
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        companyName: json['company_name'] as String?,
        companyBrand: CompanyBrand(
          logoPath: json['company_logo_path'] as String?,
          emblemPath: json['company_emblem_path'] as String?,
        ),
        returnStartTimes: {
          for (final entry in (json['return_start_times'] as Map? ?? const {}).entries)
            entry.key.toString(): entry.value.toString(),
        },
        isOfflineCache: isOfflineCache,
      );
}

/// What the pass asks of the server itself (replaced in tests). Everything it
/// shows is read by other screens already: the student's own row (the profile)
/// and the current subscription (the home screen).
abstract class StudentPassGateway {
  String? get userId;

  /// A subscription can start or end by date alone, which nothing on the
  /// server notices. Showing the card is a good moment to ask the server to
  /// bring the student's Wallet card up to date; it does nothing when the card
  /// is already right or the student has none.
  Future<void> refreshWalletCard();
}

class SupabaseStudentPassGateway implements StudentPassGateway {
  const SupabaseStudentPassGateway();

  SupabaseClient get _client => SupabaseService.client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<void> refreshWalletCard() async {
    PerfTrace.count('pass.wallet_refresh');
    await _client.rpc(SupabaseRpcs.walletRefreshMyCard);
  }
}

class StudentQrRepository {
  final StudentPassGateway _gateway;

  StudentQrRepository({StudentPassGateway? gateway}) : _gateway = gateway ?? const SupabaseStudentPassGateway();

  /// Whose Wallet card was last refreshed, and on which day.
  String? _walletRefreshedFor;

  /// What was last written to the device.
  String? _saved;

  /// The student's card and QR code, put together from what the app already
  /// holds: [student] is the student's own row and [subscription] the current
  /// subscription, each read once for every screen that shows it (and each
  /// from its saved copy first, so the card never waits for the network when
  /// it has been shown before). The card itself costs no request.
  ///
  /// The pass is also kept under its own key, so it survives anything else
  /// failing: with no connection and nothing else saved, that copy is shown.
  Future<StudentPassDetails?> getStudentPassDetails({
    required Future<Map<String, dynamic>?> Function() student,
    required Future<SubscriptionModel?> Function() subscription,
  }) async {
    final userId = _gateway.userId;
    if (userId == null) return null;

    try {
      // Side by side: neither waits for the other.
      final subscriptionFuture = subscription();
      // Never left unawaited with an error if the student read fails first.
      subscriptionFuture.ignore();
      final row = await student();
      if (row == null) return null;
      final current = await subscriptionFuture;

      var qrValue = row['qr_code_value'] as String?;
      if (!row.containsKey('qr_code_value')) {
        // A copy saved by a version that did not keep the code with the
        // profile: the pass saved by that version still has it.
        qrValue = (await OfflineCache.readStudentPass())?['qr_value'] as String?;
      }
      final photo = (row['profile_image_url'] as String?)?.trim() ?? '';
      final details = StudentPassDetails(
        qrValue: qrValue,
        fullName: row['full_name'] as String?,
        phone: row['phone'] as String?,
        university: row['university'] as String?,
        college: row['college'] as String?,
        profileImagePath: photo.isEmpty ? null : photo,
        lineName: current?.lineName,
        stationName: current?.stationName,
        subscriptionId: current?.id,
        subscriptionType: current?.type,
        subscriptionStatus: current?.status,
        periodPhase: current?.periodPhase,
        periodName: current?.periodName,
        academicYear: current?.academicYear,
        startDate: current?.startDate,
        endDate: current?.endDate,
        companyName: current?.companyName,
        companyBrand: current?.companyBrand ?? CompanyBrand.none,
        returnStartTimes: current?.returnStartTimes ?? const {},
        isOfflineCache: OfflineCache.offlineSince.value != null,
      );
      final json = details.toCacheJson();
      final encoded = jsonEncode(json);
      if (encoded != _saved && (qrValue ?? '').isNotEmpty) {
        _saved = encoded;
        await OfflineCache.saveStudentPass(json);
      }
      _refreshWalletCard(userId);
      return details;
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

  /// Once a day in a run of the app (what changes by date alone changes at
  /// midnight; every other change the server notices itself), not every time
  /// the card is put together again. Never blocks the screen; a failure is
  /// tried again the next time.
  void _refreshWalletCard(String userId) {
    final key = '$userId ${DateTime.now().toIso8601String().substring(0, 10)}';
    if (key == _walletRefreshedFor) return;
    _walletRefreshedFor = key;
    _gateway.refreshWalletCard().then((_) {}, onError: (_) {
      if (_walletRefreshedFor == key) _walletRefreshedFor = null;
    });
  }
}
