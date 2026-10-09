import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/signed_photo.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/storage/offline_cache.dart';
import '../../../../core/sync/session.dart';
import '../../../../core/sync/sync_hub.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../../core/widgets/connection_strip_host.dart';
import '../../../../core/widgets/greeting_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../notifications/data/notification_feed.dart';
import '../../daily_ride/data/daily_ride_repository.dart';
import '../../daily_ride/data/vote_reminders.dart';
import '../../daily_ride/models/vote_settings.dart';
import '../../invites/invites.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/models/subscription_model.dart';
import '../../subscription/presentation/purchase_flow.dart' show formatMoney;
import 'notifications_screen.dart';
import 'ride_card.dart';
import 'ride_sheet.dart';
import 'supervisor_contact_sheet.dart';

final subscriptionRepoProvider = Provider((ref) => SubscriptionRepository());
final dailyRideRepoProvider = Provider((ref) => DailyRideRepository());

/// The subscription shown on the home screen: from the saved copy at once,
/// then from the server; refreshed by live events and on app resume.
class CurrentSubscriptionNotifier extends SnapshotNotifier<SubscriptionModel?> {
  @override
  String get snapshotName => 'current_subscription';
  @override
  SubscriptionModel? get signedOut => null;
  @override
  Future<Object?> fetchJson() => ref.read(subscriptionRepoProvider).getCurrentSubscriptionJson();
  @override
  SubscriptionModel? parse(Object? json) =>
      json == null ? null : SubscriptionModel.fromJson(Map<String, dynamic>.from(json as Map));
}

final currentSubscriptionProvider =
    AsyncNotifierProvider<CurrentSubscriptionNotifier, SubscriptionModel?>(CurrentSubscriptionNotifier.new);

/// When the student's company runs the ride vote and how often it reminds
/// (the platform's settings until a subscription is known). Set in the
/// dashboard; re-read on app resume.
final voteSettingsProvider = FutureProvider<VoteSettings>((ref) {
  ref.watch(sessionUserIdProvider);
  // The settings are the subscription's company's. They are read once, when
  // the subscription is known (it comes from its saved copy at once), instead
  // of the platform's first and the company's a moment later.
  final subscription = ref.watch(currentSubscriptionProvider
      .select((s) => (known: s.hasValue || s.hasError, companyId: s.valueOrNull?.companyId)));
  if (!subscription.known) return Completer<VoteSettings>().future;
  return ref.watch(dailyRideRepoProvider).getVoteSettings(subscription.companyId);
});

