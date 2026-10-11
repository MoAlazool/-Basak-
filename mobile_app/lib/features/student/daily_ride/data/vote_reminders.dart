import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../notifications/local/local_notifier.dart';
import '../models/vote_settings.dart';

/// Notifications that remind a student to confirm a ride before its vote closes.
///
/// The phone schedules them itself (no push server): from the moment a vote
/// opens, every [VoteSettings.reminderMinutes] until it closes, for the ride
/// days of the coming week that the subscription covers. A day the student
/// has already voted for (riding or not) gets none. The plan is made again
/// whenever the app opens, comes back to the foreground or a vote is sent, so
/// voting stops that day's reminders and a changed setting arrives then.
class VoteReminders {
  VoteReminders._();

  static FlutterLocalNotificationsPlugin get _plugin => LocalNotifier.plugin;
  static Future<void> _queue = Future.value();

  /// How far ahead reminders are planned. How many at most, and under which
  /// numbers, is [LocalNotifier.voteMax]: the phone's other notifications
  /// (the subscription's dates, the inbox) are never touched from here.
  static const _days = 7;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'vote_reminders',
      'تذكير تأكيد الرحلة',
      channelDescription: 'تذكير بتأكيد حضور الرحلة قبل قفل التصويت',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_basak',
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Replaces the planned reminders. [votedDays] are the ride days (dates
  /// only) the student has already voted for; [validFrom] / [validUntil] bound
  /// the subscription. Never throws: reminders are a convenience.
  static Future<void> plan({
    required VoteSettings settings,
    required DateTime? validFrom,
    required DateTime? validUntil,
    required Set<DateTime> votedDays,
  }) =>
      _serial(() async {
        if (!await LocalNotifier.ready()) return;
        await _cancelOwn();

        final now = DateTime.now();
        final first = settings.rideDateFor(now);
        final reminders = <({DateTime day, DateTime at})>[];
        for (var i = 0; i < _days; i++) {
          final day = DateTime(first.year, first.month, first.day + i);
          if (validFrom != null && day.isBefore(validFrom)) continue;
          if (validUntil != null && day.isAfter(validUntil)) break;
          if (votedDays.contains(day)) continue;
          for (final at in settings.reminderTimesFor(day)) {
            if (at.isAfter(now)) reminders.add((day: day, at: at));
          }
        }
        if (reminders.isEmpty || !await LocalNotifier.permitted(ask: true)) return;

        final closes = VoteSettings.clock(settings.closesAt, long: true);
        for (final (index, reminder) in reminders.take(LocalNotifier.voteMax).indexed) {
          final at = reminder.at;
          await _plugin.zonedSchedule(
            id: LocalNotifier.voteFirst + index,
            title: 'أكّد رحلة ${_dayName(reminder.day)}',
            body: 'لم تؤكد حضورك بعد. التصويت مفتوح حتى $closes.',
            scheduledDate: tz.TZDateTime(
                LocalNotifier.cairo, at.year, at.month, at.day, at.hour, at.minute),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      });

  /// Nothing to remind about (no running subscription, reminders switched off).
  static Future<void> cancelAll() => _serial(_cancelOwn);

  /// Up to 64: an earlier version of the app planned that many.
  static Future<void> _cancelOwn() => LocalNotifier.cancelRange(LocalNotifier.voteFirst, 64);

  /// One plan at a time, so an older plan never lands after a newer one.
  static Future<void> _serial(Future<void> Function() work) {
    final next = _queue.then((_) => work()).catchError((Object error) {
      debugPrint('Vote reminders: $error');
    });
    _queue = next;
    return next;
  }

  static String _dayName(DateTime day) => const [
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد',
      ][day.weekday - 1];
}
