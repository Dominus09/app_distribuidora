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

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        label: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        backgroundColor: color.withValues(alpha: 0.1),
      ),
    );
  }
}
