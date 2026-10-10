import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/tokens.dart';

/// The app's one theme, built from the tokens so that Material widgets a
/// screen has not restyled yet (buttons, fields, sheets, snack bars, dialogs)
/// already carry the redesign.
class AppTheme {
  static ThemeData get lightTheme {
    const colors = BasakColors.light;
    const text = BasakText.standard;

    final scheme = ColorScheme.fromSeed(
      seedColor: colors.teal,
      primary: colors.teal,
      onPrimary: colors.onTeal,
      primaryContainer: colors.tealTint,
      onPrimaryContainer: colors.teal,
      secondary: colors.teal,
      onSecondary: colors.onTeal,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.ink2,
      error: colors.danger,
      onError: colors.surface,
      errorContainer: colors.dangerTint,
      onErrorContainer: colors.danger,
      outline: colors.disabled,
      outlineVariant: colors.hairline,
      scrim: colors.ink,
    );

    final controlShape = RoundedRectangleBorder(borderRadius: BasakRadius.all(BasakRadius.control));
    const controlSize = Size.fromHeight(54);

    OutlineInputBorder ring(Color? color) => OutlineInputBorder(
          borderRadius: BasakRadius.all(BasakRadius.control),
          borderSide: color == null ? BorderSide.none : BorderSide(color: color, width: 2),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: const [colors, text],
      scaffoldBackgroundColor: colors.ground,
      canvasColor: colors.ground,
      dividerColor: colors.hairline,
      // One typeface for the whole app, including text that sets no style.
      fontFamily: BasakText.fontFamily,
      textTheme: TextTheme(
        headlineMedium: text.display,
        headlineSmall: text.title,
        titleLarge: text.sheetTitle,
        titleMedium: text.rowTitle,
        titleSmall: text.label,
        bodyLarge: text.body,
        bodyMedium: text.bodySmall,
        bodySmall: text.caption,
        labelLarge: text.rowTitle,
        labelMedium: text.label,
        labelSmall: text.tab,
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.ground,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.headline,
        // Dark status-bar icons on the light ground.
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.teal,
          foregroundColor: colors.onTeal,
          disabledBackgroundColor: colors.sunken,
          disabledForegroundColor: colors.disabled,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: controlSize,
          shape: controlShape,
          textStyle: text.rowTitle,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.teal,
          foregroundColor: colors.onTeal,
          disabledBackgroundColor: colors.sunken,
          disabledForegroundColor: colors.disabled,
          minimumSize: controlSize,
          shape: controlShape,
          textStyle: text.rowTitle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          side: BorderSide(color: colors.hairline),
          minimumSize: controlSize,
          shape: controlShape,
          textStyle: text.rowTitle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.teal,
          minimumSize: const Size(BasakSpace.tapTarget, BasakSpace.tapTarget),
          shape: RoundedRectangleBorder(borderRadius: BasakRadius.all(BasakRadius.small)),
          textStyle: text.bodySmall.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Sunken at rest; white inside the ring once focused or in error.
        fillColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.focused) || states.contains(WidgetState.error)
                ? colors.surface
                : colors.sunken),
        contentPadding: const EdgeInsets.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s16),
        hintStyle: text.body.copyWith(color: colors.ink3),
        labelStyle: text.label.copyWith(color: colors.ink2),
        floatingLabelStyle: text.label.copyWith(color: colors.teal),
        helperStyle: text.caption.copyWith(color: colors.ink3),
        errorStyle: text.caption.copyWith(color: colors.danger),
        border: ring(null),
        enabledBorder: ring(null),
        disabledBorder: ring(null),
        focusedBorder: ring(colors.teal),
        errorBorder: ring(colors.danger),
        focusedErrorBorder: ring(colors.danger),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.teal,
        selectionColor: colors.tealTint,
        selectionHandleColor: colors.teal,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        modalBackgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.scrim,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(BasakRadius.sheet)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BasakRadius.all(24)),
        titleTextStyle: text.headline,
        contentTextStyle: text.bodySmall.copyWith(color: colors.ink2),
      ),
      // Every message is ink; its icon carries the tone (see BasakToast).
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.ink,
        contentTextStyle: text.bodySmall.copyWith(color: colors.onInk),
        actionTextColor: colors.sky,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BasakRadius.all(BasakRadius.small)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.teal,
        linearTrackColor: colors.sunken,
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: colors.hairline, thickness: 1, space: 1),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _BasakPageTransitionsBuilder(),
        // The iPhone keeps its own transition, and with it the back swipe.
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}

/// A page rises a little and fades in over the app's 350 ms `easeInOutCubic`.
class _BasakPageTransitionsBuilder extends PageTransitionsBuilder {
  const _BasakPageTransitionsBuilder();

  @override
  Duration get transitionDuration => BasakMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Reduced motion: the fade alone.
    final slides = !MediaQuery.disableAnimationsOf(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: BasakMotion.pageCurve,
      reverseCurve: BasakMotion.pageCurve.flipped,
    );
    final faded = FadeTransition(opacity: curved, child: child);
    if (!slides) return faded;
    return SlideTransition(
      position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(curved),
      child: faded,
    );
  }
}
