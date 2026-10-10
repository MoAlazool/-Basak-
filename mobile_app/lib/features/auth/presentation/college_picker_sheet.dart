import 'package:flutter/material.dart';

import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/ui/ui.dart';

import '../data/colleges.dart';
import 'university_picker_sheet.dart';

/// The sheet a student picks their college from: the app's list, or, under
/// «كلية أخرى», a name of their own. Either way the answer is a text.
class CollegePickerSheet extends StatefulWidget {
  final String? selected;
  final List<String> colleges;

  const CollegePickerSheet({super.key, this.selected, this.colleges = kColleges});

  /// Returns the college's name, or null when the sheet is dismissed.
  static Future<String?> show(BuildContext context, {String? selected}) => BasakSheet.showFrame<String>(
        context,
        builder: (_) => CollegePickerSheet(selected: selected),
      );

  /// The longest college name the database takes.
  static const maxLength = 80;

  @override
  State<CollegePickerSheet> createState() => _CollegePickerSheetState();
}

class _CollegePickerSheetState extends State<CollegePickerSheet> {
  final _search = TextEditingController();
  final _other = TextEditingController();
  final _otherFocus = FocusNode();
  String _query = '';
  String? _picked;
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    final selected = widget.selected?.trim() ?? '';
    if (selected.isEmpty) return;
    if (widget.colleges.contains(selected)) {
      _picked = selected;
    } else {
      // A name of the student's own, chosen before: back in its field.
      _typing = true;
      _other.text = selected;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _other.dispose();
    _otherFocus.dispose();
    super.dispose();
  }

  String? get _answer {
    if (!_typing) return _picked;
    final typed = _other.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return typed.length < 2 ? null : typed;
  }

  void _openOther() {
    setState(() {
      _typing = true;
      _picked = null;
    });
    _otherFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final needle = UniversityPickerSheet.normalize(_query);
    final matches = widget.colleges.where((name) => UniversityPickerSheet.normalize(name).contains(needle)).toList();
    final answer = _answer;

    return BasakSheetFrame(
      title: 'كليتك',
      largeTitle: true,
      header: BasakSearchField(
        controller: _search,
        hint: 'ابحث باسم الكلية',
        onChanged: (value) => setState(() => _query = value),
      ),
      // The way to another college stays in sight, whatever the list is scrolled to.
      primary: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_typing)
            Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14),
              decoration: BoxDecoration(color: colors.ground, borderRadius: BasakRadius.all(BasakRadius.control)),
              child: GroupedField(
                key: const Key('college-other-field'),
                label: 'كلية أخرى',
                hint: 'اكتب اسم كليتك',
                controller: _other,
                focusNode: _otherFocus,
                maxLength: CollegePickerSheet.maxLength,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  final typed = _answer;
                  if (typed != null) Navigator.pop(context, typed);
                },
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: BasakButton(
                key: const Key('college-other'),
                label: 'كلية أخرى',
                icon: LucideIcons.plus,
                onPressed: _openOther,
                variant: BasakButtonVariant.quiet,
                size: BasakButtonSize.small,
                expand: false,
              ),
            ),
          const SizedBox(height: BasakSpace.s10),
          BasakButton(
            key: const Key('college-confirm'),
            label: 'تأكيد',
            onPressed: answer == null ? null : () => Navigator.pop(context, answer),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
              child: Text('لا توجد كلية بهذا الاسم. اكتبها تحت «كلية أخرى».',
                  style: context.text.bodySmall.copyWith(color: colors.ink2)),
            )
          else
            Semantics(
              container: true,
              label: 'الكليات',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < matches.length; i++) ...[
                    if (i > 0) const SizedBox(height: BasakSpace.s2),
                    SheetRadioRow(
                      title: matches[i],
                      selected: !_typing && matches[i] == _picked,
                      onTap: () => setState(() {
                        _picked = matches[i];
                        _typing = false;
                      }),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
