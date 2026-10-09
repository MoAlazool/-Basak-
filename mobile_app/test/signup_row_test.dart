import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/auth/data/colleges.dart';

/// Answers the inserts of a student's row without a database: with the
/// `specialisation` column, or as a database that does not have it yet.
class _Rows implements StudentRows {
  final bool hasSpecialisation;
  final Object? alwaysFail;
  final List<Map<String, dynamic>> inserts = [];

  _Rows({this.hasSpecialisation = true, this.alwaysFail});

  @override
  Future<void> insert(Map<String, dynamic> record) async {
    inserts.add(record);
    if (alwaysFail != null) throw alwaysFail!;
    if (!hasSpecialisation && record.containsKey('specialisation')) {
      throw const PostgrestException(
        message: "Could not find the 'specialisation' column of 'students' in the schema cache",
        code: 'PGRST204',
      );
    }
  }
}

const _record = <String, dynamic>{
  'id': 'u1',
  'phone': '01012345678',
  'full_name': 'سارة أحمد محمود',
  'university': 'جامعة المنصورة الجديدة',
  'college': 'الهندسة',
};

/// The student's row at sign-up: the specialisation is optional, and signing
/// up works on a database that has no column for it yet.
void main() {
  test('no specialisation: one insert, and the key is not sent at all', () async {
    for (final empty in [null, '', '   ']) {
      final rows = _Rows(hasSpecialisation: false);
      await AuthRepository(students: rows).saveStudentRow(_record, specialisation: empty);
      expect(rows.inserts, [_record]);
    }
  });

  test('a specialisation is saved with the row, trimmed, in one insert', () async {
    final rows = _Rows();
    await AuthRepository(students: rows).saveStudentRow(_record, specialisation: '  هندسة مدنية ');
    expect(rows.inserts, [
      {..._record, 'specialisation': 'هندسة مدنية'},
    ]);
  });

  test('a database without the column: the row is sent once more without it', () async {
    final rows = _Rows(hasSpecialisation: false);
    await AuthRepository(students: rows).saveStudentRow(_record, specialisation: 'هندسة مدنية');
    expect(rows.inserts, [
      {..._record, 'specialisation': 'هندسة مدنية'},
      _record,
    ]);
  });

  test('an undefined-column answer from Postgres itself is treated the same way', () {
    expect(
        AuthRepository.isUnknownSpecialisationColumn(const PostgrestException(
            message: 'column "specialisation" of relation "students" does not exist', code: '42703')),
        isTrue);
    expect(
        AuthRepository.isUnknownSpecialisationColumn(
            const PostgrestException(message: "Could not find the 'nickname' column of 'students'", code: 'PGRST204')),
        isFalse);
    expect(AuthRepository.isUnknownSpecialisationColumn(Exception('specialisation column')), isFalse);
  });

  test('any other failure is told as it is, with no second attempt', () async {
    const duplicate = PostgrestException(
        message: 'duplicate key value violates unique constraint "students_phone_key"', code: '23505');
    final rows = _Rows(alwaysFail: duplicate);
    await expectLater(AuthRepository(students: rows).saveStudentRow(_record, specialisation: 'هندسة مدنية'),
        throwsA(same(duplicate)));
    expect(rows.inserts, hasLength(1));

    final plain = _Rows(alwaysFail: duplicate);
    await expectLater(AuthRepository(students: plain).saveStudentRow(_record), throwsA(same(duplicate)));
    expect(plain.inserts, hasLength(1));
  });

  test('the college list: the sheet as drawn first, no repeats, and each within the database limit', () {
    expect(kColleges.take(7),
        ['الهندسة', 'الطب', 'الصيدلة', 'طب الأسنان', 'الحاسبات والمعلومات', 'العلوم', 'التجارة']);
    expect(kColleges.toSet(), hasLength(kColleges.length));
    expect(kColleges.every((name) => name.trim() == name && name.length <= 80), isTrue);
    expect(kColleges, isNot(contains(AuthRepository.unknownCollege)));
  });

  test('the phone-taken message is the one written for the phone field', () {
    expect(AuthRepository.phoneAlreadyRegisteredMessage,
        'رقم الهاتف مسجل بالفعل. سجّل الدخول به، أو استخدم نسيت كلمة المرور.');
  });
}
