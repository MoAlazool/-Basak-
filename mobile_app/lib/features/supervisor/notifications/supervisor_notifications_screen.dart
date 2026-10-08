import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/basak_ui.dart';
import '../../notifications/data/notification_feed.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/data/quick_templates.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../data/supervisor_repository.dart';
import '../models/supervisor_models.dart';

/// The supervisor's notifications: what the company sent to the students of
/// their lines, what they sent themselves, ready operational messages to send
/// with two taps, and a card to write to the students.
class SupervisorNotificationsScreen extends StatelessWidget {
  const SupervisorNotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SupervisorNotificationsScreen()));

  @override
  Widget build(BuildContext context) => const NotificationsPage(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_SendCard(), _QuickActions()],
        ),
      );
}

/// Tells the supervisor what was sent, after a sheet closed with its result.
void _announceSent(BuildContext context, WidgetRef ref, SendResult? result) {
  if (result == null || !context.mounted) return;
  ref.invalidate(notificationFeedProvider);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(result.duplicate
        ? 'سبق إرسال هذا الإشعار، ولم يُرسل مرة أخرى.'
        : 'تم إرسال الإشعار إلى ${result.students} طالب.'),
    backgroundColor: AppColors.success,
    behavior: SnackBarBehavior.floating,
  ));
}

class _SendCard extends ConsumerWidget {
  const _SendCard();

  Future<void> _compose(BuildContext context, WidgetRef ref, SupervisorDashboard dashboard) async {
    final result = await showModalBottomSheet<SendResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SendNotificationSheet(dashboard: dashboard),
    );
    if (context.mounted) _announceSent(context, ref, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(supervisorDashboardProvider).valueOrNull;
    final hasLines = dashboard != null && dashboard.lines.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: BasakUi.heroGradient,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.megaphone, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('أرسل إشعاراً لطلابك',
                  style: AppTextStyles.titleMedium.copyWith(color: Colors.white)),
              const SizedBox(height: 3),
              Text(
                  hasLines
                      ? 'لكل طلاب الخط أو لركاب رحلة اليوم فقط.'
                      : 'يتاح بعد أن تسند الشركة خطاً إلى حسابك.',
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
            ]),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: hasLines ? () => _compose(context, ref, dashboard) : null,
            icon: const Icon(LucideIcons.send, size: 16),
            label: const Text('إرسال'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: BasakUi.teal,
              disabledBackgroundColor: Colors.white24,
              // The theme's buttons span the width; this one sits in a row.
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The ready operational messages (the bus is late, it left, it arrived, the
/// return is leaving from the university, …): one tap to choose, one to confirm.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  Future<void> _send(BuildContext context, WidgetRef ref, SupervisorDashboard dashboard,
      QuickNotificationTemplate template) async {
    final result = await showModalBottomSheet<SendResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickNotificationSheet(dashboard: dashboard, template: template),
    );
    if (context.mounted) _announceSent(context, ref, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(supervisorDashboardProvider).valueOrNull;
    final templates = ref.watch(quickTemplatesProvider).valueOrNull ?? const [];
    if (dashboard == null || dashboard.lines.isEmpty || templates.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('إشعارات سريعة',
            style: AppTextStyles.bodyMedium
                .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final template in templates)
            ActionChip(
              label: Text(template.title),
              avatar: const Icon(LucideIcons.zap, size: 15, color: BasakUi.teal),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFE0E8EE)),
              onPressed: () => _send(context, ref, dashboard, template),
            ),
        ]),
      ]),
    );
  }
}

/// A trip the supervisor can write to: its riders on [rideDate].
typedef _TripChoice = ({String tripId, DateTime rideDate, String direction, String label});

