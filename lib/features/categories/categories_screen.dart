import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/data/models/finance_models.dart';
import 'package:finbiz/data/repositories/finance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(financeRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kategori')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategorySheet(context, ref),
        child: const Icon(Icons.add),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Kategori gagal dimuat.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.read(financeRepositoryProvider.notifier).refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (state) => state.categories.isEmpty
            ? const Center(
                child: Text(
                  'Belum ada kategori. Tambahkan kategori pertama Anda.',
                ),
              )
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(financeRepositoryProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.categories.length,
                  itemBuilder: (context, index) {
                    final category = state.categories[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: category.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(category.icon, color: category.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  category.isExpense
                                      ? 'Kategori pengeluaran'
                                      : 'Kategori pemasukan',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: category.isExpense
                                  ? AppTheme.error.withValues(alpha: 0.1)
                                  : AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              category.isExpense ? 'Pengeluaran' : 'Pemasukan',
                              style: TextStyle(
                                color: category.isExpense
                                    ? AppTheme.error
                                    : AppTheme.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Hapus kategori',
                            onPressed: () =>
                                _deleteCategory(context, ref, category),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    FinanceCategory category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus kategori?'),
        content: Text(
          'Transaksi terkait tetap tersimpan, tetapi kategorinya akan dilepas.',
        ),
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
          .deleteCategory(category.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(financeErrorMessage(error))));
      }
    }
  }

  void _showAddCategorySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AddCategorySheet(ref: ref),
    );
  }
}

class _AddCategorySheet extends ConsumerStatefulWidget {
  const _AddCategorySheet({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends ConsumerState<_AddCategorySheet> {
  final nameController = TextEditingController();
  bool isExpense = true;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Tambah kategori',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Nama kategori'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            initialValue: isExpense,
            decoration: const InputDecoration(labelText: 'Jenis'),
            items: const [
              DropdownMenuItem(value: true, child: Text('Pengeluaran')),
              DropdownMenuItem(value: false, child: Text('Pemasukan')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => isExpense = value);
              }
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isSaving ? 'Menyimpan...' : 'Simpan kategori'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama kategori tidak boleh kosong.')),
      );
      return;
    }

    final category = FinanceCategory(
      id: const Uuid().v4(),
      name: name,
      iconName: isExpense ? 'shopping_cart' : 'trending_up',
      colorValue: isExpense
          ? AppTheme.error.toARGB32()
          : AppTheme.success.toARGB32(),
      isExpense: isExpense,
    );

    setState(() => _isSaving = true);
    try {
      await ref.read(financeRepositoryProvider.notifier).addCategory(category);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori berhasil disimpan.')),
      );
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
