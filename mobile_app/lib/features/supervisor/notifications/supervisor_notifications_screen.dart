import 'package:flutter/material.dart';

import '../../../core/sync/own_changes.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/presentation/notifications_page.dart';

export 'supervisor_send_screen.dart';

/// The supervisor's inbox: what the company sent to the students of their
/// lines and what they sent themselves, in one list by day. Their own are
/// marked «أرسلته أنت · {audience}». Writing to the students is a page of its
/// own (`SupervisorSendScreen`), reached from Home.
class SupervisorNotificationsScreen extends StatelessWidget {
  const SupervisorNotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SupervisorNotificationsScreen()));

  @override
  Widget build(BuildContext context) => const NotificationsPage();
}

/// Sends a notification. The server announces the new notification back to
/// this phone too; the inbox is read once for it, when the send page closes
/// (see `SupervisorSendScreen.open`), and not again for that announcement.
Future<SendResult> sendAnnouncedOnce(Future<SendResult> Function() send) async {
  final echo = OwnChanges.begin('notifications', op: 'INSERT', once: true);
  try {
    final result = await send();
    echo.done();
    return result;
  } catch (_) {
    echo.failed();
    rethrow;
  }
}
