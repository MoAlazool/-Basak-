import 'package:flutter/material.dart';
import '../../core/widgets/floating_glass_nav_bar.dart';
import '../../core/widgets/offline_banner.dart';
import 'home/presentation/supervisor_home_screen.dart';
import 'monthly/presentation/supervisor_monthly_screen.dart';
import 'profile/presentation/supervisor_profile_screen.dart';
import 'qr_scanner/presentation/supervisor_qr_scanner_screen.dart';
import 'trips/presentation/supervisor_trips_screen.dart';

class SupervisorMainScreen extends StatefulWidget {
  const SupervisorMainScreen({super.key});

  @override
  State<SupervisorMainScreen> createState() => _SupervisorMainScreenState();
}

class _SupervisorMainScreenState extends State<SupervisorMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Per-trip rider counts open from the Home tab. Receipt review is an
    // admin-only task (dashboard), never part of the supervisor app.
    final screens = [
      SupervisorHomeScreen(onOpenScanner: () => setState(() => _currentIndex = 2)),
      // Going / Return trips: route, students per station, check-in state.
      const SupervisorTripsScreen(),
      const SupervisorQrScannerScreen(),
      const SupervisorMonthlyScreen(),
      const SupervisorProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: OfflineBanner(
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
      bottomNavigationBar: FloatingGlassNavBar(
        currentIndex: _currentIndex,
        onTabSelected: (index) => setState(() => _currentIndex = index),
        items: FloatingGlassNavBar.supervisorNavItems,
      ),
    );
  }
}
