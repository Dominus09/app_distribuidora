import 'dart:async';

import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/api_service.dart';
import '../../features/vendedor/services/location_service.dart';
import '../session/operational_scope.dart';
import '../session/session_manager.dart';
import '../sync/telemetry_runtime_registry.dart';
import '../utils/field_log.dart';
import 'device_context_service.dart';
import 'gps_tracking_service.dart';
import 'operational_status_snapshot.dart';
import 'outbox_database.dart';
import 'outbox_item_type.dart';
import 'outbox_observability.dart';
import 'outbox_queue_service.dart';
import 'telemetry_config.dart';
import 'timer_registry.dart';

/// Telemetría por vendedor con **un solo timer** coordinador.
class OperationalTelemetryService {
  OperationalTelemetryService({
    required String vendedorId,
    required this.api,
    required this.locationService,
    DeviceContextService? deviceContext,
    OutboxDatabase? database,
  })  : _vendedorId = vendedorId.trim(),
        _device = deviceContext ?? DeviceContextService(),
        _db = database ?? OutboxDatabase.instance,
        _gps = GpsTrackingService(
          locationService: locationService,
          database: database,
        ),
        _queue = OutboxQueueService(
          api: api,
          vendedorId: vendedorId.trim(),
          database: database,
        );

  final String _vendedorId;
  final ApiService api;
  final LocationService locationService;
  final DeviceContextService _device;
  final OutboxDatabase _db;
  final GpsTrackingService _gps;
  final OutboxQueueService _queue;

  Timer? _coordinatorTimer;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastFlushAt;
  DateTime? _lastVisitaSyncAt;
  bool _active = false;
  bool _coordinatorBusy = false;
  OperationalScope? _scope;

  int Function()? _pendingVisitasCount;
  Future<void> Function()? _onPeriodicVisitaSync;

  bool get isActive => _active;
  bool get isQueueFlushing => _queue.isFlushing;
  OutboxQueueService get queueForRecovery => _queue;

  void bindVisitasContext({
    required int Function() pendingVisitasCount,
    required Future<void> Function() onPeriodicVisitaSync,
  }) {
    _pendingVisitasCount = pendingVisitasCount;
    _onPeriodicVisitaSync = onPeriodicVisitaSync;
  }

  void bindOperationalScope(OperationalScope? scope) {
    _scope = scope;
    _queue.bindOperationalScope(scope);
    if (_active && scope != null) {
      _gps.setFechaOperativa(scope.fechaOperativa);
    }
  }

  void startEnRuta() {
    if (_active) {
      fieldLogImportant(
        'Telemetry',
        'startEnRuta ignorado: ya activo v=$_vendedorId',
      );
      return;
    }
    if (!TelemetryRuntimeRegistry.instance.tryAcquire(_vendedorId, this)) {
      fieldLogImportant(
        'Telemetry',
        'coordinador ya activo — no se inicia duplicado v=$_vendedorId',
      );
      return;
    }
    _active = true;
    final now = DateTime.now();
    _lastHeartbeatAt = now.subtract(TelemetryConfig.heartbeatInterval);
    _lastFlushAt = now;
    _lastVisitaSyncAt = now;

    _gps.start(
      _vendedorId,
      fechaOperativa: _scope?.fechaOperativa,
    );

    _coordinatorTimer?.cancel();
    _coordinatorTimer = Timer.periodic(
      TelemetryConfig.coordinatorTickInterval,
      (_) => unawaited(_runCoordinatorTick()),
    );
    TimerRegistry.instance.register(
      name: 'telemetry_coordinator',
      owner: 'OperationalTelemetryService',
      detail: 'v=$_vendedorId',
    );
    unawaited(_runCoordinatorTick());
    fieldLog('Telemetry', 'coordinador ON v=$_vendedorId scope=$_scope', force: true);
  }

  void stop() {
    _coordinatorTimer?.cancel();
    _coordinatorTimer = null;
    TimerRegistry.instance.unregister('telemetry_coordinator');
    _gps.stop();
    _active = false;
    _coordinatorBusy = false;
    TelemetryRuntimeRegistry.instance.release(this);
    fieldLog('Telemetry', 'coordinador OFF v=$_vendedorId', force: true);
  }

  Future<void> onConnectivityRestored() async {
    await _queue.flushPending(maxItems: TelemetryConfig.maxOutboxFlushPerTick);
    await _runPeriodicVisitaSync();
  }

