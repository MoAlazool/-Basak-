import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';

/// Auth state the test can switch between accounts (no Supabase needed).
class _SwitchableAuth extends AuthNotifier {
  _SwitchableAuth() : super(AuthRepository());

  void signInAs(String? id) => state = AuthState(
        user: id == null
            ? null
            : User(id: id, appMetadata: const {}, userMetadata: const {}, aud: '', createdAt: ''),
        role: UserRole.student,
      );
}

/// Returns the pass of whoever is "signed in" and counts server round trips.
class _FakeQrRepository implements StudentQrRepository {
  String? signedIn;
  int fetches = 0;

  @override
  Future<StudentPassDetails?> getStudentPassDetails({
    required Future<Map<String, dynamic>?> Function() student,
    required Future<SubscriptionModel?> Function() subscription,
  }) async {
    fetches++;
    return StudentPassDetails(fullName: signedIn);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a student pass loaded for one account is never shown to the next', () async {
    final auth = _SwitchableAuth();
    final repo = _FakeQrRepository();
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth),
      studentQrRepoProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    container.listen(studentQrProvider, (_, __) {});

    repo.signedIn = 'student A';
    auth.signInAs('a');
    expect((await container.read(studentQrProvider.future))?.fullName, 'student A');

    // Same account: switching tabs reuses the loaded pass, no new request.
    final before = repo.fetches;
    await container.read(studentQrProvider.future);
    expect(repo.fetches, before);

    // Student A signs out and student B signs in without restarting the app.
    auth.signInAs(null);
    repo.signedIn = 'student B';
    auth.signInAs('b');
    expect((await container.read(studentQrProvider.future))?.fullName, 'student B');
  });
}
