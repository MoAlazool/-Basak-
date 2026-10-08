import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';
import 'package:basak_mobile/core/widgets/glass_container.dart';

/// The student / supervisor shell in miniature: a scrolling tab body (with a
/// horizontal strip at the top) and the floating bar, wired the same way.
class _Shell extends StatefulWidget {
  final int rows;
  const _Shell({this.rows = 60});

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _currentIndex = 0;
  bool _navCollapsed = false;

  void _selectTab(int index) => setState(() {
        _currentIndex = index;
        _navCollapsed = false;
      });

  bool _onScroll(ScrollNotification notification) {
    final collapse = FloatingGlassNavBar.collapseOnScroll(notification);
    if (collapse != null && collapse != _navCollapsed) {
      setState(() => _navCollapsed = collapse);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView(
          key: const Key('body'),
          // Like the app's pull-to-refresh pages: drags register even on short pages.
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 80,
              child: ListView(
                key: const Key('strip'),
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < 20; i++) SizedBox(width: 120, child: Text('بطاقة $i'))],
              ),
            ),
            TextButton(onPressed: () => _selectTab(2), child: const Text('افتح المسح')),
            for (var i = 0; i < widget.rows; i++) SizedBox(height: 48, child: Text('صف $i')),
          ],
        ),
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _selectTab,
        items: FloatingGlassNavBar.supervisorNavItems,
        collapsed: _navCollapsed,
        onExpand: () => setState(() => _navCollapsed = false),
      ),
    );
  }
}

Widget _app({int rows = 60}) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: _Shell(rows: rows)),
    );

Rect _bar(WidgetTester tester) => tester.getRect(
    find.descendant(of: find.byType(FloatingGlassNavBar), matching: find.byType(GlassContainer)));

void main() {
  testWidgets('scrolling down shrinks the bar to a circle at the start side; up expands it',
      (tester) async {
    await tester.pumpWidget(_app());
    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(_bar(tester).width, screenWidth - 40);
    expect(find.text('الرحلات'), findsOneWidget);

    await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
    // Mid-animation: the tabs are clipped, never squeezed (an overflow fails the test).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    final mid = _bar(tester).width;
    expect(mid, lessThan(screenWidth - 40));
    expect(mid, greaterThan(FloatingGlassNavBar.height));
    await tester.pumpAndSettle();

    final circle = _bar(tester);
    expect(circle.size, const Size.square(FloatingGlassNavBar.height));
    expect(circle.right, screenWidth - 20, reason: 'RTL: the start side is the right');
    expect(find.text('الرحلات'), findsNothing);
    final selected = FloatingGlassNavBar.supervisorNavItems.first.activeIcon;
    expect(find.byIcon(selected), findsOneWidget);

    await tester.drag(find.byKey(const Key('body')), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(_bar(tester).width, screenWidth - 40);
    expect(find.text('الرحلات'), findsOneWidget);
  });

  testWidgets('the circle shows the selected tab; tapping it expands the bar on that tab',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('الرحلات'));
    await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_bar(tester).width, FloatingGlassNavBar.height);
    final trips = FloatingGlassNavBar.supervisorNavItems[1].activeIcon;
    expect(find.byIcon(trips), findsOneWidget);

    // The circle sits where the first tab was: the tap expands, it does not switch tabs.
    await tester.tap(find.byIcon(trips));
    await tester.pumpAndSettle();
    expect(find.text('الرحلات'), findsOneWidget);
    expect(_bar(tester).width, greaterThan(FloatingGlassNavBar.height));

    await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byIcon(trips), findsOneWidget);
  });

  testWidgets('changing tabs from the page expands the bar', (tester) async {
    await tester.pumpWidget(_app());
    await tester.drag(find.byKey(const Key('body')), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(_bar(tester).width, FloatingGlassNavBar.height);

    await tester.tap(find.text('افتح المسح'));
    await tester.pumpAndSettle();
    expect(find.text('مسح QR'), findsOneWidget);
    expect(_bar(tester).width, greaterThan(FloatingGlassNavBar.height));
  });

  testWidgets('horizontal scrolls and pages too short to scroll leave the bar alone',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.drag(find.byKey(const Key('strip')), const Offset(300, 0));
    await tester.drag(find.byKey(const Key('strip')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('الرحلات'), findsOneWidget);

    await tester.pumpWidget(_app(rows: 1));
    await tester.drag(find.byKey(const Key('body')), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('الرحلات'), findsOneWidget);
  });

  testWidgets('coming to rest at the top expands the bar', (tester) async {
    await tester.pumpWidget(_app());
    final context = tester.element(find.byKey(const Key('body')));
    UserScrollNotification at(double pixels, ScrollDirection direction) => UserScrollNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 2000,
            pixels: pixels,
            viewportDimension: 600,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          context: context,
          direction: direction,
        );

    expect(FloatingGlassNavBar.collapseOnScroll(at(0, ScrollDirection.idle)), isFalse);
    expect(FloatingGlassNavBar.collapseOnScroll(at(400, ScrollDirection.idle)), isNull);
    // A scroll down that starts at the top is reported before the content moves.
    expect(FloatingGlassNavBar.collapseOnScroll(at(0, ScrollDirection.reverse)), isTrue);
    expect(FloatingGlassNavBar.collapseOnScroll(at(400, ScrollDirection.forward)), isFalse);
  });
}
