import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../selection/supervisor_selection.dart';

/// The supervisor's lines as single-choice rows. The choice is kept in
/// [supervisorSelectionProvider], so it applies to Home, Trips, the scanner
/// and the messages alike. Opened from Home's line row (and from the account
/// page's lines row).
class SupervisorLineSheet extends ConsumerStatefulWidget {
  const SupervisorLineSheet({super.key});

  static Future<void> show(BuildContext context) =>
      BasakSheet.showFrame<void>(context, builder: (_) => const SupervisorLineSheet());

  /// "جامعة المنصورة الجديدة · 124 مشتركاً".
  static String caption(SupervisorLine line) => [
        if (line.destination != null) line.destination!,
        ArabicCount.subscribers(line.registeredStudents),
      ].join(' · ');

  @override
  ConsumerState<SupervisorLineSheet> createState() => _SupervisorLineSheetState();
}

class _SupervisorLineSheetState extends ConsumerState<SupervisorLineSheet> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(supervisorDashboardProvider).valueOrNull?.lines ?? const <SupervisorLine>[];
    final selected = ref.watch(supervisorSelectionProvider).lineId;
    // With nothing chosen yet, the first line is the one on screen.
    final current = lines.any((l) => l.id == selected) ? selected : (lines.isEmpty ? null : lines.first.id);
    final chosen = lines.any((l) => l.id == _chosen) ? _chosen : current;

    return BasakSheetFrame(
      title: 'الخط',
      subtitle: 'يُطبَّق اختيارك على الرحلات والمسح والإشعارات.',
      largeTitle: true,
      primary: BasakButton(
        key: const Key('line-confirm'),
        label: 'تأكيد',
        onPressed: chosen == null
            ? null
            : () {
                // The same line keeps its chosen trip.
                if (chosen != current) ref.read(supervisorSelectionProvider.notifier).selectLine(chosen);
                Navigator.of(context).pop();
              },
      ),
      child: Semantics(
        container: true,
        label: 'الخطوط المسندة إليك',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, line) in lines.indexed) ...[
              if (i > 0) const SizedBox(height: BasakSpace.s8),
              RadioCard(
                key: Key('line-${line.id}'),
                title: line.name,
                subtitle: SupervisorLineSheet.caption(line),
                selected: line.id == chosen,
                tag: line.isActive ? null : const BasakTag('متوقف'),
                onTap: () => setState(() => _chosen = line.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
