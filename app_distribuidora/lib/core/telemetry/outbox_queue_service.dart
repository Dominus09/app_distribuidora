import 'dart:async';
import 'package:uuid/uuid.dart';

import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/api_service.dart';
import '../utils/field_log.dart';
import 'outbox_database.dart';
import 'outbox_item_type.dart';
import 'telemetry_config.dart';

/// Procesa la cola offline con backoff exponencial y ACK del backend.
class OutboxQueueService {
  OutboxQueueService({
    required this.api,
    OutboxDatabase? database,
  }) : _db = database ?? OutboxDatabase.instance;

  final ApiService api;
  final OutboxDatabase _db;
  final _uuid = const Uuid();
  bool _flushing = false;

  bool get isFlushing => _flushing;

  Duration _backoffDelay(int retryCount) {
    final factor = 1 << retryCount.clamp(0, 6);
    final ms = TelemetryConfig.retryBaseDelay.inMilliseconds * factor;
    final capped = ms.clamp(
      TelemetryConfig.retryBaseDelay.inMilliseconds,
      TelemetryConfig.retryMaxDelay.inMilliseconds,
    );
    return Duration(milliseconds: capped);
  }

  /// Envía pendientes cuando hay red.
  Future<int> flushPending({bool onlyWhenReachable = true}) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      if (onlyWhenReachable) {
        final reach = await api.checkReachability(
          timeout: const Duration(seconds: 8),
        );
        if (!reach.ok) {
          fieldLog('OutboxQueue', 'sin red, flush omitido');
          return 0;
        }
      }

      final items = await _db.pendingItems();
      fieldLog('OutboxQueue', 'flush ${items.length} ítem(s) pendiente(s)');

      for (final row in items) {
        if (row.retryCount >= TelemetryConfig.maxRetryAttempts) {
          fieldLog(
            'OutboxQueue',
            'id=${row.id} superó reintentos (${row.retryCount})',
          );
          continue;
        }
        try {
          final ack = await _dispatch(row);
          if (ack) {
            await _db.markSynced(row.id);
            sent++;
            fieldLog('OutboxQueue', 'ACK id=${row.id} type=${row.itemType.value}');
          }
        } catch (e) {
          final next = row.retryCount + 1;
          final delay = _backoffDelay(next);
          await _db.scheduleRetry(
            row.id,
            next,
            DateTime.now().add(delay),
          );
          fieldLog(
            'OutboxQueue',
            'retry id=${row.id} intento=$next en ${delay.inSeconds}s: $e',
          );
        }
      }

      await _db.purgeSyncedOlderThan(const Duration(days: 7));
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
            );
          }
        }
        return ack.confirmed;
      case OutboxItemType.visitaSync:
        final raw = row.payload['visita'];
        if (raw is! Map) return false;
        final visita = Visita.fromJson(Map<String, dynamic>.from(raw));
        final saved = await api.registrarVisita(visita);
        final lid = visita.localActionId;
        if (lid != null && lid.isNotEmpty) {
          await _db.rememberProcessedAction(lid);
        }
        return saved.syncStatus == SyncStatus.synced ||
            saved.id.isNotEmpty;
    }
  }

  Future<void> enqueueHeartbeat(Map<String, dynamic> payload) async {
    final key = payload['idempotency_key'] as String? ??
        'hb_${payload['vendedor_id']}_${payload['timestamp']}';
    await _db.enqueue(
      type: OutboxItemType.heartbeat,
      payload: payload,
      idempotencyKey: key,
    );
    fieldLog('OutboxQueue', 'heartbeat encolado key=$key');
  }

  Future<void> enqueueGpsTrack(Map<String, dynamic> payload) async {
    await _db.enqueue(
      type: OutboxItemType.gpsTrack,
      payload: payload,
      idempotencyKey: payload['idempotency_key'] as String?,
    );
  }

  Future<void> enqueueVisitaBackup(Visita visita) async {
    final lid = visita.localActionId;
    if (lid == null || lid.isEmpty) return;
    await _db.enqueue(
      type: OutboxItemType.visitaSync,
      payload: {'visita': visita.toJson()},
      idempotencyKey: 'visita_$lid',
    );
    fieldLog('OutboxQueue', 'visita backup encolada lid=$lid');
  }

  String newHeartbeatIdempotencyKey(String vendedorId) {
    return 'hb_${vendedorId}_${_uuid.v4()}';
  }
}
