import 'dart:async';

import 'package:finbiz/core/constants/api_config.dart';
import 'package:finbiz/features/auth/auth_screen.dart';
import 'package:finbiz/features/auth/change_password_screen.dart';
import 'package:finbiz/features/auth/setup_screen.dart';
import 'package:finbiz/features/auth/splash_screen.dart';
import 'package:finbiz/features/categories/categories_screen.dart';
import 'package:finbiz/features/admin/user_management_screen.dart';
import 'package:finbiz/features/budgets/budgets_screen.dart';
import 'package:finbiz/features/dashboard/dashboard_screen.dart';
import 'package:finbiz/features/debts/debts_screen.dart';
import 'package:finbiz/features/home/home_shell.dart';
import 'package:finbiz/features/reports/reports_screen.dart';
import 'package:finbiz/features/savings/savings_screen.dart';
import 'package:finbiz/features/settings/settings_screen.dart';
import 'package:finbiz/features/transactions/transactions_screen.dart';
import 'package:finbiz/data/services/auth_service.dart';
import 'package:finbiz/data/services/api_client.dart';
import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/core/widgets/finbiz_logo.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/user_profile.dart';

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Stream<dynamic> authChanges) {
    _subscription = authChanges.listen((_) => notifyListeners());
  }

  StreamSubscription<dynamic>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

String _profileFailureReason(Object error) {
  if (error is ApiException) {
    final kind = profileFailureFromApi(error).kind;
    return switch (kind) {
      ProfileFailureKind.databaseNotReady => 'database',
      ProfileFailureKind.profilePermissionDenied => 'permission',
      ProfileFailureKind.creatorProvisioningRequired => 'creator-provisioning',
      ProfileFailureKind.missingProfile => 'missing-profile',
      ProfileFailureKind.invalidRole => 'invalid-role',
      ProfileFailureKind.profileUnavailable => 'database',
    };
  }
  return 'database';
}

GoRouter createAppRouter() {
  final authRefresh = _AuthRefreshListenable(
    AuthService(ApiClient.instance).authStateChanges,
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      if (ApiConfig.initializationFailure != null || !ApiConfig.isConfigured) {
        return location == '/setup' ? null : '/setup';
      }
      if (location == '/setup') {
        return '/splash';
      }

      final session = ApiClient.instance.currentUser;
      const publicLocations = {
        '/login',
        '/register',
        '/forgot-password',
        '/reset-password',
      };
      if (session == null) {
        return publicLocations.contains(location) ? null : '/login';
      }
      Map<String, dynamic>? profile;
      try {
        final currentProfile = await AuthService(ApiClient.instance)
            .getProfile();
        profile = currentProfile == null
            ? null
            : {
                'role': currentProfile.role.name,
                'must_change_password': currentProfile.mustChangePassword,
              };
        if (profile == null) {
          return location == '/access-error'
              ? null
              : '/access-error?reason=missing-profile';
        }
      } catch (error) {
        final reason = _profileFailureReason(error);
        return location == '/access-error'
            ? null
            : '/access-error?reason=$reason';
      }

      final roleName = profile['role'] as String?;
      if (roleName == null ||
          !UserRole.values.any((role) => role.name == roleName)) {
        return location == '/access-error'
            ? null
            : '/access-error?reason=invalid-role';
      }

      final mustChangePassword =
          profile['must_change_password'] as bool? ?? false;
      if (mustChangePassword && location != '/change-password') {
        return '/change-password';
      }
      if (publicLocations.contains(location) ||
          location == '/splash' ||
          location == '/access-error') {
        return '/dashboard';
      }
      if (location == '/admin/users' || location == '/creator/system') {
        final role = userRoleFromString(roleName);
        if (location == '/creator/system' && role != UserRole.creator) {
          return '/dashboard';
        }
        if (location == '/admin/users' &&
            role != UserRole.admin &&
            role != UserRole.creator) {
          return '/dashboard';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const AuthScreen(mode: AuthScreenMode.login),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            const AuthScreen(mode: AuthScreenMode.register),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) =>
            const AuthScreen(mode: AuthScreenMode.forgotPassword),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ChangePasswordScreen(
          email: state.uri.queryParameters['email'],
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/access-error',
        builder: (context, state) =>
            _AccessErrorScreen(reason: state.uri.queryParameters['reason']),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/debts',
            builder: (context, state) => const DebtsScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/savings',
            builder: (context, state) => const SavingsScreen(),
          ),
          GoRoute(
            path: '/budgets',
            builder: (context, state) => const BudgetsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/creator/system',
            builder: (context, state) => const _RolePlaceholderScreen(
              title: 'Pengaturan sistem',
              description: 'Konfigurasi aplikasi hanya tersedia untuk Creator.',
            ),
          ),
        ],
      ),
    ],
  );
}

class _RolePlaceholderScreen extends StatelessWidget {
  const _RolePlaceholderScreen({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(description, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _AccessErrorScreen extends StatelessWidget {
  const _AccessErrorScreen({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final (title, message, icon, color) = switch (reason) {
      'missing-profile' => (
        'Profil belum tersedia',
        'Login berhasil, tetapi profil akun belum ditemukan. Minta pengelola memeriksa provisioning profil dan memastikan profiles.id sama dengan ID akun Auth.',
        Icons.person_search_rounded,
        AppTheme.warning,
      ),
      'invalid-role' => (
        'Role akun tidak valid',
        'Profil ditemukan, tetapi role tidak dikenali. Minta Creator memeriksa role akun melalui proses administrasi.',
        Icons.admin_panel_settings_outlined,
        AppTheme.warning,
      ),
      'permission' => (
        'Akses profil ditolak',
        'Login berhasil, tetapi kebijakan RLS menolak pembacaan profil. Pengelola perlu memastikan pengguna dapat membaca profilnya sendiri.',
        Icons.lock_outline_rounded,
        AppTheme.error,
      ),
      'creator-provisioning' => (
        'Profil Creator belum disiapkan',
        'Akun Creator berhasil diautentikasi, tetapi profilnya belum diprovisikan. Administrator perlu memeriksa konfigurasi provisioning akun.',
        Icons.admin_panel_settings_outlined,
        AppTheme.warning,
      ),
      'database' => (
        'Profil belum dapat dimuat',
        'Login berhasil, tetapi API FinBiz tidak dapat membaca profil dari database MySQL. Pengelola perlu memeriksa migration dan konfigurasi API.',
        Icons.storage_rounded,
        AppTheme.error,
      ),
      _ => (
        'Profil belum dapat diverifikasi',
        'Sesi login aktif, tetapi profil belum dapat dibaca. Periksa koneksi API dan database MySQL.',
        Icons.cloud_off_rounded,
        AppTheme.error,
      ),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FinBizLogo(size: 24),
                      const SizedBox(height: 28),
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: color.withValues(alpha: 0.1),
                        child: Icon(icon, size: 32, color: color),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => GoRouter.of(context).refresh(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Coba lagi'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await AuthService(ApiClient.instance).signOut();
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(authErrorMessage(error)),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Keluar dan masuk ulang'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
