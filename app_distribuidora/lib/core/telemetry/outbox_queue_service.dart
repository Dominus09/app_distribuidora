import 'dart:async';

import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/api_service.dart';
import '../session/operational_scope.dart';
import '../network/api_timeouts.dart';
import '../sync/outbox_sync_state.dart';
import '../sync/processed_action_record.dart';
import '../utils/field_log.dart';
import 'outbox_database.dart';
import 'outbox_item_type.dart';
import 'outbox_observability.dart';
import 'telemetry_config.dart';

/// Procesa la cola offline del **vendedor y alcance operacional actual**.
class OutboxQueueService {
  OutboxQueueService({
    required this.api,
    required this.vendedorId,
    OutboxDatabase? database,
  }) : _db = database ?? OutboxDatabase.instance;

  final ApiService api;
  final String vendedorId;
  final OutboxDatabase _db;
  bool _flushing = false;
  OperationalScope? _scope;

  bool get isFlushing => _flushing;

  void bindOperationalScope(OperationalScope? scope) {
    _scope = scope;
  }

  Duration _backoffDelay(int retryCount) {
    final factor = 1 << retryCount.clamp(0, 6);
    final ms = TelemetryConfig.retryBaseDelay.inMilliseconds * factor;
    final capped = ms.clamp(
      TelemetryConfig.retryBaseDelay.inMilliseconds,
      TelemetryConfig.retryMaxDelay.inMilliseconds,
    );
    return Duration(milliseconds: capped);
  }

  /// Idempotencia estable por minuto (evita 1 fila nueva por cada fallo).
  String heartbeatIdempotencyKeyFor(DateTime utcNow) {
    final fecha = _scope?.fechaOperativa ??
        OperationalScope.fechaFromDateTime(utcNow.toLocal());
    final bucket = utcNow.millisecondsSinceEpoch ~/ 60000;
    return 'hb_${vendedorId}_${fecha}_$bucket';
  }

  /// Una sola fila outbox GPS por vendedor/fecha (evita +1 fila por cada punto nuevo).
  String gpsBatchIdempotencyKey() {
    final fecha = _scope?.fechaOperativa ?? 'na';
    return 'gps_batch_${vendedorId}_$fecha';
  }

