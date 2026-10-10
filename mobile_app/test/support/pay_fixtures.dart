// What the subscription tab, the pay page and the receipt are tested and drawn
// with: the data of the canvas boards (النورس للنقل, الزرقا, كوبري السرو).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:basak_mobile/features/student/subscription/data/subscription_repository.dart';
import 'package:basak_mobile/features/student/subscription/models/payment_method_model.dart';
import 'package:basak_mobile/features/student/subscription/models/sale_catalog.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/pay_screen.dart';
import 'package:basak_mobile/features/student/subscription/presentation/purchase_flow.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

String isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

/// One subscription of سارة on line الزرقا.
SubscriptionModel boardSub(
  String status, {
  String id = 'sub1',
  String code = 'first',
  String phase = 'current',
  int year = 2026,
  String start = '2026-09-20',
  String end = '2027-01-14',
  double price = 4500,
  String type = 'termly',
  String? supervisorPhone = '01012345678',
}) =>
    SubscriptionModel.fromJson({
      'id': id, 'student_id': 'me', 'line_id': 'l1', 'company_id': 'c1', 'station_id': 's1', 'type': type,
      'status': status, 'price': price, 'created_at': start, 'start_date': start, 'end_date': end,
      'period_code': type == 'daily' ? null : code, 'academic_year': year, 'period_phase': phase,
      'lines': {
        'name': 'الزرقا',
        'companies': {'name': 'النورس للنقل'},
        if (supervisorPhone != null) 'supervisors': {'full_name': 'أحمد علي', 'phone': supervisorPhone},
      },
      'stations': {'name': 'كوبري السرو'},
      'student': {'university': 'جامعة المنصورة الجديدة'},
    });

/// The five methods of the Pay board.
List<PaymentMethodModel> boardMethods() => [
      for (final m in [
        {'id': 'm1', 'method_type': 'instapay', 'display_name': 'InstaPay', 'instapay_address': 'elnawras@instapay',
         'account_holder': 'شركة النورس للنقل', 'instructions': 'اكتب اسمك الثلاثي في ملاحظات التحويل.'},
        {'id': 'm2', 'method_type': 'vodafone_cash', 'display_name': 'فودافون كاش', 'wallet_phone': '010 1234 5678',
         'account_holder': 'شركة النورس للنقل'},
        {'id': 'm3', 'method_type': 'vodafone_cash', 'display_name': 'اتصالات كاش', 'wallet_phone': '011 1234 5678',
         'account_holder': 'شركة النورس للنقل'},
        {'id': 'm4', 'method_type': 'bank', 'display_name': 'البنك الأهلي', 'bank_name': 'البنك الأهلي المصري',
         'bank_account_number': '0123 4567 8901 234', 'iban': 'EG00 0003 0000 0000 0000 0000 000',
         'account_holder': 'شركة النورس للنقل'},
        {'id': 'm5', 'method_type': 'bank', 'display_name': 'بنك مصر', 'bank_name': 'بنك مصر',
         'bank_account_number': '0987 6543 2109 876', 'iban': 'EG00 0002 0000 0000 0000 0000 000',
         'account_holder': 'شركة النورس للنقل'},
      ])
        PaymentMethodModel.fromJson(m),
    ];

ReceiptModel boardReceipt(int attempt, String status, {String? reason, String? at, String? method = 'm1'}) =>
    ReceiptModel.fromJson({
      'id': 'r$attempt', 'subscription_id': 'sub1', 'image_url': 'me/sub1_$attempt.jpg', 'status': status,
      'rejection_reason': reason, 'attempt_number': attempt,
      'created_at': at ?? DateTime.now().toUtc().toIso8601String(), 'payment_method_id': method,
    });

const boardReceiptDoc = SubscriptionReceipt(
  subscriptionId: 'sub1', code: '26-7F3A9C2E', companyName: 'النورس للنقل', studentName: 'سارة أحمد محمود',
  studentPhone: '010 2345 6789', universityName: 'جامعة المنصورة الجديدة', lineName: 'الزرقا',
  stationName: 'كوبري السرو', periodLabel: 'الفصل الدراسي الأول 2026/2027', startDate: '2026-09-20',
  endDate: '2027-01-14', amount: 4500, paymentMethod: 'InstaPay', approvedAt: '2026-09-22T10:00:00Z',
  companyPhone: '057 240 1122', companyAddress: 'الزرقا، دمياط',
);

