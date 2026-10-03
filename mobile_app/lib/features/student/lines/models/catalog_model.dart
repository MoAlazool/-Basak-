import 'line_model.dart';

/// get_student_catalog(): active companies with the active lines that serve
/// the signed-in student's university (subscription flow steps 1–2).
class CatalogCompany {
  final String id;
  final String name;
  final List<CatalogLine> lines;

  CatalogCompany({required this.id, required this.name, required this.lines});

  factory CatalogCompany.fromJson(Map<String, dynamic> json) => CatalogCompany(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((l) => CatalogLine.fromJson(l as Map<String, dynamic>, json))
            .toList(),
      );
}

class CatalogLine {
  final String id;
  final String companyId;
  final String companyName;
  final String name;
  final String originName;
  final String? destination;
  final double priceTermly;
  final double priceYearly;
  final double priceDaily;
  final List<String> stations;
  final List<String> departureTimes;
  final List<String> returnTimes;

  CatalogLine({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.name,
    required this.originName,
    required this.destination,
    required this.priceTermly,
    required this.priceYearly,
    required this.priceDaily,
    required this.stations,
    required this.departureTimes,
    required this.returnTimes,
  });

  static List<String> _strings(dynamic value) =>
      (value as List<dynamic>? ?? const []).map((v) => v.toString()).toList();

  factory CatalogLine.fromJson(Map<String, dynamic> json, Map<String, dynamic> company) => CatalogLine(
        id: json['id'] as String,
        companyId: company['id'] as String,
        companyName: company['name'] as String? ?? '',
        name: json['name'] as String? ?? '',
        originName: json['origin_name'] as String? ?? '',
        destination: json['destination'] as String?,
        priceTermly: (json['price_termly'] as num?)?.toDouble() ?? 0,
        priceYearly: (json['price_yearly'] as num?)?.toDouble() ?? 0,
        priceDaily: (json['price_daily'] as num?)?.toDouble() ?? 0,
        stations: _strings(json['stations']),
        departureTimes: _strings(json['departure_times']),
        returnTimes: _strings(json['return_times']),
      );

  LineModel toLineModel() => LineModel(
        id: id,
        companyId: companyId,
        name: name,
        priceTermly: priceTermly,
        priceYearly: priceYearly,
        priceDaily: priceDaily,
        isActive: true,
        companyName: companyName,
        originName: originName,
        destinationName: destination,
      );
}
