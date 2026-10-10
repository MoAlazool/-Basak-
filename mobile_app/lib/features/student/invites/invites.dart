import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/sync/own_changes.dart';
import '../../../core/sync/session.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../qr/presentation/student_qr_screen.dart';
import '../subscription/presentation/purchase_flow.dart';
import '../home/presentation/student_home_screen.dart';
import '../subscription/presentation/subscription_screen.dart';

/// A transport company asking this student to join it. The company sees nothing
/// of the account until the student accepts.
class CompanyInvite {
  final String id;
  final String companyName;
  final String lineName;
  final String stationName;
  final String subscriptionType;
  final num? price;

  const CompanyInvite({
    required this.id,
    required this.companyName,
    required this.lineName,
    required this.stationName,
    required this.subscriptionType,
    this.price,
  });

  factory CompanyInvite.fromJson(Map<String, dynamic> json) => CompanyInvite(
        id: json['id'] as String,
        companyName: json['company_name'] as String? ?? '',
        lineName: json['line_name'] as String? ?? '',
        stationName: json['station_name'] as String? ?? '',
        subscriptionType: json['subscription_type'] as String? ?? 'termly',
        price: json['price'] as num?,
      );

  String get typeLabel => switch (subscriptionType) {
        'yearly' => 'اشتراك سنوي',
        'daily' => 'اشتراك يومي',
        _ => 'اشتراك فصلي',
      };
}

/// The two requests behind the invitations (replaced in tests).
class InvitesGateway {
  const InvitesGateway();

  Future<dynamic> myInvites() => SupabaseService.client.rpc('get_my_invites');

  Future<dynamic> respond(String inviteId, bool accept) => SupabaseService.client
      .rpc('respond_company_invite', params: {'p_invite_id': inviteId, 'p_accept': accept});
}

final invitesGatewayProvider = Provider((ref) => const InvitesGateway());

/// The invitations waiting for this student's answer.
class MyInvitesNotifier extends AsyncNotifier<List<CompanyInvite>> {
  @override
  Future<List<CompanyInvite>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    final response = await ref.watch(invitesGatewayProvider).myInvites();
    return (response as List<dynamic>? ?? const [])
        .map((e) => CompanyInvite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// The student answered [inviteId] on this phone: it is gone from the list
  /// at once, without asking the server for the list again.
  void applyAnswered(String inviteId) {
    final invites = state.valueOrNull;
    if (invites != null) state = AsyncData([for (final i in invites) if (i.id != inviteId) i]);
  }
}

final myInvitesProvider =
    AsyncNotifierProvider<MyInvitesNotifier, List<CompanyInvite>>(MyInvitesNotifier.new);

/// Shown on the home screen while an invitation is waiting for an answer:
/// one card at a time, with "1 من 2" and a swipe to the next when there are
/// several.
class InvitesCard extends ConsumerStatefulWidget {
  const InvitesCard({super.key});

  @override
  ConsumerState<InvitesCard> createState() => _InvitesCardState();
}

class _InvitesCardState extends ConsumerState<InvitesCard> {
  String? _busyId;
  int _index = 0;

  Future<void> _respond(CompanyInvite invite, bool accept) async {
    // One answer at a time, however fast the buttons are tapped.
    if (_busyId != null) return;
    if (accept) {
      final confirmed = await InviteAcceptSheet.show(context, invite);
      if (confirmed != true || !mounted || _busyId != null) return;
    }
    setState(() => _busyId = invite.id);
    // What the server will announce back to this phone about its own answer.
    final echoes = [
      OwnChanges.begin('company_invites', id: invite.id),
      if (accept) OwnChanges.begin('company_students'),
      if (accept) OwnChanges.begin('subscriptions', op: 'INSERT'),
    ];
    try {
      final result = await ref.read(invitesGatewayProvider).respond(invite.id, accept);
      for (final echo in echoes) {
        echo.done();
      }
      ref.read(myInvitesProvider.notifier).applyAnswered(invite.id);
      if (accept) {
        // Joining opens a subscription on the server (it is not in the
        // answer): read once, here, not again when the announcement arrives.
        ref.invalidate(currentSubscriptionProvider);
        ref.invalidate(allSubscriptionsProvider);
        ref.invalidate(saleCatalogProvider);
        ref.invalidate(studentQrProvider);
      }
      if (!mounted) return;
      final note = (result is Map ? result['note'] : null) as String?;
      BasakToast.show(
        context,
        !accept
            ? 'تم رفض الدعوة.'
            : note == null
                ? 'انضممت إلى ${invite.companyName}. أكمل الدفع من صفحة الاشتراك.'
                : 'انضممت إلى ${invite.companyName}. لم يُفتح الاشتراك تلقائياً: $note',
        kind: accept && note != null ? BasakToastKind.info : BasakToastKind.success,
      );
    } catch (error) {
      for (final echo in echoes) {
        echo.failed();
      }
      if (!mounted) return;
      BasakToast.show(context, errorMessage(error), kind: BasakToastKind.failure);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _turn(int by, int count) {
    final next = (_index + by).clamp(0, count - 1);
    if (next != _index) setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(myInvitesProvider).valueOrNull ?? const [];
    if (invites.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, invites.length - 1);
    final invite = invites[index];
    final rtl = Directionality.of(context) == TextDirection.rtl;

    final card = InviteCard(
      key: ValueKey(invite.id),
      invite: invite,
      position: invites.length > 1 ? (index: index, count: invites.length) : null,
      busy: _busyId == invite.id,
      onAccept: _busyId == null ? () => _respond(invite, true) : null,
      onDecline: _busyId == null ? () => _respond(invite, false) : null,
    );
    if (invites.length == 1) return card;
    return GestureDetector(
      // The next invitation lies towards the end side, as pages do.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 120) return;
        _turn((velocity > 0) == rtl ? 1 : -1, invites.length);
      },
      child: AnimatedSwitcher(duration: BasakMotion.fade, switchInCurve: BasakMotion.fadeCurve, child: card),
    );
  }
}

/// One invitation: who asks, for what, at what price, and the two answers.
class InviteCard extends StatelessWidget {
  final CompanyInvite invite;

