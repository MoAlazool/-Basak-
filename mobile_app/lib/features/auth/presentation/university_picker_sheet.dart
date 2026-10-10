import 'package:flutter/material.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/ui/ui.dart';

/// The sheet a student picks their university from.
///
/// Search forgives the usual Arabic spelling differences (ه/ة, أ/إ/آ/ا, ى/ي,
/// diacritics), so "جامعه المنصوره" finds "جامعة المنصورة"; it reads the city
/// too.
class UniversityPickerSheet extends StatefulWidget {
  /// Each: `id`, `name` and, when the university has one, `city`.
  final List<Map<String, String>> universities;
  final String? selectedId;

  const UniversityPickerSheet({super.key, required this.universities, this.selectedId});

  /// Returns the chosen university id, or null when the sheet is dismissed.
  static Future<String?> show(BuildContext context,
          {required List<Map<String, String>> universities, String? selectedId}) =>
      BasakSheet.showFrame<String>(
        context,
        builder: (_) => UniversityPickerSheet(universities: universities, selectedId: selectedId),
      );

  /// Folds the letter variants people type interchangeably.
  static String normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');

  @override
  State<UniversityPickerSheet> createState() => _UniversityPickerSheetState();
}

class _UniversityPickerSheetState extends State<UniversityPickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  late String? _picked = widget.selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = UniversityPickerSheet.normalize(_query);
    final matches = widget.universities
        .where((u) => UniversityPickerSheet.normalize('${u['name'] ?? ''} ${u['city'] ?? ''}').contains(needle))
        .toList();
    final none = widget.universities.isEmpty;

    return BasakSheetFrame(
      title: 'جامعتك',
      largeTitle: true,
      header: none
          ? null
          : BasakSearchField(
              controller: _search,
              hint: 'ابحث باسم الجامعة أو المدينة',
              onChanged: (value) => setState(() => _query = value),
            ),
      primary: none
          ? null
          : BasakButton(
              key: const Key('university-confirm'),
              label: 'تأكيد',
              onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
            ),
      child: matches.isEmpty
          ? EmptyState(
              icon: LucideIcons.school,
              title: none ? 'لا توجد جامعات متاحة حالياً.' : 'لا توجد جامعة بهذا الاسم.',
            )
          : Semantics(
              container: true,
              label: 'الجامعات',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < matches.length; i++) ...[
                    if (i > 0) const SizedBox(height: BasakSpace.s4),
                    SheetRadioRow(
                      title: matches[i]['name'] ?? '',
                      subtitle: matches[i]['city'],
                      selected: matches[i]['id'] == _picked,
                      onTap: () => setState(() => _picked = matches[i]['id']),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
