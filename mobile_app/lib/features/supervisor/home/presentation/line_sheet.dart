import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../data/supervisor_repository.dart';
import '../../models/supervisor_models.dart';
import '../../selection/supervisor_selection.dart';

/// The supervisor's lines as single-choice rows, «كل الخطوط» first when there
/// is more than one. The choice is kept in [supervisorSelectionProvider], so
/// it applies to Home, Trips, the scanner and the messages alike. Opened from
/// Home's line row (and from the account page's lines row).
///
/// [pick] instead returns one line for one screen, changing nothing else.
class SupervisorLineSheet extends ConsumerStatefulWidget {
  /// One line, returned: no «كل الخطوط», the app's choice untouched.
  final bool pickOne;
  final String? initial;

  const SupervisorLineSheet({super.key}) : pickOne = false, initial = null;
  const SupervisorLineSheet.one({super.key, this.initial}) : pickOne = true;

  static Future<void> show(BuildContext context) =>
      BasakSheet.showFrame<void>(context, builder: (_) => const SupervisorLineSheet());

  /// One of the lines (its id), or null when the sheet is closed.
  static Future<String?> pick(BuildContext context, {String? initial}) =>
      BasakSheet.showFrame<String>(context, builder: (_) => SupervisorLineSheet.one(initial: initial));

  /// "3 خطوط · 262 مشتركاً".
  static String allCaption(List<SupervisorLine> lines) => [
        ArabicCount.lines(lines.length),
        ArabicCount.subscribers(lines.fold(0, (sum, l) => sum + l.registeredStudents)),
      ].join(' · ');

  /// "124 مشتركاً". No university: a line serves several, and one named
  /// would read as the only one.
  static String caption(SupervisorLine line) => ArabicCount.subscribers(line.registeredStudents);

  @override
  ConsumerState<SupervisorLineSheet> createState() => _SupervisorLineSheetState();
}

class _SupervisorLineSheetState extends ConsumerState<SupervisorLineSheet> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(supervisorDashboardProvider).valueOrNull?.lines ?? const <SupervisorLine>[];
    final withAll = !widget.pickOne && lines.length > 1;
    bool known(String? id) => lines.any((l) => l.id == id) || (withAll && id == SupervisorSelection.allLines);
    final selected = widget.pickOne ? widget.initial : ref.watch(supervisorSelectionProvider).lineId;
    // With nothing chosen yet, the first line is the one on screen.
    final current = known(selected) ? selected : (lines.isEmpty ? null : lines.first.id);
    final chosen = known(_chosen) ? _chosen : current;

    return BasakSheetFrame(
      title: 'الخط',
      subtitle: widget.pickOne ? null : 'يُطبَّق اختيارك على الرحلات والمسح والإشعارات.',
      largeTitle: true,
      primary: BasakButton(
        key: const Key('line-confirm'),
        label: 'تأكيد',
        onPressed: chosen == null
            ? null
            : () {
                if (widget.pickOne) return Navigator.of(context).pop(chosen);
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
            if (withAll) ...[
              RadioCard(
                key: const Key('line-all'),
                title: 'كل الخطوط',
                subtitle: SupervisorLineSheet.allCaption(lines),
                selected: chosen == SupervisorSelection.allLines,
                onTap: () => setState(() => _chosen = SupervisorSelection.allLines),
              ),
              const SizedBox(height: BasakSpace.s8),
            ],
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
