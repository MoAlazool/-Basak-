import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/media/signed_photo.dart';
import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/widgets/avatar_image.dart';
import 'package:basak_mobile/features/auth/providers/auth_provider.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';

import 'support/perf_fakes.dart';
import 'support/student_world.dart';

/// Links to private photos are signed once and shared; what is saved on the
/// phone is the photo's path, so an unchanged profile compares as unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RequestLog log;
  var offline = false;
  var now = DateTime(2026, 10, 9, 10);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = studentId;
    OfflineCache.resetSession();
    log = RequestLog();
    offline = false;
    now = DateTime(2026, 10, 9, 10);
    fakeSigner(log, offline: () => offline);
    SignedUrlCache.now = () => now;
    SignedUrlCache.clear();
  });
  tearDown(() {
    OfflineCache.debugUserId = null;
    SignedUrlCache.now = DateTime.now;
  });

  test('a link is signed once and reused by everyone showing the same photo', () async {
    final first = await SignedUrlCache.url('student-avatars', 'u1/a.jpg');
    expect(await SignedUrlCache.url('student-avatars', 'u1/a.jpg'), first);
    expect(SignedUrlCache.peek('student-avatars', 'u1/a.jpg'), first);
    expect(log.of('storage.sign'), 1);

    // Another photo, or the same path in another bucket, is its own link.
    await SignedUrlCache.url('student-avatars', 'u1/b.jpg');
    await SignedUrlCache.url('supervisor-avatars', 'u1/a.jpg');
    expect(log.of('storage.sign'), 3);
  });

  test('screens asking at the same moment share one request', () async {
    final links = await Future.wait([
      for (var i = 0; i < 5; i++) SignedUrlCache.url('student-avatars', 'u1/a.jpg'),
    ]);
    expect(links.toSet(), hasLength(1));
    expect(log.of('storage.sign'), 1);
  });

  test('shortly before it expires a link is replaced by a fresh one', () async {
    final first = await SignedUrlCache.url('student-avatars', 'u1/a.jpg');
    now = now.add(SignedUrlCache.lifetime - SignedUrlCache.renewBefore - const Duration(seconds: 1));
    expect(await SignedUrlCache.url('student-avatars', 'u1/a.jpg'), first, reason: 'still good');

    now = now.add(const Duration(seconds: 2));
    expect(SignedUrlCache.peek('student-avatars', 'u1/a.jpg'), isNull);
    final second = await SignedUrlCache.url('student-avatars', 'u1/a.jpg');
    expect(second, isNot(first));
    expect(log.of('storage.sign'), 2);
    // The widget tries the fresh link even if the old one had failed, and both
    // name the same copy on disk (see profile_photo_test).
    expect(avatarImage(first) == avatarImage(second), isFalse);
    expect((avatarImage(first) as CachedNetworkImageProvider).cacheKey,
        (avatarImage(second) as CachedNetworkImageProvider).cacheKey);
  });

  test('sign-out forgets every link', () async {
    final first = await SignedUrlCache.url('student-avatars', 'u1/a.jpg');
    SignedUrlCache.clear();
    expect(SignedUrlCache.peek('student-avatars', 'u1/a.jpg'), isNull);
    expect(await SignedUrlCache.url('student-avatars', 'u1/a.jpg'), isNot(first));
    expect(log.of('storage.sign'), 2);
  });

  test('offline: the photo\'s plain address, which names the same copy on disk as a signed link', () async {
    final signed = await SignedUrlCache.urlOrOffline('student-avatars', 'u1/a.jpg');
    SignedUrlCache.clear();
    offline = true;

    final plain = await SignedUrlCache.urlOrOffline('student-avatars', 'u1/a.jpg');

    expect(plain, isNot(contains('token=')));
    expect(SignedUrlCache.peek('student-avatars', 'u1/a.jpg'), isNull, reason: 'a failure is not kept');
    // Same host and path as a real signed link of this project.
    final real = Uri.parse(plain).replace(queryParameters: {'token': 'abc'}).toString();
    expect((avatarImage(plain) as CachedNetworkImageProvider).cacheKey,
        (avatarImage(real) as CachedNetworkImageProvider).cacheKey);
    expect(Uri.parse(plain).path, Uri.parse(signed).path);

    // Back online: a real link, which the widget tries as a new request.
    offline = false;
    final fresh = await SignedUrlCache.urlOrOffline('student-avatars', 'u1/a.jpg');
    expect(fresh, contains('token='));
    expect(avatarImage(fresh) == avatarImage(plain), isFalse);
  });

  test('the photo provider gives nothing for no photo and never throws', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(signedPhotoProvider((bucket: 'student-avatars', path: '')).future), isNull);
    expect(studentPhoto(null), isNull);
    expect(studentPhoto(''), isNull);
    offline = true;
    expect(await container.read(signedPhotoProvider(studentPhoto('u1/a.jpg')!).future), isNotNull);
  });

  test('what is saved holds the path only, so a start with nothing new changes nothing', () async {
    final world = StudentWorld();
    fakeSigner(world.log);
    var c = world.open();
    await watchScreens(c);

    final profile = await OfflineCache.peek('profile.summary') as Map;
    final pass = (await OfflineCache.readStudentPass())!;
    expect(profile['profile_image_url'], '$studentId/avatar-1.jpg');
    expect(profile.keys, isNot(contains('profile_image_signed_url')));
    expect(pass['profile_image_path'], '$studentId/avatar-1.jpg');
    expect(pass.keys, isNot(contains('cached_at')));
    pass.remove('_saved_at'); // when it was saved, not a link
    expect('$profile$pass', isNot(contains('token=')), reason: 'no link is saved');
    expect((await c.read(studentQrProvider.future))?.profileImagePath, '$studentId/avatar-1.jpg');

    // The next start: the server has the same data.
    OfflineCache.resetSession();
    var announced = 0;
    void listener() => announced++;
    OfflineCache.refreshed.addListener(listener);
    addTearDown(() => OfflineCache.refreshed.removeListener(listener));
    c = world.open();
    await c.read(studentProfileSummaryProvider(studentId).future);
    await c.read(studentQrProvider.future);
    await settle();

    expect(announced, 0, reason: 'nothing looked changed, so nothing is read or drawn again');
  });
}
