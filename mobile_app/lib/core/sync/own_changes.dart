/// One change the server announced: which table, what happened, which row.
class SyncEvent {
  final String table;

  /// INSERT, UPDATE, DELETE (or READ for notifications read on another phone).
  final String op;
  final String? id;

  const SyncEvent(this.table, {this.op = '', this.id});

  @override
  String toString() => '$table/$op/$id';
}

/// What this phone has just changed on the server itself.
///
/// The phone that makes a change shows it from the server's answer and never
/// waits for the live announcement. That announcement still comes back to it
/// (the server tells every phone of the account); recognised here, it is
/// dropped instead of making the screens read again what they already show.
/// Announcements about anything else, from anyone else, are untouched.
class OwnChanges {
  /// How long after the server's answer its announcement may still arrive.
  static const echoWindow = Duration(seconds: 3);

  /// The clock. Replaced in tests.
  static DateTime Function() now = DateTime.now;

  static final List<OwnChange> _expected = [];
  static final Map<String, DateTime> _seen = {};

  /// Call before sending a write: from now until [OwnChange.done] (plus a
  /// short while) or [OwnChange.failed], an announcement about [table]
  /// (and [id] / [op] when given) is this phone's own.
  static OwnChange begin(String table, {String? id, String? op}) {
    final change = OwnChange._(table, id, op);
    _expected.add(change);
    return change;
  }

  /// Whether [event] announces something this phone did itself.
  static bool isEcho(SyncEvent event) {
    final at = now();
    _expected.removeWhere((c) => c._until != null && !at.isBefore(c._until!));
    return _expected.any((c) =>
        c.table == event.table &&
        (c._id == null || c._id == event.id) &&
        (c.op == null || event.op.isEmpty || c.op == event.op));
  }

  /// True the first time [id] of [table] is reported within a short while,
  /// false after: the same news often arrives twice (a push and a live
  /// announcement) and should be acted on once.
  static bool firstSight(String table, String id, {Duration within = const Duration(seconds: 15)}) {
    final at = now();
    _seen.removeWhere((_, until) => !at.isBefore(until));
    final key = '$table/$id';
    if (_seen.containsKey(key)) return false;
    _seen[key] = at.add(within);
    return true;
  }

  /// Sign-out, or a new run in tests.
  static void clear() {
    _expected.clear();
    _seen.clear();
  }
}

class OwnChange {
  final String table;
  final String? op;
  String? _id;
  DateTime? _until;

  OwnChange._(this.table, this._id, this.op);

  /// The server answered. [id] is the row it created, when it was not known
  /// before; the announcement is expected for [keep] more.
  void done({String? id, Duration keep = OwnChanges.echoWindow}) {
    _id = id ?? _id;
    _until = OwnChanges.now().add(keep);
  }

  /// The write did not happen: nothing to expect.
  void failed() => OwnChanges._expected.remove(this);
}
