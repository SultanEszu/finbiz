import 'package:finbiz/app/router.dart';
import 'package:finbiz/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FinBizApp extends StatefulWidget {
  const FinBizApp({super.key});

  @override
  State<FinBizApp> createState() => _FinBizAppState();
}

class _FinBizAppState extends State<FinBizApp> {
  late final _router = createAppRouter();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: 'FinBiz',
        theme: AppTheme.buildTheme(),
        routerConfig: _router,
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}
