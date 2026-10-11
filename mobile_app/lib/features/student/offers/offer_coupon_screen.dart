import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/signed_photo.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../../../core/widgets/avatar_image.dart';
import '../../../core/widgets/basak_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';
import 'offer_widgets.dart';
import 'offers_repository.dart';

/// The coupon at the till, as a pass card of the same family as the student's
/// bus card: the offer's picture, who it is from and what it gives, whose it
/// is, and under the tear the time it has left — counted down every second
/// beside a bar that never stands still, so a picture of the screen is
/// plainly not the screen — with the code as the cashier's reference. The
/// card itself says when it was used and when it is over. An offer with a PIN
/// is counted when the merchant types it under the card.
class OfferCouponScreen extends ConsumerStatefulWidget {
  final Offer offer;
  final OfferCoupon coupon;

  const OfferCouponScreen({super.key, required this.offer, required this.coupon});

  static Route<void> route(Offer offer, OfferCoupon coupon) =>
      MaterialPageRoute<void>(builder: (_) => OfferCouponScreen(offer: offer, coupon: coupon));

  /// The shortest and longest PIN a merchant has.
  static const pinMin = 4, pinMax = 6;

  /// «رمز غير صحيح — بقي 3 محاولات».
  static String wrongPin(int triesLeft) => switch (triesLeft) {
        <= 0 => 'رمز غير صحيح — لم تبقَ محاولات لهذا الكوبون.',
        1 => 'رمز غير صحيح — بقيت محاولة واحدة',
        2 => 'رمز غير صحيح — بقيت محاولتان',
        _ => 'رمز غير صحيح — بقي $triesLeft محاولات',
      };

  /// "09:58", and past the hour "1:02:07".
  static String clock(Duration left) {
    final seconds = left.isNegative ? 0 : left.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = seconds ~/ 3600;
    final rest = '${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}';
    return hours > 0 ? '$hours:$rest' : rest;
  }

  @override
  ConsumerState<OfferCouponScreen> createState() => _OfferCouponScreenState();
}

class _OfferCouponScreenState extends ConsumerState<OfferCouponScreen> with SingleTickerProviderStateMixin {
  late OfferCoupon _coupon = widget.coupon;
  late final AnimationController _live =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  final _pin = TextEditingController();
  Timer? _ticker;
  late DateTime _now = _clock();
  bool _confirming = false;
  bool _renewing = false;

  /// Why the last PIN did not count, in the words to show.
  String? _pinError;

  /// No tries left on this coupon: the field waits for a new one.
  bool _locked = false;

  /// When the coupon was counted, where this phone knows: the moment the PIN
  /// was accepted here, or, without a PIN, the moment the coupon was made.
  late DateTime? _usedAt = widget.coupon.confirmed && !widget.offer.needsPin
      ? widget.coupon.expiresAt.subtract(Duration(minutes: widget.offer.couponMinutes))
      : null;

  DateTime _clock() => ref.read(offersClockProvider)();

  bool get _needsPin => widget.offer.needsPin && !_coupon.confirmed;

  /// What the coupon has left: never more than a coupon is given, whatever
  /// this phone's clock says.
  Duration get _left {
    final left = _coupon.expiresAt.difference(_now);
    final most = Duration(minutes: widget.offer.couponMinutes);
    return left > most ? most : left;
  }

  bool get _expired => _left <= Duration.zero;

  @override
  void initState() {
    super.initState();
    _live.repeat(reverse: true);
    _pin.addListener(_typed);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _live.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final was = _expired;
    setState(() => _now = _clock());
    if (_expired && !was) {
      _live.stop();
      // What the offer says of its coupon is over as well.
      ref.invalidate(offersProvider);
    }
  }

  void _typed() {
    if (!mounted) return;
    // A new digit clears what was said about the last try.
    setState(() {
      if (_pin.text.isNotEmpty && !_locked) _pinError = null;
    });
  }

  String get _typedPin => AuthRepository.toLatinDigits(_pin.text.trim());

