import 'package:flutter/material.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shared building blocks of the Student Interface design language
/// (canvas background, white rounded cards, pills, section titles, hero card),
/// so every role's screens look and feel the same.
class BasakUi {
  BasakUi._();

  static const ink = Color(0xFF17384A);
  static const teal = AppColors.teal;
  static const canvas = Color(0xFFEAF5FA);
  static const muted = Color(0xFF718695);
  static const softTeal = Color(0xFFE5F3FA);
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF247CA2), Color(0xFF075579)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration card({double radius = 20}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFEAF0F4)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A16384A), blurRadius: 14, offset: Offset(0, 5))
        ],
      );

  static String time12(String? value) {
    if (value == null) return '—';
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return value;
    final rawHour = int.tryParse(match.group(1)!) ?? 0;
    final hour = rawHour % 12 == 0 ? 12 : rawHour % 12;
    return '$hour:${match.group(2)} ${rawHour < 12 ? 'ص' : 'م'}';
  }

  static const arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const arabicWeekdays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  static String dateLabel(DateTime date) =>
      '${arabicWeekdays[date.weekday - 1]}، ${date.day} ${arabicMonths[date.month - 1]}';
}

/// Page shell used by the tab screens: canvas colour + scrollable padded column.
class BasakPage extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const BasakPage({super.key, required this.children, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: children,
    );
    return ColoredBox(
      color: BasakUi.canvas,
      child: onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: onRefresh!, color: BasakUi.teal, child: list),
    );
  }
}

class BasakPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const BasakPageHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.displayMedium
                        .copyWith(color: BasakUi.ink, fontSize: 23)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class BasakSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const BasakSectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink))),
          if (trailing != null) trailing!,
        ]),
      );
}

class BasakPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const BasakPill(this.label,
      {super.key,
      this.background = BasakUi.softTeal,
      this.foreground = BasakUi.teal,
      this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: foreground, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Compact metric card: icon bubble, big number, caption.
class BasakStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const BasakStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = BasakUi.teal,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BasakUi.card(radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: color.withOpacity(.12), shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
                  style: AppTextStyles.displayMedium
                      .copyWith(color: BasakUi.ink, fontSize: 24)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
          ],
        ),
      );
}

/// Two-column responsive grid of stat tiles.
class BasakStatGrid extends StatelessWidget {
  final List<Widget> tiles;

  const BasakStatGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth > 520 ? 4 : 2;
        final width = (c.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
        );
      });
}

class BasakInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const BasakInfoRow(
      {super.key, required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: BasakUi.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted)),
            ),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: AppTextStyles.bodyLarge.copyWith(
                      color: valueColor ?? BasakUi.ink, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

class BasakMessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const BasakMessageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BasakUi.card(),
        child: Column(children: [
          Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
              child: Icon(icon, color: BasakUi.teal)),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
          const SizedBox(height: 5),
          Text(message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
                onPressed: onAction,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(actionLabel!)),
          ],
        ]),
      );
}
