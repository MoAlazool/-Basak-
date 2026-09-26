class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hnwpkkryxovhmsrokdsd.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_27asYTB5nFSffrYYhyU2hQ_bj79mCxr',
  );

  // Storage bucket names
  static const String receiptsBucket = 'receipts';
}
