import 'package:finbiz/core/providers/api_providers.dart';
import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/data/models/user_profile.dart';
import 'package:finbiz/data/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(managedProfilesProvider);
    final currentUserId = ref.read(authServiceProvider).currentUser?.id;
    final currentProfile = ref
        .watch(currentProfileProvider)
        .when(
          data: (profile) => profile,
          loading: () => null,
          error: (error, stackTrace) => null,
        );
    final isCreator = currentProfile?.role == UserRole.creator;

    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen pengguna')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createUser(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah pengguna'),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Daftar pengguna gagal dimuat.'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(managedProfilesProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (users) => users.isEmpty
            ? const Center(child: Text('Belum ada pengguna.'))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(managedProfilesProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: users.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final canDelete =
                        user.id != currentUserId &&
                        (isCreator || user.role == UserRole.user);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryBlue.withValues(
                            alpha: 0.1,
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                        title: Text(
                          user.fullName.isEmpty ? user.email : user.fullName,
                        ),
                        subtitle: Text(
                          '${user.email}\nPeran: ${_roleLabel(user.role)}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCreator && user.id != currentUserId)
                              PopupMenuButton<UserRole>(
                                tooltip: 'Ubah peran',
                                onSelected: (role) =>
                                    _changeRole(context, ref, user, role),
                                itemBuilder: (context) => UserRole.values
                                    .map(
                                      (role) => PopupMenuItem(
                                        value: role,
                                        child: Text(_roleLabel(role)),
                                      ),
                                    )
                                    .toList(),
                                child: const Icon(
                                  Icons.manage_accounts_outlined,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Hapus pengguna',
                              onPressed: canDelete
                                  ? () => _deleteUser(context, ref, user)
                                  : null,
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppTheme.error,
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

  Future<void> _createUser(BuildContext context, WidgetRef ref) async {
    final data = await showDialog<_NewUserData>(
      context: context,
      builder: (context) => const _CreateUserDialog(),
    );
    if (data == null) return;
    try {
      await ref
          .read(authServiceProvider)
          .createManagedUser(
            email: data.email,
            password: data.password,
            fullName: data.fullName,
          );
      ref.invalidate(managedProfilesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Akun pengguna berhasil dibuat.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    UserProfile user,
    UserRole role,
  ) async {
    try {
      await ref.read(authServiceProvider).setUserRole(user.id, role);
      ref.invalidate(managedProfilesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Peran pengguna berhasil diperbarui.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
  }

  Future<void> _deleteUser(
    BuildContext context,
    WidgetRef ref,
    UserProfile user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus akun pengguna?'),
        content: Text(
          'Akun ${user.email} dan data terkait akan dihapus permanen.',
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
      await ref.read(authServiceProvider).deleteManagedUser(user.id);
      ref.invalidate(managedProfilesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
  }

  String _roleLabel(UserRole role) => switch (role) {
    UserRole.user => 'Pengguna',
    UserRole.admin => 'Admin',
    UserRole.creator => 'Creator',
  };
}

class _NewUserData {
  const _NewUserData(this.email, this.password, this.fullName);

  final String email;
  final String password;
  final String fullName;
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buat akun pengguna'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama lengkap'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama wajib diisi.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) =>
                    value == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())
                    ? 'Email tidak valid.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kata sandi sementara',
                ),
                validator: (value) => value == null || value.length < 8
                    ? 'Minimal 8 karakter.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NewUserData(
                _email.text.trim(),
                _password.text,
                _name.text.trim(),
              ),
            );
          },
          child: const Text('Buat akun'),
        ),
      ],
    );
  }
}
