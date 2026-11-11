import '../models/app_user.dart';
import '../models/user_profile.dart';
import 'api_client.dart';

class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  Stream<AppUser?> get authStateChanges => _client.authStateChanges;

  AppUser? get currentUser => _client.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    final response = await _client.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    await _saveSession(response);
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _client.post(
      '/auth/register',
      body: {
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
      },
    );
    await _saveSession(response);
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.post('/auth/forgot-password', body: {'email': email.trim()});
  }

  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    await _client.post(
      '/auth/reset-password',
      body: {'email': email, 'token': token, 'password': password},
    );
    await _client.clearSession();
  }

  Future<void> changePassword(String password) async {
    await _client.post('/auth/change-password', body: {'password': password});
  }

  Future<List<UserProfile>> getProfiles() async {
    final response = await _client.get('/profiles');
    final users = response['users'] as List<dynamic>;
    return users
        .map(
          (row) => UserProfile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> updateFullName(String fullName) async {
    await _client.patch('/profile', body: {'full_name': fullName.trim()});
  }

  Future<void> setUserRole(String userId, UserRole role) async {
    await _client.put('/profiles/$userId/role', body: {'role': role.name});
  }

  Future<void> createManagedUser({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.post(
      '/managed-users',
      body: {
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
      },
    );
  }

  Future<void> deleteManagedUser(String userId) async {
    await _client.delete('/managed-users/$userId');
  }

  Future<void> signOut() async {
    await _client.post('/auth/logout');
    await _client.clearSession();
  }

  Future<UserProfile?> getProfile() async {
    if (currentUser == null) return null;
    final response = await _client.get('/auth/me');
    return UserProfile.fromJson(
      Map<String, dynamic>.from(response['user'] as Map),
    );
  }

  Future<void> _saveSession(Map<String, dynamic> response) async {
    final user = AppUser.fromJson(
      Map<String, dynamic>.from(response['user'] as Map),
    );
    await _client.setSession(token: response['token'] as String, user: user);
  }
}

enum ProfileFailureKind {
  databaseNotReady,
  missingProfile,
  invalidRole,
  profilePermissionDenied,
  creatorProvisioningRequired,
  profileUnavailable,
}

class ProfileUnavailableException implements Exception {
  const ProfileUnavailableException(this.kind);

  final ProfileFailureKind kind;
}

ProfileUnavailableException profileFailureFromApi(ApiException error) {
  final kind = switch (error.statusCode) {
    403 => ProfileFailureKind.profilePermissionDenied,
    404 => ProfileFailureKind.missingProfile,
    409 => ProfileFailureKind.creatorProvisioningRequired,
    422 => ProfileFailureKind.invalidRole,
    500 || 503 => ProfileFailureKind.databaseNotReady,
    _ => ProfileFailureKind.profileUnavailable,
  };
  return ProfileUnavailableException(kind);
}

String authErrorMessage(Object error) {
  if (error is ProfileUnavailableException) {
    return switch (error.kind) {
      ProfileFailureKind.databaseNotReady => 'Layanan FinBiz belum siap. Minta pengelola memeriksa konfigurasi API dan database MySQL.',
      ProfileFailureKind.missingProfile => 'Autentikasi berhasil, tetapi profil pengguna belum tersedia. Minta pengelola memeriksa provisioning profil.',
      ProfileFailureKind.invalidRole => 'Profil ditemukan, tetapi role tidak valid. Minta Creator memeriksa role akun melalui proses administrasi.',
      ProfileFailureKind.profilePermissionDenied => 'Autentikasi berhasil, tetapi akses ke profil ditolak. Minta pengelola memeriksa izin akun.',
      ProfileFailureKind.creatorProvisioningRequired =>
        'Akun Creator belum diprovisikan oleh administrator.',
      ProfileFailureKind.profileUnavailable => 'Sesi login aktif, tetapi profil tidak dapat diverifikasi. Periksa server dan database.',
    };
  }
  if (error is ApiException) {
    if (error.statusCode == 401) return 'Email atau kata sandi tidak sesuai.';
    if (error.statusCode == 403) {
      return 'Anda tidak memiliki izin untuk operasi ini.';
    }
    if (error.statusCode == 404) return 'Data yang diminta tidak ditemukan.';
    if (error.statusCode == 409 || error.statusCode == 422) {
      return error.message;
    }
    if (error.statusCode >= 500) {
      return 'Server FinBiz mengalami kendala. Periksa konfigurasi API dan database MySQL.';
    }
    return error.message;
  }
  if (error is FormatException) return 'Respons server FinBiz tidak valid.';
  return 'Terjadi kesalahan jaringan. Periksa koneksi dan coba lagi.';
}
