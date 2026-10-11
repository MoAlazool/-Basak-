import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_config.dart';
import '../../../core/network/network_errors.dart';
import '../../../core/network/perf_trace.dart';
import '../../../core/network/supabase_service.dart';
import '../../../core/storage/offline_cache.dart';
import '../../../core/sync/session.dart';
import '../../../core/widgets/basak_ui.dart';

/// What an offer gives. [info] is an advert: no coupon, only the merchant's
/// contact. A kind this version does not know is shown as a coupon offer.
enum OfferKind {
  percent,
  amount,
  gift,
  info;

  static OfferKind parse(Object? value) => switch (value) {
        'amount' => OfferKind.amount,
        'gift' => OfferKind.gift,
        'info' => OfferKind.info,
        _ => OfferKind.percent,
      };
}

/// What kind of place the merchant is; the offers page filters by it. A
/// category this version does not know is [other].
enum OfferCategory {
  food('مطاعم وكافيهات'),
  study('أدوات ودراسة'),
  services('خدمات'),
  health('صحة'),
  shopping('تسوّق'),
  other('أخرى');

  final String label;
  const OfferCategory(this.label);

  static OfferCategory parse(Object? value) {
    for (final category in values) {
      if (category.name == value) return category;
    }
    return OfferCategory.other;
  }
}

/// Pictures of offers and merchants: object names in the public
/// `offer-assets` bucket, written by the platform only.
abstract final class OfferAssets {
  static const bucket = 'offer-assets';

  /// A name as the server makes it: whose picture, its id, and the file.
  /// Nothing else is ever put into an address.
  static final _path = RegExp(r'^(offers|merchants)/[0-9a-f-]{36}/[A-Za-z0-9_.-]{1,80}\.(png|jpg|jpeg|webp)$');

  static bool isValidPath(String? path) => path != null && _path.hasMatch(path);

  /// The picture's address, or null: no picture.
  static String? url(String? path, {String? base}) => isValidPath(path)
      ? '${base ?? SupabaseConfig.supabaseUrl}/storage/v1/object/public/$bucket/$path'
      : null;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value, int fallback) => value is num ? value.toInt() : fallback;

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Who an offer is from, and how to reach them.
@immutable
class OfferMerchant {
  final String id;
  final String name;
  final OfferCategory category;
  final String? logoPath;
  final String? phone;
  final String? whatsapp;
  final String? linkUrl;
  final String? address;

  const OfferMerchant({
    this.id = '',
    this.name = '',
    this.category = OfferCategory.other,
    this.logoPath,
    this.phone,
    this.whatsapp,
    this.linkUrl,
    this.address,
  });

  factory OfferMerchant.fromJson(Object? json) {
    if (json is! Map) return const OfferMerchant();
    return OfferMerchant(
      id: _text(json['id']) ?? '',
      name: _text(json['name']) ?? '',
      category: OfferCategory.parse(json['category']),
      logoPath: _text(json['logo_path']),
      phone: _text(json['phone']),
      whatsapp: _text(json['whatsapp']),
      linkUrl: _text(json['link_url']),
      address: _text(json['address']),
    );
  }

  String? get logoUrl => OfferAssets.url(logoPath);

  /// The merchant's page, when it is a web address; anything else is not opened.
  Uri? get link {
    final uri = Uri.tryParse(linkUrl ?? '');
    return uri != null && uri.host.isNotEmpty && (uri.scheme == 'https' || uri.scheme == 'http') ? uri : null;
  }

  bool get hasContact => phone != null || whatsapp != null || link != null || address != null;
}

/// The coupon a student shows at the till.
@immutable
class OfferCoupon {
  final String id;
  final String code;
  final DateTime expiresAt;

  /// Counted as a use: at once when the offer has no PIN, else when the
  /// merchant typed theirs.
  final bool confirmed;

  const OfferCoupon({required this.id, required this.code, required this.expiresAt, this.confirmed = false});

  /// From `{id, code, expires_at, seconds_left, confirmed}`, or null when it
  /// cannot be read. With [now] (an answer that has just arrived) the end is
  /// counted from the server's `seconds_left`, so a phone whose clock is wrong
  /// still shows the right time left. A saved answer has no such moment.
  static OfferCoupon? tryParse(Object? json, {DateTime? now}) {
    if (json is! Map) return null;
    final id = _text(json['id']), code = _text(json['code']);
    final left = json['seconds_left'];
    final expires = now != null && left is int && left >= 0
        ? now.add(Duration(seconds: left))
        : _time(json['expires_at']);
    if (id == null || code == null || expires == null) return null;
    return OfferCoupon(id: id, code: code, expiresAt: expires, confirmed: json['confirmed'] == true);
  }

