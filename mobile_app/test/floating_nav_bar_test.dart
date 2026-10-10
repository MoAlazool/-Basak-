import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basak_mobile/core/ui/tokens.dart';
import 'package:basak_mobile/core/widgets/floating_glass_nav_bar.dart';

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
      ),
    );
  }
}

Widget _app({int rows = 60, TextDirection direction = TextDirection.rtl}) => MaterialApp(
      home: Directionality(textDirection: direction, child: _Shell(rows: rows)),
    );

/// The phone's accessibility switches, for one test.
void _phoneAsks(WidgetTester tester, {bool lessMotion = false, bool moreContrast = false}) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: lessMotion, highContrast: moreContrast);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

int _selected(WidgetTester tester) =>
    tester.widget<FloatingGlassNavBar>(find.byType(FloatingGlassNavBar)).currentIndex;

Rect _bar(WidgetTester tester) => tester.getRect(find.byKey(const Key('nav-pill')));

void main() {
  testWidgets('scrolling down folds the labels and lowers the pill, keeping every tab; up restores it',
      (tester) async {
    await tester.pumpWidget(_app());
    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final fullWidth = screenWidth - 2 * FloatingGlassNavBar.sideMargin;
    expect(_bar(tester).size, Size(fullWidth, FloatingGlassNavBar.height));
    expect(find.text('الرحلات'), findsOneWidget);

    await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
    // Mid-animation: the labels are clipped, never squeezed (an overflow fails the test).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    final mid = _bar(tester).height;
    expect(mid, lessThan(FloatingGlassNavBar.height));
    expect(mid, greaterThan(FloatingGlassNavBar.collapsedHeight));
    await tester.pumpAndSettle();

    expect(_bar(tester).size, Size(fullWidth, FloatingGlassNavBar.collapsedHeight));
    expect(find.text('الرحلات'), findsNothing);
    for (final item in FloatingGlassNavBar.supervisorNavItems) {
      expect(find.byIcon(item.icon), findsOneWidget, reason: '${item.label} stays one tap away');
    }

    await tester.drag(find.byKey(const Key('body')), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(_bar(tester).size, Size(fullWidth, FloatingGlassNavBar.height));
    expect(find.text('الرحلات'), findsOneWidget);
  });

  testWidgets('collapsed, another tab is one tap away; choosing it brings the labels back',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_bar(tester).height, FloatingGlassNavBar.collapsedHeight);
    expect(find.text('الرحلات'), findsNothing);

    final trips = FloatingGlassNavBar.supervisorNavItems[1];
    await tester.tap(find.byIcon(trips.icon));
    await tester.pumpAndSettle();
    expect(find.text('الرحلات'), findsOneWidget);
    expect(_bar(tester).height, FloatingGlassNavBar.height);
    expect(
      tester.getSemantics(find.bySemanticsLabel(trips.label)),
      matchesSemantics(label: trips.label, isButton: true, isSelected: true, hasSelectedState: true,
          isEnabled: true, hasEnabledState: true, hasTapAction: true),
    );
  });

  testWidgets('changing tabs from the page expands the bar', (tester) async {
    await tester.pumpWidget(_app());
    await tester.drag(find.byKey(const Key('body')), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(_bar(tester).height, FloatingGlassNavBar.collapsedHeight);

    await tester.tap(find.text('افتح المسح'));
    await tester.pumpAndSettle();
    expect(find.text('مسح'), findsOneWidget);
    expect(_bar(tester).height, FloatingGlassNavBar.height);
  });

  testWidgets('every tab is at least 48 wide and tall, collapsed too', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    for (final collapsed in [false, true]) {
      if (collapsed) {
        await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      for (final item in FloatingGlassNavBar.supervisorNavItems) {
        final size = tester.getSize(find.bySemanticsLabel(item.label));
        expect(size.width, greaterThanOrEqualTo(48), reason: item.label);
        expect(size.height, greaterThanOrEqualTo(48), reason: item.label);
      }
    }
  });

  testWidgets('the ink pill sits behind the selected tab and slides to the one that is chosen',
      (tester) async {
    await tester.pumpWidget(_app());
    final items = FloatingGlassNavBar.supervisorNavItems;
    Rect pill() => tester.getRect(find.byKey(const Key('nav-indicator')));
    double centre(int index) => tester.getCenter(find.byIcon(items[index].icon)).dx;

    expect(pill().center.dx, moreOrLessEquals(centre(0), epsilon: .5));
    expect(pill().size, _restingLens(tester));

    await tester.tap(find.text(items[2].label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    // On its way: between the two tabs (RTL, so the third tab is to the left).
    expect(pill().center.dx, lessThan(centre(0)));
    expect(pill().center.dx, greaterThan(centre(2)));
    await tester.pumpAndSettle();
    expect(pill().center.dx, moreOrLessEquals(centre(2), epsilon: .5));
    // The lens is the whole tab's, so its icon is inside it rather than at its centre.
    expect(pill().contains(tester.getCenter(find.byIcon(items[2].icon))), isTrue);

    // Collapsed, it stays behind the same icon.
    await tester.drag(find.byKey(const Key('body')), const Offset(0, -300));
    await tester.pumpAndSettle();
    // Over the whole tab now, so centred on it across the bar and around its icon.
    expect(pill().center.dx, moreOrLessEquals(centre(2), epsilon: .5));
    expect(pill().contains(tester.getCenter(find.byIcon(items[2].icon))), isTrue);
  });

  testWidgets('the lens covers the whole selected tab, its icon and its label, as one capsule',
      (tester) async {
    await tester.pumpWidget(_app());
    final items = FloatingGlassNavBar.supervisorNavItems;
    final lens = tester.getRect(find.byKey(const Key('nav-indicator')));
    final icon = tester.getRect(find.byIcon(items[0].icon));
    final label = tester.getRect(find.text(items[0].label));
    expect(lens.contains(icon.topLeft) && lens.contains(icon.bottomRight), isTrue, reason: 'the icon is under it');
    expect(lens.contains(label.topLeft) && lens.contains(label.bottomRight), isTrue, reason: 'the label is under it');
    // Not the next tab's.
    expect(lens.overlaps(tester.getRect(find.byIcon(items[1].icon))), isFalse);
    // The label on the lens is white, like the icon.
    expect(tester.widget<Text>(find.text(items[0].label)).style!.color, BasakPalette.surface);
    expect(tester.widget<Text>(find.text(items[1].label)).style!.color, isNot(BasakPalette.surface));
  });

  group('the glass and its lens', () {
    Rect lens(WidgetTester tester) => tester.getRect(find.byKey(const Key('nav-indicator')));
    final items = FloatingGlassNavBar.supervisorNavItems;
    double centre(WidgetTester tester, int index) => tester.getCenter(find.byIcon(items[index].icon)).dx;

    testWidgets('the bar is glass over the page, in a layer of its own', (tester) async {
      await tester.pumpWidget(_app());
      expect(find.byKey(const Key('nav-glass')), findsOneWidget);
      expect(find.byKey(const Key('nav-solid')), findsNothing);
      expect(find.descendant(of: find.byType(FloatingGlassNavBar), matching: find.byType(RepaintBoundary)),
          findsWidgets);
    });

    testWidgets('the lens stretches on its way, lands a little past its tab and settles at its own size',
        (tester) async {
      await tester.pumpWidget(_app());
      await tester.tap(find.text(items[3].label));
      await tester.pump();
      var widest = 0.0;
      var furthest = double.infinity;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        widest = widest < lens(tester).width ? lens(tester).width : widest;
        furthest = furthest > lens(tester).center.dx ? lens(tester).center.dx : furthest;
      }
      expect(widest, greaterThan(_restingLens(tester).width + 4), reason: 'longer while it travels');
      // RTL: the fourth tab is the leftmost; the spring carries the lens a touch beyond it.
      expect(furthest, lessThan(centre(tester, 3)));
      await tester.pumpAndSettle();
      expect(lens(tester).size, _restingLens(tester));
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, 3), epsilon: .5));
    });

    testWidgets('the icon under the lens is white and full size; the others are quiet and a little smaller',
        (tester) async {
      await tester.pumpWidget(_app());
      Icon icon(int index) => tester.widget<Icon>(find.byIcon(items[index].icon));
      double scale(int index) => tester
          .widget<Transform>(find.ancestor(of: find.byIcon(items[index].icon), matching: find.byType(Transform)).first)
          .transform
          .entry(0, 0);
      expect(icon(0).color, BasakPalette.surface);
      expect(icon(1).color, BasakPalette.ink);
      expect(scale(0), 1);
      expect(scale(1), lessThan(1));

      // Half way to the next tab both are part white: they cross-fade.
      await tester.tap(find.text(items[1].label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(icon(0).color, isNot(anyOf(BasakPalette.surface, BasakPalette.ink)));
      expect(icon(1).color, isNot(anyOf(BasakPalette.surface, BasakPalette.ink)));
      await tester.pumpAndSettle();
      expect(icon(1).color, BasakPalette.surface);
      expect(icon(0).color, BasakPalette.ink);
    });

    testWidgets('a tab change clicks', (tester) async {
      final haptics = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String?);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(_app());
      await tester.tap(find.text(items[1].label));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('reduce motion: the lens is simply on the chosen tab, with no spring and no stretch',
        (tester) async {
      _phoneAsks(tester, lessMotion: true);
      await tester.pumpWidget(_app());
      await tester.tap(find.text(items[2].label));
      await tester.pump();
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, 2), epsilon: .5));
      expect(lens(tester).size, _restingLens(tester));
      expect(_selected(tester), 2);
    });

    testWidgets('increase contrast (or reduce transparency): the solid white bar, with no blur', (tester) async {
      _phoneAsks(tester, moreContrast: true);
      await tester.pumpWidget(_app());
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const Key('nav-solid')), findsOneWidget);
      // Everything else is the same bar.
      await tester.tap(find.text(items[1].label));
      await tester.pumpAndSettle();
      expect(_selected(tester), 1);
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, 1), epsilon: .5));

      // The iPhone's own «تقليل الشفافية», which the app asks the phone about.
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-glass')), findsOneWidget);
      BasakGlass.reduceTransparency.value = true;
      addTearDown(() => BasakGlass.reduceTransparency.value = false);
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a page that must not pay for a blur can ask for the solid bar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar:
              FloatingGlassNavBar(currentIndex: 0, onTabSelected: (_) {}, items: items, glass: false),
        ),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a drag along the bar carries the lens and chooses the tab it is let go on', (tester) async {
      await tester.pumpWidget(_app());
      final from = tester.getCenter(find.byIcon(items[0].icon));
      final to = tester.getCenter(find.byIcon(items[2].icon));
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset((from.dx + to.dx) / 2, from.dy));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      expect(_selected(tester), 0, reason: 'nothing is chosen until the finger lifts');
      expect(lens(tester).center.dx, moreOrLessEquals(to.dx, epsilon: 1), reason: 'the lens is under the finger');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_selected(tester), 2);
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, 2), epsilon: .5));

      // Let go between two tabs: the nearer one.
      final back = await tester.startGesture(to);
      await back.moveTo(Offset(to.dx + (from.dx - to.dx) * .2, to.dy + 2));
      await tester.pump();
      await back.moveTo(Offset(to.dx + (from.dx - to.dx) * .3, to.dy));
      await back.up();
      await tester.pumpAndSettle();
      expect(_selected(tester), 1, reason: '0.6 of a tab away from the third: the second is nearer');
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, _selected(tester)), epsilon: .5));
    });

    testWidgets('left to right the lens follows the same tabs, mirrored', (tester) async {
      await tester.pumpWidget(_app(direction: TextDirection.ltr));
      expect(centre(tester, 0), lessThan(centre(tester, 3)));
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, 0), epsilon: .5));
      await tester.tap(find.text(items[3].label));
      await tester.pumpAndSettle();
      expect(lens(tester).center.dx, moreOrLessEquals(centre(tester, 3), epsilon: .5));
    });
  });

  testWidgets('horizontal scrolls leave the bar alone; a page too short to scroll has its labels back at rest',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.drag(find.byKey(const Key('strip')), const Offset(300, 0));
    await tester.drag(find.byKey(const Key('strip')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('الرحلات'), findsOneWidget);

    // A short page: the pull folds the labels while it lasts, and at rest they are back.
    await tester.pumpWidget(_app(rows: 1));
    final pull = await tester.startGesture(tester.getCenter(find.byKey(const Key('body'))));
    await pull.moveBy(const Offset(0, -40));
    await pull.moveBy(const Offset(0, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_bar(tester).height, lessThan(FloatingGlassNavBar.height));
    await pull.up();
    await tester.pumpAndSettle();
    expect(_bar(tester).height, FloatingGlassNavBar.height);
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

/// The lens at rest: as wide as a tab less a hair, as tall as the bar less its inset.
Size _restingLens(WidgetTester tester) {
  final bar = tester.getSize(find.byKey(const Key('nav-pill')));
  return Size((bar.width - 16) / 4 - 4, bar.height - 12);
}
