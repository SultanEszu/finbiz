import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/api_client.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/storage_service.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/app_user.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(ref.watch(apiClientProvider)),
);

final authStateProvider = StreamProvider<AppUser?>((ref) {
  final service = ref.watch(authServiceProvider);
  return service.authStateChanges;
});

final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final service = ref.watch(authServiceProvider);
  if (service.currentUser == null) return null;
  return service.getProfile();
});

final managedProfilesProvider = FutureProvider<List<UserProfile>>((ref) async {
  final service = ref.watch(authServiceProvider);
  return service.getProfiles();
});
