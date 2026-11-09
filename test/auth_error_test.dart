import 'package:finbiz/data/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profil tidak tersedia menghasilkan petunjuk migrasi yang aman', () {
    expect(
      authErrorMessage(
        const ProfileUnavailableException(ProfileFailureKind.databaseNotReady),
      ),
      contains('migration'),
    );
  });

  test('profil hilang dibedakan dari kegagalan autentikasi', () {
    expect(
      authErrorMessage(
        const ProfileUnavailableException(ProfileFailureKind.missingProfile),
      ),
      contains('profil pengguna belum tersedia'),
    );
    expect(
      authErrorMessage(
        const ProfileUnavailableException(ProfileFailureKind.invalidRole),
      ),
      contains('role tidak valid'),
    );
  });
}
