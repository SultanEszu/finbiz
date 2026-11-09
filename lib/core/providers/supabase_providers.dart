import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../../data/models/user_profile.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/storage_service.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!SupabaseConfig.isConfigured) return null;
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AuthService(client);
});

final storageServiceProvider = Provider<StorageService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : StorageService(client);
});

final authStateProvider = StreamProvider<AuthState?>((ref) {
  final service = ref.watch(authServiceProvider);
  return service?.authStateChanges ?? Stream.value(null);
});

final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final authState = ref
      .watch(authStateProvider)
      .when(
        data: (state) => state,
        loading: () => null,
        error: (error, stackTrace) => null,
      );
  if (authState?.session == null) return null;
  final service = ref.watch(authServiceProvider);
  if (service == null || service.currentUser == null) return null;
  return service.getProfile();
});

final managedProfilesProvider = FutureProvider<List<UserProfile>>((ref) async {
  final service = ref.watch(authServiceProvider);
  if (service == null) return [];
  return service.getProfiles();
});
