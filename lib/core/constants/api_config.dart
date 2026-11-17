import 'dart:convert';

import 'package:flutter/services.dart';

class ApiConfig {
  const ApiConfig._();

  static const defaultBaseUrl = 'http://127.0.0.1:8000';
  static String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    final value = _baseUrl.trim();
    return value.isEmpty ? defaultBaseUrl : value;
  }

  static String? initializationFailure;

  static Future<void> load() async {
    final runtimeBaseUrl = await _loadRuntimeBaseUrl();
    if (runtimeBaseUrl != null && runtimeBaseUrl.trim().isNotEmpty) {
      _baseUrl = runtimeBaseUrl;
      return;
    }

    if (_baseUrl.trim().isEmpty) {
      _baseUrl = defaultBaseUrl;
    }
  }

  static Future<String?> _loadRuntimeBaseUrl() async {
    for (final assetPath in [
      'assets/config/.env',
      'assets/config/app_config.json',
    ]) {
      try {
        final content = await rootBundle.loadString(assetPath);
        final parsed = _parseConfig(content);
        if (parsed != null && parsed.trim().isNotEmpty) {
          return parsed;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static String? _parseConfig(String raw) {
    if (raw.trim().isEmpty) return null;

    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final value = decoded['API_BASE_URL'] ?? decoded['api_base_url'];
          if (value is String) return value.trim();
        }
      } on FormatException {
        return null;
      }
      return null;
    }

    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final cleaned = line.trim();
      if (cleaned.isEmpty || cleaned.startsWith('#')) {
        continue;
      }
      final match = RegExp(r'^API_BASE_URL\s*=\s*(.+)$').firstMatch(cleaned);
      if (match != null) {
        final value = match.group(1)?.trim();
        if (value != null) {
          return value.replaceAll(RegExp(r'^"|"$'), '');
        }
      }
    }

    return null;
  }

  static bool get isConfigured => baseUrl.trim().isNotEmpty;
}
