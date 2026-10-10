import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/network/network_errors.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/features/notifications/data/notification_feed.dart';
import 'package:basak_mobile/features/notifications/data/notification_preferences.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/presentation/notification_style.dart';
import 'package:basak_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';

import 'support/notification_fakes.dart';

/// The Notification Center: what the server sends is read safely, shown by
/// day, paged, filtered, and marked read at once (and unmarked if the server
/// could not be told).
void main() {
  final noon = DateTime(2026, 10, 8, 12);

  /// [count] notifications, one an hour, the newest an hour before [noon].
  List<AppNotification> inbox(int count, {Set<int> read = const {}}) => [
        for (var i = 0; i < count; i++)
          note('n$i', 'إشعار $i', read: read.contains(i), at: noon.subtract(Duration(hours: i + 1))),
      ];

  ({ProviderContainer container, FakeNotificationsRepo repo}) signedIn(List<AppNotification> notes,
      {String? userId = 'student-1', int perPage = 30}) {
    final repo = FakeNotificationsRepo(notes)..perPage = perPage;
    final user = StateProvider<String?>((ref) => userId);
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(user)),
      notificationsRepoProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    container.listen(notificationFeedProvider, (_, __) {});
    return (container: container, repo: repo);
  }

  group('what the server sends', () {
    test('a notification is read with its type, category, texts and where it leads', () {
      final n = AppNotification.fromJson({
        'id': 'n1', 'type': 'subscription.approved', 'category': 'subscription', 'priority': 'high',
        'title': 'تم تفعيل اشتراكك', 'body': 'اشتراكك على خط المنصورة فعّال.',
        'title_en': 'Subscription approved', 'body_en': null,
        'created_at': '2026-10-08T09:00:00Z', 'sender_role': 'system', 'sender_name': '',
        'audience': '', 'read': false, 'mine': false,
        'data': {'route': 'subscription', 'subscription_id': 'sub-1', 'line_id': null},
      });
      expect(n.category, NotificationCategory.subscription);
      expect(n.highPriority, isTrue);
      expect(n.read, isFalse);
      expect(n.senderLabel, 'باصك');
      expect(n.data, {'route': 'subscription', 'subscription_id': 'sub-1'});
      final intent = NotificationIntent.of(n);
      expect(intent.destination, NotificationDestination.subscription);
      expect(intent.subscriptionId, 'sub-1');

      // Arabic unless the app runs in English and the server has an English text.
      expect(n.titleFor('ar'), 'تم تفعيل اشتراكك');
      expect(n.titleFor('en'), 'Subscription approved');
      expect(n.bodyFor('en'), 'اشتراكك على خط المنصورة فعّال.');
    });

    test('an unknown type or route still shows, and opens the Notification Center', () {
      final n = AppNotification.fromJson({
        'id': 'n2', 'type': 'loyalty.points_added', 'category': 'loyalty',
        'title': 'نقاط جديدة', 'body': 'أضيفت نقاط إلى حسابك', 'created_at': '2026-10-08T09:00:00Z',
        'data': {'route': 'rewards', 'points': 5},
      });
      expect(n.title, 'نقاط جديدة');
      expect(n.category, NotificationCategory.announcement);
      expect(NotificationIntent.of(n).destination, NotificationDestination.center);
      expect(notificationStyle(n.type, n.category).icon, notificationStyle('', n.category).icon);

      // What the released server sends today (no type, no data) reads the same way.
      final old = AppNotification.fromJson({
        'id': 'n3', 'title': 'تأخير الباص', 'body': 'سيتأخر', 'created_at': '2026-10-08T09:00:00Z',
        'sender_role': 'supervisor', 'sender_name': 'أحمد', 'audience': 'خط المنصورة', 'read': true,
      });
      expect(old.senderLabel, 'المشرف أحمد');
      expect(NotificationIntent.of(old).destination, NotificationDestination.center);

      // A category missing from the row is taken from the type.
      expect(NotificationCategory.parse(null, type: 'transport.delay'), NotificationCategory.transport);
    });

    test('a page keeps the unread count and the cursor, and skips rows it cannot read', () {
      final page = NotificationsPageData.fromJson({
        'items': [
          {'id': 'a', 'title': 'أ', 'created_at': '2026-10-08T09:00:00Z', 'read': false},
          {'title': 'no id'},
          'not a row',
        ],
        'unread': 7,
        'next_before': '2026-10-01T00:00:00Z',
      });
      expect(page.items.map((n) => n.id), ['a']);
      expect(page.unread, 7);
      expect(page.nextBefore, '2026-10-01T00:00:00Z');
      expect(NotificationsPageData.fromJson(null).items, isEmpty);
    });

    test('every type has its own look; categories have a name', () {
      const types = [
        'subscription.payment_received', 'subscription.approved', 'subscription.rejected',
        'subscription.expiring', 'subscription.expired', 'transport.delay', 'transport.arrived',
        'transport.departed', 'transport.cancelled', 'transport.return_departing',
      ];
      for (final type in types) {
        final style = notificationStyle(type, NotificationCategory.parse(null, type: type));
        expect(style.color, isNot(style.background), reason: type);
      }
      expect(notificationStyle('transport.cancelled', NotificationCategory.transport).color,
          notificationStyle('subscription.rejected', NotificationCategory.subscription).color);
      for (final category in NotificationCategory.values) {
        expect(notificationCategoryLabel(category), isNotEmpty);
      }
    });
  });

  group('by day', () {
    test('today, yesterday, then the date', () {
      expect(notificationDayLabel(DateTime(2026, 10, 8, 0, 5), noon), 'اليوم');
      expect(notificationDayLabel(DateTime(2026, 10, 7, 23, 59), noon), 'أمس');
      expect(notificationDayLabel(DateTime(2026, 10, 6), noon), '6 أكتوبر');
      expect(notificationDayLabel(DateTime(2025, 12, 31), noon), '31 ديسمبر 2025');
    });

    test('notifications are grouped under their day, newest day first', () {
      final groups = groupNotificationsByDay([
        note('a', 'أ', at: DateTime(2026, 10, 8, 11)),
        note('b', 'ب', at: DateTime(2026, 10, 8, 1)),
        note('c', 'ج', at: DateTime(2026, 10, 7, 22)),
        note('d', 'د', at: DateTime(2026, 9, 30, 9)),
      ], noon);
      expect(groups.map((g) => g.label), ['اليوم', 'أمس', '30 سبتمبر']);
      expect(groups.map((g) => g.items.map((n) => n.id).toList()), [
        ['a', 'b'],
        ['c'],
        ['d'],
      ]);
      expect(groupNotificationsByDay(const [], noon), isEmpty);
    });
  });

  group('pages', () {
    test('merging keeps each notification once, as sent last, newest first', () {
      final merged = mergeNotifications(
        [note('a', 'أ', at: noon), note('b', 'ب', at: noon.subtract(const Duration(hours: 2)))],
        [
          note('b', 'ب', read: true, at: noon.subtract(const Duration(hours: 2))),
          note('c', 'ج', at: noon.subtract(const Duration(hours: 1))),
        ],
      );
      expect(merged.map((n) => n.id), ['a', 'c', 'b']);
      expect(merged.last.read, isTrue);
    });

    test('a refreshed first page drops what was deleted and keeps the older pages', () {
      final loaded = inbox(6);
      final head = NotificationsPageData(
        // n1 was deleted on the server; a new one arrived.
        items: [note('new', 'جديد', at: noon), loaded[0], loaded[2]],
        unread: 4,
        nextBefore: loaded[2].createdAt.toIso8601String(),
      );
      expect(refreshHead(loaded, head).map((n) => n.id), ['new', 'n0', 'n2', 'n3', 'n4', 'n5']);
      // The whole inbox fits in one page: that page is the truth.
      expect(refreshHead(loaded, NotificationsPageData(items: [loaded[0]])).map((n) => n.id), ['n0']);
    });

    test('older pages are loaded on demand until the end, never twice', () async {
      final (:container, :repo) = signedIn(inbox(7), perPage: 3);
      final notifier = container.read(notificationFeedProvider.notifier);

      var feed = await container.read(notificationFeedProvider.future);
      expect(feed.items.map((n) => n.id), ['n0', 'n1', 'n2']);
      expect(feed.unread, 7, reason: 'the count is the server\'s, not the page\'s');
      expect(feed.hasMore, isTrue);

      // Two calls at once (a fast scroll) fetch the page once.
      await Future.wait([notifier.loadMore(), notifier.loadMore()]);
      expect(repo.pageRequests, 2);
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.map((n) => n.id), ['n0', 'n1', 'n2', 'n3', 'n4', 'n5']);

      await notifier.loadMore();
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.length, 7);
      expect(feed.hasMore, isFalse);
      final requests = repo.pageRequests;
      await notifier.loadMore();
      expect(repo.pageRequests, requests, reason: 'nothing is asked for after the end');
    });

    test('a live refresh adds the new notification and keeps what was scrolled to', () async {
      final (:container, :repo) = signedIn(inbox(5), perPage: 3);
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);
      await notifier.loadMore();

      repo.inbox.add(note('new', 'جديد', at: noon));
      container.invalidate(notificationFeedProvider);
      final during = container.read(notificationFeedProvider);
      expect(during.hasValue, isTrue, reason: 'no blank list while refreshing');
      final feed = await container.read(notificationFeedProvider.future);
      expect(feed.items.map((n) => n.id), ['new', 'n0', 'n1', 'n2', 'n3', 'n4']);
      expect(feed.unread, 6);
      expect(feed.hasMore, isFalse);
    });

    test('a failed "load more" keeps the list and can be retried', () async {
      final (:container, :repo) = signedIn(inbox(5), perPage: 3);
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);

      repo.offline = true;
      await notifier.loadMore();
      var feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.length, 3);
      expect(isNetworkFailure(feed.moreError!), isTrue);
      expect(feed.loadingMore, isFalse);

      repo.offline = false;
      await notifier.loadMore();
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.length, 5);
      expect(feed.moreError, isNull);
    });

    test('another account starts from nothing of the first one', () async {
      final repo = FakeNotificationsRepo(inbox(2));
      final user = StateProvider<String?>((ref) => 'a');
      final container = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWith((ref) => ref.watch(user)),
        notificationsRepoProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      container.listen(notificationFeedProvider, (_, __) {});
      expect((await container.read(notificationFeedProvider.future)).items.length, 2);

      container.read(user.notifier).state = null;
      expect((await container.read(notificationFeedProvider.future)).items, isEmpty);
      expect(container.read(unreadNotificationsProvider), 0);

      repo.inbox = [note('b1', 'لحساب آخر')];
      container.read(user.notifier).state = 'b';
      expect((await container.read(notificationFeedProvider.future)).items.map((n) => n.id), ['b1']);
    });
  });

  group('unread filter', () {
    test('shows the unread ones at once, then what the server says', () async {
      final (:container, :repo) = signedIn(inbox(6, read: {0, 2, 4}), perPage: 3);
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);

      final switching = notifier.setUnreadOnly(true);
      var feed = container.read(notificationFeedProvider).value!;
      expect(feed.unreadOnly, isTrue);
      expect(feed.items.map((n) => n.id), ['n1'], reason: 'what is already loaded, before any answer');
      await switching;
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.map((n) => n.id), ['n1', 'n3', 'n5'], reason: 'unread ones of pages not loaded yet');
      expect(feed.unread, 3);
      expect(feed.switching, isFalse);

      await notifier.setUnreadOnly(false);
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.unreadOnly, isFalse);
      expect(feed.items.map((n) => n.id), ['n0', 'n1', 'n2']);
      expect(repo.pageRequests, 3);
    });

    test('without a connection it still filters what is on the phone', () async {
      final (:container, :repo) = signedIn(inbox(4, read: {1}));
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);
      repo.offline = true;
      await notifier.setUnreadOnly(true);
      final feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.map((n) => n.id), ['n0', 'n2', 'n3']);
      expect(feed.switching, isFalse);
    });
  });

  group('marking read', () {
    test('one notification is read at once and the count follows', () async {
      final (:container, :repo) = signedIn(inbox(3));
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);

      final marking = notifier.markRead(['n1']);
      var feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.firstWhere((n) => n.id == 'n1').read, isTrue, reason: 'before the server answers');
      expect(feed.unread, 2);
      expect(container.read(unreadNotificationsProvider), 2);
      await marking;
      expect(repo.marked, [
        ['n1']
      ]);
      // Marking it again changes nothing.
      await notifier.markRead(['n1']);
      expect(container.read(notificationFeedProvider).value!.unread, 2);
    });

    test('if the server cannot be told, the mark is taken back and the error is told', () async {
      final (:container, :repo) = signedIn(inbox(3, read: {2}));
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);

      repo.offline = true;
      await expectLater(notifier.markRead(['n0']), throwsA(predicate(isNetworkFailure)));
      var feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.first.read, isFalse);
      expect(feed.unread, 2);

      await expectLater(notifier.markAllRead(), throwsA(anything));
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.map((n) => n.read), [false, false, true], reason: 'only what it changed is undone');
      expect(feed.unread, 2);
    });

    test('"mark all" also covers pages that were never loaded', () async {
      final (:container, :repo) = signedIn(inbox(6), perPage: 2);
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);
      await notifier.markAllRead();
      expect(repo.marked, [null]);
      final feed = container.read(notificationFeedProvider).value!;
      expect(feed.unread, 0);
      expect(feed.items.every((n) => n.read), isTrue);
    });

    test('a refresh landing before the server confirmed does not show it unread again', () async {
      final (:container, :repo) = signedIn(inbox(2));
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);

      // The mark is still on its way when a live event re-reads the first page.
      repo.markGate = Completer<void>();
      final marking = notifier.markRead(['n0']);
      container.invalidate(notificationFeedProvider);
      final feed = await container.read(notificationFeedProvider.future);
      expect(feed.items.first.read, isTrue);
      expect(feed.unread, 1);
      repo.markGate!.complete();
      await marking;
      expect(container.read(notificationFeedProvider).value!.unread, 1);
    });

    test('read on another phone: the count drops and older pages follow', () async {
      final (:container, :repo) = signedIn(inbox(4), perPage: 2);
      final notifier = container.read(notificationFeedProvider.notifier);
      await container.read(notificationFeedProvider.future);
      await notifier.loadMore();

      // The live channel says READ; the first page now reports nothing unread.
      repo.inbox = [for (final n in repo.inbox) n.markedRead()];
      container.invalidate(notificationFeedProvider);
      final feed = await container.read(notificationFeedProvider.future);
      expect(feed.unread, 0);
      expect(feed.items.length, 4);
      expect(feed.items.every((n) => n.read), isTrue);
    });

    test('a tapped push is reported as opened and read, also before the inbox loaded', () async {
      final (:container, :repo) = signedIn(inbox(2));
      final notifier = container.read(notificationFeedProvider.notifier);
      // Cold start: the tap arrives while the first page is still on its way.
      await notifier.opened('n1');
      expect(repo.openedIds, ['n1']);
      var feed = await container.read(notificationFeedProvider.future);
      expect(feed.items.firstWhere((n) => n.id == 'n1').read, isTrue);
      expect(feed.unread, 1);

      // Offline: nothing is shown to the user, and it stays unread.
      repo.offline = true;
      await notifier.opened('n0');
      feed = container.read(notificationFeedProvider).value!;
      expect(feed.items.firstWhere((n) => n.id == 'n0').read, isFalse);
    });
  });

  group('preferences', () {
    test('a switch moves at once, and stays when the server agrees', () async {
      final (:container, :repo) = signedIn(const []);
      container.listen(notificationPreferencesProvider, (_, __) {});
      final notifier = container.read(notificationPreferencesProvider.notifier);
      expect((await container.read(notificationPreferencesProvider.future)).pushEnabled, isTrue);

      final saving = notifier.setCategory(NotificationCategory.announcement, false);
      expect(container.read(notificationPreferencesProvider).value!.allows(NotificationCategory.announcement),
          isFalse, reason: 'before the server answers');
      await saving;
      expect(repo.savedPreferences.categoriesJson,
          {'subscription': true, 'transport': true, 'announcement': false, 'reminder': true});
      expect(repo.savedPreferences.pushEnabled, isTrue);
    });

    test('a switch moves back when the server refuses or cannot be reached', () async {
      final (:container, :repo) = signedIn(const []);
      container.listen(notificationPreferencesProvider, (_, __) {});
      final notifier = container.read(notificationPreferencesProvider.notifier);
      await container.read(notificationPreferencesProvider.future);

      repo.offline = true;
      await expectLater(notifier.setPushEnabled(false), throwsA(predicate(isNetworkFailure)));
      expect(container.read(notificationPreferencesProvider).value!.pushEnabled, isTrue);

      repo
        ..offline = false
        ..refusal = 'غير مسموح';
      await expectLater(notifier.setCategory(NotificationCategory.transport, false), throwsA(anything));
      expect(container.read(notificationPreferencesProvider).value!.allows(NotificationCategory.transport),
          isTrue);
      expect(repo.savedPreferences.pushEnabled, isTrue);
    });

    test('preferences are read safely', () async {
      final preferences = NotificationPreferences.fromJson({
        'push_enabled': false,
        'categories': {'subscription': true, 'transport': false, 'reminder': false, 'future_one': true},
      });
      expect(preferences.pushEnabled, isFalse);
      expect(preferences.allows(NotificationCategory.transport), isFalse);
      expect(preferences.allows(NotificationCategory.announcement), isTrue, reason: 'missing means on');
      expect(NotificationPreferences.fromJson(null).pushEnabled, isTrue);
    });
  });

  group('the screen', () {
    Widget app(FakeNotificationsRepo repo, {NotificationRouter? router}) => ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue('student-1'),
            notificationsRepoProvider.overrideWithValue(repo),
            if (router != null) notificationRouterProvider.overrideWithValue(router),
          ],
          child: const MaterialApp(
            home: Directionality(textDirection: TextDirection.rtl, child: NotificationsPage()),
          ),
        );

    testWidgets('groups by day, filters unread, and opening one marks it read', (tester) async {
      final now = DateTime.now();
      final repo = FakeNotificationsRepo([
        note('a', 'تم تفعيل اشتراكك', type: 'subscription.approved', at: now.subtract(const Duration(minutes: 5)),
            data: {'route': 'subscription', 'subscription_id': 'sub-9'}),
        note('b', 'إجازة رسمية', read: true, at: now.subtract(const Duration(minutes: 20))),
        note('c', 'تأخير الباص', type: 'transport.delay', at: now.subtract(const Duration(days: 3))),
      ]);
      final shell = FakeShell();
      final router = NotificationRouter(currentUserId: () => 'student-1')..attach('student-1', shell);
      await tester.pumpWidget(app(repo, router: router));
      await tester.pumpAndSettle();

      expect(find.text('اليوم'), findsOneWidget);
      expect(find.text('غير المقروءة · 2'), findsOneWidget);
      expect(find.text('تأخير الباص'), findsOneWidget);

      await tester.tap(find.text('غير المقروءة · 2'));
      await tester.pumpAndSettle();
      expect(find.text('إجازة رسمية'), findsNothing);
      expect(find.text('تم تفعيل اشتراكك'), findsOneWidget);

      await tester.tap(find.text('الكل'));
      await tester.pumpAndSettle();
      expect(find.text('إجازة رسمية'), findsOneWidget);

      // Opening it marks it read and goes where it leads.
      await tester.tap(find.text('تم تفعيل اشتراكك'));
      await tester.pumpAndSettle();
      expect(repo.marked, [
        ['a']
      ]);
      expect(find.text('غير المقروءة · 1'), findsOneWidget);
      expect(shell.shown, [NotificationDestination.subscription]);
      expect(shell.intents.single.subscriptionId, 'sub-9');
      expect(repo.openedIds, isEmpty, reason: 'only pushes and banners count as opened');

      // A read announcement leads nowhere else: its whole text opens in a sheet.
      await tester.tap(find.text('إجازة رسمية'));
      await tester.pumpAndSettle();
      expect(shell.shown.length, 1);
      expect(repo.marked.length, 1);
      expect(find.text('نص إجازة رسمية'), findsNWidgets(2), reason: 'the row, and the sheet over it');
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();
      expect(find.text('إغلاق'), findsNothing);
    });

    testWidgets('an offline mark is undone and says why', (tester) async {
      final repo = FakeNotificationsRepo([note('a', 'إجازة رسمية')]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      repo.offline = true;
      await tester.tap(find.text('قراءة الكل'));
      await tester.pumpAndSettle();
      expect(find.text(offlineActionMessage), findsOneWidget);
      expect(find.text('غير المقروءة · 1'), findsOneWidget);
    });

    testWidgets('empty states: nothing yet, and nothing unread', (tester) async {
      final repo = FakeNotificationsRepo([note('a', 'قديم', read: true)]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('غير المقروءة'));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد إشعارات غير مقروءة'), findsOneWidget);

      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          sessionUserIdProvider.overrideWithValue('student-2'),
          notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo()),
        ],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: NotificationsPage()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد تنبيهات بعد'), findsOneWidget);
    });

    testWidgets('scrolling to the end loads the older page', (tester) async {
      final now = DateTime.now();
      final repo = FakeNotificationsRepo([
        for (var i = 0; i < 9; i++) note('n$i', 'إشعار رقم $i', at: now.subtract(Duration(minutes: i + 1))),
      ])
        ..perPage = 6;
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      expect(repo.pageRequests, 1);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(repo.pageRequests, 2);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('إشعار رقم 8'), findsOneWidget);
      expect(repo.pageRequests, 2, reason: 'the end was reached');
    });
  });
}
