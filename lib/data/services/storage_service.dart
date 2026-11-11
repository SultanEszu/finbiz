import 'dart:typed_data';

import 'api_client.dart';

class StorageService {
  StorageService(this._client);

  static const maxFileSize = 10 * 1024 * 1024;
  static const _allowedTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
  };
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final ApiClient _client;

  Future<String> uploadTransactionReceipt({
    required String businessId,
    required String transactionId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (_client.currentUser == null) {
      throw StateError('Silakan masuk untuk mengunggah bukti transaksi.');
    }
    if (!_uuidPattern.hasMatch(businessId) ||
        !_uuidPattern.hasMatch(transactionId)) {
      throw ArgumentError('Identitas bisnis atau transaksi tidak valid.');
    }
    if (!_allowedTypes.contains(contentType) ||
        bytes.isEmpty ||
        bytes.lengthInBytes > maxFileSize ||
        !_hasExpectedSignature(contentType, bytes)) {
      throw ArgumentError(
        'Bukti harus berupa JPEG, PNG, WebP, atau PDF dengan ukuran maksimal 10 MiB.',
      );
    }

    final sanitizedName = fileName
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final safeName = sanitizedName.isEmpty
        ? 'bukti.${_extensionFor(contentType)}'
        : sanitizedName.substring(
            0,
            sanitizedName.length > 120 ? 120 : sanitizedName.length,
          );
    final response = await _client.upload(
      '/receipts',
      fields: {'business_id': businessId, 'transaction_id': transactionId},
      fileField: 'file',
      fileName: safeName,
      bytes: bytes,
    );
    return response['storage_path'] as String;
  }

  Future<String> createSignedReceiptUrl({
    required String businessId,
    required String transactionId,
    required String storagePath,
    int expiresInSeconds = 300,
  }) async {
    _validateOwnedPath(businessId, transactionId, storagePath);
    if (expiresInSeconds < 30 || expiresInSeconds > 3600) {
      throw ArgumentError.value(
        expiresInSeconds,
        'expiresInSeconds',
        'Masa berlaku harus antara 30 dan 3600 detik.',
      );
    }
    final response = await _client.get(
      '/receipts/signed-url',
      query: {
        'business_id': businessId,
        'transaction_id': transactionId,
        'storage_path': storagePath,
        'expires_in': '$expiresInSeconds',
      },
    );
    return response['url'] as String;
  }

  Future<void> deleteReceipt({
    required String businessId,
    required String transactionId,
    required String storagePath,
  }) async {
    _validateOwnedPath(businessId, transactionId, storagePath);
    await _client.delete(
      '/receipts',
      body: {
        'business_id': businessId,
        'transaction_id': transactionId,
        'storage_path': storagePath,
      },
    );
  }

  void _validateOwnedPath(
    String businessId,
    String transactionId,
    String storagePath,
  ) {
    if (_client.currentUser == null) {
      throw StateError('Silakan masuk untuk mengakses bukti transaksi.');
    }
    final parts = storagePath.split('/');
    if (!_uuidPattern.hasMatch(businessId) ||
        !_uuidPattern.hasMatch(transactionId) ||
        parts.length != 3 ||
        parts[0] != businessId ||
        parts[1] != transactionId) {
      throw ArgumentError('Lokasi bukti transaksi tidak valid.');
    }
  }

  bool _hasExpectedSignature(String contentType, Uint8List bytes) {
    switch (contentType) {
      case 'image/png':
        return bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4e &&
            bytes[3] == 0x47 &&
            bytes[4] == 0x0d &&
            bytes[5] == 0x0a &&
            bytes[6] == 0x1a &&
            bytes[7] == 0x0a;
      case 'image/jpeg':
        return bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff;
      case 'image/webp':
        return bytes.length >= 12 &&
            String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
            String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
      case 'application/pdf':
        return bytes.length >= 5 &&
            String.fromCharCodes(bytes.sublist(0, 5)) == '%PDF-';
      default:
        return false;
    }
  }

  String _extensionFor(String contentType) {
    return switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'application/pdf' => 'pdf',
      _ => 'bin',
    };
  }
}
