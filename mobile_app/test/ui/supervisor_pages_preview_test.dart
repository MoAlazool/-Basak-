// Draws the supervisor's scanner, messages, inbox, account and month to PNG
// files with the app's real fonts, to hold against the canvas boards
// (SupScan*, SupSend*, SupInbox, SupProfile, SupMonthly). The camera cannot
// run in a test: the scanner's own dark surface stands in for its picture.
// Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-sup flutter test test/ui/supervisor_pages_preview_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/supervisor/monthly/presentation/supervisor_monthly_screen.dart';
import 'package:basak_mobile/features/supervisor/notifications/supervisor_notifications_screen.dart';
import 'package:basak_mobile/features/supervisor/profile/presentation/supervisor_profile_screen.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/presentation/scan_session.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/presentation/scanner_view.dart';
import 'package:basak_mobile/features/supervisor/selection/supervisor_selection.dart';

import '../support/notification_fakes.dart';
import '../support/supervisor_boards.dart';
import '../support/supervisor_pages.dart';

final _dir = Platform.environment['RENDER_DIR'];
final _key = GlobalKey();

Future<void> _fonts() async {
  Future<ByteData> file(String name) async =>
      ByteData.view((await File('assets/fonts/$name').readAsBytes()).buffer);
  final readex = FontLoader('ReadexPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    readex.addFont(file('ReadexPro-$f.ttf'));
  }
  await readex.load();
  await (FontLoader('Lucide')..addFont(file('lucide.ttf'))).load();
}

/// The screen as it stands now (a result that closes itself is not waited for).
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// The scanner already used this morning: fourteen aboard, Youssef the last.
class _UsedSession extends ScanSessionNotifier {
  @override
  ScanSession build() => ScanSession(
        boarded: 14,
        last: CheckInResult(
          outcome: CheckInOutcome.checkedIn,
          direction: 'departure',
          checkedInAt: DateTime(2026, 10, 11, 7, 17),
          student: boardStudent('يوسف طارق حسن', station: 'شرباص'),
        ),
        direction: 'departure',
      );
}

const _sizes = {'390': Size(390, 844), '360': Size(360, 640)};

AppNotification _alert(String id, String type, String title, String body, DateTime at,
        {bool read = true, String role = 'admin', String name = '', String audience = '', bool mine = false}) =>
    AppNotification(
      id: id,
      type: type,
      category: NotificationCategory.parse(null, type: type),
      title: title,
      body: body,
      createdAt: at,
      senderRole: role,
      senderName: name,
      audience: audience,
      read: read,
      mine: mine,
    );

/// The inbox of the `SupInbox` board, on today's date.
List<AppNotification> _inbox() {
  final now = DateTime.now();
  DateTime day(int ago, int hour, int minute) => DateTime(now.year, now.month, now.day - ago, hour, minute);
  return [
    _alert('n1', 'transport.delayed', 'تأخير في موعد الحافلة', 'ستتأخر الحافلة نحو 15 دقيقة.', day(0, 0, 4),
        role: 'supervisor', audience: 'ركاب ذهاب 7:00 ص', mine: true),
    _alert('n2', 'announcement.admin', 'تعديل موعد رحلة', 'إدارة الشركة: رحلة 7:45 ص تتحرك 7:55 ص من الغد.',
        day(0, 0, 2),
        read: false),
    _alert('n3', 'transport.departed', 'الحافلة تحركت', 'المشرف أحمد · عودة 3:30 م على خط الزرقا', day(1, 15, 31),
        read: false, role: 'supervisor', name: 'أحمد'),
    _alert('n4', 'announcement.supervisor', 'تغيير مكان الركوب', 'غداً الركوب من أمام البنك.', day(1, 17, 40),
        role: 'supervisor', audience: 'كل طلاب الخط', mine: true),
    _alert('n5', 'announcement.system', 'تحديث التطبيق', 'منصة باصك: نسخة جديدة متاحة للتحميل.', day(1, 9, 0),
        role: 'system'),
  ];
}

