import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _ensureCurrentProfile();
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
    if (currentUser != null) {
      await _ensureCurrentProfile();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kIsWeb
          ? Uri.base.resolve('/change-password').toString()
          : 'finbiz://reset-password',
    );
  }

  Future<void> changePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
    await _client.rpc('mark_password_changed');
  }

  Future<List<UserProfile>> getProfiles() async {
    final rows = await _client
        .from('profiles')
        .select('id, email, full_name, role, avatar_url, must_change_password')
        .order('full_name');
    return rows.map(UserProfile.fromJson).toList();
  }

  Future<void> updateFullName(String fullName) async {
    final userId = currentUser?.id;
    if (userId == null) throw StateError('Sesi pengguna tidak tersedia.');
    await _client
        .from('profiles')
        .update({'full_name': fullName.trim()})
        .eq('id', userId);
  }

  Future<void> setUserRole(String userId, UserRole role) async {
    await _client.rpc(
      'set_user_role',
      params: {'target_user_id': userId, 'new_role': role.name},
    );
  }

  Future<void> createManagedUser({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'create',
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
      },
    );
  }

  Future<void> deleteManagedUser(String userId) async {
    await _client.functions.invoke(
      'manage-users',
      body: {'action': 'delete', 'user_id': userId},
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<UserProfile?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final result = await _client
        .from('profiles')
        .select('id, email, full_name, role, avatar_url, must_change_password')
        .eq('id', user.id)
        .maybeSingle();

    if (result == null) return null;
    return UserProfile.fromJson(result);
  }

  Future<void> _ensureCurrentProfile() async {
    try {
      await _client.rpc('ensure_current_profile');
      final userId = currentUser?.id;
      if (userId == null) {
        throw const ProfileUnavailableException(
          ProfileFailureKind.missingProfile,
        );
      }
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      if (profile == null) {
        throw const ProfileUnavailableException(
          ProfileFailureKind.missingProfile,
        );
      }
      final roleName = profile['role'] as String?;
      if (roleName == null ||
          !UserRole.values.any((role) => role.name == roleName)) {
        throw const ProfileUnavailableException(ProfileFailureKind.invalidRole);
      }
    } on ProfileUnavailableException {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' ||
          error.code == 'PGRST205' ||
          error.code == '42P01' ||
          error.code == '42883') {
        throw const ProfileUnavailableException(
          ProfileFailureKind.databaseNotReady,
        );
      }
      if (error.code == '42501') {
        throw const ProfileUnavailableException(
          ProfileFailureKind.profilePermissionDenied,
        );
      }
      rethrow;
    }
  }
}

enum ProfileFailureKind {
  databaseNotReady,
  missingProfile,
  invalidRole,
  profilePermissionDenied,
}

class ProfileUnavailableException implements Exception {
  const ProfileUnavailableException(this.kind);

  final ProfileFailureKind kind;
}

String authErrorMessage(Object error) {
  if (error is ProfileUnavailableException) {
    return switch (error.kind) {
      ProfileFailureKind.databaseNotReady => 'Autentikasi berhasil, tetapi database FinBiz belum siap. Minta pengelola menerapkan migration.',
      ProfileFailureKind.missingProfile => 'Autentikasi berhasil, tetapi profil pengguna belum tersedia. Minta pengelola memeriksa provisioning profil.',
      ProfileFailureKind.invalidRole => 'Profil ditemukan, tetapi role tidak valid. Minta Creator memeriksa role akun melalui proses administrasi.',
      ProfileFailureKind.profilePermissionDenied => 'Autentikasi berhasil, tetapi akses ke profil ditolak. Minta pengelola memeriksa kebijakan RLS profil.',
    };
  }
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Email atau kata sandi tidak sesuai.';
    }
    if (message.contains('email not confirmed')) {
      return 'Konfirmasi email Anda sebelum masuk.';
    }
    if (message.contains('banned') || message.contains('disabled')) {
      return 'Akun dinonaktifkan. Hubungi pengelola FinBiz.';
    }
    if (message.contains('user already registered')) {
      return 'Email ini sudah terdaftar.';
    }
    if (message.contains('password should be at least')) {
      return 'Kata sandi harus terdiri dari minimal 8 karakter.';
    }
    if (message.contains('rate limit')) {
      return 'Terlalu banyak percobaan. Coba lagi beberapa saat.';
    }
    if (message.contains('network') ||
        message.contains('fetch') ||
        message.contains('socket')) {
      return 'Koneksi internet bermasalah. Periksa jaringan Anda lalu coba lagi.';
    }
    return 'Autentikasi gagal. Periksa data Anda dan coba lagi.';
  }
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'Anda tidak memiliki izin untuk operasi ini.';
    }
    if (error.code == 'PGRST202' ||
        error.code == 'PGRST205' ||
        error.code == '42P01' ||
        error.code == '42883') {
      return 'Database FinBiz belum siap. Minta pengelola menerapkan migration Supabase.';
    }
    return 'Operasi data gagal. Hubungi pengelola aplikasi jika masalah berlanjut.';
  }
  if (error is FunctionException) {
    return 'Layanan pengelolaan akun gagal. Pastikan fungsi server sudah dikonfigurasi.';
  }
  return 'Terjadi kesalahan jaringan. Periksa koneksi internet Anda.';
}
