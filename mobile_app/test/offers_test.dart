// «عروض باصك» without a screen: what the server's answer is read as, when the
// feature does not exist at all, what is told to the server and how often,
// and what a change on the server reads again.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/sync/session.dart';
import 'package:basak_mobile/core/sync/sync_hub.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/features/auth/models/user_role.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/presentation/notification_style.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/offers/offer_coupon_screen.dart';
import 'package:basak_mobile/features/student/offers/offer_details_screen.dart';
import 'package:basak_mobile/features/student/offers/offers_repository.dart';
import 'package:basak_mobile/features/student/offers/offers_strip.dart';

import 'support/notification_fakes.dart';
import 'support/offer_fakes.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final noon = DateTime(2026, 10, 11, 12);

  group('what the server sends', () {
    test('an offer is read whole', () {
      final state = OffersState.tryParse(offersJson([
        offerJson(1,
            title: 'خصم على المشروبات',
            special: true,
            needsPin: true,
            minutes: 15,
            limit: 3,
            used: 1,
            left: 12,
            endsAt: '2026-10-14T20:00:00Z',
            imagePath: 'offers/${offerUuid(1)}/cover.webp',
            logoPath: 'merchants/${offerUuid(901)}/logo.png',
            coupon: couponJson(noon.add(const Duration(minutes: 5)))),
      ]))!;
      expect(state.available, isTrue);
      expect(state.hidden, isFalse);
      final offer = state.offers.single;
      expect(offer.id, offerUuid(1));
      expect((offer.title, offer.valueLabel, offer.kind), ('خصم على المشروبات', '20%', OfferKind.percent));
      expect((offer.special, offer.needsPin, offer.couponMinutes), (true, true, 15));
      expect((offer.perStudentLimit, offer.used, offer.left), (3, 1, 12));
      expect(offer.endsAt, DateTime.utc(2026, 10, 14, 20).toLocal());
      expect(offer.merchant.name, 'كافيه الجامعة');
      expect(offer.merchant.category, OfferCategory.food);
      expect(offer.merchant.link, Uri.parse('https://cafe.example.com/menu'));
      expect(offer.coupon!.code, 'K7M2QP');
      expect(offer.runningCoupon(noon), isNotNull);
      expect(offer.runningCoupon(noon.add(const Duration(minutes: 6))), isNull, reason: 'its minutes ran out');
      expect(offer.imageUrl, endsWith('/storage/v1/object/public/offer-assets/offers/${offerUuid(1)}/cover.webp'));
      expect(offer.merchant.logoUrl, endsWith('/offer-assets/merchants/${offerUuid(901)}/logo.png'));
      expect(state.find(offerUuid(1)), same(offer));
      expect(state.find('nothing'), isNull);
      expect(state.find(null), isNull);
    });

    test('a kind or a category this version does not know never breaks the list', () {
      final state = OffersState.tryParse(offersJson([
        offerJson(1, kind: 'cashback', category: 'travel'),
        offerJson(2, kind: 'info', category: 'study'),
        offerJson(3, kind: 'gift'),
        offerJson(4, kind: 'amount'),
      ]))!;
      expect([for (final o in state.offers) o.kind],
          [OfferKind.percent, OfferKind.info, OfferKind.gift, OfferKind.amount]);
      expect(state.offers.first.merchant.category, OfferCategory.other);
      expect(state.offers.first.isInfo, isFalse, reason: 'shown like a coupon offer');
      expect(state.categories, [OfferCategory.food, OfferCategory.study, OfferCategory.other]);
    });

    test('everything optional may be missing or null', () {
      final offer = Offer.tryParse({'id': 'o1', 'title': 'عرض'})!;
      expect((offer.description, offer.terms, offer.valueLabel), ('', '', ''));
      expect((offer.imageUrl, offer.endsAt, offer.left, offer.coupon), (null, null, null, null));
      expect((offer.couponMinutes, offer.perStudentLimit, offer.used), (10, 1, 0));
      expect(offer.merchant.name, '');
      expect(offer.merchant.hasContact, isFalse);
      expect(offer.endsLabel(noon), isNull);
      expect(offer.leftLabel, isNull);

      final nulls = Offer.tryParse(offerJson(2, phone: null, whatsapp: null, link: null, address: null)
        ..addAll({'description': null, 'terms': null, 'value_label': null, 'merchant': null}))!;
      expect((nulls.description, nulls.terms, nulls.valueLabel, nulls.merchant.category),
          ('', '', '', OfferCategory.other));
    });

    test('what is not an offer is left out; what is not an answer is no answer', () {
      final state = OffersState.tryParse({
        'hidden': false,
        'offers': [
          offerJson(1),
          {'title': 'بلا رقم'},
          {'id': 'x'},
          'نص',
          null,
        ],
      })!;
      expect(state.offers.map((o) => o.id), [offerUuid(1)]);
      for (final junk in [null, 'x', 3, <dynamic>[], <String, dynamic>{}, {'offers': 'x'}]) {
        expect(OffersState.tryParse(junk), isNull, reason: '$junk');
      }
    });

    test('hidden by the student: no offers, and Home has nothing to show', () {
      final state = OffersState.tryParse({'hidden': true, 'offers': [offerJson(1)]})!;
      expect((state.available, state.hidden, state.shows), (true, true, false));
      expect(state.offers, isEmpty);
      expect(OffersState.tryParse(offersJson([]))!.shows, isFalse);
      expect(OffersState.tryParse(offersJson([offerJson(1)]))!.shows, isTrue);
      expect(OffersState.unavailable.shows, isFalse);
    });

    test('a picture is only ever read from where the platform puts them', () {
      final id = offerUuid(7);
      expect(OfferAssets.url('offers/$id/a.png', base: 'https://x.co'),
          'https://x.co/storage/v1/object/public/offer-assets/offers/$id/a.png');
      expect(OfferAssets.url('merchants/$id/logo-2.JPG'.toLowerCase(), base: 'https://x.co'), isNotNull);
      for (final bad in [
        null,
        '',
        'https://evil.example/a.png',
        'offers/$id/../../secret.png',
        'offers/$id/a.svg',
        'offers/not-a-uuid/a.png',
        'students/$id/a.png',
        'offers/$id/a.png?x=1',
        '/offers/$id/a.png',
      ]) {
        expect(OfferAssets.url(bad, base: 'https://x.co'), isNull, reason: '$bad');
      }
    });

    test('the merchant\'s link is opened only when it is a web address', () {
      OfferMerchant of(String? link) => OfferMerchant.fromJson({'name': 'م', 'link_url': link});
      expect(of('https://shop.example.com').link, isNotNull);
      expect(of('http://shop.example.com/x').link, isNotNull);
      for (final bad in [null, '', 'shop.example.com', 'javascript:alert(1)', 'tel:0100', 'file:///etc/passwd']) {
        expect(of(bad).link, isNull, reason: '$bad');
      }
    });
  });

  group('a coupon\'s time left', () {
    final answer = {
      'id': 'c1',
      'code': 'ABC234',
      'expires_at': '2026-10-11T12:10:00Z',
      'seconds_left': 600,
      'confirmed': false,
    };

    test('a fresh answer counts from the server\'s seconds, whatever the phone\'s clock says', () {
      // This phone is three hours ahead of the server.
      final now = DateTime.utc(2026, 10, 11, 15);
      final coupon = OfferCoupon.tryParse(answer, now: now)!;
      expect(coupon.expiresAt, now.add(const Duration(minutes: 10)));
      expect(coupon.runningAt(now), isTrue);
    });

    test('a saved answer, or an older server, goes by the end it names', () {
      final named = DateTime.utc(2026, 10, 11, 12, 10);
      expect(OfferCoupon.tryParse(answer)!.expiresAt.isAtSameMomentAs(named), isTrue);
      final old = {...answer}..remove('seconds_left');
      expect(OfferCoupon.tryParse(old, now: DateTime.utc(2026, 10, 11, 15))!.expiresAt.isAtSameMomentAs(named), isTrue);
    });
  });

  group('what a card says', () {
    Offer ending(DateTime? at) => Offer(id: 'o', title: 't', endsAt: at);

    test('when it ends', () {
      expect(ending(null).endsLabel(noon), isNull);
      expect(ending(DateTime(2026, 10, 11, 23)).endsLabel(noon), 'ينتهي اليوم');
      expect(ending(DateTime(2026, 10, 12, 1)).endsLabel(noon), 'ينتهي غداً');
      expect(ending(DateTime(2026, 10, 13, 9)).endsLabel(noon), 'ينتهي بعد يومين');
      expect(ending(DateTime(2026, 10, 14, 9)).endsLabel(noon), 'ينتهي بعد 3 أيام');
      expect(ending(DateTime(2026, 10, 21, 9)).endsLabel(noon), 'ينتهي بعد 10 أيام');
      expect(ending(DateTime(2026, 10, 26, 9)).endsLabel(noon), 'ينتهي بعد 15 يوماً');
      expect(ending(DateTime(2026, 12, 31, 9)).endsLabel(noon), 'حتى 31 ديسمبر');
      expect(ending(DateTime(2026, 10, 11, 11)).endsLabel(noon), 'انتهى');
    });

    test('«استخدمته» once the student has no use left; «متبقٍ N» only when few remain', () {
      const once = Offer(id: 'o', title: 't', used: 1);
      expect((once.usedUp, once.refusal), (true, 'استخدمت هذا العرض من قبل.'));
      const thrice = Offer(id: 'o', title: 't', used: 2, perStudentLimit: 3);
      expect((thrice.usedUp, thrice.refusal), (false, null));
      const advert = Offer(id: 'o', title: 't', kind: OfferKind.info, used: 5);
      expect(advert.usedUp, isFalse);

      expect(const Offer(id: 'o', title: 't', left: 20).leftLabel, 'متبقٍ 20');
      expect(const Offer(id: 'o', title: 't', left: 3).leftLabel, 'متبقٍ 3');
      expect(const Offer(id: 'o', title: 't', left: 21).leftLabel, isNull);
      expect(const Offer(id: 'o', title: 't').leftLabel, isNull);
      const gone = Offer(id: 'o', title: 't', left: 0);
      expect((gone.leftLabel, gone.soldOut, gone.refusal), (null, true, 'انتهت الكمية المتاحة من هذا العرض.'));
    });

    test('Home shows five at most, the special ones first, each group in the server\'s order', () {
      final offers = [
        for (var n = 1; n <= 8; n++) Offer(id: 'o$n', title: 't$n', special: n == 4 || n == 7),
      ];
      expect(OffersStrip.shownOf(offers).map((o) => o.id), ['o4', 'o7', 'o1', 'o2', 'o3']);
      expect(OffersStrip.shownOf(offers.take(2).toList()).map((o) => o.id), ['o1', 'o2']);
      expect(OffersStrip.shownOf(const []), isEmpty);
    });

    test('the words around the coupon', () {
      expect(OfferDetailsScreen.confirmMessage(const Offer(id: 'o', title: 't', couponMinutes: 10)),
          'اضغط فقط وأنت عند الكاشير — الكوبون صالح 10 دقائق.');
      expect(OfferDetailsScreen.confirmMessage(const Offer(id: 'o', title: 't', couponMinutes: 15)),
          'اضغط فقط وأنت عند الكاشير — الكوبون صالح 15 دقيقة.');
      expect(OfferCouponScreen.wrongPin(4), 'رمز غير صحيح — بقي 4 محاولات');
      expect(OfferCouponScreen.wrongPin(3), 'رمز غير صحيح — بقي 3 محاولات');
      expect(OfferCouponScreen.wrongPin(2), 'رمز غير صحيح — بقيت محاولتان');
      expect(OfferCouponScreen.wrongPin(1), 'رمز غير صحيح — بقيت محاولة واحدة');
      expect(OfferCouponScreen.wrongPin(0), contains('لم تبقَ محاولات'));
      expect(OfferCouponScreen.clock(const Duration(minutes: 9, seconds: 58)), '09:58');
      expect(OfferCouponScreen.clock(const Duration(seconds: 7)), '00:07');
      expect(OfferCouponScreen.clock(const Duration(hours: 1, minutes: 2, seconds: 7)), '1:02:07');
      expect(OfferCouponScreen.clock(const Duration(seconds: -4)), '00:00');
    });
  });

  group('the repository', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      OfflineCache.debugUserId = 'student-offers';
      OfflineCache.resetSession();
      OfflineCache.markOnline();
    });
    tearDown(() {
      OfflineCache.debugUserId = null;
      OfflineCache.markOnline();
    });

    test('a server without the function: the feature does not exist, and nothing is thrown', () async {
      final gateway = FakeOffersGateway()..failure = noSuchFunction;
      final state = await OffersRepository(gateway: gateway).load();
      expect((state.available, state.shows), (false, false));
      expect(state.offers, isEmpty);
      expect(gateway.reads, 1);

      // And it is not asked again on every refresh in this run of the app.
      final repo = OffersRepository(gateway: gateway);
      expect((await repo.load()).available, isFalse);
      expect((await repo.load()).available, isFalse);
      expect(gateway.reads, 2);
    });

    test('no connection and nothing saved, or an answer that cannot be read: the same', () async {
      final offline = FakeOffersGateway()..failure = const SocketException('Failed host lookup');
      expect((await OffersRepository(gateway: offline).load()).available, isFalse);
      OfflineCache.debugUserId = 'student-b';
      expect((await OffersRepository(gateway: FakeOffersGateway('nonsense')).load()).available, isFalse);
      OfflineCache.debugUserId = 'student-c';
      final broken = FakeOffersGateway()..failure = StateError('boom');
      expect((await OffersRepository(gateway: broken).load()).available, isFalse);
    });

    test('without a connection the saved copy is served: later in the run, and on the next start', () async {
      final gateway = FakeOffersGateway(offersJson([offerJson(1), offerJson(2, special: true)]));
      final repo = OffersRepository(gateway: gateway);
      expect((await repo.load()).offers, hasLength(2));
      await _settle();
      expect(await OfflineCache.peek(OffersRepository.cacheKey), isNotNull);

      gateway.failure = const SocketException('Failed host lookup');
      final later = await repo.load();
      expect(later.available, isTrue);
      expect(later.offers.map((o) => o.id), [offerUuid(1), offerUuid(2)]);
      expect(OfflineCache.offlineSince.value, isNotNull, reason: 'the page says it shows saved data');

      // The app was closed and opened again, still offline.
      OfflineCache.resetSession();
      OfflineCache.markOnline();
      final restarted = await OffersRepository(gateway: gateway).load();
      expect(restarted.offers, hasLength(2));
      expect(restarted.offers.last.special, isTrue);
    });

    test('offers taken off the server do not outlive it in the saved copy', () async {
      final gateway = FakeOffersGateway(offersJson([offerJson(1)]));
      expect((await OffersRepository(gateway: gateway).load()).shows, isTrue);
      await _settle();

      // The next start: the saved copy shows at once, the server says there is
      // no such function, and what shows it is told to read again.
      OfflineCache.resetSession();
      gateway.failure = noSuchFunction;
      final repo = OffersRepository(gateway: gateway);
      expect((await repo.load()).shows, isTrue);
      await _settle();
      expect(OfflineCache.takeRefreshedKeys(), contains(OffersRepository.cacheKey));
      expect((await repo.load()).available, isFalse);
      expect(await OfflineCache.peek(OffersRepository.cacheKey), isNull);
    });

    test('impressions: each offer once in a run of the app, the new ones in one request', () async {
      final gateway = FakeOffersGateway();
      final repo = OffersRepository(gateway: gateway);
      repo.seen(['a', 'b', 'c']);
      repo.seen(['a', 'b', 'c']);
      repo.seen(['b', 'd']);
      repo.seen(const []);
      await _settle();
      expect(gateway.seenCalls, [
        ['a', 'b', 'c'],
        ['d'],
      ]);
    });

    test('an impression that could not be told is never an error, and is told the next time', () async {
      final gateway = FakeOffersGateway()..seenFailure = const SocketException('offline');
      final repo = OffersRepository(gateway: gateway);
      repo.seen(['a']);
      await _settle();
      gateway.seenFailure = null;
      repo.seen(['a']);
      await _settle();
      expect(gateway.seenCalls, [
        ['a'],
        ['a'],
      ]);
    });

    test('opening an offer\'s page is told once', () async {
      final gateway = FakeOffersGateway();
      final repo = OffersRepository(gateway: gateway);
      repo
        ..opened('a')
        ..opened('a')
        ..opened('b');
      await _settle();
      expect(gateway.openedCalls, ['a', 'b']);
    });

    test('a coupon: read from the answer; a refusal is thrown in the server\'s own words', () async {
      final expires = DateTime.utc(2026, 10, 11, 10, 10);
      final gateway = FakeOffersGateway()..onRedeem = (_) => couponJson(expires, needsPin: true);
      final repo = OffersRepository(gateway: gateway);
      final coupon = await repo.redeem('o1');
      expect((coupon.id, coupon.code, coupon.confirmed), ('coupon-1', 'K7M2QP', false));
      expect(coupon.expiresAt.toUtc(), expires);

      gateway.onRedeem = (_) => throw refusal('استخدمت هذا العرض من قبل.');
      await expectLater(repo.redeem('o1'),
          throwsA(isA<Exception>().having((e) => '$e', 'message', 'Exception: استخدمت هذا العرض من قبل.')));

      gateway.onRedeem = (_) => throw noSuchFunction;
      await expectLater(repo.redeem('o1'),
          throwsA(isA<Exception>().having((e) => '$e', 'message', contains(OffersRepository.notAvailable))));

      gateway.onRedeem = (_) => {'unexpected': true};
      await expectLater(repo.redeem('o1'),
          throwsA(isA<Exception>().having((e) => '$e', 'message', contains(OffersRepository.noCoupon))));

      gateway.onRedeem = (_) => throw const SocketException('offline');
      await expectLater(
          repo.redeem('o1'), throwsA(isA<Exception>().having((e) => '$e', 'message', contains('لا يوجد اتصال'))));
    });

    test('the merchant\'s PIN: counted, or wrong with the tries that remain', () async {
      final gateway = FakeOffersGateway()
        ..onConfirm = (pin) => pin == '4821' ? {'confirmed': true} : {'confirmed': false, 'tries_left': 3};
      final repo = OffersRepository(gateway: gateway);
      expect(await repo.confirm('c1', '0000'), (confirmed: false, triesLeft: 3));
      expect(await repo.confirm('c1', '4821'), (confirmed: true, triesLeft: 0));
      expect(gateway.pins, [(id: 'c1', pin: '0000'), (id: 'c1', pin: '4821')]);
    });

    test('hiding offers is written into what the phone holds: the re-read asks nothing', () async {
      final gateway = FakeOffersGateway(offersJson([offerJson(1)]));
      final repo = OffersRepository(gateway: gateway);
      expect((await repo.load()).shows, isTrue);
      await _settle();
      expect(await repo.setHidden(true), isTrue);
      final hidden = await repo.load();
      expect((hidden.available, hidden.hidden), (true, true));
      expect(hidden.offers, isEmpty);
      expect(gateway.reads, 1);
      expect(gateway.hides, [true]);

      // Shown again: the offers have to come from the server.
      expect(await repo.setHidden(false), isFalse);
      expect((await repo.load()).shows, isTrue);
      expect(gateway.reads, 2);
    });
  });

  group('the provider', () {
    test('a signed-in student\'s offers are read; with nobody signed in nothing is asked', () async {
      final gateway = FakeOffersGateway(offersJson([offerJson(1)]));
      final container = ProviderContainer(overrides: offerOverrides(gateway, TestClock()));
      addTearDown(container.dispose);
      expect((await container.read(offersProvider.future)).shows, isTrue);
      expect(gateway.reads, 1);

      final nobody = ProviderContainer(overrides: [
        ...offerOverrides(gateway, TestClock()),
        sessionUserIdProvider.overrideWithValue(null),
      ]..removeAt(0));
      addTearDown(nobody.dispose);
      expect((await nobody.read(offersProvider.future)).available, isFalse);
      expect(gateway.reads, 1);
    });
  });

  group('a notification', () {
    test('the route `offers` leads to the offers; the offer it is about comes with it', () {
      expect(NotificationDestination.parse('offers'), NotificationDestination.offers);
      final intent = NotificationIntent.fromPush({
        'notification_id': 'n1', 'type': 'offer.special', 'route': 'offers', 'offer_id': offerUuid(3),
      });
      expect(intent.destination, NotificationDestination.offers);
      expect(intent.offerId, offerUuid(3));
      expect(NotificationIntent.fromPush(const {'route': 'offers'}).offerId, isNull);
    });

    test('the student\'s shell has the offers; a supervisor\'s opens the Notification Center', () {
      NotificationIntent tap(String id) =>
          NotificationIntent.fromPush({'notification_id': id, 'route': 'offers', 'offer_id': 'o1'});
      final student = FakeShell({...NotificationDestination.values});
      NotificationRouter(currentUserId: () => 'a')
        ..attach('a', student)
        ..open(tap('n1'), NotificationTapSource.push);
      expect(student.shown, [NotificationDestination.offers]);
      expect(student.intents.single.offerId, 'o1');

      final supervisor = FakeShell(const {NotificationDestination.home, NotificationDestination.center});
      final router = NotificationRouter(currentUserId: () => 'a')..attach('a', supervisor);
      expect(router.staysInCenter(tap('n2')), isTrue);
      router.open(tap('n2'), NotificationTapSource.push);
      expect(supervisor.shown, [NotificationDestination.center]);
    });

    test('«عرض خاص لك» has its own glyph', () {
      final style = notificationStyle('offer.special', NotificationCategory.announcement);
      expect(style.icon, LucideIcons.gift);
      expect(style.icon, isNot(notificationStyle('announcement.other', NotificationCategory.announcement).icon));
    });
  });

  group('keeping offers current', () {
    test('a change to the offers re-reads the offers, and nothing else', () {
      final stale = <ProviderOrFamily>[];
      SyncScope.invalidateFor(stale.add, const {'offers'}, UserRole.student, 'u1');
      expect(stale, [offersProvider]);

      final supervisor = <ProviderOrFamily>[];
      SyncScope.invalidateFor(supervisor.add, const {'offers'}, UserRole.supervisor, 's1');
      expect(supervisor, isEmpty);
    });

    test('the live event of an offer is an offers change', () {
      expect(SyncScope.tableOf({'table': 'offers', 'op': 'UPDATE'}), 'offers');
      expect(
          SyncScope.tableOf({
            'event': 'change',
            'payload': {'table': 'offers', 'op': 'INSERT'},
          }),
          'offers');
    });

    test('with other changes in the same burst, both are re-read', () {
      final stale = <ProviderOrFamily>[];
      SyncScope.invalidateFor(stale.add, const {'offers', 'subscriptions'}, UserRole.student, 'u1');
      expect(stale, containsAll([offersProvider, currentSubscriptionProvider]));

      // Other tables leave the offers alone.
      final other = <ProviderOrFamily>[];
      SyncScope.invalidateFor(other.add, const {'subscriptions', 'notifications'}, UserRole.student, 'u1');
      expect(other, isNot(contains(offersProvider)));
    });

    test('a saved copy that turned out stale re-reads the offers only', () {
      expect(SyncScope.tablesFor('offers'), {'offers'});
      expect(SyncScope.providerFor('offers', 'u1'), offersProvider);
      expect(SyncScope.providerFor('offers', null), offersProvider);
    });
  });
}
