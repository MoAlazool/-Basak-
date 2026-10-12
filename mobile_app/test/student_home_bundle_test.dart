import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/storage/prefetched_reads.dart';
import 'package:basak_mobile/core/sync/own_changes.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/data/home_bundle.dart';

/// get_student_home as a test double: answers what it is given, counts calls.
class _Home implements StudentHomeGateway {
  Object? answer;
  Object? fails;
  Completer<void>? gate;
  int calls = 0;
  ({String today, String? rideFrom, String? rideTo})? asked;

  @override
  Future<Object?> fetch({required String today, String? rideFrom, String? rideTo}) async {
    calls++;
    asked = (today: today, rideFrom: rideFrom, rideTo: rideTo);
    await gate?.future;
    if (fails != null) throw fails!;
    return answer;
  }
}

Map<String, Object?> _fullAnswer() => {
      'v': 1,
      'profile': {'id': 'student-a', 'full_name': 'أحمد'},
      'subscriptions': [
        {'id': 'sub-1', 'company_id': 'co-1', 'status': 'active'},
      ],
      'current': {'id': 'sub-1', 'company_id': 'co-1', 'status': 'active'},
      'vote_company': 'co-1',
      'vote_settings': {'company_id': 'co-1', 'opens_at': '14:00', 'closes_at': '07:30', 'reminder_minutes': 60},
      'ride_days': [
        {'ride_date': '2026-10-11', 'is_riding': true, 'departure_time': null, 'return_time': null, 'is_returning': true},
      ],
      'receipts_of': 'sub-1',
      'receipts': [
        {'id': 'r-1', 'subscription_id': 'sub-1', 'status': 'approved'},
      ],
      'inbox': {'items': [], 'unread': 0, 'next_before': null},
      'invites': [],
      'offers': {'hidden': false, 'offers': []},
      'line_supervisors': [
        {'line_id': 'l-1', 'id': 'sup-1', 'full_name': 'محمود', 'phone': '010', 'profile_image_url': null},
      ],
      'recap_releases': [],
      'boarded_rides': 7,
    };

