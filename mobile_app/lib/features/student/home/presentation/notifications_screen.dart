import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../notifications/presentation/notifications_page.dart';
import '../../daily_ride/models/vote_settings.dart';
import 'student_home_screen.dart';

/// Whether the app reminds the student to confirm a ride day.
enum ReminderDayState { on, voted, dayOff, outside, companyOff }

typedef ReminderDay = ({DateTime day, ReminderDayState state});

/// The coming week of ride days whose vote has not closed yet: reminded,
/// already voted for, a day off set by the company, not covered by the
/// subscription, or without reminders because the company switched them off.
List<ReminderDay> reminderDays({
  required VoteSettings vote,
  required DateTime now,
  required DateTime? validFrom,
  required DateTime? validUntil,
  required Map<DateTime, bool> voted,
}) {
  var first = vote.rideDateFor(now);
  if (!vote.windowFor(first).closes.isAfter(now)) {
    first = DateTime(first.year, first.month, first.day + 1);
  }
  return List.generate(7, (i) {
    final day = DateTime(first.year, first.month, first.day + i);
    final state = (validFrom != null && day.isBefore(validFrom)) ||
            (validUntil != null && day.isAfter(validUntil))
        ? ReminderDayState.outside
        : voted.containsKey(day)
            ? ReminderDayState.voted
            : vote.reminderMinutes <= 0
                ? ReminderDayState.companyOff
                : !vote.remindsFor(day)
                    ? ReminderDayState.dayOff
                    : ReminderDayState.on;
    return (day: day, state: state);
  });
}

/// The votes already sent for the days the strip shows.
final _votedDaysProvider = FutureProvider.autoDispose<Map<DateTime, bool>>((ref) async {
  ref.watch(sessionUserIdProvider);
  final vote = await ref.watch(voteSettingsProvider.future);
  final first = vote.rideDateFor(DateTime.now());
  return ref
      .watch(dailyRideRepoProvider)
      .getRideStatusesForRange(first, DateTime(first.year, first.month, first.day + 7));
});

/// The student's notifications, opened from the bell on the home screen, under
/// the coming week's ride-vote reminders (set by the company, not by the student).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

  @override
  Widget build(BuildContext context) =>
      const NotificationsPage(header: _ReminderDays(), preferences: false);
}

class _ReminderDays extends ConsumerWidget {
  const _ReminderDays();

  static const _ink = NotificationsPage.ink;
  static const _teal = NotificationsPage.teal;
  static const _muted = NotificationsPage.muted;
  static const _soft = NotificationsPage.soft;
  static const _line = NotificationsPage.line;
  static const _faded = Color(0xFFA3B3BE);

  static const _weekdays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vote = ref.watch(voteSettingsProvider).valueOrNull ?? VoteSettings.fallback;
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
    final subscribed = sub != null && sub.isActive;
    final days = reminderDays(
      vote: vote,
      now: DateTime.now(),
      validFrom: DateTime.tryParse(sub?.startDate ?? ''),
      validUntil: DateTime.tryParse(sub?.endDate ?? ''),
      voted: ref.watch(_votedDaysProvider).valueOrNull ?? const {},
    );
    // The days are the company's; whether a reminder is shown is the phone's
    // own notification permission. There is no switch for it in the app.
    final note = !subscribed
        ? 'التذكيرات تعمل بعد تفعيل اشتراكك.'
        : vote.reminderMinutes <= 0
            ? 'التذكيرات متوقفة من شركتك حالياً.'
            : 'نذكّرك بتأكيد حضورك قبل قفل التصويت في الأيام المفعّلة.';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تذكير تأكيد الرحلة', style: AppTextStyles.titleMedium.copyWith(color: _ink)),
                const SizedBox(height: 4),
                Text(note, style: AppTextStyles.labelSmall.copyWith(color: _muted, height: 1.5)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(14)),
              child: const Icon(LucideIcons.calendarDays, color: _teal, size: 23),
            ),
          ]),
        ),
      ),
      if (subscribed) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _dayChip(days[i]),
          ),
        ),
      ],
    ]);
  }

  Widget _dayChip(ReminderDay day) {
    final (background, border, color, icon, caption) = switch (day.state) {
      ReminderDayState.on => (_soft, _teal, _teal, LucideIcons.bell, 'تذكير مفعّل'),
      ReminderDayState.voted => (
          const Color(0xFFE7F8F0),
          const Color(0xFFBDE9D3),
          const Color(0xFF07865A),
          LucideIcons.check,
          'تم التصويت'
        ),
      ReminderDayState.dayOff => (const Color(0xFFF3F6F8), _line, _faded, LucideIcons.calendarX2, 'إجازة'),
      ReminderDayState.outside =>
        (const Color(0xFFF3F6F8), _line, _faded, LucideIcons.calendarX2, 'خارج الاشتراك'),
      ReminderDayState.companyOff =>
        (const Color(0xFFF3F6F8), _line, _faded, LucideIcons.bellOff, 'بدون تذكير'),
    };
    final faded = day.state != ReminderDayState.on && day.state != ReminderDayState.voted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
                '${_weekdays[day.day.weekday - 1]} ${day.day.day} '
                '${NotificationsPage.months[day.day.month - 1]}',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: faded ? _faded : _ink, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 3),
          Text(caption, style: AppTextStyles.labelSmall.copyWith(color: color)),
        ],
      ),
    );
  }
}
