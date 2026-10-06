import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_form_styles.dart';

/// Bottom sheet for choosing the student's university.
///
/// Search forgives the usual Arabic spelling differences (ه/ة, أ/إ/آ/ا, ى/ي,
/// diacritics), so "جامعه المنصوره" finds "جامعة المنصورة".
class UniversityPickerSheet extends StatefulWidget {
  final List<Map<String, String>> universities;
  final String? selectedId;

  const UniversityPickerSheet({super.key, required this.universities, this.selectedId});

  /// Returns the chosen university id, or null when the sheet is dismissed.
  static Future<String?> show(BuildContext context,
          {required List<Map<String, String>> universities, String? selectedId}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = UniversityPickerSheet.normalize(_query);
    final matches = widget.universities
        .where((u) => UniversityPickerSheet.normalize(u['name'] ?? '').contains(needle))
        .toList();
    // A short list needs no search box (and no keyboard covering it).
    final searchable = widget.universities.length > 6;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('اختر جامعتك',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AuthStyles.ink)),
                  SizedBox(height: 2),
                  Text('تحدد الخطوط والرحلات المتاحة لك.',
                      style: TextStyle(fontSize: 13, color: AuthStyles.muted)),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close_rounded, color: AuthStyles.muted),
              ),
            ]),
          ),
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                style: AuthStyles.inputStyle,
                onChanged: (value) => setState(() => _query = value),
                decoration: AuthStyles.field(
                  icon: Icons.search_rounded,
                  hint: 'ابحث باسم الجامعة',
                  suffix: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.cancel_rounded, size: 20, color: AuthStyles.muted),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Flexible(
            child: matches.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.search_off_rounded, size: 40, color: Color(0xFFB4C6D1)),
                      const SizedBox(height: 10),
                      Text(
                        widget.universities.isEmpty ? 'لا توجد جامعات متاحة حالياً.' : 'لا توجد جامعة بهذا الاسم.',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AuthStyles.ink),
                      ),
                      const SizedBox(height: 4),
                      const Text('جرّب كلمة أقصر، أو تواصل مع إدارة النقل لإضافة جامعتك.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, height: 1.5, color: AuthStyles.muted)),
                    ]),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: matches.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 60, endIndent: 8, color: Color(0xFFEDF2F5)),
                    itemBuilder: (context, index) {
                      final university = matches[index];
                      final selected = university['id'] == widget.selectedId;
                      return Material(
                        color: selected ? const Color(0xFFEAF5FA) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context, university['id']);
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 60),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              child: Row(children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: selected ? AuthStyles.teal : const Color(0xFFF0F5F8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.school_rounded,
                                      size: 20, color: selected ? Colors.white : AuthStyles.muted),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(university['name'] ?? '',
                                      style: TextStyle(
                                          fontSize: 15.5,
                                          height: 1.35,
                                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                          color: AuthStyles.ink)),
                                ),
                                if (selected) const Icon(Icons.check_circle_rounded, color: AuthStyles.teal),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