  /// Flush periódico aunque no esté en ruta (solo cola scoped).
  Future<int> flushOutboxBackground() async {
    return _queue.flushPending(
      onlyWhenReachable: true,
      maxItems: TelemetryConfig.maxOutboxFlushPerTick,
    );
  }

  Future<void> onAppPaused() async {
    if (_active) {
      await _sendHeartbeat(enqueueOnly: true);
    }
    await _queue.flushPending(
      onlyWhenReachable: false,
      maxItems: TelemetryConfig.maxOutboxFlushPerTick,
    );
  }

  Future<OutboxDiagnostics> loadOutboxDiagnostics() async {
    return _db.loadDiagnostics(
      vendedorId: _vendedorId,
      scope: _scope,
    );
  }

  Future<double> kmRecorridosHoy() async {
    if (!_active) return 0;
    return _db.kmRecorridosHoy(
      _vendedorId,
      fechaOperativa: _scope?.fechaOperativa,
    );
  }

  Future<OperationalStatusSnapshot> loadStatusSnapshot({
    required bool enRuta,
    required bool puedeEnviarAlServidor,
    required bool sincronizando,
    required int visitasPendientes,
  }) async {
    final diag = await loadOutboxDiagnostics();

    OutboxObservability.instance.logScopeContext(
      event: 'status_snapshot',
      scope: _scope,
      queuePending: diag.pendingCount,
      visitasSyncPending: visitasPendientes,
      byType: diag.countByItemType,
    );
    OutboxObservability.instance.logStatusBreakdown(
      outboxSqlitePending: diag.pendingCount,
      visitasSyncPendientes: visitasPendientes,
      displayedTotal: diag.pendingCount + visitasPendientes,
      outboxByType: diag.countByItemType,
    );

    final km = enRuta
        ? await _db.kmRecorridosHoy(
            _vendedorId,
            fechaOperativa: _scope?.fechaOperativa,
          )
        : 0.0;

    DateTime? ultimoHb;
    final hbRaw =
        await _db.getMeta(vendedorId: _vendedorId, key: 'last_heartbeat_at');
    if (hbRaw != null) {
      ultimoHb = DateTime.tryParse(hbRaw)?.toLocal();
    }

    DateTime? ultimoGps;
    final gpsAtRaw = await _db.getMeta(vendedorId: _vendedorId, key: 'last_gps_at');
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
    } else if (ultimoGps == null) {
      gpsEstado = OperacionalGpsEstado.buscando;
    } else {
      gpsEstado = OperacionalGpsEstado.sinSenal;
    }

    OperacionalEnlaceEstado enlace;
    if (!puedeEnviarAlServidor) {
      enlace = OperacionalEnlaceEstado.offline;
    } else if (sincronizando ||
        _queue.isFlushing ||
        (diag.pendingCount > 0 && puedeEnviarAlServidor)) {
      enlace = OperacionalEnlaceEstado.reintentando;
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

    return OperationalStatusSnapshot(
      enlace: enlace,
      gps: gpsEstado,
      pendientesCola: diag.pendingCount,
      visitasPendientes: visitasPendientes,
      visitasSyncPendientes: visitasPendientes,
      deadLetterCount: diag.deadLetterCount,
      legacyNullFechaPending: diag.legacyNullFechaPending,
      kmHoy: km,
      ultimoHeartbeat: ultimoHb,
      telemetriaActiva: enRuta && _active,
      sincronizando: sincronizando,
    );
  }

  Future<void> _runCoordinatorTick() async {
    if (!_active || _coordinatorBusy) return;
    _coordinatorBusy = true;
    try {
      final now = DateTime.now();

      if (_lastHeartbeatAt == null ||
          now.difference(_lastHeartbeatAt!) >=
              TelemetryConfig.heartbeatInterval) {
        _lastHeartbeatAt = now;
        await _sendHeartbeat();
      }

      if (_lastFlushAt == null ||
          now.difference(_lastFlushAt!) >= TelemetryConfig.outboxFlushInterval) {
        _lastFlushAt = now;
        await _queue.flushPending(
          maxItems: TelemetryConfig.maxOutboxFlushPerTick,
        );
      }

      if (_lastVisitaSyncAt == null ||
          now.difference(_lastVisitaSyncAt!) >=
              TelemetryConfig.periodicVisitaSyncInterval) {
        _lastVisitaSyncAt = now;
        await _runPeriodicVisitaSync();
      }
    } finally {
      _coordinatorBusy = false;
    }
  }

