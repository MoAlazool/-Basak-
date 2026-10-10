import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/ui/ui.dart';

/// The picture of an onboarding page: an ink panel holding small copies of
/// the components the page talks about. Decorative: hidden from screen
/// readers, never scaled with the text, and shrunk as a whole on a short
/// screen. Each is laid out on the board's 366 × 456 panel.
class OnboardingArt extends StatelessWidget {
  /// 0 companies · 1 subscribe and pay · 2 confirm and follow · 3 the card.
  final int page;

  const OnboardingArt({super.key, required this.page});

  static const _size = Size(366, 456);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: context.colors.ink, borderRadius: BasakRadius.all(36)),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MediaQuery.withNoTextScaling(
              child: SizedBox.fromSize(
                size: _size,
                child: switch (page) {
                  0 => const _Companies(),
                  1 => const _Subscribe(),
                  2 => const _Follow(),
                  _ => const _Card(),
                },
              ),
            ),
          ),
        ),
      );
}

Widget _pill(BuildContext context, {Widget? leading, required String label, bool strong = false}) => Container(
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: strong ? BasakSpace.s16 : BasakSpace.s14, vertical: BasakSpace.s8),
      decoration: BoxDecoration(color: context.colors.inkRaised, borderRadius: BasakRadius.all(BasakRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: BasakSpace.s8)],
          Text(
            label,
            style: strong
                ? context.text.bodySmall.copyWith(color: context.colors.onInk, fontWeight: FontWeight.w600)
                : context.text.label.copyWith(color: context.colors.onInk),
          ),
        ],
      ),
    );

Widget _card(BuildContext context,
        {required Widget child,
        double radius = 18,
        EdgeInsetsGeometry padding =
            const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
        bool raised = true}) =>
    Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BasakRadius.all(radius),
        boxShadow: raised ? BasakShadow.floating : null,
      ),
      child: child,
    );

Widget _tile(BuildContext context, {required Color tint, required Widget child}) => Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint, borderRadius: BasakRadius.all(BasakRadius.tile)),
      child: child,
    );

/// «من 4,500»: the small word, then the number.
Widget _from(BuildContext context, String amount, {bool large = false, String? unit}) {
  final text = context.text;
  final small = (large ? text.caption : text.tab).copyWith(color: context.colors.ink3);
  return Text.rich(TextSpan(
    style: large ? text.headline : text.label.copyWith(fontWeight: FontWeight.w600),
    children: [
      TextSpan(text: 'من ', style: small),
      TextSpan(text: amount),
      if (unit != null) TextSpan(text: ' $unit', style: small),
    ],
  ));
}

/// 1 · Three companies with their lines and prices, under the university.
class _Companies extends StatelessWidget {
  const _Companies();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget company(String letter, Color tint, String name, String lines, String price) => _card(
          context,
          child: Row(
            children: [
              _tile(context, tint: tint, child: Text(letter, style: text.rowTitle.copyWith(color: colors.teal))),
              const SizedBox(width: BasakSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: text.body.copyWith(fontWeight: FontWeight.w600)),
                    Text(lines, style: text.caption.copyWith(color: colors.ink3)),
                  ],
                ),
              ),
              const SizedBox(width: BasakSpace.s12),
              _from(context, price),
            ],
          ),
        );

    return Stack(
      children: [
        PositionedDirectional(
          top: 34,
          start: 0,
          end: 0,
          child: Column(
            children: [
              _pill(
                context,
                strong: true,
                leading: Container(
                    width: 10, height: 10, decoration: BoxDecoration(color: colors.sky, shape: BoxShape.circle)),
                label: 'جامعة المنصورة الجديدة',
              ),
              Container(width: 2, height: 30, color: colors.inkRule),
            ],
          ),
        ),
        PositionedDirectional(
            top: 104,
            start: 24,
            width: 290,
            child: company('ن', colors.tealTint, 'النورس للنقل', '4 خطوط · 22 محطة', '4,500')),
        PositionedDirectional(
            top: 198,
            start: 52,
            width: 290,
            child: company('د', colors.successTint, 'دلتا باص', '3 خطوط · 17 محطة', '4,200')),
        PositionedDirectional(
            top: 292,
            start: 24,
            width: 290,
            child: company('ص', colors.warningTint, 'الصفوة ترانس', '5 خطوط · 31 محطة', '4,800')),
        PositionedDirectional(
          bottom: 26,
          start: 0,
          end: 0,
          child: Text('3 شركات تخدم جامعتك',
              textAlign: TextAlign.center,
              style: text.label.copyWith(color: colors.onInk2, fontWeight: FontWeight.w400)),
        ),
      ],
    );
  }
}

