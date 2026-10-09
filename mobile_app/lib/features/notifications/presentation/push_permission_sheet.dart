import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/basak_ui.dart';
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

/// Once per installation, shortly after signing in: the same offer, made by
/// the app itself. Never when notifications are already on or were refused.
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

/// The phone's own notification prompt, with nothing of the app's before it
/// (students: there are no choices to make in the app). When the system no
/// longer shows a prompt and [openSettingsWhenBlocked] is set, the phone's
/// settings open instead.
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

/// Once per installation, shortly after a student signs in: the system's
/// prompt, asked plainly. Never again by itself after an answer; a refusal
/// changes nothing else in the app (the Notification Center keeps working).
Future<void> requestSystemPushPermissionOnce(WidgetRef ref) async {
  final controller = ref.read(pushControllerProvider);
  final store = ref.read(deviceStoreProvider);
  if (!await controller.start() || await store.pushPrompted()) return;
  final permission = await controller.permission();
  if (permission == PushPermission.granted) return controller.sync();
  if (permission == PushPermission.blocked) return;
  await store.markPushPrompted();
  await requestSystemPushPermission(ref);
}

Future<bool?> _show(BuildContext context, {required bool blocked}) => showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PushSheet(blocked: blocked),
    );

class _PushSheet extends StatelessWidget {
  final bool blocked;
  const _PushSheet({required this.blocked});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 10, 24, MediaQuery.paddingOf(context).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: const Color(0xFFD9E3EA), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 22),
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(color: BasakUi.softTeal, shape: BoxShape.circle),
            child: Icon(blocked ? LucideIcons.bellOff : LucideIcons.bellRing,
                color: BasakUi.teal, size: 30),
          ),
          const SizedBox(height: 16),
          Text(blocked ? 'الإشعارات متوقفة من إعدادات الهاتف' : 'فعّل إشعارات باصك',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
          const SizedBox(height: 8),
          Text(
              blocked
                  ? 'اسمح لباصك بإرسال الإشعارات من إعدادات الهاتف، ثم عد إلى التطبيق.'
                  : 'لتصلك تنبيهات تأخير الباص وتحركه، وحالة اشتراكك وإيصالك، ورسائل شركتك فور صدورها.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.muted, height: 1.6)),
          if (!blocked) ...[
            const SizedBox(height: 6),
            Text('تختار ما يصلك، أو توقفها، في أي وقت من إعدادات الإشعارات.',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted, height: 1.6)),
          ],
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: Icon(blocked ? LucideIcons.externalLink : LucideIcons.bellRing, size: 18),
            label: Text(blocked ? 'فتح إعدادات الهاتف' : 'تفعيل الإشعارات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: BasakUi.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
                foregroundColor: BasakUi.muted, minimumSize: const Size.fromHeight(44)),
            child: const Text('ليس الآن'),
          ),
        ]),
      );
}
