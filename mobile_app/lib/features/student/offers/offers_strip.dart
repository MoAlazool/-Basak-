import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui.dart';
import 'offer_details_screen.dart';
import 'offer_widgets.dart';
import 'offers_repository.dart';
import 'offers_screen.dart';

/// «عروض لك» on Home: a few offers side by side, the special ones first, and
/// the way to all of them. Home builds it only when there is an offer to show.
class OffersStrip extends ConsumerStatefulWidget {
  final List<Offer> offers;

  const OffersStrip({super.key, required this.offers});

  /// How many offers Home shows; the rest are behind «كل العروض».
  static const maxCards = 5;

  /// The offers of the strip: the special ones first, each group in the
  /// server's order.
  static List<Offer> shownOf(List<Offer> offers) => [
        ...offers.where((offer) => offer.special),
        ...offers.where((offer) => !offer.special),
      ].take(maxCards).toList();

  @override
  ConsumerState<OffersStrip> createState() => _OffersStripState();
}

class _OffersStripState extends ConsumerState<OffersStrip> {
  final Map<String, GlobalKey> _cards = {};
  ScrollPosition? _page;

  /// Whether Home is the tab in front (the others stay built behind it).
  bool _inFront = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inFront = Visibility.of(context);
    // The page scrolling brings the strip into view, or takes it away.
    final page = Scrollable.maybeOf(context)?.position;
    if (page != _page) {
      _page?.removeListener(_look);
      _page = page?..addListener(_look);
    }
  }

  @override
  void dispose() {
    _page?.removeListener(_look);
    super.dispose();
  }

  /// Tells the server which cards the student has in front of them.
  void _look() {
    if (!mounted || !_inFront) return;
    ref.read(offersRepoProvider).seen(offersOnScreen(context, _cards));
  }

  @override
  Widget build(BuildContext context) {
    final shown = OffersStrip.shownOf(widget.offers);
    final now = ref.watch(offersClockProvider)();
    _cards.removeWhere((id, _) => shown.every((offer) => offer.id != id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _look());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('عروض لك', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headline),
              ),
            ),
            const SizedBox(width: BasakSpace.s8),
            TextAction(
              key: const Key('offers-all'),
              label: 'كل العروض',
              onTap: () => OffersScreen.open(context),
            ),
          ],
        ),
        const SizedBox(height: BasakSpace.s4),
        LayoutBuilder(
          builder: (context, constraints) {
            // One offer takes the row; more leave the next one peeking in.
            final width =
                shown.length == 1 ? constraints.maxWidth : math.min(232.0, constraints.maxWidth * .74);
            // Scrolling sideways is the strip's own: the page and the tab bar
            // above it hear nothing of it.
            return NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _look();
                return true;
              },
              child: SingleChildScrollView(
                key: const Key('offers-strip-scroll'),
                scrollDirection: Axis.horizontal,
                // The cards slide under the page's gutter, to the screen's edge.
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const SizedBox(width: BasakSpace.s12),
                        SizedBox(
                          width: width,
                          child: _StripCard(
                            key: _cards.putIfAbsent(shown[i].id, GlobalKey.new),
                            offer: shown[i],
                            now: now,
                            onTap: () => OfferDetailsScreen.open(context, shown[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// One offer of the strip: the merchant, what it gives, and one line of marks.
class _StripCard extends StatelessWidget {
  final Offer offer;
  final DateTime now;
  final VoidCallback onTap;

  const _StripCard({super.key, required this.offer, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final merchant = offer.merchant;
    return BasakPressable(
      onTap: onTap,
      child: BasakCard(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OfferLogo(merchant, size: 36),
                const SizedBox(width: BasakSpace.s8),
                Expanded(
                  child: Text(
                    merchant.name.isEmpty ? merchant.category.label : merchant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.label.copyWith(color: colors.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BasakSpace.s10),
            if (offer.valueLabel.isNotEmpty)
              Text(offer.valueLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headline.copyWith(color: colors.teal)),
            Text(offer.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            if (OfferMarks.has(offer, now)) ...[
              // The marks sit on the card's last line, whatever its neighbours' height.
              const Spacer(),
              const SizedBox(height: BasakSpace.s10),
              OfferMarks(offer, now: now, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}