/// Home: who the student is, where their subscription stands, tomorrow's ride
/// and the bus supervisor. Nothing else: dates and money are on the
/// subscription tab, the QR is on the card tab.
class StudentHomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onNavigateToSubscription;
  final VoidCallback onNavigateToQr;

  const StudentHomeScreen({
    super.key,
    required this.onNavigateToSubscription,
    required this.onNavigateToQr,
  });

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  bool _isRidingToday = false;
  bool _isReturningToday = true;
  bool _isSavingRide = false;
  String? _selectedDepartureTime;
  String? _selectedReturnTime;

  /// Departure time of the confirmed ride (null when not riding). Unlike
  /// [_selectedDepartureTime] it only changes when a confirmation is saved.
  String? _confirmedDepartureTime;
  DateTime? _loadedRideDate;
  Timer? _votingWindowTimer;
  Timer? _settingsWait;
  Map<DateTime, bool> _weeklyRideStatuses = const {};

  @override
  void initState() {
    super.initState();
    // The ride day depends on the vote settings: when they are already known
    // the votes are read now, otherwise once, as soon as they arrive (see
    // build), instead of once with the default settings and again after.
    if (ref.read(voteSettingsProvider).hasValue) {
      _loadTodayRideStatus();
    } else {
      _settingsWait = Timer(const Duration(seconds: 4), () {
        if (mounted && _loadedRideDate == null) _loadTodayRideStatus();
      });
    }
    _votingWindowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final targetDate = _vote.rideDateFor(DateTime.now());
      final loadedDate = _loadedRideDate;
      if (loadedDate == null ||
          loadedDate.year != targetDate.year ||
          loadedDate.month != targetDate.month ||
          loadedDate.day != targetDate.day) {
        _loadTodayRideStatus();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _votingWindowTimer?.cancel();
    _settingsWait?.cancel();
    super.dispose();
  }

  /// The vote settings in force (the original 4 PM → 6 AM until loaded).
  VoteSettings get _vote =>
      ref.read(voteSettingsProvider).valueOrNull ?? VoteSettings.fallback;

  Future<void> _loadTodayRideStatus() async {
    try {
      final rideDate = _vote.rideDateFor(DateTime.now());
      final saturdayOffset = (rideDate.weekday + 1) % 7;
      final saturday = DateTime(rideDate.year, rideDate.month, rideDate.day)
          .subtract(Duration(days: saturdayOffset));
      final repository = ref.read(dailyRideRepoProvider);
      // One read for the week shown here, the ride day's own choices and
      // the days the reminders look at (the ride day and the six after it).
      final rides = await repository.getRides(
          saturday, DateTime(rideDate.year, rideDate.month, rideDate.day + 6));
      final statuses = rides.statuses;
      final details = rides.detailsFor(rideDate);
      if (mounted) {
        setState(() {
          _loadedRideDate = rideDate;
          _isRidingToday = details.isRiding;
          _isReturningToday = details.isReturning;
          _selectedDepartureTime = details.departureTime;
          _selectedReturnTime = details.returnTime;
          _confirmedDepartureTime = details.isRiding ? details.departureTime : null;
          _weeklyRideStatuses = statuses;
        });
      }
    } catch (_) {
      // The dashboard stays usable when the ride-status service is offline.
    }
    await _planReminders();
  }

  /// Reminders for the coming ride days not voted for yet (see VoteReminders).
  /// [justVoted] counts as voted even if the server copy is not re-read yet.
  Future<void> _planReminders({DateTime? justVoted}) async {
    if (!mounted) return;
    final settings = ref.read(voteSettingsProvider).valueOrNull;
    final subscription = ref.read(currentSubscriptionProvider);
    if (settings == null || !subscription.hasValue) return; // not known yet
    final sub = subscription.value;
    // No reminders without a running subscription, or when the company
    // switched them off. (Whether they are shown is the phone's own
    // notification permission; students have no switch for them in the app.)
    if (sub == null || !sub.isActive || settings.reminderMinutes <= 0) {
      await VoteReminders.cancelAll();
      return;
    }
    try {
      final first = settings.rideDateFor(DateTime.now());
      final loaded = _loadedRideDate;
      // The votes just read for the home screen cover these days already.
      final voted = loaded != null && DateUtils.isSameDay(loaded, first)
          ? _weeklyRideStatuses
          : (await ref.read(dailyRideRepoProvider)
                  .getRides(first, DateTime(first.year, first.month, first.day + 6)))
              .statuses;
      await VoteReminders.plan(
        settings: settings,
        validFrom: DateTime.tryParse(sub.startDate ?? ''),
        validUntil: DateTime.tryParse(sub.endDate ?? ''),
        votedDays: {...voted.keys, if (justVoted != null) justVoted},
      );
    } catch (_) {
      // Offline with nothing saved: the previous plan stays.
    }
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(currentSubscriptionProvider);
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      ref.invalidate(studentProfileSummaryProvider(user.id));
    }
    await _loadTodayRideStatus();
    try {
      await ref.read(currentSubscriptionProvider.future);
    } catch (_) {}
  }

  /// "نعم، سأركب" and "تعديل": the times are chosen in the sheet.
  Future<void> _askRide(SubscriptionModel sub, RideMoment moment) async {
    final now = DateTime.now();
    final choice = await RideSheet.show(
      context,
      title: RideWords.rideOf(moment.day, now),
      subtitle: '${RideWords.date(moment.day)} · من ${sub.boardingTitle}',
      declineLabel: 'لن أركب ${RideWords.when(moment.day, now)}',
      departures: _availableTimes(sub.departureTimes, sub.departureTime),
      returns: _availableTimes(sub.returnTimes, sub.returnTime),
      departureLabel: BasakUi.time12,
      // The way back starts at the university: that is the time shown.
      returnLabel: (time) => BasakUi.time12(sub.returnShown(time)),
      departure: _selectedDepartureTime,
      returnTime: _selectedReturnTime,
      returning: _isReturningToday,
    );
    if (choice == null || !mounted) return;
    await _confirmRide(sub, choice);
  }

  Future<void> _confirmRide(SubscriptionModel sub, RideChoice choice) async {
    // One vote at a time, however fast the button is tapped.
    if (_isSavingRide) return;
    final repository = ref.read(dailyRideRepoProvider);
    final vote = _vote;
    final now = DateTime.now();
    final rideDate = vote.rideDateFor(now);
    if (!vote.isOpenAt(now)) {
      // Closed while the sheet was open: the card says so from now on.
      _toast('انتهى وقت تأكيد ${RideWords.rideOf(rideDate, now)}.', failed: true);
      setState(() {});
      return;
    }
    final isRiding = choice.riding;
    final departureTimes =
        _availableTimes(sub.departureTimes, sub.departureTime);
    final returnTimes = _availableTimes(sub.returnTimes, sub.returnTime);
    // "Not riding" keeps the times last chosen, for the next "yes".
    final departureTime = isRiding
        ? choice.departure
        : (departureTimes.contains(_selectedDepartureTime) ? _selectedDepartureTime : departureTimes.firstOrNull);
    final isReturning = isRiding ? choice.returning : _isReturningToday;
    final returnTime = isRiding
        ? choice.returnTime
        : (returnTimes.contains(_selectedReturnTime) ? _selectedReturnTime : returnTimes.firstOrNull);
    if (isRiding && !departureTimes.contains(departureTime)) {
      _toast('لا توجد مواعيد ذهاب متاحة لهذا الخط.', failed: true);
      return;
    }
    // Show the choice at once; if the server refuses, put the previous one back.
    final before = (
      riding: _isRidingToday,
      returns: _isReturningToday,
      departure: _selectedDepartureTime,
      returning: _selectedReturnTime,
      confirmed: _confirmedDepartureTime,
      week: _weeklyRideStatuses,
      loaded: _loadedRideDate,
    );
    final rideDay = DateTime(rideDate.year, rideDate.month, rideDate.day);
    setState(() {
      _isSavingRide = true;
      _isRidingToday = isRiding;
      _isReturningToday = isReturning;
      _selectedDepartureTime = departureTime;
      _selectedReturnTime = returnTime;
      _confirmedDepartureTime = isRiding ? departureTime : null;
      _weeklyRideStatuses = {..._weeklyRideStatuses, rideDay: isRiding};
      // The vote for this day is known from here on, read or not.
      _loadedRideDate = rideDate;
    });
    try {
      final result = await repository.confirmRide(
        rideDate: rideDate,
        isRiding: isRiding,
        departureTime: departureTime,
        returnTime: returnTime,
        isReturning: isReturning,
      );
      if (!mounted) return;
      setState(() {
        _isRidingToday = result.isRiding;
        _isReturningToday = result.isReturning;
        _selectedDepartureTime = result.departureTime;
        _selectedReturnTime = result.returnTime;
        _confirmedDepartureTime = result.isRiding ? result.departureTime : null;
        _isSavingRide = false;
      });
      // Voted (riding or not): no more reminders for this ride.
      unawaited(_planReminders(justVoted: rideDay));
      _toast(isRiding
          ? 'تم تأكيد حضورك ومواعيد رحلتك ليوم ${BasakUi.dateLabel(rideDate)}.'
          : 'تم إلغاء تأكيد الحضور.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSavingRide = false;
        _isRidingToday = before.riding;
        _isReturningToday = before.returns;
        _selectedDepartureTime = before.departure;
        _selectedReturnTime = before.returning;
        _confirmedDepartureTime = before.confirmed;
        _weeklyRideStatuses = before.week;
        _loadedRideDate = before.loaded;
      });
      _toast(errorMessage(e), failed: true);
    }
  }

  List<String> _availableTimes(List<String> configured, String? fallback) {
    final values = configured.where((time) => time.trim().isNotEmpty).toList();
    if (values.isEmpty && fallback != null && fallback.trim().isNotEmpty) {
      values.addAll(fallback
          .split(RegExp(r'[,،]'))
          .map((time) => time.trim())
          .where((time) => time.isNotEmpty));
    }
    values.sort();
    return values;
  }

  void _toast(String message, {bool failed = false}) =>
      BasakToast.show(context, message, kind: failed ? BasakToastKind.failure : BasakToastKind.success);

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(currentSubscriptionProvider);
    // Back from the background, or reconnected: read the ride vote again.
    ref.listen(rideStatusTickProvider, (_, __) => _loadTodayRideStatus());
    // New vote times may move the ride day; the reminders follow both.
    ref.listen(voteSettingsProvider, (previous, next) {
      if (next.hasValue && (_loadedRideDate == null || previous?.valueOrNull != next.valueOrNull)) {
        _loadTodayRideStatus();
      } else if (next.hasError && _loadedRideDate == null) {
        _loadTodayRideStatus();
      }
    });
    ref.listen(currentSubscriptionProvider, (previous, next) {
      final before = previous?.valueOrNull, after = next.valueOrNull;
      if (next.hasValue &&
          (previous?.hasValue != true ||
              before?.id != after?.id ||
              before?.status != after?.status)) {
        _planReminders();
      }
    });
    final vote = ref.watch(voteSettingsProvider).valueOrNull ??
        VoteSettings.fallback;
    final user = ref.watch(authStateProvider).user;
    final profileAsync = user == null
        ? const AsyncValue<Map<String, dynamic>?>.data(null)
        : ref.watch(studentProfileSummaryProvider(user.id));
    final name = (user?.userMetadata?['full_name'] as String?)?.trim();
    final photo = studentPhoto(profileAsync.valueOrNull?['profile_image_url'] as String?);
    final invites = ref.watch(myInvitesProvider).valueOrNull ?? const <CompanyInvite>[];
    final colors = context.colors;

    final List<Widget> children;
    if (subAsync.hasValue) {
      final sub = subAsync.value;
      children = [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GreetingHeader(
              // Greeted by the first two names; the full name is on
              // the card, the receipts and the profile.
              name: (name == null || name.isEmpty) ? 'طالبنا' : GreetingHeader.firstTwoNames(name),
              photoUrl: photo == null ? null : ref.watch(signedPhotoProvider(photo)).valueOrNull,
              unread: ref.watch(unreadNotificationsProvider),
              onNotifications: () => NotificationsScreen.open(context),
            ),
            // Saved data on screen: said here, under the header.
            ConnectionStripHost(
              onRetry: _handleRefresh,
              padding: const EdgeInsetsDirectional.only(top: BasakSpace.s12),
            ),
          ],
        ),
        if (invites.isNotEmpty) const InvitesCard(),
        if (sub != null)
          _pass(sub)
        else if (invites.isEmpty)
          _StartCard(
            university: _withoutTitle(profileAsync.valueOrNull?['university'] as String?),
            onStart: widget.onNavigateToSubscription,
          )
        else
          // An invitation is one way in; choosing a subscription is the other.
          SheetLink(label: 'أو اختر اشتراكك بنفسك', onTap: widget.onNavigateToSubscription),
        if (sub != null && !sub.isExpired)
          sub.isActive ? _ride(sub, vote) : const RideLockedCard(),
        if (sub != null && (sub.supervisorPhone ?? '').isNotEmpty) _supervisor(sub),
      ];
    } else if (subAsync.hasError) {
      final offline = isNetworkFailure(subAsync.error!);
      children = [
        SizedBox(height: MediaQuery.sizeOf(context).height * .14),
        PageError(
          icon: offline ? LucideIcons.wifiOff : LucideIcons.triangleAlert,
          title: offline ? 'لا يوجد اتصال' : 'تعذر تحميل بيانات الاشتراك',
          message: offline
              ? 'نحتاج الإنترنت مرة واحدة لتحميل بياناتك. بعدها تعمل بطاقتك واشتراكك بدون اتصال.'
              : errorMessage(subAsync.error!),
          onAction: () => ref.invalidate(currentSubscriptionProvider),
        ),
      ];
    } else {
      // A true first load, with nothing saved: the page's own shape.
      children = const [HomeSkeleton()];
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: colors.ground,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: BasakPage(
        onRefresh: _handleRefresh,
        // Clear of the floating tab bar, whose height the shell reports here.
        bottomInset: MediaQuery.paddingOf(context).bottom + BasakSpace.s24,
        children: children,
      ),
    );
  }

  /// "جامعة المنصورة الجديدة" → "المنصورة الجديدة": the caption already says
  /// it is the university.
  static String? _withoutTitle(String? university) {
    final name = (university ?? '').trim().replaceFirst(RegExp(r'^(جامعة|جامعه)\s+'), '');
    return name.isEmpty ? null : name;
  }

  static String _lineTitle(SubscriptionModel sub) {
    final line = (sub.lineName ?? '').trim();
    if (line.isEmpty) return 'الخط';
    return line.startsWith('خط ') ? line : 'خط $line';
  }

  static BasakStatus _statusOf(SubscriptionModel sub) {
    if (sub.isExpired) return BasakStatus.expired;
    if (sub.isActive) return sub.isUpcoming ? BasakStatus.upcoming : BasakStatus.active;
    if (sub.isPendingReview) return BasakStatus.pendingReview;
    if (sub.isRejected) return BasakStatus.rejected;
    return BasakStatus.pendingPayment;
  }

  /// The pass: always a ticket. Its stub carries the one thing to do, or,
  /// with nothing to do, the line and the way to the card.
  Widget _pass(SubscriptionModel sub) {
    final status = _statusOf(sub);
    final company = (sub.companyName ?? '').trim();
    final line = _lineTitle(sub);
    final starts = DateTime.tryParse(sub.startDate ?? '');
    final toSubscription = widget.onNavigateToSubscription;

    final Widget footer = switch (status) {
      BasakStatus.active =>
        PassStub(line: line, company: company, onShowCard: widget.onNavigateToQr),
      BasakStatus.upcoming =>
        PassStub(line: line, company: company, onShowCard: widget.onNavigateToQr, onInk: false),
      BasakStatus.pendingReview => const StepLine(steps: ['أُرسل الإيصال', 'المراجعة', 'التفعيل'], current: 1),
      BasakStatus.pendingPayment => PassAction(
          caption: 'المبلغ المطلوب', value: formatMoney(sub.price), actionLabel: 'ادفع الآن', onAction: toSubscription),
      BasakStatus.rejected => PassAction(
          caption: 'المبلغ المطلوب', value: formatMoney(sub.price), actionLabel: 'إيصال جديد', onAction: toSubscription),
      BasakStatus.expired => PassAction(
          caption: sub.periodName, value: formatMoney(sub.price), actionLabel: 'جدّد', onAction: toSubscription),
    };
    // With the line in the stub, the destination is captioned as what it is.
    final stubbed = status == BasakStatus.active || status == BasakStatus.upcoming;

    return PassCard(
      status: status,
      period: status == BasakStatus.upcoming && starts != null
          ? '${sub.periodName} · ${starts.day} ${BasakUi.arabicMonths[starts.month - 1]}'
          : sub.periodName,
      onPeriodTap: status == BasakStatus.active ? toSubscription : null,
      from: sub.boardingTitle,
      to: _withoutTitle(sub.destination) ?? line,
      toCaption: stubbed ? 'الجامعة' : (company.isEmpty ? line : '$line · $company'),
      footer: footer,
    );
  }

  Widget _ride(SubscriptionModel sub, VoteSettings vote) {
    final now = DateTime.now();
    final rideDay = vote.rideDateFor(now);
    final loaded = _loadedRideDate;
    // What was read is about this ride day (not the one before a roll-over).
    final known = loaded != null && DateUtils.isSameDay(loaded, rideDay);
    final moment = RideMoment.resolve(
      vote: vote,
      now: now,
      known: known,
      riding: known && _isRidingToday,
      voted: known && _weeklyRideStatuses.containsKey(rideDay),
      hasDepartures: _availableTimes(sub.departureTimes, sub.departureTime).isNotEmpty,
    );
    final returnTime = _selectedReturnTime;
    final showsWeek = moment.kind == RideCardKind.ask || moment.isConfirmed;
    return ValueListenableBuilder<DateTime?>(
      // Writes are never queued: without a connection the card says so.
      valueListenable: OfflineCache.offlineSince,
      builder: (context, offlineSince, _) => RideCard(
        moment: moment,
        now: now,
        offline: offlineSince != null,
        saving: _isSavingRide,
        departureLabel: _confirmedDepartureTime == null ? null : BasakUi.time12(_confirmedDepartureTime),
        returnLabel:
            _isReturningToday && returnTime != null ? BasakUi.time12(sub.returnShown(returnTime)) : null,
        week: showsWeek
            ? RideWords.week(
                asked: moment.day,
                statuses: _weeklyRideStatuses,
                vote: vote,
                ringAsked: moment.kind == RideCardKind.ask)
            : const [],
        onYes: () => _askRide(sub, moment),
        onNo: () => _confirmRide(sub, const RideChoice.notRiding()),
        onEdit: () => _askRide(sub, moment),
      ),
    );
  }

  /// The bus supervisor: one row, a call and a WhatsApp chat one tap away.
  /// Tapping the row opens the sheet with the rest (save, copy).
  Widget _supervisor(SubscriptionModel sub) {
    final photoUrl = sub.supervisorPhotoPath == null
        ? null
        : ref.watch(signedPhotoProvider((bucket: 'supervisor-avatars', path: sub.supervisorPhotoPath!))).valueOrNull;
    final photo = photoUrl == null ? null : avatarImage(photoUrl);
    final name = sub.supervisorName ?? 'مشرف الخط';
    final phone = sub.supervisorPhone ?? '';
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      key: const Key('supervisor-card'),
      onTap: () =>
          SupervisorContactSheet.show(context, name: name, phone: phone, lineName: sub.lineName, photo: photo),
      child: BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16, vertical: BasakSpace.s14),
        child: Row(
          children: [
            PhotoRing(name: name, image: photo),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body.copyWith(fontWeight: FontWeight.w500)),
                  Text('مشرف الباص', style: text.caption.copyWith(color: colors.ink3)),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s8),
            BasakIconButton(
              key: const Key('supervisor-row-call'),
              icon: LucideIcons.phone,
              label: 'اتصال بالمشرف',
              onCard: true,
              onPressed: () => SupervisorContactSheet.call(context, phone),
            ),
            const SizedBox(width: BasakSpace.s6),
            BasakIconButton(
              key: const Key('supervisor-row-whatsapp'),
              icon: LucideIcons.messageCircle,
              label: 'واتساب المشرف',
              onCard: true,
              onPressed: () => SupervisorContactSheet.whatsapp(context, phone),
            ),
          ],
        ),
      ),
    );
  }
}

/// No subscription yet: the route with what is already known (the
/// university) and the stop still to choose, and the way in.
class _StartCard extends StatelessWidget {
  final String? university;
  final VoidCallback onStart;

  const _StartCard({required this.university, required this.onStart});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'اشتراكك',
        child: BasakCard(
          radius: BasakRadius.sheet,
          padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ابدأ اشتراكك', style: context.text.title),
              const SizedBox(height: BasakSpace.s18),
              RouteRail(
                from: 'اختر محطتك',
                fromPending: true,
                to: university ?? 'جامعتك',
                toCaption: university == null ? 'الجامعة' : 'جامعتك',
                large: true,
              ),
              const SizedBox(height: BasakSpace.s18),
              BasakButton(label: 'اشترك الآن', onPressed: onStart),
            ],
          ),
        ),
      );
}
