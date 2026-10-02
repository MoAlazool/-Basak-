class SupabaseTables {
  static const String companies = 'companies';
  static const String lines = 'lines';
  static const String stations = 'stations';
  static const String students = 'students';
  static const String supervisors = 'supervisors';
  static const String admins = 'admins';
  static const String subscriptions = 'subscriptions';
  static const String receipts = 'receipts';
  static const String dailyRideStatus = 'daily_ride_status';
  static const String chatMessages = 'chat_messages';
  static const String complaints = 'complaints';
}

class SupabaseRpcs {
  static const String toggleStudentDailyRide = 'toggle_student_daily_ride';
  static const String getLineRiderCounts = 'get_line_rider_counts_with_returns';
  static const String lookupStudentByQr = 'lookup_student_by_qr';
}