/// Who a supervisor's notification goes to: one of their lines, and either
/// all its students or the riders of one of its trips today or on the next
/// ride day. Shared by the free-text composer and the quick messages.
mixin _Audience<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  SupervisorDashboard get dashboard;

  /// Only trips going this way are offered (null = both).
  String? get direction => null;

  late String lineId = dashboard.lines.first.id;
  _TripChoice? trip;

  SupervisorLine get line => dashboard.lines.firstWhere((l) => l.id == lineId);

  List<SupervisorTripTime> get trips => dashboard.tripTimes
      .where((t) =>
          t.lineId == lineId &&
          t.tripId != null &&
          t.students > 0 &&
          (direction == null || t.direction == direction))
      .toList();

  /// "اليوم · ذهاب 7:00 ص · 4 طالب". The return leaves from the university
  /// (there are no return stations), and is worded so.
  String tripLabel(SupervisorTripTime t) {
    final today = dashboard.today;
    final isToday = t.rideDate.year == today.year &&
        t.rideDate.month == today.month &&
        t.rideDate.day == today.day;
    return '${isToday ? 'اليوم' : 'غداً'} · ${t.isReturn ? 'عودة من الجامعة' : 'ذهاب'} '
        '${BasakUi.time12(t.time)} · ${t.students} طالب';
  }

  String? get rideDate => trip?.rideDate.toIso8601String().substring(0, 10);

  /// Who will receive it, in words.
  String get recipients => trip == null
      ? 'كل طلاب ${line.name} (${line.registeredStudents} طالب)'
      : 'ركاب رحلة ${trip!.label} على ${line.name}';

  Widget label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text,
            style: AppTextStyles.bodyMedium
                .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
      );

  Widget choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: BasakUi.teal,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
            color: selected ? Colors.white : BasakUi.ink,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        side: BorderSide(color: selected ? BasakUi.teal : const Color(0xFFE0E8EE)),
      );

  /// The line (when there is more than one) and "reaches" pickers.
  List<Widget> audiencePickers() => [
        if (dashboard.lines.length > 1) ...[
          label('الخط'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in dashboard.lines)
              choice(l.name, l.id == lineId, () => setState(() {
                    lineId = l.id;
                    trip = null;
                  })),
          ]),
        ],
        label('يصل إلى'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          choice('كل طلاب الخط', trip == null, () => setState(() => trip = null)),
          for (final t in trips)
            choice(
              tripLabel(t),
              trip?.tripId == t.tripId && trip?.rideDate == t.rideDate,
              () => setState(() => trip = (
                    tripId: t.tripId!,
                    rideDate: t.rideDate,
                    direction: t.direction,
                    label: tripLabel(t),
                  )),
            ),
        ]),
      ];

  void showError(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));

  Widget sheet(List<Widget> children) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.paddingOf(context).bottom + 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: const Color(0xFFD9E3EA), borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 16),
              ...children,
            ]),
          ),
        ),
      );

  Widget sendButton(String text, {required bool sending, required VoidCallback onPressed}) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: sending ? null : onPressed,
          icon: sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(LucideIcons.send, size: 18),
          label: Text(text),
          style: ElevatedButton.styleFrom(
            backgroundColor: BasakUi.teal,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
      );
}

/// One send, as the server tells repeats apart: the same message to the same
/// people keeps its key, so a retry after a lost answer is never delivered
/// twice; anything changed is a new send with a new key.
class _SendKey {
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

/// Writes a notification to a line's students, or to the riders of one of
/// its trips today or on the next ride day. Pops with what was sent.
class SendNotificationSheet extends ConsumerStatefulWidget {
  final SupervisorDashboard dashboard;

  const SendNotificationSheet({super.key, required this.dashboard});

  /// Ready-made messages: (chip, title, text).
  static const templates = [
    ('الباص سيتأخر', 'تأخير الباص', 'سيتأخر الباص نحو 10 دقائق عن موعده. شكراً لتفهمكم.'),
    ('الباص تحرك', 'الباص في الطريق', 'تحرك الباص الآن من أول محطة، استعدوا في محطاتكم.'),
    ('تغيير مكان الركوب', 'تغيير مكان الركوب', 'تغيّر مكان الركوب اليوم، تابعوا تعليمات المشرف.'),
    ('الباص وصل الجامعة', 'وصلنا الجامعة', 'وصل الباص إلى الجامعة. يومكم سعيد!'),
  ];

