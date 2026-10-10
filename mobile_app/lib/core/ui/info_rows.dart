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

  /// The row could not be read: [label] says so ("تعذّر تحميل الإيصال"), with
  /// a warning glyph before it and "إعادة المحاولة" at its end.
  final VoidCallback? onRetry;

  /// On the label's and the value's own text.
  final Key? labelKey;
  final Key? valueKey;

  const InfoRow({
    required this.label,
    this.value,
    this.caption,
    this.onTap,
    this.ltrValue = false,
    this.key,
    this.onRetry,
    this.labelKey,
    this.valueKey,
  });
}

/// Label at the start, value at the end, one card, no icon per row. A chevron
/// appears only on a row that navigates.
class InfoRows extends StatelessWidget {
  final List<InfoRow> rows;

  /// Inside a sheet, where the surface is already white: a ground-coloured
  /// block without a shadow, and rows 44 high.
  final bool sunken;

  /// Under the last row, after a hairline: "عرض كل الاشتراكات السابقة · 5".
  final Widget? footer;

  const InfoRows({super.key, required this.rows, this.sunken = false, this.footer});

  @override
  Widget build(BuildContext context) => BasakCard(
        padding: EdgeInsetsDirectional.symmetric(horizontal: sunken ? BasakSpace.s16 : BasakSpace.s18),
        radius: sunken ? BasakRadius.control : BasakRadius.card,
        color: sunken ? context.colors.ground : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              _row(context, rows[i]),
            ],
            if (footer != null) ...[
              if (rows.isNotEmpty) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              footer!,
            ],
          ],
        ),
      );

  Widget _row(BuildContext context, InfoRow row) {
    final colors = context.colors;
    final text = context.text;
    final navigates = row.onTap != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    if (row.onRetry != null) {
      return KeyedSubtree(
        key: row.key,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Icon(LucideIcons.triangleAlert, size: 18, color: colors.danger),
              const SizedBox(width: BasakSpace.s10),
              Expanded(child: Text(row.label, style: text.bodySmall)),
              BasakButton(
                label: 'إعادة المحاولة',
                onPressed: row.onRetry,
                variant: BasakButtonVariant.quiet,
                size: BasakButtonSize.small,
                expand: false,
              ),
            ],
          ),
        ),
      );
    }

    Widget? value;
    if (row.value != null) {
      value = Text(
        row.value!,
        key: row.valueKey,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        // A left-to-right value still sits at the row's end edge.
        textAlign: row.ltrValue && rtl ? TextAlign.start : TextAlign.end,
        textDirection: row.ltrValue ? TextDirection.ltr : null,
        style:
            navigates ? text.bodySmall.copyWith(color: colors.ink3) : text.body.copyWith(fontWeight: FontWeight.w500),
      );
    }

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: sunken ? 44 : (row.caption == null ? 56 : 64)),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: sunken ? BasakSpace.s6 : BasakSpace.s8),
        child: Row(
          children: [
            // The label keeps its words; a long value wraps beside it. With
            // no value the label has the row to itself.
            Flexible(
              flex: value == null ? 1 : 0,
              fit: value == null ? FlexFit.tight : FlexFit.loose,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: value == null ? double.infinity : MediaQuery.sizeOf(context).width * .45),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      key: row.labelKey,
                      style: navigates
                          ? text.body.copyWith(fontWeight: FontWeight.w500)
                          : text.bodySmall.copyWith(color: colors.ink2),
                    ),
                    if (row.caption != null) Text(row.caption!, style: text.caption.copyWith(color: colors.ink3)),
                  ],
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: BasakSpace.s12),
              Expanded(child: value),
            ],
            if (navigates) ...[
              const SizedBox(width: BasakSpace.s6),
              Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
            ],
          ],
        ),
      ),
    );

    return navigates
        ? BasakPressable(key: row.key, onTap: row.onTap, child: content)
        : KeyedSubtree(key: row.key, child: content);
  }
}
