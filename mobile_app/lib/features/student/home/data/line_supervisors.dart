import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/sync/session.dart';
import '../../subscription/models/subscription_model.dart';

/// One supervisor of a line the student rides.
class LineSupervisor {
  final String lineId;
  final String name;
  final String phone;

  /// The photo in 'supervisor-avatars', if the company added one.
  final String? photoPath;

  const LineSupervisor({required this.lineId, required this.name, required this.phone, this.photoPath});

  /// The supervisors of [sub]'s line from [all] (`lineSupervisorsProvider`),
  /// the primary contact first. Until they are known, or when they cannot be
  /// read (offline, an older server), the primary contact as the subscription
  /// carries it; empty when there is none.
  static List<LineSupervisor> ofLine(SubscriptionModel sub, List<LineSupervisor>? all) {
    final line = all?.where((s) => s.lineId == sub.lineId).toList() ?? const <LineSupervisor>[];
    if (line.isNotEmpty) return line;
    final phone = sub.supervisorPhone?.trim() ?? '';
    return [
      if (phone.isNotEmpty)
        LineSupervisor(
            lineId: sub.lineId,
            name: sub.supervisorName?.trim() ?? '',
            phone: phone,
            photoPath: sub.supervisorPhotoPath),
    ];
  }

  /// `get_my_line_supervisors()`'s answer; anything unexpected in it is left out.
  static List<LineSupervisor> listFromJson(Object? json) => [
        if (json is List)
          for (final row in json.whereType<Map>())
            if (row['line_id'] is String && row['phone'] is String && (row['phone'] as String).trim().isNotEmpty)
              LineSupervisor(
                lineId: row['line_id'] as String,
                name: (row['full_name'] as String?)?.trim() ?? '',
                phone: (row['phone'] as String).trim(),
                photoPath: row['profile_image_url'] as String?,
              ),
      ];
}

/// Every active supervisor of the lines of the student's active subscriptions,
/// per line the primary contact first. A line can have several; the
/// subscription itself carries only its primary contact.
final lineSupervisorsProvider = FutureProvider<List<LineSupervisor>>((ref) async {
  if (ref.watch(sessionUserIdProvider) == null) return const [];
  return LineSupervisor.listFromJson(await SupabaseService.client.rpc(SupabaseRpcs.getMyLineSupervisors));
});
