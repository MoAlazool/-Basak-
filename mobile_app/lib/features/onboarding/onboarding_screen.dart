import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/basak_ui.dart';
import 'onboarding_controller.dart';

class _Slide {
  final String title;
  final String body;
  final IconData icon;
  final List<IconData> satellites;
  final Color accent;
  final bool showLogo;

  const _Slide({
    required this.title,
    required this.body,
    required this.icon,
    required this.satellites,
    required this.accent,
    this.showLogo = false,
  });
}

const _slides = [
  _Slide(
    title: 'أهلاً بك في باصك',
    body: 'رحلتك اليومية للجامعة أسهل وأوضح: اشتراكك ومواعيدك وبطاقة صعودك في تطبيق واحد.',
    icon: LucideIcons.busFront,
    satellites: [LucideIcons.mapPin, LucideIcons.graduationCap, LucideIcons.shieldCheck],
    accent: BasakUi.teal,
    showLogo: true,
  ),
  _Slide(
    title: 'اشترك في خطك بسهولة',
    body: 'اختر خطك ومحطتك، ارفع إيصال الدفع، وتابع حالة اشتراكك لحظة بلحظة.',
    icon: LucideIcons.creditCard,
    satellites: [LucideIcons.receipt, LucideIcons.circleCheck, LucideIcons.route],
    accent: Color(0xFF4F46E5),
  ),
  _Slide(
    title: 'مواعيد جامعتك أنت',
    body: 'يعرض لك التطبيق موعد رحلة جامعتك فقط، وتؤكد ركوبك كل يوم بضغطة واحدة.',
    icon: LucideIcons.clock3,
    satellites: [LucideIcons.graduationCap, LucideIcons.calendarCheck2, LucideIcons.bell],
    accent: Color(0xFF07865A),
  ),
  _Slide(
    title: 'بطاقة صعود ذكية',
    body: 'اعرض رمز QR للمشرف عند الصعود، ويتابع المشرفون الركاب والحضور من نفس التطبيق.',
    icon: LucideIcons.qrCode,
    satellites: [LucideIcons.scanLine, LucideIcons.userCheck, LucideIcons.chartColumn],
    accent: Color(0xFFB97812),
  ),
];

