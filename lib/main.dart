import 'package:finbiz/app/app.dart';
import 'package:finbiz/data/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  await ApiClient.instance.initialize();
  runApp(const FinBizApp());
}
