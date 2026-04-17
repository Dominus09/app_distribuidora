import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Indicador global de red y actividad de sincronización (Home y ruta).
class TerrenoSyncBanner extends StatelessWidget {
  const TerrenoSyncBanner({
    super.key,
    required this.interfaceConnected,
    required this.anyItemSyncing,
    required this.batchSyncing,
  });

  /// Wi‑Fi / datos / ethernet según `connectivity_plus` (sin validar API).
  final bool interfaceConnected;

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

    if (!interfaceConnected) {
      text =
          'Sin conexión. Los registros se guardarán y se sincronizarán después.';
      bg = AppColors.primaryRed.withValues(alpha: 0.08);
      fg = AppColors.primaryRed;
      icon = Icons.wifi_off_rounded;
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
