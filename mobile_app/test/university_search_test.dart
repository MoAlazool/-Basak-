import 'package:basak_mobile/features/auth/presentation/university_picker_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('university search forgives common Arabic spelling differences', () {
    final n = UniversityPickerSheet.normalize;
    expect(n('جامعه المنصوره'), n('جامعة المنصورة'));
    expect(n('جامعة الأزهر'), n('جامعه الازهر'));
    expect(n('  جامعة   طنطا '), 'جامعه طنطا');
    expect(n('مستشفى'), n('مستشفي'));
    expect(n('Delta University').contains(n('delta')), isTrue);
    expect(n('جامعة المنصورة').contains(n('القاهرة')), isFalse);
  });
}
