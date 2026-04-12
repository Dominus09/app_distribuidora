import 'package:flutter/material.dart';

import '../models/visita.dart';

/// Indicador compacto de sincronización (listas y detalle).
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = visita.syncStatus == SyncStatus.pendingSync;
    final bg = pending
        ? const Color(0xFFFFF3E0)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final fg = pending ? const Color(0xFFE65100) : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            pending ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
            size: 18,
            color: fg,
          ),
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
