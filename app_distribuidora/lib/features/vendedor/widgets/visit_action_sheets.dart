import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';

/// Distancia máxima permitida para marcar visitado con GPS en línea (metros).
const double kMaxDistanceVisitadoMetros = 300;

/// Bottom sheet: flujo "visitado" con compra / sin compra y validación mock GPS.
Future<Visita?> showVisitadoFlowSheet({
  required BuildContext context,
  required Visita visita,
  required bool isOnline,
  required LocationService locationService,
  required VendedorService vendedorService,
  required SyncService syncService,
}) {
  return showModalBottomSheet<Visita>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _VisitadoSheetBody(
          visita: visita,
          isOnline: isOnline,
          locationService: locationService,
          vendedorService: vendedorService,
          syncService: syncService,
        ),
      );
    },
  );
}

class _VisitadoSheetBody extends StatefulWidget {
  const _VisitadoSheetBody({
    required this.visita,
    required this.isOnline,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
  });

  final Visita visita;
  final bool isOnline;
  final LocationService locationService;
  final VendedorService vendedorService;
  final SyncService syncService;

  @override
  State<_VisitadoSheetBody> createState() => _VisitadoSheetBodyState();
}

class _VisitadoSheetBodyState extends State<_VisitadoSheetBody> {
  bool? _conCompra;
  final _obsCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_conCompra == null) {
      _toast('Indica si la visita fue con compra o sin compra.');
      return;
    }

    setState(() => _busy = true);
    try {
      final actionId = widget.vendedorService.generateLocalActionId();
      final gpsOk = await widget.locationService.isGpsAvailable();
      LocationSnapshot? snap;
      if (gpsOk) {
        snap = await widget.locationService.getCurrentPosition();
      }

      final obs =
          _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim();
      final ahora = DateTime.now();

      // --- Sin conexión: siempre se permite guardar; queda pendiente de sync.
      if (!widget.isOnline) {
        if (!gpsOk) {
          _popResult(
            actionId,
            estado: VisitaEstado.visitado,
            conCompra: _conCompra,
            observacion: obs,
            lat: null,
            lon: null,
            fecha: ahora,
            dist: null,
            validacion: ValidacionEstado.sinGps,
            sync: SyncStatus.pendingSync,
          );
          return;
        }

        final d = widget.locationService.distanceToCliente(snap!, widget.visita);
        // Sin red: la distancia queda referencial; >300 m se deja para validar al sincronizar.
        final validacion = d > kMaxDistanceVisitadoMetros
            ? ValidacionEstado.pendienteValidacion
            : ValidacionEstado.offline;

        _popResult(
          actionId,
          estado: VisitaEstado.visitado,
          conCompra: _conCompra,
          observacion: obs,
          lat: snap.latitude,
          lon: snap.longitude,
          fecha: ahora,
          dist: d,
          validacion: validacion,
          sync: SyncStatus.pendingSync,
        );
        return;
      }

      // --- En línea: sin GPS → guardar con validación diferida (pendiente sync).
      if (!gpsOk) {
        _popResult(
          actionId,
          estado: VisitaEstado.visitado,
          conCompra: _conCompra,
          observacion: obs,
          lat: null,
          lon: null,
          fecha: ahora,
          dist: null,
          validacion: ValidacionEstado.sinGps,
          sync: SyncStatus.pendingSync,
        );
        return;
      }

      final d = widget.locationService.distanceToCliente(snap!, widget.visita);
      if (d > kMaxDistanceVisitadoMetros) {
        _toast(
          'Debes estar a máximo 300 metros del cliente para marcar como visitado.',
        );
        return;
      }

      final actualizada = widget.visita.copyWith(
        estado: VisitaEstado.visitado,
        conCompra: _conCompra,
        observacion: obs,
        latVisita: snap.latitude,
        lonVisita: snap.longitude,
        fechaHoraVisita: ahora,
        distanciaMetros: d,
        validacionEstado: ValidacionEstado.validado,
        syncStatus: SyncStatus.synced,
        tipoIncidencia: null,
        fotoPath: null,
        localActionId: actionId,
      );
      widget.syncService.acknowledgeActionProcessed(actionId);
      if (mounted) Navigator.of(context).pop(actualizada);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _popResult(
    String actionId, {
    required VisitaEstado estado,
    required bool? conCompra,
    required String? observacion,
    required double? lat,
    required double? lon,
    required DateTime fecha,
    required double? dist,
    required ValidacionEstado validacion,
    required SyncStatus sync,
  }) {
    final actualizada = widget.visita.copyWith(
      estado: estado,
      conCompra: conCompra,
      observacion: observacion,
      latVisita: lat,
      lonVisita: lon,
      fechaHoraVisita: fecha,
      distanciaMetros: dist,
      validacionEstado: validacion,
      syncStatus: sync,
      tipoIncidencia: null,
      fotoPath: null,
      localActionId: actionId,
    );
    if (sync == SyncStatus.synced) {
      widget.syncService.acknowledgeActionProcessed(actionId);
    }
    if (mounted) Navigator.of(context).pop(actualizada);
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = !widget.isOnline;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Marcar visitado',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.visita.clienteNombre,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '¿La visita fue con compra?',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Con compra')),
              ButtonSegment(value: false, label: Text('Sin compra')),
            ],
            selected: _conCompra != null ? {_conCompra!} : {},
            onSelectionChanged: (s) => setState(() => _conCompra = s.first),
            emptySelectionAllowed: true,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _obsCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              hintText: 'Ej. pedido para la próxima semana',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            offline
                ? 'Sin conexión: se guardará localmente y se sincronizará después.'
                : 'En línea con GPS: se valida distancia máxima 300 m. Sin GPS: la validación queda pendiente hasta sincronizar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _guardar,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar visita'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: registro de incidencia con tipo, observación y foto mock.
