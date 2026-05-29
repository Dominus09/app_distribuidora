import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Indicador compacto de conectividad (AppBar / encabezado).
class TerrenoEnlaceChip extends StatelessWidget {
  const TerrenoEnlaceChip({
    super.key,
    required this.canSyncWithServer,
    required this.interfaceConnectivityDetected,
    required this.anyItemSyncing,
    required this.batchSyncing,
  });

  final bool canSyncWithServer;
  final bool interfaceConnectivityDetected;
  final bool anyItemSyncing;
  final bool batchSyncing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final String label;
    late final Color color;

    if (!canSyncWithServer) {
      label = 'Sin conexión';
      color = AppColors.primaryRed;
    } else if (batchSyncing || anyItemSyncing) {
      label = 'Sincronizando';
      color = AppColors.secondaryBlue;
    } else if (!interfaceConnectivityDetected) {
      label = 'En línea';
      color = AppColors.secondaryBlue;
    } else {
      label = 'En línea';
      color = const Color(0xFF2E7D32);
    }

    final texto = switch (label) {
      'Sin conexión' => '🔴 Sin conexión',
      'Sincronizando' => '🟡 Sincronizando',
      _ => '🟢 En línea',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        texto,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}