/// First-launch onboarding. Shown once per device (see [OnboardingController]),
/// before login, so it works for every role.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// A session restored from a previous install/version: the last page then
  /// only offers "Get started" instead of login / registration.
  final bool isSignedIn;

  const OnboardingScreen({super.key, this.isSignedIn = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  double _page = 0;

  bool get _isLast => _page.round() == _slides.length - 1;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() => setState(() => _page = _pageController.page ?? 0));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _float.dispose();
    super.dispose();
  }

  void _next() => _pageController.nextPage(
      duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);

  void _finish({bool signup = false}) =>
      ref.read(onboardingProvider.notifier).complete(openSignup: signup);

  @override
  Widget build(BuildContext context) {
    final accent = Color.lerp(
      _slides[_page.floor().clamp(0, _slides.length - 1)].accent,
      _slides[_page.ceil().clamp(0, _slides.length - 1)].accent,
      _page - _page.floor(),
    )!;

    return Scaffold(
      backgroundColor: BasakUi.canvas,
      body: Stack(
        children: [
          // Soft ambient blooms that drift with the page.
          Positioned(
            top: -120 + _page * 18,
            right: -80 - _page * 22,
            child: _bloom(320, accent.withOpacity(.20)),
          ),
          Positioned(
            bottom: -140,
            left: -90 + _page * 26,
            child: _bloom(360, const Color(0xFF7EC8E3).withOpacity(.28)),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar: brand + skip
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(children: [
                    ClipOval(
                      child: Image.asset('assets/images/basak_icon.png', width: 32, height: 32),
                    ),
                    const SizedBox(width: 8),
                    Text('باصك', style: AppTextStyles.titleMedium.copyWith(color: BasakUi.ink)),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isLast ? 0 : 1,
                      child: TextButton(
                        onPressed: _isLast ? null : () => _finish(),
                        child: Text('تخطي',
                            style: AppTextStyles.bodyLarge
                                .copyWith(color: BasakUi.muted, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    itemBuilder: (context, index) => _slideView(_slides[index], index),
                  ),
                ),
                _dots(accent),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isLast ? _finalActions() : _nextButton(accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloom(double size, Color color) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
          ),
        ),
      );

  Widget _slideView(_Slide slide, int index) {
    // -1..1 distance of this page from the viewport centre, for parallax.
    final delta = (index - _page).clamp(-1.0, 1.0);
    return LayoutBuilder(builder: (context, constraints) {
      final art = math.min(constraints.maxWidth * .78, constraints.maxHeight * .58);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(delta * 60, 0),
              child: Opacity(
                opacity: (1 - delta.abs()).clamp(0.0, 1.0),
                child: SizedBox(width: art, height: art, child: _illustration(slide, art)),
              ),
            ),
            SizedBox(height: constraints.maxHeight * .05),
            Transform.translate(
              offset: Offset(delta * 30, 0),
              child: Column(children: [
                Text(slide.title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayMedium.copyWith(color: BasakUi.ink, fontSize: 26)),
                const SizedBox(height: 10),
                Text(slide.body,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge.copyWith(color: BasakUi.muted, height: 1.6)),
              ]),
            ),
          ],
        ),
      );
    });
  }

  Widget _illustration(_Slide slide, double size) => AnimatedBuilder(
        animation: _float,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_float.value);
          final centre = size * .44;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Concentric rings
              for (final scale in const [1.0, .78])
                Container(
                  width: size * scale,
                  height: size * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(scale == 1 ? .45 : .7),
                    border: Border.all(color: Colors.white),
                  ),
                ),
              // Hero mark
              Transform.translate(
                offset: Offset(0, -6 + 12 * t),
                child: slide.showLogo
                    ? Container(
                        width: centre,
                        height: centre,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: slide.accent.withOpacity(.28),
                                blurRadius: 30,
                                offset: const Offset(0, 14)),
                          ],
                        ),
                        child: ClipOval(child: Image.asset('assets/images/basak_icon.png')),
                      )
                    : Container(
                        width: centre,
                        height: centre,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color.lerp(slide.accent, Colors.white, .25)!, slide.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: slide.accent.withOpacity(.30),
                                blurRadius: 30,
                                offset: const Offset(0, 14)),
                          ],
                        ),
                        child: Icon(slide.icon, color: Colors.white, size: centre * .42),
                      ),
              ),
              // Orbiting satellite chips
              for (var i = 0; i < slide.satellites.length; i++)
                Transform.translate(
                  offset: Offset.fromDirection(
                    -math.pi / 2 + i * (2 * math.pi / slide.satellites.length) + t * .18,
                    size * .40,
                  ),
                  child: Container(
                    width: size * .17,
                    height: size * .17,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Color(0x1416384A), blurRadius: 16, offset: Offset(0, 6))
                      ],
                    ),
                    child: Icon(slide.satellites[i], color: slide.accent, size: size * .075),
                  ),
                ),
            ],
          );
        },
      );

  Widget _dots(Color accent) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_slides.length, (i) {
          final active = (1 - (i - _page).abs()).clamp(0.0, 1.0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8 + 18 * active,
            height: 8,
            decoration: BoxDecoration(
              color: Color.lerp(const Color(0xFFC9DCE5), accent, active),
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }),
      );

  ButtonStyle _primary(Color color) => ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: AppTextStyles.titleMedium,
      );

  Widget _nextButton(Color accent) => ElevatedButton.icon(
        key: const ValueKey('next'),
        style: _primary(accent),
        onPressed: _next,
        icon: const Icon(LucideIcons.arrowLeft, size: 20),
        label: const Text('التالي'),
      );

  Widget _finalActions() => Column(
        key: const ValueKey('final'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            style: _primary(BasakUi.teal),
            onPressed: () => _finish(),
            icon: const Icon(LucideIcons.logIn, size: 20),
            label: Text(widget.isSignedIn ? 'ابدأ الآن' : 'ابدأ الآن — تسجيل الدخول'),
          ),
          if (!widget.isSignedIn) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: BasakUi.teal,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: BasakUi.teal, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: AppTextStyles.titleMedium,
              ),
              onPressed: () => _finish(signup: true),
              icon: const Icon(LucideIcons.userPlus, size: 20),
              label: const Text('إنشاء حساب طالب جديد'),
            ),
          ],
        ],
      );
}
