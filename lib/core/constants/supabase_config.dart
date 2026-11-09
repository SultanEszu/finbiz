class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static String? initializationFailure;

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
