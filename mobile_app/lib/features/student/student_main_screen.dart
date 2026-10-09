import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/sync/session.dart';
import '../../core/sync/sync_hub.dart';
import '../../core/widgets/connection_strip_host.dart';
import '../../core/widgets/floating_glass_nav_bar.dart';
import '../auth/providers/auth_provider.dart';
import '../notifications/data/notification_feed.dart';
import '../notifications/notification_router.dart';
import '../notifications/presentation/push_permission_sheet.dart';
import '../notifications/push/push_providers.dart';
import 'home/presentation/notifications_screen.dart';
import 'home/presentation/student_home_screen.dart';
import 'invites/invites.dart';
import 'subscription/presentation/subscription_screen.dart';
import 'qr/presentation/student_qr_screen.dart';
import 'profile/presentation/profile_screen.dart';

class StudentMainScreen extends ConsumerStatefulWidget {
  const StudentMainScreen({super.key});

  @override
  ConsumerState<StudentMainScreen> createState() => _StudentMainScreenState();
}

class _StudentMainScreenState extends ConsumerState<StudentMainScreen> implements NotificationShell {
  int _currentIndex = 0;
  bool _navCollapsed = false;

  /// Tabs that have been built. The home tab comes first, alone, so the app
  /// opens on its own data only; the others are built a moment later, in the
  /// background, so they are ready (and saved for offline use) before the
  /// student taps them. Once built, a tab stays alive.
  final Set<int> _built = {0};
  Timer? _warmUp;
  Timer? _pushOffer;
  late final NotificationRouter _router = ref.read(notificationRouterProvider);

  @override
  void initState() {
    super.initState();
    _warmUp = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _built.addAll(const [1, 2, 3]));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // From here on a notification tap can be shown (one that came while the
      // app was starting is shown now).
      final userId = ref.read(sessionUserIdProvider);
      if (userId != null) _router.attach(userId, this);
    });
    // Once the home screen has settled, and only the first time on this phone.
    _pushOffer = Timer(const Duration(seconds: 3), () {
      // The app says why first; the phone's own question comes after a yes.
      if (mounted) offerPushNotificationsOnce(context, ref);
    });
  }

  @override
  void dispose() {
    _router.detach(this);
    _warmUp?.cancel();
    _pushOffer?.cancel();
    super.dispose();
  }

  @override
  Set<NotificationDestination> get destinations => NotificationDestination.values.toSet();

  @override
  void showDestination(NotificationDestination destination, NotificationIntent intent) {
    if (!mounted) return;
    // Whatever was open on top (a sheet, the purchase flow) makes way.
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (destination) {
      case NotificationDestination.home:
        _selectTab(0);
      case NotificationDestination.subscription:
        // The subscriptions tab opens the card the notification is about.
        ref.read(focusedSubscriptionProvider.notifier).state = intent.subscriptionId;
        _selectTab(1);
      case NotificationDestination.card:
        _selectTab(2);
      case NotificationDestination.center:
        NotificationsScreen.open(context);
    }
  }

  // Every tab change shows the full bar again.
  void _selectTab(int index) => setState(() {
        _currentIndex = index;
        _built.add(index);
        _navCollapsed = false;
      });

  /// "إعادة المحاولة" in the connection strip: everything the tabs show is
  /// read again, as when the app comes back to the front.
  void _retryConnection() {
    final userId = ref.read(sessionUserIdProvider);
    ref.invalidate(currentSubscriptionProvider);
    ref.invalidate(allSubscriptionsProvider);
    ref.invalidate(studentQrProvider);
    ref.invalidate(myInvitesProvider);
    ref.invalidate(notificationFeedProvider);
    if (userId != null) ref.invalidate(studentProfileSummaryProvider(userId));
    ref.invalidate(voteSettingsProvider);
    ref.read(rideStatusTickProvider.notifier).state++;
  }

  bool _onScroll(ScrollNotification notification) {
    final collapse = FloatingGlassNavBar.collapseOnScroll(notification);
    if (collapse != null && collapse != _navCollapsed) {
      setState(() => _navCollapsed = collapse);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      StudentHomeScreen(
        onNavigateToSubscription: () => _selectTab(1),
        onNavigateToQr: () => _selectTab(2),
      ),
      // In front or not: behind another tab it does not read what is on sale.
      SubscriptionScreen(visible: _currentIndex == 1),
      const StudentQrScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      // Every tab stays alive: switching tabs never reloads or shows a spinner.
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // Home places the strip itself, under its header; over the other tabs
        // it takes the top of the screen.
        child: ConnectionStripHost(
          enabled: _currentIndex != 0,
          onRetry: _retryConnection,
          child: IndexedStack(index: _currentIndex, children: [
            for (var i = 0; i < screens.length; i++)
              _built.contains(i) ? screens[i] : const SizedBox.shrink(),
          ]),
        ),
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _selectTab,
        items: FloatingGlassNavBar.studentNavItems,
        collapsed: _navCollapsed,
        onExpand: () => setState(() => _navCollapsed = false),
      ),
    );
  }
}
