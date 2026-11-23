import 'dart:async';

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

import 'package:finbiz/data/models/app_user.dart';

String _profileFailureReason(Object error) => 'database';

class _AuthRouterRefresh extends ChangeNotifier {
  _AuthRouterRefresh(Stream<AppUser?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AppUser?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter createAppRouter() {
  final authRefresh = _AuthRouterRefresh(ApiClient.instance.authStateChanges);
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final loggedIn = ApiClient.instance.currentUser != null;
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';
      if (!loggedIn && !loggingIn && state.matchedLocation != '/setup') {
        return '/login';
      }
      if (loggedIn && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(path: '/login', builder: (context, state) => const AuthScreen(mode: AuthScreenMode.login)),
      GoRoute(path: '/register', builder: (context, state) => const AuthScreen(mode: AuthScreenMode.register)),
      GoRoute(path: '/forgot-password', builder: (context, state) => const AuthScreen(mode: AuthScreenMode.forgotPassword)),
      GoRoute(path: '/change-password', builder: (context, state) => const ChangePasswordScreen()),
      GoRoute(path: '/reset-password', builder: (context, state) => ChangePasswordScreen(email: state.uri.queryParameters['email'], token: state.uri.queryParameters['token'])),
      GoRoute(path: '/access-error', builder: (context, state) => _AccessErrorScreen(reason: state.uri.queryParameters['reason'])),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/transactions', builder: (context, state) => const TransactionsScreen()),
          GoRoute(path: '/categories', builder: (context, state) => const CategoriesScreen()),
          GoRoute(path: '/debts', builder: (context, state) => const DebtsScreen()),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/savings', builder: (context, state) => const SavingsScreen()),
          GoRoute(path: '/budgets', builder: (context, state) => const BudgetsScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
          GoRoute(path: '/admin/users', builder: (context, state) => const UserManagementScreen()),
          GoRoute(path: '/creator/system', builder: (context, state) => const _RolePlaceholderScreen(title: 'Pengaturan sistem', description: 'Konfigurasi aplikasi lokal FinBiz.')),
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
        'Login berhasil, tetapi profil lokal belum dapat dimuat. Periksa penyimpanan FinBiz pada perangkat.',
        Icons.storage_rounded,
        AppTheme.error,
      ),
      _ => (
        'Profil belum dapat diverifikasi',
        'Sesi login aktif, tetapi profil lokal belum dapat dibaca. Periksa penyimpanan FinBiz pada perangkat.',
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
