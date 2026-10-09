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
import '../../features/student/subscription/models/subscription_model.dart';
import 'own_changes.dart';

export 'own_changes.dart';

/// Bumped whenever the student's ride vote should be read again (app resume,
/// reconnect). The home screen listens to it.
final rideStatusTickProvider = StateProvider<int>((ref) => 0);

/// Bumped when the rider counts a supervisor is looking at were opened from
/// their saved copy and the server had newer ones. The counts screen listens
/// to it (and gets the fresh numbers from memory, without a request).
final riderCountsTickProvider = StateProvider<int>((ref) => 0);

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
    if (key == 'profile.summary') return const {'students'};
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

  /// Changes in the company that nothing in the supervisor's app shows.
  @visibleForTesting
  static const supervisorUnrelatedTables = {
    'receipts', 'complaints', 'company_payment_methods', 'wallet_card_settings', 'password_reset_requests',
    'company_invites', 'student_correction_requests', 'line_period_prices',
    'notifications', 'notification_preferences', 'notification_templates',
  };

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

  /// What a live event says: the table, what happened to it and to which row.
  @visibleForTesting
  static SyncEvent eventOf(Map<dynamic, dynamic> message) {
    // The event's fields are in its body; older clients wrap it in `payload`.
    final body = message['payload'] is Map ? message['payload'] as Map : message;
    return SyncEvent(body['table'] as String? ?? '',
        op: body['op'] as String? ?? '', id: body['id']?.toString());
  }

  /// The table a live event is about.
  @visibleForTesting
  static String tableOf(Map<dynamic, dynamic> message) => eventOf(message).table;

  /// Marks stale exactly what shows [tables], and nothing else: a notification
  /// arriving or being read re-reads the inbox only, and a receipt re-reads the
  /// subscriptions and their receipts, not the card or what is on sale.
  ///
  /// [subscriptionChanged] is whether a `subscriptions` change is known (or
  /// has to be assumed) to alter what the card, the sale catalog and the
  /// issued receipt show: its status, line, station or dates. When the caller
  /// can tell that it did not, those three are left alone.
  @visibleForTesting
  static void invalidateFor(
      void Function(ProviderOrFamily provider) invalidate, Set<String> tables, UserRole role, String? userId,
      {bool subscriptionChanged = true}) {
    if (tables.contains('notifications')) invalidate(notificationFeedProvider);
    if (tables.contains('notification_preferences')) invalidate(notificationPreferencesProvider);
    if (tables.contains('notification_templates')) invalidate(quickTemplatesProvider);
    const ownScreens = {'notifications', 'notification_preferences', 'notification_templates'};
    if (tables.every(ownScreens.contains)) return;
    if (role == UserRole.student) {
      final subscription = tables.contains('subscriptions');
      // What the subscription cards are built from (names, times, the supervisor).
      const lineTables = {'company_students', 'lines', 'stations', 'line_trips', 'supervisor_lines'};
      final line = tables.any(lineTables.contains);
      if (subscription || line || tables.contains('receipts')) {
        invalidate(currentSubscriptionProvider);
        invalidate(allSubscriptionsProvider);
      }
      if (subscription || tables.contains('receipts')) invalidate(subscriptionReceiptsProvider);
      // The card shows the student, the line, the station and the subscription's state.
      if (line || tables.contains('students') || (subscription && subscriptionChanged)) {
        invalidate(studentQrProvider);
      }
      // What is on sale depends on the lines, their prices and what the student holds.
      if (tables.any(const {'lines', 'stations', 'line_trips', 'line_period_prices'}.contains) ||
          (subscription && subscriptionChanged)) {
        invalidate(saleCatalogProvider);
      }
      if (subscription && subscriptionChanged) invalidate(subscriptionReceiptDocProvider);
      if (tables.contains('company_invites') || tables.contains('company_students')) {
        invalidate(myInvitesProvider);
      }
      if (tables.contains('students') && userId != null) {
        invalidate(studentProfileSummaryProvider(userId));
      }
    } else if (role == UserRole.supervisor) {
      // A supervisor hears of every change in the company. Most of it shows
      // nowhere in this app (a receipt sent or reviewed, a payment method, the
      // Wallet card's design, a password reset, an invitation, a price): for
      // those nothing is read. Anything else, a table this version does not
      // know included, may change the day's numbers and the trip lists.
      if (!tables.every(supervisorUnrelatedTables.contains)) {
        invalidate(supervisorDashboardProvider);
        invalidate(tripManifestProvider);
      }
      // Which subscription types are on sale is the company's own switches.
      if (tables.contains('companies')) invalidate(offeredSubscriptionTypesProvider);
      if (tables.contains('supervisors')) invalidate(supervisorPhotoUrlProvider);
      if (tables.contains('supervisor_scan_events')) invalidate(supervisorMonthlySummaryProvider);
    }
  }

  /// Whether a change to the subscriptions named by [events] alters what the
  /// card, the sale catalog or an issued receipt show. The event carries ids
  /// only, so this compares the subscriptions as they were with how they were
  /// just read again: a subscription that appeared or went, or whose status,
  /// line, station, type or dates differ. Unknown ([before] never loaded) is
  /// taken as yes.
  @visibleForTesting
  static bool subscriptionChangeMatters(
      List<SubscriptionModel>? before, List<SubscriptionModel> after, Iterable<SyncEvent> events) {
    if (before == null) return true;
    SubscriptionModel? find(List<SubscriptionModel> list, String? id) {
      for (final s in list) {
        if (s.id == id) return s;
      }
      return null;
    }

    for (final event in events) {
      if (event.op != 'UPDATE' || event.id == null) return true;
      final was = find(before, event.id), now = find(after, event.id);
      if (was == null || now == null) {
        if (was != now) return true;
        continue;
      }
      if (was.status != now.status ||
          was.lineId != now.lineId ||
          was.stationId != now.stationId ||
          was.type != now.type ||
          was.startDate != now.startDate ||
          was.endDate != now.endDate) {
        return true;
      }
    }
    return false;
  }

  /// Acts on live [events]: drops the ones that only repeat what this phone
  /// did itself, then marks stale what the rest are about. For a subscription
  /// the card, the catalog and the issued receipt are read again only when
  /// the re-read subscriptions show that it matters.
  @visibleForTesting
  static Future<void> onEvents(
    Iterable<SyncEvent> events, {
    required void Function(ProviderOrFamily provider) invalidate,
    required T Function<T>(ProviderListenable<T> provider) read,
    required UserRole role,
    required String? userId,
  }) =>
      _handle(withoutEchoes(events), invalidate: invalidate, read: read, role: role, userId: userId);

  /// [events] without this phone's own echoes, and without news it already
  /// acted on (a notification whose push arrived first).
  @visibleForTesting
  static List<SyncEvent> withoutEchoes(Iterable<SyncEvent> events) => [
        for (final event in events)
          if (!OwnChanges.isEcho(event) &&
              (event.table != 'notifications' ||
                  event.op != 'INSERT' ||
                  event.id == null ||
                  OwnChanges.firstSight('notifications', event.id!)))
            event,
      ];

  static Future<void> _handle(
    List<SyncEvent> events, {
    required void Function(ProviderOrFamily provider) invalidate,
    required T Function<T>(ProviderListenable<T> provider) read,
    required UserRole role,
    required String? userId,
  }) async {
    if (events.isEmpty) return;
    // News from elsewhere: nothing this phone wrote itself may answer for it.
    OfflineCache.forgetLocal();
    final tables = {for (final event in events) event.table};
    final changed = [
      for (final event in events)
        if (event.table == 'subscriptions') event
    ];
    if (role != UserRole.student || changed.isEmpty) {
      invalidateFor(invalidate, tables, role, userId);
      return;
    }
    final before = read(allSubscriptionsProvider).valueOrNull;
    invalidateFor(invalidate, tables, role, userId, subscriptionChanged: false);
    final List<SubscriptionModel> after;
    try {
      after = await read(allSubscriptionsProvider.future);
    } catch (_) {
      return; // Unreachable: resume and reconnect read everything again.
    }
    if (!subscriptionChangeMatters(before, after, changed)) return;
    invalidate(studentQrProvider);
    invalidate(saleCatalogProvider);
    for (final event in changed) {
      invalidate(event.id == null ? subscriptionReceiptDocProvider : subscriptionReceiptDocProvider(event.id!));
    }
  }

  /// The provider that shows the saved read [key], when it is the only one
  /// (null: see [tablesFor]). A saved copy that turned out stale is then shown
  /// by re-reading just that provider, which is answered from memory.
  @visibleForTesting
  static ProviderOrFamily? providerFor(String key, String? userId) {
    String rest(String prefix) => key.substring(prefix.length);
    if (key == 'subscriptions') return allSubscriptionsProvider;
    if (key == 'subscriptions.current') return currentSubscriptionProvider;
    if (key == 'profile.summary') return userId == null ? null : studentProfileSummaryProvider(userId);
    if (key == 'sale_catalog') return saleCatalogProvider;
    if (key == 'supervisor.photo') return supervisorPhotoUrlProvider;
    if (key == 'supervisor.dashboard') return supervisorDashboardProvider;
    if (key.startsWith('supervisor.offered.')) return offeredSubscriptionTypesProvider(rest('supervisor.offered.'));
    if (key.startsWith('supervisor.monthly.')) {
      final month = DateTime.tryParse(rest('supervisor.monthly.'));
      return month == null ? null : supervisorMonthlySummaryProvider(DateTime(month.year, month.month));
    }
    if (key.startsWith('supervisor.manifest.')) {
      // supervisor.manifest.{day}.{line}.{direction}.{trip or -}
      final parts = rest('supervisor.manifest.').split('.');
      if (parts.length != 4) return null;
      return tripManifestProvider(
          (lineId: parts[1], direction: parts[2], tripId: parts[3] == '-' ? null : parts[3]));
    }
    if (key.startsWith('vote_settings.')) return voteSettingsProvider;
    if (key.startsWith('receipts.')) return subscriptionReceiptsProvider(rest('receipts.'));
    if (key.startsWith('payment_methods.')) return paymentMethodsProvider(rest('payment_methods.'));
    if (key.startsWith('subscription_receipt.v2.')) {
      return subscriptionReceiptDocProvider(rest('subscription_receipt.v2.'));
    }
    return null;
  }

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope> with WidgetsBindingObserver {
  final Map<String, RealtimeChannel> _channels = {};
  final Set<String> _lostTopics = {};
  Timer? _debounce;
  final Set<String> _pendingTables = {};
  final List<SyncEvent> _pendingEvents = [];
  bool _rideVotesRefreshed = false;
  bool _riderCountsRefreshed = false;
  DateTime _lastFullRefresh = DateTime.now();
  Timer? _offlineRetry;
  Timer? _tidy;

  SupabaseClient get _client => SupabaseService.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retune();
      _settlePendingReceipts();
    });
    OfflineCache.refreshed.addListener(_onSavedCopyRefreshed);
    OfflineCache.offlineSince.addListener(_onOfflineChanged);
    // Well after the start: saved reads of days long gone are cleared away.
    _tidy = Timer(const Duration(seconds: 20), () => unawaited(OfflineCache.prune()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OfflineCache.refreshed.removeListener(_onSavedCopyRefreshed);
    OfflineCache.offlineSince.removeListener(_onOfflineChanged);
    _offlineRetry?.cancel();
    _tidy?.cancel();
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
    final userId = ref.read(authStateProvider).user?.id;
    for (final key in OfflineCache.takeRefreshedKeys()) {
      final provider = SyncScope.providerFor(key, userId);
      if (provider != null) {
        ref.invalidate(provider);
      } else if (key.startsWith('ride.')) {
        // The home screen reads its ride votes itself.
        _rideVotesRefreshed = true;
      } else if (key.startsWith('rider_counts.') || key == 'supervisor.line_ids') {
        // So does the supervisor's rider counts screen.
        _riderCountsRefreshed = true;
      } else {
        _pendingTables.addAll(SyncScope.tablesFor(key));
      }
    }
    _debounce = Timer(const Duration(milliseconds: 150), _flush);
  }

  /// While saved data is on screen, try again quietly until the server answers;
  /// the first answer brings everything up to date.
  void _onOfflineChanged() {
    final offline = OfflineCache.offlineSince.value != null;
    if (offline && _offlineRetry == null) {
      _offlineRetry = Timer.periodic(const Duration(seconds: 20), (_) => _refreshEverything());
    } else if (!offline) {
      if (_offlineRetry != null) _settlePendingReceipts();
      _offlineRetry?.cancel();
      _offlineRetry = null;
    }
  }

  /// Receipt images sent earlier whose outcome this phone never learned (see
  /// SubscriptionRepository.reconcilePendingReceipts).
  void _settlePendingReceipts() {
    if (!mounted || ref.read(authStateProvider).role != UserRole.student) return;
    unawaited(ref.read(receiptSubmitterProvider).settlePending());
  }

  /// What the debounce collected: saved copies that turned out stale, and
  /// live events.
  void _flush() {
    if (!mounted) return;
    final tables = Set<String>.from(_pendingTables);
    _pendingTables.clear();
    final events = List<SyncEvent>.from(_pendingEvents);
    _pendingEvents.clear();
    if (_rideVotesRefreshed) {
      _rideVotesRefreshed = false;
      ref.read(rideStatusTickProvider.notifier).state++;
    }
    if (_riderCountsRefreshed) {
      _riderCountsRefreshed = false;
      ref.read(riderCountsTickProvider.notifier).state++;
    }
    final auth = ref.read(authStateProvider);
    // Already in memory: these cost no request.
    if (tables.isNotEmpty) {
      SyncScope.invalidateFor(ref.invalidate, tables, auth.role, auth.user?.id, subscriptionChanged: false);
    }
    unawaited(SyncScope._handle(events,
        invalidate: ref.invalidate, read: ref.read, role: auth.role, userId: auth.user?.id));
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
          _onChange(SyncScope.eventOf(message));
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

  void _onChange(SyncEvent event) {
    // This phone's own change, announced back to it: already on screen.
    if (SyncScope.withoutEchoes([event]).isEmpty) return;
    _pendingEvents.add(event);
    // One refresh for a burst (approving a receipt touches three tables).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _flush);
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
      // 'lines' includes what is on sale: company settings (sale switches,
      // vote times) send no event to students.
      _invalidateFor(const {'subscriptions', 'lines', 'company_invites', 'students', 'notifications'});
      ref.invalidate(voteSettingsProvider);
      _settlePendingReceipts();
      ref.read(rideStatusTickProvider.notifier).state++;
    } else if (role == UserRole.supervisor) {
      // 'companies': the platform's and the company's sale switches send
      // nothing a supervisor's phone would hear while it slept.
      _invalidateFor(const {'supervisor_scan_events', 'notifications', 'supervisors', 'companies'});
    }
    _retune();
  }

  @override
  Widget build(BuildContext context) {
    // The topics depend on who is signed in and on what they are subscribed to.
    ref.listen(authStateProvider.select((s) => s.user?.id), (_, __) {
      _retune();
      _settlePendingReceipts();
    });
    ref.listen(currentSubscriptionProvider.select((s) => s.valueOrNull?.lineId), (_, __) => _retune());
    ref.listen(supervisorDashboardProvider.select((s) => s.valueOrNull?.profile.companyId), (_, __) => _retune());
    return widget.child;
  }
}
