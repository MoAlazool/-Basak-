import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, User;

import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/student/offers/offers_repository.dart';

/// Ids as the server makes them.
String offerUuid(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// The server without the offers migration: no such function.
const noSuchFunction = PostgrestException(
    message: 'Could not find the function public.get_my_offers without parameters in the schema cache',
    code: 'PGRST202');

/// A refusal the server raises with words written to be shown as they are.
PostgrestException refusal(String message) => PostgrestException(message: message, code: 'P0001');

/// One offer as `get_my_offers` sends it.
Map<String, dynamic> offerJson(
  int n, {
  String? title,
  String kind = 'percent',
  String value = '20%',
  String category = 'food',
  String merchant = 'كافيه الجامعة',
  bool special = false,
  bool needsPin = false,
  int minutes = 10,
  int limit = 1,
  int used = 0,
  int? left,
  String? endsAt,
  Map<String, dynamic>? coupon,
  String description = 'خصم على كل المشروبات الساخنة لطلاب الجامعة.',
  String terms = 'مرة واحدة لكل طالب. لا يُجمع مع عروض أخرى.',
  String? imagePath,
  String? logoPath,
  String? phone = '01011223344',
  String? whatsapp = '01011223344',
  String? link = 'https://cafe.example.com/menu',
  String? address = 'شارع الجامعة، أمام البوابة الرئيسية',
}) =>
    {
      'id': offerUuid(n),
      'title': title ?? 'عرض رقم $n',
      'description': description,
      'terms': terms,
      'image_path': imagePath,
      'kind': kind,
      'value_label': value,
      'ends_at': endsAt,
      'special': special,
      'needs_pin': needsPin,
      'coupon_minutes': minutes,
      'per_student_limit': limit,
      'used': used,
      'left': left,
      'coupon': coupon,
      'merchant': {
        'id': offerUuid(900 + n),
        'name': merchant,
        'category': category,
        'logo_path': logoPath,
        'phone': phone,
        'whatsapp': whatsapp,
        'link_url': link,
        'address': address,
      },
    };

Map<String, dynamic> offersJson(List<Map<String, dynamic>> offers, {bool hidden = false}) =>
    {'hidden': hidden, 'offers': hidden ? <dynamic>[] : offers};

Map<String, dynamic> couponJson(DateTime expiresAt,
        {String id = 'coupon-1', String code = 'K7M2QP', bool confirmed = false, bool? needsPin}) =>
    {
      'id': id,
      'code': code,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'confirmed': confirmed,
      if (needsPin != null) 'needs_pin': needsPin,
    };

/// The server's side of offers: what it would answer, and what it was asked.
class FakeOffersGateway implements OffersGateway {
  FakeOffersGateway([this.answer]);

  /// What `get_my_offers` answers; [failure] is thrown instead when set.
  Object? answer;
  Object? failure;
  int reads = 0;

  final List<List<String>> seenCalls = [];
  Object? seenFailure;
  final List<String> openedCalls = [];

  final List<String> redeemed = [];
  FutureOr<Object?> Function(String offerId)? onRedeem;

  final List<({String id, String pin})> pins = [];
  FutureOr<Object?> Function(String pin)? onConfirm;


  @override
  Future<dynamic> myOffers() async {
    reads++;
    if (failure != null) throw failure!;
    return answer;
  }

  @override
  Future<void> seen(List<String> ids) async {
    seenCalls.add(ids);
    if (seenFailure != null) throw seenFailure!;
  }

  @override
  Future<void> opened(String id) async => openedCalls.add(id);

  @override
  Future<dynamic> redeem(String offerId) async {
    redeemed.add(offerId);
    return await onRedeem?.call(offerId);
  }

  @override
  Future<dynamic> confirm(String redemptionId, String pin) async {
    pins.add((id: redemptionId, pin: pin));
    return await onConfirm?.call(pin);
  }
}

class FakeOfferStudent extends AuthNotifier {
  FakeOfferStudent() : super(AuthRepository()) {
    state = const AuthState(
      user: User(id: 'student-1', appMetadata: {}, userMetadata: {'full_name': 'سارة أحمد محمود'}, aud: '', createdAt: ''),
      role: UserRole.student,
    );
  }
}

/// A clock the test moves.
class TestClock {
  TestClock([DateTime? at]) : now = at ?? DateTime(2026, 10, 11, 12);
  DateTime now;
  DateTime call() => now;
  void forward(Duration by) => now = now.add(by);
}

/// What every offers screen needs around it: a signed-in student, the fake
/// server and the test's clock.
List<Override> offerOverrides(FakeOffersGateway gateway, TestClock clock, {Map<String, dynamic>? profile}) => [
      sessionUserIdProvider.overrideWithValue('student-1'),
      authStateProvider.overrideWith((ref) => FakeOfferStudent()),
      offersRepoProvider.overrideWithValue(OffersRepository(gateway: gateway)),
      offersClockProvider.overrideWithValue(clock.call),
      studentProfileSummaryProvider.overrideWith((ref, id) async => profile ?? {'full_name': 'سارة أحمد محمود'}),
    ];

/// [home] as a page of the app, in Arabic, at [textScale].
Widget offersApp(Widget home, List<Override> overrides, {double textScale = 1}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: home,
      ),
    );
