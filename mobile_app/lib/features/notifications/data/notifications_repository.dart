import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';

/// What a notification is about. Decides its icon, its colour, its Android
/// channel and which switch of the preferences silences its push.
enum NotificationCategory {
  subscription,
  transport,
  announcement,

  /// Only the app's own vote reminders; the server sends none.
  reminder;

  /// A category this version does not know is shown as an announcement.
  static NotificationCategory parse(String? value, {String type = ''}) {
    final name = (value == null || value.isEmpty) ? type.split('.').first : value;
    return NotificationCategory.values.asNameMap()[name] ?? NotificationCategory.announcement;
  }
}

/// A notification of the signed-in user (get_my_notifications_page).
class AppNotification {
  final String id;

  /// 'subscription.approved', 'transport.delay', 'announcement.admin', …
  /// A type this version does not know still shows its title and text.
  final String type;
  final NotificationCategory category;
  final bool highPriority;
  final String title;
  final String body;

  /// English text, when the server has one. The app is Arabic today; these are
  /// used as soon as it runs in English.
  final String? titleEn;
  final String? bodyEn;
  final DateTime createdAt;

  /// 'admin' | 'supervisor' | 'system'
  final String senderRole;
  final String senderName;

  /// Who it went to, as written by the server: the company, a line, or a trip.
  final String audience;
  final bool read;

  /// Sent by the signed-in supervisor.
  final bool mine;

  /// Where a tap leads (`route`) and the ids it concerns. Ids only.
  final Map<String, String> data;

  const AppNotification({
    required this.id,
    this.type = 'announcement.admin',
    this.category = NotificationCategory.announcement,
    this.highPriority = false,
    required this.title,
    required this.body,
    this.titleEn,
    this.bodyEn,
    required this.createdAt,
    required this.senderRole,
    required this.senderName,
    required this.audience,
    required this.read,
    this.mine = false,
    this.data = const {},
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final rawData = json['data'];
    return AppNotification(
      id: json['id'] as String,
      type: type,
      category: NotificationCategory.parse(json['category'] as String?, type: type),
      highPriority: json['priority'] == 'high',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      titleEn: _text(json['title_en']),
      bodyEn: _text(json['body_en']),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      senderRole: json['sender_role'] as String? ?? 'admin',
      senderName: json['sender_name'] as String? ?? '',
      audience: json['audience'] as String? ?? '',
      read: json['read'] as bool? ?? true,
      mine: json['mine'] as bool? ?? false,
      data: {
        if (rawData is Map)
          for (final entry in rawData.entries)
            if (entry.value != null) '${entry.key}': '${entry.value}',
      },
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  bool get fromSupervisor => senderRole == 'supervisor';

  /// "المشرف أحمد" / "إدارة الشركة" / "باصك" for what the system sends itself.
  String get senderLabel => switch (senderRole) {
        'supervisor' => senderName.isEmpty ? 'المشرف' : 'المشرف $senderName',
        'system' => 'باصك',
        // Sent by the platform to every company (announcement.platform).
        _ => type == 'announcement.platform' ? 'منصة باصك' : 'إدارة الشركة',
      };

  /// The title and text in the app's language: English only when the app runs
  /// in English and the server sent an English text.
  String titleFor(String languageCode) => languageCode == 'en' ? (titleEn ?? title) : title;
  String bodyFor(String languageCode) => languageCode == 'en' ? (bodyEn ?? body) : body;

  AppNotification markedRead() => read ? this : _withRead(true);
  AppNotification markedUnread() => read ? _withRead(false) : this;

  AppNotification _withRead(bool value) => AppNotification(
        id: id,
        type: type,
        category: category,
        highPriority: highPriority,
        title: title,
        body: body,
        titleEn: titleEn,
        bodyEn: bodyEn,
        createdAt: createdAt,
        senderRole: senderRole,
        senderName: senderName,
        audience: audience,
        read: value,
        mine: mine,
        data: data,
      );

  /// Matches a search of title, text, sender or audience.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [title, body, senderLabel, audience].any((field) => field.toLowerCase().contains(q));
  }
}

/// One page of the inbox, newest first.
class NotificationsPageData {
  final List<AppNotification> items;

  /// Every unread notification of the user, not only the ones on this page.
  final int unread;

  /// Pass it to read the next (older) page; null at the end.
  final String? nextBefore;

  const NotificationsPageData({this.items = const [], this.unread = 0, this.nextBefore});

  factory NotificationsPageData.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return NotificationsPageData(
      items: [
        for (final row in map['items'] as List? ?? const [])
          if (row is Map && row['id'] is String)
            AppNotification.fromJson(Map<String, dynamic>.from(row)),
      ],
      unread: (map['unread'] as num?)?.toInt() ?? 0,
      nextBefore: map['next_before'] as String?,
    );
  }
}

/// Which pushes the user wants. The inbox always keeps everything; these only
/// silence the push (and, for [reminder], the app's own vote reminders).
class NotificationPreferences {
  final bool pushEnabled;
  final Map<NotificationCategory, bool> categories;

