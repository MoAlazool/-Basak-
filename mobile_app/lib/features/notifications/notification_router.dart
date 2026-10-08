import 'data/notifications_repository.dart';

/// Where a notification leads inside the app.
enum NotificationDestination {
  home,
  subscription,
  card,

  /// The Notification Center: also where anything unknown ends up.
  center;

  /// From the server's `route`. A route this version does not know opens the
  /// Notification Center, where the notification can at least be read.
  static NotificationDestination parse(String? route) => switch (route) {
        'home' => NotificationDestination.home,
        'subscription' => NotificationDestination.subscription,
        'card' => NotificationDestination.card,
        _ => NotificationDestination.center,
      };
}

/// How the user got to a notification.
enum NotificationTapSource {
  /// A row of the Notification Center.
  list,

  /// A system notification, with the app in the background or closed.
  push,

  /// The banner shown inside the app while it is open.
  banner,
}

/// A tap on a notification, from wherever it came.
class NotificationIntent {
  final String? notificationId;
  final String type;
  final NotificationDestination destination;

  /// Ids only (subscription_id, line_id, trip_id, ride_date).
  final Map<String, String> data;

  const NotificationIntent({
    this.notificationId,
    this.type = '',
    this.destination = NotificationDestination.center,
    this.data = const {},
  });

  factory NotificationIntent.of(AppNotification notification) => NotificationIntent(
        notificationId: notification.id,
        type: notification.type,
        destination: NotificationDestination.parse(notification.data['route']),
        data: notification.data,
      );

  /// From the `data` of a push (all strings; anything else is ignored).
  factory NotificationIntent.fromPush(Map<String, dynamic> data) {
    final strings = {
      for (final entry in data.entries)
        if (entry.value is String && (entry.value as String).isNotEmpty) entry.key: entry.value as String,
    };
    return NotificationIntent(
      notificationId: strings['notification_id'],
      type: strings['type'] ?? '',
      destination: NotificationDestination.parse(strings['route']),
      data: strings,
    );
  }

  String? get subscriptionId => data['subscription_id'];
}

/// The signed-in app shell (the student's or the supervisor's tabs), which
/// knows how to show a destination.
abstract interface class NotificationShell {
  /// The places this shell has. Anything else opens the Notification Center.
  Set<NotificationDestination> get destinations;

  void showDestination(NotificationDestination destination, NotificationIntent intent);
}

/// The one place that decides where a notification tap goes: rows of the
/// Notification Center, system notifications and the in-app banner all pass
/// through [open].
///
/// A tap can arrive before the app is ready for it (opened from a push while
/// closed: the session is still being restored and no screen is up). It then
/// waits for the shell of the account it was meant for, and is dropped if
/// another account, or nobody, ends up signed in.
class NotificationRouter {
  /// Who is signed in right now (null = nobody), known as soon as the app starts.
  final String? Function() currentUserId;

  /// A push or a banner was tapped and is now being shown.
  final void Function(NotificationIntent intent)? onOpened;

  NotificationRouter({required this.currentUserId, this.onOpened});

  NotificationShell? _shell;
  String? _shellUserId;
  ({NotificationIntent intent, NotificationTapSource source, String userId})? _waiting;

  /// Pushes already acted on. The same tap is reported twice on some launches
  /// (as the message that opened the app and as a tap), and a banner may sit
  /// over a system notification for the same message.
  final Set<String> _handled = {};

  bool get hasWaiting => _waiting != null;

  /// Returns false when the tap was ignored: a repeat, or nobody is signed in.
  bool open(NotificationIntent intent, NotificationTapSource source) {
    final userId = currentUserId();
    if (userId == null) return false;
    final id = intent.notificationId;
    if (source != NotificationTapSource.list && id != null && !_handled.add(id)) return false;

    final shell = _shell;
    if (shell != null && _shellUserId == userId) {
      _show(shell, intent, source);
    } else {
      _waiting = (intent: intent, source: source, userId: userId);
    }
    return true;
  }

  /// The signed-in shell of [userId] is on screen and can navigate.
  void attach(String userId, NotificationShell shell) {
    _shell = shell;
    _shellUserId = userId;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && waiting.userId == userId) _show(shell, waiting.intent, waiting.source);
  }

  void detach(NotificationShell shell) {
    if (!identical(_shell, shell)) return;
    _shell = null;
    _shellUserId = null;
  }

  /// Sign-in, sign-out or another account: a tap meant for someone else is dropped.
  void accountChanged(String? userId) {
    if (_waiting != null && _waiting!.userId != userId) _waiting = null;
    if (userId == null || (_shellUserId != null && _shellUserId != userId)) {
      _handled.clear();
      _shell = null;
      _shellUserId = null;
    }
  }

  void _show(NotificationShell shell, NotificationIntent intent, NotificationTapSource source) {
    final destination = shell.destinations.contains(intent.destination)
        ? intent.destination
        : NotificationDestination.center;
    // Already in the Notification Center: the row itself is the content.
    final stays = source == NotificationTapSource.list && destination == NotificationDestination.center;
    if (!stays) shell.showDestination(destination, intent);
    if (source != NotificationTapSource.list) onOpened?.call(intent);
  }
}