  Future<void> _confirm() async {
    final pin = _typedPin;
    if (_confirming || _locked || pin.length < OfferCouponScreen.pinMin) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _confirming = true;
      _pinError = null;
    });
    try {
      final answer = await ref.read(offersRepoProvider).confirm(_coupon.id, pin);
      if (!mounted) return;
      if (answer.confirmed) {
        setState(() {
          _confirming = false;
          _coupon = _coupon.asConfirmed();
          _usedAt = _clock();
        });
        // Used: Home and the offer's page say so.
        ref.invalidate(offersProvider);
      } else {
        _pin.clear();
        setState(() {
          _confirming = false;
          _locked = answer.triesLeft <= 0;
          _pinError = OfferCouponScreen.wrongPin(answer.triesLeft);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _pinError = errorMessage(error);
      });
    }
  }

  /// «اطلب كوبوناً جديداً», after the minutes ran out before it was used.
  Future<void> _renew() async {
    if (_renewing) return;
    setState(() => _renewing = true);
    try {
      final coupon = await ref.read(offersRepoProvider).redeem(widget.offer.id);
      if (!mounted) return;
      _pin.clear();
      setState(() {
        _renewing = false;
        _coupon = coupon;
        _now = _clock();
        _usedAt = coupon.confirmed ? _now : null;
        _locked = false;
        _pinError = null;
      });
      _live.repeat(reverse: true);
      ref.invalidate(offersProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _renewing = false);
      ref.invalidate(offersProvider);
      BasakToast.show(context, errorMessage(error), kind: BasakToastKind.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final expired = _expired;
    final used = _coupon.confirmed;
    return Scaffold(
      backgroundColor: colors.ground,
      body: BasakPage(
        header: const PageTitleBar(title: 'الكوبون'),
        children: [
          _card(context),
          if (!expired && used && !widget.offer.needsPin)
            Text('أرِ هذه البطاقة للكاشير قبل انتهاء الوقت.',
                textAlign: TextAlign.center, style: context.text.label.copyWith(color: colors.ink2)),
          if (!expired && _needsPin) _pinEntry(context),
          if (expired && used)
            BasakButton(
              label: 'تم',
              variant: BasakButtonVariant.secondary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }

  /// Where the coupon stands, as the card's own strip says it.
  Widget _standing(bool expired) {
    if (_coupon.confirmed) {
      final at = _usedAt;
      return InfoStrip(
        key: const Key('coupon-used'),
        tone: BasakTone.success,
        label: 'تم الاستخدام',
        value: at == null
            ? 'أكّد الكاشير الكوبون'
            : 'الساعة ${BasakUi.time12('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}')}',
        icon: LucideIcons.check,
      );
    }
    if (expired) {
      return const InfoStrip(
        key: Key('coupon-expired'),
        tone: BasakTone.neutral,
        label: 'انتهت مدة الكوبون',
        value: 'لم يُحسب عليك استخدام',
        icon: LucideIcons.hourglass,
      );
    }
    return const InfoStrip(
      key: Key('coupon-waiting'),
      tone: BasakTone.warning,
      label: 'بانتظار الكاشير',
      value: 'يكتب رمز المحل في الأسفل',
      icon: LucideIcons.clock3,
    );
  }

  /// The pass: the picture, the merchant and the offer, whose coupon it is,
  /// and under the tear where it stands, the time left and the code.
  Widget _card(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final offer = widget.offer;
    final merchant = offer.merchant;
    final expired = _expired;
    final used = _coupon.confirmed;
    final user = ref.watch(authStateProvider).user;
    final profile = user == null ? null : ref.watch(studentProfileSummaryProvider(user.id)).valueOrNull;
    final typed = ((profile?['full_name'] ?? user?.userMetadata?['full_name']) as String?)?.trim() ?? '';
    final name = typed.isEmpty ? 'الطالب' : typed;
    final photo = studentPhoto(profile?['profile_image_url'] as String?);
    final photoUrl = photo == null ? null : ref.watch(signedPhotoProvider(photo)).valueOrNull;
    final code = _coupon.code.split('').join(' ');
    // A coupon that is over reads as one: its words step back.
    final strong = expired ? colors.ink3 : colors.ink;

    return Semantics(
      container: true,
      label: 'كوبون ${merchant.name}',
      child: Container(
        key: const Key('coupon-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BasakRadius.all(BasakRadius.sheet),
          boxShadow: BasakShadow.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OfferPicture(offer, aspectRatio: 2.4, muted: expired),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s16, BasakSpace.s20, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OfferLogo(merchant, size: 40),
                      const SizedBox(width: BasakSpace.s12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (merchant.name.isNotEmpty)
                              Text(merchant.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.rowTitle.copyWith(color: strong)),
                            Text(merchant.category.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.caption.copyWith(color: colors.ink3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: BasakSpace.s14),
                  if (offer.valueLabel.isNotEmpty)
                    // Whole and on one line, however long the merchant made it.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(offer.valueLabel,
                          maxLines: 1, style: text.amount.copyWith(color: expired ? colors.ink3 : colors.teal)),
                    ),
                  Text(offer.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.body.copyWith(fontWeight: FontWeight.w500, color: strong)),
                  const SizedBox(height: BasakSpace.s16),
                  Row(
                    children: [
                      PhotoRing(
                        key: const Key('coupon-student-photo'),
                        name: name,
                        image: photoUrl == null ? null : avatarImage(photoUrl),
                        size: 48,
                        ring: used ? colors.success : (expired ? colors.track : colors.teal),
                      ),
                      const SizedBox(width: BasakSpace.s14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('صاحب الكوبون', style: text.caption.copyWith(color: colors.ink3)),
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.headline.copyWith(color: strong)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: BasakSpace.s6),
            TicketTear(color: colors.track),
            Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(BasakSpace.s20, BasakSpace.s6, BasakSpace.s20, BasakSpace.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(liveRegion: true, child: _standing(expired)),
                  if (!expired) ...[
                    const SizedBox(height: BasakSpace.s14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ينتهي بعد', style: text.caption.copyWith(color: colors.ink3)),
                            Text(
                              OfferCouponScreen.clock(_left),
                              key: const Key('coupon-countdown'),
                              textDirection: TextDirection.ltr,
                              style: text.title.copyWith(
                                color: _left < const Duration(minutes: 1) ? colors.danger : colors.ink,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: BasakSpace.s16),
                        // The cashier's reference: small, and never cut.
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('الرمز', style: text.caption.copyWith(color: colors.ink3)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerEnd,
                                child: Semantics(
                                  label: 'رمز الكوبون $code',
                                  child: ExcludeSemantics(
                                    child: Text(
                                      code,
                                      key: const Key('coupon-code'),
                                      maxLines: 1,
                                      textDirection: TextDirection.ltr,
                                      style: text.body.copyWith(
                                        color: colors.ink2,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 1.5,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BasakSpace.s12),
                    _LiveBar(animation: _live),
                  ] else if (!used) ...[
                    const SizedBox(height: BasakSpace.s14),
                    BasakButton(
                      key: const Key('coupon-renew'),
                      label: 'اطلب كوبوناً جديداً',
                      size: BasakButtonSize.medium,
                      loading: _renewing,
                      onPressed: _renew,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Where the merchant types their PIN.
  Widget _pinEntry(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final enough = _typedPin.length >= OfferCouponScreen.pinMin;
    return GroupSection(
      title: 'رمز المحل (يكتبه الكاشير)',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IgnorePointer(
            ignoring: _locked || _confirming,
            child: CodeField(
              key: const Key('coupon-pin'),
              controller: _pin,
              length: OfferCouponScreen.pinMax,
              hasError: _pinError != null,
              semanticLabel: 'رمز المحل',
            ),
          ),
          if (_pinError != null) ...[
            const SizedBox(height: BasakSpace.s8),
            Semantics(
              liveRegion: true,
              child: Text(_pinError!,
                  key: const Key('coupon-pin-error'), style: text.label.copyWith(color: colors.danger)),
            ),
          ],
          const SizedBox(height: BasakSpace.s14),
          BasakButton(
            key: const Key('coupon-confirm'),
            label: 'تأكيد',
            loading: _confirming,
            onPressed: enough && !_locked ? _confirm : null,
          ),
        ],
      ),
    );
  }
}

/// A mark that slides along its track for as long as the coupon runs: the one
/// thing on the screen a picture of it cannot do.
class _LiveBar extends StatelessWidget {
  final Animation<double> animation;

  const _LiveBar({required this.animation});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        key: const Key('coupon-live'),
        height: BasakSpace.s6,
        decoration: BoxDecoration(color: colors.track, borderRadius: BasakRadius.all(BasakRadius.full)),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Align(
            alignment: Alignment(Curves.easeInOut.transform(animation.value) * 2 - 1, 0),
            child: child,
          ),
          child: FractionallySizedBox(
            widthFactor: .28,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: colors.teal, borderRadius: BasakRadius.all(BasakRadius.full)),
            ),
          ),
        ),
      ),
    );
  }
}
