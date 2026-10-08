import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/basak_ui.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/models/user_role.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/notification_preferences.dart';
import '../data/notifications_repository.dart';
import '../push/notification_platform.dart';
import '../push/push_messaging.dart';
import '../push/push_providers.dart';
import 'notification_style.dart';
import 'push_permission_sheet.dart';

/// Which pushes the user wants, and whether this phone can show them at all.
/// The in-app inbox is not affected by anything here.
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
    setState(() => _saving = true);
    try {
      await change(ref.read(notificationPreferencesProvider.notifier));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage(error)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPreferencesProvider);
    final preferences = async.valueOrNull;
    final isStudent = ref.watch(authStateProvider.select((s) => s.role)) == UserRole.student;

    return Scaffold(
      backgroundColor: BasakUi.canvas,
      appBar: AppBar(
        title: const Text('إعدادات الإشعارات'),
        backgroundColor: Colors.white,
        foregroundColor: BasakUi.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        color: BasakUi.teal,
        onRefresh: () async {
          ref.invalidate(pushPermissionProvider);
          ref.invalidate(notificationPreferencesProvider);
          try {
            await ref.read(notificationPreferencesProvider.future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
          children: [
            const _SystemState(),
            if (preferences == null && async.isLoading)
              const Padding(
                  padding: EdgeInsets.only(top: 18), child: SkeletonList(rows: 4, avatars: false))
            else if (preferences == null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: BasakMessageCard(
                  icon: LucideIcons.wifiOff,
                  title: 'تعذر تحميل الإعدادات',
                  message: errorMessage(async.error ?? ''),
                  actionLabel: 'إعادة المحاولة',
                  onAction: () => ref.invalidate(notificationPreferencesProvider),
                ),
              )
            else ...[
              const BasakSectionTitle('الإشعارات الفورية'),
              _card([
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
              if (isStudent) ...[
                const BasakSectionTitle('تذكيرات التطبيق'),
                _card([
                  _switch(
                    icon: LucideIcons.calendarClock,
                    title: notificationCategoryLabel(NotificationCategory.reminder),
                    subtitle: 'يذكّرك التطبيق بتأكيد حضورك قبل قفل التصويت',
                    value: preferences.allows(NotificationCategory.reminder),
                    onChanged: (value) =>
                        _change((n) => n.setCategory(NotificationCategory.reminder, value)),
                  ),
                ]),
              ],
            ],
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(LucideIcons.inbox, size: 18, color: BasakUi.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'مركز الإشعارات داخل التطبيق يحتفظ بكل إشعاراتك دائماً. هذه الإعدادات تحدد فقط ما يصلك كإشعار على الهاتف.',
                    style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted, height: 1.6)),
              ),
            ]),
          ],
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

  Widget _card(List<Widget> rows) => Container(
        decoration: BasakUi.card(),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            for (final (i, row) in rows.indexed) ...[if (i > 0) const Divider(height: 1), row],
          ]),
        ),
      );

  Widget _switch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) =>
      SwitchListTile(
        secondary: Icon(icon, color: BasakUi.teal, size: 22),
        title: Text(title, style: AppTextStyles.bodyLarge.copyWith(color: BasakUi.ink)),
        subtitle: Text(subtitle, style: AppTextStyles.labelSmall.copyWith(color: BasakUi.muted)),
        value: value,
        activeColor: BasakUi.teal,
        onChanged: _saving ? null : onChanged,
      );
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
        icon: LucideIcons.info,
        title: 'الإشعارات الفورية غير متاحة بعد',
        message: 'ستتاح في تحديث قادم. حتى ذلك الحين تجد كل إشعاراتك داخل التطبيق في مركز الإشعارات.',
      );
    }
    final permission = ref.watch(pushPermissionProvider).valueOrNull;
    return switch (permission) {
      null => const SizedBox.shrink(),
      PushPermission.granted => _box(
          icon: LucideIcons.circleCheck,
          color: const Color(0xFF07865A),
          background: const Color(0xFFE7F8F0),
          title: 'الإشعارات مفعّلة على هذا الهاتف',
          message: 'تصلك الإشعارات التي تختارها بالأسفل.',
        ),
      PushPermission.blocked => _box(
          icon: LucideIcons.bellOff,
          color: const Color(0xFFB97812),
          background: const Color(0xFFFDF3DC),
          title: 'الإشعارات متوقفة من إعدادات الهاتف',
          message: 'اسمح لباصك بإرسال الإشعارات من إعدادات الهاتف لتصلك.',
          actionLabel: 'فتح إعدادات الهاتف',
          onAction: NotificationPlatform.openSystemSettings,
        ),
      PushPermission.notAsked || PushPermission.denied => _box(
          icon: LucideIcons.bellOff,
          color: const Color(0xFFB97812),
          background: const Color(0xFFFDF3DC),
          title: 'الإشعارات غير مفعّلة على هذا الهاتف',
          message: 'فعّلها لتصلك التنبيهات حتى والتطبيق مغلق.',
          actionLabel: 'تفعيل الإشعارات',
          onAction: () => offerPushNotifications(context, ref),
        ),
    };
  }

  Widget _box({
    required IconData icon,
    required String title,
    required String message,
    Color color = BasakUi.teal,
    Color background = BasakUi.softTeal,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(message,
                  style: AppTextStyles.labelSmall.copyWith(color: BasakUi.ink, height: 1.6)),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel),
                ),
            ]),
          ),
        ]),
      );
}
