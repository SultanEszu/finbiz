import 'package:finbiz/core/theme/app_theme.dart';
import 'package:finbiz/core/widgets/finbiz_logo.dart';
import 'package:finbiz/core/providers/supabase_providers.dart';
import 'package:finbiz/data/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum AuthScreenMode { login, register, forgotPassword }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({required this.mode, super.key});

  final AuthScreenMode mode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    AuthScreenMode.login => 'Selamat datang kembali',
    AuthScreenMode.register => 'Buat akun FinBiz',
    AuthScreenMode.forgotPassword => 'Atur ulang kata sandi',
  };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final service = ref.read(authServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Layanan autentikasi belum siap. Periksa konfigurasi dan koneksi Supabase.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      switch (widget.mode) {
        case AuthScreenMode.login:
          await service.signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
          if (mounted) context.go('/dashboard');
        case AuthScreenMode.register:
          await service.register(
            email: _emailController.text,
            password: _passwordController.text,
            fullName: _nameController.text,
          );
          if (!mounted) return;
          final hasSession = service.currentUser != null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasSession ? 'Akun berhasil dibuat.' : 'Akun dibuat. Periksa email untuk konfirmasi sebelum masuk.',
              ),
            ),
          );
          context.go(hasSession ? '/dashboard' : '/login');
        case AuthScreenMode.forgotPassword:
          await service.sendPasswordReset(_emailController.text);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tautan pengaturan ulang dikirim ke email Anda.'),
            ),
          );
          context.go('/login');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: FinBizLogo(size: 28)),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'Kelola Keuangan Bisnis Lebih Mudah.',
                        style: TextStyle(color: AppTheme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      _title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    if (widget.mode == AuthScreenMode.register) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nama lengkap',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Nama lengkap wajib diisi.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(email)
                            ? null
                            : 'Masukkan alamat email yang valid.';
                      },
                    ),
                    if (widget.mode != AuthScreenMode.forgotPassword) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: widget.mode == AuthScreenMode.login
                            ? const [AutofillHints.password]
                            : const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Kata sandi',
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Kata sandi wajib diisi.';
                          }
                          if (widget.mode == AuthScreenMode.register &&
                              value.length < 8) {
                            return 'Kata sandi minimal 8 karakter.';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(switch (widget.mode) {
                              AuthScreenMode.login => 'Masuk',
                              AuthScreenMode.register => 'Daftar',
                              AuthScreenMode.forgotPassword => 'Kirim tautan',
                            }),
                    ),
                    const SizedBox(height: 12),
                    if (widget.mode == AuthScreenMode.login) ...[
                      TextButton(
                        onPressed: () => context.go('/forgot-password'),
                        child: const Text('Lupa kata sandi?'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: const Text('Belum punya akun? Daftar'),
                      ),
                    ] else if (widget.mode != AuthScreenMode.forgotPassword)
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Sudah punya akun? Masuk'),
                      )
                    else
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Kembali ke halaman masuk'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
