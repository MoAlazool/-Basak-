import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/ui/ui.dart';
import '../../../core/widgets/basak_ui.dart' show BasakUi;
import '../../../core/widgets/skeleton.dart';
import '../../notifications/data/notification_feed.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/data/quick_templates.dart';
import '../data/supervisor_repository.dart';
import '../models/supervisor_models.dart';
import '../selection/supervisor_selection.dart';
import '../supervisor_copy.dart';
import 'supervisor_notifications_screen.dart' show sendAnnouncedOnce;

/// Who a supervisor's message goes to: every student of one of their lines,
/// or the riders of one of its trips today or on the next ride day.
class SendAudience {
  final SupervisorLine line;

  /// Null: every student of [line].
  final SupervisorTripTime? trip;

  /// The server's today, to say «اليوم» or «غداً».
  final DateTime today;

  const SendAudience({required this.line, this.trip, required this.today});

  String get lineId => line.id;
  String? get tripId => trip?.tripId;
  String? get rideDate => trip?.rideDate.toIso8601String().substring(0, 10);

  /// How many students will receive it.
  int get students => trip?.students ?? line.registeredStudents;

  /// "خط الزرقا", whether or not the line's name already says «خط».
  String get lineName => line.name.trim().startsWith('خط ') ? line.name.trim() : 'خط ${line.name.trim()}';

  static String day(SupervisorTripTime trip, DateTime today) => DateUtils.isSameDay(trip.rideDate, today) ? 'اليوم' : 'غداً';

  /// "ذهاب 7:00 ص".
  static String tripName(SupervisorTripTime trip) =>
      '${SupervisorCopy.direction(trip.direction)} ${BasakUi.time12(trip.time)}';

  /// "اليوم · ذهاب 7:00 ص": a trip as the audience row and its sheet name it.
  static String tripTitle(SupervisorTripTime trip, DateTime today) => '${day(trip, today)} · ${tripName(trip)}';

  /// "ركاب ذهاب 7:00 ص اليوم", or "كل طلاب خط الزرقا".
  String get sentence => trip == null ? 'كل طلاب $lineName' : 'ركاب ${tripName(trip!)} ${day(trip!, today)}';

  /// What tells one send from another, besides its text.
  String get signature => '$lineId|$tripId|$rideDate';
}

/// One send, as the server tells repeats apart: the same message to the same
/// people keeps its key, so a retry after a lost answer is never delivered
/// twice; anything changed is a new send with a new key.
class SendKey {
  String? _for;
  String _key = '';

  String of(String what) {
    if (what != _for) {
      _for = what;
      _key = newUuid();
    }
    return _key;
  }
}

/// «إشعار للطلاب»: who it reaches (the riders of one trip, or the whole
/// line), then what it says: one of the server's ready messages, or a text
/// of the supervisor's own. Either way it is confirmed in [SendConfirmSheet]
/// before it goes out. Pops with what was sent.
class SupervisorSendScreen extends ConsumerStatefulWidget {
  const SupervisorSendScreen({super.key});

  /// "تم إرسال الإشعار إلى 38 طالباً."
  static String sentMessage(SendResult result) => result.duplicate
      ? 'سبق إرسال هذا الإشعار، ولم يُرسل مرة أخرى.'
      : 'تم إرسال الإشعار إلى ${ArabicCount.students(result.students, oblique: true)}.';

  /// Opens the page; what was sent is said in a toast on the screen it was
  /// opened from, and the inbox is read once for it.
  static Future<void> open(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context)
        .push(MaterialPageRoute<SendResult>(builder: (_) => const SupervisorSendScreen()));
    if (result == null || !context.mounted) return;
    ref.invalidate(notificationFeedProvider);
    BasakToast.show(context, sentMessage(result));
  }

  @override
  ConsumerState<SupervisorSendScreen> createState() => _SupervisorSendScreenState();
}

class _SupervisorSendScreenState extends ConsumerState<SupervisorSendScreen> {
  final _key = SendKey();

  /// Null until the supervisor chooses: then the trip picked on Trips, when
  /// it has riders, else the whole line.
  bool? _riders;
  SupervisorTripTime? _trip;

  SupervisorLine _line(SupervisorDashboard dashboard) {
    final chosen = ref.watch(supervisorSelectionProvider).lineId;
    return dashboard.lines.firstWhere((l) => l.id == chosen, orElse: () => dashboard.lines.first);
  }

