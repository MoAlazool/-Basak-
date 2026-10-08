import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/session.dart';
import 'notifications_repository.dart';

/// The ready operational messages the signed-in supervisor may send.
final quickTemplatesProvider = FutureProvider<List<QuickNotificationTemplate>>((ref) {
  if (ref.watch(sessionUserIdProvider) == null) return const [];
  return ref.watch(notificationsRepoProvider).quickTemplates();
});
