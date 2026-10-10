// Draws the rating sheet (both stores), the optional-update sheet and the
// required-update screen to PNG files with the app's real fonts, to hold
// against the boards RateIOS, RateAndroid, UpdateAvailable, UpdateRequired.
// Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-prompts flutter test test/ui/prompts_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/app_update/app_version.dart';
import 'package:basak_mobile/features/app_update/update_gate.dart';
import 'package:basak_mobile/features/rating/rating.dart';

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

/// What the boards draw behind a sheet: the shape of Home.
class _HomeShape extends StatelessWidget {
  const _HomeShape();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('سارة أحمد', style: context.text.title),
              const SizedBox(height: BasakSpace.s16),
              Container(
                height: 232,
                decoration: BoxDecoration(color: colors.ink, borderRadius: BasakRadius.all(BasakRadius.sheet)),
              ),
              const SizedBox(height: BasakSpace.s16),
              const BasakCard(child: SizedBox(height: 140)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<BuildContext> _frame(WidgetTester tester, Size size, Widget home, {double top = 47, double bottom = 34}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: top * 2, bottom: bottom * 2);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        // A new app each time: nothing of the frame before stays open.
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.element(find.byType(Scaffold).first);
}

final _update = AppUpdate.resolve(installed: '2.3.1', answer: const {
  'min_version': '2.5.0', 'latest_version': '2.5.0',
  'whats_new': ['بطاقة أوضح للمشرف عند الصعود', 'ملخّص الترم ومشاركته', 'تحسينات في السرعة وإصلاحات'],
  'store_url': 'https://play.google.com/store/apps/details?id=basak',
});

void main() {
  const sizes = {'390': Size(390, 844), '360': Size(360, 640)};

  testWidgets('draw the rating and update boards', (tester) async {
    await tester.runAsync(_fonts);
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      final small = size.height < 700;
      final top = small ? 24.0 : 47.0, bottom = small ? 0.0 : 34.0;

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var context = await _frame(tester, size, const _HomeShape(), top: top, bottom: bottom);
      RateSheet.show(context);
      await _shot(tester, 'rate-ios-$name');
      debugDefaultTargetPlatformOverride = null;

      context = await _frame(tester, size, const _HomeShape(), top: top, bottom: bottom);
      RateSheet.show(context);
      await _shot(tester, 'rate-android-$name');

      context = await _frame(tester, size, const _HomeShape(), top: top, bottom: bottom);
      UpdateAvailableSheet.show(context, _update);
      await _shot(tester, 'update-available-$name');

      await _frame(tester, size, UpdateRequiredScreen(update: _update, hasCard: true), top: top, bottom: bottom);
      await _shot(tester, 'update-required-$name');

      await _frame(tester, size, UpdateRequiredScreen(update: _update, hasCard: false), top: top, bottom: bottom);
      await _shot(tester, 'update-required-supervisor-$name');
    }
    debugDefaultTargetPlatformOverride = null;
  }, skip: _dir == null);
}
