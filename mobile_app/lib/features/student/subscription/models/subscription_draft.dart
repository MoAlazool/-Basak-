import 'sale_catalog.dart';

/// The five steps of choosing a subscription.
enum DraftStep { company, line, station, period, review }

/// What the student has chosen so far. It lives in the app only: moving
/// between the steps and changing a choice writes nothing to the server. The
/// subscription is created once, when the student confirms the review.
///
/// Changing an earlier choice keeps the later ones that still apply and
/// clears the rest (a station that is not on the new line, a period the new
/// line does not sell).
class SubscriptionDraft {
  final String? companyId;
  final String? lineId;
  final String? stationId;

  /// [SaleOption.key] of the chosen period, or [dailyKey].
  final String? optionKey;

  static const dailyKey = 'daily';

  const SubscriptionDraft({this.companyId, this.lineId, this.stationId, this.optionKey});

  bool get isDaily => optionKey == dailyKey;

  SubscriptionDraft pickCompany(SaleCatalog catalog, String id) {
    if (id == companyId) return this;
    return SubscriptionDraft(companyId: id);
  }

  SubscriptionDraft pickLine(SaleCatalog catalog, String id) {
    if (id == lineId) return this;
    final line = catalog.line(id);
    if (line == null) return this;
    return SubscriptionDraft(
      companyId: line.companyId,
      lineId: id,
      // Same station name on the new line (e.g. two lines through one town).
      stationId: line.station(stationId)?.id,
      optionKey: _stillOffered(line, optionKey),
    );
  }

  SubscriptionDraft pickStation(String id) => SubscriptionDraft(
      companyId: companyId, lineId: lineId, stationId: id, optionKey: optionKey);

  SubscriptionDraft pickOption(String key) => SubscriptionDraft(
      companyId: companyId, lineId: lineId, stationId: stationId, optionKey: key);

  static String? _stillOffered(SaleLine line, String? key) {
    if (key == null) return null;
    if (key == dailyKey) return line.dailyEnabled ? key : null;
    return line.option(key)?.key;
  }

  /// The same choices checked against a fresh catalog: whatever is no longer
  /// there (a line switched off, a period taken off sale) is dropped.
  SubscriptionDraft reconciled(SaleCatalog catalog) {
    final company = catalog.company(companyId);
    if (company == null) return const SubscriptionDraft();
    final line = company.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return SubscriptionDraft(companyId: company.id);
    return SubscriptionDraft(
      companyId: company.id,
      lineId: line.id,
      stationId: line.station(stationId)?.id,
      optionKey: _stillOffered(line, optionKey),
    );
  }

  /// The first step that still needs a choice.
  DraftStep get firstOpenStep => companyId == null
      ? DraftStep.company
      : lineId == null
          ? DraftStep.line
          : stationId == null
              ? DraftStep.station
              : optionKey == null
                  ? DraftStep.period
                  : DraftStep.review;

  /// Whether [step] can be opened with what is chosen so far.
  bool canOpen(DraftStep step) => step.index <= firstOpenStep.index;

  @override
  bool operator ==(Object other) =>
      other is SubscriptionDraft &&
      other.companyId == companyId &&
      other.lineId == lineId &&
      other.stationId == stationId &&
      other.optionKey == optionKey;

  @override
  int get hashCode => Object.hash(companyId, lineId, stationId, optionKey);
}

/// Everything the server needs to create the subscription the draft describes.
class SubscriptionRequest {
  final String lineId;
  final String stationId;
  final String departureTripId;
  final String departureTime;
  final String? returnTripId;
  final String? returnTime;
  final String type; // termly | yearly | daily
  final double price;
  final String? periodCode;
  final int? academicYear;

  const SubscriptionRequest({
    required this.lineId,
    required this.stationId,
    required this.departureTripId,
    required this.departureTime,
    this.returnTripId,
    this.returnTime,
    required this.type,
    required this.price,
    this.periodCode,
    this.academicYear,
  });

  /// The request for a complete [draft], or null while a choice is missing or
  /// no longer offered. The subscription records the earliest trip of each
  /// direction at the station; the student picks the day's times on the home screen.
  static SubscriptionRequest? from(SubscriptionDraft draft, SaleCatalog catalog) {
    final line = catalog.line(draft.lineId);
    final station = line?.station(draft.stationId);
    if (line == null || station == null || station.departures.isEmpty) return null;
    final option = draft.isDaily ? null : line.option(draft.optionKey);
    if (draft.isDaily ? !line.dailyEnabled : option == null) return null;
    final departure = station.departures.first;
    final back = station.returns.firstOrNull;
    return SubscriptionRequest(
      lineId: line.id,
      stationId: station.id,
      departureTripId: departure.tripId,
      departureTime: departure.time,
      returnTripId: back?.tripId,
      returnTime: back?.time,
      type: option?.type ?? 'daily',
      price: option?.price ?? line.dailyPrice,
      periodCode: option?.option,
      academicYear: option?.academicYear,
    );
  }
}
