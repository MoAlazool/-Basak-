import 'package:flutter/foundation.dart';

import '../constants/supabase_config.dart';

/// A transport company's branding as the server hands it out: two folders in
/// the public `wallet-assets` bucket. The app only reads them.
///
///   * [logoPath]: the full logo. `master.png` is the logo as uploaded (long
///     side up to 1024), `google.png` is the same logo centred on a
///     transparent 660 square.
///   * [emblemPath]: the square mark. `small.png` is 128 × 128, `master.png`
///     is 512 × 512.
///
/// Every upload is a new folder and a file is never overwritten, so an
/// address stands for one picture for good: it is cached under itself, with
/// no query string, and a logo seen once shows offline.
///
/// Either folder may be null, and on an older server the field may not be
/// there at all: both read as "no picture", and the company's initial stands
/// in (see `CompanyLogo`).
@immutable
class CompanyBrand {
  final String? logoPath;
  final String? emblemPath;

  const CompanyBrand({this.logoPath, this.emblemPath});

  static const none = CompanyBrand();

  /// From a company as the server sends it (`{logo_path, emblem_path, …}`),
  /// or from anything else (a suspended company embeds as null): [none].
  factory CompanyBrand.fromJson(Object? json) {
    if (json is! Map) return none;
    String? path(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return CompanyBrand(logoPath: path('logo_path'), emblemPath: path('emblem_path'));
  }

  static const bucket = 'wallet-assets';

  /// The largest box, in points, the 128-pixel mark is drawn in.
  static const smallBox = 64.0;

  /// A folder as the server names it: the company's id, what it holds, and
  /// the upload. Nothing else is ever put into an address.
  static final _folder = RegExp(r'^[0-9a-f-]{36}/(logo|emblem)/[A-Za-z0-9_-]{1,64}$');

  static bool isValidPath(String? path) => path != null && _folder.hasMatch(path);

  static String _url(String folder, String file, String? base) =>
      '${base ?? SupabaseConfig.supabaseUrl}/storage/v1/object/public/$bucket/$folder/$file';

  /// The square mark for a box [size] points wide: the emblem (the small file
  /// up to [smallBox], the large one above it), else the logo on its square,
  /// else null: the initial.
  String? markUrl(double size, {String? base}) {
    if (isValidPath(emblemPath)) return _url(emblemPath!, size <= smallBox ? 'small.png' : 'master.png', base);
    if (isValidPath(logoPath)) return _url(logoPath!, 'google.png', base);
    return null;
  }

  /// The full logo in its own proportions (a receipt, a wide header), or null.
  String? logoUrl({String? base}) => logoFileUrl(logoPath, base: base);

  /// [logoUrl] for a logo folder kept on its own (`subscription_receipts.company_logo_path`).
  static String? logoFileUrl(String? logoPath, {String? base}) =>
      isValidPath(logoPath) ? _url(logoPath!, 'master.png', base) : null;

  bool get hasMark => isValidPath(emblemPath) || isValidPath(logoPath);

  Map<String, Object?> toJson() => {'logo_path': logoPath, 'emblem_path': emblemPath};

  @override
  bool operator ==(Object other) =>
      other is CompanyBrand && other.logoPath == logoPath && other.emblemPath == emblemPath;

  @override
  int get hashCode => Object.hash(logoPath, emblemPath);
}
