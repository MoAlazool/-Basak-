import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/storage/offline_cache.dart';
import '../models/subscription_model.dart';
import '../models/payment_method_model.dart';
import '../models/sale_catalog.dart';
import 'pending_receipts.dart';
import 'subscription_gateway.dart';

/// One submission of a receipt image: the image the student chose for a
/// subscription. Its key is made once, when the image is chosen, and names
/// the stored file, so every retry of the same submission writes the same
/// file instead of adding another.
class ReceiptAttempt {
  final String subscriptionId;
  final String key;

  const ReceiptAttempt({required this.subscriptionId, required this.key});

  factory ReceiptAttempt.start(String subscriptionId) {
    final random = Random.secure();
    final tail = List.generate(6, (_) => random.nextInt(36).toRadixString(36)).join();
    return ReceiptAttempt(
        subscriptionId: subscriptionId, key: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$tail');
  }

  String pathFor(String userId) => '$userId/${subscriptionId}_$key.jpg';
}

/// Where a receipt is on its way to the server.
enum ReceiptPhase { preparing, uploading, saving, done }

class SubscriptionRepository {
  final SubscriptionGateway _gateway;

  SubscriptionRepository({SubscriptionGateway? gateway}) : _gateway = gateway ?? const SupabaseSubscriptionGateway();

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Every subscription of the signed-in student: current, upcoming (paid in
  /// advance or awaiting payment) and expired, newest period first.
  Future<List<SubscriptionModel>> getSubscriptions() async {
    final userId = _gateway.userId;
    if (userId == null) return const [];
    final response = await OfflineCache.readThrough('subscriptions', () => _gateway.subscriptions(userId));
    return (response as List<dynamic>)
        .map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The subscription that matters now: the one running today, otherwise the
  /// next upcoming one. Expired subscriptions are history only.
  Future<SubscriptionModel?> getCurrentSubscription() async {
    final json = await getCurrentSubscriptionJson();
    return json == null ? null : SubscriptionModel.fromJson(json);
  }

  /// [getCurrentSubscription] as the server sent it, so it can be saved for the next start.
  Future<Map<String, dynamic>?> getCurrentSubscriptionJson() async {
    final userId = _gateway.userId;
    if (userId == null) return null;

    final response = await OfflineCache.readThrough(
        'subscriptions.current', () => _gateway.currentSubscription(userId, _today()));
    return response == null ? null : Map<String, dynamic>.from(response as Map);
  }

  /// Companies, lines, stations with their trip times, and the options on
  /// sale with their prices, for the signed-in student's university.
  Future<SaleCatalog> getSaleCatalog() async {
    final response = await OfflineCache.readThrough('sale_catalog', _gateway.saleCatalog);
    return SaleCatalog.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// The receipt issued when [subscriptionId] was approved, if any.
  Future<SubscriptionReceipt?> getSubscriptionReceipt(String subscriptionId) async {
    final row = await OfflineCache.readThrough(
        'subscription_receipt.v2.$subscriptionId',
        () => _gateway.receiptDoc(subscriptionId));
    return row == null
        ? null
        : SubscriptionReceipt.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Create a subscription. Status, dates and price are set by the database:
  /// daily = cash on the bus, active for the next ride; termly / yearly =
  /// pending_payment for the chosen period until a receipt is approved.
  Future<SubscriptionModel> createSubscription({
    required String lineId,
    required String stationId,
    required String departureTime,
    String? returnTime,
    required String type, // termly | yearly | daily
    required double price,
    String? departureTripId,
    String? returnTripId,
    String? periodCode,
    int? academicYear,
  }) async {
    final userId = _gateway.userId;
    if (userId == null) throw Exception('المستخدم غير مسجل.');

    try {
      final inserted = await requireOnline(() => _gateway.insertSubscription({
        'student_id': userId,
        'line_id': lineId,
        'station_id': stationId,
        // The database validates the trips (station + university) and owns the times.
        if (departureTripId != null) 'departure_trip_id': departureTripId,
        if (returnTripId != null) 'return_trip_id': returnTripId,
        'departure_time': departureTime,
        'return_time': returnTime,
        'type': type,
        'price': price,
        if (type != 'daily' && periodCode != null) 'period_code': periodCode,
        if (type != 'daily' && academicYear != null) 'academic_year': academicYear,
      }));
      await applySubscriptionCreated(inserted);
      return SubscriptionModel.fromJson(inserted);
    } on PostgrestException catch (error) {
      // Messages raised by the database triggers are already in Arabic.
      throw Exception(error.message);
    }
  }

  /// Upload receipt photo to Supabase Storage and insert receipt record
  /// Active payment methods of the subscription's company (managed by the
  /// company in the dashboard; never hardcoded in the app).
  Future<List<PaymentMethodModel>> getPaymentMethods(String companyId) async {
    final rows = await OfflineCache.readThrough(
        'payment_methods.$companyId',
        () => _gateway.paymentMethods(companyId));
    return (rows as List<dynamic>)
        .map((e) => PaymentMethodModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static const receiptLimitMessage = 'تم استخدام المحاولات الخمس لرفع الإيصال. تواصل مع الإدارة للمساعدة.';

  /// What to tell the student when a receipt could not be sent. The database
  /// answers in Arabic under its own codes (BR001 attempt limit, BR002 already
  /// under review, BR003 already active); an older database states the limit
  /// in English.
  static String receiptErrorText(Object error) {
    if (error is PostgrestException) {
      if (error.code == 'BR001' || error.message.contains('Maximum receipt upload limit')) {
        return receiptLimitMessage;
      }
      return error.message;
    }
    if (error is StorageException) return 'تعذر رفع صورة الإيصال. حاول مرة أخرى.';
    return errorMessage(error);
  }

  /// "Already under review" or "this image already has a receipt": what the
  /// database answers when an earlier try was saved and its answer got lost.
  static bool _mayBeSavedAlready(Object error) =>
      error is PostgrestException && (error.code == 'BR002' || error.code == '23505');

  /// Images being sent right now: [reconcilePendingReceipts] leaves them alone.
  static final Set<String> _inFlight = {};

  /// Sends the receipt of [attempt]: the image to the private bucket, then the
  /// receipt row (the database numbers the attempt and moves the subscription
  /// to "under review").
  ///
  /// The image never stays behind without a receipt. Its path belongs to the
  /// attempt, so sending the same submission again replaces its own file; if
  /// the row cannot be saved the file is removed, and when even that is not
  /// possible (no connection, app closed) the path is remembered on the device
  /// and settled later by [reconcilePendingReceipts].
  ///
  /// On success the saved copies on this phone already show the receipt and
  /// the new status (see [applyReceiptSubmitted]); the caller only has to
  /// invalidate the providers, which costs no request.
  Future<ReceiptModel> uploadReceipt({
    required ReceiptAttempt attempt,
    required Uint8List fileBytes,
    String? paymentMethodId,
    void Function(ReceiptPhase phase)? onPhase,
    void Function(int sent, int total)? onProgress,
  }) async {
    final userId = _gateway.userId;
    if (userId == null) throw Exception('المستخدم غير مسجل.');
    // receipts/{student_id}/{subscription_id}_{attempt}.jpg — the database
    // and the storage policies rely on this exact layout.
    final path = attempt.pathFor(userId);
    _inFlight.add(path);
    try {
      // An earlier try of this submission may have been saved without its
      // answer reaching the phone: then it is done, and nothing is sent twice.
      if ((await PendingReceipts.find(path))?.unknown == true) {
        final saved = await requireOnline(() => _gateway.receiptByPath(path));
        if (saved != null) return await _adopt(saved);
      }
      await PendingReceipts.remember(PendingReceipt(path: path, subscriptionId: attempt.subscriptionId));

      // 1. The image (replacing what an earlier try of this submission left).
      onPhase?.call(ReceiptPhase.uploading);
      try {
        await _gateway.uploadReceiptImage(path, fileBytes, onProgress: onProgress);
      } catch (error) {
        // No connection: the path stays remembered; a retry replaces the file
        // and the next start removes whatever part of it arrived.
        if (isNetworkFailure(error)) throw Exception(offlineActionMessage);
        // Refused: the image of a saved receipt can no longer be replaced.
        final adopted = await _settle(path, attempt.subscriptionId, maybeSaved: true);
        if (adopted != null) return adopted;
        throw Exception(receiptErrorText(error));
      }

      // 2. The receipt row (trigger sets attempt number, amount, pending_review).
      onPhase?.call(ReceiptPhase.saving);
      final Map<String, dynamic> inserted;
      try {
        inserted = await _gateway.insertReceipt({
          'subscription_id': attempt.subscriptionId,
          'image_url': path,
          if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
          'status': 'pending',
        });
      } catch (error) {
        // Whatever went wrong (refused, timed out, connection lost, anything
        // else): the image must not be left without a receipt.
        final lost = isNetworkFailure(error);
        final adopted = await _settle(path, attempt.subscriptionId, maybeSaved: lost || _mayBeSavedAlready(error));
        if (adopted != null) return adopted;
        throw Exception(lost ? offlineActionMessage : receiptErrorText(error));
      }
      return await _adopt(inserted);
    } finally {
      _inFlight.remove(path);
    }
  }

  /// The receipt is saved: this phone shows it, and the path is settled.
  Future<ReceiptModel> _adopt(Map<String, dynamic> receipt) async {
    await applyReceiptSubmitted(receipt);
    await PendingReceipts.forget(receipt['image_url'] as String);
    return ReceiptModel.fromJson(receipt);
  }

  /// Decides what becomes of an image whose receipt was not confirmed: if a
  /// receipt does reference it ([maybeSaved]: the answer may have been lost)
  /// that receipt is adopted and returned; otherwise the file is removed.
  /// When the server cannot be reached the path stays remembered.
  Future<ReceiptModel?> _settle(String path, String subscriptionId, {required bool maybeSaved}) async {
    try {
      if (maybeSaved) {
        final saved = await _gateway.receiptByPath(path);
        if (saved != null) return await _adopt(saved);
      }
      await _gateway.removeReceiptImage(path);
      await PendingReceipts.forget(path);
    } catch (_) {
      await PendingReceipts.remember(
          PendingReceipt(path: path, subscriptionId: subscriptionId, unknown: maybeSaved));
    }
    return null;
  }

  /// Settles the images remembered from earlier (app closed or offline before
  /// they could be tied to a receipt or removed): an image a receipt now
  /// references was sent successfully and is adopted; any other is deleted.
  /// Called on start, on return to the app and on reconnect. Returns the
  /// subscriptions whose receipt was adopted, for their screens to refresh.
  Future<Set<String>> reconcilePendingReceipts() async {
    final adopted = <String>{};
    if (_gateway.userId == null) return adopted;
    for (final pending in await PendingReceipts.all()) {
      if (_inFlight.contains(pending.path)) continue;
      try {
        final saved = await _gateway.receiptByPath(pending.path);
        if (saved != null) {
          await _adopt(saved);
          adopted.add(pending.subscriptionId);
        } else {
          await _gateway.removeReceiptImage(pending.path);
          await PendingReceipts.forget(pending.path);
        }
      } catch (_) {
        // Still unreachable: it stays remembered for the next time.
      }
    }
    return adopted;
  }

  /// Writes a receipt this phone just sent (the row the server returned) into
  /// what the phone holds: the receipt list of its subscription, and the
  /// subscription's status in the list, the current subscription and the pass.
  /// Nothing is read from the server for it.
  Future<void> applyReceiptSubmitted(Map<String, dynamic> receipt) async {
    final subscriptionId = receipt['subscription_id'] as String;
    Object? reviewed(Object? row) => row is Map && row['id'] == subscriptionId && row['status'] != 'active'
        ? {...row, 'status': 'pending_review'}
        : row;
    await OfflineCache.applyLocal('receipts.$subscriptionId', (current) => [
          receipt,
          for (final other in current as List? ?? const [])
            if (other is! Map || other['id'] != receipt['id']) other,
        ]);
    await OfflineCache.applyLocal('subscriptions', (current) => [for (final row in current as List? ?? const []) reviewed(row)]);
    await OfflineCache.applyLocal('subscriptions.current', reviewed);
    await OfflineCache.applyLocal(
        'student_pass',
        (current) => current is Map && current['subscription_id'] == subscriptionId
            ? {...current, 'subscription_status': 'pending_review'}
            : current);
  }

  /// Writes a subscription this phone just created into what the phone holds.
  Future<void> applySubscriptionCreated(Map<String, dynamic> created) async {
    await OfflineCache.applyLocal('subscriptions', (current) => [
          created,
          for (final other in current as List? ?? const [])
            if (other is! Map || other['id'] != created['id']) other,
        ]);
    // The current one is the earliest still open (see getCurrentSubscriptionJson).
    await OfflineCache.applyLocal('subscriptions.current', (current) {
      if (current is! Map) return created;
      final mine = created['start_date'] as String?, theirs = current['start_date'] as String?;
      if (mine == null) return current;
      return theirs == null || mine.compareTo(theirs) <= 0 ? created : current;
    });
  }

  /// Get receipts history for a subscription
  Future<List<ReceiptModel>> getReceiptsHistory(String subscriptionId) async {
    final response = await OfflineCache.readThrough(
        'receipts.$subscriptionId',
        () => _gateway.receipts(subscriptionId));

    return (response as List<dynamic>)
        .map((e) => ReceiptModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
