import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/features/notifications/notification_router.dart';

import 'support/notification_fakes.dart';

/// One router for every tap on a notification: where it leads, when it has to
/// wait for the app to be ready, and when it must not be shown at all.
void main() {
  NotificationIntent push(String id, {String route = 'subscription'}) => NotificationIntent.fromPush({
        'notification_id': id, 'type': 'subscription.approved', 'category': 'subscription',
        'route': route, 'subscription_id': 'sub-1',
      });

  test('a route leads to its place; anything unknown to the Notification Center', () {
    expect(NotificationDestination.parse('subscription'), NotificationDestination.subscription);
    expect(NotificationDestination.parse('home'), NotificationDestination.home);
    expect(NotificationDestination.parse('card'), NotificationDestination.card);
    expect(NotificationDestination.parse('notifications'), NotificationDestination.center);
    expect(NotificationDestination.parse('something_new'), NotificationDestination.center);
    expect(NotificationDestination.parse(null), NotificationDestination.center);
  });

  test('a push carries ids only, and is read whatever else is in it', () {
    final intent = NotificationIntent.fromPush({
      'notification_id': 'n1', 'type': 'transport.delay', 'route': 'home',
      'line_id': 'line-1', 'trip_id': '', 'badge': 3, 'nested': {'x': 1},
    });
    expect(intent.notificationId, 'n1');
    expect(intent.destination, NotificationDestination.home);
    expect(intent.data, {'notification_id': 'n1', 'type': 'transport.delay', 'route': 'home', 'line_id': 'line-1'});
    // Nothing of ours in it (a test message from the console): the inbox opens.
    final bare = NotificationIntent.fromPush(const {});
    expect(bare.notificationId, isNull);
    expect(bare.destination, NotificationDestination.center);
  });

  test('list, push and banner taps all go through the shell, each to its place', () {
    final shell = FakeShell();
    final opened = <String?>[];
    final router = NotificationRouter(currentUserId: () => 'a', onOpened: (i) => opened.add(i.notificationId))
      ..attach('a', shell);

    expect(router.open(push('n1'), NotificationTapSource.list), isTrue);
    expect(router.open(push('n2', route: 'home'), NotificationTapSource.push), isTrue);
    expect(router.open(push('n3', route: 'card'), NotificationTapSource.banner), isTrue);
    expect(router.open(push('n4', route: 'nowhere'), NotificationTapSource.push), isTrue);
    expect(shell.shown, [
      NotificationDestination.subscription,
      NotificationDestination.home,
      NotificationDestination.card,
      NotificationDestination.center,
    ]);
    expect(shell.intents.first.subscriptionId, 'sub-1');
    expect(opened, ['n2', 'n3', 'n4'], reason: 'pushes and banners are reported as opened; list rows are not');
  });

  test('a row that leads to the Notification Center stays where it is', () {
    final shell = FakeShell();
    final router = NotificationRouter(currentUserId: () => 'a')..attach('a', shell);
    expect(router.open(push('n1', route: 'notifications'), NotificationTapSource.list), isTrue);
    expect(shell.shown, isEmpty);
  });

  test('a supervisor has no subscription or card: those open the Notification Center', () {
    final shell = FakeShell(const {NotificationDestination.home, NotificationDestination.center});
    final router = NotificationRouter(currentUserId: () => 'sup')..attach('sup', shell);
    router.open(push('n1'), NotificationTapSource.push);
    router.open(push('n2', route: 'card'), NotificationTapSource.banner);
    router.open(push('n3', route: 'home'), NotificationTapSource.push);
    expect(shell.shown,
        [NotificationDestination.center, NotificationDestination.center, NotificationDestination.home]);
  });

  test('the same notification is acted on once, however many times it is reported', () {
    final shell = FakeShell();
    final opened = <String?>[];
    final router = NotificationRouter(currentUserId: () => 'a', onOpened: (i) => opened.add(i.notificationId))
      ..attach('a', shell);

    // The message that opened the app is also reported as a tap.
    expect(router.open(push('n1'), NotificationTapSource.push), isTrue);
    expect(router.open(push('n1'), NotificationTapSource.push), isFalse);
    // The banner and the system notification of one message.
    expect(router.open(push('n1'), NotificationTapSource.banner), isFalse);
    expect(shell.shown.length, 1);
    expect(opened, ['n1']);

    // Its row in the list can still be opened, as often as the user likes.
    expect(router.open(push('n1'), NotificationTapSource.list), isTrue);
    expect(router.open(push('n1'), NotificationTapSource.list), isTrue);
    expect(shell.shown.length, 3);
    expect(opened, ['n1']);
  });

  test('a tap that comes before the app is ready waits for the shell of its account', () {
    String? signedIn = 'a'; // the session restored from the device
    final opened = <String?>[];
    final router =
        NotificationRouter(currentUserId: () => signedIn, onOpened: (i) => opened.add(i.notificationId));

    // Cold start from a push: no screen is up yet.
    expect(router.open(push('n1'), NotificationTapSource.push), isTrue);
    expect(router.hasWaiting, isTrue);
    expect(opened, isEmpty, reason: 'nothing is reported until it is actually shown');

    // The role is known, the session is confirmed: same account.
    router.accountChanged('a');
    expect(router.hasWaiting, isTrue);

    final shell = FakeShell();
    router.attach('a', shell);
    expect(shell.shown, [NotificationDestination.subscription]);
    expect(opened, ['n1']);
    expect(router.hasWaiting, isFalse);

    // Shown once: a later shell (after a rebuild) does not get it again.
    final again = FakeShell();
    router.attach('a', again);
    expect(again.shown, isEmpty);
  });

  test('a waiting tap is dropped when another account, or nobody, ends up signed in', () {
    String? signedIn = 'a';
    final opened = <String?>[];
    final router =
        NotificationRouter(currentUserId: () => signedIn, onOpened: (i) => opened.add(i.notificationId));

    // The restored session turns out to be expired; someone else signs in.
    router.open(push('n1'), NotificationTapSource.push);
    signedIn = null;
    router.accountChanged(null);
    expect(router.hasWaiting, isFalse);
    signedIn = 'b';
    router.accountChanged('b');
    final shellB = FakeShell();
    router.attach('b', shellB);
    expect(shellB.shown, isEmpty);
    expect(opened, isEmpty);

    // Still waiting when the other account's shell appears without a sign-out in between.
    signedIn = 'a';
    router.accountChanged('a');
    router.open(push('n2'), NotificationTapSource.push);
    signedIn = 'b';
    final direct = FakeShell();
    router.attach('b', direct);
    expect(direct.shown, isEmpty);
    expect(router.hasWaiting, isFalse);
    expect(opened, isEmpty);
  });

  test('with nobody signed in a tap is ignored', () {
    final router = NotificationRouter(currentUserId: () => null);
    expect(router.open(push('n1'), NotificationTapSource.push), isFalse);
    expect(router.hasWaiting, isFalse);
  });

  test('a shell that left the screen no longer receives taps', () {
    final shell = FakeShell();
    final router = NotificationRouter(currentUserId: () => 'a')..attach('a', shell);
    router.detach(shell);
    router.open(push('n1'), NotificationTapSource.push);
    expect(shell.shown, isEmpty);
    expect(router.hasWaiting, isTrue, reason: 'it waits for the next shell of the same account');
    final next = FakeShell();
    router.attach('a', next);
    expect(next.shown, [NotificationDestination.subscription]);
  });
}
