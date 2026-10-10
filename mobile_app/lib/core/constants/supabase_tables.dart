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
}

class SupabaseRpcs {
  static const String toggleStudentDailyRide = 'toggle_student_daily_ride';
  static const String getLineRiderCounts = 'get_line_rider_counts_with_returns';
  static const String getLinesRiderCounts = 'get_lines_rider_counts';
  static const String lookupStudentByQr = 'lookup_student_by_qr';
  static const String getSupervisorDashboard = 'get_supervisor_dashboard';
  static const String supervisorCheckInStudent = 'supervisor_check_in_student';
  static const String getSupervisorMonthlySummary = 'get_supervisor_monthly_summary';
  static const String getSupervisorTripManifest = 'get_supervisor_trip_manifest';
  static const String getMyLineCapacities = 'get_my_line_capacities';
  static const String getSubscriptionCatalog = 'get_subscription_catalog';
  static const String getSubscriptionSwitches = 'get_subscription_switches';
  static const String getVoteSettings = 'get_vote_settings';
  static const String requestStudentPasswordReset = 'request_student_password_reset';
  static const String getSupportWhatsApp = 'get_support_whatsapp';
  static const String getMyLineSupervisors = 'get_my_line_supervisors';
  static const String walletRefreshMyCard = 'wallet_refresh_my_card';
  static const String getAppVersion = 'get_app_version';
  static const String getMyBoardedRidesCount = 'get_my_boarded_rides_count';
}

class SupabaseFunctions {
  static const String studentWalletPass = 'student-wallet-pass';
}
