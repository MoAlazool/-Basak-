import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:basak_mobile/core/network/network_errors.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/widgets/connection_strip_host.dart';

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

  test('the time of the saved data is short for today and dated otherwise', () {
    final now = DateTime(2026, 10, 4, 12);
    expect(ConnectionStripHost.dataTime(DateTime(2026, 10, 4, 8, 5), now), '8:05 ص');
    expect(ConnectionStripHost.dataTime(DateTime(2026, 10, 3, 21, 40), now), '3 أكتوبر 9:40 م');
  });

  // The supervisor's shell shows the connection strip above its tabs (it was
  // the offline banner before the redesign).
  testWidgets('the connection strip appears only while showing saved data, then says the connection is back',
      (tester) async {
    addTearDown(OfflineCache.markOnline);
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ConnectionStripHost(
            onRetry: () => retried++,
            note: 'المسح لا يسجّل الصعود الآن',
            child: const Text('content'),
          ),
        ),
      ),
    ));
    expect(find.textContaining('بدون إنترنت'), findsNothing);

    final now = DateTime.now();
    OfflineCache.markOffline(DateTime(now.year, now.month, now.day, 8, 5));
    await tester.pumpAndSettle();
    expect(find.text('بدون إنترنت · بيانات 8:05 ص · المسح لا يسجّل الصعود الآن'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    expect(retried, 1);

    OfflineCache.markOnline();
    await tester.pumpAndSettle();
    expect(find.textContaining('بدون إنترنت'), findsNothing);
    expect(find.text('عاد الاتصال · البيانات محدّثة'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
    // The green strip leaves by itself.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('عاد الاتصال'), findsNothing);
  });
}
