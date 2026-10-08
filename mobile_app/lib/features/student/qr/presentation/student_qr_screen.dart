import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/sync/session.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../wallet/data/wallet_pass_repository.dart';
import '../../wallet/presentation/add_to_wallet_button.dart';
import '../data/student_qr_repository.dart';
import '../../subscription/models/subscription_model.dart';

final studentQrRepoProvider = Provider((ref) => StudentQrRepository());
final studentQrProvider = FutureProvider<StudentPassDetails?>((ref) async {
  ref.watch(sessionUserIdProvider);
  return ref.watch(studentQrRepoProvider).getStudentPassDetails();
});

class StudentQrScreen extends ConsumerWidget {
  const StudentQrScreen({super.key});

  static const _ink = Color(0xFF17384A);
  static const _teal = Color(0xFF00658D);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passAsync = ref.watch(studentQrProvider);

    return GlassScaffold(
      canvas: const Color(0xFFEAF5FA),
      body: ColoredBox(
        color: const Color(0xFFEAF5FA),
        child: SafeArea(
          child: RefreshIndicator(
            color: _teal,
            onRefresh: () async {
              ref.invalidate(studentQrProvider);
              try {
                await ref.read(studentQrProvider.future);
              } catch (_) {}
            },
            child: passAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: _message('تعذر تحميل بطاقة الطالب',
                      errorMessage(error), () => ref.invalidate(studentQrProvider)),
                ),
              ),
              data: (pass) {
                if (pass == null || (pass.qrValue ?? '').isEmpty) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: _message(
                          'البطاقة غير متاحة حالياً',
                          'سجل دخولك مرة أخرى أو تواصل مع إدارة الجامعة.',
                          () => ref.invalidate(studentQrProvider)),
                    ),
                  );
                }
                final active = pass.subscriptionStatus == 'active';
                // A fixed page that fills the screen down to the navigation
                // bar: nothing scrolls, and the QR code takes whatever height
                // is left, so it is as large as the phone allows.
                return LayoutBuilder(builder: (context, box) {
                  // Short screens drop the two lines of help to keep the code large.
                  final compact = box.maxHeight < 640;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                    child: Column(children: [
                      SizedBox(
                        width: double.infinity,
                        child: Text('بطاقة الطالب',
                            style: AppTextStyles.displayMedium.copyWith(color: _ink)),
                      ),
                      if (!compact)
                        SizedBox(
                          width: double.infinity,
                          child: Text('أظهر الرمز للمشرف عند الصعود.',
                              style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF718695))),
                        ),
                      const SizedBox(height: 10),
                      if (pass.isOfflineCache)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(14)),
                          child: Text('بيانات محفوظة من آخر اتصال.',
                              style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF8A5A00)),
                              textAlign: TextAlign.center),
                        ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: const [
                                BoxShadow(color: Color(0x1117384A), blurRadius: 18, offset: Offset(0, 7))
                              ]),
                          // Everything on the card grows and shrinks together: the
                          // design is drawn for a card 500 high and scaled to the
                          // height this phone gives it, so the code keeps its
                          // proportion to the name, the status and the details.
                          child: LayoutBuilder(builder: (context, card) {
                            final rows = compact ? 3 : 4;
                            final k = (card.maxHeight / (410 + rows * 28)).clamp(0.72, 1.22);
                            final qrSide = (230 * k).clamp(150.0, card.maxWidth);
                            return MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                  textScaler: TextScaler.linear(
                                      (MediaQuery.textScalerOf(context).scale(1) * k).clamp(0.8, 1.3))),
                              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  CircleAvatar(
                                      radius: 24 * k,
                                      backgroundColor: const Color(0xFFE4F2F9),
                                      backgroundImage:
                                          pass.profileImageUrl == null ? null : avatarImage(pass.profileImageUrl!),
                                      child: pass.profileImageUrl == null
                                          ? Icon(LucideIcons.userRound, color: _teal, size: 24 * k)
                                          : null),
                                  SizedBox(width: 11 * k),
                                  Flexible(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(pass.fullName ?? 'الطالب',
                                        style: AppTextStyles.titleLarge.copyWith(color: _ink),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(pass.university ?? 'الجامعة المسجلة',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF718695)))
                                  ])),
                                ]),
                                Container(
                                  width: qrSide,
                                  height: qrSide,
                                  padding: EdgeInsets.all(11 * k),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: const Color(0xFFE7EEF3))),
                                  child: QrImageView(
                                    key: const Key('student-qr'),
                                    data: pass.qrValue!,
                                    version: QrVersions.auto,
                                    padding: EdgeInsets.zero,
                                    backgroundColor: Colors.white,
                                    eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square, color: Color(0xFF102A3A)),
                                    dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape: QrDataModuleShape.square, color: Color(0xFF102A3A)),
                                  ),
                                ),
                                Container(
                                    padding: EdgeInsets.symmetric(horizontal: 13 * k, vertical: 6 * k),
                                    decoration: BoxDecoration(
                                        color: active ? const Color(0xFFE7F8F0) : const Color(0xFFFFF4E5),
                                        borderRadius: BorderRadius.circular(18)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(active ? LucideIcons.circleCheck : LucideIcons.clock3,
                                          size: 16 * k,
                                          color: active ? const Color(0xFF07865A) : const Color(0xFFB56900)),
                                      const SizedBox(width: 6),
                                      Text(
                                          active
                                              ? 'الاشتراك نشط'
                                              : pass.subscriptionStatus == 'rejected'
                                                  ? 'الإيصال مرفوض'
                                                  : 'الاشتراك غير نشط',
                                          style: AppTextStyles.labelSmall.copyWith(
                                              color: active ? const Color(0xFF07865A) : const Color(0xFFB56900),
                                              fontWeight: FontWeight.bold))
                                    ])),
                                Column(mainAxisSize: MainAxisSize.min, children: [
                                  const Divider(height: 1),
                                  SizedBox(height: 10 * k),
                                  _detailRow(
                                      'الخط',
                                      pass.lineName == null
                                          ? 'لا يوجد اشتراك'
                                          : SubscriptionModel.routeLabel(pass.lineName, pass.university),
                                      LucideIcons.busFront, k),
                                  SizedBox(height: 7 * k),
                                  _detailRow('محطة الصعود', pass.stationName ?? '—', LucideIcons.mapPin, k),
                                  SizedBox(height: 7 * k),
                                  _detailRow('نوع الاشتراك', _typeLabel(pass.subscriptionType), LucideIcons.ticket, k),
                                  if ((pass.phone ?? '').isNotEmpty && !compact) ...[
                                    SizedBox(height: 7 * k),
                                    _detailRow('رقم الهاتف', pass.phone!, LucideIcons.phone, k),
                                  ],
                                ]),
                              ]),
                            );
                          }),
                        ),
                      ),
                      if (AddToWalletButton.canOffer(
                          pass, WalletPassRepository.platformFor(defaultTargetPlatform))) ...[
                        const SizedBox(height: 10),
                        AddToWalletButton(pass: pass),
                      ],
                      if (!compact) ...[
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(LucideIcons.info, color: _teal, size: 15),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('الرمز للتحقق فقط. أكّد رحلتك من الصفحة الرئيسية.',
                                style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF315F75))),
                          ),
                        ]),
                      ],
                    ]),
                  );
                });
            },
          ),
        ),
      ),
    ),
  );
}

  /// The value sits right beside its label and wraps when it is long.
  static Widget _detailRow(String label, String value, IconData icon, [double k = 1]) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(icon, size: 16, color: _teal),
        ),
        const SizedBox(width: 8),
        SizedBox(
          // Wide enough for the longest label at the card's scale.
          width: 100 * k,
          child: Text(label,
              maxLines: 1,
              style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF718695), height: 1.6)),
        ),
        Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // A phone number reads left to right but stays beside its label.
                textAlign: TextAlign.right,
                textDirection: RegExp(r'^[0-9+ ]+$').hasMatch(value) ? TextDirection.ltr : null,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: _ink, fontWeight: FontWeight.w600, height: 1.45)))
      ]);

  static String _typeLabel(String? type) => switch (type) {
        'yearly' => 'الفصلان معاً',
        'termly' => 'فصل دراسي',
        'daily' => 'يومي نقدي',
        _ => '—',
      };

  static Widget _message(String title, String message, VoidCallback retry) =>
      Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(LucideIcons.badgeHelp, color: _teal, size: 36),
                const SizedBox(height: 12),
                Text(title,
                    style: AppTextStyles.titleLarge.copyWith(color: _ink)),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium),
                TextButton.icon(
                    onPressed: retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'))
              ])));
}
