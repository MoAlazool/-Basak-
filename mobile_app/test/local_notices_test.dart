import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/local/inbox_announcer.dart';
import 'package:basak_mobile/features/notifications/local/local_notifier.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySeen implements SeenNotices {
  final Map<String, List<String>> saved = {};

  @override
  Future<Set<String>?> read(String userId) async => saved[userId]?.toSet();

  @override
  Future<void> write(String userId, Iterable<String> ids) async => saved[userId] = ids.toList();
}

AppNotification _notice(String id,
        {bool read = false, bool mine = false, int minutesAgo = 0, String type = 'subscription.approved'}) =>
    AppNotification(
      id: id,
      type: type,
      category: NotificationCategory.subscription,
      title: 'عنوان $id',
      body: 'نص $id',
      createdAt: DateTime(2026, 10, 11, 12).subtract(Duration(minutes: minutesAgo)),
      senderRole: 'system',
      senderName: '',
      audience: '',
      read: read,
      mine: mine,
      data: const {'route': 'subscription', 'subscription_id': 'sub-1'},
    );

void main() {
  group('the subscription\'s two dates, planned on the phone', () {
    final end = DateTime(2026, 10, 30);

    test('three days before the last day and the day after it, at nine', () {
      final notices = SubscriptionReminders.noticesFor(endDate: end, daily: false, now: DateTime(2026, 10, 11, 12));
      expect([for (final n in notices) n.type], ['subscription.expiring', 'subscription.expired']);
      expect(notices[0].at, DateTime(2026, 10, 27, 9));
      expect(notices[1].at, DateTime(2026, 10, 31, 9));
      expect(notices[0].id, LocalNotifier.subscriptionExpiring);
      expect(notices[1].id, LocalNotifier.subscriptionExpired);
    });

    test('a moment already gone is not planned', () {
      final late = SubscriptionReminders.noticesFor(endDate: end, daily: false, now: DateTime(2026, 10, 27, 9, 1));
      expect([for (final n in late) n.type], ['subscription.expired']);
      expect(SubscriptionReminders.noticesFor(endDate: end, daily: false, now: DateTime(2026, 11, 1)), isEmpty);
    });

    test('a day ticket gets none, nor a subscription with no end', () {
      expect(SubscriptionReminders.noticesFor(endDate: end, daily: true, now: DateTime(2026, 10, 11)), isEmpty);
      expect(SubscriptionReminders.noticesFor(endDate: null, daily: false, now: DateTime(2026, 10, 11)), isEmpty);
    });

    test('a month\'s end is crossed correctly', () {
      final notices = SubscriptionReminders.noticesFor(
          endDate: DateTime(2026, 10, 31), daily: false, now: DateTime(2026, 10, 1));
      expect(notices[0].at, DateTime(2026, 10, 28, 9));
      expect(notices[1].at, DateTime(2026, 11, 1, 9));
    });
  });

  group('each kind of local notification keeps to its own numbers', () {
    test('cancelling the vote reminders leaves the subscription dates and the inbox alone', () {
      bool vote(int id) => LocalNotifier.inRange(id, LocalNotifier.voteFirst, 64);
      expect(vote(0), isTrue);
      expect(vote(LocalNotifier.voteMax - 1), isTrue);
      expect(vote(63), isTrue, reason: 'what an earlier version planned is still cleared');
      expect(vote(LocalNotifier.subscriptionExpiring), isFalse);
      expect(vote(LocalNotifier.subscriptionExpired), isFalse);
      expect(vote(LocalNotifier.inboxId('7b0c9a52-0000-4000-8000-000000000001')), isFalse);
    });

    test('cancelling the subscription dates leaves the vote reminders alone', () {
      bool dates(int id) => LocalNotifier.inRange(id, LocalNotifier.subscriptionExpiring, 2);
      expect(dates(LocalNotifier.subscriptionExpiring), isTrue);
      expect(dates(LocalNotifier.subscriptionExpired), isTrue);
      expect(dates(LocalNotifier.voteMax - 1), isFalse);
      expect(dates(LocalNotifier.inboxId('a')), isFalse);
    });

    test('everything fits in what iOS keeps pending', () {
      expect(LocalNotifier.voteMax + 2, lessThanOrEqualTo(64));
    });

    test('an inbox notification is always shown under the same number', () {
      const id = '7b0c9a52-0000-4000-8000-000000000001';
      expect(LocalNotifier.inboxId(id), LocalNotifier.inboxId(id));
      expect(LocalNotifier.inboxId(id), isNot(LocalNotifier.inboxId('7b0c9a52-0000-4000-8000-000000000002')));
      expect(LocalNotifier.inboxId(id), greaterThanOrEqualTo(1000));
      expect(LocalNotifier.inboxId(id), lessThan(1 << 31), reason: 'Android takes a 32-bit number');
    });

    test('a tap carries ids and the route only, and leads where a push would', () {
      final data = LocalNotifier.dataOf(LocalNotifier.payloadOf(LocalNotifier.tapData(_notice('n1'))));
      expect(data, {
        'route': 'subscription',
        'subscription_id': 'sub-1',
        'notification_id': 'n1',
        'type': 'subscription.approved',
        'category': 'subscription',
      });
      final intent = NotificationIntent.fromPush(data);
      expect(intent.notificationId, 'n1');
      expect(intent.destination, NotificationDestination.subscription);
      expect(LocalNotifier.dataOf('not json'), isEmpty);
      expect(LocalNotifier.dataOf(null), isEmpty);
    });
  });

  group('what is new in the inbox', () {
    test('the first read on a phone announces nothing: it is all known', () {
      final arrivals = newArrivals([_notice('a'), _notice('b')], null);
      expect(arrivals.fresh, isEmpty);
      expect(arrivals.seen, containsAll(['a', 'b']));
    });

    test('only unread notifications from someone else, not seen before', () {
      final arrivals = newArrivals(
          [_notice('new'), _notice('read', read: true), _notice('own', mine: true), _notice('old')], {'old'});
      expect([for (final n in arrivals.fresh) n.id], ['new']);
      expect(arrivals.seen, containsAll(['new', 'read', 'own', 'old']));
    });

    test('older pages scrolled to are not news', () {
      final items = [
        for (var i = 0; i < NotificationsRepository.pageSize + 5; i++) _notice('n$i', minutesAgo: i),
      ];
      final arrivals = newArrivals(items, {'n0'});
      expect(arrivals.fresh.length, NotificationsRepository.pageSize - 1);
      expect(arrivals.fresh.any((n) => n.id == 'n${NotificationsRepository.pageSize}'), isFalse);
    });

    test('the wording counts as Arabic does', () {
      expect(newNoticesTitle(2), 'لديك إشعاران جديدان');
      expect(newNoticesTitle(3), 'لديك 3 إشعارات جديدة');
      expect(newNoticesTitle(11), 'لديك 11 إشعاراً جديداً');
    });
  });

  group('telling the user without a push', () {
    late _MemorySeen seen;
    late List<PushMessage> banners;
    late List<String> system;
    var foreground = true;
    var pushReaches = false;

    InboxAnnouncer announcer() => InboxAnnouncer(
          store: seen,
          inForeground: () => foreground,
          pushReaches: () => pushReaches,
          showBanner: banners.add,
          showSystem: (n) async {
            system.add(n.id);
            return true;
          },
        );

    setUp(() {
      seen = _MemorySeen()..saved['user-a'] = ['old'];
      banners = [];
      system = [];
      foreground = true;
      pushReaches = false;
    });

    test('app on screen: one new notification is the banner, once', () async {
      final a = announcer();
      await a.inboxRead('user-a', [_notice('n1'), _notice('old')]);
      expect(banners.single.title, 'عنوان n1');
      expect(banners.single.notificationId, 'n1');
      expect(banners.single.intent.destination, NotificationDestination.subscription);
      expect(system, isEmpty);

      // The same inbox read again (a refresh, the app opened again): no repeat.
      await a.inboxRead('user-a', [_notice('n1'), _notice('old')]);
      await announcer().inboxRead('user-a', [_notice('n1'), _notice('old')]);
      expect(banners.length, 1);
    });

    test('several at once (the app was away): one banner that opens the inbox', () async {
      await announcer().inboxRead('user-a', [_notice('n3'), _notice('n2'), _notice('n1'), _notice('old')]);
      expect(banners.single.title, 'لديك 3 إشعارات جديدة');
      expect(banners.single.intent.destination, NotificationDestination.center);
    });

    test('app not on screen: system notifications, a few at most, newest last', () async {
      foreground = false;
      await announcer().inboxRead('user-a', [for (var i = 5; i >= 1; i--) _notice('n$i'), _notice('old')]);
      expect(banners, isEmpty);
      expect(system, ['n3', 'n4', 'n5']);

      // Back in the app: they were already announced.
      foreground = true;
      await announcer().inboxRead('user-a', [for (var i = 5; i >= 1; i--) _notice('n$i'), _notice('old')]);
      expect(banners, isEmpty);
    });

    test('a phone that push reaches is told by the push: nothing here, but remembered', () async {
      pushReaches = true;
      await announcer().inboxRead('user-a', [_notice('n1'), _notice('old')]);
      expect(banners, isEmpty);
      expect(system, isEmpty);

      pushReaches = false;
      await announcer().inboxRead('user-a', [_notice('n1'), _notice('old')]);
      expect(banners, isEmpty, reason: 'the push already told them');
    });

    test('another account on the phone starts from its own inbox', () async {
      await announcer().inboxRead('user-b', [_notice('n1')]);
      expect(banners, isEmpty, reason: 'first read on this phone');
      await announcer().inboxRead('user-b', [_notice('n2'), _notice('n1')]);
      expect(banners.single.notificationId, 'n2');
    });
  });
}
