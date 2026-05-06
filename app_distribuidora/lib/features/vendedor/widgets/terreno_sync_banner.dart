import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Indicador global de red y actividad de sincronización (Home y ruta).
class TerrenoSyncBanner extends StatelessWidget {
  const TerrenoSyncBanner({
    super.key,
    required this.canSyncWithServer,
    required this.interfaceConnectivityDetected,
    required this.anyItemSyncing,
    required this.batchSyncing,
  });

  /// Hay permiso/intento de usar API (`connectivity_plus` y/o servidor alcanzable).
  final bool canSyncWithServer;

  /// `connectivity_plus` informa interfaz con datos útil (wifi/móvil/ethernet…).
  final bool interfaceConnectivityDetected;

  /// Alguna visita en estado `syncing`.
  final bool anyItemSyncing;

  /// Sincronización forzada en curso desde Home.
  final bool batchSyncing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    late final String text;
    late final Color bg;
    late final Color fg;
    late final IconData icon;

    if (!canSyncWithServer) {
      text =
          'Sin acceso al servidor ahora. Los registros se guardan en el dispositivo y se envían cuando sea posible.';
      bg = AppColors.primaryRed.withValues(alpha: 0.08);
      fg = AppColors.primaryRed;
      icon = Icons.wifi_off_rounded;
    } else if (!interfaceConnectivityDetected) {
      text =
          'Servidor accesible; la interfaz no reportó tipo de red. Los envíos se intentan igualmente.';
      bg = AppColors.secondaryBlue.withValues(alpha: 0.1);
      fg = AppColors.secondaryBlue;
      icon = Icons.cloud_queue_outlined;
    } else if (batchSyncing || anyItemSyncing) {
      text = 'Sincronizando registros pendientes…';
      bg = AppColors.secondaryBlue.withValues(alpha: 0.1);
      fg = AppColors.secondaryBlue;
      icon = Icons.cloud_sync_rounded;
    } else {
      text = 'Conectado';
      bg = AppColors.secondaryBlue.withValues(alpha: 0.08);
      fg = AppColors.secondaryBlue;
      icon = Icons.cloud_done_outlined;
    }

    return Material(
      color: bg,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
