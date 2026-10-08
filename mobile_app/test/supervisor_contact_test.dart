import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/student/home/presentation/supervisor_contact_sheet.dart';

void main() {
  test('the saved contact says who it is, and the number is dialable', () {
    expect(SupervisorContactSheet.contactName('أحمد علي', 'منيه النصر'), 'أحمد علي - مشرف باص منيه النصر');
    expect(SupervisorContactSheet.contactName('', null), 'مشرف الباص');
    expect(SupervisorContactSheet.dialable('010 1234-5678'), '01012345678');
    expect(SupervisorContactSheet.dialable('+20 10 1234 5678'), '+201012345678');
  });

  testWidgets('tapping the supervisor opens a sheet to call, save or copy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SupervisorContactSheet.show(context,
                  name: 'أحمد علي', phone: '01012345678', lineName: 'منيه النصر'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('أحمد علي'), findsOneWidget);
    expect(find.text('مشرف حافلة خط منيه النصر'), findsOneWidget);
    expect(find.text('01012345678'), findsOneWidget);
    expect(find.byKey(const Key('supervisor-call')), findsOneWidget);
    expect(find.byKey(const Key('supervisor-save')), findsOneWidget);
    expect(find.byKey(const Key('supervisor-copy')), findsOneWidget);
  });
}