  bool runningAt(DateTime now) => expiresAt.isAfter(now);

  OfferCoupon asConfirmed() => OfferCoupon(id: id, code: code, expiresAt: expiresAt, confirmed: true);
}

/// One offer as the server hands it to this student.
@immutable
class Offer {
  final String id;
  final String title;
  final String description;
  final String terms;
  final String? imagePath;
  final OfferKind kind;

  /// As shown on the card: «20%», «50 ج.م», «مشروب مجاني».
  final String valueLabel;
  final DateTime? endsAt;

  /// «خاص لك»: shown first.
  final bool special;
  final bool needsPin;
  final int couponMinutes;
  final int perStudentLimit;

  /// This student's confirmed uses.
  final int used;

  /// What remains of the offer's total; null when it has none.
  final int? left;

  /// The student's last coupon, as long as the server still counted it as
  /// running when this was read (see [runningCoupon]).
  final OfferCoupon? coupon;
  final OfferMerchant merchant;

  const Offer({
    required this.id,
    required this.title,
    this.description = '',
    this.terms = '',
    this.imagePath,
    this.kind = OfferKind.percent,
    this.valueLabel = '',
    this.endsAt,
    this.special = false,
    this.needsPin = false,
    this.couponMinutes = 10,
    this.perStudentLimit = 1,
    this.used = 0,
    this.left,
    this.coupon,
    this.merchant = const OfferMerchant(),
  });

  /// An offer without an id or a title is not one: null.
  static Offer? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']), title = _text(json['title']);
    if (id == null || title == null) return null;
    final left = json['left'];
    return Offer(
      id: id,
      title: title,
      description: _text(json['description']) ?? '',
      terms: _text(json['terms']) ?? '',
      imagePath: _text(json['image_path']),
      kind: OfferKind.parse(json['kind']),
      valueLabel: _text(json['value_label']) ?? '',
      endsAt: _time(json['ends_at']),
      special: json['special'] == true,
      needsPin: json['needs_pin'] == true,
      couponMinutes: _int(json['coupon_minutes'], 10).clamp(1, 60),
      perStudentLimit: _int(json['per_student_limit'], 1).clamp(1, 100),
      used: _int(json['used'], 0),
      left: left is num ? left.toInt() : null,
      coupon: OfferCoupon.tryParse(json['coupon']),
      merchant: OfferMerchant.fromJson(json['merchant']),
    );
  }

  String? get imageUrl => OfferAssets.url(imagePath);

  /// An advert: nothing to redeem.
  bool get isInfo => kind == OfferKind.info;

  /// «استخدمته»: the student has no use of it left.
  bool get usedUp => !isInfo && used >= perStudentLimit;

  /// Nothing remains of the offer's total.
  bool get soldOut => left != null && left! <= 0;

  /// «متبقٍ N»: said only when few remain.
  static const fewLeft = 20;
  String? get leftLabel => left != null && left! > 0 && left! <= fewLeft ? 'متبقٍ $left' : null;

  /// Why «استخدم العرض» cannot be pressed, in the server's own words; null
  /// when it can.
  String? get refusal {
    if (usedUp) return 'استخدمت هذا العرض من قبل.';
    if (soldOut) return 'انتهت الكمية المتاحة من هذا العرض.';
    return null;
  }

  /// The coupon still to show at the till, by this phone's clock.
  OfferCoupon? runningCoupon(DateTime now) => coupon != null && coupon!.runningAt(now) ? coupon : null;

  /// «ينتهي اليوم», «ينتهي غداً», «ينتهي بعد 3 أيام», and past a month the
  /// date itself; null for an offer without an end.
  String? endsLabel(DateTime now) {
    final end = endsAt;
    if (end == null) return null;
    if (!end.isAfter(now)) return 'انتهى';
    final days = DateTime(end.year, end.month, end.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return 'ينتهي اليوم';
    if (days == 1) return 'ينتهي غداً';
    if (days == 2) return 'ينتهي بعد يومين';
    if (days <= 10) return 'ينتهي بعد $days أيام';
    if (days <= 30) return 'ينتهي بعد $days يوماً';
    return 'حتى ${end.day} ${BasakUi.arabicMonths[end.month - 1]}';
  }
}

