import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Progreso de ruta destacado para lectura rápida en terreno.
class RutaProgresoCard extends StatelessWidget {
  const RutaProgresoCard({
    super.key,
    required this.atendidos,
    required this.total,
    required this.visitados,
    required this.incidencias,
    required this.pendientes,
  });

  final int atendidos;
  final int total;
  final int visitados;
  final int incidencias;
  final int pendientes;

  double get _frac => total <= 0 ? 0.0 : (atendidos / total).clamp(0.0, 1.0);

  int get _pct => (total <= 0 ? 0 : (_frac * 100).round());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.secondaryBlue.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.secondaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Progreso de ruta',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppColors.secondaryBlue,
              ),
            ),
            const SizedBox(height: 14),
            if (total > 0) ...[
              Text(
                _barraVisual(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  minHeight: 18,
                  value: _frac,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: AppColors.secondaryBlue,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$atendidos de $total clientes',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              Text(
                '$_pct%',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondaryBlue,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      label: 'Visitados',
                      value: '$visitados',
                      color: AppColors.secondaryBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatChip(
                      label: 'Incidencias',
                      value: '$incidencias',
                      color: AppColors.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatChip(
                      label: 'Pendientes',
                      value: '$pendientes',
                      color: AppColors.estadoPendiente,
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                'Sin clientes cargados para hoy.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _barraVisual() {
    const n = 18;
    final filled = (_frac * n).round().clamp(0, n);
    return '${'█' * filled}${'░' * (n - filled)}';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
