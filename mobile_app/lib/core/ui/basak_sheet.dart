import 'package:flutter/material.dart';

import 'tokens.dart';

/// Every choice, detail and confirmation is a bottom sheet: a grabber, a
/// one-line title, the content, at most one primary action. Swiping down or
/// the system back button closes it before anything behind it.
abstract final class BasakSheet {
  /// Opens a sheet. [builder] gives the content; [primary] is pinned under it
  /// (a `BasakButton`), and the content scrolls once the sheet reaches 88% of
  /// the screen.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    String? subtitle,
    WidgetBuilder? primary,
    bool isDismissible = true,
    bool largeTitle = false,
  }) =>
      showFrame<T>(
        context,
        isDismissible: isDismissible,
        builder: (context) => BasakSheetFrame(
          title: title,
          subtitle: subtitle,
          largeTitle: largeTitle,
          primary: primary?.call(context),
          child: builder(context),
        ),
      );

  /// Opens a sheet whose [builder] gives the whole [BasakSheetFrame]: for a
  /// sheet that keeps state across its header, its list and its button (a
  /// searchable picker).
  static Future<T?> showFrame<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: isDismissible,
        enableDrag: isDismissible,
        backgroundColor: Colors.transparent,
        elevation: 0,
        barrierColor: context.colors.scrim,
        sheetAnimationStyle: const AnimationStyle(
          duration: BasakMotion.sheetIn,
          curve: BasakMotion.sheetInCurve,
          reverseDuration: BasakMotion.sheetOut,
          reverseCurve: BasakMotion.sheetOutCurve,
        ),
        builder: builder,
      );
}

/// What a sheet looks like, apart from how it is opened.
class BasakSheetFrame extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final Widget? primary;

  /// The sheet asks a question of its own ("رحلة الغد", "الانضمام إلى …؟"):
  /// its title is set 22 / 32 and the line under it 14 / 22.
  final bool largeTitle;

  /// Stays put between the title and the scrolling content: a search box.
  final Widget? header;

  const BasakSheetFrame(
      {super.key,
      this.title,
      this.subtitle,
      required this.child,
      this.primary,
      this.largeTitle = false,
      this.header});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final media = MediaQuery.of(context);
    final safe = media.padding.bottom;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        // The sheet rides above the keyboard.
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: BasakSpace.maxContentWidth, maxHeight: media.size.height * .88),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadiusDirectional.vertical(top: Radius.circular(BasakRadius.sheet)),
                boxShadow: BasakShadow.floating,
              ),
              padding: EdgeInsetsDirectional.fromSTEB(
                  BasakSpace.gutter, BasakSpace.s10, BasakSpace.gutter, safe > 0 ? safe + BasakSpace.s8 : BasakSpace.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: colors.grabber, borderRadius: BasakRadius.all(2)),
                    ),
                  ),
                  const SizedBox(height: BasakSpace.s14),
                  if (title != null) ...[
                    Semantics(
                      header: true,
                      child: Text(title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: largeTitle ? text.title : text.sheetTitle),
                    ),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: largeTitle
                              ? text.bodySmall.copyWith(color: colors.ink2)
                              : text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                    const SizedBox(height: BasakSpace.s14),
                  ],
                  if (header != null) ...[
                    header!,
                    const SizedBox(height: BasakSpace.s14),
                  ],
                  Flexible(child: SingleChildScrollView(child: child)),
                  if (primary != null) ...[
                    const SizedBox(height: BasakSpace.s14),
                    primary!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
