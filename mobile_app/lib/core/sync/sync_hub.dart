import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/models/user_role.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/student/home/presentation/student_home_screen.dart';
import '../../features/student/invites/invites.dart';
import '../../features/student/qr/presentation/student_qr_screen.dart';
import '../../features/student/subscription/presentation/subscription_screen.dart';
import '../../features/supervisor/data/supervisor_repository.dart';
import '../../features/supervisor/trips/presentation/supervisor_trips_screen.dart';
import '../network/supabase_service.dart';

/// Bumped whenever the student's ride vote should be read again (app resume,
/// reconnect). The home screen listens to it.
final rideStatusTickProvider = StateProvider<int>((ref) => 0);

/// Keeps what is on screen current without the user refreshing anything.
///
/// The server announces changes on private topics (ids only, never contents);
/// which topics an account may join is decided by the database. Each event marks
/// the matching providers stale, and they re-read through the normal queries.
/// Returning to the app, or the connection coming back, revalidates everything.
class SyncScope extends ConsumerStatefulWidget {
  final Widget child;
  const SyncScope({super.key, required this.child});

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> with WidgetsBindingObserver {
  final Map<String, RealtimeChannel> _channels = {};
  final Set<String> _lostTopics = {};
  Timer? _debounce;
  final Set<String> _pendingTables = {};
  DateTime _lastFullRefresh = DateTime.now();

  SupabaseClient get _client => SupabaseService.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _retune());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    for (final channel in _channels.values) {
      _client.removeChannel(channel);
    }
    _channels.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground: whatever changed while the app slept is fetched now.
    if (state == AppLifecycleState.resumed) _refreshEverything();
  }

  /// The topics this account should be listening to right now.
  Set<String> _wantedTopics() {
    final auth = ref.read(authStateProvider);
    final userId = auth.user?.id;
    if (userId == null) return const {};
    if (auth.role == UserRole.student) {
      final lineId = ref.read(currentSubscriptionProvider).valueOrNull?.lineId;
      return {'student:$userId', if (lineId != null && lineId.isNotEmpty) 'line:$lineId'};
    }
    if (auth.role == UserRole.supervisor) {
      final companyId = ref.read(supervisorDashboardProvider).valueOrNull?.profile.companyId;
      return {if (companyId != null && companyId.isNotEmpty) 'company:$companyId'};
    }
    return const {};
  }

  /// Joins missing topics and leaves the ones no longer needed.
  void _retune() {
    if (!mounted) return;
    final wanted = _wantedTopics();
    for (final topic in _channels.keys.toList()) {
      if (!wanted.contains(topic)) {
        _client.removeChannel(_channels.remove(topic)!);
        _lostTopics.remove(topic);
      }
    }
    for (final topic in wanted) {
      if (_channels.containsKey(topic)) continue;
      final channel = _client.channel(topic, opts: const RealtimeChannelConfig(private: true));
      channel.onBroadcast(
        event: 'change',
        callback: (message) {
          // The table name is in the event body; older clients wrap it in `payload`.
          final body = message['payload'] is Map ? message['payload'] as Map : message;
          _onChange(body['table'] as String? ?? '');
        },
      );
      channel.subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          // Rejoined after a drop: events were missed meanwhile, so re-read.
          if (_lostTopics.remove(topic)) _refreshEverything();
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          _lostTopics.add(topic);
        }
      });
      _channels[topic] = channel;
    }
  }

  void _onChange(String table) {
    _pendingTables.add(table);
    // One refresh for a burst (approving a receipt touches three tables).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final tables = Set<String>.from(_pendingTables);
      _pendingTables.clear();
      _invalidateFor(tables);
    });
  }

  void _invalidateFor(Set<String> tables) {
    final role = ref.read(authStateProvider).role;
    if (tables.contains('notifications')) ref.invalidate(myNotificationsProvider);
    if (role == UserRole.student) {
      const subscriptionTables = {'subscriptions', 'receipts', 'company_students', 'lines', 'stations', 'line_trips', 'supervisor_lines'};
      if (tables.any(subscriptionTables.contains)) {
        ref.invalidate(currentSubscriptionProvider);
        ref.invalidate(allSubscriptionsProvider);
        ref.invalidate(subscriptionReceiptsProvider);
        ref.invalidate(studentQrProvider);
      }
      if (tables.any(const {'lines', 'stations', 'line_trips'}.contains)) {
        ref.invalidate(studentCatalogProvider);
        ref.invalidate(allLinesProvider);
      }
      if (tables.contains('company_invites') || tables.contains('company_students')) {
        ref.invalidate(myInvitesProvider);
      }
      if (tables.contains('students')) {
        final userId = ref.read(authStateProvider).user?.id;
        if (userId != null) ref.invalidate(studentProfileSummaryProvider(userId));
        ref.invalidate(studentQrProvider);
      }
    } else if (role == UserRole.supervisor) {
      ref.invalidate(supervisorDashboardProvider);
      ref.invalidate(tripManifestProvider);
      ref.invalidate(offeredSubscriptionTypesProvider);
      if (tables.contains('supervisors')) ref.invalidate(supervisorPhotoUrlProvider);
      if (tables.contains('supervisor_scan_events')) ref.invalidate(supervisorMonthlySummaryProvider);
    }
  }

  void _refreshEverything() {
    if (!mounted) return;
    // Resume and reconnect often arrive together; once is enough.
    final now = DateTime.now();
    if (now.difference(_lastFullRefresh) < const Duration(seconds: 2)) return;
    _lastFullRefresh = now;
    final role = ref.read(authStateProvider).role;
    if (role == UserRole.student) {
      _invalidateFor(const {'subscriptions', 'lines', 'company_invites', 'students', 'notifications'});
      // Company settings (annual / daily switches, vote times) send no event to students.
      ref.invalidate(purchasablePeriodsProvider);
      ref.invalidate(dailySubscriptionEnabledProvider);
      ref.invalidate(voteSettingsProvider);
      ref.read(rideStatusTickProvider.notifier).state++;
    } else if (role == UserRole.supervisor) {
      _invalidateFor(const {'supervisor_scan_events', 'notifications', 'supervisors'});
    }
    _retune();
  }

  @override
  Widget build(BuildContext context) {
    // The topics depend on who is signed in and on what they are subscribed to.
    ref.listen(authStateProvider.select((s) => s.user?.id), (_, __) => _retune());
    ref.listen(currentSubscriptionProvider.select((s) => s.valueOrNull?.lineId), (_, __) => _retune());
    ref.listen(supervisorDashboardProvider.select((s) => s.valueOrNull?.profile.companyId), (_, __) => _retune());
    return widget.child;
  }
}
