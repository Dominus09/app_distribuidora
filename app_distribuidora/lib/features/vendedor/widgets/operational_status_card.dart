import 'package:flutter/material.dart';

import '../../../core/telemetry/operational_status_snapshot.dart';
import '../../../core/theme/app_colors.dart';

/// Tarjeta compacta: conexión, último envío, cola, km y GPS.
class OperationalStatusCard extends StatelessWidget {
  const OperationalStatusCard({
    super.key,
    this.snapshot,
    this.isLoading = false,
  });

  final OperationalStatusSnapshot? snapshot;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading || snapshot == null) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: AppColors.secondaryBlue.withValues(alpha: 0.2),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      );
    }

    final snap = snapshot!;
    final theme = Theme.of(context);
    final enlaceColor = _colorEnlace(snap.enlace);
    final gpsColor = _colorGps(snap.gps);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: enlaceColor.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: enlaceColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StatusDot(color: enlaceColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snap.enlaceLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: enlaceColor,
                    ),
                  ),
                ),
                if (snap.sincronizando)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: enlaceColor,
                    ),
                  )
                else
                  Icon(
                    _iconoEnlace(snap.enlace),
                    size: 20,
                    color: enlaceColor,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCell(
                    icon: Icons.sync_rounded,
                    label: 'Último envío',
                    value: snap.ultimoEnvioLabel,
                    color: AppColors.secondaryBlue,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Expanded(
                  child: _MetricCell(
                    icon: Icons.cloud_upload_outlined,
                    label: 'En cola',
                    value: '${snap.pendientesTotal}',
                    color: snap.pendientesTotal > 0
                        ? AppColors.estadoPendiente
                        : AppColors.secondaryBlue,
                    destacar: snap.pendientesTotal > 0,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Expanded(
                  child: _MetricCell(
                    icon: Icons.gps_fixed_rounded,
                    label: 'GPS',
                    value: snap.gpsLabel,
                    color: gpsColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.secondaryBlue.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: 20,
                    color: AppColors.secondaryBlue.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recorrido hoy',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    snap.kmLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.secondaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            if (snap.deadLetterCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryRed.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.report_problem_outlined,
                      size: 18,
                      color: AppColors.primaryRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${snap.deadLetterCount} registro(s) no se pudieron enviar '
                        'tras varios intentos. Revisa sincronización forzada.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primaryRed,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!snap.telemetriaActiva) ...[
              const SizedBox(height: 8),
              Text(
                'Inicia la ruta para activar el seguimiento en terreno.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _colorEnlace(OperacionalEnlaceEstado e) => switch (e) {
        OperacionalEnlaceEstado.online => AppColors.secondaryBlue,
        OperacionalEnlaceEstado.offline => AppColors.primaryRed,
        OperacionalEnlaceEstado.reintentando => AppColors.estadoPendiente,
      };

  static Color _colorGps(OperacionalGpsEstado e) => switch (e) {
        OperacionalGpsEstado.activo => AppColors.secondaryBlue,
        OperacionalGpsEstado.sinSenal => AppColors.primaryRed,
        OperacionalGpsEstado.inactivo =>
          AppColors.secondaryBlue.withValues(alpha: 0.45),
      };

  static IconData _iconoEnlace(OperacionalEnlaceEstado e) => switch (e) {
        OperacionalEnlaceEstado.online => Icons.cloud_done_outlined,
        OperacionalEnlaceEstado.offline => Icons.cloud_off_outlined,
        OperacionalEnlaceEstado.reintentando => Icons.cloud_sync_outlined,
      };
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.destacar = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool destacar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.9)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: destacar ? FontWeight.w900 : FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
