import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/supabase_service.dart';
import '../models/user_role.dart';

class AuthRepository {
  final SupabaseClient _client = SupabaseService.client;

  // Format phone to internal email identifier to enable immediate password auth without SMS gateway costs
  static String phoneToAuthEmail(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$cleanPhone@busak.app';
  }

  /// Register a new student:
  /// Enforces 4-part name check and creates student record with unique phone and static QR code
  Future<User> registerStudent({
    required String phone,
    required String fullName,
    required String university,
    required String password,
  }) async {
    // 1. Validate 4-part name
    final nameParts = fullName.trim().split(RegExp(r'\s+'));
    if (nameParts.length < 4) {
      throw Exception('يرجى إدخال الاسم الرباعي كاملاً (4 أجزاء).');
    }

    final cleanPhone = phone.trim();
    final authEmail = phoneToAuthEmail(cleanPhone);

    // 2. Create Auth User
    final authResponse = await _client.auth.signUp(
      email: authEmail,
      password: password,
      data: {
        'role': 'student',
        'phone': cleanPhone,
        'full_name': fullName.trim(),
      },
    );

    final user = authResponse.user;
    if (user == null) {
      throw Exception('فشل إنشاء الحساب، يرجى المحاولة مرة أخرى.');
    }

    // 3. Create Student Profile Record (phone is unique at DB level)
    try {
      await _client.from(SupabaseTables.students).insert({
        'id': user.id,
        'phone': cleanPhone,
        'full_name': fullName.trim(),
        'university': university.trim(),
      });
    } catch (e) {
      // If student table insert fails (e.g. duplicate phone), sign out
      await _client.auth.signOut();
      rethrow;
    }

    return user;
  }

  /// Sign In with Phone & Password (or Email for Admin)
  Future<UserRole> signIn({
    required String identifier,
    required String password,
  }) async {
    String loginEmail = identifier.trim();
    if (!loginEmail.contains('@')) {
      loginEmail = phoneToAuthEmail(loginEmail);
    }

    final response = await _client.auth.signInWithPassword(
      email: loginEmail,
      password: password,
    );

    if (response.user == null) {
      throw Exception('تعذر تسجيل الدخول.');
    }

    return await detectUserRole(response.user!.id);
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

    // Deleting the student profile cascades subscriptions, receipts, etc.
    await _client.from(SupabaseTables.students).delete().eq('id', user.id);
    await _client.auth.signOut();
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