/// What the student has of offers right now.
@immutable
class OffersState {
  /// False where the feature does not exist for this phone: a server without
  /// it, or nothing known yet. Nothing about offers is then shown anywhere.
  final bool available;

  /// The student's own switch («إظهار العروض» off).
  final bool hidden;

  /// Already filtered to this student and ordered, the special ones first.
  final List<Offer> offers;

  const OffersState({this.available = true, this.hidden = false, this.offers = const []});

  static const unavailable = OffersState(available: false);

  /// From `{hidden, offers: […]}`; anything else is null. An offer that cannot
  /// be read is left out.
  static OffersState? tryParse(Object? json) {
    if (json is! Map) return null;
    final list = json['offers'];
    if (list is! List) return null;
    final offers = [for (final item in list) Offer.tryParse(item)].whereType<Offer>().toList();
    return OffersState(hidden: json['hidden'] == true, offers: json['hidden'] == true ? const [] : offers);
  }

  /// Whether Home has anything to show.
  bool get shows => available && !hidden && offers.isNotEmpty;

  Offer? find(String? id) {
    for (final offer in offers) {
      if (offer.id == id) return offer;
    }
    return null;
  }

  /// The categories that have offers, in the enum's order.
  List<OfferCategory> get categories {
    final present = {for (final offer in offers) offer.merchant.category};
    return [for (final category in OfferCategory.values) if (present.contains(category)) category];
  }
}

/// What the merchant's PIN did: counted, or wrong with [triesLeft] to go.
typedef PinAnswer = ({bool confirmed, int triesLeft});

/// The requests behind offers, one method each (see ProfileGateway).
abstract class OffersGateway {
  Future<dynamic> myOffers();
  Future<void> seen(List<String> ids);
  Future<void> opened(String id);
  Future<dynamic> redeem(String offerId);
  Future<dynamic> confirm(String redemptionId, String pin);
  Future<dynamic> setHidden(bool hidden);
}

class SupabaseOffersGateway implements OffersGateway {
  const SupabaseOffersGateway();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<dynamic> myOffers() {
    PerfTrace.count('offers.mine');
    return _client.rpc('get_my_offers');
  }

  @override
  Future<void> seen(List<String> ids) async {
    PerfTrace.count('offers.seen');
    await _client.rpc('offer_seen', params: {'p_ids': ids});
  }

  @override
  Future<void> opened(String id) async {
    PerfTrace.count('offers.opened');
    await _client.rpc('offer_opened', params: {'p_id': id});
  }

  @override
  Future<dynamic> redeem(String offerId) {
    PerfTrace.count('offers.redeem');
    return _client.rpc('redeem_offer', params: {'p_offer': offerId});
  }

  @override
  Future<dynamic> confirm(String redemptionId, String pin) {
    PerfTrace.count('offers.confirm');
    return _client.rpc('confirm_offer_redemption', params: {'p_redemption': redemptionId, 'p_pin': pin});
  }

  @override
  Future<dynamic> setHidden(bool hidden) {
    PerfTrace.count('offers.hide');
    return _client.rpc('set_offers_hidden', params: {'p_hidden': hidden});
  }
}

/// «عروض باصك»: what merchants offer this student, and the coupon they use
/// one with. The server decides who sees what; this only reads and asks.
class OffersRepository {
  final OffersGateway _gateway;

  /// The clock a fresh coupon's end is counted from (tests set their own).
  final DateTime Function() _now;

  OffersRepository({OffersGateway? gateway, DateTime Function()? now})
      : _gateway = gateway ?? const SupabaseOffersGateway(),
        _now = now ?? DateTime.now;

  /// The saved read's name (see OfflineCache.readThrough and SyncScope).
  static const cacheKey = 'offers';

  /// Said when the server's answer to a coupon request cannot be read.
  static const noCoupon = 'تعذر إصدار الكوبون. حاول مرة أخرى.';
  static const notAvailable = 'هذا العرض غير متاح الآن.';

  /// Offers told to the server as seen, and as opened, in this run of the app.
  final Set<String> _seen = {};
  final Set<String> _opened = {};

