import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/data/models/finance_models.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savingsAsync = ref.watch(financeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tabungan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTarget(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Target baru'),
      ),
      body: savingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Data tabungan gagal dimuat.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.read(financeRepositoryProvider.notifier).refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () =>
              ref.read(financeRepositoryProvider.notifier).refresh(),
          child: state.savings.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 180),
                    Center(
                      child: Text(
                        'Belum ada target tabungan. Buat target pertama Anda.',
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.savings.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final target = state.savings[index];
                    final progress =
                        (target.currentAmount / target.targetAmount).clamp(
                          0.0,
                          1.0,
                        );
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
                                    target.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Hapus target',
                                  onPressed: () =>
                                      _deleteTarget(context, ref, target),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppTheme.error,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: progress,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_currency(target.currentAmount)} dari ${_currency(target.targetAmount)}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed:
                                    target.currentAmount >= target.targetAmount
                                    ? null
                                    : () => _addContribution(
                                        context,
                                        ref,
                                        target,
                                      ),
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Tambah setoran'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showAddTarget(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AddSavingsTargetSheet(),
    );
  }

  Future<void> _addContribution(
    BuildContext context,
    WidgetRef ref,
    SavingsTarget target,
  ) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => const _AmountDialog(title: 'Tambah setoran'),
    );
    if (amount == null) return;
    try {
      await ref
          .read(financeRepositoryProvider.notifier)
          .addSavingsContribution(target, amount);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(financeErrorMessage(error))));
      }
    }
  }

  Future<void> _deleteTarget(
    BuildContext context,
    WidgetRef ref,
    SavingsTarget target,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus target tabungan?'),
        content: Text('Target "${target.name}" akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(financeRepositoryProvider.notifier)
          .deleteSavingsTarget(target.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(financeErrorMessage(error))));
      }
    }
  }
}

class _AddSavingsTargetSheet extends ConsumerStatefulWidget {
  const _AddSavingsTargetSheet();

  @override
  ConsumerState<_AddSavingsTargetSheet> createState() =>
      _AddSavingsTargetSheetState();
}

class _AddSavingsTargetSheetState
    extends ConsumerState<_AddSavingsTargetSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nama target'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Jumlah target'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(_isSaving ? 'Menyimpan...' : 'Simpan target'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    if (name.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama dan jumlah target yang valid.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref
          .read(financeRepositoryProvider.notifier)
          .addSavingsTarget(name: name, targetAmount: amount);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(financeErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title});

  final String title;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Jumlah setoran'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_controller.text.trim());
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Masukkan jumlah yang valid.')),
              );
              return;
            }
            Navigator.pop(context, amount);
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

String _currency(double value) => NumberFormat.currency(
  symbol: 'Rp ',
  locale: 'id_ID',
  decimalDigits: 0,
).format(value);
