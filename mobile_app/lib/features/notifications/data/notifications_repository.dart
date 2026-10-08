import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/sync/session.dart';

/// A notification sent to students by their company's admins or a supervisor
/// (get_my_notifications).
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// 'admin' | 'supervisor'
  final String senderRole;
  final String senderName;

  /// Who it went to, as written by the server: the company, a line, or a trip.
  final String audience;
  final bool read;

  /// Sent by the signed-in supervisor.
  final bool mine;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.senderRole,
    required this.senderName,
    required this.audience,
    required this.read,
    this.mine = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        senderRole: json['sender_role'] as String? ?? 'admin',
        senderName: json['sender_name'] as String? ?? '',
        audience: json['audience'] as String? ?? '',
        read: json['read'] as bool? ?? true,
        mine: json['mine'] as bool? ?? false,
      );

  bool get fromSupervisor => senderRole == 'supervisor';

  /// "المشرف أحمد" / "إدارة الشركة".
  String get senderLabel => fromSupervisor
      ? (senderName.isEmpty ? 'المشرف' : 'المشرف $senderName')
      : 'إدارة الشركة';

  AppNotification markedRead() => AppNotification(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        senderRole: senderRole,
        senderName: senderName,
        audience: audience,
        read: true,
        mine: mine,
      );

  /// Matches a search of title, text, sender or audience.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [title, body, senderLabel, audience].any((field) => field.toLowerCase().contains(q));
  }
}

class NotificationsRepository {
  SupabaseClient get _client => SupabaseService.client;

  /// The signed-in user's notifications of the last 60 days, newest first.
  Future<List<AppNotification>> mine() async {
    final response = await OfflineCache.readThrough(
        'notifications', () => _client.rpc('get_my_notifications'));
    return [
      for (final row in response as List? ?? const [])
        AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  /// Marks [ids] read, or every notification when null.
  Future<void> markRead([List<String>? ids]) => requireOnline(
      () => _client.rpc('mark_notifications_read', params: {'p_ids': ids}));

  /// A supervisor writes to a line's students, or to the riders of one of its
  /// trips on [rideDate]. Returns how many students receive it.
  Future<int> send({
    required String title,
    required String body,
    required String lineId,
    String? tripId,
    String? rideDate,
  }) async {
    final response = await requireOnline(() => _client.rpc('send_notification', params: {
          'p_title': title,
          'p_body': body,
          'p_line_id': lineId,
          if (tripId != null) 'p_trip_id': tripId,
          if (rideDate != null) 'p_ride_date': rideDate,
        }));
    return ((response as Map?)?['students'] as num?)?.toInt() ?? 0;
  }
}

final notificationsRepoProvider = Provider((ref) => NotificationsRepository());

/// The signed-in user's notifications; refreshed by live events.
final myNotificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  if (ref.watch(sessionUserIdProvider) == null) return const [];
  return ref.watch(notificationsRepoProvider).mine();
});

/// How many are unread (the badge on the bell).
final unreadNotificationsProvider = Provider<int>((ref) =>
    ref.watch(myNotificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);
