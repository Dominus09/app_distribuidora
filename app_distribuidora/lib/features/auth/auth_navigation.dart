import 'package:flutter/material.dart';

import '../bodega/screens/bodega_home_screen.dart';
import '../chofer/screens/chofer_home_screen.dart';
import '../vendedor/screens/vendedor_home_screen.dart';
import 'models/tipo_usuario.dart';
import 'screens/login_screen.dart';

/// Pantalla principal según rol guardado en sesión.
Widget homeWidgetForRol({
  required DistribuidoraRol rol,
  required String usuarioCodigo,
  required String displayName,
}) {
  return switch (rol) {
    DistribuidoraRol.vendedor => VendedorHomeScreen(
        vendedorCodigo: usuarioCodigo,
        vendedorNombre: displayName,
      ),
    DistribuidoraRol.chofer => const ChoferHomeScreen(),
    DistribuidoraRol.bodega => BodegaHomeScreen(operadorNombre: displayName),
  };
}

/// Tras login o arranque con sesión: una sola entrada de navegación por rol.
void replaceWithHomeForRol(
  BuildContext context, {
  required DistribuidoraRol rol,
  required String usuarioCodigo,
  required String displayName,
}) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => homeWidgetForRol(
        rol: rol,
        usuarioCodigo: usuarioCodigo,
        displayName: displayName,
      ),
    ),
  );
}

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
  replaceWithHomeForRol(
    context,
    rol: DistribuidoraRol.vendedor,
    usuarioCodigo: vendedorCodigo,
    displayName: vendedorNombre,
  );
}
