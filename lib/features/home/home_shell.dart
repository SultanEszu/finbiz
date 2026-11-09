import 'package:finbiz/core/providers/supabase_providers.dart';
import 'package:finbiz/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final profile = ref
        .watch(currentProfileProvider)
        .when(
          data: (value) => value,
          loading: () => null,
          error: (error, stackTrace) => null,
        );
    final isAdmin = profile?.role.name == 'admin';
    final isCreator = profile?.role.name == 'creator';
    final destinations = <({String path, String label, IconData icon})>[
      (path: '/dashboard', label: 'Beranda', icon: Icons.dashboard_outlined),
      (
        path: '/transactions',
        label: 'Transaksi',
        icon: Icons.swap_horiz_outlined,
      ),
      (
        path: '/reports',
        label: 'Statistik',
        icon: Icons.pie_chart_outline_rounded,
      ),
      if (isAdmin || isCreator)
        (
          path: '/admin/users',
          label: 'Pengguna',
          icon: Icons.people_outline_rounded,
        )
      else
        (path: '/savings', label: 'Tabungan', icon: Icons.savings_outlined),
      if (isCreator)
        (path: '/creator/system', label: 'Sistem', icon: Icons.tune_rounded),
      (path: '/settings', label: 'Profil', icon: Icons.person_outline_rounded),
    ];
    final selectedIndex = destinations.indexWhere(
      (item) => item.path == location,
    );

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onDestinationSelected: (index) {
            context.go(destinations[index].path);
          },
          destinations: destinations
              .map(
                (item) => NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                ),
              )
              .toList(),
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.primaryBlue.withValues(alpha: 0.08),
          surfaceTintColor: Colors.transparent,
        ),
      ),
    );
  }
}
