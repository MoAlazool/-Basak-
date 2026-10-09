import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'tokens.dart';

/// One line of an [InfoRows] card.
class InfoRow {
  /// The start side. A row that navigates is named by this alone.
  final String label;

  /// The end side.
  final String? value;

  /// A second line under [label]: a past subscription's "انتهى 28 مايو 2026".
  final String? caption;

  /// With a tap the row shows a chevron and its label reads as the value does.
  final VoidCallback? onTap;

  /// Codes, phone numbers and times read left to right.
  final bool ltrValue;

  final Key? key;

  const InfoRow({required this.label, this.value, this.caption, this.onTap, this.ltrValue = false, this.key});
}

/// Label at the start, value at the end, one card, no icon per row. A chevron
/// appears only on a row that navigates.
class InfoRows extends StatelessWidget {
  final List<InfoRow> rows;

  const InfoRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              _row(context, rows[i]),
            ],
          ],
        ),
      );

  Widget _row(BuildContext context, InfoRow row) {
    final colors = context.colors;
    final text = context.text;
    final navigates = row.onTap != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    Widget? value;
    if (row.value != null) {
      value = Text(
        row.value!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        textDirection: row.ltrValue ? TextDirection.ltr : null,
        style: navigates
            ? text.bodySmall.copyWith(color: colors.ink3)
            : text.body.copyWith(fontWeight: FontWeight.w500),
      );
    }

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: row.caption == null ? 56 : 64),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s8),
        child: Row(
          children: [
            // The label keeps its words; a long value wraps beside it.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (value == null ? .8 : .45)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label,
                    style: navigates
                        ? text.body.copyWith(fontWeight: FontWeight.w500)
                        : text.bodySmall.copyWith(color: colors.ink2),
                  ),
                  if (row.caption != null) Text(row.caption!, style: text.caption.copyWith(color: colors.ink3)),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(child: value ?? const SizedBox.shrink()),
            if (navigates) ...[
              const SizedBox(width: BasakSpace.s6),
              Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
            ],
          ],
        ),
      ),
    );

    return navigates ? BasakPressable(key: row.key, onTap: row.onTap, child: content) : KeyedSubtree(key: row.key, child: content);
  }
}
