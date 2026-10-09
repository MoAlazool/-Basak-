import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/session.dart';
import '../../../core/ui/ui.dart';
import '../data/notification_feed.dart';
import '../data/notifications_repository.dart';
import '../notification_router.dart';
import '../push/notification_platform.dart';
import '../push/push_messaging.dart';
import '../push/push_providers.dart';
import 'notification_style.dart';

/// Sits above every screen of the app (MaterialApp.builder). It starts push,
/// keeps this phone attached to whoever is signed in, shows the banner for a
/// push that arrives while the app is open, and keeps the app icon's badge in
/// step with the unread count.
class NotificationsHost extends ConsumerStatefulWidget {
  final Widget child;
  const NotificationsHost({super.key, required this.child});

  @override
  ConsumerState<NotificationsHost> createState() => _NotificationsHostState();
}

class _NotificationsHostState extends ConsumerState<NotificationsHost> with WidgetsBindingObserver {
  /// The number last put on the app icon.
  int? _badge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// Nothing here asks the user for anything: with no permission yet, push
  /// simply waits until they switch it on.
  Future<void> _start() async {
    final controller = ref.read(pushControllerProvider);
    if (!controller.available) return;
    await NotificationPlatform.createChannels();
    if (await controller.start()) await controller.sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final controller = ref.read(pushControllerProvider);
    if (!controller.available) return;
    // The permission may have been changed in the system settings meanwhile,
    // and the token may be a new one.
    ref.invalidate(pushPermissionProvider);
    unawaited(controller.sync());
  }

  void _accountChanged(String? previous, String? next) {
    ref.read(notificationRouterProvider).accountChanged(next);
    ref.read(foregroundBannerProvider.notifier).reset();
    final controller = ref.read(pushControllerProvider);
    if (next != null) {
      unawaited(controller.sync());
    } else if (previous != null) {
      unawaited(controller.signedOut());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(sessionUserIdProvider, _accountChanged);
    // The icon's number is the last one a push carried; once the inbox is read
    // from the server (and whenever something is read, here or on another
    // phone) it follows the real count. Signed out, it is cleared.
    ref.listen(notificationFeedProvider, (_, feed) {
      final unread = feed.valueOrNull?.unread;
      if (unread == null || unread == _badge) return;
      _badge = unread;
      NotificationPlatform.setBadge(unread);
    });
    return Stack(children: [
      widget.child,
      const Positioned(top: 0, left: 0, right: 0, child: _ForegroundBanner()),
    ]);
  }
}

class _ForegroundBanner extends ConsumerWidget {
  const _ForegroundBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(foregroundBannerProvider);
    return AnimatedSwitcher(
      duration: BasakMotion.sheetIn,
      switchInCurve: BasakMotion.sheetInCurve,
      switchOutCurve: BasakMotion.sheetOutCurve,
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: message == null
          ? const SizedBox.shrink()
          : _BannerCard(key: ValueKey(message.notificationId ?? message.title), message: message),
    );
  }
}

class _BannerCard extends ConsumerWidget {
  final PushMessage message;
  const _BannerCard({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intent = message.intent;
    final category = NotificationCategory.parse(intent.data['category'], type: intent.type);
    final style = notificationStyle(intent.type, category);
    final banner = ref.read(foregroundBannerProvider.notifier);
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s12, BasakSpace.s8, BasakSpace.s12, 0),
            child: GestureDetector(
              // Flicked away upwards.
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < 0) banner.dismiss();
              },
              // Its own Material: the banner sits above the navigator, where
              // text has no style to inherit.
              child: Material(
                type: MaterialType.transparency,
                child: InkBanner(
                  icon: style.icon,
                  // A push with no title still says something on its first line.
                  title: message.title.isNotEmpty ? message.title : message.body,
                  message: message.title.isNotEmpty ? message.body : null,
                  onTap: () {
                    banner.dismiss();
                    ref.read(notificationRouterProvider).open(intent, NotificationTapSource.banner);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
