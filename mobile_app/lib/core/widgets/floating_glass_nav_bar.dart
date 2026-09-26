import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

class FloatingGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<NavItem> items;

  const FloatingGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.items,
  });

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
          icon: LucideIcons.calendar,
          activeIcon: LucideIcons.calendar,
          label: 'الجدول',
        ),
        NavItem(
          icon: LucideIcons.messageSquare,
          activeIcon: LucideIcons.messageSquare,
          label: 'المحادثة',
        ),
        NavItem(
          icon: LucideIcons.user,
          activeIcon: LucideIcons.user,
          label: 'حسابي',
        ),
      ];

  /// Default supervisor navigation tabs configuration
  static List<NavItem> get supervisorNavItems => const [
        NavItem(
          icon: LucideIcons.layoutDashboard,
          activeIcon: LucideIcons.layoutDashboard,
          label: 'الرئيسية',
        ),
        NavItem(
          icon: LucideIcons.fileCheck,
          activeIcon: LucideIcons.fileCheck,
          label: 'الإيصالات',
        ),
        NavItem(
          icon: LucideIcons.qrCode,
          activeIcon: LucideIcons.qrCode,
          label: 'مسح QR',
        ),
        NavItem(
          icon: LucideIcons.messageSquare,
          activeIcon: LucideIcons.messageSquare,
          label: 'المحادثة',
        ),
        NavItem(
          icon: LucideIcons.users,
          activeIcon: LucideIcons.users,
          label: 'الركاب',
        ),
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
      child: GlassContainer(
        height: 64,
        blur: 18.0,
        opacity: 0.82,
        borderRadius: 32.0, // Floating pill shape
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shadows: AppColors.floatingBarShadow,
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
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 4)
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
                            color: isSelected ? AppColors.babyBlue : AppColors.textSecondary,
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
      ),
    );
  }
}
