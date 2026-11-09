import 'package:finbiz/app/app.dart';
import 'package:finbiz/core/constants/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
    } catch (_) {
      SupabaseConfig.initializationFailure = 'Supabase gagal diinisialisasi. Periksa URL, publishable key, dan koneksi jaringan.';
    }
  }
  runApp(const FinBizApp());
}
