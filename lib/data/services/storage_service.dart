import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  StorageService(this._client);

  static const bucketName = 'transaction-receipts';
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

  final SupabaseClient _client;

  Future<String> uploadTransactionReceipt({
    required String businessId,
    required String transactionId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (_client.auth.currentUser == null) {
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
    final path = '$businessId/$transactionId/${const Uuid().v4()}-$safeName';

    await _client.storage
        .from(bucketName)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );

    try {
      await _client.from('transaction_attachments').insert({
        'business_id': businessId,
        'transaction_id': transactionId,
        'storage_path': path,
        'original_name': safeName,
        'content_type': contentType,
        'byte_size': bytes.lengthInBytes,
      });
    } catch (error) {
      try {
        await _client.storage.from(bucketName).remove([path]);
      } catch (_) {
        throw StateError(
          'Metadata bukti gagal disimpan dan file sementara tidak dapat dibersihkan. Hubungi pengelola dengan ID transaksi terkait.',
        );
      }
      rethrow;
    }

    return path;
  }

  Future<String> createSignedReceiptUrl({
    required String businessId,
    required String transactionId,
    required String storagePath,
    int expiresInSeconds = 300,
  }) {
    _validateOwnedPath(businessId, transactionId, storagePath);
    if (expiresInSeconds < 30 || expiresInSeconds > 3600) {
      throw ArgumentError.value(
        expiresInSeconds,
        'expiresInSeconds',
        'Masa berlaku harus antara 30 dan 3600 detik.',
      );
    }
    return _client.storage
        .from(bucketName)
        .createSignedUrl(storagePath, expiresInSeconds);
  }

  Future<void> deleteReceipt({
    required String businessId,
    required String transactionId,
    required String storagePath,
  }) async {
    _validateOwnedPath(businessId, transactionId, storagePath);
    await _client.storage.from(bucketName).remove([storagePath]);
    await _client
        .from('transaction_attachments')
        .delete()
        .eq('storage_path', storagePath);
  }

  void _validateOwnedPath(
    String businessId,
    String transactionId,
    String storagePath,
  ) {
    if (_client.auth.currentUser == null) {
      throw StateError('Silakan masuk untuk mengakses bukti transaksi.');
    }
    if (!_uuidPattern.hasMatch(businessId) ||
        !_uuidPattern.hasMatch(transactionId) ||
        storagePath.split('/').length != 3 ||
        storagePath.split('/')[0] != businessId ||
        storagePath.split('/')[1] != transactionId) {
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
