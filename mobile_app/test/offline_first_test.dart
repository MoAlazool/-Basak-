import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/storage/snapshot_store.dart';

/// Saved data first: what a student sees with no connection, on a cold start,
/// when the network drops while the app is open, and when it comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const card = {'qr_value': 'QR-1', 'full_name': 'طالب', 'line_name': 'منية النصر', 'station_name': 'البجلات'};
  Never offline() => throw const SocketException('Failed host lookup');
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// Closing and opening the app: memory is gone, the device storage stays.
  void coldStart() => OfflineCache.resetSession();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = 'student-a';
    OfflineCache.requestTimeout = const Duration(seconds: 12);
    OfflineCache.resetSession();
  });
  tearDown(() => OfflineCache.debugUserId = null);

  test('cold start with no internet: the card is there at once, marked with when it was saved', () async {
    expect(await OfflineCache.readThrough('student_pass', () async => card), card);
    await settle();

    coldStart();
    final never = Completer<dynamic>();
    final shown = await OfflineCache.readThrough('student_pass', () => never.future)
        .timeout(const Duration(milliseconds: 200));
    expect(shown, card, reason: 'the saved card must not wait for a request that never answers');

    coldStart();
    expect(await OfflineCache.readThrough('student_pass', () async => offline()), card);
    await settle();
    expect(OfflineCache.offlineSince.value, isNotNull, reason: 'the banner says the data is saved, and since when');
  });

  test('nothing saved and no internet: the error is told, not hidden', () async {
    await expectLater(OfflineCache.readThrough('subscriptions', () async => offline()),
        throwsA(isA<SocketException>()));
  });

  test('cold start online: saved data first, then the newer data without a second request', () async {
    await OfflineCache.readThrough('subscriptions', () async => [{'status': 'pending_review'}]);
    await settle();

    coldStart();
    var requests = 0;
    var announced = 0;
    void listener() => announced++;
    OfflineCache.refreshed.addListener(listener);
    addTearDown(() => OfflineCache.refreshed.removeListener(listener));
    Future<dynamic> server() async {
      requests++;
      return [{'status': 'active'}];
    }

    expect(await OfflineCache.readThrough('subscriptions', server), [{'status': 'pending_review'}]);
    await settle();
    expect(announced, 1, reason: 'the screen is told the server had something newer');
    expect(await OfflineCache.readThrough('subscriptions', server), [{'status': 'active'}]);
    expect(requests, 1, reason: 'the fresh value comes from memory');
    expect(OfflineCache.offlineSince.value, isNull);
  });

  test('cold start online with nothing new: no flicker, no extra reads', () async {
    await OfflineCache.readThrough('profile', () async => {'name': 'طالب'});
    await settle();
    coldStart();
    var announced = 0;
    void listener() => announced++;
    OfflineCache.refreshed.addListener(listener);
    addTearDown(() => OfflineCache.refreshed.removeListener(listener));
    expect(await OfflineCache.readThrough('profile', () async => {'name': 'طالب'}), {'name': 'طالب'});
    await settle();
    expect(announced, 0);
  });

  test('the network drops while the app is open: what was loaded stays, nothing is cleared', () async {
    expect(await OfflineCache.readThrough('subscriptions', () async => [1]), [1]);
    await settle();
    // Pull to refresh, app resume or a retry, all without a connection.
    for (var i = 0; i < 3; i++) {
      expect(await OfflineCache.readThrough('subscriptions', () async => offline()), [1]);
    }
    expect(OfflineCache.offlineSince.value, isNotNull);
    coldStart();
    expect(await OfflineCache.readThrough('subscriptions', () async => offline()), [1],
        reason: 'being offline never deletes saved data');
  });

  test('a connection with no internet does not hang: the saved data is used after the time limit', () async {
    await OfflineCache.readThrough('sale_catalog', () async => {'companies': []});
    await settle();
    OfflineCache.requestTimeout = const Duration(milliseconds: 50);
    final never = Completer<dynamic>();
    // Not the first read of this run: this one asks the server first.
    expect(await OfflineCache.readThrough('sale_catalog', () => never.future), {'companies': []});
    expect(OfflineCache.offlineSince.value, isNotNull);
  });

  test('reconnect: the first answer from the server clears the offline mark and saves the new data', () async {
    await OfflineCache.readThrough('subscriptions', () async => ['old']);
    await settle();
    await OfflineCache.readThrough('subscriptions', () async => offline());
    expect(OfflineCache.offlineSince.value, isNotNull);

    expect(await OfflineCache.readThrough('subscriptions', () async => ['new']), ['new']);
    expect(OfflineCache.offlineSince.value, isNull);
    await settle();
    coldStart();
    expect(await OfflineCache.readThrough('subscriptions', () async => offline()), ['new']);
  });

  test('another account on the same phone never sees the first one\'s data', () async {
    await OfflineCache.readThrough('student_pass', () async => card);
    await settle();

    OfflineCache.debugUserId = 'student-b';
    coldStart();
    await expectLater(OfflineCache.readThrough('student_pass', () async => offline()),
        throwsA(isA<SocketException>()), reason: 'student B has nothing saved and is not given A\'s card');
    expect(await OfflineCache.readThrough('student_pass', () async => {'qr_value': 'QR-2'}), {'qr_value': 'QR-2'});
    await settle();

    OfflineCache.debugUserId = 'student-a';
    coldStart();
    expect(await OfflineCache.readThrough('student_pass', () async => offline()), card);
  });

  test('sign-out removes everything saved, for the pass, the screens and the snapshots', () async {
    await OfflineCache.readThrough('student_pass', () async => card);
    await OfflineCache.saveStudentPass(Map<String, dynamic>.from(card));
    await SnapshotStore.write('student-a', 'current_subscription', {'id': 's1'});
    await settle();

    await OfflineCache.clearAll();
    await SnapshotStore.clear();

    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(await SnapshotStore.read('student-a', 'current_subscription'), isNull);
    await expectLater(OfflineCache.readThrough('student_pass', () async => offline()),
        throwsA(isA<SocketException>()));
  });

  test('a server refusal is not papered over with saved data', () async {
    await OfflineCache.readThrough('student_pass', () async => card);
    await settle();
    Never refused() => throw const PostgrestException(message: 'JWT expired', code: 'PGRST301');

    // Asked directly: the refusal is the answer.
    await expectLater(OfflineCache.readThrough('student_pass', () async => refused()),
        throwsA(isA<PostgrestException>()));

    // Found out behind a saved copy on a cold start: the copy is dropped and the screen reads again.
    coldStart();
    var announced = 0;
    void listener() => announced++;
    OfflineCache.refreshed.addListener(listener);
    addTearDown(() => OfflineCache.refreshed.removeListener(listener));
    expect(await OfflineCache.readThrough('student_pass', () async => refused()), card);
    await settle();
    expect(announced, 1);
    await expectLater(OfflineCache.readThrough('student_pass', () async => offline()),
        throwsA(isA<SocketException>()), reason: 'the dropped copy is not served again');
  });

  test('each screen\'s data is saved on its own: one failing does not lose the others', () async {
    await OfflineCache.readThrough('student_pass', () async => card);
    await OfflineCache.readThrough('subscriptions', () async => ['sub']);
    await OfflineCache.readThrough('sale_catalog', () async => {'companies': ['c']});
    await settle();
    coldStart();
    expect(await OfflineCache.readThrough('student_pass', () async => offline()), card);
    expect(await OfflineCache.readThrough('subscriptions', () async => offline()), ['sub']);
    expect(await OfflineCache.readThrough('sale_catalog', () async => offline()), {'companies': ['c']});
  });
}
