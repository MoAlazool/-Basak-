import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../home/presentation/student_home_screen.dart';
import '../../home/presentation/supervisor_contact_sheet.dart';

/// One way to get help: who or what it is, a line about it, and what a tap
/// does. The sheet knows nothing else about its entries: no channel (a phone
/// number, WhatsApp, a page of questions) is written into the app.
class HelpEntry {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Run with the page under the sheet, after the sheet has closed.
  final void Function(BuildContext page) action;

  /// A person rather than a channel: drawn as the first letter of [title] in
  /// a circle instead of [icon] in a tile.
  final bool person;

  const HelpEntry({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.action,
    this.person = false,
  });
}

/// «عن رحلتك واشتراكك»: the people the app already knows. Today that is the
/// bus supervisor of the student's line, when the subscription names one.
final helpJourneyProvider = Provider<List<HelpEntry>>((ref) {
  final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
  final phone = sub?.supervisorPhone?.trim() ?? '';
  if (sub == null || phone.isEmpty) return const [];
  final name = (sub.supervisorName ?? '').trim().isEmpty ? 'مشرف الباص' : sub.supervisorName!.trim();
  return [
    HelpEntry(
      icon: LucideIcons.userRound,
      person: true,
      title: name,
      subtitle: SupervisorContactSheet.roleLabel(sub.lineName),
      action: (page) => SupervisorContactSheet.show(page, name: name, phone: phone, lineName: sub.lineName),
    ),
  ];
});

/// «دعم التطبيق»: the app's own support channels. None are decided yet, so
/// the list is empty and its group is not shown; whoever owns the channels
/// overrides this provider (or fills it from configuration).
final helpSupportProvider = Provider<List<HelpEntry>>((ref) => const []);

/// Help & support: two groups of [HelpEntry]s, each hidden while it is empty.
class HelpSheet extends StatelessWidget {
  final List<HelpEntry> journey;
  final List<HelpEntry> support;

  const HelpSheet({super.key, required this.journey, this.support = const []});

  static const title = 'المساعدة والدعم';

  static Future<void> show(BuildContext context,
          {required List<HelpEntry> journey, List<HelpEntry> support = const []}) =>
      BasakSheet.show<void>(
        context,
        title: title,
        largeTitle: true,
        builder: (_) => HelpSheet(journey: journey, support: support),
        primary: (sheet) => SheetLink(label: 'إغلاق', onTap: () => Navigator.of(sheet).pop()),
      );

  Widget _group(BuildContext context, String name, List<HelpEntry> entries) => GroupSection(
        title: name,
        child: LinkRows(rows: [
          for (final entry in entries)
            LinkRow(
              icon: entry.person ? null : entry.icon,
              person: entry.person ? entry.title : null,
              title: entry.title,
              subtitle: entry.subtitle,
              onTap: () {
                // What the entry opens belongs to the page under this sheet.
                final navigator = Navigator.of(context);
                final page = navigator.context;
                navigator.pop();
                entry.action(page);
              },
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (journey.isNotEmpty) _group(context, 'عن رحلتك واشتراكك', journey),
          if (journey.isNotEmpty && support.isNotEmpty) const SizedBox(height: BasakSpace.s18),
          if (support.isNotEmpty) _group(context, 'دعم التطبيق', support),
          const SizedBox(height: BasakSpace.s4),
        ],
      );
}
