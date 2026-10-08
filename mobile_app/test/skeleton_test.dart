import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/widgets/skeleton.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

void main() {
  for (final size in const [Size(320, 568), Size(402, 874)]) {
    testWidgets('every skeleton fits a ${size.width.toInt()} wide phone without overflowing', (tester) async {
      tester.view.physicalSize = Size(size.width, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(children: [
              HomeSkeleton(), SubscriptionsSkeleton(), PurchaseFlowSkeleton(), StudentCardSkeleton(),
              ProfileSkeleton(), SupervisorHomeSkeleton(), StationRowsSkeleton(), MonthlySkeleton(), SkeletonList(),
            ]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a first load shows the screen\'s own skeleton, never a bare spinner', (tester) async {
    final never = Completer<List<SubscriptionModel>>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allSubscriptionsProvider.overrideWith((ref) => never.future),
        saleCatalogProvider.overrideWith((ref) => Completer<SaleCatalog>().future),
      ],
      child: const MaterialApp(home: SubscriptionScreen()),
    ));
    await tester.pump();
    expect(find.byType(SubscriptionsSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [studentQrProvider.overrideWith((ref) => Completer<StudentPassDetails?>().future)],
      child: const MaterialApp(home: StudentQrScreen()),
    ));
    await tester.pump();
    expect(find.byType(StudentCardSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('with something already on screen, a refresh keeps it instead of a skeleton', (tester) async {
    var calls = 0;
    final second = Completer<StudentPassDetails?>();
    const pass = StudentPassDetails(qrValue: 'QR-1', fullName: 'طالب', subscriptionStatus: 'active');
    late WidgetRef hold;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        studentQrProvider.overrideWith((ref) async => calls++ == 0 ? pass : await second.future),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          hold = ref;
          return const StudentQrScreen();
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('طالب'), findsOneWidget);
    hold.invalidate(studentQrProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('طالب'), findsOneWidget, reason: 'the card stays while it is read again');
    expect(find.byType(StudentCardSkeleton), findsNothing);
    second.complete(pass);
    await tester.pumpAndSettle();
  });
}
