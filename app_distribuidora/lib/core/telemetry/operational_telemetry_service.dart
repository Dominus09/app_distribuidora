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
import 'outbox_queue_service.dart';
import 'telemetry_config.dart';

/// Telemetría por vendedor con **un solo timer** coordinador (menos carga CPU).
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
    if (_active) return;
    if (!TelemetryRuntimeRegistry.instance.tryAcquire(_vendedorId, this)) {
      fieldLogImportant(
        'Telemetry',
        'coordinador ya activo para otro owner v=$_vendedorId',
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
    Future<void>.delayed(Duration.zero, _runCoordinatorTick);
    fieldLog('Telemetry', 'coordinador v=$_vendedorId', force: true);
  }

  void stop() {
    _coordinatorTimer?.cancel();
    _coordinatorTimer = null;
    _gps.stop();
    _active = false;
    _coordinatorBusy = false;
    TelemetryRuntimeRegistry.instance.release(this);
  }

  Future<void> onConnectivityRestored() async {
    await _queue.flushPending(maxItems: TelemetryConfig.maxOutboxFlushPerTick);
    await _runPeriodicVisitaSync();
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

  Future<double> kmRecorridosHoy() async {
    if (!_active) return 0;
    return _db.kmRecorridosHoy(_vendedorId);
  }

  Future<OperationalStatusSnapshot> loadStatusSnapshot({
    required bool enRuta,
    required bool puedeEnviarAlServidor,
    required bool sincronizando,
    required int visitasPendientes,
  }) async {
    final results = await Future.wait<Object?>([
      _db.pendingCount(vendedorId: _vendedorId, scope: _scope),
      _db.deadLetterCount(vendedorId: _vendedorId, scope: _scope),
      enRuta
          ? _db.kmRecorridosHoy(
              _vendedorId,
              fechaOperativa: _scope?.fechaOperativa,
            )
          : Future<double>.value(0),
      _db.getMeta(vendedorId: _vendedorId, key: 'last_heartbeat_at'),
      _db.getMeta(vendedorId: _vendedorId, key: 'last_gps_at'),
    ]);

    final cola = results[0]! as int;
    final deadLetters = results[1]! as int;
    final km = results[2]! as double;

    DateTime? ultimoHb;
    final hbRaw = results[3] as String?;
    if (hbRaw != null) {
      ultimoHb = DateTime.tryParse(hbRaw)?.toLocal();
    }

    DateTime? ultimoGps;
    final gpsAtRaw = results[4] as String?;
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
    if (!puedeEnviarAlServidor) {
      enlace = OperacionalEnlaceEstado.offline;
    } else if (sincronizando ||
        _queue.isFlushing ||
        (cola > 0 && puedeEnviarAlServidor)) {
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
      pendientesCola: cola,
      visitasPendientes: visitasPendientes,
      deadLetterCount: deadLetters,
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
        'idempotency_key': _queue.newHeartbeatIdempotencyKey(),
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
            vendedorId: _vendedorId,
            key: 'last_heartbeat_at',
            value: now.toIso8601String(),
          );
          fieldLog('Heartbeat', 'OK v=$_vendedorId', throttle: true);
        } else {
          await _queue.enqueueHeartbeat(payload);
        }
      } catch (e) {
        await _queue.enqueueHeartbeat(payload);
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
    final payload = {
      'vendedor_id': _vendedorId,
      if (sessionId != null) 'session_id': sessionId,
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
      'idempotency_key': _queue.newHeartbeatIdempotencyKey(),
    };

    try {
      final ack = await api
          .postGpsTrack(payload)
          .timeout(TelemetryConfig.telemetryHttpTimeout);
      if (ack.confirmed) {
        await _db.markGpsPointsUploaded(
          points.map((p) => p.id).toList(),
          vendedorId: _vendedorId,
        );
      } else {
        await _queue.enqueueGpsTrack(payload);
      }
    } catch (_) {
      await _queue.enqueueGpsTrack(payload);
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
    if (visita.syncStatus == SyncStatus.pendingSync ||
        visita.syncStatus == SyncStatus.syncError) {
      await _queue.enqueueVisitaBackup(visita);
    }
  }
}
