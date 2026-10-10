import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, User;

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';

/// The universities the entry tests pick from.
const entryUniversities = <Map<String, String>>[
  {'id': 'nmu', 'name': 'جامعة المنصورة الجديدة', 'city': 'المنصورة الجديدة'},
  {'id': 'mu', 'name': 'جامعة المنصورة', 'city': 'المنصورة'},
  {'id': 'delta', 'name': 'جامعة الدلتا للعلوم والتكنولوجيا', 'city': 'جمصة'},
  {'id': 'horus', 'name': 'جامعة حورس', 'city': 'دمياط الجديدة'},
  {'id': 'du', 'name': 'جامعة دمياط', 'city': 'دمياط الجديدة'},
];

/// Sign-in, sign-up and recovery without Supabase: records what the screens
/// send, and fails the way the server does when told to.
class FakeEntryRepository extends AuthRepository {
  /// What `registerStudent` throws; null: it never answers (the button spins).
  Object? registerError;

  /// What `signIn` throws.
  Object signInError = const AuthException('Invalid login credentials', code: 'invalid_credentials');

  Object? resetError;

  final List<Map<String, Object?>> registrations = [];
  final List<({String identifier, String password})> signIns = [];
  final List<String> resetRequests = [];
  final List<({String phone, String code, String newPassword})> resets = [];

  @override
  Future<List<Map<String, String>>> getActiveUniversities() async => entryUniversities;

  @override
  Future<User> registerStudent({
    required String phone,
    required String fullName,
    required String university,
    required String college,
    required String password,
    String? specialisation,
    Uint8List? profileImageBytes,
    String? profileImageExtension,
  }) async {
    registrations.add({
      'phone': phone,
      'fullName': fullName,
      'university': university,
      'college': college,
      'specialisation': specialisation,
      'password': password,
      'photo': profileImageBytes,
    });
    throw registerError ?? Exception('تعذر إنشاء الحساب الآن.');
  }

  @override
  Future<UserRole> signIn({required String identifier, required String password}) async {
    signIns.add((identifier: identifier, password: password));
    throw signInError;
  }

  @override
  Future<void> requestPasswordReset(String phone) async => resetRequests.add(phone);

  @override
  Future<void> resetPasswordWithCode({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    resets.add((phone: phone, code: code, newPassword: newPassword));
    if (resetError != null) throw resetError!;
  }
}

/// The app's frame around one entry screen, with [repo] behind it.
Widget entryApp(
  Widget home,
  FakeEntryRepository repo, {
  List<Override> overrides = const [],
  AuthNotifier Function(FakeEntryRepository repo)? auth,
}) =>
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authStateProvider.overrideWith((ref) => auth?.call(repo) ?? AuthNotifier(repo)),
        activeUniversitiesProvider.overrideWith((ref) async => entryUniversities),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    );
