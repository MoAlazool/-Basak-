import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:basak_mobile/core/network/secure_session_storage.dart';

const _key = 'sb-project-auth-token';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the name is supabase_flutter\'s own', () {
    expect(SecureSessionStorage.keyFor('https://hnwpkkryxovhmsrokdsd.supabase.co'),
        'sb-hnwpkkryxovhmsrokdsd-auth-token');
  });

  test('a session an older version kept in the preferences moves to secure storage, once', () async {
    SharedPreferences.setMockInitialValues({_key: '{"access_token":"old"}'});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = SecureSessionStorage(key: _key);
    await storage.initialize();

    expect(await storage.hasAccessToken(), isTrue, reason: 'the update signs nobody out');
    expect(await storage.accessToken(), '{"access_token":"old"}');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(_key), isNull, reason: 'no plain copy is left behind');
    expect(preferences.getBool(SecureSessionStorage.installMarker), isTrue);
  });

  test('sessions are written, read and removed in secure storage only', () async {
    SharedPreferences.setMockInitialValues({SecureSessionStorage.installMarker: true});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = SecureSessionStorage(key: _key);
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession('{"access_token":"new"}');
    expect(await storage.accessToken(), '{"access_token":"new"}');
    expect(await const FlutterSecureStorage().read(key: _key), '{"access_token":"new"}');
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('a session left in the Keychain by an earlier install is not signed in again', () async {
    // iOS keeps Keychain items after the app is deleted; the preferences go with it.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({_key: '{"access_token":"from before"}'});
    final storage = SecureSessionStorage(key: _key);
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('on this install, the session stays across launches', () async {
    SharedPreferences.setMockInitialValues({SecureSessionStorage.installMarker: true});
    FlutterSecureStorage.setMockInitialValues({_key: '{"access_token":"kept"}'});
    final storage = SecureSessionStorage(key: _key);
    await storage.initialize();
    expect(await storage.accessToken(), '{"access_token":"kept"}');
  });
}
