import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import '../../../../core/media/signed_photo.dart';
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
final FutureProvider<StudentPassDetails?> studentQrProvider = FutureProvider<StudentPassDetails?>((ref) async {
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
              // Only when the card has never been loaded on this phone.
              loading: () => const StudentCardSkeleton(),
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
                final photo = studentPhoto(pass.profileImagePath);
                final photoUrl = photo == null ? null : ref.watch(signedPhotoProvider(photo)).valueOrNull;
                // A fixed page, laid out as before: the card hugs its content
                // with even, tight spacing; the wallet button and the note sit
                // at the bottom, just above the navigation bar. The QR code is
                // as large as the card's width allows, and only shrinks when
                // the phone is too short to show everything.
                return LayoutBuilder(builder: (context, box) {
                  final compact = box.maxHeight < 620;
                  final wallet = AddToWalletButton.canOffer(
                      pass, WalletPassRepository.platformFor(defaultTargetPlatform));
                  final showPhone = (pass.phone ?? '').isNotEmpty && !compact;
                  // Height of everything except the QR itself.
                  final fixed = 24 + (compact ? 46 : 78) + (pass.isOfflineCache ? 44 : 0) +
                      32 + 52 + 14 + 22 + 12 + 30 + 14 + 11 +
                      (showPhone ? 4 : 3) * 22 + (showPhone ? 3 : 2) * 9 +
                      (wallet ? 66 : 0) + (compact ? 0 : 34);
                  final qrSide = (box.maxHeight - fixed)
                      .clamp(150.0, (box.maxWidth - 36 - 36 - 22).clamp(150.0, 280.0));
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      // Title and its line: same right edge as the card, with air between them.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('بطاقة الطالب',
                            textAlign: TextAlign.start,
                            style: AppTextStyles.displayMedium.copyWith(color: _ink, height: 1.25)),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('أظهر الرمز للمشرف عند الصعود.',
                              textAlign: TextAlign.start,
                              style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF718695), height: 1.4)),
                        ),
                      ],
                      const SizedBox(height: 14),
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
                      // The card takes what it needs, and the wallet button follows
                      // right under it; anything left stays at the bottom.
                      Flexible(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: 1,
                          // A last resort on very small screens: never overflow.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: box.maxWidth - 36,
                              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x1117384A), blurRadius: 18, offset: Offset(0, 7))
                                  ]),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  CircleAvatar(
                                      radius: 25,
                                      backgroundColor: const Color(0xFFE4F2F9),
                                      backgroundImage: photoUrl == null ? null : avatarImage(photoUrl),
                                      child: photoUrl == null
                                          ? const Icon(LucideIcons.userRound, color: _teal)
                                          : null),
                                  const SizedBox(width: 11),
                                  Flexible(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(pass.fullName ?? 'الطالب',
                                        style: AppTextStyles.titleLarge.copyWith(color: _ink, height: 1.25),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(pass.university ?? 'الجامعة المسجلة',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF718695)))
                                  ])),
                                ]),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: const Color(0xFFE7EEF3))),
                                  child: QrImageView(
                                    key: const Key('student-qr'),
                                    data: pass.qrValue!,
                                    version: QrVersions.auto,
                                    size: qrSide,
                                    padding: EdgeInsets.zero,
                                    backgroundColor: Colors.white,
                                    eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square, color: Color(0xFF102A3A)),
                                    dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape: QrDataModuleShape.square, color: Color(0xFF102A3A)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: active ? const Color(0xFFE7F8F0) : const Color(0xFFFFF4E5),
                                        borderRadius: BorderRadius.circular(18)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(active ? LucideIcons.circleCheck : LucideIcons.clock3,
                                          size: 16,
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
                                const SizedBox(height: 14),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                _detailRow(
                                    'الخط',
                                    pass.lineName == null
                                        ? 'لا يوجد اشتراك'
                                        : SubscriptionModel.routeLabel(pass.lineName, pass.university),
                                    LucideIcons.busFront),
                                const SizedBox(height: 9),
                                _detailRow('محطة الصعود', pass.stationName ?? '—', LucideIcons.mapPin),
                                const SizedBox(height: 9),
                                _detailRow('نوع الاشتراك', _typeLabel(pass.subscriptionType), LucideIcons.ticket),
                                if (showPhone) ...[
                                  const SizedBox(height: 9),
                                  _detailRow('رقم الهاتف', pass.phone!, LucideIcons.phone),
                                ],
                              ]),
                            ),
                          ),
                        ),
                      ),
                      if (wallet) ...[
                        const SizedBox(height: 12),
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
