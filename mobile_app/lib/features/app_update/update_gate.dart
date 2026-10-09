import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/offline_cache.dart';
import '../../core/storage/prompt_store.dart';
import '../../core/theme/app_icons.dart';
import '../../core/ui/ui.dart';
import '../auth/presentation/force_password_change_screen.dart' show mustChangePasswordProvider;
import '../auth/providers/auth_provider.dart';
import '../onboarding/onboarding_controller.dart';
import '../student/qr/presentation/student_qr_screen.dart';
import 'app_store.dart';
import 'app_update_repository.dart';
import 'app_version.dart';

/// Stands between the app and everything under it, signed in or not.
///
/// * A version the server no longer allows: [UpdateRequiredScreen] instead of
///   [child].
/// * A newer version in the store: [UpdateAvailableSheet] over the signed-in
///   home, once per store version.
/// * Anything else — no answer, no connection — [child], untouched.
class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  /// After the splash has left and the home screen has settled.
  static const calm = Duration(milliseconds: 2500);

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  Timer? _offer;
  bool _offered = false;

  @override
  void dispose() {
    _offer?.cancel();
    super.dispose();
  }

  void _plan(AppUpdate update) {
    if (_offered || _offer != null) return;
    _offer = Timer(UpdateGate.calm, () => _show(update));
  }

  void _unplan() {
    _offer?.cancel();
    _offer = null;
  }

  Future<void> _show(AppUpdate update) async {
    _offer = null;
    if (!mounted || _offered) return;
    // Only over the home screen itself: never over a sheet, a payment, the
    // onboarding or the forced password change, and never without a connection.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (OfflineCache.offlineSince.value != null) return;
    if (ref.read(onboardingProvider) != true) return;
    final auth = ref.read(authStateProvider);
    if (auth.isStudent && ref.read(mustChangePasswordProvider).valueOrNull == true) return;
    _offered = true;
    final store = ref.read(promptStoreProvider);
    final latest = update.latestVersion;
    if (await store.updateOfferedVersion(unreadable: latest) == latest) return;
    await store.markUpdateOffered(latest);
    if (!mounted) return;
    final wanted = await UpdateAvailableSheet.show(context, update);
    if (wanted == true && mounted) await openStoreForUpdate(context, ref, update);
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider).valueOrNull;
    final auth = ref.watch(authStateProvider);
    ref.listen(appUpdateProvider, (previous, next) {
      if (next.valueOrNull?.isRequired != true || previous?.valueOrNull?.isRequired == true) return;
      // Whatever was opened while the answer was on its way makes way.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    });

    if (update != null && update.isRequired) {
      _unplan();
      return UpdateRequiredScreen(update: update, hasCard: auth.isAuthenticated && auth.isStudent);
    }
    if (update != null && update.isOptional && auth.isAuthenticated && (auth.isStudent || auth.isSupervisor)) {
      _plan(update);
    } else {
      _unplan();
    }
    return widget.child;
  }
}

/// «تحديث الآن» and «تحديث من …»: the store's page for the app.
Future<void> openStoreForUpdate(BuildContext context, WidgetRef ref, AppUpdate update) async {
  final opened = await ref.read(appStoreProvider).open(update.storeUrl);
  if (!opened && context.mounted) {
    BasakToast.show(context, 'تعذّر فتح ${AppStore.name}. افتحه وابحث عن «باصك».', kind: BasakToastKind.failure);
  }
}

/// A newer version is in the store: which one, what it brings (up to three
/// lines; none when the dashboard wrote none) and the two answers.
abstract final class UpdateAvailableSheet {
  /// True for «تحديث الآن».
  static Future<bool?> show(BuildContext context, AppUpdate update) => BasakSheet.show<bool>(
        context,
        builder: (context) => UpdateAvailableBody(update: update),
        primary: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            BasakButton(
              key: const Key('update-now'),
              label: 'تحديث الآن',
              icon: LucideIcons.download,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: BasakSpace.s2),
            SheetLink(key: const Key('update-later'), label: 'لاحقاً', onTap: () => Navigator.of(context).pop(false)),
          ],
        ),
      );
}

class UpdateAvailableBody extends StatelessWidget {
  final AppUpdate update;

  const UpdateAvailableBody({super.key, required this.update});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PromptIntro(
            icon: LucideIcons.download,
            title: 'تحديث جديد متاح',
            fact: update.latestVersion,
            semanticLabel: 'تحديث متاح',
          ),
          if (update.whatsNew.isNotEmpty) ...[
            const SizedBox(height: BasakSpace.s20),
            CheckLines(lines: update.whatsNew),
          ],
          const SizedBox(height: BasakSpace.s6),
        ],
      );
}

/// This version is no longer allowed in. The store is the one way on; a
/// student's card stays one tap away, because it works without the rest of
/// the app and nobody may be stranded at the bus door by an update.
class UpdateRequiredScreen extends ConsumerWidget {
  final AppUpdate update;

  /// A student is signed in on this phone: «عرض بطاقتي» is offered.
  final bool hasCard;

  const UpdateRequiredScreen({super.key, required this.update, required this.hasCard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.colors.ground,
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: BasakSpace.s20),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.gutter),
          child: BlockingNotice(
            icon: LucideIcons.download,
            title: 'حدّث التطبيق للمتابعة',
            message: 'هذا الإصدار لم يعد مدعوماً. التحديث يأخذ دقيقة، ولا يغيّر حسابك أو اشتراكك.',
            facts: [
              (label: 'إصدارك', value: update.installed),
              (label: 'المطلوب', value: update.minVersion),
            ],
            actions: [
              BasakButton(
                key: const Key('update-required-store'),
                label: 'تحديث من ${AppStore.name}',
                icon: LucideIcons.download,
                onPressed: () => openStoreForUpdate(context, ref, update),
              ),
              if (hasCard)
                SheetLink(
                  key: const Key('update-required-card'),
                  label: 'عرض بطاقتي',
                  accent: true,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const UpdateCardScreen())),
                ),
            ],
            footnote: hasCard ? 'بطاقتك تعمل عند الصعود حتى قبل التحديث.' : null,
          ),
        ),
      ),
    );
  }
}

/// The student's card by itself, from what this phone has saved: no tabs, no
/// home screen behind it. Back returns to the update screen.
class UpdateCardScreen extends StatelessWidget {
  const UpdateCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Ink behind the card: the phone's own status icons turn light over it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BasakChrome.onDark(),
      child: Material(
        color: context.colors.ink,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.gutter, BasakSpace.s8, BasakSpace.gutter, 0),
                child: BasakBackHeader(key: const Key('update-card-back'), onBack: () => Navigator.of(context).pop()),
              ),
              // The card's own page keeps its place under the back button.
              Expanded(
                child: MediaQuery.removePadding(context: context, removeTop: true, child: const StudentQrScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
