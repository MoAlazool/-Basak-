import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// GlassScaffold provides subtle background color blooms / gradients
/// so that frosted glass containers over it achieve genuine optical refraction and depth.
class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool extendBody;

  /// The page's own background colour. When given, it fills the whole screen,
  /// including behind the status bar, so the top of the page is one colour
  /// with the rest instead of a separate strip.
  final Color? canvas;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBody = true, // Allows bottom navigation bar to float with glass blur over content
    this.canvas,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: canvas ?? AppColors.background,
      extendBody: extendBody,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Stack(
        // The page fills the screen even when its content is shorter.
        fit: StackFit.expand,
        children: [
          // Ambient blurred decorative shapes in background (pages with their
          // own canvas colour cover them, so they are not drawn there).
          if (canvas == null) ...[
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.babyBlueLight.withOpacity(0.45),
                    AppColors.babyBlueUltraLight.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: size.height * 0.15,
            right: -50,
            child: Container(
              width: size.width * 0.8,
              height: size.width * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.babyBlue.withOpacity(0.28),
                    AppColors.babyBlueUltraLight.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: size.height * 0.45,
            left: -30,
            child: Container(
              width: size.width * 0.5,
              height: size.width * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFBAE6FD).withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          ],

          // Main Screen Content
          SafeArea(
            bottom: !extendBody,
            child: body,
          ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
