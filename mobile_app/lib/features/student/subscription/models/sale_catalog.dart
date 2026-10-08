/// get_subscription_catalog(): what the signed-in student can subscribe to.
/// Lines are described by structure (line, the student's own university,
/// stations and the trips that stop at each), and every option on sale comes
/// from the database's single sale rule, with its own price.
class SaleCatalog {
  final String? universityName;
  final List<SaleCompany> companies;

  const SaleCatalog({this.universityName, this.companies = const []});

  factory SaleCatalog.fromJson(Map<String, dynamic> json) => SaleCatalog(
        universityName: (json['university'] as Map?)?['name'] as String?,
        companies: (json['companies'] as List<dynamic>? ?? const [])
            .map((c) => SaleCompany.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );

  SaleCompany? company(String? id) =>
      companies.where((c) => c.id == id).firstOrNull;

  SaleLine? line(String? id) => companies
      .expand((c) => c.lines)
      .where((l) => l.id == id)
      .firstOrNull;
}

class SaleCompany {
  final String id;
  final String name;
  final List<SaleLine> lines;

  const SaleCompany({required this.id, required this.name, this.lines = const []});

  factory SaleCompany.fromJson(Map<String, dynamic> json) => SaleCompany(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((l) => SaleLine.fromJson(
                Map<String, dynamic>.from(l as Map), json['id'] as String))
            .toList(),
      );
}

class SaleLine {
  final String id;
  final String companyId;
  final String name;
  final String originName;

  /// The student's own university: where this line takes them.
  final String? university;
  final String? firstDeparture;
  final String? lastReturn;
  final List<SaleStation> stations;

  /// The way back: when the bus leaves the student's university. It has no
  /// stations; every student is taken back to where they board.
  final List<TripStop> returns;
  final List<SaleOption> options;
  final bool dailyEnabled;
  final double dailyPrice;

  const SaleLine({
    required this.id,
    required this.companyId,
    required this.name,
    required this.originName,
    this.university,
    this.firstDeparture,
    this.lastReturn,
    this.stations = const [],
    this.returns = const [],
    this.options = const [],
    this.dailyEnabled = false,
    this.dailyPrice = 0,
  });

  /// The lowest price among what is on sale now (null: nothing is).
  double? get fromPrice => options.isEmpty
      ? null
      : options.map((o) => o.price).reduce((a, b) => a < b ? a : b);

  SaleStation? station(String? id) =>
      stations.where((s) => s.id == id).firstOrNull;

  SaleOption? option(String? key) =>
      options.where((o) => o.key == key).firstOrNull;

  factory SaleLine.fromJson(Map<String, dynamic> json, String companyId) {
    final daily = json['daily'] as Map?;
    return SaleLine(
      id: json['id'] as String,
      companyId: companyId,
      name: json['name'] as String? ?? '',
      originName: json['origin_name'] as String? ?? '',
      university: json['university'] as String?,
      firstDeparture: json['first_departure'] as String?,
      lastReturn: json['last_return'] as String?,
      stations: (json['stations'] as List<dynamic>? ?? const [])
          .map((s) => SaleStation.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      returns: SaleStation._stops(json['returns']),
      options: (json['options'] as List<dynamic>? ?? const [])
          .map((o) => SaleOption.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList(),
      dailyEnabled: daily?['enabled'] == true,
      dailyPrice: (daily?['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// A boarding station. It has no time of its own: each departure trip that
/// stops here has its time.
class SaleStation {
  final String id;
  final String name;
  final List<TripStop> departures;

  const SaleStation({required this.id, required this.name, this.departures = const []});

  static List<TripStop> _stops(dynamic value) => (value as List<dynamic>? ?? const [])
      .map((s) => TripStop.fromJson(Map<String, dynamic>.from(s as Map)))
      .toList();

  factory SaleStation.fromJson(Map<String, dynamic> json) => SaleStation(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        departures: _stops(json['departures']),
      );
}

/// A trip's time: at a station for a departure, at the university for a return.
class TripStop {
  final String tripId;
  final String time;
  final String label;

  const TripStop({required this.tripId, required this.time, this.label = ''});

  factory TripStop.fromJson(Map<String, dynamic> json) => TripStop(
        tripId: json['trip_id'] as String,
        time: json['time'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
}

/// A period on sale: first | second | both | summer.
class SaleOption {
  final String option;
  final int academicYear;
  final String label;

  /// termly | yearly (what the subscription row stores as its type).
  final String type;
  final String startDate;
  final String endDate;
  final String phase; // current | upcoming
  final double price;

  const SaleOption({
    required this.option,
    required this.academicYear,
    required this.label,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.phase,
    required this.price,
  });

  bool get isUpcoming => phase == 'upcoming';
  String get key => '$option:$academicYear';

  /// Short name shown on the choice: "الفصل الأول", "الفصلان معاً" ...
  String get title => switch (option) {
        'first' => 'الفصل الأول',
        'second' => 'الفصل الثاني',
        'both' => 'الفصلان معاً',
        'summer' => 'الفصل الصيفي',
        _ => label,
      };

  factory SaleOption.fromJson(Map<String, dynamic> json) => SaleOption(
        option: json['option'] as String,
        academicYear: (json['academic_year'] as num).toInt(),
        label: json['label'] as String? ?? '',
        type: json['type'] as String? ?? 'termly',
        startDate: json['start_date'] as String? ?? '',
        endDate: json['end_date'] as String? ?? '',
        phase: json['phase'] as String? ?? 'current',
        price: (json['price'] as num?)?.toDouble() ?? 0,
      );
}

/// subscription_receipts: the proof of payment, written once at approval and
/// never changed afterwards. The PDF and the image are built from it alone.
class SubscriptionReceipt {
  final String subscriptionId;
  final int number;
  final String companyName;
  final String studentName;
  final String? studentPhone;
  final String? universityName;
  final String lineName;
  final String? stationName;
  final String periodLabel;
  final String? startDate;
  final String? endDate;
  final double amount;
  final String? paymentMethod;
  final String approvedAt;

  const SubscriptionReceipt({
    required this.subscriptionId,
    required this.number,
    required this.companyName,
    required this.studentName,
    this.studentPhone,
    this.universityName,
    required this.lineName,
    this.stationName,
    required this.periodLabel,
    this.startDate,
    this.endDate,
    required this.amount,
    this.paymentMethod,
    required this.approvedAt,
  });

  factory SubscriptionReceipt.fromJson(Map<String, dynamic> json) => SubscriptionReceipt(
        subscriptionId: json['subscription_id'] as String,
        number: (json['receipt_no'] as num).toInt(),
        companyName: json['company_name'] as String? ?? '',
        studentName: json['student_name'] as String? ?? '',
        studentPhone: json['student_phone'] as String?,
        universityName: json['university_name'] as String?,
        lineName: json['line_name'] as String? ?? '',
        stationName: json['station_name'] as String?,
        periodLabel: json['period_label'] as String? ?? '',
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        paymentMethod: json['payment_method'] as String?,
        approvedAt: json['approved_at'] as String? ?? '',
      );
}
