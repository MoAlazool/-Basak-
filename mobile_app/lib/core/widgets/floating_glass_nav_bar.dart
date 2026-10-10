import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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

/// The floating tab bar of both shells: a solid white pill, 16 from the edges.
/// An ink pill sits behind the selected tab's icon and slides to whichever tab
/// is chosen. When [collapsed] (the page was scrolled down) the labels fold away and the
/// pill drops from 64 to 52; every tab stays one tap away.
class FloatingGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<NavItem> items;
  final bool collapsed;

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
        // Content shorter than the screen has nothing to make room for.
        return metrics.maxScrollExtent > metrics.minScrollExtent ? true : null;
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: sideMargin,
          end: sideMargin,
          bottom: bottomPadding > 0 ? bottomPadding + 8 : 10,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: collapsed ? 1.0 : 0.0),
          duration: animationDuration,
          curve: BasakMotion.pageCurve,
          builder: (context, t, _) => Container(
            key: const Key('nav-pill'),
            height: lerpDouble(height, collapsedHeight, t),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BasakRadius.all(BasakRadius.full),
              border: Border.all(color: colors.hairline),
              boxShadow: BasakShadow.floating,
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final slot = box.maxWidth / items.length;
                // The icons sit at the top of a column that is centred in the
                // bar; the label under them is what folds away.
                final label = (1 - t) * (BasakSpace.s4 + MediaQuery.textScalerOf(context).scale(_labelLine));
                final top = (box.maxHeight - _iconBox - label) / 2;
                return Stack(
                  children: [
                    AnimatedPositionedDirectional(
                      duration: animationDuration,
                      curve: BasakMotion.pageCurve,
                      start: slot * currentIndex + (slot - _indicatorWidth) / 2,
                      top: top,
                      width: _indicatorWidth,
                      height: _iconBox,
                      child: DecoratedBox(
                        key: const Key('nav-indicator'),
                        decoration:
                            BoxDecoration(color: colors.ink, borderRadius: BasakRadius.all(BasakRadius.tile)),
                      ),
                    ),
                    Row(
                      children: [
                        for (var index = 0; index < items.length; index++) Expanded(child: _tab(context, index, t)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static const double _indicatorWidth = 52;
  static const double _iconBox = 32;
  static const double _labelLine = 16;

  Widget _tab(BuildContext context, int index, double t) {
    final colors = context.colors;
    final item = items[index];
    final isSelected = index == currentIndex;

    // White on the ink pill once it arrives; the tab it leaves fades back.
    final icon = SizedBox(
      height: _iconBox,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: isSelected ? colors.onInk : colors.ink3),
        duration: animationDuration,
        curve: BasakMotion.pageCurve,
        builder: (context, color, _) =>
            Icon(isSelected ? item.activeIcon : item.icon, size: isSelected ? 20 : 22, color: color),
      ),
    );

    return BasakPressable(
      onTap: () => onTabSelected(index),
      semanticLabel: item.label,
      selected: isSelected,
      selectionHaptic: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          // The label folds away as the bar collapses; the icon stays.
          if (t < 1)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1 - t,
                child: Opacity(
                  opacity: (1 - t * 2).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: BasakSpace.s4),
                    child: ExcludeSemantics(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.tab.copyWith(
                          color: isSelected ? colors.ink : colors.ink3,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
