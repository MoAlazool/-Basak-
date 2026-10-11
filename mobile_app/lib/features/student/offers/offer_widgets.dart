import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import 'offers_repository.dart';

/// The merchant's logo, or the first letters of its name.
class OfferLogo extends StatelessWidget {
  final OfferMerchant merchant;
  final double size;

  /// On the tinted panel that stands in for a picture: the mark's tile is
  /// white, where on a card it is the tint.
  final bool onTint;

  const OfferLogo(this.merchant, {super.key, this.size = 40, this.onTint = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = merchant.logoUrl;
    Widget tile(Widget child) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.surface, borderRadius: BasakRadius.all(BasakRadius.tile)),
          child: child,
        );
    return CompanyLogo.image(
      name: merchant.name,
      image: url == null ? null : companyLogoImage(url),
      size: size,
      radius: BasakRadius.tile,
      placeholder: merchant.name.isEmpty
          ? (onTint
              ? tile(Icon(LucideIcons.tag, size: size * .45, color: colors.teal))
              : ToneTile(LucideIcons.tag, tone: BasakTone.info, size: size))
          : onTint
              ? tile(Text(
                  CompanyLogo.initialsOf(merchant.name),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: context.text.rowTitle.copyWith(color: colors.teal, fontSize: size * .34, height: 1.2),
                ))
              : null,
    );
  }
}

/// The offer's picture in its slot, which never changes size: while the
/// picture loads, when there is none and when it cannot be shown, the slot
/// holds a soft panel with the merchant's mark and what the offer gives.
class OfferPicture extends StatelessWidget {
  final Offer offer;
  final double aspectRatio;

  /// On a coupon that is over: drawn faded.
  final bool muted;

  const OfferPicture(this.offer, {super.key, this.aspectRatio = 16 / 9, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final url = offer.imageUrl;
    final panel = _PicturePanel(offer, muted: muted);
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: url == null
          ? panel
          : LayoutBuilder(
              builder: (context, box) {
                // Decoded at the size it is drawn at (to the next 100 pixels,
                // so a few sizes are kept, not one per card).
                final pixels = box.maxWidth * MediaQuery.devicePixelRatioOf(context);
                final width = math.max(100, (pixels / 100).ceil() * 100);
                final picture = Image(
                  key: const Key('offer-picture'),
                  image: ResizeImage(companyLogoImage(url), width: width),
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                  // The panel until the first frame is there, then the picture over it.
                  frameBuilder: (context, child, frame, immediate) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!immediate) panel,
                      AnimatedOpacity(
                        opacity: frame == null ? 0 : (muted ? .45 : 1),
                        duration: immediate ? Duration.zero : BasakMotion.fade,
                        curve: BasakMotion.fadeCurve,
                        child: child,
                      ),
                    ],
                  ),
                  errorBuilder: (context, error, stack) => panel,
                );
                return muted ? ColoredBox(color: context.colors.sunken, child: picture) : picture;
              },
            ),
    );
  }
}

/// What stands in for a picture: the merchant's mark over the offer's value.
class _PicturePanel extends StatelessWidget {
  final Offer offer;
  final bool muted;

  const _PicturePanel(this.offer, {required this.muted});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        key: const Key('offer-picture-panel'),
        color: muted ? colors.sunken : colors.avatarTint,
        alignment: Alignment.center,
        padding: const EdgeInsetsDirectional.all(BasakSpace.s12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Opacity(
            opacity: muted ? .55 : 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OfferLogo(offer.merchant, size: 44, onTint: true),
                if (offer.valueLabel.isNotEmpty) ...[
                  const SizedBox(height: BasakSpace.s8),
                  Text(
                    offer.valueLabel,
                    maxLines: 1,
                    style: context.text.headline.copyWith(color: muted ? colors.ink3 : colors.teal),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a card says under an offer: «خاص لك», «استخدمته», «متبقٍ 12» and when
/// it ends. [compact] keeps the two that matter most (the strip on Home).
class OfferMarks extends StatelessWidget {
  final Offer offer;
  final DateTime now;
  final bool compact;

  const OfferMarks(this.offer, {super.key, required this.now, this.compact = false});

  static bool has(Offer offer, DateTime now) =>
      offer.special || offer.usedUp || offer.soldOut || offer.leftLabel != null || offer.endsLabel(now) != null;

  @override
  Widget build(BuildContext context) {
    final ends = offer.endsLabel(now);
    final left = offer.leftLabel;
    final marks = <Widget>[
      if (offer.special) const BasakTag('خاص لك', tone: BasakTone.info),
      if (offer.usedUp)
        const BasakTag('استخدمته', tone: BasakTone.success)
      else if (offer.soldOut)
        const BasakTag('انتهت الكمية')
      else if (left != null)
        BasakTag(left, tone: BasakTone.warning),
      if (ends != null)
        IconPill(
          icon: LucideIcons.clock3,
          label: ends,
          tone: ends == 'ينتهي اليوم' ? BasakTone.warning : BasakTone.neutral,
        ),
    ];
    return Wrap(
      spacing: BasakSpace.s6,
      runSpacing: BasakSpace.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: compact ? marks.take(2).toList() : marks,
    );
  }
}

/// An offer in the list of all offers: its picture, who it is from, what it
/// gives and what there is to know before opening it.
class MerchantOfferCard extends StatelessWidget {
  final Offer offer;
  final DateTime now;
  final VoidCallback? onTap;

  const MerchantOfferCard({super.key, required this.offer, required this.now, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final merchant = offer.merchant;
    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        padding: EdgeInsets.zero,
        // The picture is the card's top: cut to its corners.
        child: ClipRRect(
          borderRadius: BasakRadius.all(BasakRadius.card),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OfferPicture(offer),
              Padding(
                padding: const EdgeInsetsDirectional.all(BasakSpace.card),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        OfferLogo(merchant, size: 44),
                        const SizedBox(width: BasakSpace.s12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (merchant.name.isNotEmpty)
                                Text(merchant.name,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.rowTitle),
                              Text(merchant.category.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.caption.copyWith(color: colors.ink3)),
                            ],
                          ),
                        ),
                        const SizedBox(width: BasakSpace.s8),
                        Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
                      ],
                    ),
                    const SizedBox(height: BasakSpace.s12),
                    if (offer.valueLabel.isNotEmpty)
                      Text(offer.valueLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: text.title.copyWith(color: colors.teal)),
                    Text(offer.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.body.copyWith(fontWeight: FontWeight.w500)),
                    if (OfferMarks.has(offer, now)) ...[
                      const SizedBox(height: BasakSpace.s10),
                      OfferMarks(offer, now: now),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The offers whose card is on screen right now: more than half of it, across
/// and down. [cards] are the keys of the cards that are built.
List<String> offersOnScreen(BuildContext context, Map<String, GlobalKey> cards) {
  final screen = Offset.zero & MediaQuery.sizeOf(context);
  final seen = <String>[];
  for (final card in cards.entries) {
    final box = card.value.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final visible = rect.intersect(screen);
    if (visible.width * 2 >= rect.width && visible.height * 2 >= rect.height) seen.add(card.key);
  }
  return seen;
}
