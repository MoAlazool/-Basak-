import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'tokens.dart';

/// The entry set: what the screens before the app share (welcome, sign-in,
/// sign-up, recovery). They sit on the light ground with no decoration; their
/// character is the lockup, the grouped card and the route rail.

const _logo = AssetImage('assets/images/basak_icon.webp');

/// The app's mark: the round icon. 104 on the splash, 96 on the welcome page.
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => ClipOval(
        child: Image(image: _logo, width: size, height: size, fit: BoxFit.cover, excludeFromSemantics: true),
      );
}

/// The name beside the icon, at the far end of an entry screen's header.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('باصك', style: context.text.headline),
          const SizedBox(width: BasakSpace.s10),
          ClipRRect(
            borderRadius: BasakRadius.all(BasakRadius.tile),
            child: const Image(image: _logo, width: 40, height: 40, fit: BoxFit.cover, excludeFromSemantics: true),
          ),
        ],
      );
}

/// The welcome page's centre: the mark, the name set large, one line.
class BrandHero extends StatelessWidget {
  final String tagline;

  const BrandHero({super.key, required this.tagline});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(),
        const SizedBox(height: BasakSpace.s20),
        Text('باصك', style: text.display.copyWith(fontSize: 32, height: 44 / 32)),
        const SizedBox(height: BasakSpace.s6),
        Text(tagline,
            textAlign: TextAlign.center,
            style: text.rowTitle.copyWith(fontWeight: FontWeight.w400, color: context.colors.ink2)),
      ],
    );
  }
}

/// Shows or hides what is typed in a password field: the field's trailing.
class PasswordEye extends StatelessWidget {
  final bool hidden;
  final VoidCallback onTap;

  const PasswordEye({super.key, required this.hidden, required this.onTap});

  @override
  Widget build(BuildContext context) => BasakPressable(
        onTap: onTap,
        semanticLabel: hidden ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
        child: Center(
          widthFactor: 1,
          child: Icon(hidden ? LucideIcons.eye : LucideIcons.eyeOff, size: 20, color: context.colors.ink3),
        ),
      );
}

/// The frame of an entry screen: the back button and what faces it, an
/// optional rail, the question in large type with one line of why, the
/// blocks, and the actions held at the bottom. On a short screen, or with
/// the keyboard up, the page scrolls and the actions follow the content.
class EntryPage extends StatelessWidget {
  /// Null: no back button (a screen there is no way back from).
  final VoidCallback? onBack;

  /// Faces the back button: a [BrandLockup], or the flow's name.
  final Widget? trailing;

  /// Under the header: the sign-up's [StepRail].
  final Widget? rail;

  final String title;
  final String? subtitle;

  /// 26 / 36 for a step of a flow; 30 / 40 for a screen that stands alone.
  final bool step;

  final List<Widget> children;

  /// The actions: the one primary button, then a quiet link under it.
  final List<Widget> actions;

  const EntryPage({
    super.key,
    this.onBack,
    this.trailing,
    this.rail,
    required this.title,
    this.subtitle,
    this.step = false,
    required this.children,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final titleStyle = step
        ? text.display.copyWith(fontSize: 26, height: 36 / 26)
        : text.display.copyWith(fontSize: 30, height: 40 / 30);

    final blocks = <Widget>[
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: BasakSpace.tapTarget),
        child: Row(
          children: [
            if (onBack != null)
              BasakIconButton(
                icon: rtl ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
                label: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack,
              ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      ),
      if (rail != null) rail!,
      Padding(
        padding: const EdgeInsetsDirectional.only(top: BasakSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(header: true, child: Text(title, style: titleStyle)),
            if (subtitle != null) ...[
              const SizedBox(height: BasakSpace.s6),
              Text(subtitle!, style: text.body.copyWith(color: colors.ink2)),
            ],
          ],
        ),
      ),
      ...children,
    ];

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: basakMaxTextScale,
      child: Scaffold(
        backgroundColor: colors.ground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, 0),
                    sliver: SliverList.separated(
                      itemCount: blocks.length,
                      itemBuilder: (context, index) => blocks[index],
                      separatorBuilder: (context, index) => const SizedBox(height: BasakSpace.s18),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          BasakSpace.gutter, BasakSpace.s18, BasakSpace.gutter, BasakSpace.s16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(height: BasakSpace.s2),
                            actions[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The route rail as a stepper: passed stops are filled teal with a check,
/// the current one is a teal ring, the rest are empty.
class StepRail extends StatelessWidget {
  final List<String> steps;

  /// The index of the step on screen.
  final int current;

  const StepRail({super.key, required this.steps, required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget node(int i) {
      if (i < current) {
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle),
          child: Icon(LucideIcons.check, size: 12, color: colors.onTeal),
        );
      }
      final now = i == current;
      return Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: now ? colors.teal : colors.grabber, width: 2),
        ),
        child: now
            ? Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle))
            : null,
      );
    }

