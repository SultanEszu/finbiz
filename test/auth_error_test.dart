import 'package:finbiz/data/services/api_client.dart';
import 'package:finbiz/data/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API server failure is classified as backend/database unavailable', () {
    final error = const ApiException(500, 'Server error');

    expect(
      profileFailureFromApi(error).kind,
      ProfileFailureKind.databaseNotReady,
    );
    expect(
      authErrorMessage(profileFailureFromApi(error)),
      contains('database MySQL'),
    );
  });

  test('access denied and missing profiles remain distinct', () {
    expect(
      profileFailureFromApi(const ApiException(403, 'Forbidden')).kind,
      ProfileFailureKind.profilePermissionDenied,
    );
    expect(
      profileFailureFromApi(const ApiException(404, 'Not found')).kind,
      ProfileFailureKind.missingProfile,
    );
  });

  test('invalid role responses are reported explicitly', () {
    expect(
      profileFailureFromApi(const ApiException(422, 'Invalid role')).kind,
      ProfileFailureKind.invalidRole,
    );
    expect(
      authErrorMessage(
        const ProfileUnavailableException(ProfileFailureKind.invalidRole),
      ),
      contains('role tidak valid'),
    );
  });

  test('Creator provisioning conflicts ask for administrator action', () {
    expect(
      authErrorMessage(
        profileFailureFromApi(const ApiException(409, 'Creator required')),
      ),
      contains('administrator'),
    );
  });
}
