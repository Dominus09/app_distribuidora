import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/visita.dart';

/// Indicador discreto de sincronización en la lista de clientes.
class ClienteSyncDot extends StatelessWidget {
  const ClienteSyncDot({super.key, required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context) {
    switch (visita.syncStatus) {
      case SyncStatus.synced:
        return Tooltip(
          message: 'Sincronizado con el servidor',
          child: const Icon(
            Icons.cloud_done_outlined,
            size: 17,
            color: AppColors.secondaryBlue,
          ),
        );
      case SyncStatus.pendingSync:
        return Tooltip(
          message: 'Pendiente de sincronización',
          child: const Icon(
            Icons.cloud_upload_outlined,
            size: 17,
            color: AppColors.primaryRed,
          ),
        );
      case SyncStatus.syncing:
        return Tooltip(
          message: 'Sincronizando…',
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.secondaryBlue,
            ),
          ),
        );
      case SyncStatus.syncError:
        return Tooltip(
          message: 'Error de sincronización',
          child: const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.primaryRed,
          ),
        );
    }
  }
}