void main() {
  late _Home home;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.debugUserId = 'student-a';
    OfflineCache.resetSession();
    PrefetchedReads.discard();
    PrefetchedReads.now = DateTime.now;
    home = _Home();
    StudentHomeBundle.gateway = home;
  });
  tearDown(() {
    OfflineCache.debugUserId = null;
    PrefetchedReads.discard();
    PrefetchedReads.now = DateTime.now;
    StudentHomeBundle.gateway = const SupabaseStudentHomeGateway();
  });

  group('PrefetchedReads', () {
    test('a covered read waits for the batch and takes its answer, once', () async {
      final answers = Completer<Map<String, Object?>?>();
      PrefetchedReads.begin(userId: 'u', covers: (k) => k.startsWith('a'), answers: answers.future);
      final first = PrefetchedReads.take('a.1', userId: 'u');
      answers.complete({'a.1': 'one', 'a.2': null});
      expect(await first, (found: true, value: 'one'));
      expect(await PrefetchedReads.take('a.1', userId: 'u'), (found: false, value: null),
          reason: 'a second read of the same thing asks the server');
      expect(await PrefetchedReads.take('a.2', userId: 'u'), (found: true, value: null),
          reason: 'an answer that is null is still an answer');
      expect(await PrefetchedReads.take('a.3', userId: 'u'), (found: false, value: null), reason: 'not in the answer');
      expect(await PrefetchedReads.take('b', userId: 'u'), (found: false, value: null), reason: 'not covered');
    });

    test('another account, a failed batch, a discarded one or a stale one answer nothing', () async {
      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: Future.value({'k': 1}));
      expect(await PrefetchedReads.take('k', userId: 'other'), (found: false, value: null));
      expect(await PrefetchedReads.take('k', userId: null), (found: false, value: null));

      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: Future.error(Exception('down')));
      expect(await PrefetchedReads.take('k', userId: 'u'), (found: false, value: null));

      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: Future.value(null));
      expect(await PrefetchedReads.take('k', userId: 'u'), (found: false, value: null));

      final late = Completer<Map<String, Object?>?>();
      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: late.future);
      final waiting = PrefetchedReads.take('k', userId: 'u');
      PrefetchedReads.discard(); // a live event or a write while it was on its way
      late.complete({'k': 1});
      expect(await waiting, (found: false, value: null));

      var clock = DateTime(2026, 10, 12, 8);
      PrefetchedReads.now = () => clock;
      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: Future.value({'k': 1, 'j': 2}));
      expect(await PrefetchedReads.take('k', userId: 'u'), (found: true, value: 1));
      clock = clock.add(PrefetchedReads.freshFor + const Duration(seconds: 1));
      expect(await PrefetchedReads.take('j', userId: 'u'), (found: false, value: null), reason: 'too old by now');
    });

    test('a read does not wait for ever for a batch that never answers', () async {
      PrefetchedReads.waitAtMost = const Duration(milliseconds: 50);
      addTearDown(() => PrefetchedReads.waitAtMost = const Duration(seconds: 6));
      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: Completer<Map<String, Object?>?>().future);
      expect(await PrefetchedReads.take('k', userId: 'u'), (found: false, value: null));
    });

    test('a write from this phone drops the batch', () async {
      PrefetchedReads.begin(userId: 'u', covers: (_) => true, answers: Future.value({'k': 1}));
      OwnChanges.begin('subscriptions').done();
      expect(await PrefetchedReads.take('k', userId: 'u'), (found: false, value: null));
    });
  });

  group('OfflineCache.readThrough with a batch', () {
    test('the batch answers the read; the next read asks the server', () async {
      var asked = 0;
      Future<dynamic> ask() async => ++asked;
      PrefetchedReads.begin(userId: 'student-a', covers: (k) => k == 'k', answers: Future.value({'k': 'ahead'}));
      expect(await OfflineCache.readThrough('k', ask), 'ahead');
      expect(asked, 0);
      expect(await OfflineCache.readThrough('k', ask), 1);
      expect(await OfflineCache.readThrough('other', ask), 2, reason: 'not covered: asked as before');
    });

    test('with a saved copy, the copy shows at once and the batch is what checks it', () async {
      await OfflineCache.readThrough('k', () async => 'old'); // saved by an earlier run
      OfflineCache.resetSession();
      var asked = 0;
      PrefetchedReads.begin(userId: 'student-a', covers: (k) => k == 'k', answers: Future.value({'k': 'new'}));
      expect(await OfflineCache.readThrough('k', () async => ++asked), 'old');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(OfflineCache.takeRefreshedKeys(), {'k'}, reason: 'the newer answer is announced');
      expect(await OfflineCache.readThrough('k', () async => ++asked), 'new', reason: 'and shown without a request');
      expect(asked, 0);
    });

    test('a batch that does not answer in time leaves the read its own full time', () async {
      PrefetchedReads.waitAtMost = const Duration(milliseconds: 50);
      final timeout = OfflineCache.requestTimeout;
      OfflineCache.requestTimeout = const Duration(milliseconds: 200);
      addTearDown(() {
        PrefetchedReads.waitAtMost = const Duration(seconds: 6);
        OfflineCache.requestTimeout = timeout;
      });
      PrefetchedReads.begin(userId: 'student-a', covers: (_) => true, answers: Completer<Map<String, Object?>?>().future);
      // 50 ms waited for the batch, then 150 ms for the request: still inside
      // its own 200 ms.
      final value = await OfflineCache.readThrough(
          'k', () => Future<dynamic>.delayed(const Duration(milliseconds: 150), () => 'asked'));
      expect(value, 'asked');
    });

    test('a batch for another account is never used', () async {
      PrefetchedReads.begin(userId: 'student-b', covers: (_) => true, answers: Future.value({'k': 'theirs'}));
      expect(await OfflineCache.readThrough('k', () async => 'mine'), 'mine');
    });
  });

  group('StudentHomeBundle', () {
    test('each part goes to the read it stands for, under that read\'s own name', () async {
      home.answer = _fullAnswer();
      const vote = VoteSettings(opensAt: 14 * 60, closesAt: 7 * 60 + 30);
      StudentHomeBundle.prefetch('student-a', vote: vote);
      final range = homeRideRange(vote, DateTime.now());
      Future<Object?> served(String key) async {
        final hit = await PrefetchedReads.take(key, userId: 'student-a');
        expect(hit.found, isTrue, reason: key);
        return hit.value;
      }

      expect(await served('profile.summary'), {'id': 'student-a', 'full_name': 'أحمد'});
      expect(await served('subscriptions'), hasLength(1));
      expect((await served('subscriptions.current') as Map)['id'], 'sub-1');
      expect((await served('vote_settings.co-1') as Map)['opens_at'], '14:00');
      expect(await served(rideDaysKey(range.start, range.end)), hasLength(1));
      expect(await served('receipts.sub-1'), hasLength(1));
      expect(await served('notifications.page'), isA<Map>());
      expect(await served('offers'), {'hidden': false, 'offers': []});
      expect(await served('recap.releases'), isEmpty);
      expect(await served('invites'), isEmpty);
      expect(await served('line_supervisors'), hasLength(1));
      expect(await served('boarded_rides'), 7);
      expect(home.calls, 1);
      expect(home.asked?.rideFrom, range.start.toIso8601String().substring(0, 10));
      expect(home.asked?.rideTo, range.end.toIso8601String().substring(0, 10));
      expect(home.asked?.today, DateTime.now().toIso8601String().substring(0, 10));
    });

    test('no current subscription: the platform\'s vote settings, no receipts', () async {
      home.answer = {..._fullAnswer(), 'current': null, 'vote_company': null, 'receipts_of': null, 'receipts': []};
      StudentHomeBundle.prefetch('student-a', vote: VoteSettings.fallback);
      expect((await PrefetchedReads.take('vote_settings.platform', userId: 'student-a')).found, isTrue);
      expect((await PrefetchedReads.take('vote_settings.co-1', userId: 'student-a')).found, isFalse);
      expect((await PrefetchedReads.take('receipts.sub-1', userId: 'student-a')).found, isFalse);
      expect(await PrefetchedReads.take('subscriptions.current', userId: 'student-a'), (found: true, value: null));
    });

    test('opened with the saved vote settings, as the home screen opens', () async {
      // Saved by the last run: the current subscription and its company's settings.
      await OfflineCache.readThrough('subscriptions.current', () async => {'id': 'sub-1', 'company_id': 'co-1'});
      await OfflineCache.readThrough(
          'vote_settings.co-1', () async => {'opens_at': '12:00', 'closes_at': '09:00', 'reminder_minutes': 0});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      OfflineCache.resetSession();
      home.answer = _fullAnswer();
      StudentHomeBundle.prefetch('student-a');
      await PrefetchedReads.take('profile.summary', userId: 'student-a');
      final saved = VoteSettings.fromJson({'opens_at': '12:00', 'closes_at': '09:00', 'reminder_minutes': 0});
      final range = homeRideRange(saved, DateTime.now());
      expect(home.asked?.rideFrom, range.start.toIso8601String().substring(0, 10));
    });

    test('a refused or failed request, or an answer it does not know, leaves every read to itself', () async {
      for (final setUpGateway in <void Function()>[
        () => home.fails = Exception('PGRST202: Could not find the function public.get_student_home'),
        () => home.fails = TimeoutException('slow'),
        () => home.answer = {'v': 2, 'profile': {}},
        () => home.answer = null,
      ]) {
        home
          ..fails = null
          ..answer = null;
        setUpGateway();
        StudentHomeBundle.prefetch('student-a', vote: VoteSettings.fallback);
        var asked = 0;
        expect(await OfflineCache.readThrough('profile.summary', () async => {'asked': ++asked}), {'asked': 1});
        expect(await StudentHomeBundle.answerOr('invites', () async => 'asked'), 'asked');
      }
    });

    test('reads made without OfflineCache take their part too', () async {
      home.answer = _fullAnswer();
      StudentHomeBundle.prefetch('student-a', vote: VoteSettings.fallback);
      var asked = 0;
      expect(await StudentHomeBundle.answerOr('boarded_rides', () async => ++asked), 7);
      expect(await StudentHomeBundle.answerOr('boarded_rides', () async => ++asked), 1, reason: 'once only');
    });
  });
}
