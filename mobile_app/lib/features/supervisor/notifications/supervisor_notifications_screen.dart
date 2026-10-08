import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/basak_ui.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../data/supervisor_repository.dart';
import '../models/supervisor_models.dart';

/// The supervisor's notifications: what the company sent to the students of
/// their lines, what they sent themselves, and a card to write to the students.
class SupervisorNotificationsScreen extends StatelessWidget {
  const SupervisorNotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SupervisorNotificationsScreen()));

  @override
  Widget build(BuildContext context) => const NotificationsPage(header: _SendCard());
}

class _SendCard extends ConsumerWidget {
  const _SendCard();

  Future<void> _compose(BuildContext context, WidgetRef ref, SupervisorDashboard dashboard) async {
    final students = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SendNotificationSheet(dashboard: dashboard),
    );
    if (students == null || !context.mounted) return;
    ref.invalidate(myNotificationsProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تم إرسال الإشعار إلى $students طالب.'),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
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

/// A trip the supervisor can write to: its riders on [rideDate].
typedef _TripChoice = ({String tripId, DateTime rideDate});

/// Writes a notification to a line's students, or to the riders of one of
/// its trips today or on the next ride day. Pops with how many receive it.
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

class _SendNotificationSheetState extends ConsumerState<SendNotificationSheet> {
  late String _lineId = widget.dashboard.lines.first.id;
  _TripChoice? _trip;
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  List<SupervisorTripTime> get _trips => widget.dashboard.tripTimes
      .where((t) => t.lineId == _lineId && t.tripId != null && t.students > 0)
      .toList();

  String _tripLabel(SupervisorTripTime t) {
    final today = widget.dashboard.today;
    final isToday = t.rideDate.year == today.year &&
        t.rideDate.month == today.month &&
        t.rideDate.day == today.day;
    return '${isToday ? 'اليوم' : 'غداً'} · ${t.isReturn ? 'عودة' : 'ذهاب'} '
        '${BasakUi.time12(t.time)} · ${t.students} طالب';
  }

  Future<void> _send() async {
    final title = _title.text.trim(), body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _message('اكتب عنوان الإشعار ونصه.');
      return;
    }
    setState(() => _sending = true);
    try {
      final trip = _trip;
      final students = await ref.read(notificationsRepoProvider).send(
            title: title,
            body: body,
            lineId: _lineId,
            tripId: trip?.tripId,
            rideDate: trip?.rideDate.toIso8601String().substring(0, 10),
          );
      if (mounted) Navigator.of(context).pop(students);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      _message(errorMessage(error));
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));

  @override
  Widget build(BuildContext context) {
    final lines = widget.dashboard.lines;
    return Padding(
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
            Text('إشعار جديد للطلاب',
                style: AppTextStyles.titleLarge.copyWith(color: BasakUi.ink)),
            if (lines.length > 1) ...[
              _label('الخط'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final line in lines)
                  _choice(line.name, line.id == _lineId,
                      () => setState(() {
                            _lineId = line.id;
                            _trip = null;
                          })),
              ]),
            ],
            _label('يصل إلى'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _choice('كل طلاب الخط', _trip == null, () => setState(() => _trip = null)),
              for (final t in _trips)
                _choice(
                  _tripLabel(t),
                  _trip?.tripId == t.tripId && _trip?.rideDate == t.rideDate,
                  () => setState(() => _trip = (tripId: t.tripId!, rideDate: t.rideDate)),
                ),
            ]),
            _label('رسائل جاهزة'),
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
            _label('العنوان'),
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: _decoration('مثال: تأخير الباص'),
            ),
            _label('نص الإشعار'),
            TextField(
              controller: _body,
              maxLength: 600,
              minLines: 3,
              maxLines: 6,
              decoration: _decoration('اكتب ما تريد أن يعرفه الطلاب'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.send, size: 18),
                label: const Text('إرسال الإشعار'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BasakUi.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text,
            style: AppTextStyles.bodyMedium
                .copyWith(color: BasakUi.ink, fontWeight: FontWeight.w700)),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
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
