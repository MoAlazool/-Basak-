import 'package:flutter/material.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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

/// The Notification Center of students and supervisors: an optional [header]
/// (the student's reminder days, the supervisor's send card), search, the
/// all / unread filter and the inbox by day. Opening a notification marks it
/// read and goes where it leads.
class NotificationsPage extends ConsumerStatefulWidget {
  final Widget? header;


  /// Whether the user has notification settings in the app (supervisors). A
  /// student has none: no settings button, and when the phone does not let the
  /// app show notifications, one line that leads to the system's own prompt
  /// or settings. The inbox itself is the same either way.
  final bool preferences;

  const NotificationsPage({super.key, this.header, this.preferences = true});

  static const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  static const ink = Color(0xFF17384A);
  static const teal = Color(0xFF00658D);
  static const muted = Color(0xFF718695);
  static const soft = Color(0xFFE5F3FA);
  static const line = Color(0xFFE3EDF3);

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  static const _ink = NotificationsPage.ink;
  static const _teal = NotificationsPage.teal;
  static const _muted = NotificationsPage.muted;
  static const _soft = NotificationsPage.soft;
  static const _line = NotificationsPage.line;

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage(error)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _open(AppNotification n) {
    if (!n.read) _marking(() => _feed.markRead([n.id]));
    ref.read(notificationRouterProvider).open(NotificationIntent.of(n), NotificationTapSource.list);
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
    final async = ref.watch(notificationFeedProvider);
    final feed = async.valueOrNull ?? const NotificationFeed();
    final shown = feed.items.where((n) => n.matches(_query)).toList();
    final now = DateTime.now();
    final language = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FA),
      body: Column(children: [
        _topBar(context, feed.unread),
        Expanded(
          child: RefreshIndicator(
            color: _teal,
            onRefresh: _feed.refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 18, bottom: 32),
                children: [
                  if (widget.header != null) ...[widget.header!, const SizedBox(height: 18)],
                  _PushOffer(plain: !widget.preferences),
                  _padded(_searchField()),
                  const SizedBox(height: 14),
                  _padded(_filters(feed)),
                  const SizedBox(height: 12),
                  if (async.isLoading && !async.hasValue)
                    _padded(const SkeletonList(rows: 5))
                  else if (async.hasError && !async.hasValue)
                    _padded(_messageCard(
                      LucideIcons.wifiOff,
                      'تعذر تحميل الإشعارات',
                      errorMessage(async.error!),
                      action: TextButton(
                        onPressed: () => ref.invalidate(notificationFeedProvider),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ))
                  else if (feed.items.isEmpty && feed.switching)
                    _padded(const SkeletonList(rows: 3))
                  else if (feed.items.isEmpty && feed.unreadOnly)
                    _padded(_messageCard(LucideIcons.checkCheck, 'لا توجد إشعارات غير مقروءة',
                        'قرأت كل إشعاراتك.'))
                  else if (feed.items.isEmpty)
                    _padded(_messageCard(
                        LucideIcons.bell, 'لا توجد إشعارات بعد', 'ستظهر هنا إشعارات رحلاتك واشتراكك.'))
                  else if (shown.isEmpty)
                    _padded(_messageCard(
                        LucideIcons.badgeHelp, 'لا توجد نتائج', 'لا يوجد إشعار يطابق "$_query".'))
                  else ...[
                    for (final day in groupNotificationsByDay(shown, now)) ...[
                      _padded(Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 10),
                        child: Text(day.label,
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: _muted, fontWeight: FontWeight.w700)),
                      )),
                      for (final n in day.items) ...[
                        _padded(_tile(n, now, language)),
                        const SizedBox(height: 10),
                      ],
                    ],
                    _padded(_more(feed)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  Widget _topBar(BuildContext context, int unread) => Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 8, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'رجوع',
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: _line),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(LucideIcons.arrowRight, color: _ink, size: 21),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('الإشعارات',
                style: AppTextStyles.titleLarge.copyWith(color: _ink, fontSize: 21)),
          ),
          TextButton.icon(
            onPressed: unread == 0 ? null : () => _marking(_feed.markAllRead),
            icon: const Icon(LucideIcons.checkCheck, size: 18),
            label: const Text('قراءة الكل'),
            style: TextButton.styleFrom(
              foregroundColor: _teal,
              textStyle: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.preferences)
            IconButton(
              tooltip: 'إعدادات الإشعارات',
              onPressed: () => NotificationPreferencesScreen.open(context),
              icon: const Icon(LucideIcons.settings, color: _ink, size: 21),
            ),
        ]),
      );

