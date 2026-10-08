import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/sync/session.dart';
import '../../core/widgets/floating_glass_nav_bar.dart';
import '../../core/widgets/offline_banner.dart';
import '../notifications/notification_router.dart';
import '../notifications/presentation/push_permission_sheet.dart';
import '../notifications/push/push_providers.dart';
import 'notifications/supervisor_notifications_screen.dart';
import 'home/presentation/supervisor_home_screen.dart';
import 'monthly/presentation/supervisor_monthly_screen.dart';
import 'profile/presentation/supervisor_profile_screen.dart';
import 'qr_scanner/presentation/supervisor_qr_scanner_screen.dart';
import 'trips/presentation/supervisor_trips_screen.dart';

class SupervisorMainScreen extends ConsumerStatefulWidget {
  const SupervisorMainScreen({super.key});

  @override
  ConsumerState<SupervisorMainScreen> createState() => _SupervisorMainScreenState();
}

class _SupervisorMainScreenState extends ConsumerState<SupervisorMainScreen>
    implements NotificationShell {
  int _currentIndex = 0;
  bool _navCollapsed = false;
  Timer? _pushOffer;
  late final NotificationRouter _router = ref.read(notificationRouterProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // From here on a notification tap can be shown (one that came while the
      // app was starting is shown now).
      final userId = ref.read(sessionUserIdProvider);
      if (userId != null) _router.attach(userId, this);
    });
    // Once the home screen has settled, and only the first time on this phone.
    _pushOffer = Timer(const Duration(seconds: 3), () {
      if (mounted) offerPushNotificationsOnce(context, ref);
    });
  }

  @override
  void dispose() {
    _router.detach(this);
    _pushOffer?.cancel();
    super.dispose();
  }

  /// A supervisor has no subscription or card: those open the Notification Center.
  @override
  Set<NotificationDestination> get destinations =>
      const {NotificationDestination.home, NotificationDestination.center};

  @override
  void showDestination(NotificationDestination destination, NotificationIntent intent) {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (destination == NotificationDestination.home) {
      _selectTab(0);
    } else {
      SupervisorNotificationsScreen.open(context);
    }
  }

  // Every tab change shows the full bar again.
  void _selectTab(int index) => setState(() {
        _currentIndex = index;
        _navCollapsed = false;
      });

  bool _onScroll(ScrollNotification notification) {
    final collapse = FloatingGlassNavBar.collapseOnScroll(notification);
    if (collapse != null && collapse != _navCollapsed) {
      setState(() => _navCollapsed = collapse);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Per-trip rider counts open from the Home tab. Receipt review is an
    // admin-only task (dashboard), never part of the supervisor app.
    final screens = [
      SupervisorHomeScreen(onOpenScanner: () => _selectTab(2)),
      // Going / Return trips: route, students per station, check-in state.
      const SupervisorTripsScreen(),
      const SupervisorQrScannerScreen(),
      const SupervisorMonthlyScreen(),
      const SupervisorProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: OfflineBanner(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_currentIndex),
              child: screens[_currentIndex],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _selectTab,
        items: FloatingGlassNavBar.supervisorNavItems,
        collapsed: _navCollapsed,
        onExpand: () => setState(() => _navCollapsed = false),
      ),
    );
  }
}
