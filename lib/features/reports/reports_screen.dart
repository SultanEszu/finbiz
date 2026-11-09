import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeAsync = ref.watch(financeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik')),
      body: financeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Laporan gagal dimuat.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.read(financeRepositoryProvider.notifier).refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (state) {
          final summary = state.categorySummary;
          final totalSpent = summary.fold<double>(
            0,
            (sum, item) => sum + item.amount,
          );
          if (summary.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Belum ada data pengeluaran untuk ditampilkan.'),
              ),
            );
          }

          final colors = [
            AppTheme.primaryBlue,
            AppTheme.success,
            AppTheme.warning,
            AppTheme.accentBlue,
          ];
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(financeRepositoryProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total pengeluaran',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currency(totalSpent),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 220,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 4,
                          centerSpaceRadius: 40,
                          sections: summary.asMap().entries.map((entry) {
                            final value = entry.value;
                            return PieChartSectionData(
                              value: value.amount,
                              title: entry.key < 3 ? value.category : '',
                              radius: 75,
                              color: colors[entry.key % colors.length],
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...summary.asMap().entries.map((entry) {
                  final item = entry.value;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 6,
                        backgroundColor: colors[entry.key % colors.length],
                      ),
                      title: Text(item.category),
                      trailing: Text(
                        _currency(item.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _currency(double value) => NumberFormat.currency(
  symbol: 'Rp ',
  locale: 'id_ID',
  decimalDigits: 0,
).format(value);