/// 2 · A line card, the stop being picked, and the receipt on its way.
class _Subscribe extends StatelessWidget {
  const _Subscribe();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget time(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s12, vertical: BasakSpace.s8),
            decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.tile)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: text.tab.copyWith(color: colors.ink3)),
                Text(value, style: text.bodySmall.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );

    Widget stop(String name, {bool first = false, bool last = false, bool picked = false}) => Container(
          height: 46,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s10),
          decoration: BoxDecoration(
            color: picked ? colors.tealTint : null,
            borderRadius: BasakRadius.all(BasakRadius.small),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 14,
                child: Column(
                  children: [
                    Container(width: 2, height: 16, color: first ? null : colors.grabber),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: picked ? colors.teal : colors.surface,
                        shape: BoxShape.circle,
                        border: picked ? null : Border.all(color: colors.disabled, width: 2),
                      ),
                    ),
                    Expanded(child: Container(width: 2, color: last ? null : colors.grabber)),
                  ],
                ),
              ),
              const SizedBox(width: BasakSpace.s12),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(name, style: text.body.copyWith(fontWeight: picked ? FontWeight.w600 : FontWeight.w400)),
                ),
              ),
              if (picked)
                Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle),
                    child: Icon(LucideIcons.check, size: 13, color: colors.onTeal),
                  ),
                ),
            ],
          ),
        );

    return Stack(
      children: [
        PositionedDirectional(
          top: 52,
          start: 24,
          width: 296,
          child: _card(
            context,
            radius: BasakRadius.card,
            raised: false,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('الزرقا', style: text.headline),
                          Text('7 محطات', style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                        ],
                      ),
                    ),
                    _from(context, '4,500', large: true, unit: 'ج.م'),
                  ],
                ),
                const SizedBox(height: BasakSpace.s12),
                Row(children: [
                  time('أول ذهاب', '6:15 ص'),
                  const SizedBox(width: BasakSpace.s8),
                  time('آخر عودة', '5:30 م'),
                ]),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          top: 212,
          end: 24,
          width: 268,
          child: _card(
            context,
            radius: BasakRadius.card,
            padding: const EdgeInsetsDirectional.all(BasakSpace.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                stop('ميت الخولي', first: true),
                stop('كوبري السرو', picked: true),
                stop('السرو', last: true),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          bottom: 28,
          start: 24,
          child: _pill(
            context,
            leading: Icon(LucideIcons.check, size: 15, color: colors.mint),
            label: 'وصل إيصالك · قيد المراجعة',
          ),
        ),
      ],
    );
  }
}

/// 3 · The ride question, an alert from the supervisor and one from the company.
class _Follow extends StatelessWidget {
  const _Follow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget answer(String label, {required bool primary}) => Expanded(
          flex: primary ? 7 : 5,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? colors.teal : colors.sunken,
              borderRadius: BasakRadius.all(BasakRadius.tile),
            ),
            child: Text(
              label,
              style: text.bodySmall.copyWith(
                  color: primary ? colors.onTeal : colors.ink, fontWeight: primary ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
        );

    Widget alert({
      required IconData icon,
      required BasakTone tone,
      required String from,
      String? time,
      required String title,
      bool raised = true,
    }) =>
        _card(
          context,
          raised: raised,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tile(context, tint: tone.tint(colors), child: Icon(icon, size: 19, color: tone.foreground(colors))),
              const SizedBox(width: BasakSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(from, style: text.caption.copyWith(color: colors.ink3))),
                        if (time != null) Text(time, style: text.caption.copyWith(color: colors.ink3)),
                      ],
                    ),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.body.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Stack(
      children: [
        PositionedDirectional(
          top: 50,
          start: 24,
          width: 300,
          child: _card(
            context,
            radius: BasakRadius.card,
            raised: false,
            padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('الاثنين 12 أكتوبر', style: text.caption.copyWith(color: colors.ink3))),
                    const IconPill(icon: LucideIcons.clock3, label: 'حتى 6:00 ص', tone: BasakTone.warning),
                  ],
                ),
                const SizedBox(height: BasakSpace.s12),
                Text('هل ستركب غداً؟', style: text.headline),
                const SizedBox(height: BasakSpace.s12),
                Row(children: [
                  answer('نعم، سأركب', primary: true),
                  const SizedBox(width: BasakSpace.s8),
                  answer('لن أركب', primary: false),
                ]),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          top: 242,
          end: 24,
          width: 296,
          child: alert(
            icon: LucideIcons.bus,
            tone: BasakTone.success,
            from: 'مشرف الباص',
            time: '6:58 ص',
            title: 'الباص تحرّك من موقف الزرقا',
          ),
        ),
        PositionedDirectional(
          top: 338,
          end: 44,
          width: 276,
          child: Opacity(
            opacity: .92,
            child: alert(
              icon: LucideIcons.megaphone,
              tone: BasakTone.info,
              from: 'النورس للنقل',
              title: 'تعديل موعد رحلة 7:45',
              raised: false,
            ),
          ),
        ),
      ],
    );
  }
}

/// 4 · The card, and the two things it promises.
class _Card extends StatelessWidget {
  const _Card();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Stack(
      children: [
        PositionedDirectional(
          top: 40,
          start: 58,
          end: 58,
          child: _card(
            context,
            radius: 24,
            raised: false,
            padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    PhotoRing(name: 'سارة أحمد', size: 40, ring: colors.mint),
                    const SizedBox(width: BasakSpace.s10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('سارة أحمد', style: text.body.copyWith(fontWeight: FontWeight.w600)),
                          Text('الزرقا · كوبري السرو', style: text.caption.copyWith(color: colors.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BasakSpace.s12),
                QrImageView(
                  data: 'https://basak.app',
                  size: 156,
                  padding: EdgeInsets.zero,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: colors.qrInk),
                  dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: colors.qrInk),
                ),
                const SizedBox(height: BasakSpace.s12),
                const StatusChip(BasakStatus.active, label: 'اشتراك نشط'),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          bottom: 30,
          start: 0,
          end: 0,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pill(context,
                    leading: Icon(LucideIcons.shieldCheck, size: 15, color: colors.onInk), label: 'بدون إنترنت'),
                const SizedBox(width: BasakSpace.s8),
                _pill(context, leading: Icon(LucideIcons.wallet, size: 15, color: colors.onInk), label: 'محفظة الهاتف'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
