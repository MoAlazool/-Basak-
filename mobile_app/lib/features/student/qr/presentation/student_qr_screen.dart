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
/// today's ride. The rest of what the card knows is on its back: a tap turns
/// it over.
class StudentQrScreen extends ConsumerWidget {
  const StudentQrScreen({super.key, this.visible = true});

  /// Whether this tab is the one on show. A card left on its back is turned
  /// to its face when the student goes elsewhere, so it always opens on the
  /// code at the bus door.
  final bool visible;

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
          maxScaleFactor: basakMaxTextScale,
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
                          visible: visible,
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
///
/// The card has two sides. Its face is who the student is and the code; its
/// back is everything else it knows. A tap on the card, or the button under
/// it, turns it over.
class _CardFace extends StatefulWidget {
  final StudentPassDetails pass;

  /// The room for the whole page, at text scale 1.
  final double height;
  final ImageProvider? photo;
  final TodayRide? ride;

  /// When the receipt under review was sent, if this phone already knows.
  final String? receiptSentAt;

  /// The card's tab is the one on show.
  final bool visible;

  const _CardFace({
    required this.pass,
    required this.height,
    this.photo,
    this.ride,
    this.receiptSentAt,
    this.visible = true,
  });

  /// The page as the board draws it (844 high: 700 between the status bar and
  /// the tab bar), and with every gap at its tightest and the QR still 184.
  static const roomy = 700.0;
  static const tight = 592.0;

  /// Under this the page scrolls: tight, with the QR down to about 120. (The
  /// four facts moved to the back of the card, so the face needs less.)
  static const tightest = 470.0;

  /// The height of the card's lines of text, which grows with the text size.
  static const textHeight = 200.0;

  /// The code is drawn this large when there is room, never larger: it is the
  /// card that grows with the phone, not the code.
  static const qrLargest = 232.0;

  /// The card is never taller than this many times its width: a pass, like
  /// the ones in the phone's wallet, not a column.
  static const tallest = 1.65;

  @override
  State<_CardFace> createState() => _CardFaceState();
}

class _CardFaceState extends State<_CardFace> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 0: the face. 1: the back.
  /// Kept at its own pace under "reduce motion": the turn becomes a short
  /// fade there (see [_flip]) and that fade should still be seen.
  late final AnimationController _turn = AnimationController(
      vsync: this, duration: BasakMotion.flip, animationBehavior: AnimationBehavior.preserve);
  bool _back = false;

  StudentPassDetails get pass => widget.pass;

