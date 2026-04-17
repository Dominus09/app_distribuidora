import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/visita.dart';

/// Indicador compacto de sincronización (listas y detalle).
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final Color bg;
    late final Color fg;
    late final IconData icon;

    switch (visita.syncStatus) {
      case SyncStatus.pendingSync:
        bg = AppColors.primaryRed.withValues(alpha: 0.1);
        fg = AppColors.primaryRed;
        icon = Icons.cloud_upload_outlined;
      case SyncStatus.syncing:
        bg = AppColors.secondaryBlue.withValues(alpha: 0.12);
        fg = AppColors.secondaryBlue;
        icon = Icons.cloud_sync_rounded;
      case SyncStatus.syncError:
        bg = AppColors.primaryRed.withValues(alpha: 0.12);
        fg = AppColors.primaryRed;
        icon = Icons.cloud_off_outlined;
      case SyncStatus.synced:
        bg = AppColors.secondaryBlue.withValues(alpha: 0.08);
        fg = AppColors.secondaryBlue;
        icon = Icons.cloud_done_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              visita.syncStatus.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
