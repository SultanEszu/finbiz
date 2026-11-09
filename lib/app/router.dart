import 'dart:async';

import 'package:finbiz/core/constants/supabase_config.dart';
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
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/user_profile.dart';

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Stream<AuthState>? authChanges) {
    _subscription = authChanges?.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        isPasswordRecovery = true;
      } else if (state.event == AuthChangeEvent.userUpdated ||
          state.event == AuthChangeEvent.signedOut) {
        isPasswordRecovery = false;
      }
      notifyListeners();
    });
  }

  StreamSubscription<AuthState>? _subscription;
  bool isPasswordRecovery = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

GoRouter createAppRouter() {
  final authRefresh = _AuthRefreshListenable(
    SupabaseConfig.isConfigured && SupabaseConfig.initializationFailure == null
        ? Supabase.instance.client.auth.onAuthStateChange
        : null,
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      if (SupabaseConfig.initializationFailure != null ||
          !SupabaseConfig.isConfigured) {
        return location == '/setup' ? null : '/setup';
      }
      if (location == '/setup') {
        return '/splash';
      }

      final session = Supabase.instance.client.auth.currentSession;
      const publicLocations = {'/login', '/register', '/forgot-password'};
      if (session == null) {
        return publicLocations.contains(location) ? null : '/login';
      }
      if (authRefresh.isPasswordRecovery && location != '/change-password') {
        return '/change-password';
      }
      if (publicLocations.contains(location) || location == '/splash') {
        return '/dashboard';
      }

      Map<String, dynamic>? profile;
      try {
        profile = await Supabase.instance.client
            .from('profiles')
            .select('role, must_change_password')
            .eq('id', session.user.id)
            .maybeSingle();
        if (profile == null) {
          return location == '/access-error'
              ? null
              : '/access-error?reason=missing-profile';
        }
      } catch (_) {
        return location == '/access-error'
            ? null
            : '/access-error?reason=database';
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
        redirect: (context, state) => '/change-password',
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
    final message = switch (reason) {
      'missing-profile' => 'Sesi login aktif, tetapi profil belum tersedia. Minta pengelola memeriksa provisioning akun.',
      'invalid-role' => 'Profil ditemukan, tetapi role tidak valid. Minta Creator memeriksa role akun.',
      'database' => 'Sesi login aktif, tetapi database/profil tidak dapat dibaca. Minta pengelola memeriksa migration dan RLS.',
      _ => 'Sesi Anda aktif, tetapi profil atau database belum dapat diverifikasi. Minta pengelola memastikan migration Supabase sudah diterapkan.',
    };
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Periksa kembali'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
