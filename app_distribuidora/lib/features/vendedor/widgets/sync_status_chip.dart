import 'package:flutter/material.dart';

import '../models/visita.dart';
import 'terreno_badges.dart';

/// Indicador de sincronización con badge uniforme.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context) {
    if (visita.syncStatus == SyncStatus.synced &&
        visita.estado == VisitaEstado.pendiente) {
      return const SizedBox.shrink();
    }
    return TerrenoBadge(
      kind: badgeKindForSyncStatus(visita.syncStatus),
      compact: true,
    );
  }
}
