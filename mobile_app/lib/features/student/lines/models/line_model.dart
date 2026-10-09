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
