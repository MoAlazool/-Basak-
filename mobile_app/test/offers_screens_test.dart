// «عروض باصك» on screen: the strip on Home, the page of all offers, one offer
// in full, the coupon at the till, the switch on the account page, and the
// way in from a notification.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:basak_mobile/core/storage/offline_cache.dart';
import 'package:basak_mobile/core/theme/app_icons.dart';
import 'package:basak_mobile/core/ui/ui.dart';
import 'package:basak_mobile/features/notifications/data/notifications_repository.dart';
import 'package:basak_mobile/features/notifications/notification_router.dart';
import 'package:basak_mobile/features/notifications/push/push_providers.dart';
import 'package:basak_mobile/features/student/daily_ride/data/daily_ride_repository.dart';
import 'package:basak_mobile/features/student/daily_ride/models/vote_settings.dart';
import 'package:basak_mobile/features/student/home/data/line_supervisors.dart';
import 'package:basak_mobile/features/student/home/presentation/ride_card.dart';
import 'package:basak_mobile/features/student/home/presentation/student_home_screen.dart';
import 'package:basak_mobile/features/student/invites/invites.dart';
import 'package:basak_mobile/features/student/offers/offer_coupon_screen.dart';
import 'package:basak_mobile/features/student/offers/offer_details_screen.dart';
import 'package:basak_mobile/features/student/offers/offer_widgets.dart';
import 'package:basak_mobile/features/student/offers/offers_repository.dart';
import 'package:basak_mobile/features/student/offers/offers_screen.dart';
import 'package:basak_mobile/features/student/offers/offers_strip.dart';
import 'package:basak_mobile/features/student/profile/presentation/profile_screen.dart';
import 'package:basak_mobile/features/student/qr/presentation/student_qr_screen.dart';
import 'package:basak_mobile/features/student/student_main_screen.dart';
import 'package:basak_mobile/features/student/subscription/models/subscription_model.dart';
import 'package:basak_mobile/features/student/subscription/presentation/subscription_screen.dart'
    show SubscriptionScreen, allSubscriptionsProvider, paymentMethodsProvider, subscriptionReceiptsProvider;

import 'support/notification_fakes.dart';
import 'support/offer_fakes.dart';
import 'support/perf_fakes.dart' show onePixel;

class _Sub extends CurrentSubscriptionNotifier {
  final SubscriptionModel? sub;
  _Sub(this.sub);

  @override
  Future<SubscriptionModel?> build() async => sub;
}

/// Open all day, whatever the hour the test runs at.
const _open = VoteSettings(opensAt: 0, closesAt: 0);

class _Rides implements DailyRideRepository {
  @override
  Future<VoteSettings> getVoteSettings(String? companyId) async => _open;

  @override
  Future<RideDays> getRides(DateTime start, DateTime end) async => const RideDays({});

  @override
  Future<DailyRideDetails> confirmRide({
    required DateTime rideDate,
    required bool isRiding,
    required String? departureTime,
    required String? returnTime,
    required bool isReturning,
  }) async =>
      DailyRideDetails(
          isRiding: isRiding, departureTime: departureTime, returnTime: returnTime, isReturning: isReturning);
}

class _Invites implements InvitesGateway {
  @override
  Future<dynamic> myInvites() async => const <dynamic>[];

  @override
  Future<dynamic> respond(String inviteId, bool accept) async => {'note': null};
}

final _active = SubscriptionModel(
  id: 'sub',
  studentId: 'student-1',
  lineId: 'l',
  stationId: 'st',
  type: 'termly',
  status: 'active',
  price: 4500,
  createdAt: '2026-09-01',
  startDate: '2020-01-01',
  endDate: '2099-12-31',
  lineName: 'الزرقا',
  stationName: 'كوبري السرو',
  departureTimes: const ['06:38', '07:23', '08:08'],
  returnTimes: const ['12:30', '15:30'],
  supervisorName: 'محمود السيد',
  supervisorPhone: '01011223344',
  studentUniversity: 'جامعة المنصورة الجديدة',
  companyName: 'النورس للنقل',
  periodCode: 'first',
  periodPhase: 'current',
);

/// What Home reads, over the fake offers server.
List<Override> _homeOverrides(FakeOffersGateway gateway, TestClock clock,
    {bool subscribed = true, Map<String, dynamic>? profile}) {
  final sub = subscribed ? _active : null;
  return [
      ...offerOverrides(gateway, clock, profile: profile),
      subscriptionReceiptsProvider.overrideWith((ref, id) async => const []),
      allSubscriptionsProvider.overrideWith((ref) async => [if (sub != null) sub]),
      paymentMethodsProvider.overrideWith((ref, id) async => const []),
      currentSubscriptionProvider.overrideWith(() => _Sub(sub)),
      voteSettingsProvider.overrideWith((ref) async => _open),
      dailyRideRepoProvider.overrideWithValue(_Rides()),
      invitesGatewayProvider.overrideWithValue(_Invites()),
      notificationsRepoProvider.overrideWithValue(FakeNotificationsRepo()),
      lineSupervisorsProvider.overrideWith((ref) async => const <LineSupervisor>[]),
    ];
}

Widget _home(FakeOffersGateway gateway, TestClock clock, {bool subscribed = true, double textScale = 1}) =>
    offersApp(
      Scaffold(body: StudentHomeScreen(onNavigateToSubscription: () {}, onNavigateToQr: () {})),
      _homeOverrides(gateway, clock, subscribed: subscribed),
      textScale: textScale,
    );

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A few frames: requests answered, a page pushed and settled. (Never
/// pumpAndSettle near a coupon: its bar does not stop moving.)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The page's own back button (the newest page's, when several are open).
Future<void> _back(WidgetTester tester) =>
    tester.tap(find.widgetWithIcon(BasakIconButton, LucideIcons.arrowRight).last);

/// A picture the phone cannot load (no connection, a file that is gone).
class _Broken extends ImageProvider<_Broken> {
  const _Broken();

  @override
  Future<_Broken> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Broken key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.error(StateError('no picture')));
}

Finder _pinField() =>
    find.descendant(of: find.byKey(const Key('coupon-pin')), matching: find.byType(TextField));

