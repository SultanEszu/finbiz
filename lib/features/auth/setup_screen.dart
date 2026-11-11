import 'package:finbiz/core/widgets/finbiz_logo.dart';
import 'package:finbiz/core/constants/api_config.dart';
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
                  'API FinBiz belum dikonfigurasi',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  ApiConfig.initializationFailure ?? 'URL backend API diperlukan untuk menghubungkan aplikasi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Jalankan aplikasi dengan --dart-define=API_BASE_URL=https://alamat-backend-anda.',
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
