// The supervisor's month, ready messages and scan answers as the canvas
// boards draw them (SupMonthly, SupSend, SupScanOk, SupScanStop, …).
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/supervisor/data/supervisor_repository.dart';
import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:basak_mobile/features/supervisor/qr_scanner/models/scanned_student_details.dart';

/// get_supervisor_monthly_summary() as on SupMonthly: October 2026, 1,284
/// boardings on nine working days.
Map<String, dynamic> boardMonth({int days = 9}) {
  const worked = [1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 24, 25, 26, 27, 28, 29, 31];
  const going = [83, 82, 85, 79, 76, 84, 81, 86, 52];
  const back = [69, 66, 71, 66, 61, 70, 69, 72, 32];
  return {
    'month': '2026-10-01',
    'totals': {
      'checkins': 1284, 'departure_checkins': 702, 'return_checkins': 582, 'unique_students': 118,
      'scans': 1352, 'duplicate_scans': 52, 'rejected_scans': 16, 'active_days': 9, 'confirmed_rides': 771,
    },
    'days': [
      for (var i = 0; i < days; i++)
        {
          'date': '2026-10-${worked[i].toString().padLeft(2, '0')}',
          'checkins': going[i % going.length] + back[i % back.length],
          'departure': going[i % going.length],
          'return': back[i % back.length],
          'scans': going[i % going.length] + back[i % back.length] + 6,
          'confirmed': 86,
        },
    ],
    'stations': [
      for (final (name, count) in const [
        ('كوبري السرو', 268), ('موقف الزرقا', 214), ('السرو', 201), ('شرباص', 176), ('الروضة', 163),
        ('فارسكور', 142), ('كفر سعد', 120),
      ])
        {'station': name, 'line': 'الزرقا', 'checkins': count},
    ],
  };
}

/// A month nobody scanned in.
Map<String, dynamic> emptyMonth(String month) => {'month': month, 'totals': <String, dynamic>{}};

/// The server's ready messages, as on SupSend.
const boardTemplates = [
  QuickNotificationTemplate(
      key: 'delay', title: 'تأخير في موعد الحافلة', body: 'ستتأخر الحافلة نحو {minutes} دقيقة. نعتذر عن التأخير.',
      needsMinutes: true),
  QuickNotificationTemplate(
      key: 'departed', title: 'الحافلة تحركت',
      body: 'بدأت رحلة الذهاب والحافلة في طريقها. كن في محطتك في الموعد.', direction: 'departure'),
  QuickNotificationTemplate(
      key: 'arrived', title: 'وصلت الحافلة إلى الجامعة', body: 'وصلت رحلة الذهاب إلى الجامعة.',
      direction: 'departure'),
  QuickNotificationTemplate(
      key: 'cancelled', title: 'إلغاء الرحلة', body: 'أُلغيت هذه الرحلة اليوم. تابع الإشعارات لمعرفة البديل.'),
];

ScannedStudentDetails boardStudent(String name, {String phone = '01023456789', String station = 'كوبري السرو'}) =>
    ScannedStudentDetails(
      id: 'student-1',
      fullName: name,
      phone: phone,
      university: 'جامعة المنصورة الجديدة',
      subscriptionStatus: 'active',
      lineName: 'الزرقا',
      stationName: station,
      todayRideStatus: true,
    );

/// What a scan answers, per outcome, as on SupScanStates.
CheckInResult boardScan(CheckInOutcome outcome) {
  const vote = RideVote(isRiding: true, isReturning: true, departureTime: '07:00:00', returnTime: '15:30:00');
  CheckInResult of({ScannedStudentDetails? student, DateTime? at}) => CheckInResult(
      outcome: outcome, direction: 'departure', checkedInAt: at, rideVote: vote, hasRideVote: true, student: student);
  return switch (outcome) {
    CheckInOutcome.checkedIn => of(student: boardStudent('سارة أحمد محمود'), at: DateTime(2026, 10, 11, 7, 23)),
    CheckInOutcome.alreadyCheckedIn =>
      of(student: boardStudent('يوسف طارق حسن', station: 'شرباص'), at: DateTime(2026, 10, 11, 7, 2)),
    CheckInOutcome.noActiveSubscription =>
      of(student: boardStudent('عمر خالد منصور', phone: '01144556677', station: 'السرو')),
    CheckInOutcome.outsideAssignedLines || CheckInOutcome.notFound => of(),
    CheckInOutcome.offlineLookup => of(student: boardStudent('سارة أحمد محمود')),
  };
}

/// A server that answers every scan with [answer] and counts nothing else.
class ScanRepo extends SupervisorRepository {
  CheckInResult answer;
  ScanRepo(this.answer);

  @override
  Future<CheckInResult> checkIn(String qrValue, {required String direction, String? tripId}) async => answer;
}
