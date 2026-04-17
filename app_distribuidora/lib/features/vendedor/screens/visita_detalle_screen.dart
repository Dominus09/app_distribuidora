import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../utils/incidencia_photo.dart';
import '../utils/maps_navigation.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/visit_action_sheets.dart';

/// Detalle del cliente antes de marcar visita o incidencia (vista principal en terreno).
class VisitaDetalleScreen extends StatefulWidget {
  const VisitaDetalleScreen({
    super.key,
    required this.visita,
    required this.attemptRemoteSave,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
    required this.apiService,
  });

  final Visita visita;
  final bool attemptRemoteSave;
  final LocationService locationService;
  final VendedorService vendedorService;
  final SyncService syncService;
  final ApiService apiService;

  @override
  State<VisitaDetalleScreen> createState() => _VisitaDetalleScreenState();
}

class _VisitaDetalleScreenState extends State<VisitaDetalleScreen> {
  late Visita _visita;

  @override
  void initState() {
    super.initState();
    _visita = widget.visita;
  }

  void _pop() {
    Navigator.of(context).pop(_visita);
  }

  Future<void> _ir() async {
    final v = _visita;
    if (!visitaTieneCoordenadasCliente(v.latCliente, v.lonCliente)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este cliente no tiene coordenadas para navegar.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await launchGoogleMapsDirections(v.latCliente, v.lonCliente);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir Google Maps.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _marcarVisita() async {
    final r = await showVisitadoFlowSheet(
      context: context,
      visita: _visita,
      attemptRemoteSave: widget.attemptRemoteSave,
      apiService: widget.apiService,
      locationService: widget.locationService,
      vendedorService: widget.vendedorService,
      syncService: widget.syncService,
    );
    if (r != null) setState(() => _visita = r);
  }

  Future<void> _registrarIncidencia() async {
    final r = await showIncidenciaFlowSheet(
      context: context,
      visita: _visita,
      attemptRemoteSave: widget.attemptRemoteSave,
      apiService: widget.apiService,
      locationService: widget.locationService,
      vendedorService: widget.vendedorService,
      syncService: widget.syncService,
    );
    if (r != null) setState(() => _visita = r);
  }

  static String _mostrar(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return '—';
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = _visita;
    final estadoColor = Color(v.estado.toneColorValue);
    final puedeEditar = v.puedeEditarse;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_visita);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(v.orden > 0 ? 'Cliente · Parada ${v.orden}' : 'Cliente'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _pop,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Datos del cliente',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CampoTerreno(
                      etiqueta: 'Nombre fantasía',
                      valor: _mostrar(v.nombreFantasia),
                    ),
                    _CampoTerreno(
                      etiqueta: 'Dirección',
                      valor: _mostrar(v.direccion.isEmpty ? null : v.direccion),
                    ),
                    _CampoTerreno(
                      etiqueta: 'Comuna',
                      valor: _mostrar(v.comuna),
                    ),
                    _CampoTerreno(etiqueta: 'RUT', valor: _mostrar(v.rutClean)),
                    const SizedBox(height: 6),
                    Text(
                      'Estado actual',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: estadoColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: estadoColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          v.estado.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: estadoColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!puedeEditar) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.75,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Visita ya registrada. Puedes revisar o ir al local.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: _ir,
              icon: const Icon(Icons.directions_outlined, size: 24),
              label: const Text('Ir'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: puedeEditar ? _marcarVisita : null,
              icon: const Icon(Icons.check_circle_outline, size: 24),
              label: const Text('Marcar visita'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: puedeEditar ? _registrarIncidencia : null,
              icon: const Icon(Icons.warning_amber_rounded, size: 24),
              label: const Text('Registrar incidencia'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                foregroundColor: theme.colorScheme.error,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Más información',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  _filaCompacta(
                    context,
                    'Razón social / nombre',
                    v.clienteNombre,
                  ),
                  if (v.tipoIncidencia != null)
                    _filaCompacta(
                      context,
                      'Tipo de incidencia',
                      v.tipoIncidencia!.label,
                    ),
                  if (v.conCompra != null)
                    _filaCompacta(
                      context,
                      'Compra',
                      v.conCompra! ? 'Con compra' : 'Sin compra',
                    ),
                  if (v.observacion != null && v.observacion!.trim().isNotEmpty)
                    _filaCompacta(
                      context,
                      'Observación',
                      v.observacion!.trim(),
                    ),
                  _filaCompacta(
                    context,
                    'Validación GPS',
                    v.validacionEstado.label,
                  ),
                  const SizedBox(height: 8),
                  SyncStatusChip(visita: v),
                  if (v.fechaHoraVisita != null)
                    _filaCompacta(
                      context,
                      'Marcación',
                      _fmtFechaHora(v.fechaHoraVisita!),
                    ),
                  if (v.distanciaMetros != null)
                    _filaCompacta(
                      context,
                      'Distancia',
                      '${v.distanciaMetros!.toStringAsFixed(0)} m',
                    ),
                  if (v.fotoPath != null && v.fotoPath!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Evidencia',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Center(
                          child: buildEvidenciaFotoPreview(
                            v.fotoPath!,
                            maxHeight: 220,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtFechaHora(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$dd-$mm-$yy $h:$m';
  }

  Widget _filaCompacta(BuildContext context, String etiqueta, String valor) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              etiqueta,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoTerreno extends StatelessWidget {
  const _CampoTerreno({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
