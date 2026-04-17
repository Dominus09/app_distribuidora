import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../utils/incidencia_photo.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/visit_action_sheets.dart';

/// Detalle de una visita; visitado/incidencia solo si sigue [VisitaEstado.pendiente].
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

  Future<void> _visitado() async {
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

  Future<void> _incidencia() async {
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
          title: const Text('Detalle de visita'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _pop,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.clienteNombre,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _lineaIcono(
                      context,
                      Icons.place_outlined,
                      v.direccion,
                    ),
                    const SizedBox(height: 16),
                    _filaEtiqueta(
                      context,
                      'Estado',
                      v.estado.label,
                      color: estadoColor,
                    ),
                    if (v.tipoIncidencia != null)
                      _filaEtiqueta(
                        context,
                        'Tipo de incidencia',
                        v.tipoIncidencia!.label,
                      ),
                    if (v.conCompra != null)
                      _filaEtiqueta(
                        context,
                        'Compra',
                        v.conCompra! ? 'Con compra' : 'Sin compra',
                      ),
                    if (v.observacion != null && v.observacion!.isNotEmpty)
                      _filaEtiqueta(context, 'Observación', v.observacion!),
                    _filaEtiqueta(
                      context,
                      'Validación georreferencia',
                      v.validacionEstado.label,
                    ),
                    const SizedBox(height: 8),
                    SyncStatusChip(visita: v),
                    if (v.localActionId != null) ...[
                      const SizedBox(height: 10),
                      _filaEtiqueta(
                        context,
                        'ID acción local',
                        v.localActionId!,
                      ),
                    ],
                    if (v.fechaHoraVisita != null)
                      _filaEtiqueta(
                        context,
                        'Fecha y hora de marcación',
                        _fmtFechaHora(v.fechaHoraVisita!),
                      ),
                    if (v.distanciaMetros != null)
                      _filaEtiqueta(
                        context,
                        'Distancia registrada',
                        '${v.distanciaMetros!.toStringAsFixed(0)} m',
                      ),
                  ],
                ),
              ),
            ),
            if (v.fotoPath != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Evidencia',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                              maxHeight: 240,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        v.fotoPath!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!puedeEditar) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ya registrado',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: puedeEditar ? _visitado : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Marcar visitado'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: puedeEditar ? _incidencia : null,
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Marcar incidencia'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                foregroundColor: theme.colorScheme.error,
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

  Widget _lineaIcono(BuildContext context, IconData icon, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    );
  }

  Widget _filaEtiqueta(
    BuildContext context,
    String etiqueta,
    String valor, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
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
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
