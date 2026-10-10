import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:basak_mobile/core/ui/ui.dart';

import 'onboarding_art.dart';
import 'onboarding_controller.dart';

/// What each page says, under its picture.
const onboardingPages = <({String title, String body})>[
  (
    title: 'كل شركات النقل في مكان واحد',
    body: 'قارن الخطوط والأسعار والمواعيد لجامعتك، واختر ما يناسبك.',
  ),
  (
    title: 'اشترك وادفع من هاتفك',
    body: 'اختر الخط والمحطة، حوّل المبلغ، وارفع الإيصال. بلا طوابير.',
  ),
  (
    title: 'أكّد رحلتك، وتابع كل جديد',
    body: 'تأكيدك يحجز مكانك، والمشرف يبلّغك بأي تأخير أو تغيير.',
  ),
  (
    title: 'بطاقتك دائماً معك',
    body: 'رمز الصعود يعمل حتى بدون إنترنت، ويُضاف إلى محفظة هاتفك.',
  ),
];

/// First-launch onboarding. Shown once per device (see [OnboardingController]),
/// before sign-in, so it works for every role.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// A session restored from a previous install/version: the last page then
  /// only offers "ابدأ الآن" instead of creating an account or signing in.
  final bool isSignedIn;

  const OnboardingScreen({super.key, this.isSignedIn = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  bool get _isLast => _index == onboardingPages.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _pages.nextPage(duration: BasakMotion.page, curve: BasakMotion.pageCurve);

  void _finish({bool signup = false, bool signIn = false}) =>
      ref.read(onboardingProvider.notifier).complete(openSignup: signup, openSignIn: signIn);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: basakMaxTextScale,
      child: Scaffold(
        backgroundColor: colors.ground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: onboardingPages.length,
                      onPageChanged: (index) => setState(() => _index = index),
                      itemBuilder: (context, index) {
                        final page = onboardingPages[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    BasakSpace.s12, BasakSpace.s12, BasakSpace.s12, 0),
                                child: OnboardingArt(page: index),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  BasakSpace.s24, BasakSpace.s24, BasakSpace.s24, 0),
                              // Room for two lines of each on every page, so the picture
                              // above keeps one size from page to page.
                              child: Stack(
                                children: [
                                  ExcludeSemantics(
                                    child: Opacity(
                                      opacity: 0,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('\n', style: text.display),
                                          const SizedBox(height: BasakSpace.s8),
                                          Text('\n', style: text.rowTitle),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(header: true, child: Text(page.title, style: text.display)),
                                      const SizedBox(height: BasakSpace.s8),
                                      Text(page.body,
                                          style:
                                              text.rowTitle.copyWith(fontWeight: FontWeight.w400, color: colors.ink2)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        BasakSpace.s24, BasakSpace.s18, BasakSpace.s24, BasakSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Dots(count: onboardingPages.length, index: _index),
                        const SizedBox(height: BasakSpace.s18),
                        if (!_isLast) ...[
                          BasakButton(key: const ValueKey('next'), label: 'التالي', onPressed: _next),
                          const SizedBox(height: BasakSpace.s2),
                          EntryLink(label: 'تخطي', tone: EntryLinkTone.quiet, onTap: _finish),
                        ] else if (widget.isSignedIn) ...[
                          BasakButton(key: const ValueKey('final'), label: 'ابدأ الآن', onPressed: _finish),
                          const SizedBox(height: BasakSpace.s2),
                          const SizedBox(height: BasakSpace.tapTarget),
                        ] else ...[
                          BasakButton(
                            key: const ValueKey('final'),
                            label: 'إنشاء حساب',
                            onPressed: () => _finish(signup: true),
                          ),
                          const SizedBox(height: BasakSpace.s2),
                          EntryLink(
                            label: 'لديّ حساب',
                            tone: EntryLinkTone.quiet,
                            onTap: () => _finish(signIn: true),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the pager stands: a teal dash for the page on screen.
class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'الصفحة ${index + 1} من $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: BasakSpace.s6),
            AnimatedContainer(
              duration: BasakMotion.fade,
              width: i == index ? 24 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? colors.teal : colors.grabber,
                borderRadius: BasakRadius.all(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