Future<Visita?> showIncidenciaFlowSheet({
  required BuildContext context,
  required Visita visita,
  required bool isOnline,
  required LocationService locationService,
  required VendedorService vendedorService,
  required SyncService syncService,
}) {
  return showModalBottomSheet<Visita>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _IncidenciaSheetBody(
          visita: visita,
          isOnline: isOnline,
          locationService: locationService,
          vendedorService: vendedorService,
          syncService: syncService,
        ),
      );
    },
  );
}

class _IncidenciaSheetBody extends StatefulWidget {
  const _IncidenciaSheetBody({
    required this.visita,
    required this.isOnline,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
  });

  final Visita visita;
  final bool isOnline;
  final LocationService locationService;
  final VendedorService vendedorService;
  final SyncService syncService;

  @override
  State<_IncidenciaSheetBody> createState() => _IncidenciaSheetBodyState();
}

class _IncidenciaSheetBodyState extends State<_IncidenciaSheetBody> {
  TipoIncidencia _tipo = TipoIncidencia.localCerrado;
  final _obsCtrl = TextEditingController();
  String? _fotoPath;
  bool _busy = false;

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  void _adjuntarFotoDemo() {
    setState(() {
      _fotoPath =
          'mock://incidencia_${widget.visita.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    });
  }

  Future<void> _guardar() async {
    final obs = _obsCtrl.text.trim();
    if (obs.isEmpty) {
      _toast('La observación es obligatoria.');
      return;
    }
    if (_fotoPath == null) {
      _toast('Debes adjuntar la evidencia (usa el botón de foto demo).');
      return;
    }

    setState(() => _busy = true);
    try {
      final actionId = widget.vendedorService.generateLocalActionId();
      final gpsOk = await widget.locationService.isGpsAvailable();
      LocationSnapshot? snap;
      if (gpsOk) {
        snap = await widget.locationService.getCurrentPosition();
      }

      final ahora = DateTime.now();
      final metros = snap != null
          ? widget.locationService.distanceToCliente(snap, widget.visita)
          : null;

      final validacion = !widget.isOnline
          ? ValidacionEstado.offline
          : (gpsOk && snap != null
              ? ValidacionEstado.validado
              : ValidacionEstado.sinGps);

      final sync =
          widget.isOnline ? SyncStatus.synced : SyncStatus.pendingSync;

      final actualizada = widget.visita.copyWith(
        estado: VisitaEstado.incidencia,
        tipoIncidencia: _tipo,
        observacion: obs,
        conCompra: null,
        latVisita: snap?.latitude,
        lonVisita: snap?.longitude,
        fechaHoraVisita: ahora,
        distanciaMetros: metros,
        validacionEstado: validacion,
        fotoPath: _fotoPath,
        syncStatus: sync,
        localActionId: actionId,
      );

      if (sync == SyncStatus.synced) {
        widget.syncService.acknowledgeActionProcessed(actionId);
      }
      if (mounted) Navigator.of(context).pop(actualizada);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Registrar incidencia',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.visita.clienteNombre,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<TipoIncidencia>(
            key: ValueKey(_tipo),
            initialValue: _tipo,
            decoration: const InputDecoration(
              labelText: 'Tipo de incidencia',
            ),
            items: TipoIncidencia.values
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.label),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _tipo = v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _obsCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Observación',
              hintText: 'Describe qué ocurrió en el punto de venta',
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _adjuntarFotoDemo,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(
              _fotoPath == null
                  ? 'Adjuntar foto (demo obligatoria)'
                  : 'Foto lista (volver a generar)',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isOnline
                ? 'En línea: la incidencia se marca como sincronizada (mock).'
                : 'Sin conexión: quedará pendiente de envío hasta la sincronización forzada.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _guardar,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: _busy
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onError,
                    ),
                  )
                : const Text('Guardar incidencia'),
          ),
        ],
      ),
    );
  }
}