  /// The server said it has no offers function: not asked again in this run
  /// of the app (every resume and refresh would otherwise be one more 404).
  bool _missing = false;

  /// The student's offers, from the saved copy first. [OffersState.unavailable]
  /// when there is nothing to show them from: a server without the feature
  /// (no such function), no connection and nothing saved, or an answer that
  /// cannot be read. Never throws — missing offers are not an error anyone
  /// should see.
  Future<OffersState> load() async {
    if (_missing) return OffersState.unavailable;
    try {
      final json = await OfflineCache.readThrough(cacheKey, _mine);
      return OffersState.tryParse(json) ?? OffersState.unavailable;
    } catch (_) {
      return OffersState.unavailable;
    }
  }

  Future<dynamic> _mine() async {
    try {
      return await _gateway.myOffers();
    } catch (error) {
      if (isMissingFunction(error)) _missing = true;
      rethrow;
    }
  }

  /// [ids] were on the student's screen: told once each in a run of the app,
  /// the new ones together in one request. Never an error; one that could not
  /// be told is told the next time it is on screen.
  void seen(Iterable<String> ids) {
    final fresh = [for (final id in ids) if (_seen.add(id)) id];
    if (fresh.isEmpty) return;
    unawaited(_quietly(() => _gateway.seen(fresh), onFailure: () => _seen.removeAll(fresh)));
  }

  /// The student opened the offer's page. Once in a run of the app.
  void opened(String id) {
    if (!_opened.add(id)) return;
    unawaited(_quietly(() => _gateway.opened(id), onFailure: () => _opened.remove(id)));
  }

  Future<void> _quietly(Future<void> Function() tell, {required VoidCallback onFailure}) async {
    try {
      await tell();
    } catch (_) {
      onFailure();
    }
  }

  /// «استخدم العرض»: the coupon to show at the till — the one still running
  /// when there is one. A refusal (already used, ran out, not available) is
  /// thrown with the server's own words, written to be shown as they are.
  Future<OfferCoupon> redeem(String offerId) async {
    final answer = await _ask(() => _gateway.redeem(offerId));
    final coupon = OfferCoupon.tryParse(answer, now: _now());
    if (coupon == null) throw Exception(noCoupon);
    return coupon;
  }

  /// The merchant's [pin], typed on the student's phone. Throws with the
  /// server's words when the coupon ran out of time or of tries.
  Future<PinAnswer> confirm(String redemptionId, String pin) async {
    final answer = await _ask(() => _gateway.confirm(redemptionId, pin));
    if (answer is! Map) throw Exception(noCoupon);
    return (confirmed: answer['confirmed'] == true, triesLeft: _int(answer['tries_left'], 0));
  }

  /// The student's own switch. Returns what the server now holds.
  ///
  /// Hidden, the server has no offers for the student: that is written into
  /// what this phone holds, so the caller's re-read is answered without a
  /// request. Shown again, the offers have to be read.
  Future<bool> setHidden(bool hidden) async {
    final answer = await _ask(() => _gateway.setHidden(hidden));
    final now = answer is bool ? answer : hidden;
    if (now) await OfflineCache.applyLocal(cacheKey, (_) => {'hidden': true, 'offers': const <Object>[]});
    return now;
  }

  Future<dynamic> _ask(Future<dynamic> Function() request) async {
    try {
      return await requireOnline(request);
    } on PostgrestException catch (error) {
      // An older server (no such function) has nothing to say to a student.
      throw Exception(isMissingFunction(error) || error.message.trim().isEmpty ? notAvailable : error.message);
    }
  }

  /// The server has no function of that name (PostgREST PGRST202, a 404).
  static bool isMissingFunction(Object error) =>
      error is PostgrestException && (error.code == 'PGRST202' || error.code == '42883' || error.code == '404');
}

/// One per signed-in account: what it told the server it has seen is its own.
final offersRepoProvider = Provider<OffersRepository>((ref) {
  ref.watch(sessionUserIdProvider);
  return OffersRepository(now: ref.watch(offersClockProvider));
});

/// The clock the offers read (tests set their own).
final offersClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The student's offers. Re-read on pull to refresh, on app resume and when
/// the server says the offers changed.
final offersProvider = FutureProvider<OffersState>((ref) async {
  if (ref.watch(sessionUserIdProvider) == null) return OffersState.unavailable;
  return ref.watch(offersRepoProvider).load();
});
