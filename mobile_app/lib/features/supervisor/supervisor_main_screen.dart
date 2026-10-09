import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/session.dart';
import '../../core/theme/app_icons.dart';
import '../../core/ui/ui.dart';
import '../../core/widgets/connection_strip_host.dart';
import '../../core/widgets/floating_glass_nav_bar.dart';
import '../auth/providers/auth_provider.dart';
import '../notifications/data/notification_feed.dart';
import '../notifications/notification_router.dart';
import '../notifications/presentation/push_permission_sheet.dart';
import '../notifications/push/push_providers.dart';
import 'data/supervisor_repository.dart';
import 'home/presentation/supervisor_home_screen.dart';
import 'notifications/supervisor_notifications_screen.dart';
import 'profile/presentation/supervisor_profile_screen.dart';
import 'qr_scanner/presentation/supervisor_qr_scanner_screen.dart';
import 'selection/supervisor_selection.dart';
import 'trips/presentation/supervisor_trips_screen.dart';

/// The supervisor's app: four tabs on the floating pill — الرئيسية (the
/// numbers), الرحلات (one trip), مسح (boarding, the filled one) and حسابي.
/// The line and the trip chosen on one tab hold on the others
/// ([supervisorSelectionProvider]). A suspended account sees one blocking
/// screen instead of the tabs.
class SupervisorMainScreen extends ConsumerStatefulWidget {
  const SupervisorMainScreen({super.key});

  static const homeTab = 0, tripsTab = 1, scanTab = 2, accountTab = 3;

  @override
  ConsumerState<SupervisorMainScreen> createState() => _SupervisorMainScreenState();
}

class _SupervisorMainScreenState extends ConsumerState<SupervisorMainScreen>
    implements NotificationShell {
  int _currentIndex = SupervisorMainScreen.homeTab;
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
      // A new sign-in starts from its own first line, on today.
      ref.read(supervisorSelectionProvider.notifier).reset();
      ref.read(supervisorTripDayProvider.notifier).state = null;
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
      _selectTab(SupervisorMainScreen.homeTab);
    } else {
      SupervisorNotificationsScreen.open(context);
    }
  }

  // Every tab change shows the full bar again.
  void _show(int index) => setState(() {
        _currentIndex = index;
        _navCollapsed = false;
      });

  /// A tab chosen on the bar. Trips opened this way is about today; a trip of
  /// tomorrow is only ever opened from Home's card of tomorrow.
  void _selectTab(int index) {
    if (index == SupervisorMainScreen.tripsTab) ref.read(supervisorTripDayProvider.notifier).state = null;
    _show(index);
  }

  /// "إعادة المحاولة" in the connection strip: what the tabs show is read again.
  void _retryConnection() {
    ref.invalidate(supervisorDashboardProvider);
    ref.invalidate(lineCapacitiesProvider);
    ref.invalidate(tripManifestProvider);
    ref.invalidate(supervisorMonthlySummaryProvider);
    ref.invalidate(notificationFeedProvider);
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
    // One blocking screen for the whole app, not a card on Home.
    final suspended =
        ref.watch(supervisorDashboardProvider.select((d) => d.valueOrNull?.profile.isActive == false));
    if (suspended) return const SupervisorSuspendedScreen();

    // Only the tab in front is built: the camera never runs behind another
    // tab. What a tab chose is kept in providers, not in the tab.
    final screen = switch (_currentIndex) {
      SupervisorMainScreen.homeTab =>
        SupervisorHomeScreen(onOpenTrips: () => _show(SupervisorMainScreen.tripsTab)),
      SupervisorMainScreen.tripsTab => const SupervisorTripsScreen(),
      SupervisorMainScreen.scanTab => const SupervisorQrScannerScreen(),
      _ => const SupervisorProfileScreen(),
    };

    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // Home places the strip itself, under its header, and the scanner says
        // it on the camera; over the other tabs it takes the top of the screen.
        child: ConnectionStripHost(
          enabled: _currentIndex == SupervisorMainScreen.tripsTab || _currentIndex == SupervisorMainScreen.accountTab,
          onRetry: _retryConnection,
          note: _currentIndex == SupervisorMainScreen.tripsTab ? 'المسح لا يسجّل الصعود الآن' : null,
          child: AnimatedSwitcher(
            duration: BasakMotion.fade,
            switchInCurve: BasakMotion.fadeCurve,
            switchOutCurve: BasakMotion.fadeCurve,
            child: KeyedSubtree(key: ValueKey(_currentIndex), child: screen),
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

/// The company stopped this supervisor's account: nothing else of the app is
/// shown until it is active again.
class SupervisorSuspendedScreen extends ConsumerWidget {
  const SupervisorSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: context.colors.ground,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, safe.top + BasakSpace.s24, BasakSpace.gutter,
                  safe.bottom > 0 ? safe.bottom + BasakSpace.s8 : BasakSpace.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: ToneState(
                          icon: LucideIcons.userX,
                          tone: BasakTone.danger,
                          title: 'الحساب موقوف',
                          message: 'أوقفت إدارة الشركة حساب المشرف. تواصل مع شركتك لإعادة تفعيله.',
                        ),
                      ),
                    ),
                  ),
                  BasakButton(
                    key: const Key('suspended-retry'),
                    label: 'إعادة المحاولة',
                    icon: LucideIcons.refreshCw,
                    variant: BasakButtonVariant.secondary,
                    onPressed: () => ref.invalidate(supervisorDashboardProvider),
                  ),
                  const SizedBox(height: BasakSpace.s8),
                  BasakButton(
                    key: const Key('suspended-sign-out'),
                    label: 'تسجيل الخروج',
                    variant: BasakButtonVariant.danger,
                    size: BasakButtonSize.medium,
                    onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
