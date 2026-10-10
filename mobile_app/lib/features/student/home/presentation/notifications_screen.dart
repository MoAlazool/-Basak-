import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../notifications/presentation/notifications_page.dart';
import '../../daily_ride/models/vote_settings.dart';
import 'student_home_screen.dart';
import 'supervisor_contact_sheet.dart';

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

/// The student's alerts, behind the bell on Home: the inbox alone. No
/// settings, no categories, no search; the days a ride reminder comes on are
/// the week strip's on Home (see [reminderDays]).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Home already holds the subscription: nothing is read again for it here.
    final phone = ref.watch(currentSubscriptionProvider).valueOrNull?.supervisorPhone ?? '';
    return NotificationsPage(
      preferences: false,
      detailAction: (notification) => _callSupervisor(phone, notification),
    );
  }

  /// A message from the bus supervisor can be answered with a call, when the
  /// student's subscription knows the supervisor's number.
  static AlertAction? _callSupervisor(String phone, AppNotification notification) {
    if (notification.senderRole != 'supervisor') return null;
    if (phone.trim().isEmpty) return null;
    return (
      label: 'اتصل بالمشرف',
      icon: LucideIcons.phone,
      run: (page) => SupervisorContactSheet.call(page, phone),
    );
  }
}
