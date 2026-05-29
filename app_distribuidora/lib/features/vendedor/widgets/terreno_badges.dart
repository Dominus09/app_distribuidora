import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/visita.dart';

/// Badges uniformes para estado operacional en terreno.
enum TerrenoBadgeKind {
  pendiente,
  visitado,
  incidencia,
  sinCompra,
  conCompra,
  sincronizado,
  pendienteSync,
  reenviando,
  errorSync,
}

TerrenoBadgeKind badgeKindForVisitaEstado(VisitaEstado e) => switch (e) {
      VisitaEstado.pendiente => TerrenoBadgeKind.pendiente,
      VisitaEstado.visitado => TerrenoBadgeKind.visitado,
      VisitaEstado.incidencia => TerrenoBadgeKind.incidencia,
    };

TerrenoBadgeKind badgeKindForSyncStatus(SyncStatus s) => switch (s) {
      SyncStatus.synced => TerrenoBadgeKind.sincronizado,
      SyncStatus.pendingSync => TerrenoBadgeKind.pendienteSync,
      SyncStatus.syncing => TerrenoBadgeKind.reenviando,
      SyncStatus.syncError => TerrenoBadgeKind.errorSync,
      SyncStatus.deadLetter => TerrenoBadgeKind.errorSync,
    };

class TerrenoBadge extends StatelessWidget {
  const TerrenoBadge({
    super.key,
    required this.kind,
    this.compact = false,
  });

  final TerrenoBadgeKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, fg, bg) = _style();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 12 : 13,
        ),
      ),
    );
  }

  (String, Color, Color) _style() => switch (kind) {
        TerrenoBadgeKind.pendiente => (
            '🟡 Pendiente',
            const Color(0xFFF57F17),
            AppColors.estadoPendiente.withValues(alpha: 0.18),
          ),
        TerrenoBadgeKind.visitado => (
            '🟢 Visitado',
            AppColors.secondaryBlue,
            AppColors.secondaryBlue.withValues(alpha: 0.12),
          ),
        TerrenoBadgeKind.incidencia => (
            '🔴 Incidencia',
            AppColors.primaryRed,
            AppColors.primaryRed.withValues(alpha: 0.12),
          ),
        TerrenoBadgeKind.sinCompra => (
            '⚪ Sin compra',
            const Color(0xFF616161),
            Colors.grey.withValues(alpha: 0.14),
          ),
        TerrenoBadgeKind.conCompra => (
            '🟢 Con compra',
            AppColors.secondaryBlue,
            AppColors.secondaryBlue.withValues(alpha: 0.1),
          ),
        TerrenoBadgeKind.sincronizado => (
            '🟢 Sincronizado',
            AppColors.secondaryBlue,
            AppColors.secondaryBlue.withValues(alpha: 0.1),
          ),
        TerrenoBadgeKind.pendienteSync => (
            '🟠 Pendiente Sync',
            const Color(0xFFE65100),
            const Color(0xFFFF9800).withValues(alpha: 0.18),
          ),
        TerrenoBadgeKind.reenviando => (
            '🔵 Reenviando',
            AppColors.secondaryBlue,
            AppColors.secondaryBlue.withValues(alpha: 0.12),
          ),
        TerrenoBadgeKind.errorSync => (
            '🔴 Error Sync',
            AppColors.primaryRed,
            AppColors.primaryRed.withValues(alpha: 0.12),
          ),
      };
}
