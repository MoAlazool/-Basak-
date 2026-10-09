import 'dart:async';

import '../../../../core/storage/offline_cache.dart';

/// A receipt image this phone sent whose receipt is not known to be saved.
class PendingReceipt {
  final String path;
  final String subscriptionId;

  /// The save was sent but its answer never came: it may have gone through.
  final bool unknown;

  const PendingReceipt({required this.path, required this.subscriptionId, this.unknown = false});

  Map<String, dynamic> toJson() => {'path': path, 'subscription_id': subscriptionId, 'unknown': unknown};

  factory PendingReceipt.fromJson(Map<String, dynamic> json) => PendingReceipt(
      path: json['path'] as String,
      subscriptionId: json['subscription_id'] as String,
      unknown: json['unknown'] as bool? ?? false);
}

/// Remembers, on the device and per account, which receipt images still have
/// to be either tied to a saved receipt or removed. It survives the app being
/// closed and is erased with the account's other data on sign-out (a file
/// left then is removed by the server's own clean-up).
class PendingReceipts {
  static const _name = 'pending_receipts';

  // One change at a time: the list is read, changed and written back.
  static Future<void> _queue = Future.value();

  static Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<List<PendingReceipt>> _read() async {
    final saved = await OfflineCache.readNote(_name);
    if (saved is! List) return [];
    return [
      for (final entry in saved)
        if (entry is Map && entry['path'] is String && entry['subscription_id'] is String)
          PendingReceipt.fromJson(Map<String, dynamic>.from(entry)),
    ];
  }

  static Future<List<PendingReceipt>> all() => _locked(_read);

  static Future<PendingReceipt?> find(String path) async {
    for (final entry in await all()) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  static Future<void> remember(PendingReceipt receipt) => _locked(() async {
        final entries = (await _read()).where((e) => e.path != receipt.path).toList()..add(receipt);
        await OfflineCache.writeNote(_name, [for (final e in entries) e.toJson()]);
      });

  static Future<void> forget(String path) => _locked(() async {
        final entries = await _read();
        if (!entries.any((e) => e.path == path)) return;
        await OfflineCache.writeNote(_name, [for (final e in entries) if (e.path != path) e.toJson()]);
      });
}
