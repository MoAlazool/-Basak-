import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../media/company_brand.dart';
import 'tokens.dart';

/// Stands in for the network picture where there is no image cache (tests).
@visibleForTesting
ImageProvider? Function(String url)? debugCompanyLogoImage;

/// A company picture by its address. The address never changes what it shows
/// (see [CompanyBrand]), so the disk cache keeps it under the address itself,
/// for good: seen once, it shows offline.
ImageProvider companyLogoImage(String url) => debugCompanyLogoImage?.call(url) ?? CachedNetworkImageProvider(url);

/// A transport company's mark in a fixed box: its emblem, or its logo centred
/// on a square where it has no emblem, or (nothing added yet, still loading,
/// offline with nothing saved, a broken file, a path the app does not trust)
/// the company's initials on the teal tint. The initials are drawn first and
/// the picture fades in over them, so the box is never empty, never changes
/// size and never waits for the network.
///
/// The pictures may be transparent: they are shown whole on white, inside a
/// hairline.
///
///   * [CompanyLogo.new] takes the company's name and its [CompanyBrand] (the
///     two paths the server sends) and picks the file for its [size];
///   * [CompanyLogo.image] takes a picture that is already in hand.
class CompanyLogo extends StatelessWidget {
  /// The company's name: its initials stand in for a missing logo, and it is
  /// what a screen reader says.
  final String name;

  /// Null: the initials.
  final ImageProvider? image;
  final double size;

  /// The corners of the box. Null: a disc.
  final double? radius;

  /// What stands in for a missing picture instead of the initials (the bus
  /// glyph of a pass's stub). It fills the box itself.
  final Widget? placeholder;

  CompanyLogo({
    super.key,
    required this.name,
    CompanyBrand brand = CompanyBrand.none,
    this.size = 40,
    this.radius,
    this.placeholder,
  }) : image = _markOf(brand, size);

  const CompanyLogo.image({super.key, required this.name, this.image, this.size = 40, this.radius, this.placeholder});

  static ImageProvider? _markOf(CompanyBrand brand, double size) {
    final url = brand.markUrl(size);
    return url == null ? null : companyLogoImage(url);
  }

  /// Words that open most company names and say nothing about which one it is.
  static const _fillers = {'شركة', 'مؤسسة', 'مكتب', 'مجموعة'};

  /// Up to two letters: the first of each of the name's first two telling
  /// words («شركة النورس للنقل» → «ن ل», «Delta Bus» → «DB»).
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    final telling = words.where((word) => !_fillers.contains(word)).toList();
    final from = telling.isEmpty ? words : telling;
    String first(String word) {
      // The article is not the letter a name is known by.
      final bare = word.startsWith('ال') && word.characters.length > 2 ? word.substring(2) : word;
      return bare.characters.first.toUpperCase();
    }

    return from.take(2).map(first).join(_arabic(name) ? ' ' : '');
  }

  // Arabic letters would join into one shape side by side; a space keeps them apart.
  static bool _arabic(String text) => RegExp(r'[؀-ۿ]').hasMatch(text);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initials = initialsOf(name);
    final corners = radius == null ? null : BasakRadius.all(radius!);
    final shape = radius == null ? BoxShape.circle : BoxShape.rectangle;
    final fallback = placeholder ??
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.tealTint, shape: shape, borderRadius: corners),
          child: Text(
            initials,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: context.text.rowTitle.copyWith(color: colors.teal, fontSize: size * .34, height: 1.2),
          ),
        );
    final logo = image;
    return Semantics(
      image: true,
      label: name.trim().isEmpty ? 'شعار الشركة' : 'شعار ${name.trim()}',
      child: ExcludeSemantics(
        // One box whatever is in it: nothing around it moves when the picture arrives.
        child: SizedBox.square(
          dimension: size,
          child: logo == null
              ? fallback
              : Image(
                  image: logo,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  // The initials until the first frame is there, then the picture over them.
                  frameBuilder: (context, child, frame, immediate) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!immediate) fallback,
                      AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: immediate ? Duration.zero : BasakMotion.fade,
                        curve: BasakMotion.fadeCurve,
                        child: Container(
                          key: const Key('company-logo-image'),
                          clipBehavior: Clip.antiAlias,
                          padding: EdgeInsetsDirectional.all(size * (radius == null ? .14 : .08)),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: shape,
                            borderRadius: corners,
                            border: Border.all(color: colors.hairline),
                          ),
                          child: child,
                        ),
                      ),
                    ],
                  ),
                  errorBuilder: (context, error, stack) => fallback,
                ),
        ),
      ),
    );
  }
}
