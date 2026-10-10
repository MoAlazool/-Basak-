import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_config.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/perf_trace.dart';
import '../../../core/network/supabase_service.dart';
import '../models/user_role.dart';

/// How the role of an account is asked from the server (replaced in tests).
abstract class RoleLookup {
  /// 'admin' | 'supervisor' | 'student', or null when the account has no role.
  /// Throws [RoleRpcUnavailable] when the database has no such function.
  Future<String?> myRole();

  /// Whether [userId] has a row in [table] (the lookup used before `my_role`).
  Future<bool> isIn(String table, String userId);
}

/// The database is older than `my_role()`.
class RoleRpcUnavailable implements Exception {
  const RoleRpcUnavailable();
}

class SupabaseRoleLookup implements RoleLookup {
  const SupabaseRoleLookup();

  @override
  Future<String?> myRole() async {
    PerfTrace.count('role.rpc');
    try {
      return await SupabaseService.client.rpc('my_role') as String?;
    } on PostgrestException catch (error) {
      // PGRST202: not in the schema cache; 42883: undefined function.
      if (error.code == 'PGRST202' || error.code == '42883' || error.code == '404') {
        throw const RoleRpcUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<bool> isIn(String table, String userId) async {
    PerfTrace.count('role.select');
    return await SupabaseService.client.from(table).select('id').eq('id', userId).maybeSingle() != null;
  }
}

/// How a new student's row reaches the database (replaced in tests).
abstract class StudentRows {
  Future<void> insert(Map<String, dynamic> record);
}

class SupabaseStudentRows implements StudentRows {
  const SupabaseStudentRows();

  @override
  Future<void> insert(Map<String, dynamic> record) =>
      SupabaseService.client.from(SupabaseTables.students).insert(record);
}

class AuthRepository {
  final RoleLookup _roles;
  final StudentRows _students;

  bool _roleRpcMissing = false;

  AuthRepository({RoleLookup? roles, StudentRows? students})
      : _roles = roles ?? const SupabaseRoleLookup(),
        _students = students ?? const SupabaseStudentRows();

  SupabaseClient get _client => SupabaseService.client;

  // Format phone to internal email identifier to enable immediate password auth without SMS gateway costs
  static String phoneToAuthEmail(String phone) {
    final cleanPhone = normalizeEgyptianPhone(phone);
    return '$cleanPhone@busak.app';
  }

  /// Arabic keyboards type ٠١٢… (and Persian ones ۰۱۲…): same digits, different characters.
  static String toLatinDigits(String input) => input.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
        final code = match.group(0)!.codeUnitAt(0);
        return String.fromCharCode(0x30 + (code >= 0x06F0 ? code - 0x06F0 : code - 0x0660));
      });

  static const phoneAlreadyRegisteredMessage =
      'رقم الهاتف مسجل بالفعل. سجّل الدخول به، أو استخدم نسيت كلمة المرور.';

  /// What is saved for a student who names no college (older accounts).
  static const unknownCollege = 'غير محدد';

  /// The longest specialisation the database takes.
  static const specialisationMaxLength = 80;

  static String normalizeEgyptianPhone(String phone) {
    var digits = toLatinDigits(phone).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('20') && digits.length >= 12) {
      digits = digits.substring(2);
    }
    if (digits.length == 10 && digits.startsWith('1')) {
      digits = '0$digits';
    }
    return digits;
  }

  /// The universities a student can pick: id, name and, when it has one, city.
  Future<List<Map<String, String>>> getActiveUniversities() async {
    final rows = await _client
        .from('universities')
        .select('id, name, city')
        .eq('is_active', true)
        .order('name');
    return (rows as List<dynamic>)
        .map((row) => {
              'id': row['id'] as String,
              'name': row['name'] as String,
              if ((row['city'] as String?)?.trim().isNotEmpty ?? false) 'city': (row['city'] as String).trim(),
            })
        .toList();
  }

  /// Whether [error] says the database has no `specialisation` column yet
  /// (the migration that adds it has not been applied).
  static bool isUnknownSpecialisationColumn(Object error) {
    if (error is! PostgrestException) return false;
    final text = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'.toLowerCase();
    if (!text.contains('specialisation')) return false;
    // PGRST204: not in the schema cache; 42703: undefined column.
    return error.code == 'PGRST204' || error.code == '42703' || text.contains('column');
  }

