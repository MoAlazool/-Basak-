// Draws the subscription screens to PNG files with the app's real fonts, for a
// look at the layout without a device. Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-preview flutter test test/render_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/features/student/subscription/models/payment_method_model.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import 'subscription_flow_test.dart' as fixtures;

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

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _open(WidgetTester tester, List<SubscriptionModel> subs, {SubscriptionReceipt? doc, double height = 874}) async {
  tester.view.physicalSize = Size(402 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      allSubscriptionsProvider.overrideWith((ref) async => subs),
      saleCatalogProvider.overrideWith((ref) async => fixtures.catalog()),
      subscriptionReceiptsProvider.overrideWith((ref, id) async => <ReceiptModel>[]),
      subscriptionReceiptDocProvider.overrideWith((ref, id) async => doc),
      paymentMethodsProvider.overrideWith((ref, id) async => [
            PaymentMethodModel.fromJson({
              'id': 'm1', 'company_id': 'c1', 'method_type': 'instapay', 'display_name': 'InstaPay',
              'instapay_address': 'almostaqbal@instapay', 'account_holder': 'شركة المستقبل',
              'instructions': 'اكتب اسم الطالب في خانة الملاحظات عند التحويل.', 'is_active': true, 'sort_order': 0,
            }),
            PaymentMethodModel.fromJson({
              'id': 'm2', 'company_id': 'c1', 'method_type': 'vodafone_cash', 'display_name': 'فودافون كاش',
              'wallet_phone': '01012345678', 'is_active': true, 'sort_order': 1,
            }),
          ]),
    ],
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SubscriptionScreen(),
      ),
    ),
  ));
}

void main() {
  testWidgets('draw the subscription screens', (tester) async {
    await tester.runAsync(_fonts);
    Directory(_dir!).createSync(recursive: true);
    Future<void> tap(String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    await _open(tester, []);
    await _shot(tester, '1-company');
    await tap('company-c1');
    await _shot(tester, '2-line');
    await tap('line-l1');
    await _shot(tester, '3-station');
    await tap('station-s2');
    await _shot(tester, '4-period');
    await tap('option-both');
    await _shot(tester, '5-review');

    await _open(tester, [fixtures.subscription('pending_payment')], height: 1250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('InstaPay').first);
    await _shot(tester, '6-payment');
    await _open(tester, [fixtures.subscription('active')], doc: fixtures.receipt, height: 1150);
    await _shot(tester, '7-approved');
  }, skip: _dir == null);
}
