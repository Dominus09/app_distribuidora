import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import 'sync_status_chip.dart';
import 'visit_action_sheets.dart';

/// Tarjeta de parada en ruta con acciones rápidas.
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

  void _navigate() {
    // ignore: avoid_print
    print('Abrir mapa para ${visita.clienteNombre}');
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

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTapDetalle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
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
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            visita.clienteNombre,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            visita.estado.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: c,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            visita.direccion,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (visita.conCompra != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        visita.conCompra! ? 'Con compra' : 'Sin compra',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ],
                    if (visita.tipoIncidencia != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Incidencia: ${visita.tipoIncidencia!.label}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SyncStatusChip(visita: visita),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _openVisitado(context),
                          icon: const Icon(Icons.check_circle_outline, size: 20),
                          label: const Text('Visitado'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _openIncidencia(context),
                          icon: const Icon(Icons.warning_amber_rounded, size: 20),
                          label: const Text('Incidencia'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            foregroundColor: theme.colorScheme.error,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _navigate,
                          icon: const Icon(Icons.navigation_outlined, size: 20),
                          label: const Text('Navegar'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
