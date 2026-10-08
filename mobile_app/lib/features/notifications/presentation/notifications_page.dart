import 'package:flutter/material.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/notifications_repository.dart';

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

/// The notifications screen of students and supervisors: "mark all read",
/// an optional [header] (the student's reminder days, the supervisor's send
/// card), search and the list. Opening a notification marks it read.
class NotificationsPage extends ConsumerStatefulWidget {
  final Widget? header;

  const NotificationsPage({super.key, this.header});

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

  /// Marked read on this screen, shown read before the list reloads.
  final Set<String> _readNow = {};

  Future<void> _markRead(List<String> ids, {bool all = false}) async {
    if (ids.isEmpty) return;
    setState(() => _readNow.addAll(ids));
    try {
      await ref.read(notificationsRepoProvider).markRead(all ? null : ids);
      ref.invalidate(myNotificationsProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _readNow.removeAll(ids));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage(error)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myNotificationsProvider);
    final all = [
      for (final n in async.valueOrNull ?? const <AppNotification>[])
        _readNow.contains(n.id) ? n.markedRead() : n,
    ];
    final unread = [for (final n in all) if (!n.read) n.id];
    final shown = all.where((n) => n.matches(_query)).toList();
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FA),
      body: Column(children: [
        _topBar(context, unread),
        Expanded(
          child: RefreshIndicator(
            color: _teal,
            onRefresh: () async {
              ref.invalidate(myNotificationsProvider);
              try {
                await ref.read(myNotificationsProvider.future);
              } catch (_) {}
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 18, bottom: 32),
              children: [
                if (widget.header != null) ...[widget.header!, const SizedBox(height: 18)],
                _padded(_searchField()),
                const SizedBox(height: 16),
                _padded(Row(children: [
                  const Icon(LucideIcons.bellRing, color: _teal, size: 19),
                  const SizedBox(width: 8),
                  Text('${unread.length} إشعارات غير مقروءة',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: _teal, fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(height: 12),
                if (async.isLoading && !async.hasValue)
                  const SkeletonList(rows: 5)
                else if (async.hasError && !async.hasValue)
                  _padded(_messageCard(
                    LucideIcons.wifiOff,
                    'تعذر تحميل الإشعارات',
                    errorMessage(async.error!),
                    action: TextButton(
                      onPressed: () => ref.invalidate(myNotificationsProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ))
                else if (all.isEmpty)
                  _padded(_messageCard(
                      LucideIcons.bell, 'لا توجد إشعارات بعد', 'ستظهر هنا إشعارات رحلاتك واشتراكك.'))
                else if (shown.isEmpty)
                  _padded(_messageCard(
                      LucideIcons.badgeHelp, 'لا توجد نتائج', 'لا يوجد إشعار يطابق "$_query".'))
                else
                  for (final n in shown) ...[
                    _padded(_tile(n, now)),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

  Widget _topBar(BuildContext context, List<String> unread) => Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 12, 12),
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
            onPressed: unread.isEmpty ? null : () => _markRead(unread, all: true),
            icon: const Icon(LucideIcons.checkCheck, size: 18),
            label: const Text('مسح الكل'),
            style: TextButton.styleFrom(
              foregroundColor: _teal,
              textStyle: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
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

  Widget _tile(AppNotification n, DateTime now) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: n.read ? _line : _teal.withOpacity(.35)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onTap: n.read ? null : () => _markRead([n.id]),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: n.fromSupervisor ? const Color(0xFFE7F8F0) : _soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(n.fromSupervisor ? LucideIcons.busFront : LucideIcons.bell,
                    color: n.fromSupervisor ? const Color(0xFF07865A) : _teal, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(n.title,
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
                  Text(n.body,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: const Color(0xFF3D5566), height: 1.5)),
                  const SizedBox(height: 8),
                  Text(
                    '${n.mine ? 'أرسلته أنت' : n.senderLabel} · ${n.audience}',
                    style: AppTextStyles.labelSmall.copyWith(color: _muted),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );

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
