import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/session.dart';
import 'notifications_repository.dart';

/// The inbox as the Notification Center shows it: the pages loaded so far.
class NotificationFeed {
  /// Newest first, each notification once.
  final List<AppNotification> items;

  /// Every unread notification of the user (the bell), counted by the server
  /// and kept in step with what is marked read here.
  final int unread;

  /// Where the next (older) page starts; null when everything is loaded.
  final String? nextBefore;

  /// Showing unread notifications only.
  final bool unreadOnly;

  /// The first page of a filter that was just switched to is on its way.
  final bool switching;
  final bool loadingMore;

  /// Why the last "load more" failed; the list keeps what it has.
  final Object? moreError;

  const NotificationFeed({
    this.items = const [],
    this.unread = 0,
    this.nextBefore,
    this.unreadOnly = false,
    this.switching = false,
    this.loadingMore = false,
    this.moreError,
  });

  bool get hasMore => nextBefore != null;

  NotificationFeed copyWith({
    List<AppNotification>? items,
    int? unread,
    String? Function()? nextBefore,
    bool? unreadOnly,
    bool? switching,
    bool? loadingMore,
    Object? Function()? moreError,
  }) =>
      NotificationFeed(
        items: items ?? this.items,
        unread: unread ?? this.unread,
        nextBefore: nextBefore == null ? this.nextBefore : nextBefore(),
        unreadOnly: unreadOnly ?? this.unreadOnly,
        switching: switching ?? this.switching,
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: moreError == null ? this.moreError : moreError(),
      );
}

/// [current] with [incoming] added: a notification present in both appears
/// once, as the server sent it last; the result is newest first.
List<AppNotification> mergeNotifications(
    List<AppNotification> current, List<AppNotification> incoming) {
  final byId = {for (final n in current) n.id: n, for (final n in incoming) n.id: n};
  return byId.values.toList()
    ..sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
}

