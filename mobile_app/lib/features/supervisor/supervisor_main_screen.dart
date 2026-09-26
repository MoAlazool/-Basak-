import 'package:flutter/material.dart';
import '../../core/widgets/floating_glass_nav_bar.dart';
import 'receipts/presentation/supervisor_receipts_screen.dart';
import 'rider_counts/presentation/rider_counts_screen.dart';
import 'qr_scanner/presentation/supervisor_qr_scanner_screen.dart';
import '../student/chat/presentation/chat_screen.dart';
import '../student/profile/presentation/profile_screen.dart';

class SupervisorMainScreen extends StatefulWidget {
  const SupervisorMainScreen({super.key});

  @override
  State<SupervisorMainScreen> createState() => _SupervisorMainScreenState();
}

class _SupervisorMainScreenState extends State<SupervisorMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const RiderCountsScreen(),
      const SupervisorReceiptsScreen(),
      const SupervisorQrScannerScreen(),
      const ChatScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        currentIndex: _currentIndex,
        onTabSelected: (index) => setState(() => _currentIndex = index),
        items: FloatingGlassNavBar.supervisorNavItems,
      ),
    );
  }
}
