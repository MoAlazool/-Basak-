import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'status_chip.dart';
import 'tokens.dart';

enum ConnectionStripState { offline, syncing, backOnline }

/// One strip under the header for the state of the connection. Offline is
/// amber and carries the time of the saved data; syncing is teal; "back
/// online" is green and is taken away after [BasakMotion.backOnline].
class ConnectionStrip extends StatelessWidget {
  final ConnectionStripState state;

  /// Offline only: when the data on screen was saved, already formatted
  /// ("8:15 ص").
  final String? dataTime;

  /// Offline only.
  final VoidCallback? onRetry;

  /// Offline only: one more fact after the time ("المسح لا يسجّل الصعود الآن").
  final String? note;

  const ConnectionStrip({super.key, required this.state, this.dataTime, this.onRetry, this.note});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (BasakTone tone, IconData icon, String message) = switch (state) {
      ConnectionStripState.offline => (
          BasakTone.warning,
          LucideIcons.wifiOff,
          ['بدون إنترنت', if (dataTime != null) 'بيانات $dataTime', if (note != null) note!].join(' · '),
        ),
      ConnectionStripState.syncing => (BasakTone.info, LucideIcons.refreshCw, 'جارٍ التحديث…'),
      ConnectionStripState.backOnline => (
          BasakTone.success,
          LucideIcons.check,
          'عاد الاتصال · البيانات محدّثة'
        ),
    };
    final foreground = tone.foreground(colors);
    final retry = state == ConnectionStripState.offline ? onRetry : null;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsetsDirectional.only(start: BasakSpace.s14, end: retry == null ? BasakSpace.s14 : BasakSpace.s2),
        decoration: BoxDecoration(color: tone.tint(colors), borderRadius: BasakRadius.all(BasakRadius.small)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: BasakSpace.s10),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
                child: Text(
                  message,
                  style: context.text.label.copyWith(color: foreground, fontWeight: FontWeight.w400),
                ),
              ),
            ),
            if (retry != null)
              BasakPressable(
                onTap: retry,
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12),
                    child: Text(
                      'إعادة المحاولة',
                      style: context.text.label.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum BasakToastKind { success, failure, info }

/// The app's one kind of passing message: ink, with an icon that carries
/// success or failure. One at a time, three seconds.
abstract final class BasakToast {
  static void show(BuildContext context, String message, {BasakToastKind kind = BasakToastKind.success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: BasakMotion.toast,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, 0, BasakSpace.gutter, BasakSpace.s16),
        content: BasakToastBody(message: message, kind: kind),
      ));
  }
}

/// What a toast looks like, apart from how it is shown.
class BasakToastBody extends StatelessWidget {
  final String message;
  final BasakToastKind kind;

  const BasakToastBody({super.key, required this.message, this.kind = BasakToastKind.success});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (IconData icon, Color tint) = switch (kind) {
      BasakToastKind.success => (LucideIcons.check, colors.mint),
      BasakToastKind.failure => (LucideIcons.triangleAlert, colors.refusedFrame),
      BasakToastKind.info => (LucideIcons.info, colors.sky),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s12),
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BasakRadius.all(BasakRadius.small),
        boxShadow: BasakShadow.floating,
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: BasakSpace.s10),
          Expanded(child: Text(message, style: context.text.bodySmall.copyWith(color: colors.onInk))),
        ],
      ),
    );
  }
}

/// Nothing here yet: one neutral glyph, one line of title, one of help, and
/// at most one action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  /// A whole page on the ink ground (the card tab with no card to show):
  /// larger, light on dark, and its action is the page's primary button.
  final bool onInk;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.onInk = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    if (onInk) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: colors.inkRaised, borderRadius: BasakRadius.all(22)),
                child: Icon(icon, size: 28, color: colors.sky),
              ),
            ),
            const SizedBox(height: BasakSpace.s16),
            Text(title, textAlign: TextAlign.center, style: text.sheetTitle.copyWith(color: colors.onInk)),
            if (message != null) ...[
              const SizedBox(height: BasakSpace.s10),
              Text(message!, textAlign: TextAlign.center, style: text.body.copyWith(color: colors.onInk2)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: BasakSpace.s20),
              BasakButton(
                label: actionLabel!,
                onPressed: onAction,
                icon: actionIcon,
                size: BasakButtonSize.medium,
                expand: false,
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(18)),
            child: Icon(icon, size: 24, color: colors.ink2),
          ),
          const SizedBox(height: BasakSpace.s12),
          Text(title, textAlign: TextAlign.center, style: text.headline),
          if (message != null) ...[
            const SizedBox(height: BasakSpace.s6),
            Text(message!, textAlign: TextAlign.center, style: text.bodySmall.copyWith(color: colors.ink2)),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: BasakSpace.s16),
            BasakButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: BasakButtonVariant.tonal,
              size: BasakButtonSize.small,
              expand: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// A transport alert shown on Home only while it is live.
class LiveAlertBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String time;
  final VoidCallback? onTap;

  const LiveAlertBanner({
    super.key,
    this.icon = LucideIcons.bus,
    required this.title,
    required this.time,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final card = BasakCard(
      radius: BasakRadius.control,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: colors.successTint, borderRadius: BasakRadius.all(BasakRadius.tile)),
            child: Icon(icon, size: 18, color: colors.success),
          ),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: text.bodySmall.copyWith(fontWeight: FontWeight.w500)),
                Text(time, style: text.caption.copyWith(color: colors.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null ? card : BasakPressable(onTap: onTap, child: card);
  }
}