  Widget _searchField() => TextField(
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'ابحث في الإشعارات',
          prefixIcon: const Icon(LucideIcons.search, color: _muted, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _teal),
          ),
        ),
      );

  Widget _filters(NotificationFeed feed) => Row(children: [
        _filter('الكل', !feed.unreadOnly, () => _feed.setUnreadOnly(false)),
        const SizedBox(width: 8),
        _filter(feed.unread > 0 ? 'غير المقروءة (${feed.unread})' : 'غير المقروءة', feed.unreadOnly,
            () => _feed.setUnreadOnly(true)),
        const Spacer(),
        if (feed.switching)
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _teal)),
      ]);

  Widget _filter(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: _teal,
        backgroundColor: Colors.white,
        labelStyle: AppTextStyles.bodyMedium.copyWith(
            color: selected ? Colors.white : _ink,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        side: BorderSide(color: selected ? _teal : _line),
      );

  /// The end of the list: the next page loading, a retry, or nothing.
  Widget _more(NotificationFeed feed) {
    if (feed.loadingMore) return const SkeletonList(rows: 2);
    if (feed.moreError != null) {
      return Column(children: [
        Text(errorMessage(feed.moreError!),
            textAlign: TextAlign.center, style: AppTextStyles.labelSmall.copyWith(color: _muted)),
        TextButton(onPressed: _feed.loadMore, child: const Text('إعادة المحاولة')),
      ]);
    }
    if (feed.hasMore) {
      return Center(
        child: TextButton(onPressed: _feed.loadMore, child: const Text('عرض إشعارات أقدم')),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _tile(AppNotification n, DateTime now, String language) {
    final style = notificationStyle(n.type, n.category);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: n.read ? _line : _teal.withOpacity(.35)),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: () => _open(n),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
              child: Icon(style.icon, color: style.color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(n.titleFor(language),
                        style: AppTextStyles.titleMedium.copyWith(color: _ink)),
                  ),
                  const SizedBox(width: 8),
                  Text(notificationAge(n.createdAt, now),
                      style: AppTextStyles.labelSmall.copyWith(color: _muted)),
                  if (!n.read) ...[
                    const SizedBox(width: 6),
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
                    ),
                  ],
                ]),
                const SizedBox(height: 5),
                Text(n.bodyFor(language),
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: const Color(0xFF3D5566), height: 1.5)),
                const SizedBox(height: 8),
                Text(
                  [n.mine ? 'أرسلته أنت' : n.senderLabel, if (n.audience.isNotEmpty) n.audience]
                      .join(' · '),
                  style: AppTextStyles.labelSmall.copyWith(color: _muted),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _messageCard(IconData icon, String title, String message, {Widget? action}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: _soft, shape: BoxShape.circle),
            child: Icon(icon, color: _teal, size: 28),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppTextStyles.titleMedium.copyWith(color: _ink)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: _muted)),
          if (action != null) ...[const SizedBox(height: 8), action],
        ]),
      );
}

/// Shown while this phone could receive pushes but the system does not let
/// the app show them: one tap away from switching them on.
class _PushOffer extends ConsumerWidget {
  /// Ask the system directly, with no explanation sheet of the app's own.
  final bool plain;
  const _PushOffer({this.plain = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(pushReadyProvider).valueOrNull != true) return const SizedBox.shrink();
    final permission = ref.watch(pushPermissionProvider).valueOrNull;
    if (permission == null || permission == PushPermission.granted) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Material(
        color: NotificationsPage.soft,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => plain
              ? requestSystemPushPermission(ref, openSettingsWhenBlocked: true)
              : offerPushNotifications(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              const Icon(LucideIcons.bellRing, color: NotificationsPage.teal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    plain && permission == PushPermission.blocked
                        ? 'الإشعارات متوقفة من إعدادات الهاتف.'
                        : 'فعّل الإشعارات لتصلك التنبيهات حتى والتطبيق مغلق.',
                    style: AppTextStyles.bodyMedium.copyWith(color: NotificationsPage.ink)),
              ),
              const SizedBox(width: 8),
              Text(plain && permission == PushPermission.blocked ? 'فتح الإعدادات' : 'تفعيل',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: NotificationsPage.teal, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
