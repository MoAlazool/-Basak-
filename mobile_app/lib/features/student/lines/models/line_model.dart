String stationTimesLabel(dynamic value) {
  if (value == null) return '';
  if (value is List) {
    return value.map((time) => time.toString()).join('، ');
  }
  return value.toString();
}

List<String> stationTimes(dynamic value) {
  if (value == null) return const [];
  final raw = value is List ? value : [value];
  final values = raw
      .map((time) => time.toString())
      .where((time) => time.isNotEmpty)
      .map((time) => time.length >= 5 ? time.substring(0, 5) : time)
      .toList();
  int? minutes(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;
    return (int.parse(match.group(1)!) * 60) + int.parse(match.group(2)!);
  }

  values.sort((a, b) {
    final aMinutes = minutes(a);
    final bMinutes = minutes(b);
    if (aMinutes != null && bMinutes != null) {
      return aMinutes.compareTo(bMinutes);
    }
    return a.compareTo(b);
  });
  return values;
}

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

  /// Route ends: start location and destination university.
  final String? originName;
  final String? destinationName;

  /// True when the line runs per-university trips (line_university_schedules).
  final bool usesUniversitySchedules;

  /// The trip of the signed-in student's university on this line, if any.
  final String? scheduleId;
  final String? universityName;
  final String? scheduleDepartureTime;
  final String? scheduleReturnTime;

  bool get hasUniversitySchedule => scheduleId != null;

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
    this.originName,
    this.destinationName,
    this.usesUniversitySchedules = false,
    this.scheduleId,
    this.universityName,
    this.scheduleDepartureTime,
    this.scheduleReturnTime,
  });

  /// Applies a row of the get_student_line_options RPC.
  LineModel withStudentOption(Map<String, dynamic> option) {
    String? hhmm(dynamic value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return text.length >= 5 ? text.substring(0, 5) : text;
    }

    return LineModel(
      id: id,
      companyId: companyId,
      name: name,
      supervisorId: supervisorId,
      priceTermly: priceTermly,
      priceYearly: priceYearly,
      priceDaily: priceDaily,
      isActive: isActive,
      companyName: companyName,
      originName: originName,
      destinationName: destinationName,
      usesUniversitySchedules:
          option['uses_university_schedules'] as bool? ?? false,
      scheduleId: option['schedule_id'] as String?,
      universityName: option['university_name'] as String?,
      scheduleDepartureTime: hhmm(option['departure_time']),
      scheduleReturnTime: hhmm(option['return_time']),
    );
  }

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
      companyName: json['companies'] != null
          ? json['companies']['name'] as String?
          : null,
      originName: json['origin_name'] as String?,
      destinationName: (json['destination'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

class StationModel {
  final String id;
  final String lineId;
  final String name;
  final int orderIndex;
  final List<String> departureTimes;
  final List<String> returnTimes;
  String get departureTime => departureTimes.join('، ');
  String get returnTime => returnTimes.join('، ');

  StationModel({
    required this.id,
    required this.lineId,
    required this.name,
    required this.orderIndex,
    required this.departureTimes,
    required this.returnTimes,
  });

  factory StationModel.fromJson(Map<String, dynamic> json) {
    return StationModel(
      id: json['id'] as String,
      lineId: json['line_id'] as String,
      name: json['name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
      departureTimes:
          stationTimes(json['departure_times'] ?? json['departure_time']),
      returnTimes: stationTimes(json['return_times'] ?? json['return_time']),
    );
  }
}
