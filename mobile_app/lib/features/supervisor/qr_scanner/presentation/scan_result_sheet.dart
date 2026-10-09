import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../student/home/presentation/supervisor_contact_sheet.dart';
import '../../models/supervisor_models.dart';
import '../../supervisor_copy.dart';
import '../models/scanned_student_details.dart';

/// What one scan says, apart from how it is drawn: the six outcomes of
/// `supervisor_check_in_student`, each with its tone, its title and one line.
class ScanResultWords {
  final BasakTone tone;
  final IconData icon;
  final String title;
  final String message;

  /// Under the student's name.
  final String? caption;
  final List<PersonFact> facts;

  const ScanResultWords({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    this.caption,
    this.facts = const [],
  });

  /// [tripLabel] is the trip the scanner is pinned to ("7:00 ص"); without it
  /// the trip is the student's own, known from what they confirmed.
  factory ScanResultWords.of(CheckInResult result, {String? tripLabel}) {
    final student = result.student;
    final direction = result.direction;
    final at = result.checkedInAt == null ? null : SupervisorCopy.clock(result.checkedInAt!);
    final vote = result.rideVote;
    final ownTime = vote == null || !vote.isRiding
        ? null
        : (direction == 'return' ? (vote.isReturning ? vote.returnTime : null) : vote.departureTime);
    final tripTime = tripLabel ?? (ownTime == null ? null : BasakUi.time12(ownTime));
    final trip = [SupervisorCopy.direction(direction), if (tripTime != null) tripTime].join(' ');

    final phone =
        student == null ? null : PersonFact('الهاتف', SupervisorContactSheet.readable(student.phone), ltr: true);
    final lineAndStop = student == null ? null : PersonFact('الخط والمحطة', _lineAndStop(student));
    final boardingFacts = [
      if (student != null) PersonFact('المحطة', student.stationName ?? 'غير محددة'),
      if (student != null) PersonFact('تأكيد اليوم', confirmation(result)),
      if (phone != null) phone,
    ];

    return switch (result.outcome) {
      CheckInOutcome.checkedIn => ScanResultWords(
          tone: BasakTone.success,
          icon: LucideIcons.check,
          title: 'تم تسجيل الصعود',
          message: at == null ? trip : '$trip · سُجّل $at',
          caption: student?.university,
          facts: boardingFacts,
        ),
      CheckInOutcome.alreadyCheckedIn => ScanResultWords(
          tone: BasakTone.info,
          icon: LucideIcons.history,
          title: 'سبق تسجيله اليوم',
          message: at == null
              ? 'صعد في رحلة ${SupervisorCopy.theDirection(direction)} اليوم.'
              : 'صعد $at في رحلة ${SupervisorCopy.theDirection(direction)}.',
          caption: student?.university,
          facts: boardingFacts,
        ),
      CheckInOutcome.noActiveSubscription => ScanResultWords(
          tone: BasakTone.danger,
          icon: LucideIcons.ban,
          title: 'لا يوجد اشتراك ساري',
          message: 'لم يُسجَّل الصعود.',
          caption: student?.university,
          facts: [
            if (lineAndStop != null) lineAndStop,
            if (student != null) const PersonFact('الاشتراك', 'غير مفعّل أو منتهٍ', tone: BasakTone.danger),
            if (phone != null) phone,
          ],
        ),
      CheckInOutcome.outsideAssignedLines => const ScanResultWords(
          tone: BasakTone.danger,
          icon: LucideIcons.x,
          title: 'الطالب ليس على خطك',
          message: 'غير مشترك في الخطوط المسندة إليك. لم يُسجَّل الصعود.',
        ),
      CheckInOutcome.notFound => const ScanResultWords(
          tone: BasakTone.danger,
          icon: LucideIcons.circleHelp,
          title: 'رمز غير معروف',
          message: 'هذا الرمز لا يخص أي طالب مسجّل في باصك.',
        ),
      CheckInOutcome.offlineLookup => ScanResultWords(
          tone: BasakTone.warning,
          icon: LucideIcons.wifiOff,
          title: 'بدون إنترنت · لم يُسجَّل',
          message: 'بيانات محفوظة من آخر تحقق. أعد المسح عند عودة الاتصال.',
          caption: student?.university,
          facts: [
            if (lineAndStop != null) lineAndStop,
            if (phone != null) phone,
          ],
        ),
    };
  }

  static String _lineAndStop(ScannedStudentDetails student) {
    final parts = [
      if ((student.lineName ?? '').isNotEmpty) student.lineName!,
      if ((student.stationName ?? '').isNotEmpty) student.stationName!,
    ];
    return parts.isEmpty ? 'غير محدد' : parts.join(' · ');
  }

  /// What the student confirmed for the day: "ذهاب 7:23 ص · عودة 3:30 م".
  static String confirmation(CheckInResult result) {
    if (!result.hasRideVote) {
      // An older server says only whether they confirmed.
      return result.confirmedRideToday == true ? 'أكّد الركوب' : 'لم يؤكّد اليوم';
    }
    final vote = result.rideVote;
    if (vote == null) return 'لم يؤكّد اليوم';
    if (!vote.isRiding) return 'أكّد أنه لن يركب';
    final going = vote.departureTime == null ? 'ذهاب' : 'ذهاب ${BasakUi.time12(vote.departureTime)}';
    final back = !vote.isReturning
        ? 'بدون عودة'
        : (vote.returnTime == null ? 'عودة' : 'عودة ${BasakUi.time12(vote.returnTime)}');
    return '$going · $back';
  }
}

/// The result of a scan, over the live camera: a badge in the outcome's
/// tone, a title, one line, then who was scanned when the server said so.
/// A boarding closes itself after [BasakMotion.boardedResult]; every other
/// result waits for «مسح التالي».
abstract final class ScanResultSheet {
  static const next = 'مسح التالي';

  static Future<void> show(
    BuildContext context,
    CheckInResult result, {
    String? tripLabel,
    bool closesItself = false,
  }) {
    final words = ScanResultWords.of(result, tripLabel: tripLabel);
    final student = result.student;
    return BasakSheet.show<void>(
      context,
      builder: (context) => Semantics(
        container: true,
        liveRegion: true,
        label: 'نتيجة المسح: ${words.title}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ResultHeader(tone: words.tone, icon: words.icon, title: words.title, message: words.message),
            if (student != null) ...[
              const SizedBox(height: BasakSpace.s16),
              PersonFacts(name: student.fullName, caption: words.caption, facts: words.facts),
            ],
            const SizedBox(height: BasakSpace.s2),
          ],
        ),
      ),
      primary: (sheet) {
        final route = ModalRoute.of(sheet);
        void close() {
          // Only this sheet: never a page that took its place meanwhile.
          if (route?.isCurrent ?? false) Navigator.of(sheet).pop();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasakButton(key: const Key('scan-next'), label: next, onPressed: close),
            if (closesItself) ...[
              const SizedBox(height: BasakSpace.s10),
              AutoReturnBar(onDone: close),
            ],
          ],
        );
      },
    );
  }
}
