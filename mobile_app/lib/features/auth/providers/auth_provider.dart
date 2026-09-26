import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/supabase_service.dart';
import '../data/auth_repository.dart';
import '../models/user_role.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

class AuthState {
  final User? user;
  final UserRole role;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.user,
    this.role = UserRole.unknown,
    this.isLoading = false,
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
    String? errorMessage,
  }) {
    return AuthState(
      user: user ?? this.user,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final current = SupabaseService.currentUser;
    if (current != null) {
      state = state.copyWith(isLoading: true);
      try {
        final role = await _repo.detectUserRole(current.id);
        state = AuthState(user: current, role: role, isLoading: false);
      } catch (e) {
        state = AuthState(user: current, role: UserRole.unknown, isLoading: false);
      }
    }
  }

  Future<void> registerStudent({
    required String phone,
    required String fullName,
    required String university,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _repo.registerStudent(
        phone: phone,
        fullName: fullName,
        university: university,
        password: password,
      );
      state = AuthState(user: user, role: UserRole.student, isLoading: false);
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
      state = AuthState(
        user: SupabaseService.currentUser,
        role: role,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repo.deleteStudentAccount();
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthState();
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});
