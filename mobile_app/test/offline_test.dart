import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:basak_mobile/core/network/network_errors.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/widgets/offline_banner.dart';

void main() {
  test('network failures are told apart from server errors', () {
    expect(isNetworkFailure(const SocketException('Failed host lookup')), isTrue);
    expect(isNetworkFailure(TimeoutException('slow')), isTrue);
    expect(isNetworkFailure(Exception('ClientException with SocketException')), isTrue);
    expect(isNetworkFailure(AuthRetryableFetchException()), isTrue);
    expect(
        isNetworkFailure(const PostgrestException(message: 'permission denied', code: '42501')),
        isFalse);
    expect(isNetworkFailure(Exception('الرقم مستخدم بالفعل.')), isFalse);
  });

  test('errorMessage hides socket noise and the Exception prefix', () {
    expect(errorMessage(const SocketException('Failed host lookup')), offlineActionMessage);
    expect(errorMessage(Exception('فشل تأكيد حضور الرحلة.')), 'فشل تأكيد حضور الرحلة.');
  });

  test('requireOnline turns a network failure into the offline message', () async {
    await expectLater(
      requireOnline<void>(() => throw const SocketException('down')),
      throwsA(predicate((e) => e.toString().contains(offlineActionMessage))),
    );
    await expectLater(
      requireOnline<void>(() => throw Exception('server said no')),
      throwsA(predicate((e) => e.toString().contains('server said no'))),
    );
    expect(await requireOnline(() async => 7), 7);
  });

  test('readThrough without a signed-in user just runs the query', () async {
    expect(await OfflineCache.readThrough('k', () async => [1, 2]), [1, 2]);
  });

  test('saved-at label is short for today and dated otherwise', () {
    final now = DateTime(2026, 10, 4, 12);
    expect(OfflineBanner.savedAtLabel(DateTime(2026, 10, 4, 8, 5), now), 'اليوم 08:05');
    expect(OfflineBanner.savedAtLabel(DateTime(2026, 10, 3, 21, 40), now), '2026/10/03 21:40');
  });

  testWidgets('offline banner appears only while showing saved data', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: OfflineBanner(child: Text('content'))),
    ));
    expect(find.textContaining('غير متصل'), findsNothing);

    OfflineCache.markOffline(DateTime.now());
    await tester.pump();
    expect(find.textContaining('غير متصل'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    OfflineCache.markOnline();
    await tester.pump();
    expect(find.textContaining('غير متصل'), findsNothing);
  });
}
