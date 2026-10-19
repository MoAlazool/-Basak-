import 'package:basak_mobile/core/network/network_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a server function\'s refusal is shown in its own words, never raw', () {
    expect(errorMessage(const FunctionException(status: 403, details: {'error': 'هذا الإجراء للطلاب فقط.'})),
        'هذا الإجراء للطلاب فقط.');
    final raw = errorMessage(const FunctionException(status: 500, details: 'Internal'));
    expect(raw, isNot(contains('FunctionException')));
    expect(raw, 'تعذّر إتمام الطلب الآن. حاول مرة أخرى بعد قليل.');
  });

  test('other errors keep their text without the Dart prefix', () {
    expect(errorMessage(Exception('رسالة')), 'رسالة');
  });
}
