import 'package:finbiz/core/widgets/finbiz_logo.dart';
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
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FinBizLogo(),
                SizedBox(height: 24),
                Text('FinBiz siap digunakan', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                Text('Aplikasi berjalan dalam mode lokal tanpa backend.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
