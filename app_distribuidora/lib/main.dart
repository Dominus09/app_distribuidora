import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/widgets/app_start_gate.dart';

void main() {
  runApp(const AppDistribuidora());
}

class AppDistribuidora extends StatelessWidget {
  const AppDistribuidora({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.light,
      home: const AppStartGate(),
    );
  }
}
