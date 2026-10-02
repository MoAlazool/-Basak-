import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/supabase_service.dart';
import '../models/user_role.dart';

class AuthRepository {
  SupabaseClient get _client => SupabaseService.client;

  // Format phone to internal email identifier to enable immediate password auth without SMS gateway costs
  static String phoneToAuthEmail(String phone) {
    final cleanPhone = normalizeEgyptianPhone(phone);
    return '$cleanPhone@busak.app';
  }

  static String normalizeEgyptianPhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('20') && digits.length >= 12) {
      digits = digits.substring(2);
    }
    if (digits.length == 10 && digits.startsWith('1')) {
      digits = '0$digits';
    }
    return digits;
  }

  Future<List<Map<String, String>>> getActiveUniversities() async {
    final rows = await _client
        .from('universities')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    return (rows as List<dynamic>)
        .map(
            (row) => {'id': row['id'] as String, 'name': row['name'] as String})
        .toList();
  }

  Future<List<String>> getActiveColleges(String universityId) async {
    final rows = await _client
        .from('colleges')
        .select('name')
        .eq('university_id', universityId)
        .eq('is_active', true)
        .order('name');
    return (rows as List<dynamic>).map((row) => row['name'] as String).toList();
  }

  /// Register a new student:
  /// Enforces 4-part name check and creates student record with unique phone and static QR code
  Future<User> registerStudent({
    required String phone,
    required String fullName,
    required String university,
    required String college,
    required String password,
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

    // 2. Check if student already exists in public.students table
    try {
      final existing = await _client
          .from(SupabaseTables.students)
          .select('id')
          .eq('phone', cleanPhone)
          .maybeSingle();

      if (existing != null) {
        throw Exception('الرقم مستخدم بالفعل. يرجى تسجيل الدخول مباشرة.');
      }
    } catch (e) {
      if (e.toString().contains('مسجل مسبقاً')) rethrow;
    }

    // 3. Create Auth User in Supabase Auth
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
    } catch (authError) {
      // If user already exists in auth or email rate limit was triggered, try sign in
      try {
        final signRes = await _client.auth.signInWithPassword(
          email: authEmail,
          password: password,
        );
        user = signRes.user;
      } catch (_) {}
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

    // 4. Create Student Profile Record (phone is unique at DB level)
    try {
      final Map<String, dynamic> record = {
        'id': studentId,
        'phone': cleanPhone,
        'full_name': fullName.trim(),
        'university': university.trim(),
        'college': college.trim().isEmpty ? 'غير محدد' : college.trim(),
        if (profileImagePath != null) 'profile_image_url': profileImagePath,
      };
      await _client.from(SupabaseTables.students).insert(record);
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
        throw Exception('الرقم مستخدم بالفعل.');
      }
      throw Exception('تعذر حفظ بيانات الطالب في قاعدة البيانات: $e');
    }

    // 5. Ensure active session
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

  /// Detect role by checking tables
  Future<UserRole> detectUserRole(String userId) async {
    // 1. Check if Admin
    final admin = await _client
        .from(SupabaseTables.admins)
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    if (admin != null) return UserRole.admin;

    // 2. Check if Supervisor
    final supervisor = await _client
        .from(SupabaseTables.supervisors)
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    if (supervisor != null) return UserRole.supervisor;

    // 3. Check if Student
    final student = await _client
        .from(SupabaseTables.students)
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    if (student != null) return UserRole.student;

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
}
