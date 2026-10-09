import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/network/supabase_service.dart';
import '../../core/storage/offline_cache.dart';
import '../../core/storage/prompt_store.dart';
import '../../core/sync/session.dart';
import '../../core/theme/app_icons.dart';
import '../../core/ui/ui.dart';
import '../app_update/app_store.dart';
import '../app_update/app_update_repository.dart';
import '../app_update/app_version.dart';
import '../auth/providers/auth_provider.dart';

/// When the app may ask for a store rating by itself: once per installed
/// version, and only after the student's fifth boarded ride.
abstract final class RatingRules {
  static const ridesNeeded = 5;

  /// Whether [askedVersion] (what the phone remembers) is the installed one.
  /// A build number is not a new version: "1.0.6+35" was asked as "1.0.6".
  static bool askedOn(String? askedVersion, String installed) {
    if (askedVersion == null || askedVersion.isEmpty) return false;
    final asked = AppVersion.tryParse(askedVersion), mine = AppVersion.tryParse(installed);
    return asked != null && mine != null ? asked == mine : askedVersion == installed;
  }

  static bool due({required int boardedRides, required String installed, required String? askedVersion}) =>
      !askedOn(askedVersion, installed) && boardedRides >= ridesNeeded;
}

/// The one request behind the rating prompt.
abstract class BoardedRidesGateway {
  /// `get_my_boarded_rides_count()`: the caller's own successful check-ins.
  Future<Object?> boardedRidesCount();
}

class SupabaseBoardedRidesGateway implements BoardedRidesGateway {
  const SupabaseBoardedRidesGateway();

  @override
  Future<Object?> boardedRidesCount() async =>
      await SupabaseService.client.rpc(SupabaseRpcs.getMyBoardedRidesCount);
}

/// Whether to ask. Anything that goes wrong — no connection, a server without
/// the function, an answer that is not a number — means "do not ask".
class RatingRepository {
  final BoardedRidesGateway _gateway;
  final PromptStore _store;
  final Duration timeout;

  RatingRepository({
    BoardedRidesGateway? gateway,
    PromptStore store = const PromptStore(),
    this.timeout = const Duration(seconds: 8),
  })  : _gateway = gateway ?? const SupabaseBoardedRidesGateway(),
        _store = store;

  Future<int> boardedRides() async {
    try {
      final answer = await _gateway.boardedRidesCount().timeout(timeout);
      return answer is num ? answer.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// The rides are counted only when this version has not been asked yet, and
  /// never without a connection.
  Future<bool> isDue({required String? installed}) async {
    if (installed == null || installed.isEmpty) return false;
    final asked = await _store.ratingAskedVersion(unreadable: installed);
    if (RatingRules.askedOn(asked, installed)) return false;
    if (OfflineCache.offlineSince.value != null) return false;
    return RatingRules.due(boardedRides: await boardedRides(), installed: installed, askedVersion: asked);
  }

  Future<void> markAsked(String installed) => _store.markRatingAsked(installed);
}

final ratingRepoProvider = Provider((ref) => RatingRepository(store: ref.watch(promptStoreProvider)));

/// Whether the signed-in student is due the rating question. Worked out at
/// most once per run of the app (one request, or none once this version has
/// been asked); always false for anyone who is not a student.
final ratingDueProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  final isStudent = ref.watch(authStateProvider.select((s) => s.isStudent));
  final repository = ref.watch(ratingRepoProvider);
  if (userId == null || !isStudent) return false;
  return repository.isDue(installed: await ref.watch(installedVersionProvider.future));
});

/// Where the rating goes and why, a button named for this phone's store, and
/// «ليس الآن». No stars and no question of the app's own: the store asks.
abstract final class RateSheet {
  /// True for «قيّم على …».
  static Future<bool?> show(BuildContext context) => BasakSheet.show<bool>(
        context,
        builder: (context) => const RateSheetBody(),
        primary: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            BasakButton(
              key: const Key('rate-store'),
              label: 'قيّم على ${AppStore.name}',
              icon: LucideIcons.star,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: BasakSpace.s2),
            SheetLink(key: const Key('rate-later'), label: 'ليس الآن', onTap: () => Navigator.of(context).pop(false)),
          ],
        ),
      );
}

class RateSheetBody extends StatelessWidget {
  const RateSheetBody({super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PromptIntro(
            icon: LucideIcons.star,
            title: 'قيّم باصك',
            message: 'تقييمك على ${AppStore.name} يساعد طلاباً آخرين على الوصول إلى باصك، ويساعدنا على تحسينه.',
            semanticLabel: 'تقييم التطبيق',
          ),
          const SizedBox(height: BasakSpace.s6),
        ],
      );
}

/// Hands over to the store. [dialogFirst]: its own review dialog, and its
/// page for the app only where there is no dialog (the sheet's button). The
/// other way round for a tap on the settings row, which must always lead
/// somewhere: the store shows its dialog only so often.
///
/// The page's address is what the update check learned at launch; nothing is
/// asked again.
Future<void> _handOver(BuildContext context, WidgetRef ref, {required bool dialogFirst}) async {
  final url = ref.read(appUpdateProvider).valueOrNull?.storeUrl;
  final store = ref.read(appStoreProvider);
  final handed = dialogFirst
      ? await store.requestReview() || await store.open(url)
      : await store.open(url) || await store.requestReview();
  if (!handed && context.mounted) {
    BasakToast.show(context, 'تعذّر فتح ${AppStore.name}. افتحه وابحث عن «باصك».', kind: BasakToastKind.failure);
  }
}

/// «قيّم التطبيق» under حسابي → التطبيق: always there, asked for by the
/// student, so it goes to the store without a sheet in between.
Future<void> rateFromSettings(BuildContext context, WidgetRef ref) => _handOver(context, ref, dialogFirst: false);

/// Wraps Home. When Home has loaded with an active subscription ([ready]) it
/// works out, once, whether the rating question is due; if so it waits for a
/// calm moment and shows [RateSheet] — only while Home itself is in front
/// (no sheet, no payment, no other tab), the subscription is still active and
/// the phone is online. A moment that is not calm is let go until the next
/// run of the app.
class RatingMoment extends ConsumerStatefulWidget {
  final bool ready;
  final Widget child;

  const RatingMoment({super.key, required this.ready, required this.child});

  /// After Home has settled, and after the notifications offer had its turn.
  static const calm = Duration(seconds: 4);

  @override
  ConsumerState<RatingMoment> createState() => _RatingMomentState();
}

class _RatingMomentState extends ConsumerState<RatingMoment> {
  Timer? _calm;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(RatingMoment old) {
    super.didUpdateWidget(old);
    _start();
  }

  @override
  void dispose() {
    _calm?.cancel();
    super.dispose();
  }

  void _start() {
    if (_started || !widget.ready) return;
    _started = true;
    ref.read(ratingDueProvider.future).then((due) {
      if (mounted && due) _calm = Timer(RatingMoment.calm, _offer);
    }, onError: (_) {});
  }

  Future<void> _offer() async {
    if (!mounted || !widget.ready) return;
    if (OfflineCache.offlineSince.value != null) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    // Home is kept alive behind the other tabs; there it is not in front.
    if (!TickerMode.of(context)) return;
    final installed = ref.read(installedVersionProvider).valueOrNull;
    if (installed == null) return;
    // Asked from here on, whatever the answer: once per version.
    await ref.read(ratingRepoProvider).markAsked(installed);
    if (!mounted) return;
    final wanted = await RateSheet.show(context);
    if (wanted == true && mounted) await _handOver(context, ref, dialogFirst: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