    Widget line(Color color) => Expanded(child: Container(height: 2, color: color));

    return Semantics(
      container: true,
      label: 'الخطوة ${current + 1} من ${steps.length}: ${steps[current]}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        line(i == 0 ? Colors.transparent : (i <= current ? colors.teal : colors.track)),
                        node(i),
                        line(i == steps.length - 1
                            ? Colors.transparent
                            : (i < current ? colors.teal : colors.track)),
                      ],
                    ),
                    const SizedBox(height: BasakSpace.s6),
                    Text(
                      steps[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: i == current
                          ? text.caption.copyWith(fontWeight: FontWeight.w600)
                          : text.caption.copyWith(color: i < current ? colors.teal : colors.ink3),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum EntryLinkTone {
  /// Teal: another way forward ("لديّ رمز بالفعل").
  action,

  /// Ink: a way aside ("تخطي", "دخول المشرفين").
  quiet,

  /// Red: the way out ("تسجيل الخروج").
  danger,
}

/// A text link of an entry screen, 48 high: the second action under the
/// primary button, or, [inline], a few words inside a line.
class EntryLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final EntryLinkTone tone;

  /// As wide as its words, 14 px: "نسيت كلمة المرور؟", "إنشاء حساب".
  final bool inline;

  /// 600 instead of 500: the link a sentence leads to.
  final bool strong;

  const EntryLink({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = EntryLinkTone.action,
    this.inline = false,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = onTap == null
        ? colors.disabled
        : switch (tone) {
            EntryLinkTone.action => colors.teal,
            EntryLinkTone.quiet => colors.ink2,
            EntryLinkTone.danger => colors.danger,
          };
    final style = (inline ? context.text.bodySmall : context.text.body)
        .copyWith(color: color, fontWeight: strong ? FontWeight.w600 : FontWeight.w500);
    return BasakPressable(
      onTap: onTap,
      child: Center(
        widthFactor: inline ? 1 : null,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ),
    );
  }
}

/// One quiet line of why, under a card: a small glyph and a sentence.
class InfoNote extends StatelessWidget {
  final String text;
  final IconData icon;

  const InfoNote(this.text, {super.key, this.icon = LucideIcons.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
          child: Icon(icon, size: 16, color: colors.ink3),
        ),
        const SizedBox(width: BasakSpace.s10),
        Expanded(
          child: Text(text, style: context.text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
        ),
      ],
    );
  }
}

/// A field's error when the field itself cannot carry it (a tick box, the
/// code boxes): one red line.
class FieldNote extends StatelessWidget {
  final String text;

  const FieldNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Text(text, style: context.text.caption.copyWith(color: context.colors.danger)),
      );
}

/// How strong a password is, as three bars and a word.
class StrengthMeter extends StatelessWidget {
  /// 1 weak, 2 medium, 3 strong.
  final int level;
  final String label;

