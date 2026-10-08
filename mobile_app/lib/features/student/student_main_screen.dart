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

  @override
  Widget build(BuildContext context) {
    final screens = [
      StudentHomeScreen(
        onNavigateToSubscription: () => setState(() => _currentIndex = 1),
        onNavigateToQr: () => setState(() => _currentIndex = 2),
      ),
      const SubscriptionScreen(),
      const StudentQrScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      // Every tab stays alive: switching tabs never reloads or shows a spinner.
      body: OfflineBanner(
        child: IndexedStack(index: _currentIndex, children: screens),
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        currentIndex: _currentIndex,
        onTabSelected: (index) => setState(() => _currentIndex = index),
        items: FloatingGlassNavBar.studentNavItems,
      ),
    );
  }
}
