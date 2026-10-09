import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/media/signed_photo.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../daily_ride/data/daily_ride_repository.dart';
import '../../home/presentation/student_home_screen.dart';
import '../../subscription/presentation/subscription_screen.dart' show subscriptionReceiptsProvider;
import '../../wallet/data/wallet_pass_repository.dart';
import '../../wallet/presentation/add_to_wallet_button.dart';
import '../data/student_qr_repository.dart';
import 'card_details_sheet.dart';
import 'card_facts.dart';

final studentQrRepoProvider = Provider((ref) => StudentQrRepository());

/// The student's card. It reads nothing itself: it is put together from the
/// student's own row and the current subscription, which the home screen and
/// the profile load anyway, and follows them when they change.
final FutureProvider<StudentPassDetails?> studentQrProvider = FutureProvider<StudentPassDetails?>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return null;
  return ref.watch(studentQrRepoProvider).getStudentPassDetails(
        student: () => ref.watch(studentProfileSummaryProvider(userId).future),
        subscription: () => ref.watch(currentSubscriptionProvider.future),
      );
});

/// Reads the card's data from the server again (pull to refresh, "retry").
void refreshStudentPass(WidgetRef ref) {
  final userId = ref.read(sessionUserIdProvider);
  if (userId != null) ref.invalidate(studentProfileSummaryProvider(userId));
  ref.invalidate(currentSubscriptionProvider);
  ref.invalidate(studentQrProvider);
}

/// "بطاقتي": the student's card on an ink ground, written for the person
/// looking at the phone — the supervisor at the bus door. Everything fits one
/// screen, so the phone never has to be touched: the photo, the name, the QR,
/// whether the subscription is valid and until when, the four facts, and
/// today's ride.
class StudentQrScreen extends ConsumerWidget {
  const StudentQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final passAsync = ref.watch(studentQrProvider);

    Future<void> refresh() async {
      refreshStudentPass(ref);
      try {
        await ref.read(studentQrProvider.future);
      } catch (_) {}
    }

    // The ground is ink: the phone's own status icons turn light on it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BasakChrome.onDark(colors.ink),
      child: Material(
        color: colors.ink,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
                child: passAsync.when(
                  // The card stays while what it is made of is read again.
                  skipLoadingOnReload: true,
                  // Only when the card has never been loaded on this phone.
                  loading: () => const SingleChildScrollView(
                    physics: NeverScrollableScrollPhysics(),
                    child: StudentCardSkeleton(),
                  ),
                  error: (error, _) => _CardPage(
                    onRefresh: refresh,
                    builder: (context, height) => _Unavailable(
                      title: 'تعذّر تحميل البطاقة',
                      message: errorMessage(error),
                      onRetry: () => refreshStudentPass(ref),
                    ),
                  ),
                  data: (pass) {
                    if (pass == null || (pass.qrValue ?? '').isEmpty) {
                      return _CardPage(
                        onRefresh: refresh,
                        builder: (context, height) => _Unavailable(
                          title: 'البطاقة غير متاحة حالياً',
                          message: 'تعذّر تجهيز بطاقتك. سجّل دخولك مرة أخرى، أو تواصل مع الدعم.',
                          onRetry: () => refreshStudentPass(ref),
                        ),
                      );
                    }
                    final photo = studentPhoto(pass.profileImagePath);
                    final photoUrl = photo == null ? null : ref.watch(signedPhotoProvider(photo)).valueOrNull;
                    // The receipt's own time is shown only when the subscription
                    // tab has already read the receipts: the card asks for nothing.
                    final id = pass.subscriptionId;
                    final receipts = id != null && ref.exists(subscriptionReceiptsProvider(id))
                        ? ref.watch(subscriptionReceiptsProvider(id)).valueOrNull
                        : null;
                    return _CardPage(
                      onRefresh: refresh,
                      // Short of this the page scrolls instead of squeezing the QR.
                      minHeight: _CardFace.tightest,
                      builder: (context, height) => ListenableBuilder(
                        // Today's ride follows the vote the moment Home reads or saves it.
                        listenable: KnownRides.changes,
                        builder: (context, _) => _CardFace(
                          pass: pass,
                          height: height,
                          photo: photoUrl == null ? null : avatarImage(photoUrl),
                          ride: TodayRide.known(),
                          receiptSentAt: receipts == null || receipts.isEmpty ? null : receipts.first.createdAt,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page under the title: as tall as the screen, so nothing scrolls, yet
/// it can be pulled to read the card again. Below [minHeight] (a short phone
/// with large text) it scrolls rather than shrink what must stay readable.
class _CardPage extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final double minHeight;
  final Widget Function(BuildContext context, double height) builder;

  const _CardPage({required this.onRefresh, required this.builder, this.minHeight = 0});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grow = _textGrowth(context);
    return LayoutBuilder(builder: (context, box) {
      final height = math.max(box.maxHeight, minHeight + grow);
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: colors.teal,
        backgroundColor: colors.surface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.gutter),
              child: builder(context, height - grow),
            ),
          ),
        ),
      );
    });
  }

