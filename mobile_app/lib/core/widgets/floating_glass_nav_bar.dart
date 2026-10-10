import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../ui/basak_button.dart';
import '../ui/tokens.dart';

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Whether the phone asks for less see-through surfaces. Flutter does not
/// pass on the iPhone's «تقليل الشفافية», so it is asked over `basak/accessibility`
/// (AppDelegate.swift); everywhere else it stays false and the phone's
/// high-contrast setting decides alone (see [FloatingGlassNavBar]).
abstract final class BasakGlass {
  static const _channel = MethodChannel('basak/accessibility');

  static final ValueNotifier<bool> reduceTransparency = ValueNotifier(false);

  /// Asked when a glass surface comes up and when the app returns to the front.
  static Future<void> refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      reduceTransparency.value = await _channel.invokeMethod<bool>('reduceTransparency') ?? false;
    } catch (_) {
      // An older build of the iOS side: the bar stays glass.
    }
  }
}

/// The floating tab bar of both shells: a pill of Basak's own glass, 16 from
/// the edges. What is behind it shows through, blurred and whitened enough
/// that the labels read on the ground and on the ink of the card alike.
///
/// The selected tab, icon and label, sits under an ink **lens** the size of
/// the tab. Choosing another tab sends the
/// lens there on a spring: it stretches while it travels, lands a little past
/// and settles, and the icon it passes over brightens and grows as it would
/// under a drop of glass. Dragging along the bar carries the lens with the
/// finger and chooses the tab it is let go on.
///
/// When [collapsed] (the page was scrolled down) the labels fold away and the
/// pill drops from 64 to 52; every tab stays one tap away.
///
/// The phone's settings are followed: with "reduce motion" the lens is simply
/// on the chosen tab, and with "reduce transparency" or "increase contrast"
/// the bar is the solid white pill it was.
class FloatingGlassNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<NavItem> items;
  final bool collapsed;

  /// Off: the solid bar, whatever the phone says (a page that must not pay
  /// for a blur).
  final bool glass;

  static const double height = 64;
  static const double collapsedHeight = 52;
  static const double sideMargin = 16;
  static const Duration animationDuration = BasakMotion.page;

  const FloatingGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.items,
    this.collapsed = false,
    this.glass = true,
  });

  /// Whether a scroll should collapse (true) or expand (false) the bar, or
  /// leave it as it is (null). Only vertical user scrolls count: scrolling
  /// down collapses, scrolling up or coming to rest at the top expands.
  static bool? collapseOnScroll(ScrollNotification notification) {
    if (notification is! UserScrollNotification) return null;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return null;
    switch (notification.direction) {
      // Sent before the drag moves the content, so a scroll down that starts
      // at the top still reports the top position: no position check here.
      case ScrollDirection.reverse:
        // On a page too short to scroll as well: the pull itself folds the
        // labels, and they are back when it comes to rest at the top.
        return true;
      case ScrollDirection.forward:
        return false;
      case ScrollDirection.idle:
        return metrics.pixels <= metrics.minScrollExtent ? false : null;
    }
  }

  /// Default student navigation tabs configuration
  static List<NavItem> get studentNavItems => const [
        NavItem(
          icon: LucideIcons.home,
          activeIcon: LucideIcons.home,
          label: 'الرئيسية',
        ),
        NavItem(
          icon: LucideIcons.ticket,
          activeIcon: LucideIcons.ticket,
          label: 'اشتراكي',
        ),
        NavItem(
          icon: LucideIcons.qrCode,
          activeIcon: LucideIcons.qrCode,
          label: 'بطاقتي',
        ),
        NavItem(
          icon: LucideIcons.user,
          activeIcon: LucideIcons.user,
          label: 'حسابي',
        ),
      ];

  /// Supervisor navigation tabs configuration
  static List<NavItem> get supervisorNavItems => const [
        NavItem(icon: LucideIcons.home, activeIcon: LucideIcons.home, label: 'الرئيسية'),
        NavItem(icon: LucideIcons.route, activeIcon: LucideIcons.route, label: 'الرحلات'),
        NavItem(icon: LucideIcons.scanLine, activeIcon: LucideIcons.scanLine, label: 'مسح'),
        NavItem(icon: LucideIcons.user, activeIcon: LucideIcons.user, label: 'حسابي'),
      ];

  @override
  State<FloatingGlassNavBar> createState() => _FloatingGlassNavBarState();
}