  /// Saves the student's row. The specialisation travels only when there is
  /// one, and a database that does not know the column yet gets the row once
  /// more without it: signing up never depends on that migration.
  Future<void> saveStudentRow(Map<String, dynamic> record, {String? specialisation}) async {
    final value = specialisation?.trim() ?? '';
    if (value.isEmpty) return _students.insert(record);
    try {
      await _students.insert({...record, 'specialisation': value});
    } catch (error) {
      if (!isUnknownSpecialisationColumn(error)) rethrow;
      await _students.insert(record);
    }
  }

  /// Registers a new student: the sign-in account, the optional photo and the
  /// student row (unique phone; the database issues the permanent QR code).
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
    // Require a three-part name, while allowing the four-part form used by the UI.
    final nameParts = fullName.trim().split(RegExp(r'\s+'));
    if (nameParts.length < 3) {
      throw Exception('يرجى إدخال الاسم ثلاثياً على الأقل.');
    }
    if (university.trim().isEmpty) {
      throw Exception('اختر الجامعة من القائمة.');
    }

    final cleanPhone = normalizeEgyptianPhone(phone);
    if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(cleanPhone)) {
      throw Exception('يرجى إدخال رقم هاتف مصري صحيح مكون من 11 رقماً.');
    }
    final authEmail = phoneToAuthEmail(cleanPhone);

    // Create the sign-in account. The phone is its login, so a number that is
    // already registered is refused here by the server, whatever password is typed.
    User? user;
    try {
      final authResponse = await _client.auth.signUp(
        email: authEmail,
        password: password,
        data: {
          'role': 'student',
          'phone': cleanPhone,
          'full_name': fullName.trim(),
        },
      );
      user = authResponse.user;
      // Some configurations answer a duplicate sign-up with a user that has no identities.
      if (user != null && (user.identities?.isEmpty ?? false) && authResponse.session == null) {
        throw Exception(phoneAlreadyRegisteredMessage);
      }
    } on AuthException catch (authError) {
      final text = '${authError.code ?? ''} ${authError.message}'.toLowerCase();
      if (text.contains('already') || text.contains('user_already_exists') || text.contains('exists')) {
        throw Exception(phoneAlreadyRegisteredMessage);
      }
      rethrow;
    }

    // Phone-based synthetic email addresses do not need an email confirmation.
    // Recover a session here if the project returns a user without one.
    if (_client.auth.currentUser == null && user != null) {
      try {
        final response = await _client.auth.signInWithPassword(
          email: authEmail,
          password: password,
        );
        user = response.user ?? user;
      } catch (_) {}
    }

    final studentId = user?.id ?? SupabaseService.currentUser?.id;

    if (studentId == null || _client.auth.currentUser == null) {
      throw Exception('تعذر تفعيل جلسة الطالب. أعد المحاولة قبل حفظ البيانات.');
    }

    String? profileImagePath;
    if (profileImageBytes != null) {
      final extension = (profileImageExtension ?? 'jpg').toLowerCase();
      final safeExtension =
          const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
              ? extension
              : 'jpg';
      profileImagePath = '$studentId/avatar.$safeExtension';
      final contentType = safeExtension == 'jpg' || safeExtension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$safeExtension';
      await _client.storage.from('student-avatars').uploadBinary(
            profileImagePath,
            profileImageBytes,
            fileOptions: FileOptions(contentType: contentType),
          );
    }

    // The student's profile row (the phone is unique in the database).
    try {
      final Map<String, dynamic> record = {
        'id': studentId,
        'phone': cleanPhone,
        'full_name': fullName.trim(),
        'university': university.trim(),
        'college': college.trim().isEmpty ? unknownCollege : college.trim(),
        if (profileImagePath != null) 'profile_image_url': profileImagePath,
      };
      await saveStudentRow(record, specialisation: specialisation);
    } catch (e) {
      if (profileImagePath != null) {
        try {
          await _client.storage
              .from('student-avatars')
              .remove([profileImagePath]);
        } catch (_) {}
      }
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique')) {
        throw Exception(phoneAlreadyRegisteredMessage);
      }
      throw Exception('تعذر حفظ بيانات الطالب في قاعدة البيانات: $e');
    }

    // Make sure a session is active.
    if (_client.auth.currentUser == null) {
      try {
        await _client.auth.signInWithPassword(
          email: authEmail,
          password: password,
        );
      } catch (_) {}
    }

    final finalUser = _client.auth.currentUser ?? user;
    if (finalUser == null) {
      throw Exception(
          'تم إنشاء الحساب بنجاح! يرجى التبديل لتبويب تسجيل الدخول الآن.');
    }

    return finalUser;
  }

  /// Sign In with Phone & Password (or Email for Admin)
  Future<UserRole> signIn({
    required String identifier,
    required String password,
  }) async {
    String loginEmail = identifier.trim();
    if (!loginEmail.contains('@')) {
      loginEmail = phoneToAuthEmail(identifier);
    }

    // Accounts are created server-side as confirmed Auth users; there is no
    // plaintext-password fallback. Auth errors surface to the login screen.
    final response = await _client.auth.signInWithPassword(
      email: loginEmail,
      password: password,
    );
    if (response.user != null) {
      return await detectUserRole(response.user!.id);
    }

    return UserRole.unknown;
  }

  /// The account's role: one request (`my_role`), or, on a database that
  /// does not have that function yet, the three table lookups side by side.
  Future<UserRole> detectUserRole(String userId) async {
    if (!_roleRpcMissing) {
      try {
        return UserRole.fromString(await _roles.myRole());
      } on RoleRpcUnavailable {
        _roleRpcMissing = true; // asked once per run, not on every start
      }
    }
    final found = await Future.wait([
      _roles.isIn(SupabaseTables.admins, userId),
      _roles.isIn(SupabaseTables.supervisors, userId),
      _roles.isIn(SupabaseTables.students, userId),
    ]);
    if (found[0]) return UserRole.admin;
    if (found[1]) return UserRole.supervisor;
    if (found[2]) return UserRole.student;
    return UserRole.unknown;
  }

  /// Delete Student Account (Core Rule: Delete-and-re-register only)
  Future<void> deleteStudentAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.functions.invoke('student-delete-account');
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// The signed-in session's refresh token: what signing out puts aside when
  /// signing in with Face ID or a fingerprint is switched on.
  String? get currentRefreshToken {
    try {
      return _client.auth.currentSession?.refreshToken;
    } catch (_) {
      return null; // Supabase not started (tests, previews)
    }
  }

  /// Signs out of this phone only: the session stays alive on the server, to
  /// be picked up again by [restoreSession].
  Future<void> signOutKeepingSession() => SupabaseService.signOutOnThisPhone();

  /// Signs in with a refresh token put aside by an earlier sign-out. Throws
  /// what the server answers when the token is no longer good.
  Future<({User user, UserRole role})> restoreSession(String refreshToken) async {
    final response = await _client.auth.setSession(refreshToken);
    final user = response.user ?? response.session?.user ?? _client.auth.currentUser;
    if (user == null) throw const AuthException('The session could not be restored.');
    return (user: user, role: await detectUserRole(user.id));
  }

  /// Ends on the server a session this phone no longer wants («حساب آخر»),
  /// through a client of its own: nobody is signed in here meanwhile.
  Future<void> revokeSession(String refreshToken) async {
    final auth = GoTrueClient(
      url: '${SupabaseConfig.supabaseUrl}/auth/v1',
      headers: {
        'apikey': SupabaseConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
      },
      autoRefreshToken: false,
    );
    try {
      await auth.setSession(refreshToken).timeout(const Duration(seconds: 10));
      await auth.signOut().timeout(const Duration(seconds: 10));
    } finally {
      auth.dispose();
    }
  }

  /// Forgot password, step 1 (no sign-in): asks the student's bus company to
  /// verify them. The answer is the same whether or not the number exists.
  Future<void> requestPasswordReset(String phone) async {
    final cleanPhone = normalizeEgyptianPhone(phone);
    if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(cleanPhone)) {
      throw Exception('يرجى إدخال رقم هاتف مصري صحيح مكون من 11 رقماً.');
    }
    await _client.rpc(SupabaseRpcs.requestStudentPasswordReset,
        params: {'p_phone': cleanPhone});
  }

  /// Forgot password, step 2: the one-time code given by the company admin
  /// plus the new password. The password goes only to Supabase Auth.
  Future<void> resetPasswordWithCode({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    try {
      await _client.functions.invoke('student-reset-password', body: {
        'phone': normalizeEgyptianPhone(phone),
        'code': code.trim(),
        'newPassword': newPassword,
      });
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'تعذر تغيير كلمة المرور. حاول مرة أخرى.';
      throw Exception(message);
    }
  }
}
