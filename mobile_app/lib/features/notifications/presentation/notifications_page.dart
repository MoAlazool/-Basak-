import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../../../core/widgets/basak_ui.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/notification_feed.dart';
import '../data/notifications_repository.dart';
import '../notification_router.dart';
import '../push/push_messaging.dart';
import '../push/push_providers.dart';
import 'notification_preferences_screen.dart';
import 'notification_style.dart';
import 'push_permission_sheet.dart';

/// "الآن", "منذ 5 دقائق", "منذ ساعتين", "أمس", "8 أكتوبر".
String notificationAge(DateTime at, DateTime now) {
  final minutes = now.difference(at).inMinutes;
  if (minutes < 1) return 'الآن';
  if (minutes < 60) {
    return switch (minutes) {
      1 => 'منذ دقيقة',
      2 => 'منذ دقيقتين',
      <= 10 => 'منذ $minutes دقائق',
      _ => 'منذ $minutes دقيقة',
    };
  }
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final hours = minutes ~/ 60;
  if (day == today || hours < 6) {
    return switch (hours) {
      1 => 'منذ ساعة',
      2 => 'منذ ساعتين',
      <= 10 => 'منذ $hours ساعات',
      _ => 'منذ $hours ساعة',
    };
  }
  if (today.difference(day).inDays == 1) return 'أمس';
  return '${at.day} ${NotificationsPage.months[at.month - 1]}';
}

/// "اليوم", "أمس", "8 أكتوبر" (with the year when it is not this one).
String notificationDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(DateTime(day.year, day.month, day.day)).inDays;
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  final date = '${day.day} ${NotificationsPage.months[day.month - 1]}';
  return day.year == now.year ? date : '$date ${day.year}';
}

/// "6:58 ص": the hour an alert arrived at, under its day's heading.
String notificationTime(DateTime at) =>
    BasakUi.time12('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}');

/// Who an alert is from, as its detail sheet says it: "محمود السيد · مشرف
/// الباص", "إدارة الشركة", "باصك", or "أرسلته أنت" for the supervisor's own.
String notificationSender(AppNotification n) {
  if (n.mine) return 'أرسلته أنت';
  if (n.senderRole != 'supervisor') return n.senderLabel;
  return n.senderName.trim().isEmpty ? 'مشرف الباص' : '${n.senderName.trim()} · مشرف الباص';
}

/// One day of the inbox.
typedef NotificationDay = ({DateTime day, String label, List<AppNotification> items});

/// [items] (newest first) under the day they arrived on, newest day first.
List<NotificationDay> groupNotificationsByDay(List<AppNotification> items, DateTime now) {
  final days = <NotificationDay>[];
  for (final n in items) {
    final day = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
    if (days.isEmpty || days.last.day != day) {
      days.add((day: day, label: notificationDayLabel(day, now), items: []));
    }
    days.last.items.add(n);
  }
  return days;
}

/// What the detail sheet of an alert offers besides closing it («اتصل
/// بالمشرف»). [run] is given the page under the sheet, after the sheet closed.
typedef AlertAction = ({String label, IconData icon, void Function(BuildContext page) run});

/// The inbox of students and supervisors: back, the title and «قراءة الكل»,
/// the all / unread filter and the alerts by day. A tap marks the alert read
/// and opens the screen it is about, or, when it has none, a sheet with its
/// whole text.
///
/// A supervisor also gets what [header] holds (the send card), a search box
/// and the way to the push switches ([preferences]). A student gets none of
/// the three: only the phone's own permission, as one card when it is off.
class NotificationsPage extends ConsumerStatefulWidget {
  final Widget? header;

  /// Whether the user has notification settings in the app (supervisors).
  final bool preferences;

  /// The action a free-text alert's sheet offers, if any.
  final AlertAction? Function(AppNotification notification)? detailAction;

  const NotificationsPage({super.key, this.header, this.preferences = true, this.detailAction});

  static const months = BasakUi.arabicMonths;

