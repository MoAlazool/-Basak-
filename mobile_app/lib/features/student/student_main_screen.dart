import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/widgets/floating_glass_nav_bar.dart';
import '../../core/widgets/offline_banner.dart';
import 'home/presentation/student_home_screen.dart';
import 'subscription/presentation/subscription_screen.dart';
import 'qr/presentation/student_qr_screen.dart';
import 'profile/presentation/profile_screen.dart';

class StudentMainScreen extends StatefulWidget {
  const StudentMainScreen({super.key});

  @override
  State<StudentMainScreen> createState() => _StudentMainScreenState();
}

class _StudentMainScreenState extends State<StudentMainScreen> {
  int _currentIndex = 0;
  bool _navCollapsed = false;

  /// Tabs that have been built. The home tab comes first, alone, so the app
  /// opens on its own data only; the others are built a moment later, in the
  /// background, so they are ready (and saved for offline use) before the
  /// student taps them. Once built, a tab stays alive.
  final Set<int> _built = {0};
  Timer? _warmUp;

  @override
  void initState() {
    super.initState();
    _warmUp = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _built.addAll(const [1, 2, 3]));
    });
  }

  @override
  void dispose() {
    _warmUp?.cancel();
    super.dispose();
  }

  // Every tab change shows the full bar again.
  void _selectTab(int index) => setState(() {
        _currentIndex = index;
        _built.add(index);
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
    final screens = [
      StudentHomeScreen(
        onNavigateToSubscription: () => _selectTab(1),
        onNavigateToQr: () => _selectTab(2),
      ),
      const SubscriptionScreen(),
      const StudentQrScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      // Every tab stays alive: switching tabs never reloads or shows a spinner.
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: OfflineBanner(
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
