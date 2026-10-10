// The shared pieces added after the redesign: the copy boxes (the box that
// was tapped says «تم النسخ» itself; no toast) and the company logo.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/ui/ui.dart';

import 'support/perf_fakes.dart' show onePixel;

Widget _app(Widget child, {bool lessMotion = false}) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: lessMotion),
          child: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(20), child: child))),
        ),
      ),
    );

/// The colour of the first tinted box inside [finder].
Color? _fill(WidgetTester tester, Finder finder) {
  final box = tester.widget<AnimatedContainer>(
      find.descendant(of: finder, matching: find.byType(AnimatedContainer)).first);
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  late List<String> copied;
  late List<String?> haptics;

  setUp(() {
    copied = [];
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String?);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  group('a copy box', () {
    testWidgets('the row: copies, turns green with a tick and «تم النسخ», then is itself again', (tester) async {
      await tester.pumpWidget(_app(const CopyRow(label: 'عنوان InstaPay', value: 'elnawras@instapay')));
      final row = find.byType(CopyRow);
      expect(find.text('نسخ'), findsOneWidget);
      expect(find.byIcon(LucideIcons.copy), findsOneWidget);
      expect(_fill(tester, row), BasakPalette.surface);

      // The whole row is the button, not only the word at its end.
      await tester.tap(find.text('elnawras@instapay'));
      await tester.pump();
      expect(copied, ['elnawras@instapay']);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_fill(tester, row), BasakPalette.successTint);
      expect(find.text('تم النسخ'), findsOneWidget);
      expect(find.text('نسخ'), findsNothing);
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(LucideIcons.check)).color, BasakPalette.success);
      // What was copied stays readable throughout.
      expect(find.text('عنوان InstaPay'), findsOneWidget);
      expect(find.text('elnawras@instapay'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: 'nothing comes up from the bottom');

      // Still green just before its time is up, and back after it.
      await tester.pump(BasakMotion.copied - const Duration(milliseconds: 400));
      expect(find.text('تم النسخ'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('نسخ'), findsOneWidget);
      expect(find.text('تم النسخ'), findsNothing);
      expect(_fill(tester, row), BasakPalette.surface);
    });

    testWidgets('it holds between 1.2 and 1.5 seconds, and a second tap starts the time again', (tester) async {
      expect(BasakMotion.copied, greaterThanOrEqualTo(const Duration(milliseconds: 1200)));
      expect(BasakMotion.copied, lessThanOrEqualTo(const Duration(milliseconds: 1500)));

      await tester.pumpWidget(_app(const CopyButton(label: 'نسخ الرقم', value: '01098765432')));
      await tester.tap(find.byType(CopyButton));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tap(find.byType(CopyButton));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('تم النسخ'), findsOneWidget, reason: 'counted from the second tap');
      expect(copied, ['01098765432', '01098765432']);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('نسخ الرقم'), findsOneWidget);
    });

    testWidgets('the button and the tile do the same in their own shapes', (tester) async {
      await tester.pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: const [
        CopyButton(label: 'نسخ المبلغ', value: '4500', variant: BasakButtonVariant.surface, expand: false),
        SizedBox(height: 20),
        SizedBox(width: 110, child: CopyTile(label: 'نسخ الرقم', value: '01012345678')),
      ])));
      expect(tester.getSize(find.byType(CopyButton)).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byType(CopyTile)).height, greaterThanOrEqualTo(72));

      await tester.tap(find.byType(CopyTile));
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, ['01012345678']);
      expect(_fill(tester, find.byType(CopyTile)), BasakPalette.successTint);
      expect(_fill(tester, find.byType(CopyButton)), BasakPalette.surface, reason: 'only the box that was tapped');
      expect(find.descendant(of: find.byType(CopyTile), matching: find.text('تم النسخ')), findsOneWidget);
      expect(find.text('نسخ المبلغ'), findsOneWidget);
      await tester.pump(BasakMotion.copied);
      await tester.pumpAndSettle();
      expect(find.text('تم النسخ'), findsNothing);
    });

    testWidgets('nothing to copy: drawn disabled, and a tap does nothing', (tester) async {
      await tester.pumpWidget(_app(const CopyButton(label: 'نسخ الرقم', value: null)));
      await tester.tap(find.byType(CopyButton), warnIfMissed: false);
      await tester.pump();
      expect(copied, isEmpty);
      expect(find.text('تم النسخ'), findsNothing);
    });

    testWidgets('it is a button to a screen reader, and says «تم النسخ» when it has copied', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const CopyRow(label: 'رقم الحساب', value: '0123 4567')));
      expect(
        tester.getSemantics(find.bySemanticsLabel('نسخ رقم الحساب، 0123 4567')),
        matchesSemantics(label: 'نسخ رقم الحساب، 0123 4567', isButton: true, isEnabled: true,
            hasEnabledState: true, hasTapAction: true),
      );
      await tester.tap(find.byType(CopyRow));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getSemantics(find.bySemanticsLabel('تم النسخ')),
        matchesSemantics(label: 'تم النسخ', isButton: true, isEnabled: true, hasEnabledState: true,
            hasTapAction: true, isLiveRegion: true),
        reason: 'said without being asked',
      );
      await tester.pump(BasakMotion.copied);
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('with reduce motion the colour changes at once', (tester) async {
      await tester.pumpWidget(_app(const CopyRow(label: 'IBAN', value: 'EG00'), lessMotion: true));
      await tester.tap(find.byType(CopyRow));
      await tester.pump();
      expect(find.text('تم النسخ'), findsOneWidget);
      expect(find.text('نسخ'), findsNothing);
      await tester.pump(BasakMotion.copied);
      await tester.pump();
      expect(find.text('نسخ'), findsOneWidget);
    });

    testWidgets('a long address is cut with its row intact, at the largest text too', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: PayeeCard(name: 'شركة النورس للنقل والرحلات الجامعية', method: 'تحويل بنكي', fields: const [
                CopyField(label: 'IBAN', value: 'EG00 0003 0000 0000 0000 0000 0000 0000 0000'),
              ]),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(CopyRow));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pump(BasakMotion.copied);
      await tester.pumpAndSettle();
    });
  });

  group('a company picture\'s address', () {
    const company = '0b6f3c1e-8a2d-4e5f-9c7b-1d2e3f4a5b6c';
    const logo = '$company/logo/1760000000000';
    const emblem = '$company/emblem/v2_AbC-9';
    const base = 'https://example.supabase.co';
    const root = '$base/storage/v1/object/public/wallet-assets';

    test('the emblem: the small file up to a 64 box, the large one above it', () {
      const brand = CompanyBrand(logoPath: logo, emblemPath: emblem);
      expect(brand.markUrl(24, base: base), '$root/$emblem/small.png');
      expect(brand.markUrl(64, base: base), '$root/$emblem/small.png');
      expect(brand.markUrl(65, base: base), '$root/$emblem/master.png');
      expect(brand.hasMark, isTrue);
    });

    test('no emblem: the logo on its square; neither: nothing, and the initial stands in', () {
      expect(const CompanyBrand(logoPath: logo).markUrl(40, base: base), '$root/$logo/google.png');
      expect(const CompanyBrand(logoPath: logo).markUrl(200, base: base), '$root/$logo/google.png');
      expect(CompanyBrand.none.markUrl(40, base: base), isNull);
      expect(CompanyBrand.none.hasMark, isFalse);
      expect(CompanyBrand.none.logoUrl(base: base), isNull);
    });

    test('the full logo is its master file, for the receipt too', () {
      expect(const CompanyBrand(logoPath: logo).logoUrl(base: base), '$root/$logo/master.png');
      expect(CompanyBrand.logoFileUrl(logo, base: base), '$root/$logo/master.png');
      expect(CompanyBrand.logoFileUrl(null), isNull);
      expect(CompanyBrand.logoFileUrl(''), isNull);
    });

    test('the address is the project\'s own public bucket, with no query string', () {
      final url = const CompanyBrand(emblemPath: emblem).markUrl(40)!;
      expect(url, startsWith('https://'));
      expect(url, contains('/storage/v1/object/public/wallet-assets/'));
      expect(Uri.parse(url).hasQuery, isFalse);
    });

    test('only a folder the server would name is ever put into an address', () {
      for (final bad in [
        'https://evil.example/x.png',
        '../$logo',
        '$company/logo/../../secret',
        '$company/logo/a b',
        '$company/logo/',
        '$company/logo/${'a' * 65}',
        '$company/avatar/1',
        '${company.toUpperCase()}/logo/1',
        'short/logo/1',
        '$logo/master.png',
        '$logo?download=1',
        ' $logo',
      ]) {
        expect(CompanyBrand.isValidPath(bad), isFalse, reason: bad);
        expect(CompanyBrand(logoPath: bad, emblemPath: bad).markUrl(40), isNull, reason: bad);
        expect(CompanyBrand.logoFileUrl(bad), isNull, reason: bad);
      }
      expect(CompanyBrand.isValidPath(logo), isTrue);
      expect(CompanyBrand.isValidPath(emblem), isTrue);
      // A bad emblem does not hide a good logo.
      expect(const CompanyBrand(logoPath: logo, emblemPath: 'x').markUrl(40, base: base), '$root/$logo/google.png');
    });

    test('fields that are null, absent or not text read as no picture', () {
      expect(CompanyBrand.fromJson({'id': 'c', 'name': 'النورس'}), CompanyBrand.none, reason: 'an older server');
      expect(CompanyBrand.fromJson({'logo_path': null, 'emblem_path': null}), CompanyBrand.none);
      expect(CompanyBrand.fromJson({'logo_path': '', 'emblem_path': 7}), CompanyBrand.none);
      expect(CompanyBrand.fromJson(null), CompanyBrand.none, reason: 'a suspended company embeds as null');
      expect(CompanyBrand.fromJson({'logo_path': logo, 'emblem_path': emblem}),
          const CompanyBrand(logoPath: logo, emblemPath: emblem));
    });
  });

  group('a company logo', () {
    const company = '0b6f3c1e-8a2d-4e5f-9c7b-1d2e3f4a5b6c';
    final asked = <String>[];
    setUp(() {
      asked.clear();
      debugCompanyLogoImage = (url) {
        asked.add(url);
        return MemoryImage(onePixel);
      };
    });
    tearDown(() => debugCompanyLogoImage = null);

    test('initials: the first letters of the two telling words', () {
      expect(CompanyLogo.initialsOf('شركة النورس للنقل'), 'ن ل');
      expect(CompanyLogo.initialsOf('المستقبل'), 'م');
      expect(CompanyLogo.initialsOf('Delta bus'), 'DB');
      expect(CompanyLogo.initialsOf('شركة'), 'ش');
      expect(CompanyLogo.initialsOf('  '), '');
    });

    testWidgets('with an emblem: the emblem, sized for its box', (tester) async {
      const brand = CompanyBrand(logoPath: '$company/logo/1', emblemPath: '$company/emblem/2');
      await tester.pumpWidget(_app(CompanyLogo(name: 'النورس', brand: brand, size: 48)));
      await tester.pumpAndSettle();
      expect(asked.single, endsWith('/$company/emblem/2/small.png'));
      expect(find.byKey(const Key('company-logo-image')), findsOneWidget);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      expect(tester.getSize(find.byType(CompanyLogo)), const Size(48, 48));

      await tester.pumpWidget(_app(CompanyLogo(name: 'النورس', brand: brand, size: 96)));
      await tester.pumpAndSettle();
      expect(asked.last, endsWith('/$company/emblem/2/master.png'));
    });

    testWidgets('without an emblem: the logo on its square', (tester) async {
      await tester.pumpWidget(
          _app(CompanyLogo(name: 'النورس', brand: const CompanyBrand(logoPath: '$company/logo/1'))));
      await tester.pumpAndSettle();
      expect(asked.single, endsWith('/$company/logo/1/google.png'));
      expect(find.byKey(const Key('company-logo-image')), findsOneWidget);
    });

    testWidgets('with neither, or with paths the app does not trust: the initials, and nothing is asked for',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(CompanyLogo(name: 'شركة النورس للنقل', size: 48)));
      expect(find.text('ن ل'), findsOneWidget);
      expect(tester.getSize(find.byType(CompanyLogo)), const Size(48, 48));
      expect(find.bySemanticsLabel('شعار شركة النورس للنقل'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(_app(CompanyLogo(
          name: 'النورس', brand: const CompanyBrand(logoPath: 'https://evil.example/a.png', emblemPath: '../x'))));
      expect(find.byType(Image), findsNothing);
      expect(find.text('ن'), findsOneWidget);
      expect(asked, isEmpty);
      handle.dispose();
    });

    testWidgets('a picture that cannot be read falls back to the initials, in the same box', (tester) async {
      await tester.pumpWidget(_app(CompanyLogo.image(
          name: 'النورس للنقل', image: MemoryImage(Uint8List.fromList([1, 2, 3])), size: 40)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ن ل'), findsOneWidget);
      expect(find.byKey(const Key('company-logo-image')), findsNothing);
      expect(tester.getSize(find.byType(CompanyLogo)), const Size(40, 40));
    });

    testWidgets('where a placeholder is given it stands in instead of the initials, in the same box',
        (tester) async {
      await tester.pumpWidget(_app(CompanyLogo.image(
        name: 'النورس',
        image: MemoryImage(Uint8List.fromList([1, 2, 3])),
        size: 40,
        radius: BasakRadius.tile,
        placeholder: const Icon(LucideIcons.bus),
      )));
      // The first frame: nothing decoded yet, and the box is already its size.
      expect(tester.getSize(find.byType(CompanyLogo)), const Size(40, 40));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.bus), findsOneWidget);
      expect(find.text('ن'), findsNothing);
      expect(tester.getSize(find.byType(CompanyLogo)), const Size(40, 40));
    });
  });
}
