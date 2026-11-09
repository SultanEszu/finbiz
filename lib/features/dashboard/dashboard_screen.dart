import 'dart:math' as math;

import 'package:finbiz/core/providers/supabase_providers.dart';
import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/core/widgets/finbiz_logo.dart';
import 'package:finbiz/data/models/finance_models.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:finbiz/features/transactions/transactions_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

enum DashboardPeriod { today, week, month, year }

extension on DashboardPeriod {
  String get label => switch (this) {
    DashboardPeriod.today => 'Hari ini',
    DashboardPeriod.week => 'Minggu ini',
    DashboardPeriod.month => 'Bulan ini',
    DashboardPeriod.year => 'Tahun ini',
  };
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeAsync = ref.watch(financeRepositoryProvider);
    final profile = ref
        .watch(currentProfileProvider)
        .when(
          data: (value) => value,
          loading: () => null,
          error: (error, stackTrace) => null,
        );

    return Scaffold(
      appBar: AppBar(
        title: const FinBizLogo(size: 20),
        actions: [
          IconButton(
            tooltip: 'Perbarui data',
            onPressed: () =>
                ref.read(financeRepositoryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: financeAsync.when(
        loading: () => const _DashboardLoading(),
        error: (error, stackTrace) => _DashboardError(
          onRetry: () => ref.read(financeRepositoryProvider.notifier).refresh(),
        ),
        data: (state) => _DashboardContent(
          state: state,
          name: profile?.fullName ?? '',
          onRefresh: () =>
              ref.read(financeRepositoryProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatefulWidget {
  const _DashboardContent({
    required this.state,
    required this.name,
    required this.onRefresh,
  });

  final FinanceState state;
  final String name;
  final Future<void> Function() onRefresh;

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  DashboardPeriod _period = DashboardPeriod.month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = _periodStart(now);
    final today = DateTime(now.year, now.month, now.day);
    final periodTransactions = widget.state.transactions.where((item) {
      final date = DateTime(item.date.year, item.date.month, item.date.day);
      return !date.isBefore(start) && !date.isAfter(today);
    }).toList();
    final income = _sum(periodTransactions, TransactionType.income);
    final expense = _sum(periodTransactions, TransactionType.expense);
    final budgets = widget.state.budgets
        .where(
          (item) =>
              !today.isBefore(
                DateTime(
                  item.startDate.year,
                  item.startDate.month,
                  item.startDate.day,
                ),
              ) &&
              !today.isAfter(
                DateTime(
                  item.endDate.year,
                  item.endDate.month,
                  item.endDate.day,
                ),
              ),
        )
        .toList();
    final budgetLimit = budgets.fold<double>(
      0,
      (total, item) => total + item.amount,
    );
    final budgetSpent = widget.state.transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              budgets.any((budget) {
                final date = DateTime(
                  item.date.year,
                  item.date.month,
                  item.date.day,
                );
                final budgetStart = DateTime(
                  budget.startDate.year,
                  budget.startDate.month,
                  budget.startDate.day,
                );
                final budgetEnd = DateTime(
                  budget.endDate.year,
                  budget.endDate.month,
                  budget.endDate.day,
                );
                return !date.isBefore(budgetStart) && !date.isAfter(budgetEnd);
              }),
        )
        .fold<double>(0, (total, item) => total + item.amount);
    final recent = widget.state.recentTransactions.take(4).toList();
    final categoryTotals = <String, double>{};
    for (final transaction in periodTransactions.where(
      (item) => item.type == TransactionType.expense,
    )) {
      final category = widget.state.categories
          .where((item) => item.id == transaction.categoryId)
          .toList();
      final name = category.isEmpty ? 'Lainnya' : category.first.name;
      categoryTotals[name] = (categoryTotals[name] ?? 0) + transaction.amount;
    }
    final categorySummary =
        categoryTotals.entries
            .map((item) => (category: item.key, amount: item.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Halo${widget.name.trim().isEmpty ? '' : ', ${widget.name.trim()}'}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Kelola Keuangan Bisnis Lebih Mudah.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DashboardPeriod.values.map((period) {
              return ChoiceChip(
                label: Text(period.label),
                selected: period == _period,
                onSelected: (_) => setState(() => _period = period),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SummaryMetricCard(
                  title: 'Pemasukan',
                  value: _currency(income),
                  color: AppTheme.success,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryMetricCard(
                  title: 'Pengeluaran',
                  value: _currency(expense),
                  color: AppTheme.error,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BalanceCard(balance: widget.state.totalBalance),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      _openAddTransaction(context, TransactionType.income),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Pemasukan'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openAddTransaction(context, TransactionType.expense),
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('Pengeluaran'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ChartCard(
            transactions: periodTransactions,
            period: _period,
            now: now,
          ),
          const SizedBox(height: 16),
          _BudgetCard(
            limit: budgetLimit,
            spent: budgetSpent,
            onManage: () => context.go('/budgets'),
          ),
          const SizedBox(height: 16),
          _NotificationsCard(notifications: widget.state.notifications),
          const SizedBox(height: 16),
          _CategoryBreakdownCard(summary: categorySummary.take(4).toList()),
          const SizedBox(height: 16),
          _RecentTransactionsCard(
            transactions: recent,
            categories: widget.state.categories,
          ),
        ],
      ),
    );
  }

  DateTime _periodStart(DateTime now) {
    switch (_period) {
      case DashboardPeriod.today:
        return DateTime(now.year, now.month, now.day);
      case DashboardPeriod.week:
        final today = DateTime(now.year, now.month, now.day);
        return today.subtract(Duration(days: today.weekday - 1));
      case DashboardPeriod.month:
        return DateTime(now.year, now.month);
      case DashboardPeriod.year:
        return DateTime(now.year);
    }
  }

  double _sum(List<FinanceTransaction> transactions, TransactionType type) {
    return transactions
        .where((item) => item.type == type)
        .fold<double>(0, (total, item) => total + item.amount);
  }

  void _openAddTransaction(BuildContext context, TransactionType type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddTransactionSheet(initialType: type),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.transactions,
    required this.period,
    required this.now,
  });

  final List<FinanceTransaction> transactions;
  final DashboardPeriod period;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final buckets = _buckets();
    final values = buckets.map((bucket) {
      var income = 0.0;
      var expense = 0.0;
      for (final item in transactions) {
        if (item.date.isBefore(bucket.start) ||
            !item.date.isBefore(bucket.end)) {
          continue;
        }
        if (item.type == TransactionType.income) {
          income += item.amount;
        } else {
          expense += item.amount;
        }
      }
      return (income: income, expense: expense);
    }).toList();
    final maxValue = values.fold<double>(
      0,
      (maximum, item) => math.max(maximum, math.max(item.income, item.expense)),
    );
    final maxY = maxValue == 0 ? 1.0 : maxValue * 1.2;

    return _SectionCard(
      title: 'Pemasukan & pengeluaran',
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: values.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.income,
                        color: AppTheme.success,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                      ),
                      BarChartRodData(
                        toY: entry.value.expense,
                        color: AppTheme.error,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            buckets[index].label,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 18,
            children: [
              _Legend(color: AppTheme.success, label: 'Pemasukan'),
              _Legend(color: AppTheme.error, label: 'Pengeluaran'),
            ],
          ),
        ],
      ),
    );
  }

  List<({DateTime start, DateTime end, String label})> _buckets() {
    switch (period) {
      case DashboardPeriod.today:
        final start = DateTime(now.year, now.month, now.day);
        return [
          (
            start: start,
            end: start.add(const Duration(days: 1)),
            label: 'Hari ini',
          ),
        ];
      case DashboardPeriod.week:
        final today = DateTime(now.year, now.month, now.day);
        final monday = today.subtract(Duration(days: today.weekday - 1));
        const labels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
        return List.generate(7, (index) {
          final start = monday.add(Duration(days: index));
          return (
            start: start,
            end: start.add(const Duration(days: 1)),
            label: labels[index],
          );
        });
      case DashboardPeriod.month:
        final start = DateTime(now.year, now.month);
        final days = DateTime(now.year, now.month + 1).difference(start).inDays;
        return List.generate(5, (index) {
          final firstDay = index * 7 + 1;
          final lastDay = math.min(firstDay + 7, days + 1);
          final bucketStart = start.add(Duration(days: firstDay - 1));
          final bucketEnd = start.add(Duration(days: lastDay - 1));
          return (
            start: bucketStart,
            end: bucketEnd,
            label: '$firstDay-${math.min(lastDay - 1, days)}',
          );
        }).where((item) => !item.start.isAfter(now)).toList();
      case DashboardPeriod.year:
        return List.generate(12, (index) {
          final start = DateTime(now.year, index + 1);
          final end = DateTime(now.year, index + 2);
          return (
            start: start,
            end: end,
            label: DateFormat('MMM', 'id_ID').format(start),
          );
        }).where((item) => !item.start.isAfter(now)).toList();
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.limit,
    required this.spent,
    required this.onManage,
  });

  final double limit;
  final double spent;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final hasBudget = limit > 0;
    final progress = hasBudget ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    return _SectionCard(
      title: 'Anggaran aktif',
      trailing: TextButton(onPressed: onManage, child: const Text('Kelola')),
      child: hasBudget
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_currency(spent)} dari ${_currency(limit)}'),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            )
          : const Text('Belum ada anggaran aktif.'),
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.notifications});

  final List<FinanceNotification> notifications;

  @override
  Widget build(BuildContext context) {
    final unread = notifications.where((item) => !item.isRead).take(2).toList();
    return _SectionCard(
      title: 'Notifikasi keuangan',
      child: unread.isEmpty
          ? const Text('Belum ada notifikasi baru.')
          : Column(
              children: unread
                  .map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.notifications_none_rounded,
                        color: AppTheme.primaryBlue,
                      ),
                      title: Text(item.title),
                      subtitle: Text(item.message),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({required this.summary});

  final List<({String category, double amount})> summary;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Kategori pengeluaran teratas',
      child: summary.isEmpty
          ? const Text('Belum ada pengeluaran pada periode ini.')
          : Column(
              children: summary
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 9,
                            color: AppTheme.accentBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item.category)),
                          Text(
                            _currency(item.amount),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _RecentTransactionsCard extends StatelessWidget {
  const _RecentTransactionsCard({
    required this.transactions,
    required this.categories,
  });

  final List<FinanceTransaction> transactions;
  final List<FinanceCategory> categories;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Transaksi terbaru',
      child: transactions.isEmpty
          ? const Text('Transaksi terbaru akan tampil di sini.')
          : Column(
              children: transactions.map((item) {
                final category = categories
                    .where((value) => value.id == item.categoryId)
                    .toList();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.type == TransactionType.income
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: item.type == TransactionType.income
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    '${category.isEmpty ? 'Kategori' : category.first.name} • '
                    '${DateFormat('dd MMM yyyy', 'id_ID').format(item.date)}',
                  ),
                  trailing: Text(
                    '${item.type == TransactionType.income ? '+' : '-'}${_currency(item.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: item.type == TransactionType.income
                          ? AppTheme.success
                          : AppTheme.error,
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class SummaryMetricCard extends StatelessWidget {
  const SummaryMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryBlue, AppTheme.accentBlue],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo tersedia',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  _currency(balance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.white,
            size: 28,
          ),
        ],
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SkeletonBlock(width: 180, height: 28),
        const SizedBox(height: 8),
        _SkeletonBlock(width: 260, height: 16),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _SkeletonBlock(height: 108)),
            const SizedBox(width: 12),
            Expanded(child: _SkeletonBlock(height: 108)),
          ],
        ),
        const SizedBox(height: 16),
        _SkeletonBlock(height: 100),
        const SizedBox(height: 16),
        _SkeletonBlock(height: 230),
        const SizedBox(height: 16),
        _SkeletonBlock(height: 120),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.border.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Ringkasan keuangan gagal dimuat. Periksa koneksi Supabase Anda.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

String _currency(double value) {
  return NumberFormat.currency(
    symbol: 'Rp ',
    locale: 'id_ID',
    decimalDigits: 0,
  ).format(value);
}
