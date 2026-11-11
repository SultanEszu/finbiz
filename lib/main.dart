import 'package:finbiz/app/app.dart';
import 'package:finbiz/core/constants/api_config.dart';
import 'package:finbiz/data/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  if (ApiConfig.isConfigured) {
    try {
      await ApiClient.instance.initialize();
    } catch (error) {
      ApiConfig.initializationFailure =
          'Backend FinBiz gagal dihubungi. Periksa URL API dan koneksi jaringan ($error).';
    }
  }
  runApp(const FinBizApp());
}
