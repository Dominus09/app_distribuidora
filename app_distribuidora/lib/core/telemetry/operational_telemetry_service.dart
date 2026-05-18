import 'dart:async';

import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/api_service.dart';
import '../../features/vendedor/services/location_service.dart';
import '../utils/field_log.dart';
import 'device_context_service.dart';
import 'gps_tracking_service.dart';
import 'operational_status_snapshot.dart';
import 'outbox_database.dart';
import 'outbox_queue_service.dart';
import 'telemetry_config.dart';

/// Coordinador de telemetría: heartbeat 60s, GPS continuo, cola offline, sync periódico.
class OperationalTelemetryService {
  OperationalTelemetryService({
    required this.api,
    required this.locationService,
    DeviceContextService? deviceContext,
    OutboxDatabase? database,
  })  : _device = deviceContext ?? DeviceContextService(),
        _db = database ?? OutboxDatabase.instance,
        _gps = GpsTrackingService(
          locationService: locationService,
          database: database,
        ),
        _queue = OutboxQueueService(api: api, database: database);

  final ApiService api;
  final LocationService locationService;
  final DeviceContextService _device;
  final OutboxDatabase _db;
  final GpsTrackingService _gps;
  final OutboxQueueService _queue;

  Timer? _heartbeatTimer;
  Timer? _periodicSyncTimer;
  Timer? _flushTimer;
  String? _vendedorId;
  bool _active = false;

  int Function()? _pendingVisitasCount;
  Future<void> Function()? _onPeriodicVisitaSync;

  bool get isActive => _active;
  bool get isQueueFlushing => _queue.isFlushing;
  GpsTrackingService get gpsTracker => _gps;

  /// Registra callback para contar visitas pendientes en heartbeat.
  void bindVisitasContext({
    required int Function() pendingVisitasCount,
    required Future<void> Function() onPeriodicVisitaSync,
  }) {
    _pendingVisitasCount = pendingVisitasCount;
    _onPeriodicVisitaSync = onPeriodicVisitaSync;
  }

