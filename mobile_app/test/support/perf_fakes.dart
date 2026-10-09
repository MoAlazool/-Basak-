import 'dart:io';
import 'dart:typed_data';

import 'package:basak_mobile/core/media/signed_url_cache.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, StorageException;
import 'package:basak_mobile/features/auth/data/auth_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/profile/data/profile_repository.dart';
import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_gateway.dart';

/// Every "request" the fakes below answer, by name.
class RequestLog {
  final Map<String, int> calls = {};

  void hit(String name) => calls[name] = (calls[name] ?? 0) + 1;
  int get total => calls.values.fold(0, (a, b) => a + b);
  int of(String name) => calls[name] ?? 0;
  void reset() => calls.clear();

  @override
  String toString() => '$total $calls';
}

/// A tiny PNG, for where a photo is shown but nothing is downloaded.
final onePixel = Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));

const studentId = 'student-1';
const subscriptionId = 'sub-1';

Map<String, dynamic> subscriptionRow({String status = 'pending_payment', String id = subscriptionId}) => {
      'id': id, 'student_id': studentId, 'line_id': 'line-1', 'company_id': 'company-1', 'station_id': 'station-1',
      'type': 'termly', 'status': status, 'price': 8000, 'created_at': '2026-10-01T08:00:00Z',
      'start_date': '2026-09-05', 'end_date': '2027-01-30', 'departure_time': '07:00:00', 'return_time': '15:00:00',
      'period_code': 'first', 'academic_year': 2026, 'period_label': 'الفصل الدراسي الأول 2026/2027',
      'period_phase': 'current',
      'lines': {
        'name': 'منية النصر', 'companies': {'name': 'المستقبل'},
        'supervisors': {'full_name': 'محمود', 'phone': '01000000000', 'profile_image_url': 'sup-1/photo.jpg'},
        'line_trips': <dynamic>[],
      },
      'stations': {'name': 'البجلات', 'departure_times': ['07:00'], 'return_times': ['15:00'], 'line_trip_stops': <dynamic>[]},
      'student': {'university': 'جامعة الدلتا'},
    };

/// The server as the subscription screens see it: subscriptions, receipts and
/// the receipt images, with the insert trigger's behaviour.
class FakeSubscriptionServer implements SubscriptionGateway {
  final RequestLog log;
  FakeSubscriptionServer(this.log);

  @override
  String? userId = studentId;

  final List<Map<String, dynamic>> subs = [subscriptionRow()];
  final List<Map<String, dynamic>> receiptRows = [];
  final Map<String, int> images = {}; // path -> times written

  /// How this database words the attempt limit (a newer one: BR001 in Arabic).
  String limitMessage = 'بلغت الحد الأقصى لمحاولات رفع الإيصال.';
  String? limitCode = 'BR001';
  int _nextReceipt = 1;

  /// Thrown instead of answering (once), per request name.
  final Map<String, Object> failNext = {};
  /// The insert is saved but its answer never arrives.
  bool loseInsertAnswer = false;
  /// Thrown by every removal while set.
  Object? removeFails;

  /// No connection: every request fails the way a phone without internet does.
  bool offline = false;

  /// The image of a saved receipt may be overwritten (a server without that
  /// storage rule): the duplicate is then caught by the unique index.
  bool allowOverwrite = false;

  void _request(String name) {
    log.hit(name);
    if (offline) throw const SocketException('Failed host lookup');
    final error = failNext.remove(name);
    if (error != null) throw error;
  }

  Map<String, dynamic> sub(String id) => subs.firstWhere((s) => s['id'] == id);

  @override
  Future<List<dynamic>> subscriptions(String userId) async {
    _request('subscriptions.all');
    return [for (final s in subs) Map<String, dynamic>.from(s)];
  }

  @override
  Future<Map<String, dynamic>?> currentSubscription(String userId, String today) async {
    _request('subscriptions.current');
    return subs.isEmpty ? null : Map<String, dynamic>.from(subs.first);
  }

