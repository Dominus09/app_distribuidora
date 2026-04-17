import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../utils/incidencia_photo.dart';

/// Distancia máxima permitida para marcar visitado con GPS en línea (metros).
const double kMaxDistanceVisitadoMetros = 300;

/// Bottom sheet: flujo "visitado" con compra / sin compra y validación mock GPS.
Future<Visita?> showVisitadoFlowSheet({
  required BuildContext context,
  required Visita visita,
  required bool attemptRemoteSave,
  required ApiService apiService,
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
          attemptRemoteSave: attemptRemoteSave,
          apiService: apiService,
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
    required this.attemptRemoteSave,
    required this.apiService,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
  });

  final Visita visita;
  final bool attemptRemoteSave;
  final ApiService apiService;
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

      // --- Sin intento remoto: siempre se permite guardar; queda pendiente de sync.
      if (!widget.attemptRemoteSave) {
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

      final paraEnviar = widget.visita.copyWith(
        estado: VisitaEstado.visitado,
        conCompra: _conCompra,
        observacion: obs,
        latVisita: snap.latitude,
        lonVisita: snap.longitude,
        fechaHoraVisita: ahora,
        distanciaMetros: d,
        validacionEstado: ValidacionEstado.validado,
        syncStatus: SyncStatus.pendingSync,
        tipoIncidencia: null,
        fotoPath: null,
        localActionId: actionId,
      );

      try {
        final guardada = await widget.apiService.registrarVisita(paraEnviar);
        if (!mounted) return;
        widget.syncService.acknowledgeActionProcessed(actionId);
        Navigator.of(context).pop(
          guardada.copyWith(
            syncStatus: SyncStatus.synced,
            localActionId: actionId,
          ),
        );
      } catch (_) {
        if (!mounted) return;
        _toast('Sin conexión, se guardará para sincronizar');
        Navigator.of(context).pop(paraEnviar);
      }
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
    final offline = !widget.attemptRemoteSave;

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

/// Bottom sheet: registro de incidencia con tipo, observación y evidencia (cámara / galería).
Future<Visita?> showIncidenciaFlowSheet({
  required BuildContext context,
  required Visita visita,
  required bool attemptRemoteSave,
  required ApiService apiService,
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
          attemptRemoteSave: attemptRemoteSave,
          apiService: apiService,
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
    required this.attemptRemoteSave,
    required this.apiService,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
  });

  final Visita visita;
  final bool attemptRemoteSave;
  final ApiService apiService;
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
  bool _pickingPhoto = false;
  /// Error de validación al pulsar Guardar; se muestra en el propio sheet.
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _obsCtrl.addListener(_onObservacionChanged);
  }

  static const _msgObsRequerida = 'La observación es obligatoria.';

  void _onObservacionChanged() {
    if (!mounted || _validationError == null) return;
    if (_validationError == _msgObsRequerida &&
        _obsCtrl.text.trim().isNotEmpty) {
      setState(() => _validationError = null);
    }
  }

  @override
  void dispose() {
    _obsCtrl.removeListener(_onObservacionChanged);
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFrom(ImageSource source) async {
    setState(() => _pickingPhoto = true);
    try {
      final path = await pickAndPersistIncidenciaPhoto(
        source: source,
        visitaId: widget.visita.id,
      );
      if (!mounted) return;
      if (path == null) return;
      setState(() {
        _fotoPath = path;
        _validationError = null;
      });
    } catch (_) {
      if (!mounted) return;
      _toast(
        'No se pudo obtener la foto. Comprueba permisos de cámara o galería e inténtalo de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _guardar() async {
    if (!mounted) return;
    setState(() => _validationError = null);

    final obs = _obsCtrl.text.trim();
    if (obs.isEmpty) {
      setState(() {
        _validationError = _msgObsRequerida;
      });
      return;
    }
    final foto = _fotoPath?.trim();
    if (foto == null || foto.isEmpty) {
      setState(() {
        _validationError = 'Debe subir evidencia antes de guardar';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      final actionId = widget.vendedorService.generateLocalActionId();
      final telefonica = _tipo == TipoIncidencia.atencionTelefonica;

      var gpsOk = false;
      LocationSnapshot? snap;
      if (!telefonica) {
        gpsOk = await widget.locationService.isGpsAvailable();
        if (gpsOk) {
          snap = await widget.locationService.getCurrentPosition();
        }
      }

      final ahora = DateTime.now();
      final metros = telefonica
          ? null
          : (snap != null
              ? widget.locationService.distanceToCliente(snap, widget.visita)
              : null);

      final ValidacionEstado validacion = telefonica
          ? (!widget.attemptRemoteSave
              ? ValidacionEstado.offline
              : ValidacionEstado.sinGps)
          : (!widget.attemptRemoteSave
              ? ValidacionEstado.offline
              : (gpsOk && snap != null
                  ? ValidacionEstado.validado
                  : ValidacionEstado.sinGps));

      final paraEnviar = widget.visita.copyWith(
        estado: VisitaEstado.incidencia,
        tipoIncidencia: _tipo,
        observacion: obs,
        conCompra: null,
        latVisita: telefonica ? null : snap?.latitude,
        lonVisita: telefonica ? null : snap?.longitude,
        fechaHoraVisita: ahora,
        distanciaMetros: metros,
        validacionEstado: validacion,
        fotoPath: _fotoPath,
        syncStatus: SyncStatus.pendingSync,
        localActionId: actionId,
      );

      if (!widget.attemptRemoteSave) {
        if (mounted) Navigator.of(context).pop(paraEnviar);
        return;
      }

      try {
        final guardada = await widget.apiService.registrarVisita(paraEnviar);
        if (!mounted) return;
        widget.syncService.acknowledgeActionProcessed(actionId);
        Navigator.of(context).pop(
          guardada.copyWith(
            syncStatus: SyncStatus.synced,
            localActionId: actionId,
          ),
        );
      } catch (_) {
        if (!mounted) return;
        _toast('Sin conexión, se guardará para sincronizar');
        Navigator.of(context).pop(paraEnviar);
      }
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
              if (v != null) {
                setState(() {
                  _tipo = v;
                  _validationError = null;
                });
              }
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
          Text(
            'Evidencia (obligatoria)',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _pickingPhoto
                      ? null
                      : () => _pickFrom(ImageSource.camera),
                  icon: _pickingPhoto
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cámara'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _pickingPhoto
                      ? null
                      : () => _pickFrom(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ),
          if (_fotoPath != null) ...[
            const SizedBox(height: 12),
            Text(
              'Vista previa',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Center(
                  child: buildEvidenciaFotoPreview(
                    _fotoPath!,
                    maxHeight: 220,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy || _pickingPhoto
                    ? null
                    : () => setState(() {
                          _fotoPath = null;
                          _validationError = null;
                        }),
                child: const Text('Quitar foto'),
              ),
            ),
          ],
          if (_tipo == TipoIncidencia.atencionTelefonica) ...[
            const SizedBox(height: 8),
            Text(
              'Debe subir evidencia del contacto (llamada o WhatsApp)',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            widget.attemptRemoteSave
                ? 'En línea: se enviará al servidor al guardar.'
                : 'Sin conexión: quedará pendiente de envío hasta la sincronización forzada.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 16),
            Material(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _validationError!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
