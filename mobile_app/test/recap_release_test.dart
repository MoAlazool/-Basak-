// The recap is shown when the platform publishes it, whatever the date: the
// owner chooses the moment. (Before, Home also waited for the term's last two
// weeks, so a recap published in the middle of a term never appeared.)
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/features/student/recap/recap_engine.dart';
import 'package:basak_mobile/features/student/recap/recap_repository.dart';

import 'support/recap_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A term from September to the end of January, looked at in October.
  final from = DateTime.utc(2026, 9, 5), to = DateTime.utc(2027, 1, 30);
  final october = DateTime.utc(2026, 10, 11);
  final rides = [for (var d = 0; d < 12; d++) DateTime.utc(2026, 9, 6 + d)];
  Map<String, dynamic> answer({bool? published, DateTime? today}) => recapJson(
        rides: rides, from: from, to: to, today: today ?? october,
      )..addAll({if (published != null) 'published': published});

  group('the banner', () {
    test('published in the middle of the term: shown at once', () {
      final recap = recapOf(answer(published: true))!;
      expect(recapWindowOpen(october, to), isFalse, reason: 'the dates alone would not show it yet');
      expect(recap.bannerOpen(), isTrue);
    });

    test('not published: hidden, in the middle of the term and in its last weeks', () {
      expect(recapOf(answer(published: false))!.bannerOpen(), isFalse);
      expect(recapOf(answer(published: false, today: DateTime.utc(2027, 1, 25)))!.bannerOpen(), isFalse);
    });

    test('published: it stays to four weeks past the end of the term, and no longer', () {
      expect(recapOf(answer(published: true, today: DateTime.utc(2027, 2, 27)))!.bannerOpen(), isTrue);
      expect(recapOf(answer(published: true, today: DateTime.utc(2027, 3, 1)))!.bannerOpen(), isFalse);
    });

    test('a server that does not say: the dates alone, as before', () {
      expect(recapOf(answer())!.bannerOpen(), isFalse);
      expect(recapOf(answer(today: DateTime.utc(2027, 1, 25)))!.bannerOpen(), isTrue);
    });
  });

  group('which term to ask for', () {
    setUp(() {
      OfflineCache.debugUserId = 'student-recap';
      OfflineCache.resetSession();
    });
    tearDown(() => OfflineCache.debugUserId = null);

    const term = (subscriptionId: 'sub-1', end: null);
    RecapTerm current() => (subscriptionId: term.subscriptionId, end: to);

    test('outside the window nothing is asked for unless the platform has a recap out', () async {
      var asked = 0;
      Future<bool> published(bool value) async {
        asked++;
        return value;
      }

      expect(await RecapGate.resolveWith(october, current(), () => published(false)), isNull);
      expect(asked, 1);
      final found = await RecapGate.resolveWith(october, current(), () => published(true));
      expect(found?.subscriptionId, 'sub-1');
    });

    test('inside the window the term is asked for without checking for a release', () async {
      var asked = 0;
      final found = await RecapGate.resolveWith(DateTime.utc(2027, 1, 25), current(), () async {
        asked++;
        return false;
      });
      expect(found?.subscriptionId, 'sub-1');
      expect(asked, 0);
    });

    test('no term subscription, or one long over: nothing, and no release check', () async {
      var asked = 0;
      Future<bool> published() async {
        asked++;
        return true;
      }

      expect(await RecapGate.resolveWith(october, null, published), isNull);
      expect(await RecapGate.resolveWith(DateTime.utc(2027, 6, 1), current(), published), isNull);
      expect(asked, 0);
    });
  });

  group('whether a recap is out', () {
    setUp(() {
      OfflineCache.debugUserId = 'student-recap';
      OfflineCache.resetSession();
    });
    tearDown(() => OfflineCache.debugUserId = null);

    Future<bool> out(Object? rows) =>
        TermRecapRepository(fetch: (_) async => null, releases: () async => rows).anyPublished();

    test('published and not withdrawn', () async {
      expect(await out([{'academic_year': 2026, 'period_code': 'first', 'published_at': '2026-10-11T11:47:59Z', 'unpublished_at': null}]), isTrue);
    });

    test('withdrawn, never published, or no rows', () async {
      OfflineCache.debugUserId = 'student-b';
      expect(await out([{'published_at': '2026-10-01T00:00:00Z', 'unpublished_at': '2026-10-02T00:00:00Z'}]), isFalse);
      OfflineCache.debugUserId = 'student-c';
      expect(await out([{'published_at': null, 'unpublished_at': null}]), isFalse);
      OfflineCache.debugUserId = 'student-d';
      expect(await out(<dynamic>[]), isFalse);
    });

    test('a database without the table, or no connection: not out, and no error', () async {
      final repo = TermRecapRepository(fetch: (_) async => null, releases: () async => throw Exception('42P01'));
      expect(await repo.anyPublished(), isFalse);
    });
  });

  test('a saved recap that turned out stale re-reads the recap only, not everything', () {
    expect(SyncScope.tablesFor('recap.sub-1'), {'recap'});
    expect(SyncScope.tablesFor('recap.releases'), {'recap'});
  });
}