  /// How much taller the card's lines of text are at the phone's text size.
  static double _textGrowth(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(100) / 100 - 1).clamp(0.0, .3) * _CardFace.textHeight;
}

/// The page's title, and beside it what the student should know about the
/// card: it needs no connection.
class _Title extends StatelessWidget {
  final bool compact;
  final bool worksOffline;

  const _Title({this.compact = false, this.worksOffline = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Row(
      children: [
        Semantics(
          header: true,
          child: Text('بطاقتي', maxLines: 1, style: (compact ? text.title : text.display).copyWith(color: colors.onInk)),
        ),
        const SizedBox(width: BasakSpace.s12),
        // At the far end; on a narrow phone with large text it shrinks to fit.
        Expanded(
          child: !worksOffline
              ? const SizedBox.shrink()
              : Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.shieldCheck, size: 15, color: colors.sky),
                        const SizedBox(width: BasakSpace.s6),
                        Text('تعمل بدون إنترنت',
                            style: text.label.copyWith(color: colors.sky, fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// No card to show: why, and one way out.
class _Unavailable extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _Unavailable({required this.title, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: BasakSpace.s12),
          const _Title(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.only(bottom: BasakSpace.s40),
                child: EmptyState(
                  onInk: true,
                  icon: LucideIcons.qrCode,
                  title: title,
                  message: message,
                  actionLabel: 'إعادة المحاولة',
                  actionIcon: LucideIcons.refreshCw,
                  onAction: onRetry,
                ),
              ),
            ),
          ),
        ],
      );
}

/// The card and the buttons under it. Its spacing opens up with the room the
/// phone gives ([height]); what is left over goes to the QR, which is the only
/// part that flexes, so nothing here can overflow and the code is the last
/// thing to shrink.
class _CardFace extends StatelessWidget {
  final StudentPassDetails pass;

  /// The room for the whole page, at text scale 1.
  final double height;
  final ImageProvider? photo;
  final TodayRide? ride;

  /// When the receipt under review was sent, if this phone already knows.
  final String? receiptSentAt;

  const _CardFace({required this.pass, required this.height, this.photo, this.ride, this.receiptSentAt});

  /// The page as the board draws it (844 high: 700 between the status bar and
  /// the tab bar), and with every gap at its tightest and the QR still 184.
  static const roomy = 700.0;
  static const tight = 592.0;

  /// Under this the page scrolls: tight, with the QR down to about 120.
  static const tightest = 530.0;

  /// The height of the card's lines of text, which grows with the text size.
  static const textHeight = 250.0;

  /// The code is drawn this large when there is room, never larger.
  static const qrLargest = 208.0;

  static double _lerp(double from, double to, double t) => from + (to - from) * t;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final standing = CardStanding.of(pass);
    // 0: a 360 × 640 phone. 1: the board.
    final room = ((height - tight) / (roomy - tight)).clamp(0.0, 1.0);
    final compact = room < .5;
    final gap = _lerp(BasakSpace.s8, BasakSpace.s14, room);
    final pad = _lerp(BasakSpace.s12, BasakSpace.card, room);
    final name = (pass.fullName ?? '').trim().isEmpty ? 'الطالب' : pass.fullName!.trim();
    final school = [pass.college, pass.university].map((s) => (s ?? '').trim()).where((s) => s.isNotEmpty).join(' · ');
    final until = CardDates.parse(pass.endDate);
    final beside = switch (standing) {
      CardStanding.active => until == null ? null : 'حتى ${CardDates.full(until)}',
      CardStanding.expired => until == null ? null : 'انتهى ${CardDates.full(until)}',
      _ => 'غير مفعّل بعد',
    };
    String fact(String? value) => (value ?? '').trim().isEmpty ? '—' : value!.trim();
    // A Wallet card is offered for a subscription that is valid today.
    final wallet = standing.isActive &&
        AddToWalletButton.canOffer(pass, WalletPassRepository.platformFor(defaultTargetPlatform));

    Widget inset(Widget child) =>
        Padding(padding: EdgeInsetsDirectional.symmetric(horizontal: pad), child: child);

    final strip = _strip(standing, compact);

    final card = Semantics(
      container: true,
      label: 'بطاقة الطالب',
      child: Container(
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsetsDirectional.symmetric(vertical: pad),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BasakRadius.all(BasakRadius.sheet)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            inset(Padding(
              padding: EdgeInsetsDirectional.only(start: BasakSpace.s4, top: compact ? 0 : BasakSpace.s4),
              child: Row(
                children: [
                  PhotoRing(image: photo, name: name, size: _lerp(48, 60, room), ring: standing.ring(colors)),
                  const SizedBox(width: BasakSpace.s14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headline),
                        if (school.isNotEmpty)
                          Text(school,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
            SizedBox(height: gap),
            // The one flexible part: it takes what the rest leaves.
            Flexible(child: _Qr(value: pass.qrValue!, frame: compact ? BasakSpace.s6 : BasakSpace.s10)),
            SizedBox(height: gap),
            // One line whatever the text size: it shrinks before it would wrap or cut.
            inset(FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusChip(standing.status, label: standing.chipLabel),
                  if (beside != null) ...[
                    const SizedBox(width: BasakSpace.s10),
                    Text(beside, maxLines: 1, style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400)),
                  ],
                ],
              ),
            )),
            // The tear is 20 high around its line: it brings its own air.
            SizedBox(height: math.max(0, gap - 10)),
            TicketTear(color: colors.track, ground: colors.ink),
            SizedBox(height: math.max(0, gap - 10)),
            inset(FactGrid(dense: compact, facts: [
              ('الخط', fact(pass.lineName)),
              ('محطة الصعود', fact(pass.stationName)),
              ('الفترة', fact(pass.periodName)),
              ('الشركة', fact(pass.companyName)),
            ])),
            if (strip != null) ...[
              SizedBox(height: gap),
              inset(strip),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _lerp(BasakSpace.s4, BasakSpace.s12, room)),
        _Title(compact: compact, worksOffline: true),
        SizedBox(height: gap),
        // The card hugs its content at the top; what the QR does not use
        // stays between the card and the buttons.
        Expanded(child: Align(alignment: AlignmentDirectional.topCenter, child: card)),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(
              flex: 4,
              child: InkOutlineButton(
                key: const Key('card-details-open'),
                label: 'كل التفاصيل',
                icon: LucideIcons.idCard,
                onPressed: () => CardDetailsSheet.show(context, pass: pass, photo: photo, ride: ride),
              ),
            ),
            if (wallet) ...[
              const SizedBox(width: BasakSpace.s10),
              // Apple's and Google's own buttons, as each asks them to be drawn.
              Expanded(
                flex: 5,
                child: SizedBox(height: BasakSpace.tapTarget, child: AddToWalletButton(pass: pass)),
              ),
            ],
          ],
        ),
        SizedBox(height: _lerp(BasakSpace.s8, BasakSpace.s14, room)),
      ],
    );
  }

  /// The strip under the facts. Valid: today's ride, once this phone knows it.
  /// Otherwise the receipt, which is what the subscription is waiting for.
  Widget? _strip(CardStanding standing, bool dense) {
    final today = ride;
    return switch (standing) {
      CardStanding.active => today == null
          ? null
          : InfoStrip(
              key: const Key('card-ride'),
              dense: dense,
              label: today.title,
              value: today.summary(pass),
              icon: today.isRiding ? LucideIcons.check : null,
            ),
      CardStanding.pendingReview => InfoStrip(
          key: const Key('card-receipt'),
          dense: dense,
          tone: BasakTone.warning,
          label: 'الإيصال',
          value: receiptSentAt == null ? 'استلمنا إيصالك' : CardDates.sent(receiptSentAt!),
          icon: LucideIcons.clock3,
        ),
      CardStanding.pendingPayment => InfoStrip(
          key: const Key('card-receipt'), dense: dense, tone: BasakTone.info, label: 'الإيصال', value: 'لم يُرسل بعد'),
      CardStanding.rejected => InfoStrip(
          key: const Key('card-receipt'), dense: dense, tone: BasakTone.danger, label: 'الإيصال', value: 'مرفوض'),
      CardStanding.upcoming || CardStanding.expired || CardStanding.none => null,
    };
  }
}

/// The code in its hairline frame, as large as it is given room for.
class _Qr extends StatelessWidget {
  final String value;
  final double frame;

  const _Qr({required this.value, required this.frame});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(builder: (context, box) {
      // The frame and its hairline are part of what must fit.
      final room = math.min(box.maxHeight, box.maxWidth) - 2 * (frame + 1);
      final side = math.max(0.0, math.min(room, _CardFace.qrLargest));
      return Center(
        heightFactor: 1,
        child: Semantics(
          image: true,
          label: 'رمز QR للطالب',
          child: Container(
            padding: EdgeInsetsDirectional.all(frame),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BasakRadius.all(BasakRadius.card),
              border: Border.all(color: colors.hairline),
            ),
            child: QrImageView(
              key: const Key('student-qr'),
              data: value,
              version: QrVersions.auto,
              size: side,
              padding: EdgeInsets.zero,
              backgroundColor: colors.surface,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: colors.qrInk),
              dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: colors.qrInk),
            ),
          ),
        ),
      );
    });
  }
}
