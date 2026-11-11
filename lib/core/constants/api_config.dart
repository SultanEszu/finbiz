class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment('API_BASE_URL');

  static String? initializationFailure;

  static bool get isConfigured => baseUrl.trim().isNotEmpty;
}
