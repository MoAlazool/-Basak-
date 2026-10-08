import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/storage/snapshot_store.dart';
import '../data/auth_repository.dart';
import '../models/user_role.dart';
import '../../student/daily_ride/data/vote_reminders.dart';
import '../../student/qr/data/student_qr_repository.dart';

final activeUniversitiesProvider =
    FutureProvider<List<Map<String, String>>>((ref) {
  return ref.watch(authRepositoryProvider).getActiveUniversities();
});
/// Companies serving a university (sign-up screen, information only).
final universityCompaniesProvider = FutureProvider.autoDispose
    .family<List<({String name, int lines})>, String>((ref, universityId) {
  return ref.watch(authRepositoryProvider).getCompaniesForUniversity(universityId);
});
final activeCollegesProvider =
    FutureProvider.family<List<String>, String>((ref, universityId) {
  return ref.watch(authRepositoryProvider).getActiveColleges(universityId);
});

final studentProfileSummaryProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  final cached = await OfflineCache.readThrough('profile.summary', () async {
    final response = await SupabaseService.client
        .from('students')
        .select('full_name, phone, university, college, profile_image_url')
        .eq('id', userId)
        .maybeSingle();
    if (response == null) return null;
    final path = response['profile_image_url'] as String?;
    if (path == null || path.isEmpty) return response;
    try {
      final signed = await SupabaseService.client.storage
          .from('student-avatars')
          .createSignedUrl(path, 600);
      return {...response, 'profile_image_signed_url': signed};
    } catch (_) {
      return response;
    }
  });
  return cached == null ? null : Map<String, dynamic>.from(cached as Map);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

class AuthState {
  final User? user;
  final UserRole role;
  final bool isLoading;
  final bool isInitialLoading;
  final String? errorMessage;

  const AuthState({
    this.user,
    this.role = UserRole.unknown,
    this.isLoading = false,
    this.isInitialLoading = false,
    this.errorMessage,
  });

  bool get isAuthenticated => user != null;
  bool get isStudent => role == UserRole.student;
  bool get isSupervisor => role == UserRole.supervisor;
  bool get isAdmin => role == UserRole.admin;

  AuthState copyWith({
    User? user,
    UserRole? role,
    bool? isLoading,
    bool? isInitialLoading,
    String? errorMessage,
  }) {
    return AuthState(
      user: user ?? this.user,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  StreamSubscription<dynamic>? _sessionSubscription;

  AuthNotifier(this._repo) : super(const AuthState(isInitialLoading: true)) {
    _init();
    _watchSession();
  }

  /// A session that ends elsewhere (expired, revoked, account deleted by an
  /// admin) signs this device out too, instead of leaving stale screens up.
  void _watchSession() {
    try {
      _sessionSubscription = SupabaseService.client.auth.onAuthStateChange.listen((change) async {
        if (change.event == AuthChangeEvent.signedOut && state.isAuthenticated) {
          await OfflineCache.clearStudentPass();
          await OfflineCache.clearStudentLookups();
          await SnapshotStore.clear();
          if (mounted) state = const AuthState();
        }
      });
    } catch (_) {
      // Supabase not initialised (widget previews and tests).
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final current = SupabaseService.currentUser;
      if (current != null) {
        UserRole role;
        try {
          role = await _repo.detectUserRole(current.id);
          await OfflineCache.saveSession(current, role.name);
        } catch (_) {
          final cachedRole = await OfflineCache.readRoleFor(current.id);
          role = UserRole.fromString(cachedRole);
        }
        state = AuthState(user: current, role: role, isInitialLoading: false);
        if (role == UserRole.student) unawaited(_refreshOfflineStudentPass());
      } else {
        state = const AuthState(isInitialLoading: false);
      }
    } catch (_) {
      // Keep the app usable at the sign-in screen when the backend is offline
      // or has not been initialized (for example, in a widget preview).
      state = const AuthState(isInitialLoading: false);
    }
  }

  Future<void> registerStudent({
    required String phone,
    required String fullName,
    required String university,
    required String college,
    required String password,
    Uint8List? profileImageBytes,
    String? profileImageExtension,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _repo.registerStudent(
        phone: phone,
        fullName: fullName,
        university: university,
        college: college,
        password: password,
        profileImageBytes: profileImageBytes,
        profileImageExtension: profileImageExtension,
      );
      await OfflineCache.saveSession(user, UserRole.student.name);
      unawaited(_refreshOfflineStudentPass());
      state = AuthState(
          user: user,
          role: UserRole.student,
          isLoading: false,
          isInitialLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final role = await _repo.signIn(
        identifier: identifier,
        password: password,
      );
      final user = SupabaseService.currentUser;
      if (user != null) await OfflineCache.saveSession(user, role.name);
      if (role == UserRole.student) unawaited(_refreshOfflineStudentPass());
      state = AuthState(
        user: user,
        role: role,
        isLoading: false,
        isInitialLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> deleteStudentAccount() async {
    state = state.copyWith(isLoading: true);
    try {
      await requireOnline(_repo.deleteStudentAccount);
      await VoteReminders.cancelAll();
      await OfflineCache.clearAll();
      await SnapshotStore.clear();
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> deleteAccount() async => deleteStudentAccount();

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } catch (error) {
      // Offline: the local session is already removed; only the server-side
      // revoke failed, so the student is still signed out on this device.
      if (!isNetworkFailure(error)) rethrow;
    }
    // The next account on this phone must not get this student's reminders.
    await VoteReminders.cancelAll();
    await OfflineCache.clearAll();
    await SnapshotStore.clear();
    state = const AuthState();
  }

  Future<void> _refreshOfflineStudentPass() async {
    try {
      await StudentQrRepository().getStudentPassDetails();
    } catch (_) {
      // The app remains available. The last encrypted pass is used when offline.
    }
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});

/// The signed-in user's id. Every provider holding per-user data watches it,
/// so its cached result is dropped as soon as another user signs in on this
/// device (or the user signs out) and is never shown to the next person.
final currentUserIdProvider = Provider<String?>(
    (ref) => ref.watch(authStateProvider.select((s) => s.user?.id)));
