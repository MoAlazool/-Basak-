// What the app's root guarantees for every screen (main.dart `BasakRoot`), and
// the toast that follows a refused camera or photos permission.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/media/picker_errors.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/main.dart';

void main() {
  Future<double> scaleUnderRoot(WidgetTester tester, double phoneScale) async {
    late double seen;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(phoneScale)),
        child: BasakRoot(child: child!),
      ),
      home: Builder(builder: (context) {
        seen = MediaQuery.textScalerOf(context).scale(100) / 100;
        return const SizedBox.shrink();
      }),
    ));
    return seen;
  }

  testWidgets('text follows the phone from 1.0 to 1.3 and no further', (tester) async {
    expect(await scaleUnderRoot(tester, 1.0), closeTo(1.0, .001));
    expect(await scaleUnderRoot(tester, 1.15), closeTo(1.15, .001));
    expect(await scaleUnderRoot(tester, 1.3), closeTo(1.3, .001));
    expect(await scaleUnderRoot(tester, 2.0), closeTo(basakMaxTextScale, .001));
    expect(await scaleUnderRoot(tester, .8), closeTo(1.0, .001));
  });

  testWidgets('the status bar has dark icons unless a dark page says otherwise', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BasakRoot(child: SizedBox.expand())));
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(of: find.byType(BasakRoot), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)));
    expect(region.value.statusBarIconBrightness, Brightness.dark);
    expect(BasakChrome.onDark().statusBarIconBrightness, Brightness.light);
    expect(BasakChrome.onDark(BasakPalette.scanBase).systemNavigationBarColor, BasakPalette.scanBase);
  });

  testWidgets('a refused permission is told with the way to the settings', (tester) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        page = context;
        return const SizedBox.expand();
      })),
    ));

    showPickerError(page, PlatformException(code: 'camera_access_denied'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا يوجد إذن لاستخدام الكاميرا'), findsOneWidget);
    expect(find.text('فتح الإعدادات'), findsOneWidget);
    // Tapping it closes the toast (the settings themselves are the phone's).
    await tester.tap(find.text('فتح الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.text('فتح الإعدادات'), findsNothing);

    showPickerError(page, PlatformException(code: 'photo_access_denied'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا يوجد إذن للوصول إلى الصور'), findsOneWidget);
    expect(find.text('فتح الإعدادات'), findsOneWidget);

    // Anything else is only told.
    showPickerError(page, PlatformException(code: 'no_available_camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا توجد كاميرا متاحة على هذا الجهاز.'), findsOneWidget);
    expect(find.text('فتح الإعدادات'), findsNothing);
  });
}