  /// Inicia telemetría mientras el vendedor está en ruta.
  void startEnRuta(String vendedorId) {
    if (_active && _vendedorId == vendedorId) return;
    stop();
    _vendedorId = vendedorId;
    _active = true;
    fieldLog('Telemetry', 'inicio en ruta vendedor=$vendedorId');

    _gps.start(vendedorId);

    _heartbeatTimer = Timer.periodic(
      TelemetryConfig.heartbeatInterval,
      (_) => unawaited(_sendHeartbeat()),
    );
    unawaited(_sendHeartbeat());

    _periodicSyncTimer = Timer.periodic(
      TelemetryConfig.periodicVisitaSyncInterval,
      (_) => unawaited(_runPeriodicVisitaSync()),
    );

    _flushTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_queue.flushPending()),
    );

    unawaited(_queue.flushPending());
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _gps.stop();
    _active = false;
    _vendedorId = null;
    fieldLog('Telemetry', 'detenido');
  }

  Future<void> onConnectivityRestored() async {
    fieldLog('Telemetry', 'conectividad restaurada → flush + sync');
    await _queue.flushPending();
    await _runPeriodicVisitaSync();
  }

  Future<void> onAppPaused() async {
    fieldLog('Telemetry', 'app pausada → heartbeat de respaldo');
    if (_active) {
      await _sendHeartbeat(enqueueOnly: true);
    }
    await _queue.flushPending(onlyWhenReachable: false);
  }

  Future<double> kmRecorridosHoy() async {
    final vid = _vendedorId;
    if (vid == null) return 0;
    return _db.kmRecorridosHoy(vid);
  }

  /// Estado operacional para la tarjeta del Home (textos no técnicos).
  Future<OperationalStatusSnapshot> loadStatusSnapshot({
    required bool enRuta,
    required bool puedeEnviarAlServidor,
    required bool sincronizando,
    required int visitasPendientes,
  }) async {
    final cola = await _db.pendingCount();
    final km = enRuta ? await kmRecorridosHoy() : 0.0;

    DateTime? ultimoHb;
    final hbRaw = await _db.getMeta('last_heartbeat_at');
    if (hbRaw != null) {
      ultimoHb = DateTime.tryParse(hbRaw)?.toLocal();
    }

    final gpsAtRaw = await _db.getMeta('last_gps_at');
    DateTime? ultimoGps;
    if (gpsAtRaw != null) {
      ultimoGps = DateTime.tryParse(gpsAtRaw)?.toLocal();
    }
    final snap = _gps.lastKnown;
    if (snap != null) {
      ultimoGps = snap.capturedAt;
    }

    OperacionalGpsEstado gpsEstado;
    if (!enRuta) {
      gpsEstado = OperacionalGpsEstado.inactivo;
    } else if (ultimoGps != null &&
        DateTime.now().difference(ultimoGps) <
            TelemetryConfig.gpsPollMaxInterval * 2) {
      gpsEstado = OperacionalGpsEstado.activo;
    } else {
      gpsEstado = OperacionalGpsEstado.sinSenal;
    }

    OperacionalEnlaceEstado enlace;
    if (sincronizando || _queue.isFlushing || (cola > 0 && puedeEnviarAlServidor)) {
      enlace = OperacionalEnlaceEstado.reintentando;
    } else if (!puedeEnviarAlServidor) {
      enlace = OperacionalEnlaceEstado.offline;
    } else if (enRuta && ultimoHb != null) {
      final age = DateTime.now().difference(ultimoHb);
      enlace = age <= TelemetryConfig.heartbeatInterval * 2
          ? OperacionalEnlaceEstado.online
          : OperacionalEnlaceEstado.reintentando;
    } else if (enRuta) {
      enlace = OperacionalEnlaceEstado.reintentando;
    } else {
      enlace = OperacionalEnlaceEstado.online;
    }

    if (!puedeEnviarAlServidor) {
      enlace = OperacionalEnlaceEstado.offline;
    }

    return OperationalStatusSnapshot(
      enlace: enlace,
      gps: gpsEstado,
      pendientesCola: cola,
      visitasPendientes: visitasPendientes,
      kmHoy: km,
      ultimoHeartbeat: ultimoHb,
      telemetriaActiva: enRuta && _active,
      sincronizando: sincronizando,
    );
  }

  Future<void> _sendHeartbeat({bool enqueueOnly = false}) async {
    final vid = _vendedorId;
    if (vid == null || !_active) return;

    try {
      final device = await _device.snapshot();
      final gps = await _gps.gpsPayloadForHeartbeat();
      final pending = _pendingVisitasCount?.call() ?? 0;
      final now = DateTime.now().toUtc();

      final payload = <String, dynamic>{
        'vendedor_id': vid,
        'timestamp': now.toIso8601String(),
        if (gps != null) 'gps': gps,
        'bateria': device['bateria'],
        'conexion': device['conexion'],
        'visitas_pendientes': pending,
        'app_version': device['app_version'],
        'dispositivo': device['dispositivo'],
        'idempotency_key': _queue.newHeartbeatIdempotencyKey(vid),
      };

      if (enqueueOnly) {
        await _queue.enqueueHeartbeat(payload);
        return;
      }

      try {
        final ack = await api
            .postHeartbeat(payload)
            .timeout(TelemetryConfig.telemetryHttpTimeout);
        if (ack.confirmed) {
          await _db.setMeta(
            'last_heartbeat_at',
            now.toIso8601String(),
          );
          fieldLog('Heartbeat', 'enviado OK vendedor=$vid pending=$pending');
        } else {
          await _queue.enqueueHeartbeat(payload);
          fieldLog('Heartbeat', 'sin ACK → cola offline');
        }
      } catch (e) {
        await _queue.enqueueHeartbeat(payload);
        fieldLog('Heartbeat', 'falló → cola: $e');
      }

      await _uploadPendingGpsPoints(vid);
    } catch (e) {
      fieldLog('Heartbeat', 'error construyendo payload: $e');
    }
  }

  Future<void> _uploadPendingGpsPoints(String vendedorId) async {
    final points = await _db.unuploadedGpsPoints(vendedorId: vendedorId);
    if (points.isEmpty) return;

    final payload = {
      'vendedor_id': vendedorId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'point_ids': points.map((p) => p.id).toList(),
      'puntos': points
          .map(
            (p) => {
              'lat': p.latitude,
              'lon': p.longitude,
              'accuracy_m': p.accuracyMeters,
              'captured_at': p.capturedAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
      'idempotency_key': _queue.newHeartbeatIdempotencyKey(
        '${vendedorId}_gps',
      ),
    };

    try {
      final ack = await api
          .postGpsTrack(payload)
          .timeout(TelemetryConfig.telemetryHttpTimeout);
      if (ack.confirmed) {
        await _db.markGpsPointsUploaded(points.map((p) => p.id).toList());
        fieldLog('GPS-Track', '${points.length} punto(s) subidos');
      } else {
        await _queue.enqueueGpsTrack(payload);
      }
    } catch (e) {
      await _queue.enqueueGpsTrack(payload);
      fieldLog('GPS-Track', 'upload falló → cola: $e');
    }
  }

  Future<void> _runPeriodicVisitaSync() async {
    if (!_active) return;
    final cb = _onPeriodicVisitaSync;
    if (cb == null) return;
    try {
      fieldLog('Telemetry', 'sync periódico visitas');
      await cb();
    } catch (e) {
      fieldLog('Telemetry', 'sync periódico error: $e');
    }
  }

  /// Persiste visita en cola de respaldo si queda pendiente de sync.
  Future<void> backupPendingVisita(Visita visita) async {
    if (visita.syncStatus == SyncStatus.pendingSync ||
        visita.syncStatus == SyncStatus.syncError) {
      await _queue.enqueueVisitaBackup(visita);
    }
  }
}
