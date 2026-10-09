import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_service.dart';
import '../../../core/sync/own_changes.dart';
import '../../../core/sync/session.dart';
import '../qr/presentation/student_qr_screen.dart';
import '../subscription/presentation/purchase_flow.dart';
import '../../../core/theme/app_colors.dart';
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

/// The invitations waiting for this student's answer.
class MyInvitesNotifier extends AsyncNotifier<List<CompanyInvite>> {
  @override
  Future<List<CompanyInvite>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    final response = await SupabaseService.client.rpc('get_my_invites');
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

/// Shown on the home screen while an invitation is waiting for an answer.
class InvitesCard extends ConsumerStatefulWidget {
  const InvitesCard({super.key});

  @override
  ConsumerState<InvitesCard> createState() => _InvitesCardState();
}

class _InvitesCardState extends ConsumerState<InvitesCard> {
  String? _busyId;

  Future<void> _respond(CompanyInvite invite, bool accept) async {
    if (accept) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('الانضمام إلى ${invite.companyName}؟'),
          content: Text(
              'ستتمكن إدارة ${invite.companyName} من رؤية اسمك ورقم هاتفك وجامعتك وصورتك، '
              'ويُفتح لك ${invite.typeLabel} على خط ${invite.lineName} بانتظار الدفع.\n\n'
              'لا يتغير حسابك ولا اشتراكاتك لدى أي شركة أخرى.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ليس الآن')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('موافق، انضم')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busyId = invite.id);
    // What the server will announce back to this phone about its own answer.
    final echoes = [
      OwnChanges.begin('company_invites', id: invite.id),
      if (accept) OwnChanges.begin('company_students'),
      if (accept) OwnChanges.begin('subscriptions', op: 'INSERT'),
    ];
    try {
      final result = await SupabaseService.client.rpc('respond_company_invite',
          params: {'p_invite_id': invite.id, 'p_accept': accept});
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!accept
            ? 'تم رفض الدعوة.'
            : note == null
                ? 'انضممت إلى ${invite.companyName}. أكمل الدفع من صفحة الاشتراك.'
                : 'انضممت إلى ${invite.companyName}. لم يُفتح الاشتراك تلقائياً: $note'),
      ));
    } catch (error) {
      for (final echo in echoes) {
        echo.failed();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString()), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(myInvitesProvider).valueOrNull ?? const [];
    if (invites.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final invite in invites)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFBFE3F3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('دعوة من ${invite.companyName}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF17384A))),
                const SizedBox(height: 6),
                Text(
                    '${invite.typeLabel} • خط ${invite.lineName} • محطة ${invite.stationName}'
                    '${invite.price == null ? '' : ' • ${invite.price} ج.م'}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF718695))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busyId == null ? () => _respond(invite, true) : null,
                        child: Text(_busyId == invite.id ? 'لحظة…' : 'قبول'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busyId == null ? () => _respond(invite, false) : null,
                        child: const Text('رفض'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