/// What is on sale on line الزرقا: the second term, upcoming or current.
SaleCatalog boardCatalog({String secondPhase = 'upcoming', bool withSecond = true}) =>
    SaleCatalog.fromJson(jsonDecode(jsonEncode({
      'university': {'id': 'u1', 'name': 'جامعة المنصورة الجديدة'},
      'companies': [
        {
          'id': 'c1', 'name': 'النورس للنقل',
          'lines': [
            {
              'id': 'l1', 'name': 'الزرقا', 'origin_name': 'الزرقا', 'university': 'جامعة المنصورة الجديدة',
              'first_departure': '06:30:00', 'last_return': '17:30:00',
              'stations': [
                {'id': 's1', 'name': 'كوبري السرو', 'departures': [{'trip_id': 't1', 'time': '07:00:00', 'label': ''}]},
              ],
              'returns': [{'trip_id': 'r1', 'time': '15:00:00', 'label': ''}],
              'options': [
                if (withSecond)
                  {'option': 'second', 'academic_year': 2026, 'name': 'الفصل الدراسي الثاني',
                   'label': 'الفصل الدراسي الثاني 2026/2027', 'type': 'termly', 'start_date': '2027-02-07',
                   'end_date': '2027-06-10', 'phase': secondPhase, 'price': 4500},
              ],
              'daily': {'enabled': false, 'price': 0},
            },
          ],
        },
      ],
    })) as Map<String, dynamic>);

/// A submitter whose sending is driven by the test: it reports [phase] and
/// [sent], then waits for [finish].
class ScriptedSubmitter extends ReceiptSubmitter {
  ScriptedSubmitter(super.ref);

  static ReceiptPhase phase = ReceiptPhase.uploading;
  static double? sent = .62;
  /// Completed with the saved receipt, or with what the sending fails with.
  static Completer<Object> finish = Completer<Object>();
  static String? lastMethodId;
  static int calls = 0;

  /// The page's own listeners, for a test that moves the sending on.
  static void Function(ReceiptPhase phase)? tellPhase;
  static void Function(int sent, int total)? tellProgress;

  static void reset() {
    phase = ReceiptPhase.uploading;
    sent = .62;
    finish = Completer<Object>();
    lastMethodId = null;
    calls = 0;
    tellPhase = null;
    tellProgress = null;
  }

  @override
  Future<ReceiptModel> submit({
    required ReceiptAttempt attempt,
    required Uint8List bytes,
    String? paymentMethodId,
    void Function(ReceiptPhase phase)? onPhase,
    void Function(int sent, int total)? onProgress,
  }) {
    calls++;
    lastMethodId = paymentMethodId;
    tellPhase = onPhase;
    tellProgress = onProgress;
    onPhase?.call(phase);
    if (sent != null) onProgress?.call((sent! * 1000).round(), 1000);
    return finish.future.then((outcome) => outcome is ReceiptModel ? outcome : throw outcome);
  }
}

/// The providers a screen of this group reads, answered from memory.
List<Override> payOverrides({
  List<SubscriptionModel> subs = const [],
  List<ReceiptModel> receipts = const [],
  List<PaymentMethodModel>? methods,
  SubscriptionReceipt? doc,
  Object? docError,
  SaleCatalog? catalog,
  bool catalogNever = false,
  bool methodsNever = false,
  bool scripted = true,
}) =>
    [
      allSubscriptionsProvider.overrideWith((ref) async => subs),
      saleCatalogProvider.overrideWith(
          (ref) => catalogNever ? Completer<SaleCatalog>().future : Future.value(catalog ?? boardCatalog())),
      subscriptionReceiptsProvider.overrideWith((ref, id) async => receipts),
      subscriptionReceiptDocProvider.overrideWith((ref, id) async {
        if (docError != null) throw docError;
        return doc;
      }),
      paymentMethodsProvider.overrideWith((ref, id) =>
          methodsNever ? Completer<List<PaymentMethodModel>>().future : Future.value(methods ?? boardMethods())),
      if (scripted) receiptSubmitterProvider.overrideWith((ref) => ScriptedSubmitter(ref)),
    ];

/// A small real JPEG on disk, handed over as the picture the student chose.
Future<void> fakeReceiptPicker(WidgetTester tester) async {
  late final String path;
  await tester.runAsync(() async {
    final picture = img.Image(width: 240, height: 320)..clear(img.ColorRgb8(214, 235, 245));
    img.fillRect(picture, x1: 30, y1: 40, x2: 210, y2: 70, color: img.ColorRgb8(23, 56, 74));
    img.fillRect(picture, x1: 30, y1: 100, x2: 160, y2: 116, color: img.ColorRgb8(88, 112, 127));
    img.fillRect(picture, x1: 30, y1: 140, x2: 190, y2: 156, color: img.ColorRgb8(88, 112, 127));
    final dir = await Directory.systemTemp.createTemp('basak-receipt');
    path = '${dir.path}/receipt.jpg';
    await File(path).writeAsBytes(img.encodeJpg(picture));
  });
  PayScreen.debugPickImage = (ImageSource source) async => XFile(path, name: 'receipt.jpg');
  addTearDown(() => PayScreen.debugPickImage = null);
}

/// Lets what runs outside the test's clock (reading and preparing the
/// picture) finish, then draws.
Future<void> realTime(WidgetTester tester, [int ms = 250]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
