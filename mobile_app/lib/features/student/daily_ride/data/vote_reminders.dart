import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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

  static final _plugin = FlutterLocalNotificationsPlugin();
  static tz.Location? _cairo;
  static bool _askedPermission = false;
  static Future<void> _queue = Future.value();

  /// How far ahead reminders are planned, and how many at most (iOS keeps 64).
  static const _days = 7;
  static const _maxPending = 60;

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

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Replaces the planned reminders. [votedDays] are the ride days (dates
  /// only) the student has already voted for and [daysOff] those they turned
  /// reminders off for; [validFrom] / [validUntil] bound the subscription.
  /// Never throws: reminders are a convenience.
  static Future<void> plan({
    required VoteSettings settings,
    required DateTime? validFrom,
    required DateTime? validUntil,
    required Set<DateTime> votedDays,
    Set<DateTime> daysOff = const {},
  }) =>
      _serial(() async {
        if (!await _ready()) return;
        await _plugin.cancelAll();

        final now = DateTime.now();
        final first = settings.rideDateFor(now);
        final reminders = <({DateTime day, DateTime at})>[];
        for (var i = 0; i < _days; i++) {
          final day = DateTime(first.year, first.month, first.day + i);
          if (validFrom != null && day.isBefore(validFrom)) continue;
          if (validUntil != null && day.isAfter(validUntil)) break;
          if (votedDays.contains(day) || daysOff.contains(day)) continue;
          for (final at in settings.reminderTimesFor(day)) {
            if (at.isAfter(now)) reminders.add((day: day, at: at));
          }
        }
        if (reminders.isEmpty || !await _permitted()) return;

        final closes = VoteSettings.clock(settings.closesAt, long: true);
        for (final (id, reminder) in reminders.take(_maxPending).indexed) {
          final at = reminder.at;
          await _plugin.zonedSchedule(
            id: id,
            title: 'أكّد رحلة ${_dayName(reminder.day)}',
            body: 'لم تؤكد حضورك بعد. التصويت مفتوح حتى $closes.',
            scheduledDate: tz.TZDateTime(
                _cairo!, at.year, at.month, at.day, at.hour, at.minute),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      });

  /// Signed out, account deleted, or nothing to remind about.
  static Future<void> cancelAll() => _serial(() async {
        if (await _ready()) await _plugin.cancelAll();
      });

  /// One plan at a time, so an older plan never lands after a newer one.
  static Future<void> _serial(Future<void> Function() work) {
    final next = _queue.then((_) => work()).catchError((Object error) {
      debugPrint('Vote reminders: $error');
    });
    _queue = next;
    return next;
  }

  static Future<bool> _ready() async {
    if (!_supported) return false;
    if (_cairo != null) return true;
    tz_data.initializeTimeZones();
    // Vote times are Cairo times, wherever the phone is set.
    final cairo = tz.getLocation('Africa/Cairo');
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_basak'),
        // Asked when there is a first reminder to plan, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _cairo = cairo;
    return true;
  }

  /// Android 13+ and iOS ask the student once; a refusal is respected.
  static Future<bool> _permitted() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      if (await android.areNotificationsEnabled() == true) return true;
      if (_askedPermission) return false;
      _askedPermission = true;
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      // Shows the system prompt the first time only.
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
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