  /// With several invitations: which one this is.
  final ({int index, int count})? position;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const InviteCard({
    super.key,
    required this.invite,
    this.position,
    this.busy = false,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final company = invite.companyName.trim();
    // The letter that tells companies apart: not the article ("النورس" → ن).
    final initial = company.replaceFirst(RegExp('^ال'), '');
    final where = [invite.lineName.trim(), invite.stationName.trim()].where((part) => part.isNotEmpty).join(' · ');
    final price = invite.price;
    final quiet = text.label.copyWith(fontWeight: FontWeight.w400);

    return Semantics(
      container: true,
      label: 'دعوة من شركة النقل',
      child: BasakCard(
        radius: BasakRadius.sheet,
        padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: colors.avatarTint, borderRadius: BasakRadius.all(BasakRadius.small)),
                    child: Text(
                      initial.isEmpty ? '' : initial.characters.first,
                      textScaler: TextScaler.noScaling,
                      style: text.headline.copyWith(color: colors.teal),
                    ),
                  ),
                ),
                const SizedBox(width: BasakSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('دعوة للاشتراك من', style: quiet.copyWith(color: colors.ink3)),
                      Text(company, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headline),
                    ],
                  ),
                ),
                if (position != null) ...[
                  const SizedBox(width: BasakSpace.s8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${position!.index + 1} من ${position!.count}',
                          style: text.caption.copyWith(color: colors.ink3)),
                      const SizedBox(width: BasakSpace.s2),
                      for (var i = 0; i < position!.count; i++)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsetsDirectional.only(start: BasakSpace.s4),
                          decoration: BoxDecoration(
                              color: i == position!.index ? colors.teal : colors.grabber, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: BasakSpace.s16),
            Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14, vertical: BasakSpace.s12),
              decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (where.isNotEmpty)
                          Text(where,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.body.copyWith(fontWeight: FontWeight.w500)),
                        Text(invite.typeLabel, style: quiet.copyWith(color: colors.ink2)),
                      ],
                    ),
                  ),
                  if (price != null) ...[
                    const SizedBox(width: BasakSpace.s12),
                    MoneyText(formatMoney(price.toDouble()), style: text.headline, unitSize: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(height: BasakSpace.s16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: BasakButton(
                    key: const Key('invite-accept'),
                    label: 'قبول الدعوة',
                    size: BasakButtonSize.medium,
                    loading: busy,
                    onPressed: onAccept,
                  ),
                ),
                const SizedBox(width: BasakSpace.s10),
                Expanded(
                  flex: 2,
                  child: BasakButton(
                    key: const Key('invite-decline'),
                    label: 'رفض',
                    size: BasakButtonSize.medium,
                    variant: BasakButtonVariant.secondary,
                    onPressed: onDecline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Before joining: exactly what the company will see and what is opened.
/// Gives back true when the student agrees.
abstract final class InviteAcceptSheet {
  static Future<bool?> show(BuildContext context, CompanyInvite invite) {
    final line = invite.lineName.trim();
    final onLine = line.isEmpty ? '' : ' على ${line.startsWith('خط ') ? line : 'خط $line'}';
    return BasakSheet.show<bool>(
      context,
      title: 'الانضمام إلى ${invite.companyName}؟',
      largeTitle: true,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: BasakSpace.s6),
          const SheetPoint(icon: LucideIcons.userRound, text: 'ترى الشركة اسمك وهاتفك وجامعتك وصورتك.'),
          const SizedBox(height: BasakSpace.s16),
          SheetPoint(icon: LucideIcons.ticket, text: 'يُفتح لك ${invite.typeLabel}$onLine بانتظار الدفع.'),
          const SizedBox(height: BasakSpace.s16),
          const SheetPoint(icon: LucideIcons.shieldCheck, text: 'لا يتغيّر حسابك ولا اشتراكاتك لدى شركات أخرى.'),
          const SizedBox(height: BasakSpace.s6),
        ],
      ),
      primary: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BasakButton(
            key: const Key('invite-join'),
            label: 'موافق، انضم',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BasakSpace.s2),
          SheetLink(label: 'ليس الآن', onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}
