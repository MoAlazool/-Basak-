import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/notification_preferences.dart';
import '../data/notifications_repository.dart';
import '../push/notification_platform.dart';
import '../push/push_messaging.dart';
import '../push/push_providers.dart';
import 'notification_style.dart';
import 'push_permission_sheet.dart';

/// Which pushes a supervisor wants, and whether this phone can show them at
/// all. The in-app inbox is not affected by anything here. (Students have no
/// switches: their inbox opens without the settings button.)
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationPreferencesScreen()));

  @override
  ConsumerState<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends ConsumerState<NotificationPreferencesScreen> {
  bool _saving = false;

  /// The switch moves at once; if the server refuses, it moves back and the
  /// reason is shown.
  Future<void> _change(Future<void> Function(NotificationPreferencesNotifier) change) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await change(ref.read(notificationPreferencesProvider.notifier));
    } catch (error) {
      if (!mounted) return;
      BasakToast.show(context, errorMessage(error), kind: BasakToastKind.failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final async = ref.watch(notificationPreferencesProvider);
    final preferences = async.valueOrNull;

    return Scaffold(
      backgroundColor: colors.ground,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: basakMaxTextScale,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                        BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, BasakSpace.s12),
                    child: PageTitleBar(title: 'إعدادات الإشعارات'),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: colors.teal,
                      backgroundColor: colors.surface,
                      onRefresh: () async {
                        ref.invalidate(pushPermissionProvider);
                        ref.invalidate(notificationPreferencesProvider);
                        try {
                          await ref.read(notificationPreferencesProvider.future);
                        } catch (_) {}
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, BasakSpace.s4, BasakSpace.gutter,
                            BasakSpace.s40 + MediaQuery.paddingOf(context).bottom),
                        children: [
                          const _SystemState(),
                          const SizedBox(height: BasakSpace.s20),
                          if (preferences == null && async.isLoading)
                            const SkeletonList(rows: 4, avatars: false)
                          else if (preferences == null)
                            EmptyState(
                              icon: LucideIcons.wifiOff,
                              title: 'تعذر تحميل الإعدادات',
                              message: errorMessage(async.error ?? ''),
                              actionLabel: 'إعادة المحاولة',
                              onAction: () => ref.invalidate(notificationPreferencesProvider),
                            )
                          else
                            GroupSection(
                              title: 'الإشعارات الفورية',
                              child: _card([
                                _switch(
                                  icon: LucideIcons.bellRing,
                                  title: 'الإشعارات الفورية',
                                  subtitle: 'تصلك على الهاتف حتى والتطبيق مغلق',
                                  value: preferences.pushEnabled,
                                  onChanged: (value) => _change((n) => n.setPushEnabled(value)),
                                ),
                                for (final category in const [
                                  NotificationCategory.transport,
                                  NotificationCategory.subscription,
                                  NotificationCategory.announcement,
                                ])
                                  _switch(
                                    icon: notificationStyle('', category).icon,
                                    title: notificationCategoryLabel(category),
                                    subtitle: _about(category),
                                    value: preferences.pushEnabled && preferences.allows(category),
                                    // Nothing to choose from while everything is off.
                                    onChanged: preferences.pushEnabled
                                        ? (value) => _change((n) => n.setCategory(category, value))
                                        : null,
                                  ),
                              ]),
                            ),
                          const SizedBox(height: BasakSpace.s18),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
                              child: Icon(LucideIcons.inbox, size: 16, color: colors.ink3),
                            ),
                            const SizedBox(width: BasakSpace.s8),
                            Expanded(
                              child: Text(
                                  'مركز الإشعارات داخل التطبيق يحتفظ بكل إشعاراتك دائماً. هذه الإعدادات تحدد فقط ما يصلك كإشعار على الهاتف.',
                                  style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _about(NotificationCategory category) => switch (category) {
        NotificationCategory.transport => 'تأخير الباص، تحركه، وصوله أو إلغاء الرحلة',
        NotificationCategory.subscription => 'مراجعة الإيصال، تفعيل الاشتراك وقرب انتهائه',
        NotificationCategory.announcement => 'رسائل إدارة الشركة ومشرف الباص',
        NotificationCategory.reminder => '',
      };

  Widget _card(List<Widget> rows) => BasakCard(
        padding: EdgeInsetsDirectional.zero,
        // Switch rows draw their ink on a Material of their own.
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: BasakSpace.s18,
                    endIndent: BasakSpace.s18,
                    color: context.colors.hairline),
              row,
            ],
          ]),
        ),
      );

  Widget _switch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final colors = context.colors;
    final text = context.text;
    return SwitchListTile(
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s2),
      secondary: Icon(icon, color: colors.ink2, size: 20),
      title: Text(title, style: text.body.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
      value: value,
      activeTrackColor: colors.teal,
      inactiveTrackColor: colors.track,
      inactiveThumbColor: colors.surface,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      onChanged: _saving ? null : onChanged,
    );
  }
}

/// Whether this phone can show pushes right now, and the way to fix it when
/// it cannot.
class _SystemState extends ConsumerWidget {
  const _SystemState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(pushReadyProvider);
    if (ready.isLoading) return const SizedBox.shrink();
    if (ready.valueOrNull != true) {
      return _box(
        context,
        icon: LucideIcons.info,
        title: 'الإشعارات الفورية غير متاحة بعد',
        message: 'ستتاح في تحديث قادم. حتى ذلك الحين تجد كل إشعاراتك داخل التطبيق في مركز الإشعارات.',
      );
    }
    final permission = ref.watch(pushPermissionProvider).valueOrNull;
    return switch (permission) {
      null => const SizedBox.shrink(),
      PushPermission.granted => _box(
          context,
          icon: LucideIcons.circleCheck,
          tone: BasakTone.success,
          title: 'الإشعارات مفعّلة على هذا الهاتف',
          message: 'تصلك الإشعارات التي تختارها بالأسفل.',
        ),
      PushPermission.blocked => const ActionNotice(
          icon: LucideIcons.bellOff,
          title: 'الإشعارات متوقفة من إعدادات الهاتف',
          message: 'اسمح لباصك بإرسال الإشعارات من إعدادات الهاتف لتصلك.',
          actionLabel: 'فتح إعدادات الهاتف',
          onAction: NotificationPlatform.openSystemSettings,
        ),
      PushPermission.notAsked || PushPermission.denied => ActionNotice(
          icon: LucideIcons.bellOff,
          title: 'الإشعارات غير مفعّلة على هذا الهاتف',
          message: 'فعّلها لتصلك التنبيهات حتى والتطبيق مغلق.',
          actionLabel: 'تفعيل الإشعارات',
          onAction: () => offerPushNotifications(context, ref),
        ),
    };
  }

  /// A state with nothing to do about it: said on its tone's tint.
  Widget _box(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    BasakTone tone = BasakTone.info,
  }) {
    final colors = context.colors;
    final text = context.text;
    return BasakCard(
      color: tone.tint(colors),
      padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
          child: Icon(icon, color: tone.foreground(colors), size: 20),
        ),
        const SizedBox(width: BasakSpace.s12),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.body.copyWith(fontWeight: FontWeight.w600)),
            Text(message, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
          ]),
        ),
      ]),
    );
  }
}
