import 'package:basak_mobile/features/supervisor/models/supervisor_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> dashboard(List<Map<String, dynamic>> tripTimes) => {
        'today': '2026-10-08',
        'profile': {'id': 'sup', 'full_name': 'مشرف'},
        'totals': <String, dynamic>{},
        'lines': [
          {
            'id': 'line',
            'name': 'خط المنصورة',
            'schedules': [
              {'id': 'trip-a', 'university': 'كل الجامعات', 'departure_time': '06:55:00', 'registered_students': 9},
              {'university': 'جامعة قديمة', 'departure_time': '09:00:00', 'registered_students': 2},
            ],
          }
        ],
        'trip_times': tripTimes,
      };

  final departure = {
    'ride_date': '2026-10-08',
    'line_id': 'line',
    'line_name': 'خط المنصورة',
    'direction': 'departure',
    'time': '06:55:00',
    'students': 3,
    'trip_id': 'trip-a',
    'label': ' الرحلة الأولى ',
    'university': null,
    'stations': [
      {'id': 'st1', 'name': 'المحطة الأولى', 'order_index': 1, 'stop_time': '06:55:00', 'students': 2},
      {'id': 'st2', 'name': 'المحطة الثانية', 'order_index': 2, 'stop_time': '07:00:00', 'students': 0},
      {'id': 'st9', 'name': 'خارج المسار', 'order_index': 9, 'stop_time': null, 'students': 1},
    ],
    'universities': [
      {'name': 'جامعة المنصورة', 'students': 2},
      {'name': 'غير محددة', 'students': 1},
    ],
    'riders': [
      {'id': 's1', 'full_name': 'أحمد', 'phone': '01000000001', 'station_id': 'st1', 'station': 'المحطة الأولى', 'university': 'جامعة المنصورة', 'time': '06:55:00'},
      {'id': 's2', 'full_name': 'سارة', 'phone': '01000000002', 'station_id': 'st1', 'station': 'المحطة الأولى', 'university': 'جامعة المنصورة', 'time': '06:55:00'},
      {'id': 's3', 'full_name': 'منى', 'phone': '01000000003', 'station_id': 'st9', 'station': 'خارج المسار', 'university': '', 'time': '06:50:00'},
    ],
  };

  test('a trip time carries its trip, stations, universities and riders', () {
    final t = SupervisorTripTime.fromJson(departure);
    expect(t.tripId, 'trip-a');
    expect(t.label, 'الرحلة الأولى');
    expect(t.university, isNull);
    expect(t.subtitle, 'الرحلة الأولى');
    expect(t.hasBreakdown, isTrue);
    expect(t.stations.map((s) => s.id), ['st1', 'st2', 'st9']);
    expect(t.stations.first.stopTime, '06:55:00');
    expect(t.stations.last.stopTime, isNull);
    expect(t.stations.map((s) => s.students), [2, 0, 1]);
    expect(t.stations[1].orderIndex, 2);
    expect(t.universities.map((u) => (u.name, u.students)), [('جامعة المنصورة', 2), ('غير محددة', 1)]);
    expect(t.ridersAt('st1').map((r) => r.fullName), ['أحمد', 'سارة']);
    expect(t.ridersAt('st2'), isEmpty);
    // A blank university falls in the server's "غير محددة" group.
    expect(t.ridersOf('غير محددة').map((r) => r.id), ['s3']);
    expect(t.riders.last.time, '06:50:00');
    expect(t.riders.first.phone, '01000000001');
  });

  test('a trip time from an older server has no breakdown', () {
    final t = SupervisorTripTime.fromJson({
      'ride_date': '2026-10-08',
      'line_id': 'line',
      'line_name': 'خط المنصورة',
      'direction': 'return',
      'time': '17:00:00',
      'students': 5,
    });
    expect(t.isReturn, isTrue);
    expect(t.students, 5);
    expect(t.tripId, isNull);
    expect(t.label, '');
    expect(t.university, isNull);
    expect(t.subtitle, '');
    expect(t.stations, isEmpty);
    expect(t.universities, isEmpty);
    expect(t.riders, isEmpty);
    expect(t.hasBreakdown, isFalse);
  });

  test("a line trip shows today's riders by their chosen time", () {
    final d = SupervisorDashboard.fromJson(dashboard([
      departure,
      {...departure, 'trip_id': 'trip-b', 'students': 4},
      {...departure, 'direction': 'return', 'students': 2},
      {...departure, 'ride_date': '2026-10-09', 'students': 7},
    ]));
    final trips = d.lines.single.schedules;
    expect(trips.first.id, 'trip-a');
    expect(trips.last.id, isNull);
    // Departure 3 + return 2 on trip-a today; tomorrow is not counted.
    expect(d.ridersOnTrip('trip-a', d.today), 5);
    expect(d.ridersOnTrip('trip-c', d.today), 0);
    expect(d.ridersOnTrip(null, d.today), isNull);
  });

  test('per-trip counts are unknown when the server does not group by trip', () {
    final d = SupervisorDashboard.fromJson(dashboard([
      {
        'ride_date': '2026-10-08',
        'line_id': 'line',
        'line_name': 'خط المنصورة',
        'direction': 'departure',
        'time': '06:55:00',
        'students': 3,
      }
    ]));
    expect(d.ridersOnTrip('trip-a', d.today), isNull);
    expect(SupervisorDashboard.fromJson(dashboard([])).ridersOnTrip('trip-a', d.today), 0);
  });

  test('the manifest carries chosen times and the unconfirmed students', () {
    final m = TripManifest.fromJson({
      'line': {'id': 'line', 'name': 'خط المنصورة', 'origin_name': 'طلخا'},
      'direction': 'departure',
      'trips': [
        {'id': 'trip-a', 'label': '', 'start_time': '06:55:00', 'students': 2}
      ],
      'trip': {'id': 'trip-a', 'label': '', 'start_time': '06:55:00', 'students': 2},
      'stations': [
        {
          'id': 'st1',
          'name': 'المحطة الأولى',
          'stop_time': '06:55:00',
          'students': [
            {'id': 's1', 'full_name': 'أحمد', 'phone': '010', 'confirmed': true, 'chosen_time': '06:55:00'},
            {'id': 's4', 'full_name': 'علي', 'phone': '011', 'confirmed': false, 'chosen_time': '09:00:00',
             'checked_in_at': '2026-10-08T05:00:00Z'},
          ],
        }
      ],
      'unconfirmed': [
        {'id': 's5', 'full_name': 'هدى', 'phone': '012', 'university': null, 'station': 'المحطة الثانية'}
      ],
    });
    final students = m.students;
    expect(students.first.chosenTime, '06:55:00');
    expect(students.last.confirmed, isFalse);
    expect(students.last.chosenTime, '09:00:00');
    expect(students.last.isCheckedIn, isTrue);
    expect(m.unconfirmed.single.fullName, 'هدى');
    expect(m.unconfirmed.single.station, 'المحطة الثانية');
    expect(m.unconfirmed.single.isCheckedIn, isFalse);
  });

  test('a manifest from an older server has no chosen times or unconfirmed list', () {
    final m = TripManifest.fromJson({
      'line': {'id': 'line', 'name': 'خط المنصورة', 'origin_name': 'طلخا'},
      'direction': 'return',
      'trips': <dynamic>[],
      'stations': [
        {
          'id': 'st1',
          'name': 'المحطة الأولى',
          'stop_time': null,
          'students': [
            {'id': 's1', 'full_name': 'أحمد', 'phone': '010', 'confirmed': true}
          ],
        }
      ],
    });
    expect(m.students.single.chosenTime, isNull);
    expect(m.students.single.station, isNull);
    expect(m.unconfirmed, isEmpty);
  });
}
