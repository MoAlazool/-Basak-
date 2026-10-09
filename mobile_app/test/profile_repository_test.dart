import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/own_changes.dart';
import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';

/// The server's `update_my_profile`, as a database that has the form with the
/// specialisation ([hasSpecialisation]) and as one that does not have it yet.
class _Server implements ProfileGateway {
  _Server({required this.hasSpecialisation});

  final bool hasSpecialisation;
  final calls = <Map<String, dynamic>>[];

  /// What the next save is refused with, instead of being done.
  PostgrestException? refusal;

  @override
  String? userId = 'u1';

  @override
  Future<Map<String, dynamic>?> summaryRow(String userId) async => {
        'full_name': 'سارة أحمد', 'phone': '01023456789', 'university': 'جامعة المنصورة الجديدة',
        'college': 'الهندسة', 'email': null, 'birth_date': null, 'profile_image_url': null,
        if (hasSpecialisation) 'specialisation': 'مدني',
      };

  @override
  Future<dynamic> updateDetails(Map<String, dynamic> params) async {
    calls.add(params);
    if (refusal != null) throw refusal!;
    final four = params.containsKey('p_specialisation');
    if (four && !hasSpecialisation) {
      // What PostgREST answers for a function it does not know (HTTP 404).
      throw const PostgrestException(
        message: 'Could not find the function public.update_my_profile(p_birth_date, p_college, p_email, '
            'p_specialisation) in the schema cache',
        code: 'PGRST202',
      );
    }
    String text(String key) => ((params[key] as String?) ?? '').trim();
    return {
      'email': text('p_email').isEmpty ? null : text('p_email').toLowerCase(),
      'college': text('p_college').isEmpty ? 'غير محدد' : text('p_college'),
      'birth_date': params['p_birth_date'],
      if (four) 'specialisation': text('p_specialisation').isEmpty ? null : text('p_specialisation'),
    };
  }

  @override
  Future<void> uploadPhoto(String path, Uint8List jpeg) async {}
  @override
  Future<dynamic> setPhoto(String path) async => null;
  @override
  Future<List<String>> listPhotos(String userId) async => const [];
  @override
  Future<void> removePhotos(List<String> paths) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = 'u1';
    OfflineCache.resetSession();
    OwnChanges.clear();
  });
  tearDown(() => OfflineCache.debugUserId = null);

  /// The profile as the app holds it after its one read.
  Future<Map> held(_Server server) async {
    await OfflineCache.readThrough('profile.summary', () => server.summaryRow('u1'));
    return await OfflineCache.peek('profile.summary') as Map;
  }

  test('the profile is read whole: a database without the specialisation simply has no such key', () async {
    final old = await held(_Server(hasSpecialisation: false));
    expect(old.containsKey('specialisation'), isFalse);
    expect(old['specialisation'], isNull, reason: 'read as "not added", never an error');
    expect(old['college'], 'الهندسة');
  });

  test('the profile is read whole: a database with the specialisation gives it', () async {
    expect((await held(_Server(hasSpecialisation: true)))['specialisation'], 'مدني');
  });

  for (final has in [true, false]) {
    test('specialisation untouched (database ${has ? 'ready' : 'not ready'}): one three-argument save, as always',
        () async {
      final server = _Server(hasSpecialisation: has);
      await held(server);
      final all = await ProfileRepository(gateway: server)
          .updateDetails(email: ' A@B.co ', college: 'الطب', birthDate: DateTime(2005, 3, 14), specialisation: 'مدني');
      expect(all, isTrue);
      expect(server.calls, [
        {'p_email': 'A@B.co', 'p_college': 'الطب', 'p_birth_date': '2005-03-14'}
      ]);
      expect((await OfflineCache.peek('profile.summary') as Map)['college'], 'الطب');
    });
  }

  test('specialisation changed, database ready: one four-argument save, and the answer is held', () async {
    final server = _Server(hasSpecialisation: true);
    await held(server);
    final all = await ProfileRepository(gateway: server).updateDetails(
        email: '', college: 'الهندسة', birthDate: null, specialisation: ' ميكاترونكس ', specialisationChanged: true);
    expect(all, isTrue);
    expect(server.calls, [
      {'p_email': '', 'p_college': 'الهندسة', 'p_birth_date': null, 'p_specialisation': 'ميكاترونكس'}
    ]);
    expect((await OfflineCache.peek('profile.summary') as Map)['specialisation'], 'ميكاترونكس');

    // Emptied: cleared on the server and on this phone.
    await ProfileRepository(gateway: server)
        .updateDetails(email: '', college: 'الهندسة', specialisation: '', specialisationChanged: true);
    final now = await OfflineCache.peek('profile.summary') as Map;
    expect(now.containsKey('specialisation'), isTrue);
    expect(now['specialisation'], isNull);
  });

  test('specialisation changed, database not ready: the rest is saved the old way and the answer says so',
      () async {
    final server = _Server(hasSpecialisation: false);
    await held(server);
    final all = await ProfileRepository(gateway: server).updateDetails(
        email: 'a@b.co',
        college: 'الطب',
        birthDate: DateTime(2005, 3, 14),
        specialisation: 'جراحة',
        specialisationChanged: true);
    expect(all, isFalse, reason: 'everything but the specialisation');
    expect(server.calls, [
      {'p_email': 'a@b.co', 'p_college': 'الطب', 'p_birth_date': '2005-03-14', 'p_specialisation': 'جراحة'},
      {'p_email': 'a@b.co', 'p_college': 'الطب', 'p_birth_date': '2005-03-14'},
    ]);
    final now = await OfflineCache.peek('profile.summary') as Map;
    expect([now['email'], now['college'], now['birth_date']], ['a@b.co', 'الطب', '2005-03-14']);
    expect(now['specialisation'], isNull, reason: 'nothing is shown as saved that was not');
  });

  test('any other refusal is not a missing function: no second try, and the words of the server are kept',
      () async {
    final server = _Server(hasSpecialisation: true)
      ..refusal = const PostgrestException(message: 'اسم التخصص طويل جداً.', code: '23514');
    await held(server);
    await expectLater(
      ProfileRepository(gateway: server)
          .updateDetails(college: 'الطب', specialisation: 'x' * 90, specialisationChanged: true),
      throwsA(isA<Exception>().having((e) => '$e', 'message', contains('اسم التخصص طويل جداً.'))),
    );
    expect(server.calls, hasLength(1));
    expect((await OfflineCache.peek('profile.summary') as Map)['college'], 'الهندسة', reason: 'nothing was saved');

    expect(ProfileRepository.isMissingFunction(const PostgrestException(message: 'x', code: 'PGRST202')), isTrue);
    expect(ProfileRepository.isMissingFunction(const PostgrestException(message: 'x', code: '404')), isTrue);
    expect(ProfileRepository.isMissingFunction(const PostgrestException(message: 'x', code: '42501')), isFalse);
    expect(ProfileRepository.isMissingFunction(Exception('PGRST202')), isFalse);
  });
}