  @override
  ConsumerState<SendNotificationSheet> createState() => _SendNotificationSheetState();
}

class _SendNotificationSheetState extends ConsumerState<SendNotificationSheet>
    with _Audience<SendNotificationSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _key = _SendKey();
  bool _sending = false;

  @override
  SupervisorDashboard get dashboard => widget.dashboard;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _title.text.trim(), body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      showError('اكتب عنوان الإشعار ونصه.');
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await ref.read(notificationsRepoProvider).send(
            title: title,
            body: body,
            lineId: lineId,
            tripId: trip?.tripId,
            rideDate: rideDate,
            idempotencyKey: _key.of('$lineId|${trip?.tripId}|$rideDate|$title|$body'),
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showError(errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => sheet([
        Text('إشعار جديد للطلاب', style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
        ...audiencePickers(),
        label('رسائل جاهزة'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (chip, title, body) in SendNotificationSheet.templates)
            ActionChip(
              label: Text(chip),
              avatar: const Icon(LucideIcons.megaphone, size: 15, color: BasakUi.teal),
              backgroundColor: BasakUi.softTeal,
              side: BorderSide.none,
              onPressed: () => setState(() {
                _title.text = title;
                _body.text = body;
              }),
            ),
        ]),
        label('العنوان'),
        TextField(
          controller: _title,
          maxLength: 80,
          decoration: _decoration('مثال: تأخير الباص'),
        ),
        label('نص الإشعار'),
        TextField(
          controller: _body,
          maxLength: 600,
          minLines: 3,
          maxLines: 6,
          decoration: _decoration('اكتب ما تريد أن يعرفه الطلاب'),
        ),
        const SizedBox(height: 8),
        sendButton('إرسال الإشعار', sending: _sending, onPressed: _send),
      ]);

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE3EDF3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE3EDF3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BasakUi.teal),
        ),
      );
}

/// Confirms one ready message before it goes out: to which line or trip, how
/// many minutes when the message needs them, and who will receive it. The
/// server writes the final text, checks the line is this supervisor's and
/// limits how often; what it refuses is shown in its own words. Pops with
/// what was sent.
class QuickNotificationSheet extends ConsumerStatefulWidget {
  final SupervisorDashboard dashboard;
  final QuickNotificationTemplate template;

  const QuickNotificationSheet({super.key, required this.dashboard, required this.template});

  /// The delays offered for a message that needs minutes.
  static const minuteChoices = [5, 10, 15, 20, 30, 45];

  @override
  ConsumerState<QuickNotificationSheet> createState() => _QuickNotificationSheetState();
}

class _QuickNotificationSheetState extends ConsumerState<QuickNotificationSheet>
    with _Audience<QuickNotificationSheet> {
  final _key = _SendKey();
  late int? _minutes = widget.template.needsMinutes ? 10 : null;
  bool _sending = false;

  @override
  SupervisorDashboard get dashboard => widget.dashboard;

  @override
  String? get direction => widget.template.direction;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final result = await ref.read(notificationsRepoProvider).sendQuick(
            templateKey: widget.template.key,
            lineId: lineId,
            tripId: trip?.tripId,
            rideDate: rideDate,
            minutes: _minutes,
            idempotencyKey:
                _key.of('${widget.template.key}|$lineId|${trip?.tripId}|$rideDate|$_minutes'),
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showError(errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    return sheet([
      Text(template.title, style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFF7FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE3EDF3))),
        child: Text(template.preview(_minutes),
            style: AppTextStyles.bodyMedium.copyWith(color: BasakUi.ink, height: 1.6)),
      ),
      ...audiencePickers(),
      if (template.needsMinutes) ...[
        label('المدة بالدقائق'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final minutes in QuickNotificationSheet.minuteChoices)
            choice('$minutes', _minutes == minutes, () => setState(() => _minutes = minutes)),
        ]),
      ],
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: BasakUi.softTeal, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(LucideIcons.users, size: 18, color: BasakUi.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text('سيصل إلى: $recipients',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      sendButton('تأكيد الإرسال', sending: _sending, onPressed: _send),
    ]);
  }
}
