import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, StorageException;

import 'package:basak_mobile/core/network/network_errors.dart';
import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/storage/snapshot_store.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/subscription/data/pending_receipts.dart';
import 'package:basak_mobile/features/student/subscription/data/receipt_image_upload.dart';
import 'package:basak_mobile/features/student/subscription/data/subscription_repository.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart';

import 'support/perf_fakes.dart';
import 'support/student_world.dart';

/// Sending a payment receipt: the image never stays behind without a receipt,
/// and the phone that sent it shows the result from the server's own answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final image = Uint8List.fromList(List.filled(40, 7));
  const attempt = ReceiptAttempt(subscriptionId: subscriptionId, key: 'abc123');
  const path = '$studentId/${subscriptionId}_abc123.jpg';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = studentId;
    OfflineCache.resetSession();
    OwnChanges.now = DateTime.now;
  });
  tearDown(() {
    OfflineCache.debugUserId = null;
    OwnChanges.now = DateTime.now;
  });

  String? savedStatus(Object? json) => (json as Map?)?['status'] as String?;

  group('the stored file', () {
    test('its path belongs to the attempt, and a new image gets a new one', () {
      expect(attempt.pathFor(studentId), path);
      final first = ReceiptAttempt.start(subscriptionId), second = ReceiptAttempt.start(subscriptionId);
      expect(first.key, isNot(second.key));
      expect(first.pathFor(studentId), startsWith('$studentId/${subscriptionId}_'));
      expect(first.pathFor(studentId), endsWith('.jpg'));
    });

    test('the receipt is refused by the database: the image is removed', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      world.server.failNext['receipts.insert'] =
          const PostgrestException(message: 'هذا الاشتراك مفعّل بالفعل.', code: 'BR003');

      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image),
          throwsA(predicate((e) => errorMessage(e!) == 'هذا الاشتراك مفعّل بالفعل.')));

      expect(world.server.images, isEmpty, reason: 'no image without a receipt');
      expect(await PendingReceipts.all(), isEmpty);
      expect(world.server.receiptRows, isEmpty);
    });

    test('the save fails for any other reason (a timeout, a bug): the image is removed too', () async {
      for (final failure in <Object>[TimeoutException('no answer'), StateError('unexpected')]) {
        final world = StudentWorld();
        final repo = SubscriptionRepository(gateway: world.server);
        world.server.failNext['receipts.insert'] = failure;

        await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image), throwsException);

        expect(world.server.images, isEmpty, reason: '$failure');
        expect(await PendingReceipts.all(), isEmpty, reason: '$failure');
      }
    });

    test('the image cannot be removed now: it is remembered on the phone and removed later', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      world.server
        ..failNext['receipts.insert'] = const PostgrestException(message: 'مرفوض', code: 'P0001')
        ..removeFails = const SocketException('Failed host lookup');

      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image), throwsException);
      expect(world.server.images.keys, [path], reason: 'still there: the connection dropped');
      expect((await PendingReceipts.all()).single.path, path);

      // The app is closed and opened again; the connection is back.
      OfflineCache.resetSession();
      world.server.removeFails = null;
      final later = SubscriptionRepository(gateway: world.server);
      expect(await later.reconcilePendingReceipts(), isEmpty, reason: 'nothing was saved, so nothing to show');

      expect(world.server.images, isEmpty);
      expect(await PendingReceipts.all(), isEmpty);
    });

    test('still no connection on the next start: it stays remembered', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      world.server
        ..failNext['receipts.insert'] = const PostgrestException(message: 'مرفوض', code: 'P0001')
        ..removeFails = const SocketException('Failed host lookup');
      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image), throwsException);

      world.server.offline = true;
      await repo.reconcilePendingReceipts();
      expect((await PendingReceipts.all()).single.path, path);
    });

    test('the answer was lost but the receipt was saved: it is adopted, never deleted', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.server
        ..loseInsertAnswer = true
        ..failNext['receipts.by_path'] = const SocketException('Failed host lookup');

      await expectLater(c.read(receiptSubmitterProvider).submit(attempt: attempt, bytes: image),
          throwsA(predicate((e) => errorMessage(e!) == offlineActionMessage)));
      expect(world.server.receiptRows, hasLength(1), reason: 'the server did save it');
      final pending = (await PendingReceipts.all()).single;
      expect([pending.path, pending.unknown], [path, true]);
      expect(c.read(currentSubscriptionProvider).value?.status, 'pending_payment', reason: 'not known yet');

      // Back online (or the next start).
      world.log.reset();
      await c.read(receiptSubmitterProvider).settlePending();
      await loaded(c);

      expect(world.server.images.keys, [path], reason: 'the image of a saved receipt is kept');
      expect(await PendingReceipts.all(), isEmpty);
      expect(c.read(currentSubscriptionProvider).value?.status, 'pending_review');
      expect(c.read(subscriptionReceiptsProvider(subscriptionId)).value?.single.imageUrl, path);
      expect(world.log.calls, {'receipts.by_path': 1}, reason: 'one small read; the screens read nothing again');
    });

    test('the answer was lost but the server is still reachable: it counts as sent at once', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      world.server.loseInsertAnswer = true;

      final receipt = await repo.uploadReceipt(attempt: attempt, fileBytes: image);

      expect(receipt.imageUrl, path);
      expect(world.server.images.keys, [path]);
      expect(await PendingReceipts.all(), isEmpty);
    });

    test('sending the same submission again writes the same file, replacing it', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      world.server.offline = true;
      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image), throwsException);

      // The save did not get through the first time either.
      world.server
        ..offline = false
        ..failNext['receipts.insert'] = const SocketException('Connection reset')
        ..failNext['receipts.by_path'] = const SocketException('Connection reset');
      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image), throwsException);
      expect(world.server.images, {path: 1});

      final receipt = await repo.uploadReceipt(attempt: attempt, fileBytes: image);

      expect(world.server.images, {path: 2}, reason: 'one file, written again; never a second one');
      expect(receipt.attemptNumber, 1);
      expect(world.server.receiptRows, hasLength(1));
      expect(await PendingReceipts.all(), isEmpty);
    });

    test('sending again after a lost answer finds the saved receipt instead of sending twice', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      world.server
        ..loseInsertAnswer = true
        ..failNext['receipts.by_path'] = const SocketException('Failed host lookup');
      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image), throwsException);
      world.log.reset();

      final receipt = await repo.uploadReceipt(attempt: attempt, fileBytes: image);

      expect(receipt.imageUrl, path);
      expect(world.log.calls, {'receipts.by_path': 1}, reason: 'no second upload, no second receipt');
      expect(world.server.receiptRows, hasLength(1));
    });

    test('the database says "already under review" or "this image has a receipt": adopted, not deleted',
        () async {
      for (final overwrite in [false, true]) {
        FlutterSecureStorage.setMockInitialValues({});
        OfflineCache.resetSession();
        final world = StudentWorld();
        final repo = SubscriptionRepository(gateway: world.server);
        // Saved by an earlier try this phone knows nothing about any more.
        await repo.uploadReceipt(attempt: attempt, fileBytes: image);
        world.server.allowOverwrite = overwrite; // false: storage refuses; true: the unique index does

        final receipt = await repo.uploadReceipt(attempt: attempt, fileBytes: image);

        expect(receipt.imageUrl, path);
        expect(world.server.images.keys, [path], reason: 'overwrite allowed: $overwrite');
        expect(world.server.receiptRows, hasLength(1));
      }
    });

    test('a different receipt is under review: this image is removed and the reason is told', () async {
      final world = StudentWorld();
      final repo = SubscriptionRepository(gateway: world.server);
      await repo.uploadReceipt(attempt: const ReceiptAttempt(subscriptionId: subscriptionId, key: 'other'), fileBytes: image);

      await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image),
          throwsA(predicate((e) => errorMessage(e!).contains('قيد المراجعة'))));

      expect(world.server.images.keys, ['$studentId/${subscriptionId}_other.jpg']);
      expect(world.server.receiptRows, hasLength(1));
    });

    test('the attempt limit is told in Arabic, by the new code and by an older database\'s English', () async {
      for (final old in [false, true]) {
        final world = StudentWorld();
        final repo = SubscriptionRepository(gateway: world.server);
        for (var i = 1; i <= 5; i++) {
          world.server.receiptRows.add({
            'id': 'old-$i', 'subscription_id': subscriptionId, 'image_url': 'x/$i.jpg', 'status': 'rejected',
            'attempt_number': i, 'created_at': '2026-10-0${i}T10:00:00Z',
          });
        }
        if (old) {
          world.server
            ..limitCode = 'P0001'
            ..limitMessage = 'Maximum receipt upload limit reached (5 attempts: initial + 4 re-uploads).';
        }
        world.log.reset();

        await expectLater(repo.uploadReceipt(attempt: attempt, fileBytes: image),
            throwsA(predicate((e) => errorMessage(e!) == SubscriptionRepository.receiptLimitMessage)));

        expect(world.log.of('receipts.precheck'), 0, reason: 'the database is the judge; nothing is asked first');
        expect(world.server.images, isEmpty);
      }
    });
  });

  group('what the phone shows', () {
    test('a sent receipt is on screen and saved on the phone from the answer alone', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.log.reset();
      final phases = <ReceiptPhase>[];
      final progress = <int>[];

      final receipt = await c.read(receiptSubmitterProvider).submit(
          attempt: attempt,
          bytes: image,
          paymentMethodId: 'pm-1',
          onPhase: phases.add,
          onProgress: (sent, total) => progress.add(sent));
      await loaded(c);

      expect(phases, [ReceiptPhase.uploading, ReceiptPhase.saving]);
      expect(progress.last, image.length);
      expect(world.log.calls, {'receipts.upload': 1, 'receipts.insert': 1}, reason: 'nothing is read again');

      // The providers.
      expect(c.read(currentSubscriptionProvider).value?.status, 'pending_review');
      expect(c.read(allSubscriptionsProvider).value?.single.status, 'pending_review');
      expect(c.read(subscriptionReceiptsProvider(subscriptionId)).value?.single.id, receipt.id);
      expect(c.read(studentQrProvider).value?.subscriptionStatus, 'pending_review');
      // The saved copies.
      expect(savedStatus(await OfflineCache.peek('subscriptions.current')), 'pending_review');
      expect(savedStatus((await OfflineCache.peek('subscriptions') as List).single), 'pending_review');
      expect(((await OfflineCache.peek('receipts.$subscriptionId')) as List).single['id'], receipt.id);
      expect(savedStatus(await SnapshotStore.read(studentId, 'current_subscription')), 'pending_review');

      // Closed and opened again with no connection: the same state.
      OfflineCache.resetSession();
      world.server.offline = true;
      final next = world.open();
      expect((await next.read(currentSubscriptionProvider.future))?.status, 'pending_review');
      expect((await next.read(allSubscriptionsProvider.future)).single.status, 'pending_review');
      expect((await next.read(subscriptionReceiptsProvider(subscriptionId).future)).single.attemptNumber, 1);
      await settle();
    });

    test('a failed send leaves the screens and the saved copies as they were', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.server.failNext['receipts.insert'] = const PostgrestException(message: 'مرفوض', code: 'P0001');
      world.log.reset();

      await expectLater(c.read(receiptSubmitterProvider).submit(attempt: attempt, bytes: image), throwsException);
      await loaded(c);

      expect(c.read(currentSubscriptionProvider).value?.status, 'pending_payment');
      expect(c.read(allSubscriptionsProvider).value?.single.status, 'pending_payment');
      expect(c.read(subscriptionReceiptsProvider(subscriptionId)).value, isEmpty);
      expect(savedStatus(await OfflineCache.peek('subscriptions.current')), 'pending_payment');
      expect(world.log.calls, {'receipts.upload': 1, 'receipts.insert': 1, 'receipts.remove_image': 1});

      // Nothing was left expecting an echo: a live event is acted on as usual.
      world.server.sub(subscriptionId)['status'] = 'rejected';
      await world.events(c, const [SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId)]);
      await loaded(c);
      expect(c.read(currentSubscriptionProvider).value?.status, 'rejected');
    });

    test('its own echo reads nothing; the same tables changed from elsewhere are read again', () async {
      var now = DateTime(2026, 10, 9, 10);
      OwnChanges.now = () => now;
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      final receipt = await c.read(receiptSubmitterProvider).submit(attempt: attempt, bytes: image);
      await loaded(c);
      world.log.reset();

      // The server's announcement of what this phone just did.
      await world.events(c, [
        SyncEvent('receipts', op: 'INSERT', id: receipt.id),
        const SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId),
      ]);
      await loaded(c);
      expect(world.log.total, 0);

      // The reviewer rejects it a moment later: that is news.
      now = now.add(const Duration(seconds: 20));
      world.server.sub(subscriptionId)['status'] = 'rejected';
      world.server.receiptRows.single['status'] = 'rejected';
      await world.events(c, [
        SyncEvent('receipts', op: 'UPDATE', id: receipt.id),
        const SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId),
      ]);
      await loaded(c);

      expect(c.read(currentSubscriptionProvider).value?.status, 'rejected');
      expect(c.read(subscriptionReceiptsProvider(subscriptionId)).value?.single.status, 'rejected');
      expect(c.read(studentQrProvider).value?.subscriptionStatus, 'rejected', reason: 'the card follows');
      expect(world.log.of('subscriptions.all'), 1);
      expect(world.log.of('receipts.list'), 1);
    });

    test('a receipt sent from the student\'s other phone is read here', () async {
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      world.log.reset();

      await SubscriptionRepository(gateway: world.server).uploadReceipt(attempt: attempt, fileBytes: image);
      OfflineCache.resetSession(); // the other phone has its own memory
      world.log.reset();
      await world.events(c, const [
        SyncEvent('receipts', op: 'INSERT', id: 'receipt-1'),
        SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId),
      ]);
      await loaded(c);

      expect(c.read(currentSubscriptionProvider).value?.status, 'pending_review');
      expect(c.read(subscriptionReceiptsProvider(subscriptionId)).value, hasLength(1));
      expect(world.log.of('receipts.list'), 1);
    });

    test('an approval right after sending still shows promptly', () async {
      var now = DateTime(2026, 10, 9, 10);
      OwnChanges.now = () => now;
      final world = StudentWorld();
      final c = world.open();
      await watchScreens(c);
      await c.read(receiptSubmitterProvider).submit(attempt: attempt, bytes: image);
      await loaded(c);

      now = now.add(const Duration(seconds: 4));
      world.server.approve(subscriptionId);
      await world.events(c, const [
        SyncEvent('receipts', op: 'UPDATE', id: 'receipt-1'),
        SyncEvent('subscriptions', op: 'UPDATE', id: subscriptionId),
      ]);
      await loaded(c);

      expect(c.read(currentSubscriptionProvider).value?.status, 'active');
      expect(c.read(studentQrProvider).value?.subscriptionStatus, 'active');
    });
  });

  group('the upload request', () {
    test('one streamed POST that replaces the file, with the progress of what was really sent', () async {
      final bytes = Uint8List.fromList(List.generate(100 * 1024, (i) => i % 251));
      late http.BaseRequest seen;
      final received = <int>[];
      final sentWhenReceived = <int>[];
      var reported = 0;
      final client = MockClient.streaming((request, body) async {
        seen = request;
        await for (final piece in body) {
          received.addAll(piece);
          sentWhenReceived.add(reported);
        }
        return http.StreamedResponse(Stream.value('{"Key":"receipts/x"}'.codeUnits), 200);
      });
      final progress = <int>[];

      await ReceiptImageUpload.post(
          client: client,
          url: Uri.parse('https://x.supabase.co/storage/v1/object/receipts/$path'),
          headers: {'Authorization': 'Bearer token', 'apikey': 'key'},
          bytes: bytes,
          onProgress: (sent, total) {
            expect(total, bytes.length);
            reported = sent;
            progress.add(sent);
          });

      expect(seen.method, 'POST');
      expect(seen.url.path, '/storage/v1/object/receipts/$path');
      expect(seen.headers['x-upsert'], 'true');
      expect(seen.headers['content-type'], 'image/jpeg');
      expect(seen.headers['Authorization'], 'Bearer token');
      expect(seen.contentLength, bytes.length);
      expect(received, bytes, reason: 'the image itself, not a form around it');
      expect(progress.length, greaterThan(3), reason: 'several steps, not one jump');
      expect([...progress]..sort(), progress, reason: 'it only goes forward');
      expect(progress.last, bytes.length);
      // A piece is counted after the connection took it, never before.
      for (var i = 0; i < sentWhenReceived.length; i++) {
        expect(sentWhenReceived[i], lessThanOrEqualTo(i * 16 * 1024));
      }
      expect(progress[progress.length - 2], lessThan(bytes.length), reason: 'complete only once the server answered');
    });

    test('a refusal by the storage service is told as one', () async {
      final client = MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
            Stream.value('{"statusCode":"403","message":"new row violates row-level security policy"}'.codeUnits), 400);
      });
      await expectLater(
          ReceiptImageUpload.post(
              client: client, url: Uri.parse('https://x/storage/v1/object/receipts/a.jpg'), headers: const {}, bytes: image),
          throwsA(isA<StorageException>().having((e) => e.message, 'message', contains('row-level security'))));
    });
  });
}
