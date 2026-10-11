import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../../../core/widgets/basak_ui.dart';
import '../home/presentation/supervisor_contact_sheet.dart';
import 'offer_coupon_screen.dart';
import 'offer_widgets.dart';
import 'offers_repository.dart';

/// One offer in full: its picture, who it is from, what it says and asks,
/// how long it runs, how to reach the merchant, and «استخدم العرض».
class OfferDetailsScreen extends ConsumerStatefulWidget {
  final Offer offer;

  const OfferDetailsScreen({super.key, required this.offer});

  /// Opens [offer]. With a coupon still running the student is at the till:
  /// that coupon is put straight back in front of them.
  static Future<void> open(BuildContext context, Offer offer) {
    final navigator = Navigator.of(context);
    final now = ProviderScope.containerOf(context, listen: false).read(offersClockProvider)();
    final closed = navigator.push(MaterialPageRoute<void>(builder: (_) => OfferDetailsScreen(offer: offer)));
    final coupon = offer.runningCoupon(now);
    if (coupon != null) unawaited(navigator.push(OfferCouponScreen.route(offer, coupon)));
    return closed;
  }

  /// «اضغط فقط وأنت عند الكاشير»: asked before a coupon's minutes start.
  static String confirmMessage(Offer offer) =>
      'اضغط فقط وأنت عند الكاشير — الكوبون صالح ${ArabicCount.minutes(offer.couponMinutes)}.';

