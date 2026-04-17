import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../utils/maps_navigation.dart';
import 'cliente_sync_dot.dart';
import 'sync_status_chip.dart';
import 'visit_action_sheets.dart';

/// Tarjeta de parada en ruta con acciones rápidas (terreno).
class VisitaCard extends StatelessWidget {
  const VisitaCard({
    super.key,
    required this.visita,
    required this.attemptRemoteSave,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
    required this.apiService,
    required this.onVisitadoPressed,
    required this.onIncidenciaPressed,
    required this.onTapDetalle,
    required this.onMapFocus,
    this.distanciaEtiqueta,
  });

  final Visita visita;
  final bool attemptRemoteSave;
  final LocationService locationService;
  final VendedorService vendedorService;
  final SyncService syncService;
  final ApiService apiService;
  final ValueChanged<Visita> onVisitadoPressed;
  final ValueChanged<Visita> onIncidenciaPressed;
  final VoidCallback onTapDetalle;
  final VoidCallback onMapFocus;

  /// Distancia al cliente (ej. `120 m`); `null` si no hay GPS o coordenadas.
  final String? distanciaEtiqueta;

  Future<void> _openDirections(BuildContext context) async {
    if (!visitaTieneCoordenadasCliente(visita.latCliente, visita.lonCliente)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este cliente no tiene coordenadas para navegar.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await launchGoogleMapsDirections(
      visita.latCliente,
      visita.lonCliente,
    );
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir Google Maps.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openVisitado(BuildContext context) async {
    final result = await showVisitadoFlowSheet(
      context: context,
      visita: visita,
      attemptRemoteSave: attemptRemoteSave,
      apiService: apiService,
      locationService: locationService,
      vendedorService: vendedorService,
      syncService: syncService,
    );
    if (result != null) onVisitadoPressed(result);
  }

  Future<void> _openIncidencia(BuildContext context) async {
    final result = await showIncidenciaFlowSheet(
      context: context,
      visita: visita,
      attemptRemoteSave: attemptRemoteSave,
      apiService: apiService,
      locationService: locationService,
      vendedorService: vendedorService,
      syncService: syncService,
    );
    if (result != null) onIncidenciaPressed(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Color(visita.estado.toneColorValue);
    final puedeEditar = visita.puedeEditarse;
    final edgeColor = c;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: edgeColor, width: 5),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondaryBlue.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTapDetalle,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${visita.orden}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          visita.clienteNombre,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          visita.estado.label,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: c,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      if (visita.estado !=
                                          VisitaEstado.pendiente) ...[
                                        const SizedBox(width: 6),
                                        ClienteSyncDot(visita: visita),
                                      ],
                                    ],
                                  ),
                                  if (distanciaEtiqueta
                                      case final String d) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.near_me_outlined,
                                          size: 18,
                                          color: theme.colorScheme.secondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          d,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    theme.colorScheme.secondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 22,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          visita.direccion,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                height: 1.25,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (visita.conCompra != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      visita.conCompra!
                                          ? 'Con compra'
                                          : 'Sin compra',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.tertiary,
                                          ),
                                    ),
                                  ],
                                  if (visita.tipoIncidencia != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Incidencia: ${visita.tipoIncidencia!.label}',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primaryRed,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  SyncStatusChip(visita: visita),
                                  if (!puedeEditar) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.lock_outline,
                                          size: 18,
                                          color: theme.colorScheme.outline,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Ya registrado · toca para ver detalle',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Toca para ver ficha del cliente',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message:
                      visitaTieneCoordenadasCliente(
                        visita.latCliente,
                        visita.lonCliente,
                      )
                      ? 'Abrir mapa de ruta'
                      : 'Sin coordenadas para el mapa',
                  child: TextButton(
                    onPressed:
                        visitaTieneCoordenadasCliente(
                          visita.latCliente,
                          visita.lonCliente,
                        )
                        ? onMapFocus
                        : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      'Ver mapa',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ver ficha',
                  iconSize: 24,
                  onPressed: onTapDetalle,
                  icon: const Icon(Icons.description_outlined),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: puedeEditar
                        ? () => _openVisitado(context)
                        : null,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Visitar'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.secondary,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: puedeEditar
                        ? () => _openIncidencia(context)
                        : null,
                    icon: const Icon(Icons.warning_amber_rounded, size: 20),
                    label: const Text('Incidencia'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: AppColors.primaryRed.withValues(alpha: 0.12),
                      foregroundColor: AppColors.primaryRed,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Ir',
                  onPressed:
                      visitaTieneCoordenadasCliente(
                        visita.latCliente,
                        visita.lonCliente,
                      )
                      ? () => _openDirections(context)
                      : null,
                  icon: const Icon(Icons.directions_outlined, size: 20),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
