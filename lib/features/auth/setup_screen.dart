import 'package:finbiz/core/widgets/finbiz_logo.dart';
import 'package:finbiz/core/constants/supabase_config.dart';
import 'package:flutter/material.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FinBizLogo(),
                const SizedBox(height: 24),
                Text(
                  'Supabase belum dikonfigurasi',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  SupabaseConfig.initializationFailure ?? 'Supabase belum dikonfigurasi. File konfigurasi lokal diperlukan untuk menghubungkan aplikasi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Jalankan aplikasi dengan --dart-define-from-file=supabase.local.json setelah mengisi URL project dan publishable key.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