  const StrengthMeter({super.key, required this.level, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = level <= 1 ? colors.danger : colors.success;
    return Semantics(
      label: 'قوة كلمة المرور: $label',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: BasakSpace.s4),
                    Expanded(
                      child: AnimatedContainer(
                        duration: BasakMotion.fade,
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < level ? tone : colors.track,
                          borderRadius: BasakRadius.all(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s10),
            Text(label, style: context.text.caption.copyWith(color: tone, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// A tick box and what it agrees to. The whole row is the target.
class CheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget child;

  /// A smaller box for a choice that should stay out of the way.
  final bool quiet;

  const CheckRow({super.key, required this.value, required this.onChanged, required this.child, this.quiet = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final side = quiet ? 20.0 : 24.0;
    return Semantics(
      checked: value,
      child: BasakPressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        selectionHaptic: true,
        child: Row(
          mainAxisSize: quiet ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: quiet ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: BasakMotion.press,
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: value ? colors.teal : colors.surface,
                borderRadius: BasakRadius.all(quiet ? 6 : 8),
                border: value ? null : Border.all(color: colors.grabber, width: 2),
              ),
              child: value ? Icon(LucideIcons.check, size: quiet ? 13 : 15, color: colors.onTeal) : null,
            ),
            SizedBox(width: quiet ? BasakSpace.s8 : BasakSpace.s12),
            if (quiet) child else Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// A code typed one digit to a box, left to right whatever the language.
class CodeField extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final String semanticLabel;

  const CodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onChanged,
    this.hasError = false,
    this.semanticLabel = 'الرمز',
  });

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(CodeField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final code = widget.controller.text;
    final active = math.min(code.length, widget.length - 1);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) const SizedBox(width: BasakSpace.s8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: BasakMotion.press,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BasakRadius.all(BasakRadius.small),
                        border: widget.hasError
                            ? Border.all(color: colors.danger, width: 2)
                            : (_focus.hasFocus && i == active ? Border.all(color: colors.teal, width: 2) : null),
                        boxShadow: BasakShadow.card,
                      ),
                      child: Text(
                        i < code.length ? code[i] : '',
                        textScaler: TextScaler.noScaling,
                        style: context.text.title,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The one real field: unseen, over the boxes, so a tap anywhere types.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: Semantics(
                label: widget.semanticLabel,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  enableInteractiveSelection: false,
                  showCursor: false,
                  maxLength: widget.length,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  onChanged: widget.onChanged,
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The search box at the top of a picker sheet.
class BasakSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const BasakSearchField({super.key, required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.text.body;
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsetsDirectional.only(start: BasakSpace.s14),
      decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.control)),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 19, color: colors.ink3),
          const SizedBox(width: BasakSpace.s10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: style,
              cursorColor: colors.teal,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: BasakSpace.s12),
                hintText: hint,
                hintStyle: style.copyWith(color: colors.ink3),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(width: BasakSpace.s14)
                : BasakPressable(
                    semanticLabel: 'مسح البحث',
                    onTap: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                    child: Center(widthFactor: 1, child: Icon(LucideIcons.x, size: 18, color: colors.ink3)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One option of a picker sheet: a name, a line under it when there is one,
/// and a radio at the end. The chosen one is tinted.
class SheetRadioRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const SheetRadioRow({super.key, required this.title, this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final tall = subtitle != null;
    return BasakPressable(
      onTap: onTap,
      selected: selected,
      selectionHaptic: true,
      child: AnimatedContainer(
        duration: BasakMotion.fade,
        curve: BasakMotion.fadeCurve,
        constraints: BoxConstraints(minHeight: tall ? 64 : 50),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12, vertical: BasakSpace.s8),
        decoration: BoxDecoration(
          color: selected ? colors.tealTint : colors.surface,
          borderRadius: BasakRadius.all(tall ? BasakRadius.control : BasakRadius.small),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: text.rowTitle.copyWith(
                        fontWeight: selected ? FontWeight.w600 : (tall ? FontWeight.w500 : FontWeight.w400)),
                  ),
                  if (tall)
                    Text(subtitle!, style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            AnimatedContainer(
              duration: BasakMotion.fade,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? colors.teal : colors.grabber, width: selected ? 7 : 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A way to go on, as a row of a sheet: a glyph in a tile, what it does, and
/// a chevron ("التقاط صورة بالكاميرا").
class SheetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const SheetActionRow({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return BasakPressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s10),
        decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: colors.surface, borderRadius: BasakRadius.all(BasakRadius.tile)),
              child: Icon(icon, size: 20, color: colors.teal),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Text(label, style: context.text.rowTitle.copyWith(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: BasakSpace.s8),
            Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
          ],
        ),
      ),
    );
  }
}

/// Where the account's photo goes: a dashed circle until there is one, then
/// the photo itself, drawn as it will be everywhere else.
class PhotoDrop extends StatelessWidget {
  final ImageProvider? image;
  final VoidCallback? onTap;
  final double size;

  const PhotoDrop({super.key, this.image, this.onTap, this.size = 168});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onTap,
      semanticLabel: image == null ? 'مكان الصورة' : 'تغيير الصورة',
      child: SizedBox.square(
        dimension: size,
        child: image == null
            ? CustomPaint(
                painter: _DashedCircle(color: colors.disabled, fill: colors.surface),
                child: Center(child: Icon(LucideIcons.camera, size: 40, color: colors.ink3)),
              )
            : Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.avatarTint,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 3, strokeAlign: BorderSide.strokeAlignOutside),
                  boxShadow: BasakShadow.card,
                ),
                child: Image(
                  image: image!,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
              ),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  final Color color;
  final Color fill;

  const _DashedCircle({required this.color, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    canvas.drawOval(rect, Paint()..color = fill);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    const dashes = 44;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * .58, false, stroke);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color || old.fill != fill;
}

/// The splash's rail: three stops, drawn as far as [progress] (0 to 1) has
/// travelled. The stop behind is filled, the one being reached is a ring.
class SplashRail extends StatelessWidget {
  final double progress;

  const SplashRail({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget stop(double at) {
      final reached = progress >= at;
      final passed = progress >= at + .5 || (at == 0);
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: passed ? colors.sky : null,
          shape: BoxShape.circle,
          border: passed ? null : Border.all(color: reached ? colors.sky : colors.inkRule, width: 2),
        ),
      );
    }

    Widget line(double from) => SizedBox(
          width: 44,
          height: 2,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: colors.inkRule)),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: 44 * ((progress - from) / .5).clamp(0.0, 1.0),
                child: ColoredBox(color: colors.sky),
              ),
            ],
          ),
        );

    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [stop(0), line(0), stop(.5), line(.5), stop(1)],
      ),
    );
  }
}