  @override
  ConsumerState<OfferDetailsScreen> createState() => _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends ConsumerState<OfferDetailsScreen> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    ref.read(offersRepoProvider).opened(widget.offer.id);
  }

  /// The offer as the server has it now (used a moment ago, a coupon running),
  /// else as it was when the page opened.
  Offer get _offer => ref.read(offersProvider).valueOrNull?.find(widget.offer.id) ?? widget.offer;

  Future<void> _use() async {
    if (_asking) return;
    final offer = _offer;
    final running = offer.runningCoupon(ref.read(offersClockProvider)());
    if (running != null) {
      await Navigator.of(context).push(OfferCouponScreen.route(offer, running));
      return;
    }
    final sure = await BasakDialog.confirm(
      context,
      icon: LucideIcons.ticket,
      title: 'استخدام العرض الآن؟',
      message: OfferDetailsScreen.confirmMessage(offer),
      confirmLabel: 'استخدم العرض',
      tone: BasakTone.info,
    );
    if (!sure || !mounted) return;
    setState(() => _asking = true);
    try {
      final coupon = await ref.read(offersRepoProvider).redeem(offer.id);
      if (!mounted) return;
      // The offer now has a coupon, and without a PIN a use.
      ref.invalidate(offersProvider);
      setState(() => _asking = false);
      await Navigator.of(context).push(OfferCouponScreen.route(offer, coupon));
    } catch (error) {
      if (!mounted) return;
      setState(() => _asking = false);
      // Refused: what the offer says of itself may be out of date.
      ref.invalidate(offersProvider);
      BasakToast.show(context, errorMessage(error), kind: BasakToastKind.failure);
    }
  }

  Future<void> _launch(Uri uri, String failure) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) BasakToast.show(context, failure, kind: BasakToastKind.failure);
    } catch (_) {
      if (mounted) BasakToast.show(context, failure, kind: BasakToastKind.failure);
    }
  }

  /// Only the ways the merchant gave.
  List<SettingRow> _contact(OfferMerchant merchant) {
    final link = merchant.link;
    return [
      if (merchant.whatsapp != null)
        SettingRow(
          key: const Key('offer-whatsapp'),
          label: 'واتساب',
          value: SupervisorContactSheet.readable(merchant.whatsapp!),
          ltrValue: true,
          external: true,
          onTap: () => SupervisorContactSheet.whatsapp(context, merchant.whatsapp!),
        ),
      if (merchant.phone != null)
        SettingRow(
          key: const Key('offer-call'),
          label: 'اتصال',
          value: SupervisorContactSheet.readable(merchant.phone!),
          ltrValue: true,
          external: true,
          onTap: () => SupervisorContactSheet.call(context, merchant.phone!),
        ),
      if (link != null)
        SettingRow(
          key: const Key('offer-link'),
          label: 'الموقع',
          value: link.host.replaceFirst(RegExp(r'^www\.'), ''),
          ltrValue: true,
          external: true,
          onTap: () => _launch(link, 'تعذر فتح الرابط على هذا الجهاز.'),
        ),
      if (merchant.address != null)
        SettingRow(
          key: const Key('offer-address'),
          label: 'العنوان',
          value: merchant.address,
          external: true,
          onTap: () => _launch(
              Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': merchant.address!}),
              'تعذر فتح الخريطة على هذا الجهاز.'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final offer = ref.watch(offersProvider).valueOrNull?.find(widget.offer.id) ?? widget.offer;
    final now = ref.watch(offersClockProvider)();
    final merchant = offer.merchant;
    final running = offer.runningCoupon(now);
    final refusal = running == null ? offer.refusal : null;
    final end = offer.endsAt;
    final contact = _contact(merchant);

    final facts = <(String, String)>[
      if (end != null) ('ينتهي', '${end.day} ${BasakUi.arabicMonths[end.month - 1]}'),
      if (!offer.isInfo && offer.left != null) ('المتبقي', offer.soldOut ? 'انتهت الكمية' : '${offer.left}'),
      if (!offer.isInfo && offer.perStudentLimit > 1) ('استخدمته', '${offer.used} من ${offer.perStudentLimit}'),
    ];

    return Scaffold(
      backgroundColor: colors.ground,
      body: BasakPage(
        header: const PageTitleBar(title: 'تفاصيل العرض'),
        dock: offer.isInfo
            ? null
            : BasakDock(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (refusal != null) ...[
                      Text(refusal,
                          key: const Key('offer-refusal'),
                          textAlign: TextAlign.center,
                          style: text.label.copyWith(color: colors.ink2)),
                      const SizedBox(height: BasakSpace.s10),
                    ],
                    BasakButton(
                      key: const Key('offer-use'),
                      label: running != null ? 'عرض الكوبون' : 'استخدم العرض',
                      icon: LucideIcons.ticket,
                      loading: _asking,
                      onPressed: refusal == null ? _use : null,
                    ),
                  ],
                ),
              ),
        children: [
          // The picture leads the page; without one its place holds the merchant's mark.
          ClipRRect(
            borderRadius: BasakRadius.all(BasakRadius.card),
            child: OfferPicture(offer),
          ),
          BasakCard(
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
                            Text(merchant.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.rowTitle),
                          Text(merchant.category.label, style: text.caption.copyWith(color: colors.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BasakSpace.s14),
                if (offer.valueLabel.isNotEmpty)
                  Text(offer.valueLabel, style: text.title.copyWith(color: colors.teal)),
                Semantics(header: true, child: Text(offer.title, style: text.headline)),
                if (offer.description.isNotEmpty) ...[
                  const SizedBox(height: BasakSpace.s8),
                  Text(offer.description, style: text.body.copyWith(color: colors.ink2)),
                ],
                if (OfferMarks.has(offer, now)) ...[
                  const SizedBox(height: BasakSpace.s12),
                  OfferMarks(offer, now: now),
                ],
              ],
            ),
          ),
          if (facts.isNotEmpty) BasakCard(child: FactGrid(facts: facts)),
          if (offer.terms.isNotEmpty)
            GroupSection(
              title: 'الشروط',
              child: BasakCard(
                child: SizedBox(
                  width: double.infinity,
                  child: Text(offer.terms, style: text.bodySmall.copyWith(color: colors.ink2)),
                ),
              ),
            ),
          if (contact.isNotEmpty) GroupSection(title: 'تواصل مع المحل', child: SettingRows(rows: contact)),
        ],
      ),
    );
  }
}