class _FloatingGlassNavBarState extends State<FloatingGlassNavBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Where the lens is, in tabs: 0 is the first tab, 1.5 is midway between
  /// the second and the third.
  late final AnimationController _lens =
      AnimationController.unbounded(vsync: this, value: widget.currentIndex.toDouble());

  /// A drag along the bar is carrying the lens.
  bool _scrubbing = false;
  int _scrubTab = 0;

  /// The lens covers the whole tab, icon and label, as one capsule: this far
  /// in from the bar's top and bottom, and this far from its neighbours.
  static const double _lensInset = 6;
  static const double _lensGap = 2;
  static const double _iconBox = 28;

  /// How far the lens stretches at full speed, and what it gives up in height.
  static const double _stretch = 18;
  static const double _squeeze = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BasakGlass.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The setting may have been changed while the app was behind.
    if (state == AppLifecycleState.resumed) BasakGlass.refresh();
  }

  @override
  void didUpdateWidget(FloatingGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex && !_scrubbing) _travel(widget.currentIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lens.dispose();
    super.dispose();
  }

  /// Sends the lens to [tab]: on its spring, or at once where the phone asks
  /// for less motion.
  void _travel(int tab) {
    final to = tab.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _lens
        ..stop()
        ..value = to;
      return;
    }
    _lens.animateWith(SpringSimulation(BasakMotion.lensSpring, _lens.value, to, _lens.velocity)).whenComplete(() {
      // The spring stops within a hair of the tab; the lens rests exactly on it.
      if (mounted && !_scrubbing && !_lens.isAnimating) _lens.value = to;
    });
  }

  /// The tab under a finger at [dx] from the bar's left edge, as a position
  /// of the lens.
  double _tabAt(double dx, double width) {
    final slot = width / widget.items.length;
    final fromStart = Directionality.of(context) == TextDirection.rtl ? width - dx : dx;
    return (fromStart / slot - .5).clamp(0.0, widget.items.length - 1.0);
  }

  void _scrub(double dx, double width) {
    final at = _tabAt(dx, width);
    _lens
      ..stop()
      ..value = at;
    // A click each time the lens comes over another tab.
    if (at.round() != _scrubTab) {
      _scrubTab = at.round();
      HapticFeedback.selectionClick();
    }
  }

  void _endScrub() {
    if (!_scrubbing) return;
    _scrubbing = false;
    final tab = _lens.value.round().clamp(0, widget.items.length - 1);
    _travel(tab);
    if (tab == widget.currentIndex) return;
    widget.onTabSelected(tab);
    // A shell that did not take the tab gets its lens back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scrubbing && widget.currentIndex != tab) _travel(widget.currentIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final highContrast = MediaQuery.highContrastOf(context);

    // Its own layer: the lens and the icons repaint without the page under
    // them, and the page scrolls without repainting the bar's content.
    return RepaintBoundary(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: basakMaxTextScale,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: FloatingGlassNavBar.sideMargin,
            end: FloatingGlassNavBar.sideMargin,
            bottom: bottomPadding > 0 ? bottomPadding + 8 : 10,
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: BasakGlass.reduceTransparency,
            builder: (context, reduceTransparency, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: widget.collapsed ? 1.0 : 0.0),
              duration: FloatingGlassNavBar.animationDuration,
              curve: BasakMotion.pageCurve,
              builder: (context, t, _) => _GlassPill(
                height: lerpDouble(FloatingGlassNavBar.height, FloatingGlassNavBar.collapsedHeight, t)!,
                glass: widget.glass && !highContrast && !reduceTransparency,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s8),
                  child: LayoutBuilder(builder: (context, box) => _content(context, box, t)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, BoxConstraints box, double t) {
    final items = widget.items;
    final slot = box.maxWidth / items.length;
    // The lens is as tall as the bar allows and as wide as its tab, so the
    // selected tab is wholly under it at either height of the bar.
    final lensWidth = slot - _lensGap * 2;
    final lensHeight = box.maxHeight - _lensInset * 2;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _scrubbing = true;
        _scrubTab = _lens.value.round();
        _scrub(details.localPosition.dx, box.maxWidth);
      },
      onHorizontalDragUpdate: (details) => _scrub(details.localPosition.dx, box.maxWidth),
      onHorizontalDragEnd: (_) => _endScrub(),
      onHorizontalDragCancel: _endScrub,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _lens,
            builder: (context, child) {
              // Longer and flatter the faster it goes; itself again at rest.
              final speed = _lens.isAnimating ? (_lens.velocity.abs() / 9).clamp(0.0, 1.0) : 0.0;
              final width = lensWidth + _stretch * speed;
              final height = lensHeight - _squeeze * speed;
              return PositionedDirectional(
                start: slot * _lens.value + (slot - width) / 2,
                top: _lensInset + (lensHeight - height) / 2,
                width: width,
                height: height,
                child: child!,
              );
            },
            child: const _Lens(key: Key('nav-indicator')),
          ),
          Row(
            children: [
              for (var index = 0; index < items.length; index++) Expanded(child: _tab(context, index, t)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index, double t) {
    final colors = context.colors;
    final item = widget.items[index];
    final isSelected = index == widget.currentIndex;

    return BasakPressable(
      onTap: () => widget.onTabSelected(index),
      semanticLabel: item.label,
      selected: isSelected,
      selectionHaptic: true,
      child: AnimatedBuilder(
        animation: _lens,
        builder: (context, _) {
          // How much of the lens is over this tab: 1 under it, 0 a tab away.
          final under = (1 - (_lens.value - index).abs()).clamp(0.0, 1.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Under the lens the icon turns white and grows, as through glass.
              SizedBox(
                height: _iconBox,
                child: Transform.scale(
                  scale: lerpDouble(.92, 1, under),
                  child: Icon(
                    under > .5 ? item.activeIcon : item.icon,
                    size: 22,
                    // Ink, not grey: the glass is clear and what is behind it varies.
                    color: Color.lerp(colors.ink, colors.onInk, under),
                  ),
                ),
              ),
              // The label folds away as the bar collapses; the icon stays.
              if (t < 1)
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1 - t,
                    child: Opacity(
                      opacity: (1 - t * 2).clamp(0.0, 1.0),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
                        child: ExcludeSemantics(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.tab.copyWith(
                              // White on the lens, like its icon.
                              color: Color.lerp(colors.ink, colors.onInk, under),
                              fontWeight: under > .5 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The bar's body: glass (what is behind it, blurred, under a white veil with
/// a lit upper edge) or, when [glass] is off, the solid white pill.
class _GlassPill extends StatelessWidget {
  final double height;
  final bool glass;
  final Widget child;

  const _GlassPill({required this.height, required this.glass, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BasakRadius.all(BasakRadius.full);
    return Container(
      key: const Key('nav-pill'),
      height: height,
      decoration: BoxDecoration(borderRadius: radius, boxShadow: BasakShadow.floating),
      child: !glass
          ? DecoratedBox(
              key: const Key('nav-solid'),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: radius,
                border: Border.all(color: colors.hairline),
              ),
              child: child,
            )
          : ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                key: const Key('nav-glass'),
                filter: ImageFilter.blur(sigmaX: BasakGlassStyle.blur, sigmaY: BasakGlassStyle.blur),
                child: CustomPaint(
                  foregroundPainter: const _GlassEdge(),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [BasakGlassStyle.veilTop, BasakGlassStyle.veilBottom],
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
    );
  }
}

/// The glass's edge: one hairline, lit from above and fading to a faint ink
/// line underneath, so the pill has a rim on a white page and on a dark one.
class _GlassEdge extends CustomPainter {
  const _GlassEdge();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [BasakGlassStyle.edgeLit, BasakGlassStyle.edgeMid, BasakGlassStyle.edgeShade],
        stops: [0, .5, 1],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)), paint);
  }

  @override
  bool shouldRepaint(_GlassEdge old) => false;
}

/// The lens over the selected tab: Basak's ink as a drop of glass, lit along
/// its upper half, with a soft shadow of its own.
class _Lens extends StatelessWidget {
  const _Lens({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(BasakRadius.full)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BasakGlassStyle.lensTop, BasakGlassStyle.lensBottom],
          ),
          boxShadow: BasakGlassStyle.lensShadow,
        ),
        child: CustomPaint(painter: _LensLight()),
      );
}

/// The light on the lens: a sheen over its upper half and a bright upper rim.
class _LensLight extends CustomPainter {
  const _LensLight();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(shape);
    final sheen = Rect.fromLTWH(size.width * .08, -size.height * .5, size.width * .84, size.height);
    canvas.drawOval(
      sheen,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BasakGlassStyle.lensSheen, BasakGlassStyle.lensSheenEnd],
        ).createShader(sheen),
    );
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BasakGlassStyle.lensRim, BasakGlassStyle.lensRimEnd],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LensLight old) => false;
}
