/// A version as the stores number them: up to three numbers, compared number
/// by number ("1.0.10" is after "1.0.6"). A missing number is zero ("2.5" is
/// "2.5.0"); a build suffix ("+35") or a pre-release tag ("-beta") is not part
/// of it.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  const AppVersion(this.major, [this.minor = 0, this.patch = 0]);

  /// Null for anything that is not a version: the caller then behaves as if
  /// there were nothing to compare.
  static AppVersion? tryParse(String? text) {
    var value = (text ?? '').trim();
    if (value.startsWith('v') || value.startsWith('V')) value = value.substring(1);
    value = value.split('+').first.split('-').first.trim();
    if (value.isEmpty) return null;
    final pieces = value.split('.');
    if (pieces.length > 3) return null;
    final numbers = <int>[];
    for (final piece in pieces) {
      if (!RegExp(r'^\d{1,9}$').hasMatch(piece)) return null;
      numbers.add(int.parse(piece));
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && major == other.major && minor == other.minor && patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

enum UpdateKind {
  /// Nothing to say.
  none,

  /// A newer version is in the store: offered once, over Home.
  optional,

  /// This version is no longer allowed in: asked for before anything else.
  required,
}

/// What the server says about this platform's releases, held against the
/// installed version.
class AppUpdate {
  final UpdateKind kind;

  /// As shown: "2.3.1".
  final String installed;
  final String minVersion;
  final String latestVersion;

  /// At most three lines.
  final List<String> whatsNew;

  /// The app's page in this platform's store, when the dashboard has one.
  final String? storeUrl;

  const AppUpdate({
    required this.kind,
    this.installed = '',
    this.minVersion = '',
    this.latestVersion = '',
    this.whatsNew = const [],
    this.storeUrl,
  });

  /// Nothing known, or nothing newer: the app carries on.
  static const none = AppUpdate(kind: UpdateKind.none);

  bool get isRequired => kind == UpdateKind.required;
  bool get isOptional => kind == UpdateKind.optional;

  /// Reads `get_app_version`'s answer. Anything unexpected in it (no row, a
  /// version that is not one, another shape) means no update.
  factory AppUpdate.resolve({required String? installed, required Object? answer}) {
    final mine = AppVersion.tryParse(installed);
    if (mine == null || answer is! Map) return none;
    // The server sends text; anything else is not trusted to be a version.
    String? text(String key) => answer[key] is String ? answer[key] as String : null;
    final min = AppVersion.tryParse(text('min_version'));
    final latest = AppVersion.tryParse(text('latest_version'));
    final kind = min != null && mine < min
        ? UpdateKind.required
        : (latest != null && mine < latest ? UpdateKind.optional : UpdateKind.none);
    final url = (text('store_url') ?? '').trim();
    final lines = answer['whats_new'];
    return AppUpdate(
      kind: kind,
      installed: mine.toString(),
      minVersion: (min ?? const AppVersion(0)).toString(),
      // A required update is to the newest version, whatever the floor is.
      latestVersion: (latest != null && (min == null || !(latest < min)) ? latest : (min ?? mine)).toString(),
      whatsNew: [
        if (lines is List)
          for (final line in lines)
            if (line is String && line.trim().isNotEmpty) line.trim(),
      ].take(3).toList(growable: false),
      storeUrl: url.startsWith('https://') ? url : null,
    );
  }
}