  static double _lerp(double from, double to, double t) => from + (to - from) * t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(_CardFace old) {
    super.didUpdateWidget(old);
    // Being rebuilt already: no rebuild of its own to ask for.
    if (old.visible && !widget.visible) _showFace(rebuild: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The phone was put away with the back showing: next time, the code.
    if (state == AppLifecycleState.paused) _showFace();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turn.dispose();
    super.dispose();
  }

  /// Back on the code at once, with nothing to watch.
  void _showFace({bool rebuild = true}) {
    if (!_back && _turn.value == 0) return;
    _turn.value = 0;
    _back = false;
    if (rebuild && mounted) setState(() {});
  }

  void _flip() {
    HapticFeedback.lightImpact();
    setState(() => _back = !_back);
    // Less motion: the two sides fade into each other instead of turning.
    final reduced = MediaQuery.disableAnimationsOf(context);
    _turn.animateTo(
      _back ? 1 : 0,
      duration: reduced ? BasakMotion.fade : BasakMotion.flip,
      curve: reduced ? BasakMotion.fadeCurve : BasakMotion.flipCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final standing = CardStanding.of(pass);
    // 0: a 360 × 640 phone. 1: the board.
    final room = ((widget.height - _CardFace.tight) / (_CardFace.roomy - _CardFace.tight)).clamp(0.0, 1.0);
    final compact = room < .5;
    final gap = _lerp(BasakSpace.s8, BasakSpace.s14, room);
    final pad = _lerp(BasakSpace.s12, BasakSpace.card, room);
    // A Wallet card is offered for a subscription that is valid today.
    final wallet = standing.isActive &&
        AddToWalletButton.canOffer(pass, WalletPassRepository.platformFor(defaultTargetPlatform));

    final card = AnimatedBuilder(
      animation: _turn,
      builder: (context, _) => CardFlip(
        turn: _turn.value,
        fade: MediaQuery.disableAnimationsOf(context),
        shadow: colors.scanBase,
        onTap: _flip,
        front: _front(context, standing, room: room, compact: compact, gap: gap, pad: pad),
        // Built once the card starts to turn: the face alone costs nothing of it.
        back: _turn.value > 0 ? _backSide(context, standing, gap: gap, pad: pad) : const SizedBox.shrink(),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _lerp(BasakSpace.s4, BasakSpace.s12, room)),
        _Title(compact: compact, worksOffline: true),
        SizedBox(height: gap),
        // The card takes the page down to the buttons over the tab bar, up to
        // a pass's proportions; on a very tall phone what is left stays above it.
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: AlignmentDirectional.bottomCenter,
              child: SizedBox(
                height: math.min(box.maxHeight, box.maxWidth * _CardFace.tallest),
                child: card,
              ),
            ),
          ),
        ),
        SizedBox(height: gap),
        // Two buttons of one height and one width: the card's other side, and
        // the phone's wallet.
        Row(
          children: [
            Expanded(
              child: InkOutlineButton(
                key: const Key('card-flip'),
                // Short, so both fit beside the wallet on a narrow phone at the largest text.
                label: _back ? 'الرمز' : 'التفاصيل',
                semanticLabel: _back ? 'اقلب البطاقة لعرض رمز QR' : 'اقلب البطاقة لعرض التفاصيل',
                icon: _back ? LucideIcons.qrCode : LucideIcons.rotate3d,
                onPressed: _flip,
              ),
            ),
            if (wallet) ...[
              const SizedBox(width: BasakSpace.s10),
              Expanded(child: AddToWalletButton(pass: pass)),
            ],
          ],
        ),
        SizedBox(height: _lerp(BasakSpace.s8, BasakSpace.s14, room)),
      ],
    );
  }

  BoxDecoration _paper(BasakColors colors) =>
      BoxDecoration(color: colors.surface, borderRadius: BasakRadius.all(BasakRadius.sheet));

  /// What a tap on this side does, said quietly at its foot.
  Widget _hint(BuildContext context, String words) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.rotate3d, size: 14, color: colors.ink3),
            const SizedBox(width: BasakSpace.s6),
            Text(words, maxLines: 1, style: context.text.caption.copyWith(color: colors.ink3)),
          ],
        ),
      ),
    );
  }

  /// The face: who the student is, the code, and whether they may board.
  Widget _front(BuildContext context, CardStanding standing,
      {required double room, required bool compact, required double gap, required double pad}) {
    final colors = context.colors;
    final text = context.text;
    final name = (pass.fullName ?? '').trim().isEmpty ? 'الطالب' : pass.fullName!.trim();
    final until = CardDates.parse(pass.endDate);
    final beside = switch (standing) {
      CardStanding.active => until == null ? null : 'حتى ${CardDates.full(until)}',
      CardStanding.expired => until == null ? null : 'انتهى ${CardDates.full(until)}',
      _ => 'غير مفعّل بعد',
    };
    final strip = _strip(standing, compact);

    Widget inset(Widget child) =>
        Padding(padding: EdgeInsetsDirectional.symmetric(horizontal: pad), child: child);

    return Semantics(
      container: true,
      label: 'بطاقة الطالب',
      child: Container(
        key: const Key('card-front'),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsetsDirectional.only(top: pad, bottom: math.max(BasakSpace.s8, pad - BasakSpace.s6)),
        decoration: _paper(colors),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            inset(Padding(
              padding: EdgeInsetsDirectional.only(start: BasakSpace.s4, top: compact ? 0 : BasakSpace.s4),
              child: Row(
                children: [
                  PhotoRing(image: widget.photo, name: name, size: _lerp(48, 60, room), ring: standing.ring(colors)),
                  const SizedBox(width: BasakSpace.s14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headline),
                        // The college, then the university: never run together.
                        SchoolLine(college: pass.college, university: pass.university),
                      ],
                    ),
                  ),
                ],
              ),
            )),
            SizedBox(height: gap),
            // The one flexible part: it takes what the rest leaves.
            // The one flexible part: the code at its own size, in the middle of
            // what the rest leaves.
            Expanded(child: Center(child: _Qr(value: pass.qrValue!, frame: compact ? BasakSpace.s6 : BasakSpace.s10))),
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
            if (strip != null) ...[
              inset(strip),
              SizedBox(height: compact ? BasakSpace.s6 : BasakSpace.s10),
            ],
            inset(_hint(context, 'اضغط البطاقة لعرض التفاصيل')),
          ],
        ),
      ),
    );
  }

  /// Unicode's left-to-right isolate and its end: for a run that must keep
  /// its order inside an Arabic line.
  static final _ltr = String.fromCharCode(0x2066);
  static final _end = String.fromCharCode(0x2069);

  static String _or(String? value) => (value ?? '').trim().isEmpty ? '—' : value!.trim();

  /// The back: the subscription, the student, and today's ride, in the
  /// card's own two columns. As large as the face; on a short phone with
  /// large text its middle scrolls.
  Widget _backSide(BuildContext context, CardStanding standing, {required double gap, required double pad}) {
    final colors = context.colors;
    final text = context.text;
    final year = pass.academicYear;
    // The years read left to right inside the Arabic line.
    final period = [
      if ((pass.periodName ?? '').isNotEmpty) pass.periodName!,
      if (year != null) '$_ltr$year / ${year + 1}$_end',
    ].join(' · ');
    final phone = (pass.phone ?? '').trim();
    final today = widget.ride;

    Widget group(String title, List<(String, String)> facts, {Map<String, Widget> marks = const {}}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: text.label.copyWith(color: colors.teal))),
            const SizedBox(height: BasakSpace.s6),
            FactGrid(facts: facts, marks: marks),
          ],
        );

    final groups = [
      if (standing != CardStanding.none)
        group('الاشتراك', [
          ('الخط', _or(pass.lineName)),
          ('محطة الصعود', _or(pass.stationName)),
          ('الشركة', _or(pass.companyName)),
          ('الفترة', _or(period)),
          ('الصلاحية', _or(CardDates.range(pass.startDate, pass.endDate))),
        ], marks: {
          // The company's mark beside its name, once it has one.
          if (pass.companyBrand.hasMark && (pass.companyName ?? '').trim().isNotEmpty)
            'الشركة': ExcludeSemantics(
              child: CompanyLogo(
                key: const Key('card-company-logo'),
                name: pass.companyName!.trim(),
                brand: pass.companyBrand,
                size: 24,
              ),
            ),
        }),
      group('بيانات الطالب', [
        ('الجامعة', _or(pass.university)),
        ('الكلية', _or(pass.college)),
        if (phone.isNotEmpty) ('الهاتف', '$_ltr${cardPhone(phone)}$_end'),
      ]),
      if (standing.isActive && today != null && today.isRiding)
        group(today.title, [
          ('الذهاب', _or(today.going)),
          ('العودة', _or(today.returning(pass))),
        ]),
    ];

    return Semantics(
      container: true,
      label: 'تفاصيل البطاقة',
      child: Container(
        key: const Key('card-back'),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsetsDirectional.only(top: pad, bottom: math.max(BasakSpace.s8, pad - BasakSpace.s6)),
        decoration: _paper(colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: pad),
              child: LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child:
                            Text('تفاصيل البطاقة', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headline),
                      ),
                    ),
                    const SizedBox(width: BasakSpace.s10),
                    // A long status at the largest text shrinks; it is never cut.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * .6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: StatusChip(standing.status, label: standing.chipLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: math.max(0, gap - 10)),
            TicketTear(color: colors.track, ground: colors.ink),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(pad, math.max(0, gap - 10), pad, BasakSpace.s8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < groups.length; i++) ...[
                      if (i > 0) ...[
                        SizedBox(height: gap),
                        Divider(height: 1, thickness: 1, color: colors.hairline),
                        SizedBox(height: gap),
                      ],
                      groups[i],
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: pad),
              child: _hint(context, 'اضغط البطاقة للعودة إلى الرمز'),
            ),
          ],
        ),
      ),
    );
  }

  /// The strip under the tear. Valid: today's ride, once this phone knows it.
  /// Otherwise the receipt, which is what the subscription is waiting for.
  Widget? _strip(CardStanding standing, bool dense) {
    final today = widget.ride;
    final receiptSentAt = widget.receiptSentAt;
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
          value: receiptSentAt == null ? 'استلمنا إيصالك' : CardDates.sent(receiptSentAt),
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
