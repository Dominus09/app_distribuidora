import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../utils/maps_navigation.dart';
import '../utils/phone_launcher.dart';
import 'sync_status_chip.dart';
import 'terreno_badges.dart';
import 'visit_action_sheets.dart';

/// Tarjeta de parada en ruta con acciones rápidas (terreno).
class VisitaCard extends StatelessWidget {
  const VisitaCard({
    super.key,
    required this.visita,
    required this.attemptRemoteSave,
    required this.interfaceConnectivityDetected,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
    required this.apiService,
    required this.onVisitadoPressed,
    required this.onIncidenciaPressed,
    required this.onTapDetalle,
    required this.onMapFocus,
    this.distanciaEtiqueta,
    this.onGeorefDesdeIncidencia,
  });

  final Visita visita;
  final bool attemptRemoteSave;
  final bool interfaceConnectivityDetected;
  final LocationService locationService;
  final VendedorService vendedorService;
  final SyncService syncService;
  final ApiService apiService;
  final ValueChanged<Visita> onVisitadoPressed;
  final ValueChanged<Visita> onIncidenciaPressed;
  final Future<void> Function({
    required Visita visita,
    required double lat,
    required double lon,
    String? observacion,
  })? onGeorefDesdeIncidencia;
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
      interfaceConnectivityDetected: interfaceConnectivityDetected,
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
      interfaceConnectivityDetected: interfaceConnectivityDetected,
      apiService: apiService,
      locationService: locationService,
      vendedorService: vendedorService,
      syncService: syncService,
      onGeorefDesdeIncidencia: onGeorefDesdeIncidencia,
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
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTapDetalle,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  visita.clienteNombre.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 19,
                                    height: 1.12,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 22,
                                      color: theme.colorScheme.secondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        visita.direccion,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (distanciaEtiqueta case final String d) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.straighten,
                                        size: 20,
                                        color: theme.colorScheme.secondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '📏 $d',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Text(
                                  'Estado:',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TerrenoBadge(
                                  kind: badgeKindForVisitaEstado(visita.estado),
                                ),
                                if (visita.estado != VisitaEstado.pendiente) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Última gestión:',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (visita.conCompra != null)
                                    TerrenoBadge(
                                      kind: visita.conCompra!
                                          ? TerrenoBadgeKind.conCompra
                                          : TerrenoBadgeKind.sinCompra,
                                    ),
                                  if (visita.tipoIncidencia != null) ...[
                                    const SizedBox(height: 6),
                                    TerrenoBadge(
                                      kind: TerrenoBadgeKind.incidencia,
                                    ),
                                  ],
                                  if (visita.syncStatus != SyncStatus.synced) ...[
                                    const SizedBox(height: 6),
                                    SyncStatusChip(visita: visita),
                                  ] else if (visita.estado !=
                                      VisitaEstado.pendiente) ...[
                                    const SizedBox(height: 6),
                                    const TerrenoBadge(
                                      kind: TerrenoBadgeKind.sincronizado,
                                    ),
                                  ],
                                ] else if (visita.syncStatus !=
                                    SyncStatus.synced) ...[
                                  const SizedBox(height: 8),
                                  SyncStatusChip(visita: visita),
                                ],
                                if (!puedeEditar) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Toca la tarjeta para ver ficha',
                                    style: theme.textTheme.labelMedium?.copyWith(
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(
              children: [
                if (visita.tieneTelefonoLlamable ||
                    visitaTieneCoordenadasCliente(
                      visita.latCliente,
                      visita.lonCliente,
                    )) ...[
                  Row(
                    children: [
                      if (visita.tieneTelefonoLlamable)
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () =>
                                launchPhoneDialer(visita.telefono!),
                            icon: const Icon(Icons.phone_outlined, size: 22),
                            label: const Text('📞 Llamar'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 50),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      if (visita.tieneTelefonoLlamable &&
                          visitaTieneCoordenadasCliente(
                            visita.latCliente,
                            visita.lonCliente,
                          ))
                        const SizedBox(width: 8),
                      if (visitaTieneCoordenadasCliente(
                        visita.latCliente,
                        visita.lonCliente,
                      ))
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: onMapFocus,
                            icon: const Icon(Icons.map_outlined, size: 22),
                            label: const Text('🗺 Ver mapa'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 50),
                              backgroundColor: AppColors.secondaryBlue
                                  .withValues(alpha: 0.14),
                              foregroundColor: AppColors.secondaryBlue,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: puedeEditar
                            ? () => _openVisitado(context)
                            : null,
                        icon: const Icon(Icons.check_circle_outline, size: 22),
                        label: const Text('✅ Visitar'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: puedeEditar
                            ? () => _openIncidencia(context)
                            : null,
                        icon: const Icon(Icons.warning_amber_rounded, size: 22),
                        label: const Text('⚠️ Incidencia'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor:
                              AppColors.primaryRed.withValues(alpha: 0.12),
                          foregroundColor: AppColors.primaryRed,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: visitaTieneCoordenadasCliente(
                          visita.latCliente,
                          visita.lonCliente,
                        )
                            ? () => _openDirections(context)
                            : null,
                        icon: const Icon(Icons.directions_outlined),
                        label: const Text('Ir'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Ver ficha',
                      onPressed: onTapDetalle,
                      icon: const Icon(Icons.description_outlined),
                    ),
                  ],
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