  const NotificationPreferences({this.pushEnabled = true, this.categories = const {}});

  /// Everything on: what a user who never opened the screen has.
  static const all = NotificationPreferences();

  factory NotificationPreferences.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final raw = map['categories'] is Map ? map['categories'] as Map : const {};
    return NotificationPreferences(
      pushEnabled: map['push_enabled'] as bool? ?? true,
      categories: {
        for (final category in NotificationCategory.values)
          if (raw[category.name] is bool) category: raw[category.name] as bool,
      },
    );
  }

  bool allows(NotificationCategory category) => categories[category] ?? true;

  NotificationPreferences copyWith({bool? pushEnabled, NotificationCategory? category, bool? enabled}) =>
      NotificationPreferences(
        pushEnabled: pushEnabled ?? this.pushEnabled,
        categories: {
          ...categories,
          if (category != null && enabled != null) category: enabled,
        },
      );

  Map<String, bool> get categoriesJson =>
      {for (final category in NotificationCategory.values) category.name: allows(category)};

  Map<String, dynamic> toJson() => {'push_enabled': pushEnabled, 'categories': categoriesJson};
}

/// A ready operational message a supervisor sends with two taps
/// (get_quick_notification_templates). The server writes the final text.
class QuickNotificationTemplate {
  final String key;
  final String title;

  /// May contain `{minutes}`, which the server fills in.
  final String body;
  final bool needsMinutes;

  /// 'departure' | 'return' | null (either).
  final String? direction;

  const QuickNotificationTemplate({
    required this.key,
    required this.title,
    required this.body,
    this.needsMinutes = false,
    this.direction,
  });

  factory QuickNotificationTemplate.fromJson(Map<String, dynamic> json) => QuickNotificationTemplate(
        key: json['key'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        needsMinutes: json['needs_minutes'] as bool? ?? false,
        direction: json['direction'] as String?,
      );

  /// The text as the students will read it.
  String preview(int? minutes) => body.replaceAll('{minutes}', minutes == null ? '…' : '$minutes');

  /// Whether it makes sense for a trip going in [tripDirection] (null = the whole line).
  bool fits(String? tripDirection) =>
      direction == null || tripDirection == null || direction == tripDirection;
}

/// What sending returned: how many students receive it, and whether the server
/// recognised a repeat of something already sent (same idempotency key).
typedef SendResult = ({int students, bool duplicate});

/// A random UUID (v4). Used as the idempotency key of one user action (the
/// same key is sent again when that action is retried, so the server never
/// delivers it twice) and as the id of this installation of the app.
String newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

class NotificationsRepository {
  SupabaseClient get _client => SupabaseService.client;

  static const pageSize = 30;

  /// A page of the signed-in user's inbox, newest first. The first page of the
  /// whole inbox is kept on the device, so the screen opens without a
  /// connection; older pages and the unread filter need the server.
  Future<NotificationsPageData> page({String? before, bool unreadOnly = false}) async {
    Future<dynamic> fetch() => _client.rpc('get_my_notifications_page', params: {
          'p_before': before,
          'p_limit': pageSize,
          'p_unread_only': unreadOnly,
        });
    final response = before == null && !unreadOnly
        ? await OfflineCache.readThrough('notifications.page', fetch)
        : await fetch();
    return NotificationsPageData.fromJson(response);
  }