  /// Only trips someone rides can be written to.
  List<SupervisorTripTime> _trips(SupervisorDashboard dashboard, SupervisorLine line) =>
      dashboard.tripTimes.where((t) => t.lineId == line.id && t.tripId != null && t.students > 0).toList();

  static bool _same(SupervisorTripTime a, SupervisorTripTime b) => a.tripId == b.tripId && a.rideDate == b.rideDate;

  /// The trip the message goes to: the one chosen here, else the one picked
  /// on Trips (today's), else none.
  SupervisorTripTime? _currentTrip(SupervisorDashboard dashboard, List<SupervisorTripTime> trips) {
    if (_riders == false || trips.isEmpty) return null;
    final picked = _trip;
    if (picked != null) {
      for (final t in trips) {
        if (_same(t, picked)) return t;
      }
    }
    final selection = ref.watch(supervisorSelectionProvider);
    if (selection.hasTrip) {
      for (final t in trips) {
        if (DateUtils.isSameDay(t.rideDate, dashboard.today) &&
            SupervisorSelection.keyOf(TripDirection.fromWire(t.direction), t.time) == selection.tripKey) {
          return t;
        }
      }
    }
    return _riders == true ? trips.first : null;
  }

  Future<void> _pickTrip(SupervisorDashboard dashboard, List<SupervisorTripTime> trips, SupervisorTripTime current) async {
    final picked = await BasakSheet.show<SupervisorTripTime>(
      context,
      title: 'الرحلة',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in trips) ...[
            SheetRadioRow(
              title: SendAudience.tripTitle(t, dashboard.today),
              subtitle: ArabicCount.students(t.students),
              selected: _same(t, current),
              onTap: () => Navigator.of(sheet).pop(t),
            ),
            const SizedBox(height: BasakSpace.s4),
          ],
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _riders = true;
        _trip = picked;
      });
    }
  }

  Future<void> _confirm(SendAudience audience, QuickNotificationTemplate template) async {
    final result = await SendConfirmSheet.show(context, audience: audience, template: template, sendKey: _key);
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  Future<void> _write(SendAudience audience) async {
    final result = await Navigator.of(context).push(
        MaterialPageRoute<SendResult>(builder: (_) => SupervisorCustomMessageScreen(audience: audience)));
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supervisorDashboardProvider);
    final dashboard = async.valueOrNull;

    final List<Widget> blocks;
    if (dashboard == null) {
      blocks = [
        if (async.hasError)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: BasakSpace.s40),
            child: PageError(
              title: 'تعذّر تحميل بيانات الخط',
              message: 'تحقّق من الاتصال بالإنترنت ثم أعد المحاولة.',
              onAction: () => ref.invalidate(supervisorDashboardProvider),
            ),
          )
        else
          const SkeletonList(rows: 4, avatars: false),
      ];
    } else if (dashboard.lines.isEmpty) {
      blocks = const [
        Padding(
          padding: EdgeInsetsDirectional.only(top: BasakSpace.s40),
          child: EmptyState(
            page: true,
            icon: LucideIcons.megaphone,
            title: 'لا يوجد خط مسند إليك',
            message: 'يتاح بعد أن تسند الشركة خطاً إلى حسابك.',
          ),
        ),
      ];
    } else {
      blocks = _blocks(context, dashboard);
    }

    return Scaffold(
      backgroundColor: context.colors.ground,
      body: BasakPage(
        header: const BasakBackHeader(title: 'إشعار للطلاب', inlineTitle: true),
        children: blocks,
      ),
    );
  }

  List<Widget> _blocks(BuildContext context, SupervisorDashboard dashboard) {
    final line = _line(dashboard);
    final trips = _trips(dashboard, line);
    final trip = _currentTrip(dashboard, trips);
    final audience = SendAudience(line: line, trip: trip, today: dashboard.today);
    final templatesAsync = ref.watch(quickTemplatesProvider);
    final templates = [
      for (final t in templatesAsync.valueOrNull ?? const <QuickNotificationTemplate>[])
        if (t.fits(trip?.direction)) t,
    ];

    return [
      GroupSection(
        title: 'يصل إلى',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AudienceTile(
                      key: const Key('send-to-trip'),
                      title: 'ركاب رحلة',
                      subtitle: trips.isEmpty ? 'لا توجد تأكيدات بعد' : 'من أكّدوا موعداً',
                      selected: trip != null,
                      onTap: trips.isEmpty
                          ? null
                          : () => setState(() {
                                _riders = true;
                                _trip ??= trips.first;
                              }),
                    ),
                  ),
                  const SizedBox(width: BasakSpace.s8),
                  Expanded(
                    child: AudienceTile(
                      key: const Key('send-to-line'),
                      title: 'كل طلاب الخط',
                      subtitle: ArabicCount.subscribers(line.registeredStudents),
                      selected: trip == null,
                      onTap: () => setState(() => _riders = false),
                    ),
                  ),
                ],
              ),
            ),
            if (trip != null) ...[
              const SizedBox(height: BasakSpace.s8),
              PickRow(
                key: const Key('send-trip'),
                value: SendAudience.tripTitle(trip, dashboard.today),
                note: ArabicCount.students(trip.students),
                onTap: () => _pickTrip(dashboard, trips, trip),
              ),
            ],
          ],
        ),
      ),
      if (templatesAsync.isLoading && !templatesAsync.hasValue)
        const GroupSection(title: 'الرسالة', child: SkeletonList(rows: 3, avatars: false))
      else if (templatesAsync.hasError && !templatesAsync.hasValue)
        GroupSection(
          title: 'الرسالة',
          child: InlineError(
            message: 'تعذّر تحميل الرسائل الجاهزة.',
            onRetry: () => ref.invalidate(quickTemplatesProvider),
          ),
        )
      else if (templates.isNotEmpty)
        GroupSection(
          title: 'الرسالة',
          child: MessageRows(rows: [
            for (final template in templates)
              MessageRow(
                key: Key('send-template-${template.key}'),
                title: template.title,
                preview: template.preview(null),
                onTap: () => _confirm(audience, template),
              ),
          ]),
        ),
      LinkCard(
        key: const Key('send-custom'),
        icon: LucideIcons.pencil,
        title: 'رسالة أخرى',
        subtitle: 'اكتب العنوان والنص بنفسك',
        onTap: () => _write(audience),
      ),
    ];
  }
}

