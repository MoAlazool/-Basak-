import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import 'offers_repository.dart';

/// The merchant's logo, or the first letters of its name.
class OfferLogo extends StatelessWidget {
  final OfferMerchant merchant;
  final double size;

  const OfferLogo(this.merchant, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final url = merchant.logoUrl;
    return CompanyLogo.image(
      name: merchant.name,
      image: url == null ? null : companyLogoImage(url),
      size: size,
      radius: BasakRadius.tile,
      placeholder: merchant.name.isEmpty ? ToneTile(LucideIcons.tag, tone: BasakTone.info, size: size) : null,
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

/// An offer in the list of all offers: who it is from, what it gives and
/// what there is to know before opening it.
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
                        Text(merchant.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.rowTitle),
                      Text(merchant.category.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption.copyWith(color: colors.ink3)),
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
                maxLines: 2, overflow: TextOverflow.ellipsis, style: text.body.copyWith(fontWeight: FontWeight.w500)),
            if (OfferMarks.has(offer, now)) ...[
              const SizedBox(height: BasakSpace.s10),
              OfferMarks(offer, now: now),
            ],
          ],
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