  @override
  Future<dynamic> saleCatalog() async {
    _request('sale_catalog');
    return {'university': {'id': 'u1', 'name': 'جامعة الدلتا'}, 'companies': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>?> receiptDoc(String subscriptionId) async {
    _request('subscription_receipt');
    return null;
  }

  @override
  Future<Map<String, dynamic>> insertSubscription(Map<String, dynamic> row) async {
    _request('subscriptions.insert');
    final created = subscriptionRow(id: 'sub-${subs.length + 1}');
    subs.insert(0, created);
    return Map<String, dynamic>.from(created);
  }

  @override
  Future<List<dynamic>> paymentMethods(String companyId) async {
    _request('payment_methods');
    return [
      {'id': 'pm-1', 'method_type': 'instapay', 'display_name': 'InstaPay', 'instapay_address': 'basak@instapay'}
    ];
  }

  @override
  Future<List<dynamic>> receipts(String subscriptionId) async {
    _request('receipts.list');
    return [
      for (final r in receiptRows.reversed)
        if (r['subscription_id'] == subscriptionId) Map<String, dynamic>.from(r)
    ];
  }

  @override
  Future<void> uploadReceiptImage(String path, Uint8List bytes, {void Function(int sent, int total)? onProgress}) async {
    _request('receipts.upload');
    // The storage rule: the image of a saved receipt can no longer be replaced.
    if (!allowOverwrite && receiptRows.any((r) => r['image_url'] == path)) {
      throw const StorageException('new row violates row-level security policy', statusCode: '403');
    }
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    onProgress?.call(bytes.length, bytes.length);
    images[path] = (images[path] ?? 0) + 1;
  }

  @override
  Future<Map<String, dynamic>> insertReceipt(Map<String, dynamic> row) async {
    _request('receipts.insert');
    final subscription = row['subscription_id'] as String;
    final earlier = receiptRows.where((r) => r['subscription_id'] == subscription);
    // What the database's trigger and unique index answer.
    if (receiptRows.any((r) => r['image_url'] == row['image_url'])) {
      throw const PostgrestException(message: 'duplicate key value violates unique constraint', code: '23505');
    }
    if (earlier.any((r) => r['status'] == 'pending')) {
      throw const PostgrestException(message: 'يوجد إيصال قيد المراجعة لهذا الاشتراك.', code: 'BR002');
    }
    if (earlier.length >= 5) {
      throw PostgrestException(message: limitMessage, code: limitCode);
    }
    final attempt = earlier.length + 1;
    final saved = {
      'id': 'receipt-${_nextReceipt++}', 'subscription_id': subscription, 'image_url': row['image_url'],
      'status': 'pending', 'rejection_reason': null, 'attempt_number': attempt, 'reviewed_by': null,
      'created_at': '2026-10-09T10:00:00Z', 'reviewed_at': null,
    };
    receiptRows.add(saved);
    sub(subscription)['status'] = 'pending_review';
    if (loseInsertAnswer) {
      loseInsertAnswer = false;
      throw Exception('ClientException: Connection closed before full header was received');
    }
    return Map<String, dynamic>.from(saved);
  }

  @override
  Future<void> removeReceiptImage(String path) async {
    _request('receipts.remove_image');
    if (removeFails != null) throw removeFails!;
    // The storage rule: only an image no receipt references can be removed.
    if (receiptRows.any((r) => r['image_url'] == path)) return;
    images.remove(path);
  }

  @override
  Future<Map<String, dynamic>?> receiptByPath(String path) async {
    _request('receipts.by_path');
    for (final r in receiptRows) {
      if (r['image_url'] == path) return Map<String, dynamic>.from(r);
    }
    return null;
  }

  /// What the reviewer does in the dashboard.
  void approve(String subscription) {
    sub(subscription)['status'] = 'active';
    for (final r in receiptRows.where((r) => r['subscription_id'] == subscription)) {
      if (r['status'] == 'pending') r['status'] = 'approved';
    }
  }
}

class FakePassServer implements StudentPassGateway {
  final RequestLog log;
  final FakeSubscriptionServer server;
  FakePassServer(this.log, this.server);

  String? photoPath = '$studentId/avatar-1.jpg';
  String college = 'هندسة';

  @override
  String? userId = studentId;

  @override
  Future<Map<String, dynamic>?> studentRow(String userId) async {
    log.hit('pass.student');
    return {
      'qr_code_value': 'QR-1', 'full_name': 'محمد عادل فؤاد العزول', 'phone': '01055512301',
      'university': 'جامعة الدلتا', 'college': college, 'profile_image_url': photoPath,
    };
  }

  @override
  Future<Map<String, dynamic>?> subscriptionRow(String userId, String today) async {
    log.hit('pass.subscription');
    if (server.subs.isEmpty) return null;
    final s = server.subs.first;
    return {
      'id': s['id'], 'type': s['type'], 'status': s['status'], 'departure_time': s['departure_time'],
      'return_time': s['return_time'], 'lines': {'name': 'منية النصر'}, 'stations': {'name': 'البجلات'},
    };
  }

  @override
  void refreshWalletCard() => log.hit('pass.wallet_refresh');
}

class FakeProfileServer implements ProfileGateway {
  final RequestLog log;
  final FakePassServer pass;
  FakeProfileServer(this.log, this.pass);

  final Set<String> files = {'$studentId/avatar-1.jpg'};
  Object? setPhotoFails;
  String? email;

  @override
  String? userId = studentId;

  @override
  Future<Map<String, dynamic>?> summaryRow(String userId) async {
    log.hit('profile.summary');
    return {
      'full_name': 'محمد عادل فؤاد العزول', 'phone': '01055512301', 'university': 'جامعة الدلتا',
      'college': pass.college, 'email': email, 'birth_date': null, 'profile_image_url': pass.photoPath,
    };
  }

  @override
  Future<dynamic> updateDetails(Map<String, dynamic> params) async {
    log.hit('profile.update');
    email = params['p_email'] as String?;
    pass.college = (params['p_college'] as String?) ?? 'غير محدد';
    return {'email': email, 'college': pass.college, 'birth_date': params['p_birth_date']};
  }

  @override
  Future<void> uploadPhoto(String path, Uint8List jpeg) async {
    log.hit('profile.photo_upload');
    files.add(path);
  }

  @override
  Future<dynamic> setPhoto(String path) async {
    log.hit('profile.photo_set');
    if (setPhotoFails != null) throw setPhotoFails!;
    final old = pass.photoPath;
    pass.photoPath = path;
    return old;
  }

  @override
  Future<List<String>> listPhotos(String userId) async {
    log.hit('profile.photo_list');
    return [for (final f in files) f.split('/').last];
  }

  @override
  Future<void> removePhotos(List<String> paths) async {
    log.hit('profile.photo_remove');
    files.removeAll(paths);
  }
}

class FakeRoles implements RoleLookup {
  final RequestLog log;
  FakeRoles(this.log, {this.role = 'student', this.hasRpc = true});

  final String? role;
  final bool hasRpc;

  @override
  Future<String?> myRole() async {
    log.hit('role.rpc');
    if (!hasRpc) throw const RoleRpcUnavailable();
    return role;
  }

  @override
  Future<bool> isIn(String table, String userId) async {
    log.hit('role.select');
    return table == '${role}s';
  }
}

/// The ride votes, counted per read (each read is at most one request).
class FakeRides implements DailyRideRepository {
  final RequestLog log;
  FakeRides(this.log);

  static const settings = VoteSettings(opensAt: 16 * 60, closesAt: 6 * 60, reminderMinutes: 30);

  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async {
    log.hit('vote_settings');
    return settings;
  }

  @override
  Future<Map<DateTime, bool>> getRideStatusesForRange(DateTime start, DateTime end) async {
    log.hit('ride.range');
    return {};
  }

  @override
  Future<DailyRideDetails> getRideDetailsForDate(DateTime date) async {
    log.hit('ride.details');
    return const DailyRideDetails(isRiding: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signs like the storage service does: a new token every time it is asked.
void fakeSigner(RequestLog log, {bool Function()? offline}) {
  var token = 0;
  SignedUrlCache.signer = (bucket, path, seconds) async {
    log.hit('storage.sign');
    if (offline?.call() ?? false) throw Exception('SocketException: Failed host lookup');
    return 'https://x.supabase.co/storage/v1/object/sign/$bucket/$path?token=${++token}';
  };
}