  /// A server write. Without a connection it says so in Arabic; what the
  /// server refuses (not allowed, too many in a short time, …) is rethrown
  /// with the server's own message, which is written to be shown as it is.
  Future<dynamic> _write(Future<dynamic> Function() action) async {
    try {
      return await requireOnline(action);
    } on PostgrestException catch (error) {
      throw Exception(error.message);
    }
  }

  /// Marks [ids] read, or every notification when null.
  Future<void> markRead([List<String>? ids]) =>
      _write(() => _client.rpc('mark_notifications_read', params: {'p_ids': ids}));

  /// A push or a banner was tapped: counted as opened, and marked read.
  Future<void> opened(String id) =>
      _write(() => _client.rpc('notification_opened', params: {'p_id': id}));

  /// A supervisor writes to a line's students, or to the riders of one of its
  /// trips on [rideDate].
  Future<SendResult> send({
    required String title,
    required String body,
    required String lineId,
    String? tripId,
    String? rideDate,
    required String idempotencyKey,
  }) async {
    final response = await _write(() => _client.rpc('send_notification', params: {
          'p_title': title,
          'p_body': body,
          'p_line_id': lineId,
          if (tripId != null) 'p_trip_id': tripId,
          if (rideDate != null) 'p_ride_date': rideDate,
          'p_idempotency_key': idempotencyKey,
        }));
    return _sendResult(response);
  }

  /// The ready operational messages this supervisor may send.
  Future<List<QuickNotificationTemplate>> quickTemplates() async {
    final response = await OfflineCache.readThrough(
        'notification_templates', () => _client.rpc('get_quick_notification_templates'));
    return [
      for (final row in response as List? ?? const [])
        if (row is Map) QuickNotificationTemplate.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Sends one of the ready messages. The server checks the line is assigned
  /// to this supervisor, limits how often, and writes the text.
  Future<SendResult> sendQuick({
    required String templateKey,
    required String lineId,
    String? tripId,
    String? rideDate,
    int? minutes,
    required String idempotencyKey,
  }) async {
    final response = await _write(() => _client.rpc('send_quick_notification', params: {
          'p_template_key': templateKey,
          'p_line_id': lineId,
          'p_trip_id': tripId,
          'p_ride_date': rideDate,
          'p_minutes': minutes,
          'p_idempotency_key': idempotencyKey,
        }));
    return _sendResult(response);
  }

  static SendResult _sendResult(Object? response) {
    final map = response is Map ? response : const {};
    return (
      students: (map['students'] as num?)?.toInt() ?? 0,
      duplicate: map['duplicate'] as bool? ?? false,
    );
  }

  Future<NotificationPreferences> preferences() async => NotificationPreferences.fromJson(
      await OfflineCache.readThrough(
          'notification_preferences', () => _client.rpc('get_notification_preferences')));

  /// Saves the switches and returns them as the server now holds them.
  Future<NotificationPreferences> setPreferences(NotificationPreferences preferences) async {
    final response = await _write(() => _client.rpc('set_notification_preferences', params: {
          'p_push_enabled': preferences.pushEnabled,
          'p_categories': preferences.categoriesJson,
        }));
    // The saved copy is what the screen opens with next time.
    await OfflineCache.put('notification_preferences', response);
    return NotificationPreferences.fromJson(response);
  }

  /// Attaches this phone's push token to the signed-in account. A token belongs
  /// to one account only: the server moves it to whoever registers it last.
  Future<void> registerDevice({
    required String installationId,
    required String platform,
    required String token,
    required String locale,
    required String appVersion,
  }) =>
      _client.rpc('register_push_device', params: {
        'p_installation_id': installationId,
        'p_platform': platform,
        'p_token': token,
        'p_locale': locale,
        'p_app_version': appVersion,
      });

  /// Detaches this phone from the signed-in account (before signing out).
  Future<void> unregisterDevice(String installationId) =>
      _client.rpc('unregister_push_device', params: {'p_installation_id': installationId});
}

final notificationsRepoProvider = Provider((ref) => NotificationsRepository());
