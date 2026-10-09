import 'package:flutter/material.dart';

/// The design tokens of the 2026 redesign ("The Route"). Every colour, text
/// role, space, radius, duration and shadow the app draws with is named here;
/// screens read them through `context.colors` and `context.text` and never
/// write a literal of their own. Values are the ones printed on the canvas
/// boards `System` and `SystemPlus`.

/// The raw values. Screens do not read this class: it exists so the theme and
/// the deprecated `AppColors` aliases can stay compile-time constants.
abstract final class BasakPalette {
  // Surfaces and ink
  static const ground = Color(0xFFF0F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const sunken = Color(0xFFE4ECF1);
  static const hairline = Color(0xFFDCE6EC);
  static const ink = Color(0xFF17384A);
  static const ink2 = Color(0xFF476273);
  static const ink3 = Color(0xFF58707F);
  static const inkRaised = Color(0xFF214B61);
  static const inkRule = Color(0xFF34596D);
  static const inkRing = Color(0xFF1D4357);
  static const inkOutline = Color(0xFF3E6478);
  static const onInk2 = Color(0xFFA9BCC8);

  // Brand
  static const teal = Color(0xFF00658D);
  static const tealPressed = Color(0xFF004F6E);
  static const tealTint = Color(0xFFE5F3FA);
  static const sky = Color(0xFFA8D8F0);
  static const mint = Color(0xFF5BD4A0);

  // Status: a text-safe tone and its tint
  static const success = Color(0xFF0A6B4A);
  static const successTint = Color(0xFFE3F4EC);
  static const warning = Color(0xFF8A5300);
  static const warningTint = Color(0xFFFCF1DC);
  static const danger = Color(0xFFB3261E);
  static const dangerTint = Color(0xFFFCEBE9);

  // Core additions (board SystemPlus)
  static const avatarTint = Color(0xFFD6EBF5);
  static const photoFill = Color(0xFF8DBFD6);
  static const track = Color(0xFFD5E0E7);
  static const grabber = Color(0xFFC3D1DA);
  static const disabled = Color(0xFF9DB0BB);
  static const badge = Color(0xFFC8372D);
  static const qrInk = Color(0xFF102A3A);

  // Status accents: rings and dots, always paired with a word
  static const pendingRing = Color(0xFFE0B25A);
  static const openDot = Color(0xFFF2C46B);
  static const refusedFrame = Color(0xFFF2867E);

  // Scanner surface (supervisor scan only)
  static const scanBase = Color(0xFF0A161D);
  static const scanPanel = Color(0xFF10222C);
  static const scanGlow = Color(0xFF2B4452);
  static const scanGlass = Color(0x24FFFFFF); // white at 14%
}

/// The working palette, as a theme extension. One theme (light), so `copyWith`
/// and `lerp` have nothing to vary.
@immutable
class BasakColors extends ThemeExtension<BasakColors> {
  const BasakColors._();

  static const light = BasakColors._();

  Color get ground => BasakPalette.ground;
  Color get surface => BasakPalette.surface;
  Color get sunken => BasakPalette.sunken;
  Color get hairline => BasakPalette.hairline;
  Color get ink => BasakPalette.ink;
  Color get ink2 => BasakPalette.ink2;
  Color get ink3 => BasakPalette.ink3;
  Color get inkRaised => BasakPalette.inkRaised;
  Color get inkRule => BasakPalette.inkRule;
  Color get inkRing => BasakPalette.inkRing;
  Color get inkOutline => BasakPalette.inkOutline;
  Color get onInk => BasakPalette.surface;
  Color get onInk2 => BasakPalette.onInk2;

  Color get teal => BasakPalette.teal;
  Color get tealPressed => BasakPalette.tealPressed;
  Color get tealTint => BasakPalette.tealTint;
  Color get onTeal => BasakPalette.surface;
  Color get sky => BasakPalette.sky;
  Color get mint => BasakPalette.mint;

