import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../push/notification_platform.dart';
import '../push/push_messaging.dart';
import '../push/push_providers.dart';

/// Offers to switch push notifications on, in the app's own words first: the
/// system prompt appears only after the user agrees here, and when the system
/// no longer shows one, the way to the phone's settings is offered instead.
Future<void> offerPushNotifications(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(pushControllerProvider);
  if (!await controller.start()) return;
  var permission = await controller.permission();
  if (permission == PushPermission.granted) {
    await controller.sync();
    return;
  }
  if (!context.mounted) return;
  if (permission != PushPermission.blocked) {
    if (await _show(context, blocked: false) != true) return;
    permission = await controller.requestPermission();
    if (!context.mounted) return;
    ref.invalidate(pushPermissionProvider);
    // A plain "no" to the system prompt is an answer, not something to argue with.
    if (permission != PushPermission.blocked) return;
  }
  if (await _show(context, blocked: true) == true) {
    await NotificationPlatform.openSystemSettings();
  }
}

/// Once per installation, shortly after signing in (students and supervisors
/// alike): the same offer, made by the app itself. Never when notifications
/// are already on or were refused.
Future<void> offerPushNotificationsOnce(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(pushControllerProvider);
  final store = ref.read(deviceStoreProvider);
  if (!await controller.start() || await store.pushPrompted()) return;
  final permission = await controller.permission();
  if (permission == PushPermission.granted) return controller.sync();
  if (permission == PushPermission.blocked) return;
  await store.markPushPrompted();
  if (context.mounted) await offerPushNotifications(context, ref);
}

/// The phone's own notification prompt, with nothing of the app's before it:
/// for a row that already says what it is for (the Notification Center's
/// line). When the system no longer shows a prompt and
/// [openSettingsWhenBlocked] is set, the phone's settings open instead.
Future<PushPermission> requestSystemPushPermission(WidgetRef ref, {bool openSettingsWhenBlocked = false}) async {
  final controller = ref.read(pushControllerProvider);
  if (!await controller.start()) return PushPermission.blocked;
  var permission = await controller.permission();
  if (permission == PushPermission.granted) {
    await controller.sync();
    return permission;
  }
  if (permission == PushPermission.blocked) {
    if (openSettingsWhenBlocked) await NotificationPlatform.openSystemSettings();
    return permission;
  }
  permission = await controller.requestPermission();
  ref.invalidate(pushPermissionProvider);
  return permission;
}

Future<bool?> _show(BuildContext context, {required bool blocked}) => BasakSheet.show<bool>(
      context,
      builder: (context) => _PushExplainer(blocked: blocked),
      primary: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BasakButton(
            label: blocked ? 'فتح إعدادات الهاتف' : 'تفعيل الإشعارات',
            icon: blocked ? LucideIcons.externalLink : LucideIcons.bell,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BasakSpace.s2),
          SheetLink(label: 'ليس الآن', onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );

/// Why the app asks, in its own words, before the phone asks its one question.
class _PushExplainer extends StatelessWidget {
  final bool blocked;
  const _PushExplainer({required this.blocked});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Semantics(
      container: true,
      label: 'تفعيل الإشعارات',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: BasakSpace.s6),
          SheetGlyph(blocked ? LucideIcons.bellOff : LucideIcons.bell),
          const SizedBox(height: BasakSpace.s16),
          Semantics(
            header: true,
            child: Text(blocked ? 'الإشعارات متوقفة من إعدادات الهاتف' : 'فعّل إشعارات باصك', style: text.title),
          ),
          const SizedBox(height: BasakSpace.s10),
          Text(
            blocked
                ? 'اسمح لباصك بإرسال الإشعارات من إعدادات الهاتف، ثم عد إلى التطبيق.'
                : 'لتعرف لحظة تفعيل اشتراكك، وتحرّك الباص، وأي تغيير من المشرف. بعدها يسألك الهاتف مرة واحدة.',
            style: text.body.copyWith(color: context.colors.ink2),
          ),
          const SizedBox(height: BasakSpace.s6),
        ],
      ),
    );
  }
}