void main() {
  setUpAll(_fonts);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '2.4.0', buildNumber: '40', buildSignature: '');
    OfflineCache.offlineSince.value = null;
  });
  tearDown(() => OfflineCache.offlineSince.value = null);

  Future<void> scanner(WidgetTester tester, Size size,
      {CheckInOutcome? scan, ScanCameraState camera = ScanCameraState.ready, bool used = true}) async {
    await pumpBoard(
      tester,
      BoardWorld(),
      ScannerView(camera: const ScanBackdrop(), cameraState: camera),
      tab: 2,
      size: size,
      boundaryKey: _key,
      more: [
        supervisorRepoProvider.overrideWithValue(ScanRepo(boardScan(scan ?? CheckInOutcome.checkedIn))),
        if (used) scanSessionProvider.overrideWith(_UsedSession.new),
      ],
    );
    if (scan != null) {
      unawaited(tester.state<ScannerViewState>(find.byType(ScannerView)).handleCode('QR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  testWidgets('draw the scanner', (tester) async {
    debugDisableShadows = false;
    for (final MapEntry(key: w, value: size) in _sizes.entries) {
      await scanner(tester, size);
      await _shot(tester, 'scan_$w');

      OfflineCache.offlineSince.value = DateTime(2026, 10, 11, 6, 48);
      await scanner(tester, size);
      await _shot(tester, 'scan_offline_$w');
      OfflineCache.offlineSince.value = null;

      await scanner(tester, size, camera: ScanCameraState.denied);
      await _shot(tester, 'scan_permission_$w');

      for (final outcome in CheckInOutcome.values) {
        await scanner(tester, size, scan: outcome);
        await _shot(tester, 'scan_result_${outcome.name}_$w');
        // Leave nothing running for the next scene.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      }
    }
    debugDisableShadows = true;
  }, skip: _dir == null);

  testWidgets('draw the messages', (tester) async {
    debugDisableShadows = false;
    for (final MapEntry(key: w, value: size) in _sizes.entries) {
      final repo = FakeNotificationsRepo()..templates = boardTemplates;
      Future<void> open() async {
        await pumpBoard(tester, BoardWorld(), const SupervisorSendScreen(),
            tab: null, size: size, boundaryKey: _key, more: [notificationsRepoProvider.overrideWithValue(repo)]);
        // The 7:00 trip was picked on Trips.
        ProviderScope.containerOf(tester.element(find.byType(SupervisorSendScreen)))
            .read(supervisorSelectionProvider.notifier)
            .selectTrip(direction: TripDirection.departure, time: '07:00:00');
        await tester.pumpAndSettle();
      }

      await open();
      await _shot(tester, 'send_$w');

      await tester.tap(find.text('تأخير في موعد الحافلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await _shot(tester, 'send_confirm_$w');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('send-to-line')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('send-custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('send-body')), matching: find.byType(TextField)),
          'غداً الركوب من أمام البنك بدل الموقف.');
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('send-title')), matching: find.byType(TextField)),
          'تغيير مكان الركوب');
      await tester.pumpAndSettle();
      await _shot(tester, 'send_custom_$w');

      await tester.tap(find.byKey(const Key('send-continue')));
      await tester.pumpAndSettle();
      await _shot(tester, 'send_custom_confirm_$w');
      // The next size starts from an empty screen, not from these pages.
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugDisableShadows = true;
  }, skip: _dir == null);

  testWidgets('draw the inbox, the account and the month', (tester) async {
    debugDisableShadows = false;
    for (final MapEntry(key: w, value: size) in _sizes.entries) {
      await pumpBoard(tester, BoardWorld(), const SupervisorNotificationsScreen(),
          tab: null,
          size: size,
          boundaryKey: _key,
          more: [
            notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo(_inbox())),
            pushMessagingProvider.overrideWithValue(FakePushMessaging()),
          ]);
      await tester.pumpAndSettle();
      await _shot(tester, 'inbox_$w');

      for (final active in [true, false]) {
        await pumpBoard(tester, BoardWorld(dashboard: boardDashboard(active: active)), const SupervisorProfileScreen(),
            tab: 3,
            size: w == '390' ? const Size(390, 950) : size,
            boundaryKey: _key,
            more: [pushMessagingProvider.overrideWithValue(FakePushMessaging())]);
        await tester.pumpAndSettle();
        await _shot(tester, 'profile_${active ? 'active' : 'stopped'}_$w');
      }

      for (final (name, json) in [
        ('month', boardMonth()),
        ('month_long', boardMonth(days: 26)),
        ('month_empty', emptyMonth('2026-09-01')),
      ]) {
        await pumpBoard(tester, BoardWorld(), SupervisorMonthlyScreen(month: DateTime(2026, 10)),
            tab: null,
            size: w == '390' && name != 'month_empty' ? const Size(390, 1440) : size,
            boundaryKey: _key,
            more: [
              supervisorMonthlySummaryProvider
                  .overrideWith((ref, month) async => SupervisorMonthlySummary.fromJson(json)),
            ]);
        await tester.pumpAndSettle();
        await _shot(tester, '${name}_$w');
      }

      await pumpBoard(tester, BoardWorld(), SupervisorMonthlyScreen(month: DateTime(2026, 10)),
          tab: null,
          size: size,
          boundaryKey: _key,
          more: [
            supervisorMonthlySummaryProvider
                .overrideWith((ref, month) => Completer<SupervisorMonthlySummary>().future),
          ]);
      await tester.pump(const Duration(milliseconds: 300));
      await _shot(tester, 'month_loading_$w');
    }
    debugDisableShadows = true;
  }, skip: _dir == null);
}