  Color get success => BasakPalette.success;
  Color get successTint => BasakPalette.successTint;
  Color get warning => BasakPalette.warning;
  Color get warningTint => BasakPalette.warningTint;
  Color get danger => BasakPalette.danger;
  Color get dangerTint => BasakPalette.dangerTint;

  Color get avatarTint => BasakPalette.avatarTint;
  Color get photoFill => BasakPalette.photoFill;
  Color get track => BasakPalette.track;
  Color get grabber => BasakPalette.grabber;
  Color get disabled => BasakPalette.disabled;
  Color get badge => BasakPalette.badge;
  Color get qrInk => BasakPalette.qrInk;

  Color get pendingRing => BasakPalette.pendingRing;
  Color get openDot => BasakPalette.openDot;
  Color get refusedFrame => BasakPalette.refusedFrame;

  Color get scanBase => BasakPalette.scanBase;
  Color get scanPanel => BasakPalette.scanPanel;
  Color get scanGlow => BasakPalette.scanGlow;
  Color get scanGlass => BasakPalette.scanGlass;

  /// Dims what lies behind a sheet or a dialog.
  Color get scrim => BasakPalette.ink.withValues(alpha: .45);

  @override
  BasakColors copyWith() => this;

  @override
  BasakColors lerp(ThemeExtension<BasakColors>? other, double t) => this;
}

/// The expressive palette: the term recap's pages and posters only (Phase 9).
/// Kept out of the working screens, where teal is an action and ink is the pass.
abstract final class BasakRecapColors {
  static const tealRaised = Color(0xFF0A7AA6);
  static const sky = BasakPalette.sky;
  static const skyDeep = Color(0xFF8FCBE8);
  static const mintDeep = Color(0xFF49C792);
  static const onMint = Color(0xFF0A5A40);
  static const inkRaised = BasakPalette.inkRaised;
  static const inkDim = Color(0xFF2A566C);
  static const onInkSoft = Color(0xFFB7C8D2);

  // The posters' second tone and resting dots, per ground.
  static const onTealSoft = Color(0xFFD3E8F3);
  static const tealDim = Color(0xFF1787B3);
  static const onMintSoft = Color(0xFF1B5343);
  static const onSkySoft = Color(0xFF2F5468);
  static const lightDim = Color(0xFFE1E9EE);
}

/// The fifteen text roles. Sizes and line heights are the canvas's; Flutter's
/// `height` is line ÷ size. Every role is ink by default — recolour with
/// `copyWith(color: context.colors.…)`.
@immutable
class BasakText extends ThemeExtension<BasakText> {
  const BasakText._();

  static const standard = BasakText._();

  static const fontFamily = 'ReadexPro';

  static const _base = TextStyle(
    fontFamily: fontFamily,
    color: BasakPalette.ink,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle _role(double size, double line, FontWeight weight) =>
      _base.copyWith(fontSize: size, height: line / size, fontWeight: weight);

  /// 28 / 38 · 600 — page titles.
  TextStyle get display => _role(28, 38, FontWeight.w600);

  /// 22 / 32 · 600 — questions, the name in the Home header.
  TextStyle get title => _role(22, 32, FontWeight.w600);

  /// 20 / 30 · 600 — sheet titles.
  TextStyle get sheetTitle => _role(20, 30, FontWeight.w600);

  /// 17 / 26 · 600 — card titles, section heads.
  TextStyle get headline => _role(17, 26, FontWeight.w600);

  /// 16 / 26 · 600 — row titles, button labels.
  TextStyle get rowTitle => _role(16, 26, FontWeight.w600);

  /// 15 / 24 · 400 — text.
  TextStyle get body => _role(15, 24, FontWeight.w400);

  /// 14 / 22 · 400 — supporting text.
  TextStyle get bodySmall => _role(14, 22, FontWeight.w400);

  /// 13 / 20 · 500 — field labels, meta.
  TextStyle get label => _role(13, 20, FontWeight.w500);

  /// 12 / 18 · 400 — stamps, helper.
  TextStyle get caption => _role(12, 18, FontWeight.w400);

  /// 11 / 16 · 400 (600 when selected) — the tab bar only.
  TextStyle get tab => _role(11, 16, FontWeight.w400);

  /// 34 / 44 · 600 — the one amount on a pay or receipt screen.
  TextStyle get amount => _role(34, 44, FontWeight.w600);

  /// 48 / 56 · 600 — the supervisor's two totals.
  TextStyle get total => _role(48, 56, FontWeight.w600);

  // The recap's poster roles; weight 700 appears nowhere else (Phase 9).

  /// 40 / 48 · 700.
  TextStyle get posterTitle => _role(40, 48, FontWeight.w700);

  /// 68 / 78 · 700.
  TextStyle get storyTitle => _role(68, 78, FontWeight.w700);

  /// 144 / 150 · 700.
  TextStyle get posterNumeral => _role(144, 150, FontWeight.w700);

  @override
  BasakText copyWith() => this;

  @override
  BasakText lerp(ThemeExtension<BasakText>? other, double t) => this;
}

/// The 4-point spacing scale.
abstract final class BasakSpace {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;

