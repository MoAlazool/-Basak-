// Draws the subscribe builder in each of its states, and the sheets it opens,
// to PNG files with the app's real fonts: a look at the layout without a
// device, to hold against the canvas boards (FlowCompany, FlowLines,
// FlowStation, FlowPeriod, FlowDaily, FlowConfirm, FlowEmpty). Skipped unless
// RENDER_DIR is set:
//   RENDER_DIR=/tmp/basak-subscribe flutter test test/ui/subscribe_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/theme/app_theme.dart';
import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';

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

Map<String, dynamic> _option(String code, num price, String start, String end) => {
      'option': code, 'academic_year': 2026, 'label': code, 'type': code == 'both' ? 'yearly' : 'termly',
      'start_date': start, 'end_date': end, 'phase': 'current', 'price': price,
    };

const _stops = [
  ('s1', 'موقف الزرقا', ['06:15', '07:00', '07:45', '08:30', '09:15']),
  ('s2', 'ميت الخولي', ['06:22', '07:07', '07:52', '08:37', '09:22']),
  ('s3', 'شرباص', ['06:30', '07:15', '08:00', '08:45', '09:30']),
  ('s4', 'كوبري السرو', ['06:38', '07:23', '08:08', '08:53', '09:38']),
  ('s5', 'السرو', ['06:45', '07:30', '08:15', '09:00', '09:45']),
  ('s6', 'الروضة', ['06:55', '07:40', '08:25', '09:10', '09:55']),
  ('s7', 'فارسكور', ['07:05', '07:50', '08:35', '09:20', '10:05']),
];

Map<String, dynamic> _line(String id, String name, int stops, num price, String first, String last,
        {num? daily, bool closed = false, int periods = 3}) =>
    {
      'id': id, 'name': name, 'origin_name': name, 'university': 'جامعة المنصورة الجديدة',
      'first_departure': '$first:00', 'last_return': '$last:00',
      'stations': [
        for (final (sid, sname, times) in _stops.take(stops))
          {
            'id': '$id-$sid', 'name': sname,
            'departures': [
              for (var i = 0; i < times.length; i++) {'trip_id': 't$i', 'time': '${times[i]}:00', 'label': ''},
            ],
          },
      ],
      'returns': [
        {'trip_id': 'r1', 'time': '15:30:00', 'label': ''},
      ],
      'options': closed
          ? const <Map<String, dynamic>>[]
          : [
              _option('first', price, '2026-09-20', '2027-01-14'),
              if (periods > 1) _option('second', price, '2027-02-07', '2027-05-28'),
              if (periods > 2) _option('both', price * 2 - 1000, '2026-09-20', '2027-05-28'),
              if (periods > 3) _option('summer', 1500, '2027-07-01', '2027-08-30'),
            ],
      'daily': {'enabled': daily != null, 'price': daily ?? 0},
    };

/// The data the boards are drawn with.
SaleCatalog _catalog({int companies = 2, int periods = 3}) => SaleCatalog.fromJson(jsonDecode(jsonEncode({
      'university': {'id': 'u1', 'name': 'جامعة المنصورة الجديدة'},
      'companies': [
        if (companies > 0)
          {
            'id': 'c1', 'name': 'النورس للنقل',
            'lines': [
              _line('l1', 'الزرقا', 7, 4500, '06:15', '17:30', daily: 60, periods: periods),
              _line('l2', 'فارسكور', 5, 4200, '06:30', '17:30'),
              _line('l3', 'كفر سعد', 6, 4800, '06:00', '16:30', daily: 40),
              _line('l4', 'شربين', 4, 0, '06:00', '16:30', closed: true),
            ],
          },
        if (companies > 1)
          {
            'id': 'c2', 'name': 'دلتا باص',
            'lines': [
              _line('l5', 'دمياط الجديدة', 3, 5000, '06:00', '16:00'),
              _line('l6', 'رأس البر', 4, 5200, '06:10', '16:00'),
            ],
          },
      ],
    })) as Map<String, dynamic>);

void main() {
  for (final size in const [Size(390, 844), Size(360, 640)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('draw the subscribe builder at $tag', (tester) async {
      await tester.runAsync(_fonts);
      Directory(_dir!).createSync(recursive: true);
      // Real shadows, as on a phone (tests draw them as solid blocks by default).
      debugDisableShadows = false;

      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$_dir/$name-$tag.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      Future<void> open(SaleCatalog catalog, {Widget? home, bool settle = true}) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        // A new page each time: nothing chosen is carried over.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            saleCatalogProvider.overrideWith((ref) async => catalog),
            subscriptionCreatorProvider.overrideWithValue((request) async => SubscriptionModel.fromJson({
                  'id': 'sub1', 'student_id': 'me', 'line_id': request.lineId, 'company_id': 'c1',
                  'station_id': request.stationId, 'type': request.type, 'status': 'pending_payment',
                  'price': request.price, 'created_at': '2026-10-08',
                })),
          ],
          child: RepaintBoundary(
            key: _key,
            child: MediaQuery(
              // A phone's status bar and home indicator.
              data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 47, bottom: 34)),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                useInheritedMediaQuery: true,
                theme: AppTheme.lightTheme,
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: home ?? const PurchaseFlowPage(),
              ),
            ),
          ),
        ));
        // The skeleton's pulse never settles: it is drawn at a fixed instant.
        settle ? await tester.pumpAndSettle() : await tester.pump();
      }

      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      // FlowCompany → FlowLines → FlowStation → FlowPeriod → FlowConfirm.
      await open(_catalog());
      await shot('1-company');
      await tap('company-c1');
      await shot('2-lines');
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await shot('2-lines-end');
      await tap('line-l1');
      await tap('station-l1-s4');
      await shot('3-station');
      await tap('station-confirm');
      await shot('4-period');
      await tap('option-first');
      await shot('4-period-chosen');
      await tap('flow-review');
      await shot('5-confirm');
      await tap('review-back');

      // FlowDaily.
      await tap('option-daily');
      await shot('6-daily');

      // One company (collapsed from the start), and each count of periods.
      for (final periods in [1, 2, 4]) {
        await open(_catalog(companies: 1, periods: periods));
        if (periods == 1) await shot('7-one-company');
        await tap('line-l1');
        await tap('station-l1-s1');
        await tap('station-confirm');
        if (periods == 4) await tap('option-both');
        await shot('8-periods-$periods');
      }

      // FlowEmpty, the first load and a failed one.
      await open(_catalog(companies: 0));
      await shot('9-empty');
      await open(_catalog(),
          settle: false,
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [PurchaseFlowSkeleton()]),
              ),
            ),
          ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_dir/10-skeleton-$tag.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: _dir == null);
  }
}