/// «رسالة أخرى»: a title and a text of the supervisor's own, each counted
/// against its limit as it is typed, and who it goes to. «متابعة» opens the
/// confirm sheet; nothing is sent from here. Pops with what was sent.
class SupervisorCustomMessageScreen extends ConsumerStatefulWidget {
  final SendAudience audience;

  const SupervisorCustomMessageScreen({super.key, required this.audience});

  static const titleLimit = 80;
  static const bodyLimit = 600;

  @override
  ConsumerState<SupervisorCustomMessageScreen> createState() => _SupervisorCustomMessageScreenState();
}

class _SupervisorCustomMessageScreenState extends ConsumerState<SupervisorCustomMessageScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _key = SendKey();

  @override
  void initState() {
    super.initState();
    _title.addListener(_typed);
    _body.addListener(_typed);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _typed() => setState(() {});

  bool get _ready => _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;

  Future<void> _continue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await SendConfirmSheet.show(
      context,
      audience: widget.audience,
      title: _title.text.trim(),
      body: _body.text.trim(),
      sendKey: _key,
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final audience = widget.audience;
    return Scaffold(
      backgroundColor: context.colors.ground,
      body: BasakPage(
        header: const BasakBackHeader(title: 'رسالة أخرى', inlineTitle: true),
        dock: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                BasakSpace.gutter, BasakSpace.s8, BasakSpace.gutter, BasakSpace.s16),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth - 2 * BasakSpace.gutter),
                child: BasakButton(
                  key: const Key('send-continue'),
                  label: 'متابعة',
                  onPressed: _ready ? _continue : null,
                ),
              ),
            ),
          ),
        ),
        children: [
          CountedField(
            key: const Key('send-title'),
            label: 'العنوان',
            controller: _title,
            maxLength: SupervisorCustomMessageScreen.titleLimit,
            hint: 'مثال: تغيير مكان الركوب',
            textInputAction: TextInputAction.next,
          ),
          CountedField(
            key: const Key('send-body'),
            label: 'نص الإشعار',
            controller: _body,
            maxLength: SupervisorCustomMessageScreen.bodyLimit,
            hint: 'اكتب ما تريد أن يعرفه الطلاب',
            lines: 5,
          ),
          PickRow(
            label: 'يصل إلى',
            value: '${audience.sentence} · ${SupervisorCopy.grouped(audience.students)}',
            opensSheet: false,
            // The audience is chosen on the page before this one.
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The last look before a message goes out: the notification as the student
/// will see it, the minutes when the message needs them, and who receives it.
/// A ready message is written by the server from [template]; a text of the
/// supervisor's own is sent as [title] and [body]. The server checks the line
/// is this supervisor's and limits how often; what it refuses is shown in its
/// own words. Pops with what was sent.
class SendConfirmSheet extends ConsumerStatefulWidget {
  final SendAudience audience;
  final QuickNotificationTemplate? template;
  final String? title;
  final String? body;
  final SendKey sendKey;

  const SendConfirmSheet({
    super.key,
    required this.audience,
    this.template,
    this.title,
    this.body,
    required this.sendKey,
  }) : assert(template != null || (title != null && body != null));

  /// The delays offered for a message that needs minutes.
  static const minuteChoices = [5, 10, 15, 20, 30, 45];

  static Future<SendResult?> show(
    BuildContext context, {
    required SendAudience audience,
    QuickNotificationTemplate? template,
    String? title,
    String? body,
    required SendKey sendKey,
  }) =>
      BasakSheet.showFrame<SendResult>(
        context,
        builder: (_) =>
            SendConfirmSheet(audience: audience, template: template, title: title, body: body, sendKey: sendKey),
      );

  @override
  ConsumerState<SendConfirmSheet> createState() => _SendConfirmSheetState();
}

class _SendConfirmSheetState extends ConsumerState<SendConfirmSheet> {
  late int? _minutes = widget.template?.needsMinutes == true ? 10 : null;
  bool _sending = false;
  String? _refused;

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _refused = null;
    });
    final audience = widget.audience;
    final template = widget.template;
    final repo = ref.read(notificationsRepoProvider);
    try {
      final result = await sendAnnouncedOnce(() => template != null
          ? repo.sendQuick(
              templateKey: template.key,
              lineId: audience.lineId,
              tripId: audience.tripId,
              rideDate: audience.rideDate,
              minutes: _minutes,
              idempotencyKey: widget.sendKey.of('${template.key}|${audience.signature}|$_minutes'),
            )
          : repo.send(
              title: widget.title!,
              body: widget.body!,
              lineId: audience.lineId,
              tripId: audience.tripId,
              rideDate: audience.rideDate,
              idempotencyKey: widget.sendKey.of('${audience.signature}|${widget.title}|${widget.body}'),
            ));
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _refused = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final audience = widget.audience;
    return BasakSheetFrame(
      title: 'تأكيد الإرسال',
      largeTitle: true,
      primary: BasakButton(
        key: const Key('send-confirm'),
        label: 'تأكيد الإرسال',
        icon: LucideIcons.send,
        loading: _sending,
        loadingLabel: 'جارٍ الإرسال…',
        onPressed: _send,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NotificationPreview(
            sender: 'باصك · مشرف الباص',
            title: template?.title ?? widget.title!,
            body: template?.preview(_minutes) ?? widget.body!,
          ),
          if (template?.needsMinutes == true) ...[
            const SizedBox(height: BasakSpace.s18),
            Text('المدة بالدقائق', style: context.text.label.copyWith(color: context.colors.ink2)),
            const SizedBox(height: BasakSpace.s8),
            Semantics(
              container: true,
              label: 'المدة بالدقائق',
              child: ChipChoice<int>(
                options: SendConfirmSheet.minuteChoices,
                value: _minutes,
                onChanged: (minutes) => setState(() => _minutes = minutes),
                label: (minutes) => '$minutes',
              ),
            ),
          ],
          const SizedBox(height: BasakSpace.s18),
          ReachLine(count: ArabicCount.students(audience.students), audience: audience.sentence),
          if (_refused != null) ...[
            const SizedBox(height: BasakSpace.s14),
            InlineError(message: _refused!),
          ],
          const SizedBox(height: BasakSpace.s4),
        ],
      ),
    );
  }
}
