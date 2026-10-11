import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../notifications/data/notifications_repository.dart';
import '../../../notifications/local/local_notifier.dart';

/// One of the two notices about a subscription's last day.
class SubscriptionNotice {
  final int id;
  final String type;

  /// The Cairo day and hour it is shown at.
  final DateTime at;
  final String title;
  final String body;

  const SubscriptionNotice({
    required this.id,
    required this.type,
    required this.at,
    required this.title,
    required this.body,
  });
}

/// "Your subscription ends in 3 days" and "your subscription has ended", shown
/// by the phone itself on the day, as the vote reminders are.
///
/// The server sends the same two as pushes (notifications_daily, 09:00 Cairo).
/// A phone that push reaches therefore plans none here; a phone it does not
/// reach (no push in this build, or none allowed for it) plans its own, since
/// the dates are already known to it.
class SubscriptionReminders {
  SubscriptionReminders._();

  static Future<void> _queue = Future.value();

  /// When the server's daily notices go out, Cairo time.
  static const hour = 9;

  /// The notices for a subscription ending on [endDate] that are still to
  /// come at [now] (Cairo wall clock). The wording is the server templates'
  /// (`subscription.expiring`, `subscription.expired`). A day ticket gets none.
  @visibleForTesting
  static List<SubscriptionNotice> noticesFor({
    required DateTime? endDate,
    required bool daily,
    required DateTime now,
  }) {
    if (endDate == null || daily) return const [];
    final notices = [
      SubscriptionNotice(
        id: LocalNotifier.subscriptionExpiring,
        type: 'subscription.expiring',
        at: DateTime(endDate.year, endDate.month, endDate.day - 3, hour),
        title: 'اشتراكك ينتهي قريباً',
        body: 'ينتهي اشتراكك خلال 3 أيام. جدّده حتى لا تنقطع الخدمة.',
      ),
      SubscriptionNotice(
        id: LocalNotifier.subscriptionExpired,
        type: 'subscription.expired',
        at: DateTime(endDate.year, endDate.month, endDate.day + 1, hour),
        title: 'انتهى اشتراكك',
        body: 'انتهت مدة اشتراكك. يمكنك الاشتراك من جديد من التطبيق.',
      ),
    ];
    return [
      for (final notice in notices)
        if (notice.at.isAfter(now)) notice,
    ];
  }

  /// Replaces the planned notices with those of the running subscription
  /// [subscriptionId]. With [pushReaches] the server tells this phone itself,
  /// so nothing is planned. Never throws: reminders are a convenience.
  static Future<void> plan({
    required String subscriptionId,
    required DateTime? endDate,
    required bool daily,
    required bool pushReaches,
  }) =>
      _serial(() async {
        if (!await LocalNotifier.ready()) return;
        await _cancelOwn();
        if (pushReaches) return;
        final cairo = LocalNotifier.cairo;
        final now = tz.TZDateTime.now(cairo);
        final notices = noticesFor(
          endDate: endDate,
          daily: daily,
          now: DateTime(now.year, now.month, now.day, now.hour, now.minute),
        );
        if (notices.isEmpty || !await LocalNotifier.permitted(ask: true)) return;
        for (final notice in notices) {
          await LocalNotifier.plugin.zonedSchedule(
            id: notice.id,
            title: notice.title,
            body: notice.body,
            scheduledDate: tz.TZDateTime(cairo, notice.at.year, notice.at.month, notice.at.day, notice.at.hour),
            notificationDetails: LocalNotifier.detailsFor(NotificationCategory.subscription),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: LocalNotifier.payloadOf({
              'type': notice.type,
              'category': NotificationCategory.subscription.name,
              'route': 'subscription',
              'subscription_id': subscriptionId,
            }),
          );
        }
      });

  /// No running subscription: nothing to announce.
  static Future<void> cancelAll() => _serial(_cancelOwn);

  static Future<void> _cancelOwn() => LocalNotifier.cancelRange(LocalNotifier.subscriptionExpiring, 2);

  /// One plan at a time, so an older plan never lands after a newer one.
  static Future<void> _serial(Future<void> Function() work) {
    final next = _queue.then((_) => work()).catchError((Object error) {
      debugPrint('Subscription reminders: $error');
    });
    _queue = next;
    return next;
  }
}
