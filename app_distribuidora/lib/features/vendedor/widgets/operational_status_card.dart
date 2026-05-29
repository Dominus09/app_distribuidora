import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/telemetry/operational_status_snapshot.dart';
import '../../../core/theme/app_colors.dart';

/// Estado en terreno: enlace + GPS visibles; diagnóstico técnico expandible.
class OperationalStatusCard extends StatefulWidget {
  const OperationalStatusCard({
    super.key,
    this.snapshot,
    this.isLoading = false,
    this.onOpenOutboxDebug,
  });

  final OperationalStatusSnapshot? snapshot;
  final bool isLoading;
  final VoidCallback? onOpenOutboxDebug;

  @override
  State<OperationalStatusCard> createState() => _OperationalStatusCardState();
}

class _OperationalStatusCardState extends State<OperationalStatusCard> {
  bool _diagnosticoExpandido = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading || widget.snapshot == null) {
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

    final snap = widget.snapshot!;
    final theme = Theme.of(context);
    final enlaceColor = _colorEnlace(snap.enlace);
    final gpsColor = _colorGps(snap.gps);
    final gpsLabel = _gpsLabelTerreno(snap.gps);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: enlaceColor.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: enlaceColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _EstadoPill(
                    icon: _iconoEnlace(snap.enlace),
                    label: _enlaceLabelTerreno(snap.enlace),
                    color: enlaceColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _EstadoPill(
                    icon: Icons.gps_fixed_rounded,
                    label: gpsLabel,
                    color: gpsColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(
                () => _diagnosticoExpandido = !_diagnosticoExpandido,
              ),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '⚙ Diagnóstico',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _diagnosticoExpandido
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_diagnosticoExpandido) ...[
              const Divider(height: 1),
              const SizedBox(height: 10),
              _DiagRow(label: 'Último envío (heartbeat)', value: snap.ultimoEnvioLabel),
              _DiagRow(label: 'Cola SQLite (operacional)', value: snap.colaSqliteLabel),
              if (snap.pendientesColaTotal > snap.pendientesCola)
                _DiagRow(
                  label: 'Cola total (incl. telemetría)',
                  value: '${snap.pendientesColaTotal}',
                ),
              _DiagRow(label: 'Visitas sync', value: snap.visitasSyncLabel),
              if (snap.hayTelemetriaPendiente)
                _DiagRow(
                  label: 'Telemetría pendiente',
                  value: snap.pendientesTelemetria == 1
                      ? '1 en cola'
                      : '${snap.pendientesTelemetria} en cola',
                ),
              _DiagRow(label: 'GPS detalle', value: snap.gpsLabel),
              _DiagRow(label: 'Enlace', value: snap.enlaceLabel),
              _DiagRow(label: 'Recorrido hoy', value: snap.kmLabel),
              if (snap.deadLetterCount > 0)
                _DiagRow(
                  label: 'Dead letter',
                  value: '${snap.deadLetterCount}',
                  destacar: true,
                ),
              if (snap.sincronizando)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: enlaceColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sincronizando en segundo plano…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (kDebugMode && widget.onOpenOutboxDebug != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenOutboxDebug,
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('Abrir outbox (debug)'),
                ),
              ],
            ],
            if (!snap.telemetriaActiva && !_diagnosticoExpandido) ...[
              const SizedBox(height: 6),
              Text(
                'Inicia la ruta para activar seguimiento GPS.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _enlaceLabelTerreno(OperacionalEnlaceEstado e) => switch (e) {
        OperacionalEnlaceEstado.online => '🟢 En línea',
        OperacionalEnlaceEstado.offline => '🔴 Sin conexión',
        OperacionalEnlaceEstado.reintentando => '🟡 Reenviando',
      };

  static String _gpsLabelTerreno(OperacionalGpsEstado e) => switch (e) {
        OperacionalGpsEstado.activo => '📍 GPS activo',
        OperacionalGpsEstado.buscando => '📍 Buscando GPS…',
        OperacionalGpsEstado.sinSenal => '📍 Sin señal',
        OperacionalGpsEstado.inactivo => '📍 GPS inactivo',
      };

  static Color _colorEnlace(OperacionalEnlaceEstado e) => switch (e) {
        OperacionalEnlaceEstado.online => AppColors.secondaryBlue,
        OperacionalEnlaceEstado.offline => AppColors.primaryRed,
        OperacionalEnlaceEstado.reintentando => AppColors.estadoPendiente,
      };

  static Color _colorGps(OperacionalGpsEstado e) => switch (e) {
        OperacionalGpsEstado.activo => AppColors.secondaryBlue,
        OperacionalGpsEstado.buscando => AppColors.secondaryBlue,
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

class _EstadoPill extends StatelessWidget {
  const _EstadoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    this.destacar = false,
  });

  final String label;
  final String value;
  final bool destacar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: destacar ? AppColors.primaryRed : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