void main() {
  late FakeOffersGateway gateway;
  late TestClock clock;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    OfflineCache.markOnline();
    gateway = FakeOffersGateway();
    clock = TestClock();
  });
  tearDown(OfflineCache.markOnline);

  group('the strip on Home', () {
    testWidgets('with offers: «عروض لك» after the ride card and before the supervisor', (tester) async {
      _phone(tester, const Size(400, 1700));
      gateway.answer = offersJson([offerJson(1, title: 'خصم على المشروبات'), offerJson(2, special: true)]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);

      final strip = find.byKey(const Key('offers-strip'));
      expect(strip, findsOneWidget);
      expect(find.text('عروض لك'), findsOneWidget);
      expect(find.text('كل العروض'), findsOneWidget);
      expect(find.text('خصم على المشروبات'), findsOneWidget);
      expect(find.text('خاص لك'), findsOneWidget);
      expect(tester.getRect(strip).top, greaterThan(tester.getRect(find.byType(RideCard)).bottom));
      expect(tester.getRect(find.byKey(const Key('supervisor-card'))).top, greaterThan(tester.getRect(strip).bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no offers, hidden by the student, or a server without them: no strip and no error',
        (tester) async {
      _phone(tester, const Size(400, 1700));
      final cases = <String, void Function()>{
        'no offers': () => gateway.answer = offersJson([]),
        'hidden': () => gateway.answer = offersJson([offerJson(1)], hidden: true),
        'unavailable': () => gateway.failure = noSuchFunction,
        'unreadable': () => gateway.answer = 'x',
      };
      for (final entry in cases.entries) {
        gateway = FakeOffersGateway();
        entry.value();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_home(gateway, clock));
        await _settle(tester);
        expect(gateway.reads, 1, reason: entry.key);
        expect(find.byKey(const Key('offers-strip')), findsNothing, reason: entry.key);
        expect(find.text('عروض لك'), findsNothing, reason: entry.key);
        expect(find.byType(RideCard), findsOneWidget, reason: entry.key);
        expect(find.byKey(const Key('supervisor-card')), findsOneWidget, reason: entry.key);
        expect(find.byType(PageError), findsNothing, reason: entry.key);
        expect(gateway.seenCalls, isEmpty, reason: entry.key);
        expect(tester.takeException(), isNull, reason: entry.key);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('five cards at most, the special offers first with their mark', (tester) async {
      _phone(tester, const Size(400, 1700));
      gateway.answer = offersJson([
        for (var n = 1; n <= 8; n++) offerJson(n, title: 'العرض $n', special: n == 4 || n == 7),
      ]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);

      for (final n in [4, 7, 1, 2, 3]) {
        expect(find.text('العرض $n'), findsOneWidget, reason: '$n');
      }
      for (final n in [5, 6, 8]) {
        expect(find.text('العرض $n'), findsNothing, reason: '$n');
      }
      expect(find.text('خاص لك'), findsNWidgets(2));
      // In Arabic the first card is the one at the right.
      double right(int n) => tester.getRect(find.text('العرض $n')).right;
      expect(right(4), greaterThan(right(7)));
      expect(right(7), greaterThan(right(1)));
      expect(right(1), greaterThan(right(2)));
      expect(right(2), greaterThan(right(3)));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('one offer takes the width of the page', (tester) async {
      _phone(tester, const Size(400, 1700));
      gateway.answer = offersJson([offerJson(1, title: 'العرض الوحيد')]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);
      final card = tester.getRect(find.ancestor(of: find.text('العرض الوحيد'), matching: find.byType(BasakCard)));
      expect(card.width, 400 - 2 * BasakSpace.gutter);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the cards in front of the student are told to the server once, together', (tester) async {
      _phone(tester, const Size(400, 1700));
      gateway.answer = offersJson([for (var n = 1; n <= 5; n++) offerJson(n, title: 'العرض $n')]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);
      // The first card, and the second, more than half of which is in view.
      expect(gateway.seenCalls, [
        [offerUuid(1), offerUuid(2)],
      ]);

      // Nothing new is in view: rebuilding and refreshing tell nothing again.
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(gateway.seenCalls, hasLength(1));

      // The student slides the strip: the cards that come into view, once.
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byKey(const Key('offers-strip-scroll')), const Offset(150, 0));
        await _settle(tester);
      }
      final told = [for (final call in gateway.seenCalls) ...call];
      expect(told.toSet(), {for (var n = 1; n <= 5; n++) offerUuid(n)});
      expect(told, hasLength(5), reason: 'no offer twice');
      final calls = gateway.seenCalls.length;
      await tester.drag(find.byKey(const Key('offers-strip-scroll')), const Offset(-1200, 0));
      await _settle(tester);
      expect(gateway.seenCalls, hasLength(calls));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pulling Home down reads the offers again', (tester) async {
      _phone(tester, const Size(400, 900));
      gateway.answer = offersJson([offerJson(1, title: 'العرض القديم')]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);
      expect(gateway.reads, 1);

      gateway.answer = offersJson([]);
      await tester.fling(find.byType(RideCard), const Offset(0, 400), 1200);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(gateway.reads, 2);
      expect(find.byKey(const Key('offers-strip')), findsNothing, reason: 'the last offer ended');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('«كل العروض» opens the page; a card opens its offer', (tester) async {
      _phone(tester, const Size(400, 1700));
      gateway.answer = offersJson([offerJson(1, title: 'خصم على المشروبات'), offerJson(2)]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('offers-all')));
      await _settle(tester);
      expect(find.byType(OffersScreen), findsOneWidget);
      expect(find.text('عروض باصك'), findsOneWidget);
      await _back(tester);
      await _settle(tester);

      await tester.tap(find.text('خصم على المشروبات'));
      await _settle(tester);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(gateway.openedCalls, [offerUuid(1)]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the offers page', () {
    Future<void> open(WidgetTester tester, {Size size = const Size(400, 2400)}) async {
      _phone(tester, size);
      await tester.pumpWidget(offersApp(const OffersScreen(), offerOverrides(gateway, clock)));
      await _settle(tester);
    }

    testWidgets('a card: the merchant, the value, the title, when it ends, what is left, whether it was used',
        (tester) async {
      gateway.answer = offersJson([
        offerJson(1, title: 'خصم على المشروبات', value: '20%', endsAt: '2026-10-14T18:00:00', left: 5),
        offerJson(2, title: 'قهوة مجانية', value: 'مشروب مجاني', kind: 'gift', used: 1, endsAt: '2026-10-11T22:00:00'),
        offerJson(3, title: 'عرض بلا نهاية', special: true, left: 80),
      ]);
      await open(tester);

      MerchantOfferCard card(String title) => tester.widget(
          find.ancestor(of: find.text(title), matching: find.byType(MerchantOfferCard)));
      Finder inCard(String title, String text) => find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(MerchantOfferCard)), matching: find.text(text));

      expect(find.byType(MerchantOfferCard), findsNWidgets(3));
      expect(find.text('كافيه الجامعة'), findsNWidgets(3));
      expect(card('خصم على المشروبات').offer.id, offerUuid(1));
      expect(inCard('خصم على المشروبات', '20%'), findsWidgets);
      expect(inCard('خصم على المشروبات', 'ينتهي بعد 3 أيام'), findsOneWidget);
      expect(inCard('خصم على المشروبات', 'متبقٍ 5'), findsOneWidget);
      expect(inCard('خصم على المشروبات', 'استخدمته'), findsNothing);

      expect(inCard('قهوة مجانية', 'مشروب مجاني'), findsWidgets);
      expect(inCard('قهوة مجانية', 'ينتهي اليوم'), findsOneWidget);
      expect(inCard('قهوة مجانية', 'استخدمته'), findsOneWidget);

      expect(inCard('عرض بلا نهاية', 'خاص لك'), findsOneWidget);
      expect(find.textContaining('متبقٍ 80'), findsNothing, reason: 'plenty left is not said');
      expect(find.textContaining('ينتهي'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chips are the kinds of place that have offers; one narrows the list', (tester) async {
      gateway.answer = offersJson([
        offerJson(1, title: 'خصم على المشروبات', category: 'food'),
        offerJson(2, title: 'أدوات هندسية', category: 'study', merchant: 'مكتبة الهندسة'),
        offerJson(3, title: 'وجبة الطالب', category: 'food'),
        offerJson(4, title: 'شيء جديد', category: 'something_new', merchant: 'محل جديد'),
      ]);
      await open(tester);
      final chips = tester.widget<BasakChips<OfferCategory?>>(find.byType(BasakChips<OfferCategory?>));
      expect(chips.options, [null, OfferCategory.food, OfferCategory.study, OfferCategory.other]);
      expect(find.text('الكل'), findsOneWidget);
      expect(find.text(OfferCategory.health.label), findsNothing);
      expect(find.byType(MerchantOfferCard), findsNWidgets(4));

      await tester.tap(find.widgetWithText(BasakPressable, OfferCategory.study.label).first);
      await _settle(tester);
      expect(find.byType(MerchantOfferCard), findsOneWidget);
      expect(find.text('أدوات هندسية'), findsOneWidget);
      expect(find.text('خصم على المشروبات'), findsNothing);

      await tester.tap(find.text('الكل'));
      await _settle(tester);
      expect(find.byType(MerchantOfferCard), findsNWidgets(4));
    });

    testWidgets('the chosen kind has nothing any more: said, with the way back to all offers', (tester) async {
      gateway.answer = offersJson([
        offerJson(1, title: 'خصم على المشروبات', category: 'food'),
        offerJson(2, title: 'أدوات هندسية', category: 'study'),
        offerJson(3, title: 'كشف مخفّض', category: 'health'),
      ]);
      await open(tester);
      await tester.tap(find.widgetWithText(BasakPressable, OfferCategory.study.label).first);
      await _settle(tester);
      expect(find.text('أدوات هندسية'), findsOneWidget);

      // The offer ended on the server while the page was open.
      gateway.answer = offersJson([
        offerJson(1, title: 'خصم على المشروبات', category: 'food'),
        offerJson(3, title: 'كشف مخفّض', category: 'health'),
      ]);
      ProviderScope.containerOf(tester.element(find.byType(OffersScreen))).invalidate(offersProvider);
      await _settle(tester);
      expect(find.byKey(const Key('offers-none-here')), findsOneWidget);
      expect(find.text('لا عروض في هذا القسم الآن'), findsOneWidget);
      expect(find.byType(MerchantOfferCard), findsNothing);

      await tester.tap(find.descendant(of: find.byType(EmptyState), matching: find.text('كل العروض')));
      await _settle(tester);
      expect(find.byType(MerchantOfferCard), findsNWidgets(2));
    });

    testWidgets('one kind of place: no chips. No offers, or hidden: the page says so', (tester) async {
      gateway.answer = offersJson([offerJson(1), offerJson(2)]);
      await open(tester);
      expect(find.byType(BasakChips<OfferCategory?>), findsNothing);
      expect(find.byType(MerchantOfferCard), findsNWidgets(2));

      gateway.answer = offersJson([]);
      ProviderScope.containerOf(tester.element(find.byType(OffersScreen))).invalidate(offersProvider);
      await _settle(tester);
      expect(find.byKey(const Key('offers-empty')), findsOneWidget);
      expect(find.text('لا توجد عروض الآن'), findsOneWidget);

      gateway.answer = offersJson([offerJson(1)], hidden: true);
      ProviderScope.containerOf(tester.element(find.byType(OffersScreen))).invalidate(offersProvider);
      await _settle(tester);
      expect(find.byKey(const Key('offers-hidden')), findsOneWidget);
      expect(find.byType(MerchantOfferCard), findsNothing);
    });

    testWidgets('the cards on the page are told as seen, once', (tester) async {
      gateway.answer = offersJson([offerJson(1), offerJson(2)]);
      await open(tester);
      expect(gateway.seenCalls, [
        [offerUuid(1), offerUuid(2)],
      ]);
      await tester.drag(find.byType(MerchantOfferCard).first, const Offset(0, -30));
      await _settle(tester);
      expect(gateway.seenCalls, hasLength(1));
    });
  });

  group('the offer\'s picture', () {
    final shown = <String>[];
    setUp(() {
      shown.clear();
      debugCompanyLogoImage = (url) {
        shown.add(url);
        return MemoryImage(onePixel);
      };
    });
    tearDown(() => debugCompanyLogoImage = null);

    Rect slot(WidgetTester tester, Finder within) =>
        tester.getRect(find.descendant(of: within, matching: find.byType(OfferPicture)));

    testWidgets('on Home\'s cards, on the page\'s cards and at the top of the offer; never decoded at full size',
        (tester) async {
      _phone(tester, const Size(400, 1700));
      gateway.answer = offersJson([
        offerJson(1, title: 'خصم على المشروبات', imagePath: 'offers/${offerUuid(1)}/cover.jpg'),
        offerJson(2, title: 'عرض بلا صورة'),
      ]);
      await tester.pumpWidget(_home(gateway, clock));
      await _settle(tester);

      // The strip: the picture is the top of the card, edge to edge.
      final strip = find.byKey(const Key('offers-strip'));
      final card = find.descendant(
          of: strip, matching: find.ancestor(of: find.text('خصم على المشروبات'), matching: find.byType(BasakCard)));
      final picture = slot(tester, card);
      expect((picture.top, picture.left, picture.right),
          (tester.getRect(card).top, tester.getRect(card).left, tester.getRect(card).right));
      expect(picture.width / picture.height, closeTo(16 / 9, .01));
      expect(picture.bottom, lessThan(tester.getRect(find.text('خصم على المشروبات')).top));
      expect(find.descendant(of: strip, matching: find.byKey(const Key('offer-picture'))), findsOneWidget);
      expect(shown, contains(endsWith('/offer-assets/offers/${offerUuid(1)}/cover.jpg')));
      final image = tester.widget<Image>(find.descendant(of: strip, matching: find.byKey(const Key('offer-picture'))));
      final sized = image.image as ResizeImage;
      expect(sized.height, isNull);
      expect(sized.width, inInclusiveRange(picture.width.ceil(), picture.width.ceil() + 100),
          reason: 'as wide as it is drawn, not as it was uploaded');

      // No picture: the same slot, the same size, with the merchant's mark and the value.
      final plain = find.descendant(
          of: strip, matching: find.ancestor(of: find.text('عرض بلا صورة'), matching: find.byType(BasakCard)));
      expect(slot(tester, plain).size, picture.size);
      final panel = find.descendant(of: plain, matching: find.byKey(const Key('offer-picture-panel')));
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('20%')), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('ك ج')), findsOneWidget);
      expect(find.descendant(of: plain, matching: find.byKey(const Key('offer-picture'))), findsNothing);
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // The page of all offers, then the offer itself.
      await tester.tap(find.byKey(const Key('offers-all')));
      await _settle(tester);
      final rows = find.byType(MerchantOfferCard);
      expect(rows, findsNWidgets(2));
      for (final row in [rows.first, rows.last]) {
        final banner = slot(tester, row);
        expect((banner.top, banner.width), (tester.getRect(row).top, tester.getRect(row).width));
        expect(banner.width / banner.height, closeTo(16 / 9, .01));
      }
      expect(find.descendant(of: rows.first, matching: find.byKey(const Key('offer-picture'))), findsOneWidget);
      expect(find.descendant(of: rows.last, matching: find.byKey(const Key('offer-picture-panel'))), findsOneWidget);

      await tester.tap(find.descendant(of: rows.first, matching: find.text('خصم على المشروبات')));
      await _settle(tester);
      final page = find.byType(OfferDetailsScreen);
      final hero = slot(tester, page);
      expect(find.descendant(of: page, matching: find.byKey(const Key('offer-picture'))), findsOneWidget);
      expect(hero.bottom, lessThan(tester.getRect(find.descendant(of: page, matching: find.text('كافيه الجامعة'))).top),
          reason: 'the picture leads the page');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a path that is not the platform\'s, or a picture that cannot be loaded: the panel, and no error',
        (tester) async {
      _phone(tester, const Size(400, 2400));
      debugCompanyLogoImage = (url) {
        shown.add(url);
        return const _Broken();
      };
      gateway.answer = offersJson([
        offerJson(1, title: 'مسار غريب', imagePath: 'https://evil.example/a.png'),
        offerJson(2, title: 'صورة لا تُحمَّل', imagePath: 'offers/${offerUuid(2)}/gone.png', value: ''),
      ]);
      await tester.pumpWidget(offersApp(const OffersScreen(), offerOverrides(gateway, clock)));
      await _settle(tester);
      final rows = find.byType(MerchantOfferCard);
      expect(shown, [endsWith('/offers/${offerUuid(2)}/gone.png')], reason: 'the foreign address is never asked for');
      expect(slot(tester, rows.first).size, slot(tester, rows.last).size, reason: 'the slot never changes size');
      for (final row in [rows.first, rows.last]) {
        expect(find.descendant(of: row, matching: find.byKey(const Key('offer-picture-panel'))), findsOneWidget);
      }
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('one offer', () {
    Future<void> open(WidgetTester tester, Map<String, dynamic> offer, {Size size = const Size(400, 2400)}) async {
      _phone(tester, size);
      gateway.answer = offersJson([offer]);
      await tester.pumpWidget(offersApp(const OffersScreen(), offerOverrides(gateway, clock)));
      await _settle(tester);
      await tester.tap(find.byType(MerchantOfferCard));
      await _settle(tester);
    }

    testWidgets('what it says, what it asks, how long it runs, and how to reach the merchant', (tester) async {
      debugCompanyLogoImage = (url) => MemoryImage(onePixel);
      addTearDown(() => debugCompanyLogoImage = null);
      await open(
          tester,
          offerJson(1,
              title: 'خصم على المشروبات',
              endsAt: '2026-10-14T18:00:00',
              left: 5,
              limit: 3,
              used: 1,
              imagePath: 'offers/${offerUuid(1)}/cover.jpg'));
      final page = find.byType(OfferDetailsScreen);
      Finder on(String text) => find.descendant(of: page, matching: find.text(text));

      expect(page, findsOneWidget);
      expect(find.byKey(const Key('offer-picture')), findsOneWidget);
      expect(on('كافيه الجامعة'), findsOneWidget);
      expect(on('20%'), findsWidgets);
      expect(on('خصم على المشروبات'), findsOneWidget);
      expect(on('خصم على كل المشروبات الساخنة لطلاب الجامعة.'), findsOneWidget);
      expect(on('الشروط'), findsOneWidget);
      expect(on('مرة واحدة لكل طالب. لا يُجمع مع عروض أخرى.'), findsOneWidget);
      expect(on('14 أكتوبر'), findsOneWidget);
      expect(on('ينتهي بعد 3 أيام'), findsOneWidget);
      expect(on('5'), findsOneWidget);
      expect(on('1 من 3'), findsOneWidget);
      for (final key in ['offer-whatsapp', 'offer-call', 'offer-link', 'offer-address']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(on('cafe.example.com'), findsOneWidget);
      expect(on('شارع الجامعة، أمام البوابة الرئيسية'), findsOneWidget);
      expect(find.byKey(const Key('offer-use')), findsOneWidget);
      expect(find.byKey(const Key('offer-refusal')), findsNothing);
      expect(gateway.openedCalls, [offerUuid(1)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the ways the merchant gave; no picture, no terms, no end: none of them shown',
        (tester) async {
      await open(tester, offerJson(1, phone: null, link: 'not a link', address: null, terms: '', description: ''));
      expect(find.byKey(const Key('offer-whatsapp')), findsOneWidget);
      for (final key in ['offer-call', 'offer-link', 'offer-address', 'offer-picture']) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(find.text('الشروط'), findsNothing);
      expect(find.byType(FactGrid), findsNothing);

      await tester.pumpWidget(const SizedBox());
      gateway = FakeOffersGateway();
      await open(tester, offerJson(2, phone: null, whatsapp: null, link: null, address: null));
      expect(find.text('تواصل مع المحل'), findsNothing);
    });

    testWidgets('an advert has no coupon: no «استخدم العرض», only the merchant\'s contact', (tester) async {
      await open(tester, offerJson(1, kind: 'info', value: 'جديد'));
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(find.byKey(const Key('offer-use')), findsNothing);
      expect(find.text('استخدم العرض'), findsNothing);
      expect(find.byKey(const Key('offer-call')), findsOneWidget);
      expect(find.byType(BasakDock), findsNothing);
    });

    testWidgets('used up, or run out: the button is there, off, with the reason', (tester) async {
      await open(tester, offerJson(1, used: 1));
      expect(find.byKey(const Key('offer-refusal')), findsOneWidget);
      expect(find.text('استخدمت هذا العرض من قبل.'), findsOneWidget);
      expect(tester.widget<BasakButton>(find.byKey(const Key('offer-use'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('offer-use')));
      await _settle(tester);
      expect(find.byType(BasakDialogFrame), findsNothing);
      expect(gateway.redeemed, isEmpty);

      await tester.pumpWidget(const SizedBox());
      gateway = FakeOffersGateway();
      await open(tester, offerJson(2, left: 0));
      expect(find.text('انتهت الكمية المتاحة من هذا العرض.'), findsOneWidget);
      expect(tester.widget<BasakButton>(find.byKey(const Key('offer-use'))).onPressed, isNull);
    });
  });

  group('the coupon', () {
    Future<void> openOffer(WidgetTester tester, Map<String, dynamic> offer,
        {Size size = const Size(400, 1500)}) async {
      _phone(tester, size);
      gateway.answer = offersJson([offer]);
      await tester.pumpWidget(offersApp(const OffersScreen(), offerOverrides(gateway, clock)));
      await _settle(tester);
      await tester.tap(find.byType(MerchantOfferCard));
      await _settle(tester);
    }

    /// «استخدم العرض», then yes to the question.
    Future<void> use(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('offer-use')));
      await _settle(tester);
      expect(find.byType(BasakDialogFrame), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(BasakDialogFrame), matching: find.text('استخدم العرض')));
      await _settle(tester);
    }

    testWidgets('asked first, where the student is told to press only at the till; «إلغاء» asks for nothing',
        (tester) async {
      await openOffer(tester, offerJson(1, minutes: 10));
      await tester.tap(find.byKey(const Key('offer-use')));
      await _settle(tester);
      expect(find.byType(BasakDialogFrame), findsOneWidget);
      expect(find.text('اضغط فقط وأنت عند الكاشير — الكوبون صالح 10 دقائق.'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await _settle(tester);
      expect(gateway.redeemed, isEmpty);
      expect(find.byType(OfferCouponScreen), findsNothing);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
    });

    testWidgets('with a PIN: the code, whose it is, a countdown that ticks, a wrong PIN, then the right one',
        (tester) async {
      await openOffer(tester, offerJson(1, title: 'خصم على المشروبات', needsPin: true));
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(minutes: 10)), needsPin: true);
      gateway.onConfirm = (pin) => pin == '4821' ? {'confirmed': true} : {'confirmed': false, 'tries_left': 3};
      await use(tester);

      expect(gateway.redeemed, [offerUuid(1)]);
      final screen = find.byType(OfferCouponScreen);
      Finder on(String text) => find.descendant(of: screen, matching: find.text(text));
      expect(screen, findsOneWidget);
      expect(on('كافيه الجامعة'), findsOneWidget);
      final card = find.byKey(const Key('coupon-card'));
      Finder onCard(Finder what) => find.descendant(of: card, matching: what);
      expect(card, findsOneWidget);
      expect(onCard(find.text('20%')), findsWidgets);
      expect(onCard(find.text('خصم على المشروبات')), findsOneWidget);
      expect(onCard(find.text('صاحب الكوبون')), findsOneWidget);
      expect(onCard(find.byType(OfferPicture)), findsOneWidget);
      expect(onCard(find.byType(TicketTear)), findsOneWidget);
      // Under the tear: where it stands, the time left, the bar and the code.
      final tear = tester.getRect(find.byType(TicketTear)).bottom;
      for (final key in ['coupon-waiting', 'coupon-countdown', 'coupon-live', 'coupon-code']) {
        expect(onCard(find.byKey(Key(key))), findsOneWidget, reason: key);
        expect(tester.getRect(find.byKey(Key(key))).top, greaterThanOrEqualTo(tear), reason: key);
      }
      // The code is the cashier's reference, no longer the largest thing on the card.
      double size(Finder text) => tester.widget<Text>(text).style!.fontSize!;
      expect(size(find.byKey(const Key('coupon-code'))), lessThan(size(onCard(find.text('20%')).last)));
      // The PIN is typed under the card, not on it.
      expect(onCard(find.byKey(const Key('coupon-pin'))), findsNothing);
      expect(tester.getRect(find.byKey(const Key('coupon-pin'))).top, greaterThan(tester.getRect(card).bottom));
      expect(on('سارة أحمد محمود'), findsOneWidget);
      expect(find.byKey(const Key('coupon-student-photo')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('coupon-code'))).data, 'K 7 M 2 Q P');
      expect(find.byKey(const Key('coupon-used')), findsNothing);

      // The time left is counted down every second.
      Text countdown() => tester.widget<Text>(find.byKey(const Key('coupon-countdown')));
      expect(countdown().data, '10:00');
      clock.forward(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(countdown().data, '09:59');
      clock.forward(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(countdown().data, '09:57');

      // And the bar never stands still.
      Rect mark() => tester.getRect(find.descendant(
          of: find.byKey(const Key('coupon-live')), matching: find.byType(FractionallySizedBox)));
      final before = mark();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mark().left, isNot(before.left));
      final then = mark();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mark().left, isNot(then.left));

      // «تأكيد» waits for four digits.
      BasakButton confirm() => tester.widget<BasakButton>(find.byKey(const Key('coupon-confirm')));
      expect(confirm().onPressed, isNull);
      await tester.enterText(_pinField(), '123');
      await tester.pump();
      expect(confirm().onPressed, isNull);

      // A wrong PIN: said, with the tries that remain; the field is empty again.
      await tester.enterText(_pinField(), '1234');
      await tester.pump();
      await tester.tap(find.byKey(const Key('coupon-confirm')));
      await _settle(tester);
      expect(gateway.pins, [(id: 'coupon-1', pin: '1234')]);
      expect(find.text('رمز غير صحيح — بقي 3 محاولات'), findsOneWidget);
      expect(tester.widget<TextField>(_pinField()).controller!.text, isEmpty);
      expect(find.byKey(const Key('coupon-used')), findsNothing);

      // The right one, typed on an Arabic keyboard.
      final reads = gateway.reads;
      await tester.enterText(_pinField(), '٤٨٢١');
      await tester.pump();
      expect(find.byKey(const Key('coupon-pin-error')), findsNothing);
      await tester.tap(find.byKey(const Key('coupon-confirm')));
      await _settle(tester);
      expect(gateway.pins.last, (id: 'coupon-1', pin: '4821'));
      expect(find.byKey(const Key('coupon-used')), findsOneWidget);
      expect(onCard(find.byKey(const Key('coupon-used'))), findsOneWidget, reason: 'the card itself says it');
      expect(on('تم الاستخدام'), findsOneWidget);
      expect(on('الساعة 12:00 م'), findsOneWidget, reason: 'with the time the cashier confirmed it');
      expect(find.byKey(const Key('coupon-waiting')), findsNothing);
      expect(find.byKey(const Key('coupon-code')), findsOneWidget);
      expect(find.byKey(const Key('coupon-pin')), findsNothing);
      expect(find.byKey(const Key('coupon-confirm')), findsNothing);
      expect(gateway.reads, greaterThan(reads), reason: 'the offers are read again: this one is used');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no tries left: the field waits, and the reason stays', (tester) async {
      await openOffer(tester, offerJson(1, needsPin: true));
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(minutes: 10)), needsPin: true);
      gateway.onConfirm = (_) => {'confirmed': false, 'tries_left': 0};
      await use(tester);
      await tester.enterText(_pinField(), '1111');
      await tester.pump();
      await tester.tap(find.byKey(const Key('coupon-confirm')));
      await _settle(tester);
      expect(find.textContaining('لم تبقَ محاولات'), findsOneWidget);
      expect(tester.widget<BasakButton>(find.byKey(const Key('coupon-confirm'))).onPressed, isNull);

      // What the server says when it refuses is shown as it is.
      await tester.pumpWidget(const SizedBox());
      gateway = FakeOffersGateway();
      await openOffer(tester, offerJson(1, needsPin: true));
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(minutes: 10)), needsPin: true);
      gateway.onConfirm = (_) => throw refusal('محاولات كثيرة. اطلب كوبوناً جديداً بعد انتهاء هذا.');
      await use(tester);
      await tester.enterText(_pinField(), '1111');
      await tester.pump();
      await tester.tap(find.byKey(const Key('coupon-confirm')));
      await _settle(tester);
      expect(find.text('محاولات كثيرة. اطلب كوبوناً جديداً بعد انتهاء هذا.'), findsOneWidget);
    });

    testWidgets('without a PIN it is used at once: said, with the code still there for the cashier',
        (tester) async {
      await openOffer(tester, offerJson(1));
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(minutes: 10)), confirmed: true);
      final reads = gateway.reads;
      await use(tester);
      expect(find.byType(OfferCouponScreen), findsOneWidget);
      expect(find.byKey(const Key('coupon-used')), findsOneWidget);
      expect(find.text('تم الاستخدام'), findsOneWidget);
      expect(find.text('الساعة 12:00 م'), findsOneWidget, reason: 'used when the coupon was made');
      expect(find.text('أرِ هذه البطاقة للكاشير قبل انتهاء الوقت.'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('coupon-code'))).data, 'K 7 M 2 Q P');
      expect(find.byKey(const Key('coupon-countdown')), findsOneWidget);
      expect(find.byKey(const Key('coupon-pin')), findsNothing);
      expect(gateway.reads, greaterThan(reads));
    });

    testWidgets('its minutes run out: said, and a new coupon can be asked for', (tester) async {
      await openOffer(tester, offerJson(1, needsPin: true, minutes: 5));
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(minutes: 5)), needsPin: true);
      await use(tester);
      expect(tester.widget<Text>(find.byKey(const Key('coupon-countdown'))).data, '05:00');

      clock.forward(const Duration(minutes: 5, seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byKey(const Key('coupon-expired')), findsOneWidget);
      expect(find.text('انتهت مدة الكوبون'), findsOneWidget);
      expect(find.byKey(const Key('coupon-code')), findsNothing);
      expect(find.byKey(const Key('coupon-pin')), findsNothing);
      // The card is still there, gone quiet, with the way to a new one on it.
      expect(find.byKey(const Key('coupon-card')), findsOneWidget);
      expect(find.byKey(const Key('coupon-countdown')), findsNothing);
      expect(find.byKey(const Key('coupon-live')), findsNothing);
      expect(tester.widget<OfferPicture>(find.byType(OfferPicture)).muted, isTrue);
      expect(
          find.descendant(of: find.byKey(const Key('coupon-card')), matching: find.byKey(const Key('coupon-renew'))),
          findsOneWidget);

      gateway.onRedeem =
          (_) => couponJson(clock.now.add(const Duration(minutes: 5)), id: 'coupon-2', code: 'ZX84RT', needsPin: true);
      await tester.tap(find.byKey(const Key('coupon-renew')));
      await _settle(tester);
      expect(gateway.redeemed, [offerUuid(1), offerUuid(1)]);
      expect(tester.widget<Text>(find.byKey(const Key('coupon-code'))).data, 'Z X 8 4 R T');
      expect(find.byKey(const Key('coupon-pin')), findsOneWidget);
      expect(find.byKey(const Key('coupon-expired')), findsNothing);

      // A new one the server refuses: its words, and the page stays as it is.
      clock.forward(const Duration(minutes: 6));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      gateway.onRedeem = (_) => throw refusal('انتهت الكمية المتاحة من هذا العرض.');
      await tester.tap(find.byKey(const Key('coupon-renew')));
      await _settle(tester);
      expect(find.text('انتهت الكمية المتاحة من هذا العرض.'), findsOneWidget);
      expect(find.byKey(const Key('coupon-expired')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a phone whose clock is wrong never shows more time than a coupon is given', (tester) async {
      await openOffer(tester, offerJson(1, minutes: 10));
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(hours: 3)), confirmed: true);
      await use(tester);
      expect(tester.widget<Text>(find.byKey(const Key('coupon-countdown'))).data, '10:00');
    });

    testWidgets('the server refuses (already used): its words are shown, and no coupon opens', (tester) async {
      await openOffer(tester, offerJson(1));
      gateway.onRedeem = (_) => throw refusal('استخدمت هذا العرض من قبل.');
      final reads = gateway.reads;
      await use(tester);
      expect(gateway.redeemed, [offerUuid(1)]);
      expect(find.text('استخدمت هذا العرض من قبل.'), findsOneWidget);
      expect(find.byType(OfferCouponScreen), findsNothing);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(gateway.reads, greaterThan(reads), reason: 'what the offer says of itself was out of date');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('an offer with a coupon still running opens straight on that coupon', (tester) async {
      await openOffer(
          tester,
          offerJson(1,
              needsPin: true,
              coupon: couponJson(clock.now.add(const Duration(minutes: 4, seconds: 30)), code: 'RUN123')));
      expect(find.byType(OfferCouponScreen), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('coupon-code'))).data, 'R U N 1 2 3');
      expect(tester.widget<Text>(find.byKey(const Key('coupon-countdown'))).data, '04:30');
      expect(find.byKey(const Key('coupon-pin')), findsOneWidget);
      expect(gateway.redeemed, isEmpty, reason: 'no second coupon is asked for');

      // Back: the offer, whose button leads to the same coupon without asking.
      await _back(tester);
      await _settle(tester);
      expect(find.byType(OfferCouponScreen), findsNothing);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(find.text('عرض الكوبون'), findsOneWidget);
      await tester.tap(find.byKey(const Key('offer-use')));
      await _settle(tester);
      expect(find.byType(BasakDialogFrame), findsNothing);
      expect(find.byType(OfferCouponScreen), findsOneWidget);
      expect(gateway.redeemed, isEmpty);
    });

    testWidgets('a coupon whose minutes ran out since the offers were read is not gone back to', (tester) async {
      await openOffer(tester, offerJson(1, coupon: couponJson(clock.now.subtract(const Duration(seconds: 5)))));
      expect(find.byType(OfferCouponScreen), findsNothing);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(find.text('استخدم العرض'), findsOneWidget);
    });
  });

  testWidgets('the account page has no switch for offers', (tester) async {
    _phone(tester, const Size(400, 1400));
    PackageInfo.setMockInitialValues(
        appName: 'باصك', packageName: 'basak', version: '1.0.6', buildNumber: '35', buildSignature: '');
    await tester.pumpWidget(offersApp(
      const Scaffold(body: ProfileScreen()),
      _homeOverrides(gateway, clock, profile: {'full_name': 'سارة أحمد محمود', 'phone': '01023456789'}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('إظهار العروض'), findsNothing);
    expect(find.byKey(const Key('profile-offers')), findsNothing);
  });

  group('from a notification', () {
    Future<NotificationRouter> shell(WidgetTester tester) async {
      _phone(tester, const Size(400, 900));
      PackageInfo.setMockInitialValues(
          appName: 'باصك', packageName: 'basak', version: '1.0.6', buildNumber: '35', buildSignature: '');
      final router = NotificationRouter(currentUserId: () => 'student-1');
      await tester.pumpWidget(offersApp(
        const StudentMainScreen(),
        [
          ..._homeOverrides(gateway, clock),
          notificationRouterProvider.overrideWithValue(router),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return router;
    }

    NotificationIntent special(String id, String? offerId) => NotificationIntent.fromPush({
          'notification_id': id, 'type': 'offer.special', 'route': 'offers',
          if (offerId != null) 'offer_id': offerId,
        });

    testWidgets('«عرض خاص لك»: the offers page over Home, and on it the offer it is about', (tester) async {
      gateway.answer = offersJson([offerJson(1), offerJson(2, title: 'عرض خاص بك', special: true)]);
      final router = await shell(tester);
      final reads = gateway.reads;

      expect(router.open(special('n1', offerUuid(2)), NotificationTapSource.push), isTrue);
      await _settle(tester);
      expect(gateway.reads, greaterThan(reads), reason: 'the offer may be newer than what the phone holds');
      expect(find.byType(OffersScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(tester.widget<OfferDetailsScreen>(find.byType(OfferDetailsScreen)).offer.id, offerUuid(2));
      expect(find.byType(StudentQrScreen), findsNothing, reason: 'Home is the tab under it, not the card');

      // Back from the offer: the page of all offers; back again: Home.
      await _back(tester);
      await _settle(tester);
      expect(find.byType(OfferDetailsScreen), findsNothing);
      expect(find.byType(OffersScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an offer that is no longer the student\'s: the page alone', (tester) async {
      gateway.answer = offersJson([offerJson(1)]);
      final router = await shell(tester);
      router.open(special('n1', offerUuid(9)), NotificationTapSource.push);
      await _settle(tester);
      expect(find.byType(OffersScreen), findsOneWidget);
      expect(find.byType(OfferDetailsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('offers hidden, or a server without them: Home stays, and nothing is said', (tester) async {
      gateway.answer = offersJson([offerJson(1)], hidden: true);
      final router = await shell(tester);
      router.open(special('n1', offerUuid(1)), NotificationTapSource.push);
      await _settle(tester);
      expect(find.byType(OffersScreen), findsNothing);
      expect(find.byType(StudentHomeScreen), findsOneWidget);

      gateway
        ..answer = null
        ..failure = noSuchFunction;
      router.open(special('n2', offerUuid(1)), NotificationTapSource.push);
      await _settle(tester);
      expect(find.byType(OffersScreen), findsNothing);
      expect(find.byType(StudentHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('offers are on Home only: never on the card or the subscription tab', (tester) async {
      gateway.answer = offersJson([offerJson(1, title: 'خصم على المشروبات')]);
      await shell(tester);
      // Long enough for the other tabs to be built behind Home.
      await tester.pump(const Duration(milliseconds: 1300));
      await _settle(tester);
      Finder inTab(Type tab, Finder what) =>
          find.descendant(of: find.byType(tab, skipOffstage: false), matching: what, skipOffstage: false);
      expect(find.byType(StudentQrScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(SubscriptionScreen, skipOffstage: false), findsOneWidget);
      for (final tab in [StudentQrScreen, SubscriptionScreen]) {
        expect(inTab(tab, find.byType(OffersStrip, skipOffstage: false)), findsNothing, reason: '$tab');
        expect(inTab(tab, find.text('عروض لك', skipOffstage: false)), findsNothing, reason: '$tab');
      }
      expect(inTab(StudentHomeScreen, find.byType(OffersStrip, skipOffstage: false)), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('a small phone at the largest text', () {
    const small = Size(360, 640);
    final long = offerJson(1,
        title: 'خصم خاص لطلاب الجامعة على كل المشروبات الساخنة والباردة والحلويات',
        value: 'مشروب مجاني مع كل وجبة',
        merchant: 'كافيه ومطعم الجامعة الأهلية الجديدة بالمنصورة',
        special: true,
        needsPin: true,
        left: 3,
        limit: 4,
        used: 1,
        endsAt: '2026-10-11T23:00:00',
        description: 'خصم على كل المشروبات الساخنة والباردة لطلاب الجامعة طوال أيام الدراسة، من الأحد إلى الخميس.',
        terms: 'مرة واحدة في اليوم لكل طالب. لا يُجمع مع عروض أخرى. يُشترط إظهار الكوبون قبل الطلب.',
        link: 'https://www.a-very-long-merchant-domain-name.example.com/students/offers',
        address: 'شارع الجامعة، أمام البوابة الرئيسية، بجوار مكتبة الطالب، الدور الأرضي');

    testWidgets('the strip on Home', (tester) async {
      _phone(tester, small);
      gateway.answer = offersJson([
        long,
        offerJson(2, title: 'قهوة', value: '', merchant: ''),
        offerJson(3, used: 1, endsAt: '2026-11-30T10:00:00', left: 9),
      ]);
      await tester.pumpWidget(_home(gateway, clock, textScale: 1.3));
      await _settle(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('offers-strip')), 200,
          scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      expect(find.byKey(const Key('offers-strip')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byKey(const Key('offers-strip-scroll')), const Offset(500, 0));
      await _settle(tester);
      expect(tester.takeException(), isNull);

      // A single offer, and Home without a subscription.
      await tester.pumpWidget(const SizedBox());
      gateway.answer = offersJson([long]);
      await tester.pumpWidget(_home(gateway, clock, subscribed: false, textScale: 1.3));
      await _settle(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('offers-strip')), 200,
          scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the page, one offer and the coupon', (tester) async {
      _phone(tester, small);
      gateway.answer = offersJson([
        long,
        offerJson(2, category: 'study', merchant: 'مكتبة الهندسة', used: 1),
        offerJson(3, category: 'health', kind: 'info', value: ''),
        offerJson(4, category: 'shopping'),
        offerJson(5, category: 'services'),
        offerJson(6, category: 'other'),
      ]);
      await tester.pumpWidget(offersApp(const OffersScreen(), offerOverrides(gateway, clock), textScale: 1.3));
      await _settle(tester);
      expect(find.byType(BasakChips<OfferCategory?>), findsOneWidget);
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -900));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(list, const Offset(0, 2000));
      await _settle(tester);

      // The offer in full, to its last row.
      await tester.ensureVisible(find.text(long['title'] as String));
      await _settle(tester);
      await tester.tap(find.text(long['title'] as String));
      await _settle(tester);
      expect(find.byType(OfferDetailsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      final details = find.descendant(of: find.byType(OfferDetailsScreen), matching: find.byType(Scrollable)).first;
      await tester.drag(details, const Offset(0, -1500));
      await _settle(tester);
      expect(find.byKey(const Key('offer-address')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The question, then the coupon with its PIN.
      gateway.onRedeem = (_) => couponJson(clock.now.add(const Duration(minutes: 10)), needsPin: true);
      gateway.onConfirm = (_) => {'confirmed': false, 'tries_left': 2};
      await tester.tap(find.byKey(const Key('offer-use')));
      await _settle(tester);
      expect(find.byType(BasakDialogFrame), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.descendant(of: find.byType(BasakDialogFrame), matching: find.text('استخدم العرض')));
      await _settle(tester);
      expect(find.byType(OfferCouponScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      final coupon = find.descendant(of: find.byType(OfferCouponScreen), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const Key('coupon-confirm')), 150, scrollable: coupon);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(_pinField(), '123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('coupon-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('coupon-pin-error')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Used, and then run out.
      gateway.onConfirm = (_) => {'confirmed': true};
      await tester.enterText(_pinField(), '4821');
      await tester.pump();
      await tester.tap(find.byKey(const Key('coupon-confirm')));
      await _settle(tester);
      await tester.drag(coupon, const Offset(0, 1500));
      await _settle(tester);
      expect(find.byKey(const Key('coupon-used')), findsOneWidget);
      expect(tester.takeException(), isNull);
      clock.forward(const Duration(minutes: 11));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('تم الاستخدام'), findsOneWidget);
      expect(find.byKey(const Key('coupon-countdown')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a coupon that ran out before it was used', (tester) async {
      _phone(tester, small);
      final offer = Offer.tryParse(long)!;
      final coupon = OfferCoupon(id: 'c', code: 'K7M2QP', expiresAt: clock.now.add(const Duration(seconds: 2)));
      await tester.pumpWidget(offersApp(
          OfferCouponScreen(offer: offer, coupon: coupon),
          offerOverrides(gateway, clock, profile: {'full_name': 'محمد عادل فؤاد عبد الرحمن العزول'}),
          textScale: 1.3));
      await _settle(tester);
      expect(find.byKey(const Key('coupon-code')), findsOneWidget);
      expect(tester.takeException(), isNull);
      clock.forward(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byKey(const Key('coupon-expired')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
