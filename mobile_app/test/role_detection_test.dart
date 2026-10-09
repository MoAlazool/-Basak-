import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';

import 'support/perf_fakes.dart';

/// The role of an account: one request, or on an older database the three
/// table lookups at the same time.
void main() {
  test('one request when the database has my_role()', () async {
    for (final role in ['student', 'supervisor', 'admin']) {
      final log = RequestLog();
      final repo = AuthRepository(roles: FakeRoles(log, role: role));
      expect(await repo.detectUserRole('u1'), UserRole.fromString(role));
      expect(log.calls, {'role.rpc': 1});
    }
  });

  test('an account with no role is unknown, in one request', () async {
    final log = RequestLog();
    expect(await AuthRepository(roles: FakeRoles(log, role: null)).detectUserRole('u1'), UserRole.unknown);
    expect(log.calls, {'role.rpc': 1});
  });

  test('an older database: the three lookups, side by side, and my_role() is not asked again', () async {
    for (final role in ['student', 'supervisor', 'admin']) {
      final log = RequestLog();
      final lookups = _Slow(log, role: role);
      final repo = AuthRepository(roles: lookups);

      expect(await repo.detectUserRole('u1'), UserRole.fromString(role));
      expect(log.calls, {'role.rpc': 1, 'role.select': 3});
      expect(lookups.mostAtOnce, 3, reason: 'not one after another');

      log.reset();
      expect(await repo.detectUserRole('u1'), UserRole.fromString(role));
      expect(log.calls, {'role.select': 3});
    }
  });

  test('an older database and no role: unknown', () async {
    final log = RequestLog();
    final repo = AuthRepository(roles: FakeRoles(log, role: null, hasRpc: false));
    expect(await repo.detectUserRole('u1'), UserRole.unknown);
  });

  test('any other failure of the request is told, not papered over with a guess', () async {
    final repo = AuthRepository(roles: _Failing());
    await expectLater(repo.detectUserRole('u1'), throwsA(isA<StateError>()));
  });
}

class _Slow extends FakeRoles {
  _Slow(super.log, {super.role}) : super(hasRpc: false);

  int _running = 0;
  int mostAtOnce = 0;

  @override
  Future<bool> isIn(String table, String userId) async {
    _running++;
    if (_running > mostAtOnce) mostAtOnce = _running;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _running--;
    return super.isIn(table, userId);
  }
}

class _Failing implements RoleLookup {
  @override
  Future<String?> myRole() async => throw StateError('server error');
  @override
  Future<bool> isIn(String table, String userId) async => fail('must not fall back on a real error');
}
