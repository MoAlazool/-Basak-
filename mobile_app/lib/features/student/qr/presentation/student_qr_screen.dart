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
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 105),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Text('بطاقة الطالب',
                          style: AppTextStyles.displayMedium
                              .copyWith(color: _ink)),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                          'أظهر الرمز للمشرف للتحقق من اشتراكك وبيانات الرحلة.',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: const Color(0xFF718695))),
                    ),
                    const SizedBox(height: 18),
                    if (pass.isOfflineCache)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'تعرض البطاقة بيانات محفوظة من آخر اتصال. قد لا تشمل أي تغييرات أحدث على الاشتراك.',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: const Color(0xFF8A5A00),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x1117384A),
                                blurRadius: 18,
                                offset: Offset(0, 7))
                          ]),
                      child: Column(children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                  radius: 25,
                                  backgroundColor: const Color(0xFFE4F2F9),
                                  backgroundImage: pass.profileImageUrl == null
                                      ? null
                                      : avatarImage(pass.profileImageUrl!),
                                  child: pass.profileImageUrl == null
                                      ? const Icon(LucideIcons.userRound,
                                          color: _teal)
                                      : null),
                              const SizedBox(width: 11),
                              Flexible(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(pass.fullName ?? 'الطالب',
                                        style: AppTextStyles.titleLarge
                                            .copyWith(color: _ink),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    Text(pass.university ?? 'الجامعة المسجلة',
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                                color: const Color(0xFF718695)))
                                  ])),
                            ]),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: const Color(0xFFE7EEF3))),
                          child: QrImageView(
                            data: pass.qrValue!,
                            version: QrVersions.auto,
                            size:
                                MediaQuery.sizeOf(context).width.clamp(0, 340) -
                                    76,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Color(0xFF102A3A)),
                            dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF102A3A)),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 7),
                            decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFFE7F8F0)
                                    : const Color(0xFFFFF4E5),
                                borderRadius: BorderRadius.circular(18)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                  active
                                      ? LucideIcons.circleCheck
                                      : LucideIcons.clock3,
                                  size: 16,
                                  color: active
                                      ? const Color(0xFF07865A)
                                      : const Color(0xFFB56900)),
                              const SizedBox(width: 6),
                              Text(
                                  active
                                      ? 'الاشتراك نشط'
                                      : pass.subscriptionStatus == 'rejected'
                                          ? 'الإيصال مرفوض'
                                          : 'الاشتراك غير نشط',
                                  style: AppTextStyles.labelSmall.copyWith(
                                      color: active
                                          ? const Color(0xFF07865A)
                                          : const Color(0xFFB56900),
                                      fontWeight: FontWeight.bold))
                            ])),
                        const SizedBox(height: 18),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        _detailRow(
                            'المسار',
                            pass.lineName ?? 'لا يوجد اشتراك',
                            LucideIcons.busFront),
                        const SizedBox(height: 11),
                        _detailRow(
                            'محطة الصعود',
                            pass.stationName ?? '—',
                            LucideIcons.mapPin),
                        if ((pass.college ?? '').isNotEmpty) ...[
                          const SizedBox(height: 11),
                          _detailRow(
                              'الكلية', pass.college!, LucideIcons.school),
                        ],
                        const SizedBox(height: 11),
                        _detailRow(
                            'نوع الاشتراك',
                            _typeLabel(pass.subscriptionType),
                            LucideIcons.ticket),
                        if ((pass.phone ?? '').isNotEmpty) ...[
                          const SizedBox(height: 11),
                          _detailRow(
                              'رقم الهاتف', pass.phone!, LucideIcons.phone),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 13),
                    if (AddToWalletButton.canOffer(
                        pass,
                        WalletPassRepository.platformFor(
                            defaultTargetPlatform))) ...[
                      AddToWalletButton(pass: pass),
                      const SizedBox(height: 13),
                    ],
                    Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FA),
                            borderRadius: BorderRadius.circular(16)),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(LucideIcons.info,
                                  color: _teal, size: 19),
                              const SizedBox(width: 9),
                              Expanded(
                                  child: Text(
                                      'رمز QR للتعريف والتحقق فقط. مسحه لا يسجل الحضور تلقائياً؛ أكد رحلتك من الصفحة الرئيسية.',
                                      style: AppTextStyles.labelSmall.copyWith(
                                          color: const Color(0xFF315F75),
                                          height: 1.5)))
                            ])),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

  /// The value takes the rest of the row and wraps, so a long route shows whole.
  static Widget _detailRow(String label, String value, IconData icon) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: _teal),
        ),
        const SizedBox(width: 9),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: const Color(0xFF718695))),
        ),
        const SizedBox(width: 14),
        Expanded(
            child: Text(value,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: _ink, fontWeight: FontWeight.w600),
                textAlign: TextAlign.end))
      ]);

  static String _typeLabel(String? type) => switch (type) {
        'yearly' => 'سنوي',
        'termly' => 'فصلي',
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
