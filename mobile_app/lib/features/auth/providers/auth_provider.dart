import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/media/signed_url_cache.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/storage/snapshot_store.dart';
import '../../../core/sync/own_changes.dart';
import '../data/auth_repository.dart';
import '../models/user_role.dart';
import '../../notifications/push/push_providers.dart';
import '../../student/daily_ride/data/vote_reminders.dart';
import '../../student/profile/data/profile_repository.dart';
import '../../student/qr/presentation/student_qr_screen.dart';

final activeUniversitiesProvider =
    FutureProvider<List<Map<String, String>>>((ref) {
  return ref.watch(authRepositoryProvider).getActiveUniversities();
});

/// The student's own row. The photo is its storage path
/// (`profile_image_url`); screens sign a link to it with signedPhotoProvider.
final studentProfileSummaryProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  final cached = await OfflineCache.readThrough(
      'profile.summary', () => ref.read(profileRepositoryProvider).summaryRow(userId));
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

  /// Runs while the session is still valid, just before signing out: what
  /// must be told to the server as this account (detaching its push token).
  final Future<void> Function()? beforeSignOut;

  /// Puts together the signed-in student's pass (see [_refreshOfflineStudentPass]).
  final Future<void> Function()? refreshStudentPass;

  AuthNotifier(this._repo, {this.beforeSignOut, this.refreshStudentPass})
      : super(const AuthState(isInitialLoading: true)) {
    _init();
    _watchSession();
  }

  /// A session that ends elsewhere (expired, revoked, account deleted by an
  /// admin) signs this device out too, instead of leaving stale screens up.
  void _watchSession() {
    try {
      _sessionSubscription = SupabaseService.client.auth.onAuthStateChange.listen((change) async {
        if (change.event == AuthChangeEvent.signedOut && state.isAuthenticated) {
          // Everything saved for this account goes with the session.
          await _clearAccountData();
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
        // Known from last time: the app opens at once, with or without a
        // connection, and the role is checked with the server behind it.
        final cachedRole = await OfflineCache.readRoleFor(current.id).catchError((_) => null);
        if (cachedRole != null) {
          role = UserRole.fromString(cachedRole);
          unawaited(_confirmRole(current, role));
        } else {
          try {
            role = await _repo.detectUserRole(current.id);
            await OfflineCache.saveSession(current, role.name);
          } catch (_) {
            role = UserRole.fromString(null);
          }
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

  /// The saved role, checked against the server once it answers.
  Future<void> _confirmRole(User user, UserRole shown) async {
    try {
      final role = await _repo.detectUserRole(user.id);
      await OfflineCache.saveSession(user, role.name);
      if (mounted && role != shown && state.user?.id == user.id) {
        state = AuthState(user: user, role: role, isInitialLoading: false);
      }
    } catch (_) {
      // Offline: the saved role stands.
    }
  }

  Future<void> registerStudent({
    required String phone,
    required String fullName,
    required String university,
    required String college,
    required String password,
    String? specialisation,
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
        specialisation: specialisation,
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
      await _clearAccountData();
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      // Best effort and bounded: signing out never waits for the network.
      await beforeSignOut?.call().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await _repo.signOut();
    } catch (error) {
      // Offline: the local session is already removed; only the server-side
      // revoke failed, so the student is still signed out on this device.
      if (!isNetworkFailure(error)) rethrow;
    }
    // The next account on this phone must not get this student's reminders.
    await VoteReminders.cancelAll();
    await _clearAccountData();
    state = const AuthState();
  }

  /// Everything kept for the account, on the device and in memory, in one
  /// pass (one listing of the storage, the deletions side by side).
  Future<void> _clearAccountData() async {
    SignedUrlCache.clear();
    OwnChanges.clear();
    await OfflineCache.clearAll(also: SnapshotStore.isSnapshotKey);
  }

  /// The pass is put together as soon as the student is known, so it is saved
  /// for offline use before the card tab is opened. It is made from the two
  /// reads the home screen needs anyway (see studentQrProvider).
  Future<void> _refreshOfflineStudentPass() async {
    try {
      // After the new state has reached the providers that watch it.
      await Future<void>.delayed(Duration.zero);
      await refreshStudentPass?.call();
    } catch (_) {
      // The app remains available. The last encrypted pass is used when offline.
    }
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  // After signing out this phone must get nothing meant for the account.
  return AuthNotifier(repo,
      beforeSignOut: () => ref.read(pushControllerProvider).detach(),
      refreshStudentPass: () => ref.read(studentQrProvider.future));
});
