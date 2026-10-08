import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/models/user_role.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/notifications/data/notification_feed.dart';
import '../../features/notifications/data/notification_preferences.dart';
import '../../features/notifications/data/quick_templates.dart';
import '../../features/student/home/presentation/student_home_screen.dart';
import '../../features/student/invites/invites.dart';
import '../../features/student/qr/presentation/student_qr_screen.dart';
import '../../features/student/subscription/presentation/purchase_flow.dart';
import '../../features/student/subscription/presentation/subscription_screen.dart';
import '../../features/supervisor/data/supervisor_repository.dart';
import '../../features/supervisor/trips/presentation/supervisor_trips_screen.dart';
import '../network/supabase_service.dart';
import '../storage/offline_cache.dart';

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

  /// The tables whose screens show a saved read (see OfflineCache.readThrough).
  @visibleForTesting
  static Set<String> tablesFor(String key) {
    if (key == 'profile.summary' || key == 'student_pass') return const {'students'};
    // Read on their own: nothing else is fetched again for them.
    if (key == 'notification_preferences' || key == 'notification_templates') return {key};
    if (key.startsWith('subscriptions') || key.startsWith('receipts.') || key.startsWith('subscription_receipt')) {
      return const {'subscriptions'};
    }
    if (key == 'sale_catalog' || key.startsWith('payment_methods')) return const {'lines'};
    if (key.startsWith('notifications')) return const {'notifications'};
    if (key.startsWith('supervisor.') || key.startsWith('rider_counts')) {
      return const {'supervisor_scan_events', 'supervisors'};
    }
    return _everything;
  }

  static const _everything = {
    'subscriptions', 'lines', 'company_invites', 'students', 'notifications', 'supervisor_scan_events', 'supervisors',
  };

  /// The topics of an account: its own (`user:`, personal notifications and
  /// what it read on another phone, for every role), and those of its role.
  @visibleForTesting
  static Set<String> topicsFor({
    required String? userId,
    required UserRole role,
    String? lineId,
    String? companyId,
  }) {
    if (userId == null) return const {};
    return {
      'user:$userId',
      if (role == UserRole.student) ...{
        'student:$userId',
        if (lineId != null && lineId.isNotEmpty) 'line:$lineId',
      },
      if (role == UserRole.supervisor && companyId != null && companyId.isNotEmpty)
        'company:$companyId',
    };
  }

  /// The table a live event is about. Its `op` (INSERT, DELETE, or READ for
  /// notifications read on another phone) changes nothing here: whatever
  /// happened to the table, its screens read it again.
  @visibleForTesting
  static String tableOf(Map<dynamic, dynamic> message) {
    // The table name is in the event body; older clients wrap it in `payload`.
    final body = message['payload'] is Map ? message['payload'] as Map : message;
    return body['table'] as String? ?? '';
  }

  /// Marks stale exactly what shows [tables], and nothing else: a notification
  /// arriving or being read re-reads the inbox only.
  @visibleForTesting
  static void invalidateFor(
      void Function(ProviderOrFamily provider) invalidate, Set<String> tables, UserRole role, String? userId) {
    if (tables.contains('notifications')) invalidate(notificationFeedProvider);
    if (tables.contains('notification_preferences')) invalidate(notificationPreferencesProvider);
    if (tables.contains('notification_templates')) invalidate(quickTemplatesProvider);
    const ownScreens = {'notifications', 'notification_preferences', 'notification_templates'};
    if (tables.every(ownScreens.contains)) return;
    if (role == UserRole.student) {
      const subscriptionTables = {'subscriptions', 'receipts', 'company_students', 'lines', 'stations', 'line_trips', 'supervisor_lines'};
      if (tables.any(subscriptionTables.contains)) {
        invalidate(currentSubscriptionProvider);
        invalidate(allSubscriptionsProvider);
        invalidate(subscriptionReceiptsProvider);
        invalidate(studentQrProvider);
      }
      // What is on sale depends on the lines, their prices and what the student holds.
      if (tables.any(const {'lines', 'stations', 'line_trips', 'line_period_prices', 'subscriptions'}.contains)) {
        invalidate(saleCatalogProvider);
      }
      if (tables.contains('subscriptions')) invalidate(subscriptionReceiptDocProvider);
      if (tables.contains('company_invites') || tables.contains('company_students')) {
        invalidate(myInvitesProvider);
      }
      if (tables.contains('students')) {
        if (userId != null) invalidate(studentProfileSummaryProvider(userId));
        invalidate(studentQrProvider);
      }
    } else if (role == UserRole.supervisor) {
      invalidate(supervisorDashboardProvider);
      invalidate(tripManifestProvider);
      invalidate(offeredSubscriptionTypesProvider);
      if (tables.contains('supervisors')) invalidate(supervisorPhotoUrlProvider);
      if (tables.contains('supervisor_scan_events')) invalidate(supervisorMonthlySummaryProvider);
    }
  }

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> with WidgetsBindingObserver {
  final Map<String, RealtimeChannel> _channels = {};
  final Set<String> _lostTopics = {};
  Timer? _debounce;
  final Set<String> _pendingTables = {};
  DateTime _lastFullRefresh = DateTime.now();
  Timer? _offlineRetry;

  SupabaseClient get _client => SupabaseService.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _retune());
    OfflineCache.refreshed.addListener(_onSavedCopyRefreshed);
    OfflineCache.offlineSince.addListener(_onOfflineChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OfflineCache.refreshed.removeListener(_onSavedCopyRefreshed);
    OfflineCache.offlineSince.removeListener(_onOfflineChanged);
    _offlineRetry?.cancel();
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

  /// A screen opened from its saved copy and the server had something newer:
  /// show it. The values are already in memory, so this costs no request.
  void _onSavedCopyRefreshed() {
    if (!mounted) return;
    _debounce?.cancel();
    // Only what shows the data that changed is read again.
    for (final key in OfflineCache.takeRefreshedKeys()) {
      _pendingTables.addAll(SyncScope.tablesFor(key));
    }
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final tables = Set<String>.from(_pendingTables);
      _pendingTables.clear();
      _invalidateFor(tables);
    });
  }

  /// While saved data is on screen, try again quietly until the server answers;
  /// the first answer brings everything up to date.
  void _onOfflineChanged() {
    final offline = OfflineCache.offlineSince.value != null;
    if (offline && _offlineRetry == null) {
      _offlineRetry = Timer.periodic(const Duration(seconds: 20), (_) => _refreshEverything());
    } else if (!offline) {
      _offlineRetry?.cancel();
      _offlineRetry = null;
    }
  }

  /// The topics this account should be listening to right now.
  Set<String> _wantedTopics() {
    final auth = ref.read(authStateProvider);
    return SyncScope.topicsFor(
      userId: auth.user?.id,
      role: auth.role,
      lineId: auth.role == UserRole.student
          ? ref.read(currentSubscriptionProvider).valueOrNull?.lineId
          : null,
      companyId: auth.role == UserRole.supervisor
          ? ref.read(supervisorDashboardProvider).valueOrNull?.profile.companyId
          : null,
    );
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
          _onChange(SyncScope.tableOf(message));
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

  void _invalidateFor(Set<String> tables) => SyncScope.invalidateFor(
      ref.invalidate, tables, ref.read(authStateProvider).role, ref.read(authStateProvider).user?.id);

  void _refreshEverything() {
    if (!mounted) return;
    // Resume and reconnect often arrive together; once is enough.
    final now = DateTime.now();
    if (now.difference(_lastFullRefresh) < const Duration(seconds: 2)) return;
    _lastFullRefresh = now;
    final role = ref.read(authStateProvider).role;
    if (role == UserRole.student) {
      _invalidateFor(const {'subscriptions', 'lines', 'company_invites', 'students', 'notifications'});
      // Company settings (sale switches, vote times) send no event to students.
      ref.invalidate(saleCatalogProvider);
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