  Future<void> _sendHeartbeat({bool enqueueOnly = false}) async {
    if (!_active) return;

    try {
      final device = await _device.snapshot();
      final gps = await _gps.gpsPayloadForHeartbeat(_vendedorId);
      final pending = _pendingVisitasCount?.call() ?? 0;
      final now = DateTime.now().toUtc();
      final sessionId = SessionManager.instance.sessionId;

      final payload = <String, dynamic>{
        'vendedor_id': _vendedorId,
        'timestamp': now.toIso8601String(),
        if (sessionId != null) 'session_id': sessionId,
        if (gps != null) 'gps': gps,
        'bateria': device['bateria'],
        'conexion': device['conexion'],
        'visitas_pendientes': pending,
        'app_version': device['app_version'],
        'dispositivo': device['dispositivo'],
        'idempotency_key': _queue.heartbeatIdempotencyKeyFor(now),
      };

      if (enqueueOnly) {
        await _queue.enqueueHeartbeat(
          payload,
          source: 'OperationalTelemetry.onAppPaused',
        );
        return;
      }

      try {
        final ack = await api
            .postHeartbeat(payload)
            .timeout(TelemetryConfig.telemetryHttpTimeout);
        if (ack.confirmed) {
          await _db.setMeta(
            vendedorId: _vendedorId,
            key: 'last_heartbeat_at',
            value: now.toIso8601String(),
          );
          fieldLog('Heartbeat', 'OK v=$_vendedorId', throttle: true);
        } else {
          await _queue.enqueueHeartbeat(
            payload,
            source: 'OperationalTelemetry._sendHeartbeat!ack',
          );
        }
      } catch (e) {
        await _queue.enqueueHeartbeat(
          payload,
          source: 'OperationalTelemetry._sendHeartbeat.catch',
        );
        fieldLogImportant('Heartbeat', 'falló v=$_vendedorId: $e');
      }

      await _uploadPendingGpsPoints();
    } catch (e) {
      fieldLogImportant('Heartbeat', 'error v=$_vendedorId: $e');
    }
  }

  Future<void> _uploadPendingGpsPoints() async {
    final points =
        await _db.unuploadedGpsPoints(vendedorId: _vendedorId, limit: 40);
    if (points.isEmpty) return;

    final sessionId = SessionManager.instance.sessionId;
    final ids = points.map((p) => p.id).toList();
    final payload = {
      'vendedor_id': _vendedorId,
      if (sessionId != null) 'session_id': sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'point_ids': ids,
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
      'idempotency_key': _queue.gpsBatchIdempotencyKey(),
    };

    try {
      final ack = await api
          .postGpsTrack(payload)
          .timeout(TelemetryConfig.telemetryHttpTimeout);
      if (ack.confirmed) {
        await _db.markGpsPointsUploaded(ids, vendedorId: _vendedorId);
      } else {
        await _queue.enqueueGpsTrack(
          payload,
          source: 'OperationalTelemetry._uploadPendingGpsPoints!ack',
        );
      }
    } catch (_) {
      await _queue.enqueueGpsTrack(
        payload,
        source: 'OperationalTelemetry._uploadPendingGpsPoints.catch',
      );
    }
  }

  Future<void> _runPeriodicVisitaSync() async {
    if (!_active) return;
    final cb = _onPeriodicVisitaSync;
    if (cb == null) return;
    try {
      await cb();
    } catch (e) {
      fieldLogImportant('Telemetry', 'sync periódico: $e');
    }
  }

  Future<void> backupPendingVisita(Visita visita) async {
    if (!visita.requiereRespaldoOutbox) {
      OutboxObservability.instance.recordEnqueueSkipped(
        source: 'OperationalTelemetry.backupPendingVisita',
        reason: 'sin_cambio_local',
        tipo: OutboxItemType.visitaSync.value,
        visitaId: visita.id,
        stackSnippet: OutboxObservability.captureCallerStack(),
      );
      return;
    }
    await _queue.enqueueVisitaBackup(
      visita,
      source: 'OperationalTelemetry.backupPendingVisita',
    );
  }
}
