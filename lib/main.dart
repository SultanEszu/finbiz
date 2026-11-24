import 'package:finbiz/app/app.dart';
import 'package:finbiz/data/services/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }
  await initializeDateFormatting('id_ID');
  await ApiClient.instance.initialize();
  runApp(const FinBizApp());
}
