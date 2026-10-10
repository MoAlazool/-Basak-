import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'tokens.dart';

/// A white card on the ground: radius 20, the card shadow, no border.
class BasakCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Another surface than white: the tint of a tonal card, or sunken for a
  /// locked one. A tinted card has no shadow.
  final Color? color;

  const BasakCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(BasakSpace.card),
    this.radius = BasakRadius.card,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? context.colors.surface,
          borderRadius: BasakRadius.all(radius),
          boxShadow: color == null ? BasakShadow.card : null,
        ),
        child: child,
      );
}

/// The frame of every screen: the ground, a 20 gutter, 16 between blocks, an
/// optional header that stays put and an optional dock pinned to the bottom.
/// Text scale is honoured up to 1.3; wide screens get one centred column.
class BasakPage extends StatelessWidget {
  final List<Widget> children;

  /// Stays above the scrolling content (a [BasakBackHeader], a page title).
  final Widget? header;

  /// Pinned under the content: a [BasakDock].
  final Widget? dock;

  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  /// Room left under the last block: [tabBarClearance] on a tab's page.
  final double bottomInset;

  /// Space between two blocks.
  final double spacing;

  /// What a page under the floating tab bar leaves free at its end.
  static const double tabBarClearance = 104;

  const BasakPage({
    super.key,
    required this.children,
    this.header,
    this.dock,
    this.onRefresh,
    this.controller,
    this.bottomInset = BasakSpace.s24,
    this.spacing = BasakSpace.betweenCards,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget list = ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsetsDirectional.fromSTEB(
          BasakSpace.gutter, header == null ? BasakSpace.s12 : BasakSpace.s4, BasakSpace.gutter, bottomInset),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
      separatorBuilder: (context, index) => SizedBox(height: spacing),
    );
    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, color: colors.teal, backgroundColor: colors.surface, child: list);
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: basakMaxTextScale,
      child: ColoredBox(
        color: colors.ground,
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (header != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, BasakSpace.s12),
                            child: header,
                          ),
                        Expanded(child: list),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (dock != null) dock!,
          ],
        ),
      ),
    );
  }
}

/// The bottom dock: a white shelf with the route's one primary button.
class BasakDock extends StatelessWidget {
  final Widget child;

  const BasakDock({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadiusDirectional.vertical(top: Radius.circular(BasakRadius.sheet)),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
          BasakSpace.gutter, BasakSpace.s16, BasakSpace.gutter, safe > 0 ? safe + BasakSpace.s8 : BasakSpace.s20),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth - 2 * BasakSpace.gutter),
          child: child,
        ),
      ),
    );
  }
}

/// The top of a pushed page: the round back button, and under it the page's
/// title when it has one. [trailing] sits at the far end of the button's row.
class BasakBackHeader extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  /// The title sits beside the back button, 20 / 30, instead of under it: a
  /// page whose content is its own headline ("الإيصال", "الدفع").
  final bool inlineTitle;

  const BasakBackHeader(
      {super.key, this.title, this.subtitle, this.trailing, this.onBack, this.inlineTitle = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            BasakIconButton(
              // Back points to where the page came from: the start side.
              icon: rtl ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            if (inlineTitle && title != null) ...[
              const SizedBox(width: BasakSpace.s12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.sheetTitle),
                ),
              ),
            ] else
              const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        if (title != null && !inlineTitle) ...[
          const SizedBox(height: BasakSpace.s12),
          Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.display),
        ],
        if (subtitle != null) ...[
          const SizedBox(height: BasakSpace.s4),
          Text(subtitle!, style: text.body.copyWith(color: colors.ink2)),
        ],
      ],
    );
  }
}

/// A section's heading, 17 / 26 · 600, with an optional quiet action.
class SectionHead extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHead(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: context.text.headline)),
          if (trailing != null) trailing!,
        ],
      );
}
