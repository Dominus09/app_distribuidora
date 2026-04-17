import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../auth_navigation.dart';
import '../services/auth_service.dart';

/// Arranque: sesión guardada → [VendedorHomeScreen]; si no → [DistribuidoraLoginScreen].
class AppStartGate extends StatefulWidget {
  const AppStartGate({super.key});

  @override
  State<AppStartGate> createState() => _AppStartGateState();
}

class _AppStartGateState extends State<AppStartGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveStart());
  }

  Future<void> _resolveStart() async {
    final auth = DistribuidoraAuthService();
    final logged = await auth.isLoggedIn();
    if (!mounted) return;

    if (!logged) {
      replaceRouteWithDistribuidoraLogin(context);
      return;
    }

    final codigo = await auth.readVendedorCodigo();
    final nombre = await auth.readVendedorNombre();
    if (!mounted) return;

    if (codigo == null || codigo.isEmpty) {
      await auth.logout();
      if (!mounted) return;
      replaceRouteWithDistribuidoraLogin(context);
      return;
    }

    if (!mounted) return;
    replaceWithVendedorHome(
      context,
      vendedorCodigo: codigo,
      vendedorNombre: nombre ?? codigo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
