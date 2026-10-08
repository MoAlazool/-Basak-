import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../daily_ride/data/reminder_days_off.dart';
import '../../daily_ride/models/vote_settings.dart';
import 'student_home_screen.dart';

/// Whether the app reminds the student to confirm a ride day.
enum ReminderDayState { on, off, voted, dayOff, outside, companyOff }

typedef ReminderDay = ({DateTime day, ReminderDayState state});

/// The coming week of ride days whose vote has not closed yet: reminded,
/// switched off by the student, already voted for, a day off set by the
/// company, not covered by the subscription, or without reminders because the
/// company has them switched off.
List<ReminderDay> reminderDays({
  required VoteSettings vote,
  required DateTime now,
  required DateTime? validFrom,
  required DateTime? validUntil,
  required Map<DateTime, bool> voted,
  required Set<DateTime> daysOff,
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
                : daysOff.contains(day)
                    ? ReminderDayState.off
                    : ReminderDayState.on;
    return (day: day, state: state);
  });
}

/// The votes already sent for the days the page shows.
final _votedDaysProvider = FutureProvider.autoDispose<Map<DateTime, bool>>((ref) async {
  ref.watch(sessionUserIdProvider);
  final vote = await ref.watch(voteSettingsProvider.future);
  final first = vote.rideDateFor(DateTime.now());
  return ref
      .watch(dailyRideRepoProvider)
      .getRideStatusesForRange(first, DateTime(first.year, first.month, first.day + 7));
});

/// The student's notifications, opened from the bell on the home screen. For
/// now it holds the ride-vote reminders, which can be switched off per day.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

  static const _ink = Color(0xFF17384A);
  static const _teal = Color(0xFF00658D);
  static const _muted = Color(0xFF718695);
  static const _faded = Color(0xFFA3B3BE);
  static const _soft = Color(0xFFE5F3FA);
  static const _line = Color(0xFFE3EDF3);

  static const _weekdays = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
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
      daysOff: ref.watch(reminderDaysOffProvider).valueOrNull ?? const {},
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FA),
      body: Column(
        children: [
          _topBar(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 18, bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _remindersCard(
                    sub == null || !sub.isActive
                        ? 'التذكيرات تعمل بعد تفعيل اشتراكك.'
                        : vote.reminderMinutes <= 0
                            ? 'التذكيرات متوقفة من شركتك حالياً.'
                            : 'نذكّرك بتأكيد حضورك قبل قفل التصويت. اضغط على اليوم لإيقاف تذكيره أو تشغيله.',
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
                      itemBuilder: (context, i) => _dayChip(
                        days[i],
                        onTap: switch (days[i].state) {
                          ReminderDayState.on || ReminderDayState.off => () => ref
                              .read(reminderDaysOffProvider.notifier)
                              .toggle(days[i].day),
                          _ => null,
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    const Icon(LucideIcons.bellRing, color: _teal, size: 19),
                    const SizedBox(width: 8),
                    Text('0 إشعارات غير مقروءة',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: _teal, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _emptyCard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'رجوع',
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: _line),
              ),
              child: InkWell(
                customBorder:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(LucideIcons.arrowRight, color: _ink, size: 21),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('الإشعارات',
                style: AppTextStyles.titleLarge.copyWith(color: _ink, fontSize: 21)),
          ),
          // Enabled once the page has notifications to clear.
          TextButton.icon(
            onPressed: null,
            icon: const Icon(LucideIcons.checkCheck, size: 18),
            label: const Text('مسح الكل'),
            style: TextButton.styleFrom(
              foregroundColor: _teal,
              textStyle: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  Widget _remindersCard(String note) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('فعّل التذكير لأيام محددة',
                  style: AppTextStyles.titleMedium.copyWith(color: _ink)),
              const SizedBox(height: 4),
              Text(note,
                  style: AppTextStyles.labelSmall.copyWith(color: _muted, height: 1.5)),
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
      );

  Widget _dayChip(ReminderDay day, {VoidCallback? onTap}) {
    final (background, border, color, icon, caption) = switch (day.state) {
      ReminderDayState.on => (_soft, _teal, _teal, LucideIcons.bell, 'تذكير مفعّل'),
      ReminderDayState.off => (Colors.white, _line, _muted, LucideIcons.bellOff, 'التذكير متوقف'),
      ReminderDayState.voted => (
          const Color(0xFFE7F8F0),
          const Color(0xFFBDE9D3),
          const Color(0xFF07865A),
          LucideIcons.check,
          'تم التصويت'
        ),
      ReminderDayState.dayOff => (
          const Color(0xFFF3F6F8),
          _line,
          _faded,
          LucideIcons.calendarX2,
          'إجازة'
        ),
      ReminderDayState.outside => (
          const Color(0xFFF3F6F8),
          _line,
          _faded,
          LucideIcons.calendarX2,
          'خارج الاشتراك'
        ),
      ReminderDayState.companyOff => (
          const Color(0xFFF3F6F8),
          _line,
          _faded,
          LucideIcons.bellOff,
          'بدون تذكير'
        ),
    };
    return Semantics(
      button: onTap != null,
      toggled: onTap == null ? null : day.state == ReminderDayState.on,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text('${_weekdays[day.day.weekday - 1]} ${day.day.day}',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: onTap == null && day.state != ReminderDayState.voted
                              ? _faded
                              : _ink,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 3),
                Text(caption, style: AppTextStyles.labelSmall.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: _soft, shape: BoxShape.circle),
            child: const Icon(LucideIcons.bell, color: _teal, size: 28),
          ),
          const SizedBox(height: 14),
          Text('لا توجد إشعارات بعد',
              style: AppTextStyles.titleMedium.copyWith(color: _ink)),
          const SizedBox(height: 6),
          Text('ستظهر هنا إشعارات رحلاتك واشتراكك.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: _muted)),
        ]),
      );
}
