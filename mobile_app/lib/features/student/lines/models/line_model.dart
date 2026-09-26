class CompanyModel {
  final String id;
  final String name;
  final bool isActive;

  CompanyModel({
    required this.id,
    required this.name,
    required this.isActive,
  });

  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    return CompanyModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class LineModel {
  final String id;
  final String companyId;
  final String name;
  final String? supervisorId;
  final double priceTermly;
  final double priceYearly;
  final double priceDaily;
  final bool isActive;
  final String? companyName;

  LineModel({
    required this.id,
    required this.companyId,
    required this.name,
    this.supervisorId,
    required this.priceTermly,
    required this.priceYearly,
    required this.priceDaily,
    required this.isActive,
    this.companyName,
  });

  factory LineModel.fromJson(Map<String, dynamic> json) {
    return LineModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      supervisorId: json['supervisor_id'] as String?,
      priceTermly: (json['price_termly'] as num).toDouble(),
      priceYearly: (json['price_yearly'] as num).toDouble(),
      priceDaily: (json['price_daily'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      companyName: json['companies'] != null ? json['companies']['name'] as String? : null,
    );
  }
}

class StationModel {
  final String id;
  final String lineId;
  final String name;
  final int orderIndex;
  final String departureTime;
  final String returnTime;

  StationModel({
    required this.id,
    required this.lineId,
    required this.name,
    required this.orderIndex,
    required this.departureTime,
    required this.returnTime,
  });

  factory StationModel.fromJson(Map<String, dynamic> json) {
    return StationModel(
      id: json['id'] as String,
      lineId: json['line_id'] as String,
      name: json['name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
      departureTime: json['departure_time'] as String,
      returnTime: json['return_time'] as String,
    );
  }
}
