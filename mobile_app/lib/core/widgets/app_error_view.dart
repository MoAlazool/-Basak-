import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Beautiful, reusable error / empty state widget
/// Used to replace all plain `Text('error')` states across the app.
class AppErrorView extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String actionLabel;
  final VoidCallback? onRetry;
  final Widget? extraAction;

  const AppErrorView({
    super.key,
    required this.title,
    required this.message,
    this.icon = LucideIcons.triangleAlert,
    this.iconColor = AppColors.teal,
    this.iconBg = const Color(0xFFE4F2F9),
    this.actionLabel = 'إعادة المحاولة',
    this.onRetry,
    this.extraAction,
  });

  /// Preset: network / loading failure
  factory AppErrorView.network({VoidCallback? onRetry, String? details}) =>
      AppErrorView(
        title: 'تعذر الاتصال',
        message: details == null || details.isEmpty
            ? 'تأكد من اتصال الإنترنت وحاول مرة أخرى.'
            : _friendly(details),
        icon: LucideIcons.wifiOff,
        iconColor: const Color(0xFFB42335),
        iconBg: const Color(0xFFFFECEE),
        onRetry: onRetry,
      );

  /// Preset: empty subscription
  factory AppErrorView.emptySubscription({required VoidCallback onBrowse}) =>
      AppErrorView(
        title: 'لم يتم العثور على اشتراك',
        message: 'لم نجد اشتراكاً مرتبطاً بحسابك الحالي.',
        icon: LucideIcons.ticket,
        iconColor: AppColors.teal,
        iconBg: const Color(0xFFE2F3FB),
        actionLabel: 'استعراض الاشتراكات',
        onRetry: onBrowse,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAF0F4)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A16384A), blurRadius: 18, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated icon bubble
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: iconColor.withOpacity(0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 34),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: const Color(0xFF6B8291), height: 1.6)),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
          if (extraAction != null) ...[
            const SizedBox(height: 8),
            extraAction!,
          ],
        ],
      ),
    );
  }

  static String _friendly(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('socket') || lower.contains('network') || lower.contains('failed host')) {
      return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجدداً.';
    }
    if (lower.contains('jwt') || lower.contains('auth')) {
      return 'انتهت الجلسة، سجّل دخولك مرة أخرى.';
    }
    // Trim very long Supabase error prefix
    final cleaned = raw.replaceAll('Exception:', '').trim();
    return cleaned.length > 140 ? '${cleaned.substring(0, 137)}...' : cleaned;
  }
}

/// Minimal shimmer-like loading card with animated pulse
class AppShimmerCard extends StatefulWidget {
  final double height;
  const AppShimmerCard({super.key, this.height = 180});
  @override
  State<AppShimmerCard> createState() => _AppShimmerCardState();
}

class _AppShimmerCardState extends State<AppShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(const Color(0xFFF1F5F9), const Color(0xFFE2EEF5), _c.value),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEAF0F4)),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.teal.withOpacity(0.7 + 0.3 * _c.value)),
            ),
            const SizedBox(height: 10),
            Text('جارٍ التحميل...', style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF8AA0B0))),
          ]),
        ),
      ),
    );
  }
}

/// Animated entrance wrapper for list items (staggered)
class StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;
  const StaggeredEntrance({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 340 + (index * 70).clamp(0, 300)),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - v)),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
