import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'glass_container.dart';

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

/// Floating glass tab bar. Like iOS 26 it can collapse into a glass circle at
/// the start side holding only the selected tab's icon; tapping it calls
/// [onExpand].
class FloatingGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<NavItem> items;
  final bool collapsed;
  final VoidCallback? onExpand;

  static const double height = 64;
  static const Duration animationDuration = Duration(milliseconds: 350);

  const FloatingGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.items,
    this.collapsed = false,
    this.onExpand,
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
          icon: LucideIcons.creditCard,
          activeIcon: LucideIcons.creditCard,
          label: 'الاشتراك',
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

  /// Default supervisor navigation tabs configuration
  /// Supervisor navigation tabs configuration
  /// Supervisor navigation tabs configuration
  static List<NavItem> get supervisorNavItems => const [
        NavItem(icon: LucideIcons.home, activeIcon: LucideIcons.home, label: 'الرئيسية'),
        NavItem(icon: LucideIcons.route, activeIcon: LucideIcons.route, label: 'الرحلات'),
        NavItem(icon: LucideIcons.scanLine, activeIcon: LucideIcons.scanLine, label: 'مسح QR'),
        NavItem(icon: LucideIcons.chartColumn, activeIcon: LucideIcons.chartColumn, label: 'الملخص'),
        NavItem(icon: LucideIcons.user, activeIcon: LucideIcons.user, label: 'حسابي'),
      ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomPadding > 0 ? bottomPadding + 8 : 20,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => TweenAnimationBuilder<double>(
          tween: Tween(end: collapsed ? 1.0 : 0.0),
          duration: animationDuration,
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) {
            final fullWidth = constraints.maxWidth;
            final width = lerpDouble(fullWidth, height, t)!;
            return Align(
              alignment: AlignmentDirectional.centerStart,
              heightFactor: 1,
              child: GlassContainer(
                width: width,
                height: height,
                blur: 18.0,
                opacity: 0.82,
                borderRadius: height / 2, // Floating pill, a circle when collapsed
                padding: EdgeInsets.zero,
                shadows: AppColors.floatingBarShadow,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The tabs keep their full width and are clipped while the
                    // bar shrinks, so nothing squeezes or overflows mid-animation.
                    if (t < 1)
                      IgnorePointer(
                        ignoring: collapsed,
                        child: Opacity(
                          opacity: (1 - t * 2).clamp(0.0, 1.0),
                          child: LayoutBuilder(
                            builder: (context, inner) => OverflowBox(
                              alignment: AlignmentDirectional.centerStart,
                              minWidth: inner.maxWidth + fullWidth - width,
                              maxWidth: inner.maxWidth + fullWidth - width,
                              child: _buildTabs(),
                            ),
                          ),
                        ),
                      ),
                    if (t > 0)
                      IgnorePointer(
                        ignoring: !collapsed,
                        child: Opacity(
                          opacity: ((t - 0.5) * 2).clamp(0.0, 1.0),
                          child: _buildCollapsedTab(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCollapsedTab() {
    final item = items[currentIndex];
    return Semantics(
      button: true,
      label: item.label,
      child: GestureDetector(
        onTap: onExpand,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.babyBlueUltraLight.withOpacity(0.9),
              shape: BoxShape.circle,
            ),
            child: Icon(item.activeIcon, size: 24, color: AppColors.babyBlue),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isSelected = index == currentIndex;
          final item = items[index];

          return Expanded(
            child: GestureDetector(
              onTap: () => onTabSelected(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated Icon with Scale & Color transition
                    AnimatedScale(
                      scale: isSelected ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: isSelected
                            ? const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4)
                            : const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.babyBlueUltraLight.withOpacity(0.9)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isSelected ? item.activeIcon : item.icon,
                          size: 22,
                          color: isSelected
                              ? AppColors.babyBlue
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Text Label
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      style: isSelected
                          ? AppTextStyles.labelSmall.copyWith(
                              color: AppColors.babyBlueDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                            )
                          : AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textSecondary.withOpacity(0.7),
                              fontSize: 9.5,
                            ),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
