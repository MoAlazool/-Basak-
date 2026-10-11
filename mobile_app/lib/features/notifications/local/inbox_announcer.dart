import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/notifications_repository.dart';
import '../push/push_messaging.dart';
import 'local_notifier.dart';

/// Which inbox notifications this phone already told its user about, per
/// account. Kept on the device, so a notification is announced once whether
/// the app was open, in the background or started again since.
class SeenNotices {
  const SeenNotices();

  /// As many ids as are remembered: several pages of the inbox.
  static const kept = 200;

  static String _key(String userId) => 'basak.notices.seen.$userId';

  /// Null when nothing was ever remembered for [userId] on this phone.
  Future<Set<String>?> read(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(userId))?.toSet();
  }

  Future<void> write(String userId, Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(userId), ids.toList());
  }
}

/// What the newest page of the inbox holds that its user has not been told of.
///
/// [seen] is what was remembered before (null on this account's first read on
/// this phone: everything already there counts as known, nothing is announced).
/// Only the newest page is looked at, so scrolling back to older unread
/// notifications announces nothing.
({List<AppNotification> fresh, List<String> seen}) newArrivals(
    List<AppNotification> items, Set<String>? seen) {
  final head = items.take(NotificationsRepository.pageSize).toList();
  final fresh = seen == null
      ? const <AppNotification>[]
      : [
          for (final n in head)
            if (!n.read && !n.mine && !seen.contains(n.id)) n,
        ];
  final ids = <String>{for (final n in head) n.id, ...?seen};
  return (fresh: fresh, seen: ids.take(SeenNotices.kept).toList());
}

/// «لديك 3 إشعارات جديدة»
String newNoticesTitle(int count) => switch (count) {
      1 => 'لديك إشعار جديد',
      2 => 'لديك إشعاران جديدان',
      <= 10 => 'لديك $count إشعارات جديدة',
      _ => 'لديك $count إشعاراً جديداً',
    };

/// Tells the user about notifications that reached the inbox without a push:
/// the server could not push to this phone, but the app is running (a live
/// event arrived, the app was opened again, or the system woke it for a
/// moment) and has just read them.
///
/// With the app on screen that is the banner inside the app; otherwise a
/// system notification. A phone that push reaches is told by the push
/// itself, so nothing is shown here; what it has seen is still remembered.
class InboxAnnouncer {
  final SeenNotices store;

  /// Whether the app is on screen right now.
  final bool Function() inForeground;

  /// Whether the server pushes to this phone (see PushController.reaches).
  final bool Function() pushReaches;
  final void Function(PushMessage message) showBanner;
  final Future<bool> Function(AppNotification notification) showSystem;

  InboxAnnouncer({
    this.store = const SeenNotices(),
    required this.inForeground,
    required this.pushReaches,
    required this.showBanner,
    Future<bool> Function(AppNotification notification)? showSystem,
  }) : showSystem = showSystem ?? LocalNotifier.showInbox;

  /// At most this many system notifications at once; the rest are in the inbox.
  static const systemAtOnce = 3;

  Future<void> _queue = Future.value();

  /// Looks at the inbox as just read for [userId]. One at a time, in order.
  /// Never throws.
  Future<void> inboxRead(String userId, List<AppNotification> items) {
    final next = _queue.then((_) => _announce(userId, items)).catchError((Object error) {
      debugPrint('Inbox announcer: $error');
    });
    _queue = next;
    return next;
  }

  Future<void> _announce(String userId, List<AppNotification> items) async {
    final arrivals = newArrivals(items, await store.read(userId));
    await store.write(userId, arrivals.seen);
    final fresh = arrivals.fresh;
    if (fresh.isEmpty || pushReaches()) return;
    if (!inForeground()) {
      // Oldest first, so the newest ends on top of the tray.
      for (final notification in fresh.take(systemAtOnce).toList().reversed) {
        await showSystem(notification);
      }
      return;
    }
    if (fresh.length == 1) {
      final only = fresh.single;
      showBanner(PushMessage(title: only.title, body: only.body, data: LocalNotifier.tapData(only)));
    } else {
      // Opens the Notification Center, where they all are.
      showBanner(PushMessage(title: newNoticesTitle(fresh.length), body: fresh.first.title));
    }
  }
}
