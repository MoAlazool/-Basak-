import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../auth/presentation/university_picker_sheet.dart';
import '../models/sale_catalog.dart';

/// "محافظتك": the student's governorate, picked before the company from a
/// plain list, as the university is picked at sign-up. Under each name, how
/// many companies serve it. Above six it searches (forgiving the usual Arabic
/// spelling differences, as the universities do).
class GovernorateSheet extends StatefulWidget {
  final List<SaleGovernorate> governorates;

  /// The line under each name, by code.
  final Map<String, String> captions;
  final String? selected;

  const GovernorateSheet({super.key, required this.governorates, this.captions = const {}, this.selected});

  /// Returns the chosen code, or null when the sheet is dismissed.
  static Future<String?> show(
    BuildContext context, {
    required List<SaleGovernorate> governorates,
    Map<String, String> captions = const {},
    String? selected,
  }) =>
      BasakSheet.showFrame<String>(
        context,
        builder: (_) => GovernorateSheet(governorates: governorates, captions: captions, selected: selected),
      );

  @override
  State<GovernorateSheet> createState() => _GovernorateSheetState();
}

class _GovernorateSheetState extends State<GovernorateSheet> {
  final _search = TextEditingController();
  String _query = '';
  late String? _picked = widget.selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = UniversityPickerSheet.normalize(_query);
    final matches =
        widget.governorates.where((g) => UniversityPickerSheet.normalize(g.name).contains(needle)).toList();

    return BasakSheetFrame(
      title: 'محافظتك',
      largeTitle: true,
      header: widget.governorates.length > 6
          ? BasakSearchField(
              controller: _search,
              hint: 'ابحث باسم المحافظة',
              onChanged: (value) => setState(() => _query = value),
            )
          : null,
      primary: BasakButton(
        key: const Key('governorate-confirm'),
        label: 'تأكيد',
        onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
      ),
      child: matches.isEmpty
          ? const EmptyState(icon: LucideIcons.mapPin, title: 'لا توجد محافظة بهذا الاسم.')
          : Semantics(
              container: true,
              label: 'المحافظات',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < matches.length; i++) ...[
                    if (i > 0) const SizedBox(height: BasakSpace.s4),
                    SheetRadioRow(
                      key: Key('governorate-${matches[i].code}'),
                      title: matches[i].name,
                      subtitle: widget.captions[matches[i].code],
                      selected: matches[i].code == _picked,
                      onTap: () => setState(() => _picked = matches[i].code),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
