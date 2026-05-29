import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Bloque de ruta en curso: posición y próxima parada.
class RutaActivaCard extends StatelessWidget {
  const RutaActivaCard({
    super.key,
    required this.clienteActual,
    required this.totalClientes,
    this.proximaParadaNombre,
    this.visible = true,
  });

  final int clienteActual;
  final int totalClientes;
  final String? proximaParadaNombre;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || totalClientes <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final proxima = proximaParadaNombre?.trim();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.estadoPendiente.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: AppColors.estadoPendiente.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: theme.colorScheme.secondary,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  'Ruta activa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Cliente actual: $clienteActual de $totalClientes',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (proxima != null && proxima.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Próxima parada:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                proxima,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondaryBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
