// Draws every page of the term recap, the nine students' posters and the
// poster's five themes to PNG files with the app's real fonts: a look at the
// layout without a device, to hold against the canvas boards (Recap*).
// Skipped unless RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-recap flutter test test/ui/recap_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/student/recap/recap_copy.dart';
import 'package:basak_mobile/features/student/recap/recap_engine.dart';
import 'package:basak_mobile/features/student/recap/recap_screen.dart';

import '../support/recap_fixtures.dart';

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
  expect(tester.takeException(), isNull, reason: name);
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget child, {double top = 47}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(top: top, bottom: top > 30 ? 34 : 0)),
        child: RepaintBoundary(key: _key, child: page!),
      ),
      home: child,
    );

void main() {
  setUpAll(_fonts);
  final skip = _dir == null;

  for (final size in const [Size(390, 844), Size(360, 640)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    final students = <String, Map<String, dynamic> Function()>{'sara': sara, 'mariam': mariam, 'omar': omar};
    for (final entry in students.entries) {
      testWidgets('${entry.key}\'s recap at $tag', skip: skip, (tester) async {
        debugDisableShadows = false;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final recap = recapOf(entry.value(), key: keyDrawing('regular', 0, 6))!;
        await tester.pumpWidget(_app(RecapScreen(recap: recap), top: size.height > 700 ? 47 : 24));
        try {
          for (var i = 0; i < recap.pages.length; i++) {
            final kind = recap.pages[i].kind;
            // Sara's story is the whole of row 08; of the others only the pages that differ.
            if (entry.key == 'sara' || kind == RecapPageKind.days || kind == RecapPageKind.short || kind == RecapPageKind.share) {
              await _shot(tester, '${entry.key}_${(i + 1).toString().padLeft(2, '0')}_${kind.name}_$tag');
            }
            await tester.tapAt(const Offset(60, 400));
          }
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  }

  testWidgets('a long name, a long line and the other odd pages', skip: skip, (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final recap = recapOf(
      recapJson(
        rides: pick(studyDays(), 5, {0, 2, 3}),
        returning: (i) => null,
        college: 'الخدمة الاجتماعية',
        university: 'جامعة العلوم والتكنولوجيا بمدينة السادس من أكتوبر',
        stop: 'موقف سيارات المنصورة الجديدة الرئيسي',
        stations: [
          for (var i = 1; i <= 6; i++) 'محطة رقم $i',
          'موقف سيارات المنصورة الجديدة الرئيسي',
          for (var i = 8; i <= 14; i++) 'محطة رقم $i',
        ],
        line: 'المنصورة الجديدة السريع',
      ),
      key: keyDrawing('rarelyReturns', 0, 4),
    )!;
    await tester.pumpWidget(_app(RecapScreen(recap: recap), top: 24));
    for (var i = 0; i < recap.pages.length; i++) {
      await _shot(tester, 'odd_${(i + 1).toString().padLeft(2, '0')}_${recap.pages[i].kind.name}');
      await tester.tapAt(const Offset(60, 400));
    }
  });

  testWidgets('nine students, nine posters; and one poster in the five themes', skip: skip, (tester) async {
    tester.view.physicalSize = const Size(1040, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nine = [sara, yousef, nada, karim, menna, omar, mariam, ahmed, hadeer];
    // The board's theme for each, in its order.
    const themes = [
      PosterTheme.ink, PosterTheme.teal, PosterTheme.mint, PosterTheme.sky, PosterTheme.light,
      PosterTheme.ink, PosterTheme.sky, PosterTheme.mint, PosterTheme.teal,
    ];
    RecapPoster themed(RecapPoster p, PosterTheme theme) => RecapPoster(
          theme: theme,
          head: p.head,
          term: p.term,
          years: p.years,
          titleKicker: p.titleKicker,
          title: p.title,
          why: p.why,
          line: p.line,
          patternLabel: p.patternLabel,
          patternCount: p.patternCount,
          pattern: p.pattern,
          stats: p.stats,
          signature: p.signature,
          site: p.site,
        );
    Widget sheet(List<Widget> posters) => _app(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(spacing: 20, runSpacing: 20, children: [for (final p in posters) PosterFrame(child: p)]),
            ),
          ),
          top: 0,
        );

    await tester.pumpWidget(sheet([
      for (var i = 0; i < nine.length; i++)
        themed(RecapScreen.poster(recapOf(nine[i](), key: keyDrawing('x', 0, 1))!), themes[i]),
    ]));
    await _shot(tester, 'posters_nine');

    final one = RecapScreen.poster(recapOf(sara(), key: keyDrawing('regular', 0, 6))!);
    await tester.pumpWidget(sheet([for (final theme in PosterTheme.values) themed(one, theme)]));
    await _shot(tester, 'posters_five_themes');
  });

  testWidgets('the banner on Home', skip: skip, (tester) async {
    tester.view.physicalSize = const Size(390, 140);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: RecapBanner(title: RecapCopy.bannerTitle, message: recapOf(sara())!.bannerLine, onTap: () {}),
        ),
      ),
      top: 0,
    ));
    await _shot(tester, 'banner');
  });
}
