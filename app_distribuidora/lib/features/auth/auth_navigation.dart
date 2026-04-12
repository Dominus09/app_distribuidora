import 'package:flutter/material.dart';

import '../vendedor/screens/vendedor_home_screen.dart';
import 'screens/login_screen.dart';

/// Sustituye la pantalla actual (p. ej. splash) por el login.
void replaceRouteWithDistribuidoraLogin(BuildContext context) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => const DistribuidoraLoginScreen(),
    ),
  );
}

/// Evita dependencias circulares entre login y home vendedor.
void replaceWithDistribuidoraLogin(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => const DistribuidoraLoginScreen(),
    ),
    (_) => false,
  );
}

void replaceWithVendedorHome(
  BuildContext context, {
  required String vendedorCodigo,
  required String vendedorNombre,
}) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => VendedorHomeScreen(
        vendedorCodigo: vendedorCodigo,
        vendedorNombre: vendedorNombre,
      ),
    ),
  );
}
