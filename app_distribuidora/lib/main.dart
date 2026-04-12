import 'package:flutter/material.dart';

import 'auth/screens/login_screen.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';

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
      themeMode: ThemeMode.system,
      home: const LoginScreen(),
    );
  }
}
