import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../../../core/widgets/skeleton.dart';
import 'offer_details_screen.dart';
import 'offer_widgets.dart';
import 'offers_repository.dart';

/// «عروض باصك»: every offer meant for this student, by the kind of place it
/// is from. Opened from Home's strip and from the notification of a special
/// offer.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OffersScreen()));

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  /// The kind of place shown; null is all of them.
  OfferCategory? _category;
  final Map<String, GlobalKey> _cards = {};

  /// Tells the server which cards the student has in front of them.
  void _look() {
    if (!mounted) return;
    ref.read(offersRepoProvider).seen(offersOnScreen(context, _cards));
  }

  Future<void> _refresh() async {
    ref.invalidate(offersProvider);
    await ref.read(offersProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(offersProvider);
    final state = async.valueOrNull;
    final now = ref.watch(offersClockProvider)();
    final offers = state?.offers ?? const <Offer>[];
    final shown = [
      for (final offer in offers)
        if (_category == null || offer.merchant.category == _category) offer,
    ];
    // The chosen kind stays among the chips even when its last offer has gone.
    final categories = state?.categories ?? const <OfferCategory>[];
    final chips = <OfferCategory?>[
      null,
      for (final category in OfferCategory.values)
        if (categories.contains(category) || category == _category) category,
    ];
    _cards.removeWhere((id, _) => shown.every((offer) => offer.id != id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _look());

    final List<Widget> children;
    if (state == null) {
      children = const [SkeletonList(rows: 4)];
    } else if (state.hidden || offers.isEmpty) {
      children = [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s40),
          child: state.hidden
              ? const EmptyState(
                  key: Key('offers-hidden'),
                  page: true,
                  icon: LucideIcons.eyeOff,
                  title: 'العروض مخفية',
                  message: 'يمكنك إظهارها من «حسابي».',
                )
              : const EmptyState(
                  key: Key('offers-empty'),
                  page: true,
                  icon: LucideIcons.tag,
                  title: 'لا توجد عروض الآن',
                  message: 'ستظهر هنا عروض المحلات القريبة من جامعتك.',
                ),
        ),
      ];
    } else {
      children = [
        if (chips.length > 2)
          BasakChips<OfferCategory?>(
            options: chips,
            value: _category,
            onChanged: (category) => setState(() => _category = category),
            label: (category) => category?.label ?? 'الكل',
          ),
        if (shown.isEmpty)
          EmptyState(
            key: const Key('offers-none-here'),
            icon: LucideIcons.search,
            title: 'لا عروض في هذا القسم الآن',
            actionLabel: 'كل العروض',
            onAction: () => setState(() => _category = null),
          )
        else
          for (final offer in shown)
            MerchantOfferCard(
              key: _cards.putIfAbsent(offer.id, GlobalKey.new),
              offer: offer,
              now: now,
              onTap: () => OfferDetailsScreen.open(context, offer),
            ),
      ];
    }

    return Scaffold(
      backgroundColor: context.colors.ground,
      body: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _look();
          return false;
        },
        child: BasakPage(
          header: const PageTitleBar(title: 'عروض باصك'),
          onRefresh: _refresh,
          children: children,
        ),
      ),
    );
  }
}