  Future<int> flushPending({
    bool onlyWhenReachable = true,
    int? maxItems,
  }) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    final cap = maxItems ?? TelemetryConfig.maxOutboxFlushPerTick;
    try {
      if (onlyWhenReachable) {
        final reach = await api.checkReachability(
          timeout: ApiTimeouts.reachability,
        );
        if (!reach.ok) {
          fieldLog(
            'OutboxQueue',
            'flush omitido: sin reachability (${reach.logLine})',
            throttle: true,
          );
          return 0;
        }
      }

      final items = await _db.pendingItems(
        vendedorId: vendedorId,
        scope: _scope,
        limit: cap,
      );
      if (items.isEmpty) return 0;

      fieldLog(
        'OutboxQueue',
        'flush v=$vendedorId scope=${_scope ?? "—"} n=${items.length}',
        throttle: true,
      );

      for (final row in items) {
        if (row.vendedorId != vendedorId) continue;

        if (row.retryCount >= TelemetryConfig.maxRetryAttempts) {
          await _db.moveToDeadLetter(
            row,
            endpoint: row.endpoint ?? row.itemType.value,
            lastError: row.lastError ??
                'Máximo de reintentos (${TelemetryConfig.maxRetryAttempts})',
          );
          continue;
        }

        try {
          await _db.markSyncing(row.id, vendedorId: row.vendedorId);
          final result = await _dispatch(row);
          if (result.success) {
            await _db.markSynced(row.id, vendedorId: row.vendedorId);
            sent++;
            OutboxObservability.instance.recordFlushResult(
              type: row.itemType,
              itemId: row.id,
              success: true,
              endpoint: row.endpoint,
              retryCount: row.retryCount,
              syncState: OutboxSyncState.synced.dbValue,
            );
          } else {
            await _handleDispatchFailure(row, result.error ?? 'dispatch=false');
          }
        } catch (e) {
          await _handleDispatchFailure(row, e.toString());
        }
      }

      await _db.purgeSyncedNow(vendedorId);
      return sent;
    } finally {
      _flushing = false;
    }
  }

  Future<void> _handleDispatchFailure(OutboxRow row, String err) async {
    final next = row.retryCount + 1;
    OutboxObservability.instance.recordFlushResult(
      type: row.itemType,
      itemId: row.id,
      success: false,
      endpoint: row.endpoint,
      retryCount: next,
      syncState: row.syncState.dbValue,
      error: err,
    );
    if (next >= TelemetryConfig.maxRetryAttempts) {
      await _db.moveToDeadLetter(
        row,
        endpoint: row.endpoint ?? row.itemType.value,
        lastError: err,
      );
    } else {
      await _db.scheduleRetry(
        row.id,
        row.vendedorId,
        next,
        DateTime.now().add(_backoffDelay(next)),
        lastError: err,
      );
    }
  }

  Future<_DispatchResult> _dispatch(OutboxRow row) async {
    switch (row.itemType) {
      case OutboxItemType.heartbeat:
        try {
          final ack = await api
              .postHeartbeat(row.payload)
              .timeout(TelemetryConfig.telemetryHttpTimeout);
          return _DispatchResult(success: ack.confirmed);
        } on ApiHttpException catch (e) {
          return _DispatchResult(
            success: false,
            error: 'HTTP ${e.statusCode}: ${e.body}',
            httpStatus: e.statusCode,
          );
        }
      case OutboxItemType.gpsTrack:
        try {
          final ack = await api
              .postGpsTrack(row.payload)
              .timeout(TelemetryConfig.telemetryHttpTimeout);
          if (ack.confirmed) {
            final ids = row.payload['point_ids'];
            if (ids is List) {
              await _db.markGpsPointsUploaded(
                ids.map((e) => (e as num).toInt()).toList(),
                vendedorId: row.vendedorId,
              );
            }
          }
          return _DispatchResult(success: ack.confirmed);
        } on ApiHttpException catch (e) {
          return _DispatchResult(
            success: false,
            error: 'HTTP ${e.statusCode}: ${e.body}',
            httpStatus: e.statusCode,
          );
        }
      case OutboxItemType.visitaSync:
        final raw = row.payload['visita'];
        if (raw is! Map) {
          return const _DispatchResult(
            success: false,
            error: 'payload visita inválido',
          );
        }
        final visita = Visita.fromJson(Map<String, dynamic>.from(raw));
        if (_scope != null && !_scope!.matchesVisita(visita)) {
          return const _DispatchResult(
            success: false,
            error: 'visita fuera de scope operativo',
          );
        }
        if (!visita.requiereRespaldoOutbox) {
          await _db.markSynced(row.id, vendedorId: row.vendedorId);
          return const _DispatchResult(
            success: true,
            error: 'visita sin cambio local — descartada',
          );
        }
        if (!visita.puedeEnviarseAlBackend) {
          return const _DispatchResult(
            success: false,
            error: 'visita incompleta para POST',
          );
        }
        try {
          final saved = await api.registrarVisita(visita);
          final lid = visita.localActionId;
          if (lid != null && lid.isNotEmpty) {
            final record = _scope != null
                ? ProcessedActionRecord.fromScope(_scope!, lid)
                : ProcessedActionRecord.fromVisitaContext(
                    vendedorId: row.vendedorId,
                    fechaOperativa: row.fechaOperativa ?? '',
                    rutaId: row.rutaId,
                    actionId: lid,
                  );
            await _db.rememberProcessedAction(record);
          }
          final ok =
              saved.syncStatus == SyncStatus.synced || saved.id.isNotEmpty;
          return _DispatchResult(success: ok);
        } on ApiHttpException catch (e) {
          return _DispatchResult(
            success: false,
            error: 'HTTP ${e.statusCode}: ${e.body}',
            httpStatus: e.statusCode,
          );
        }
    }
  }

  Future<void> enqueueHeartbeat(
    Map<String, dynamic> payload, {
    required String source,
  }) async {
    final stack = OutboxObservability.captureCallerStack();
    final now = DateTime.now().toUtc();
    final key = payload['idempotency_key'] as String? ??
        heartbeatIdempotencyKeyFor(now);
    payload['idempotency_key'] = key;
    await _db.enqueue(
      vendedorId: vendedorId,
      type: OutboxItemType.heartbeat,
      payload: payload,
      idempotencyKey: key,
      fechaOperativa: _scope?.fechaOperativa,
      rutaId: _scope?.rutaId,
      endpoint: 'operaciones/heartbeat',
      source: source,
      stackSnippet: stack,
    );
  }

  Future<void> enqueueGpsTrack(
    Map<String, dynamic> payload, {
    required String source,
  }) async {
    final stack = OutboxObservability.captureCallerStack();
    final key = payload['idempotency_key'] as String? ?? gpsBatchIdempotencyKey();
    payload['idempotency_key'] = key;
    await _db.enqueue(
      vendedorId: vendedorId,
      type: OutboxItemType.gpsTrack,
      payload: payload,
      idempotencyKey: key,
      fechaOperativa: _scope?.fechaOperativa,
      rutaId: _scope?.rutaId,
      endpoint: 'operaciones/gps_track',
      source: source,
      stackSnippet: stack,
    );
  }

  Future<void> enqueueVisitaBackup(
    Visita visita, {
    required String source,
  }) async {
    final stack = OutboxObservability.captureCallerStack();
    if (!visita.requiereRespaldoOutbox) {
      OutboxObservability.instance.recordEnqueueSkipped(
        source: source,
        reason: 'sin_cambio_local',
        tipo: OutboxItemType.visitaSync.value,
        visitaId: visita.id,
        stackSnippet: stack,
      );
      return;
    }
    final lid = visita.localActionId;
    if (lid == null || lid.isEmpty) {
      OutboxObservability.instance.recordEnqueueSkipped(
        source: source,
        reason: 'sin_local_action_id',
        tipo: OutboxItemType.visitaSync.value,
        visitaId: visita.id,
        stackSnippet: stack,
      );
      return;
    }
    await _db.enqueue(
      vendedorId: vendedorId,
      type: OutboxItemType.visitaSync,
      payload: {'visita': visita.toJson()},
      idempotencyKey: 'visita_$lid',
      fechaOperativa: _scope?.fechaOperativa,
      rutaId: visita.rutaId ?? _scope?.rutaId,
      actionId: lid,
      endpoint: 'visitas',
      source: source,
      stackSnippet: stack,
    );
  }
}

class _DispatchResult {
  const _DispatchResult({
    required this.success,
    this.error,
    this.httpStatus,
  });

  final bool success;
  final String? error;
  final int? httpStatus;
}