  /// The whole text of [n] in a sheet: who sent it and when, its title, what
  /// it says, and [action] over «إغلاق» when there is one.
  static Future<void> showDetail(BuildContext context, AppNotification n, {AlertAction? action}) {
    final language = Localizations.localeOf(context).languageCode;
    final style = notificationStyle(n.type, n.category);
    final when = '${notificationDayLabel(n.createdAt, DateTime.now())} ${notificationTime(n.createdAt)}';
    return BasakSheet.show<void>(
      context,
      builder: (context) {
        final colors = context.colors;
        final text = context.text;
        return Semantics(
          container: true,
          label: 'تفاصيل التنبيه',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ToneTile(style.icon, tone: style.tone, size: 44),
                  const SizedBox(width: BasakSpace.s12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(notificationSender(n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.body.copyWith(fontWeight: FontWeight.w500)),
                        Text(
                          [when, if (n.audience.isNotEmpty) n.audience].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BasakSpace.s18),
              Semantics(header: true, child: Text(n.titleFor(language), style: text.title)),
              if (n.bodyFor(language).isNotEmpty) ...[
                const SizedBox(height: BasakSpace.s8),
                Text(n.bodyFor(language), style: text.rowTitle.copyWith(fontWeight: FontWeight.w400)),
              ],
              const SizedBox(height: BasakSpace.s6),
            ],
          ),
        );
      },
      primary: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (action != null) ...[
            BasakButton(
              key: const Key('alert-detail-action'),
              label: action.label,
              icon: action.icon,
              onPressed: () {
                // What follows (the dialer, a toast) belongs to the page under the sheet.
                final navigator = Navigator.of(sheet);
                final page = navigator.context;
                navigator.pop();
                action.run(page);
              },
            ),
            const SizedBox(height: BasakSpace.s2),
          ],
          SheetLink(label: 'إغلاق', onTap: () => Navigator.of(sheet).pop()),
        ],
      ),
    );
  }

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  String _query = '';

  NotificationFeedNotifier get _feed => ref.read(notificationFeedProvider.notifier);

  @override
  void initState() {
    super.initState();
    // The screen always opens on everything, whatever was filtered last time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _feed.setUnreadOnly(false);
    });
  }

  /// Read marks show at once; if the server cannot be told, they are taken
  /// back and the reason is said (like every write, never queued).
  Future<void> _marking(Future<void> Function() mark) async {
    try {
      await mark();
    } catch (error) {
      if (!mounted) return;
      BasakToast.show(context, errorMessage(error), kind: BasakToastKind.failure);
    }
  }

  void _open(AppNotification n) {
    if (!n.read) _marking(() => _feed.markRead([n.id]));
    final router = ref.read(notificationRouterProvider);
    final intent = NotificationIntent.of(n);
    // No screen of its own: its whole text, in a sheet.
    final stays = router.staysInCenter(intent);
    router.open(intent, NotificationTapSource.list);
    if (stays) NotificationsPage.showDetail(context, n, action: widget.detailAction?.call(n));
  }

  bool _onScroll(ScrollNotification notification) {
    // Near the end of what is loaded: the next page is fetched before it is needed.
    if (notification.metrics.axis == Axis.vertical && notification.metrics.extentAfter < 400) {
      _feed.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final async = ref.watch(notificationFeedProvider);
    final feed = async.valueOrNull ?? const NotificationFeed();
    final shown = feed.items.where((n) => n.matches(_query)).toList();
    final now = DateTime.now();
    final language = Localizations.localeOf(context).languageCode;

    final loading = async.isLoading && !async.hasValue;
    final failed = async.hasError && !async.hasValue;
    // Nothing has ever arrived: no filter to offer and nothing to mark read.
    final empty = !loading && !failed && feed.items.isEmpty && !feed.unreadOnly && !feed.switching;

    final blocks = <Widget>[
      if (widget.header != null) widget.header!,
      _PushCard(plain: !widget.preferences),
      if (widget.preferences && !empty)
        _gutter(SearchBox(hint: 'ابحث في الإشعارات', onChanged: (value) => setState(() => _query = value))),
      if (!empty)
        _gutter(BasakSegmented<bool>(
          options: const [false, true],
          value: feed.unreadOnly,
          onChanged: _feed.setUnreadOnly,
          label: (unreadOnly) => !unreadOnly
              ? 'الكل'
              : (feed.unread > 0 ? 'غير المقروءة · ${feed.unread}' : 'غير المقروءة'),
        )),
      if (loading)
        _gutter(const SkeletonList(rows: 5))
      else if (failed)
        _gutter(EmptyState(
          icon: LucideIcons.wifiOff,
          title: 'تعذر تحميل الإشعارات',
          message: errorMessage(async.error!),
          actionLabel: 'إعادة المحاولة',
          onAction: () => ref.invalidate(notificationFeedProvider),
        ))
      else if (feed.items.isEmpty && feed.switching)
        _gutter(const SkeletonList(rows: 3))
      else if (feed.items.isEmpty && feed.unreadOnly)
        _gutter(const EmptyState(
            icon: LucideIcons.checkCheck, title: 'لا توجد إشعارات غير مقروءة', message: 'قرأت كل إشعاراتك.'))
      else if (feed.items.isEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: BasakSpace.s40),
          child: EmptyState(
            page: true,
            icon: LucideIcons.bell,
            title: 'لا توجد تنبيهات بعد',
            message: widget.preferences
                ? 'ستظهر هنا إشعارات رحلاتك واشتراكك.'
                : 'ستظهر هنا حركة الباص، رسائل المشرف، وحالة اشتراكك.',
          ),
        )
      else if (shown.isEmpty)
        _gutter(EmptyState(
            icon: LucideIcons.search, title: 'لا توجد نتائج', message: 'لا يوجد إشعار يطابق "$_query".'))
      else ...[
        for (final day in groupNotificationsByDay(shown, now))
          _gutter(GroupSection(
            title: day.label,
            child: AlertRows(rows: [
              for (final n in day.items) _row(n, language),
            ]),
          )),
        if (feed.loadingMore || feed.moreError != null || feed.hasMore) _gutter(_more(feed)),
      ],
    ];

    return Scaffold(
      backgroundColor: colors.ground,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        BasakSpace.gutter, BasakSpace.s12, BasakSpace.gutter, BasakSpace.s12),
                    child: PageTitleBar(
                      title: 'التنبيهات',
                      actions: [
                        if (!empty)
                          TextAction(
                            label: 'قراءة الكل',
                            onTap: feed.unread == 0 ? null : () => _marking(_feed.markAllRead),
                          ),
                        if (widget.preferences) ...[
                          const SizedBox(width: BasakSpace.s4),
                          Tooltip(
                            message: 'إعدادات الإشعارات',
                            excludeFromSemantics: true,
                            child: BasakIconButton(
                              icon: LucideIcons.settings,
                              label: 'إعدادات الإشعارات',
                              onPressed: () => NotificationPreferencesScreen.open(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: colors.teal,
                      backgroundColor: colors.surface,
                      onRefresh: _feed.refresh,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: EdgeInsetsDirectional.only(
                              top: BasakSpace.s4, bottom: BasakSpace.s32 + MediaQuery.paddingOf(context).bottom),
                          itemCount: blocks.length,
                          itemBuilder: (context, index) => blocks[index],
                          // A block that shows nothing (the push card, when
                          // notifications are on) takes no gap either.
                          separatorBuilder: (context, index) =>
                              blocks[index] is _PushCard ? const SizedBox.shrink() : const SizedBox(height: BasakSpace.s16),
                        ),
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

  Widget _gutter(Widget child) =>
      Padding(padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.gutter), child: child);

  AlertRow _row(AppNotification n, String language) {
    final style = notificationStyle(n.type, n.category);
    return AlertRow(
      key: Key('alert-${n.id}'),
      icon: style.icon,
      tone: style.tone,
      title: n.titleFor(language),
      body: n.bodyFor(language),
      time: notificationTime(n.createdAt),
      unread: !n.read,
      onTap: () => _open(n),
    );
  }

  /// The end of the list: the next page loading, a retry, or the way to it.
  Widget _more(NotificationFeed feed) {
    if (feed.loadingMore) return const SkeletonList(rows: 2);
    if (feed.moreError != null) {
      return InlineError(message: errorMessage(feed.moreError!), onRetry: _feed.loadMore);
    }
    return Center(child: TextAction(label: 'عرض تنبيهات أقدم', onTap: _feed.loadMore));
  }
}

/// Shown while this phone could receive pushes but the system does not let
/// the app show them: one card, one tap away from switching them on.
class _PushCard extends ConsumerWidget {
  /// A student: the phone is asked directly (or its settings open), with no
  /// sheet of the app's own in between.
  final bool plain;
  const _PushCard({this.plain = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(pushReadyProvider).valueOrNull != true) return const SizedBox.shrink();
    final permission = ref.watch(pushPermissionProvider).valueOrNull;
    if (permission == null || permission == PushPermission.granted) return const SizedBox.shrink();
    final blocked = permission == PushPermission.blocked;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, 0, BasakSpace.gutter, BasakSpace.s16),
      child: ActionNotice(
        key: const Key('push-off-card'),
        icon: LucideIcons.bellOff,
        title: blocked ? 'الإشعارات متوقفة' : 'الإشعارات غير مفعّلة على هذا الهاتف',
        message: blocked ? 'فعّلها من إعدادات الهاتف لتصلك التنبيهات.' : 'فعّلها لتصلك التنبيهات حتى والتطبيق مغلق.',
        actionLabel: blocked ? 'فتح إعدادات الهاتف' : 'تفعيل الإشعارات',
        onAction: () => plain
            ? requestSystemPushPermission(ref, openSettingsWhenBlocked: true)
            : offerPushNotifications(context, ref),
      ),
    );
  }
}
