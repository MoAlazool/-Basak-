import 'package:flutter/material.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../storage/offline_cache.dart';
import '../theme/app_text_styles.dart';

/// Thin strip above [child] while the screens show saved data because the
/// server cannot be reached. Pull to refresh on any screen once back online.
class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: OfflineCache.offlineSince,
      builder: (context, since, _) {
        if (since == null) return child;
        return Column(
          children: [
            ColoredBox(
              color: const Color(0xFFFFF4DB),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.wifiOff, size: 16, color: Color(0xFF8A5A00)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'أنت غير متصل بالإنترنت · تعرض آخر بيانات محفوظة (${savedAtLabel(since)})',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: const Color(0xFF8A5A00), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  /// "اليوم 08:15" or "2026/10/03 21:40".
  static String savedAtLabel(DateTime at, [DateTime? now]) {
    final local = at.toLocal();
    final today = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    final sameDay = local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    return sameDay
        ? 'اليوم $time'
        : '${local.year}/${two(local.month)}/${two(local.day)} $time';
  }
}