/// The list after the first page was read again (pull to refresh, a live
/// event): [head] replaces everything as new as itself, so what was deleted on
/// the server goes, and the older pages already scrolled to stay.
List<AppNotification> refreshHead(
    List<AppNotification> current, NotificationsPageData head) {
  if (head.nextBefore == null || head.items.isEmpty) return mergeNotifications(const [], head.items);
  final oldest = head.items.map((n) => n.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
  return mergeNotifications(
      [for (final n in current) if (n.createdAt.isBefore(oldest)) n], head.items);
}

/// The Notification Center's data: first page from the device at once, live
/// refreshes, older pages on demand and read marks shown before the server
/// confirms them.
class NotificationFeedNotifier extends AsyncNotifier<NotificationFeed> {
  String? _userId;
  bool _unreadOnly = false;
  NotificationFeed? _feed;

  /// The whole inbox as it was when the unread filter was switched on.
  NotificationFeed? _allFeed;

  /// Marked read here while the server has not answered yet: a refresh that
  /// lands meanwhile must not show them unread again.
  final Set<String> _marking = {};
  bool _markingAll = false;

  NotificationsRepository get _repo => ref.read(notificationsRepoProvider);

  @override
  Future<NotificationFeed> build() async {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId != _userId) {
      // Another account (or nobody): nothing of the previous one is kept.
      _userId = userId;
      _unreadOnly = false;
      _feed = null;
      _allFeed = null;
      _marking.clear();
      _markingAll = false;
    }
    if (userId == null) return const NotificationFeed();
    final unreadOnly = _unreadOnly;
    final head = await _repo.page(unreadOnly: unreadOnly);
    if (unreadOnly != _unreadOnly) return _feed ?? const NotificationFeed();
    return _feed = _withHead(head);
  }

  NotificationFeed _withHead(NotificationsPageData head) {
    final previous = _feed;
    var items = _unreadOnly || previous == null || previous.unreadOnly
        ? mergeNotifications(const [], head.items)
        : refreshHead(previous.items, head);
    // Nothing unread on the server: older pages read on another phone follow.
    if (head.unread == 0) items = [for (final n in items) n.markedRead()];
    final keptOlder = !_unreadOnly &&
        previous != null &&
        !previous.unreadOnly &&
        head.items.isNotEmpty &&
        items.length > head.items.length;
    return _overlay(NotificationFeed(
      items: items,
      unread: head.unread,
      nextBefore: keptOlder ? previous.nextBefore : head.nextBefore,
      unreadOnly: _unreadOnly,
    ));
  }

  /// Read marks still on their way to the server, applied to fresh data.
  NotificationFeed _overlay(NotificationFeed feed) {
    if (!_markingAll && _marking.isEmpty) return feed;
    bool pending(AppNotification n) => !n.read && (_markingAll || _marking.contains(n.id));
    final cleared = feed.items.where(pending).length;
    return feed.copyWith(
      items: [for (final n in feed.items) pending(n) ? n.markedRead() : n],
      unread: _markingAll ? 0 : max(0, feed.unread - cleared),
    );
  }

  void _show(NotificationFeed feed) {
    _feed = feed;
    state = AsyncData(feed);
  }

  /// Reads the first page again and waits for it (pull to refresh).
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // Shown by the screen; what was loaded stays.
    }
  }

  /// All notifications, or the unread ones only. What is already loaded shows
  /// at once; the server's first page follows.
  Future<void> setUnreadOnly(bool unreadOnly) async {
    final feed = _feed;
    if (unreadOnly == _unreadOnly || feed == null || _userId == null) return;
    final userId = _userId;
    _unreadOnly = unreadOnly;
    if (unreadOnly) {
      _allFeed = feed;
      _show(NotificationFeed(
        items: [for (final n in feed.items) if (!n.read) n],
        unread: feed.unread,
        unreadOnly: true,
        switching: true,
      ));
    } else {
      final all = _allFeed ?? const NotificationFeed();
      _allFeed = null;
      _show(all.copyWith(unread: feed.unread, unreadOnly: false, switching: true));
    }
    try {
      final head = await _repo.page(unreadOnly: unreadOnly);
      if (_userId != userId || _unreadOnly != unreadOnly) return;
      _show(_withHead(head));
    } catch (_) {
      if (_userId != userId || _unreadOnly != unreadOnly) return;
      // No connection: the filter still works on what is already on the phone.
      _show(_feed!.copyWith(switching: false));
    }
  }

  /// Loads the next (older) page, once at a time.
  Future<void> loadMore() async {
    final feed = _feed;
    if (feed == null || !feed.hasMore || feed.loadingMore || feed.switching) return;
    final userId = _userId;
    final unreadOnly = _unreadOnly;
    _show(feed.copyWith(loadingMore: true, moreError: () => null));
    try {
      final page = await _repo.page(before: feed.nextBefore, unreadOnly: unreadOnly);
      final now = _feed;
      if (_userId != userId || _unreadOnly != unreadOnly || now == null) return;
      _show(_overlay(now.copyWith(
        items: mergeNotifications(now.items, page.items),
        unread: page.unread,
        nextBefore: () => page.nextBefore,
        loadingMore: false,
      )));
    } catch (error) {
      final now = _feed;
      if (_userId != userId || _unreadOnly != unreadOnly || now == null) return;
      _show(now.copyWith(loadingMore: false, moreError: () => error));
    }
  }

  /// Marks [ids] read: shown at once, and taken back if the server could not
  /// be told (the error is rethrown for the screen to say so).
  Future<void> markRead(List<String> ids) => _mark(ids, () => _repo.markRead(ids));

  /// Marks every notification read, loaded or not.
  Future<void> markAllRead() => _mark(null, () => _repo.markRead());

  /// A push or a banner for [id] was tapped: read at once and reported to the
  /// server as opened. Never throws; a tap must not end in an error message.
  Future<void> opened(String id) async {
    if (_userId == null) return;
    final feed = _feed;
    try {
      if (feed == null) {
        // Opened from a push before the inbox was read (a cold start).
        await _repo.opened(id);
      } else {
        await _mark([id], () => _repo.opened(id));
      }
      // Not on screen yet (it arrived with the push): read it now.
      if (!(feed?.items.any((n) => n.id == id) ?? false)) ref.invalidateSelf();
    } catch (_) {
      // Offline: it stays unread and can be opened from the list later.
    }
  }

  Future<void> _mark(List<String>? ids, Future<void> Function() send) async {
    final feed = _feed;
    if (feed == null || _userId == null) return;
    final userId = _userId;
    final wanted = ids?.toSet();
    bool affects(AppNotification n) => !n.read && (wanted == null || wanted.contains(n.id));

    // What actually changes on screen, so only that is taken back on failure.
    final changed = {for (final n in feed.items) if (affects(n)) n.id};
    final unreadBefore = feed.unread;
    if (wanted == null) {
      _markingAll = true;
    } else {
      _marking.addAll(wanted);
    }
    NotificationFeed marked(NotificationFeed f) => f.copyWith(
          items: [for (final n in f.items) affects(n) ? n.markedRead() : n],
          unread: wanted == null ? 0 : max(0, f.unread - f.items.where(affects).length),
        );
    _show(marked(feed));
    if (_allFeed != null) _allFeed = marked(_allFeed!);

    try {
      await send();
    } catch (_) {
      if (_userId == userId) {
        NotificationFeed unmarked(NotificationFeed f) => f.copyWith(
              items: [for (final n in f.items) changed.contains(n.id) ? n.markedUnread() : n],
              unread: wanted == null ? unreadBefore : f.unread + changed.length,
            );
        _release(wanted);
        final now = _feed;
        if (now != null) _show(unmarked(now));
        if (_allFeed != null) _allFeed = unmarked(_allFeed!);
      }
      rethrow;
    }
    if (_userId == userId) _release(wanted);
  }

  void _release(Set<String>? wanted) {
    if (wanted == null) {
      _markingAll = false;
    } else {
      _marking.removeAll(wanted);
    }
  }
}

/// The signed-in user's inbox; refreshed by live events.
final notificationFeedProvider =
    AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeed>(NotificationFeedNotifier.new);

/// How many are unread (the badge on the bell), as counted by the server.
final unreadNotificationsProvider = Provider<int>(
    (ref) => ref.watch(notificationFeedProvider).valueOrNull?.unread ?? 0);
