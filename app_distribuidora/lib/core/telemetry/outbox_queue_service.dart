import 'dart:async';
import 'package:uuid/uuid.dart';

import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/api_service.dart';
import '../session/operational_scope.dart';
import '../sync/operational_sync_log.dart';
import '../sync/outbox_sync_state.dart';
import '../sync/processed_action_record.dart';
import '../utils/field_log.dart';
import 'outbox_database.dart';
import 'outbox_item_type.dart';
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
  final _uuid = const Uuid();
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
          timeout: const Duration(seconds: 8),
        );
        if (!reach.ok) {
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
        'flush v=$vendedorId scope=${_scope ?? "—"} ${items.length} ítem(s)',
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
          opSyncLog(
            event: 'dead_letter',
            scope: _scope,
            actionId: row.actionId,
            syncState: OutboxSyncState.deadLetter,
          );
          continue;
        }

        try {
          await _db.markSyncing(row.id, vendedorId: row.vendedorId);
          final ack = await _dispatch(row);
          if (ack) {
            await _db.markSynced(row.id, vendedorId: row.vendedorId);
            sent++;
            opSyncLog(
              event: 'outbox_ack',
              scope: _scope,
              actionId: row.actionId,
              syncState: OutboxSyncState.synced,
            );
          }
        } catch (e) {
          final next = row.retryCount + 1;
          final err = e.toString();
          if (next >= TelemetryConfig.maxRetryAttempts) {
            await _db.moveToDeadLetter(
              row,
              endpoint: row.endpoint ?? row.itemType.value,
              lastError: err,
            );
            opSyncLog(
              event: 'dead_letter',
              scope: _scope,
              actionId: row.actionId,
              extra: err,
            );
          } else {
            await _db.scheduleRetry(
              row.id,
              row.vendedorId,
              next,
              DateTime.now().add(_backoffDelay(next)),
              lastError: err,
            );
            fieldLog('OutboxQueue', 'retry v=$vendedorId id=${row.id}: $e');
          }
        }
      }

      await _db.purgeSyncedOlderThan(vendedorId, const Duration(days: 7));
      return sent;
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _dispatch(OutboxRow row) async {
    switch (row.itemType) {
      case OutboxItemType.heartbeat:
        final ack = await api
            .postHeartbeat(row.payload)
            .timeout(TelemetryConfig.telemetryHttpTimeout);
        return ack.confirmed;
      case OutboxItemType.gpsTrack:
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
        return ack.confirmed;
      case OutboxItemType.visitaSync:
        final raw = row.payload['visita'];
        if (raw is! Map) return false;
        final visita = Visita.fromJson(Map<String, dynamic>.from(raw));
        if (_scope != null && !_scope!.matchesVisita(visita)) {
          fieldLog(
            'OutboxQueue',
            'skip visita fuera de scope id=${visita.id} scope=$_scope',
          );
          return false;
        }
        final saved = await api.registrarVisita(visita);
        final lid = visita.localActionId;
        if (lid != null && lid.isNotEmpty && _scope != null) {
          await _db.rememberProcessedAction(
            ProcessedActionRecord.fromScope(_scope!, lid),
          );
        } else if (lid != null && lid.isNotEmpty) {
          await _db.rememberProcessedAction(
            ProcessedActionRecord.fromVisitaContext(
              vendedorId: row.vendedorId,
              fechaOperativa: row.fechaOperativa ?? '',
              rutaId: row.rutaId,
              actionId: lid,
            ),
          );
        }
        return saved.syncStatus == SyncStatus.synced || saved.id.isNotEmpty;
    }
  }

  Future<void> enqueueHeartbeat(Map<String, dynamic> payload) async {
    final key = payload['idempotency_key'] as String? ??
        'hb_${vendedorId}_${payload['timestamp']}';
    await _db.enqueue(
      vendedorId: vendedorId,
      type: OutboxItemType.heartbeat,
      payload: payload,
      idempotencyKey: key,
      fechaOperativa: _scope?.fechaOperativa,
      rutaId: _scope?.rutaId,
      endpoint: 'operaciones/heartbeat',
    );
  }

  Future<void> enqueueGpsTrack(Map<String, dynamic> payload) async {
    await _db.enqueue(
      vendedorId: vendedorId,
      type: OutboxItemType.gpsTrack,
      payload: payload,
      idempotencyKey: payload['idempotency_key'] as String?,
      fechaOperativa: _scope?.fechaOperativa,
      rutaId: _scope?.rutaId,
      endpoint: 'operaciones/gps_track',
    );
  }

  Future<void> enqueueVisitaBackup(Visita visita) async {
    final lid = visita.localActionId;
    if (lid == null || lid.isEmpty) return;
    await _db.enqueue(
      vendedorId: vendedorId,
      type: OutboxItemType.visitaSync,
      payload: {'visita': visita.toJson()},
      idempotencyKey: 'visita_$lid',
      fechaOperativa: _scope?.fechaOperativa,
      rutaId: visita.rutaId ?? _scope?.rutaId,
      actionId: lid,
      endpoint: 'visitas',
    );
  }

  String newHeartbeatIdempotencyKey() {
    return 'hb_${vendedorId}_${_uuid.v4()}';
  }
}
