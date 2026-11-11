import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final instance = ApiClient._();
  static const _tokenKey = 'finbiz_api_token';
  static const _baseUrl = String.fromEnvironment('API_BASE_URL');

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final http.Client _http = http.Client();
  final StreamController<AppUser?> _sessionChanges =
      StreamController<AppUser?>.broadcast(sync: true);

  String? _token;
  AppUser? _currentUser;

  static String? initializationFailure;

  static bool get isConfigured => _baseUrl.trim().isNotEmpty;
  AppUser? get currentUser => _currentUser;

  Stream<AppUser?> get authStateChanges => Stream.multi((controller) {
    controller.add(_currentUser);
    final subscription = _sessionChanges.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });

  Future<void> initialize() async {
    if (!isConfigured) return;
    _token = await _secureStorage.read(key: _tokenKey);
    if (_token == null) return;

    try {
      final response = await get('/auth/me');
      _setCurrentUser(
        AppUser.fromJson(response['user'] as Map<String, dynamic>),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        return;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) => _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) => _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) => _send('DELETE', path, body: body);

  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required List<int> bytes,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(fileField, bytes, filename: fileName),
      );
    final token = _token;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['Accept'] = 'application/json';
    final streamedResponse = await _http.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query: query);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (_token != null) headers['Authorization'] = 'Bearer $_token';

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamedResponse = await _http.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _decodeResponse(http.Response response) async {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && _token != null) {
        await _clearSession();
      }
      final errors = body['errors'];
      final message = errors is Map && errors.values.isNotEmpty
          ? errors.values.first is List
                ? (errors.values.first as List).first.toString()
                : errors.values.first.toString()
          : body['message'] as String? ?? 'Permintaan ke server gagal.';
      throw ApiException(response.statusCode, message);
    }
    return body;
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final base = _baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<void> setSession({
    required String token,
    required AppUser user,
  }) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    _token = token;
    _setCurrentUser(user);
  }

  void _setCurrentUser(AppUser? user) {
    _currentUser = user;
    _sessionChanges.add(user);
  }

  Future<void> clearSession() => _clearSession();

  Future<void> _clearSession() async {
    _token = null;
    _setCurrentUser(null);
    await _secureStorage.delete(key: _tokenKey);
  }
}
