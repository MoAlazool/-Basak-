import 'dart:async';
import 'dart:io';

import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/push/push_controller.dart';
import 'package:basak_mobile/features/notifications/push/push_messaging.dart';

AppNotification note(
  String id,
  String title, {
  bool read = false,
  String role = 'admin',
  String type = 'announcement.admin',
  DateTime? at,
  Map<String, String> data = const {},
}) =>
    AppNotification(
      id: id,
      type: type,
      category: NotificationCategory.parse(null, type: type),
      title: title,
      body: 'نص $title',
      createdAt: at ?? DateTime.now().subtract(const Duration(hours: 1)),
      senderRole: role,
      senderName: 'أحمد',
      audience: 'خط المنصورة',
      read: read,
      data: data,
    );

/// The server's side of the inbox, in memory: pages, the unread count, read
/// marks, and everything the app sent, in the order it was sent.
class FakeNotificationsRepo implements NotificationsRepository {
  FakeNotificationsRepo([List<AppNotification> inbox = const []]) : inbox = [...inbox];

  List<AppNotification> inbox;
  int perPage = 30;

  /// Set to make the next writes (or reads) fail the way a lost connection does.
  bool offline = false;

  /// While set, a read mark waits here before it reaches the server.
  Completer<void>? markGate;

  /// What the server answers a write with instead of doing it.
  String? refusal;

  int pageRequests = 0;

  /// Reads and writes of the push switches.
  int preferenceRequests = 0;
  final List<List<String>?> marked = [];
  final List<String> openedIds = [];
  final List<Map<String, Object?>> sent = [];
  final List<Map<String, Object?>> quickSent = [];
  final List<String> calls = [];
  List<QuickNotificationTemplate> templates = const [];
  NotificationPreferences savedPreferences = NotificationPreferences.all;

  void _write() {
    if (offline) throw const SocketException('Failed host lookup');
    if (refusal != null) throw Exception(refusal);
  }

  @override
  Future<NotificationsPageData> page({String? before, bool unreadOnly = false}) async {
    pageRequests++;
    if (offline) throw const SocketException('Failed host lookup');
    final cursor = before == null ? null : DateTime.parse(before);
    final sorted = [...inbox]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final wanted = sorted
        .where((n) => !unreadOnly || !n.read)
        .where((n) => cursor == null || n.createdAt.isBefore(cursor))
        .toList();
    final items = wanted.take(perPage).toList();
    return NotificationsPageData(
      items: items,
      unread: inbox.where((n) => !n.read).length,
      nextBefore: wanted.length > items.length ? items.last.createdAt.toIso8601String() : null,
    );
  }

  @override
  Future<void> markRead([List<String>? ids]) async {
    await markGate?.future;
    _write();
    marked.add(ids);
    inbox = [for (final n in inbox) ids == null || ids.contains(n.id) ? n.markedRead() : n];
  }

  @override
  Future<void> opened(String id) async {
    _write();
    openedIds.add(id);
    inbox = [for (final n in inbox) n.id == id ? n.markedRead() : n];
  }

  @override
  Future<SendResult> send({
    required String title,
    required String body,
    required String lineId,
    String? tripId,
    String? rideDate,
    required String idempotencyKey,
  }) async {
    _write();
    final duplicate = sent.any((s) => s['key'] == idempotencyKey);
    sent.add({
      'title': title, 'body': body, 'line': lineId, 'trip': tripId, 'date': rideDate, 'key': idempotencyKey,
    });
    return (students: 4, duplicate: duplicate);
  }

  @override
  Future<List<QuickNotificationTemplate>> quickTemplates() async => templates;

  @override
  Future<SendResult> sendQuick({
    required String templateKey,
    required String lineId,
    String? tripId,
    String? rideDate,
    int? minutes,
    required String idempotencyKey,
  }) async {
    quickSent.add({
      'template': templateKey, 'line': lineId, 'trip': tripId, 'date': rideDate,
      'minutes': minutes, 'key': idempotencyKey,
    });
    _write();
    final duplicate = quickSent.where((s) => s['key'] == idempotencyKey).length > 1;
    return (students: 4, duplicate: duplicate);
  }

  @override
  Future<NotificationPreferences> preferences() async {
    preferenceRequests++;
    if (offline) throw const SocketException('Failed host lookup');
    return savedPreferences;
  }

  @override
  Future<NotificationPreferences> setPreferences(NotificationPreferences preferences) async {
    preferenceRequests++;
    _write();
    return savedPreferences = preferences;
  }

  @override
  Future<void> registerDevice({
    required String installationId,
    required String platform,
    required String token,
    required String locale,
    required String appVersion,
  }) async =>
      calls.add('register $installationId $platform $token');

  @override
  Future<void> unregisterDevice(String installationId) async => calls.add('unregister $installationId');
}

/// A push service the test drives by hand.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.available = true, this.granted = PushPermission.granted, this.currentToken = 'token-1'});

  @override
  bool available;
  PushPermission granted;

  /// What the system prompt answers.
  PushPermission promptAnswer = PushPermission.granted;
  String? currentToken;
  PushMessage? launchedBy;
  int initialised = 0;
  int prompts = 0;
  int tokensDeleted = 0;

  final tokenRefreshes = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final openedFromTray = StreamController<PushMessage>.broadcast();

  @override
  String get platform => 'ios';

  @override
  Future<bool> initialize() async {
    initialised++;
    return true;
  }

  @override
  Future<PushPermission> permission() async => granted;

  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return granted = promptAnswer;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Future<void> deleteToken() async {
    tokensDeleted++;
    currentToken = null;
  }

  @override
  Stream<String> get onTokenRefresh => tokenRefreshes.stream;
  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;
  @override
  Stream<PushMessage> get onMessageOpened => openedFromTray.stream;
  @override
  Future<PushMessage?> initialMessage() async => launchedBy;
}

/// The server's list of push devices: which account each phone belongs to.
class FakePushDevices implements PushDeviceApi {
  /// Who is signed in when a call arrives (the server knows it from the session).
  String? Function() signedIn = () => null;
  bool offline = false;

  /// installation id -> (account, token)
  final Map<String, ({String userId, String token})> devices = {};
  final List<String> log = [];

  @override
  Future<void> register({
    required String installationId,
    required String platform,
    required String token,
    required String locale,
    required String appVersion,
  }) async {
    if (offline) throw const SocketException('Failed host lookup');
    final userId = signedIn()!;
    // A token belongs to one account only: it moves to whoever registers it.
    devices.removeWhere((_, device) => device.token == token);
    devices[installationId] = (userId: userId, token: token);
    log.add('register $userId $token $platform $locale $appVersion');
  }

  @override
  Future<void> unregister(String installationId) async {
    if (offline) throw const SocketException('Failed host lookup');
    log.add('unregister ${signedIn()}');
    devices.remove(installationId);
  }
}

/// A signed-in shell that records where it was asked to go.
class FakeShell implements NotificationShell {
  FakeShell([this.destinations = const {
    NotificationDestination.home,
    NotificationDestination.subscription,
    NotificationDestination.card,
    NotificationDestination.center,
  }]);

  @override
  final Set<NotificationDestination> destinations;
  final List<NotificationDestination> shown = [];
  final List<NotificationIntent> intents = [];

  @override
  void showDestination(NotificationDestination destination, NotificationIntent intent) {
    shown.add(destination);
    intents.add(intent);
  }
}