  /// The screen's side padding.
  static const double gutter = s20;

  /// Between two cards.
  static const double betweenCards = s16;

  /// Between two sections.
  static const double betweenSections = s28;

  /// Inside a card.
  static const double card = s18;

  /// The smallest tap target, even when the glyph is 20.
  static const double tapTarget = 48;

  /// Wide screens centre one column of this width.
  static const double maxContentWidth = 480;
}

abstract final class BasakRadius {
  /// Tags.
  static const double tag = 10;

  /// Icon tiles and stepped chips.
  static const double tile = 12;

  /// Small buttons, strips, toasts.
  static const double small = 14;

  /// Buttons, inputs, rows.
  static const double control = 16;

  /// Cards.
  static const double card = 20;

  /// The pass and sheets.
  static const double sheet = 28;

  /// Chips, avatars, the tab bar.
  static const double full = 999;

  static BorderRadius all(double radius) => BorderRadius.all(Radius.circular(radius));
}

abstract final class BasakMotion {
  /// A press: scale to [pressScale].
  static const press = Duration(milliseconds: 120);
  static const double pressScale = .98;

  /// Fades, the connection strip, chips.
  static const fade = Duration(milliseconds: 200);
  static const Curve fadeCurve = Curves.easeOut;

  static const sheetIn = Duration(milliseconds: 280);
  static const Curve sheetInCurve = Curves.easeOutCubic;
  static const sheetOut = Duration(milliseconds: 200);
  static const Curve sheetOutCurve = Curves.easeIn;

  /// Pages, the day pager, the tab bar.
  static const page = Duration(milliseconds: 350);
  static const Curve pageCurve = Curves.easeInOutCubic;

  /// A boarded scan result closes itself.
  static const boardedResult = Duration(seconds: 2);

  /// "Back online" in the connection strip.
  static const backOnline = Duration(seconds: 2);

  /// One toast at a time.
  static const toast = Duration(seconds: 3);

  /// The skeleton's slow pulse.
  static const skeleton = Duration(milliseconds: 1200);
}

/// The two shadows: a card's, and a floating layer's (sheets, toasts, the tab bar).
abstract final class BasakShadow {
  static const card = [
    BoxShadow(color: Color(0x0D17384A), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const floating = [
    BoxShadow(color: Color(0x4717384A), offset: Offset(0, 16), blurRadius: 40, spreadRadius: -12),
  ];
}

extension BasakTheme on BuildContext {
  /// The palette. Falls back to the light one so a widget also works under a
  /// bare `MaterialApp`, as the widget tests build it.
  BasakColors get colors => Theme.of(this).extension<BasakColors>() ?? BasakColors.light;

  BasakText get text => Theme.of(this).extension<BasakText>() ?? BasakText.standard;
}
