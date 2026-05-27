import 'package:flutter/foundation.dart';

import '../session/operational_scope.dart';
import '../utils/field_log.dart';
import 'outbox_item_type.dart';

/// Evento reciente de enqueue (panel debug).
class OutboxEnqueueEvent {
  const OutboxEnqueueEvent({
    required this.at,
    required this.type,
    required this.source,
    this.endpoint,
    this.idempotencyKey,
    this.insertId,
    this.queueSizeAfter,
    this.payloadSummary,
    this.skipped = false,
    this.skipReason,
    this.stackSnippet,
  });

  final DateTime at;
  final String type;
  final String source;
  final String? endpoint;
  final String? idempotencyKey;
  final int? insertId;
  final int? queueSizeAfter;
  final String? payloadSummary;
  final bool skipped;
  final String? skipReason;
  final String? stackSnippet;
}

/// Métricas y trazas de enqueue/flush (diagnóstico cola offline).
class OutboxObservability {
  OutboxObservability._();
  static final OutboxObservability instance = OutboxObservability._();

  static const _maxRecentEvents = 40;

  final Map<String, int> _enqueueByType = {};
  final Map<String, int> _flushOkByType = {};
  final Map<String, int> _flushFailByType = {};
  final Map<String, int> _skipByReason = {};
  final List<OutboxEnqueueEvent> _recentEnqueues = [];

  DateTime? _minuteWindowStart;
  int _enqueueInWindow = 0;
  final Map<String, int> _enqueuePerTypeThisMinute = {};

  /// Stack corto del caller (solo debug).
  static String? captureCallerStack({int frames = 6}) {
    if (!kDebugMode) return null;
    final lines = StackTrace.current.toString().split('\n');
    final slice = lines.length > 2
        ? lines.sublist(2, (2 + frames).clamp(2, lines.length))
        : lines;
    return slice.map((l) => l.trim()).join(' | ');
  }

  static String summarizePayload(Map<String, dynamic> payload) {
    final keys = payload.keys.take(12).join(',');
    final visita = payload['visita'];
    if (visita is Map) {
      final id = visita['id'];
      final st = visita['sync_status'] ?? visita['estado'];
      return 'visita_id=$id sync/estado=$st keys=[$keys]';
    }
    final puntos = payload['puntos'];
    final pids = payload['point_ids'];
    if (puntos is List || pids is List) {
      final n = pids is List ? pids.length : (puntos is List ? puntos.length : 0);
      return 'gps_points=$n keys=[$keys]';
    }
    return 'keys=[$keys]';
  }

  void recordEnqueue({
    required OutboxItemType type,
    required String source,
    String? endpoint,
    String? idempotencyKey,
    OperationalScope? scope,
    int? queueSizeAfter,
    int insertId = 0,
    String? payloadSummary,
    String? stackSnippet,
  }) {
    _enqueueByType[type.value] = (_enqueueByType[type.value] ?? 0) + 1;
    _bumpMinuteWindow(type.value);

    final parts = <String>[
      '[OUTBOX][ENQUEUE]',
      'tipo=${type.value}',
      'source=$source',
      if (endpoint != null) 'endpoint=$endpoint',
      if (scope != null) 'vendedor=${scope.vendedorIdTrimmed}',
      if (scope != null) 'fecha=${scope.fechaOperativa}',
      if (scope?.rutaId != null) 'ruta=${scope!.rutaId}',
      if (idempotencyKey != null) 'idempotency_key=$idempotencyKey',
      if (insertId > 0) 'insert_id=$insertId',
      if (insertId == -1) 'result=duplicate_skipped',
      if (queueSizeAfter != null) 'queue_sqlite=$queueSizeAfter',
      if (payloadSummary != null) 'payload=$payloadSummary',
      'rate_min=$_enqueueInWindow (${_formatPerMinuteRates()})',
      if (stackSnippet != null) 'stack=$stackSnippet',
    ];
    fieldLog('OutboxObs', parts.join(' '), throttle: false, force: true);

    _pushRecent(
      OutboxEnqueueEvent(
        at: DateTime.now(),
        type: type.value,
        source: source,
        endpoint: endpoint,
        idempotencyKey: idempotencyKey,
        insertId: insertId == 0 ? null : insertId,
        queueSizeAfter: queueSizeAfter,
        payloadSummary: payloadSummary,
        stackSnippet: stackSnippet,
      ),
    );
  }

  void recordEnqueueSkipped({
    required String source,
    required String reason,
    String? tipo,
    String? visitaId,
    String? stackSnippet,
  }) {
    _skipByReason[reason] = (_skipByReason[reason] ?? 0) + 1;
    fieldLog(
      'OutboxObs',
      '[OUTBOX][SKIP] source=$source reason=$reason '
      '${tipo != null ? "tipo=$tipo " : ""}'
      '${visitaId != null ? "visita_id=$visitaId " : ""}'
      '${stackSnippet != null ? "stack=$stackSnippet" : ""}',
      throttle: false,
      force: true,
    );
    _pushRecent(
      OutboxEnqueueEvent(
        at: DateTime.now(),
        type: tipo ?? '—',
        source: source,
        skipped: true,
        skipReason: reason,
        stackSnippet: stackSnippet,
      ),
    );
  }

  void recordFlushResult({
    required OutboxItemType type,
    required int itemId,
    required bool success,
    String? endpoint,
    int? retryCount,
    String? syncState,
    String? error,
    int? httpStatus,
  }) {
    final map = success ? _flushOkByType : _flushFailByType;
    map[type.value] = (map[type.value] ?? 0) + 1;
    fieldLog(
      'OutboxObs',
      '[OUTBOX][${success ? "ACK" : "FAIL"}] '
      'id=$itemId tipo=${type.value} endpoint=${endpoint ?? "—"} '
      'retry=$retryCount state=${syncState ?? "—"} '
      '${httpStatus != null ? "http=$httpStatus " : ""}'
      '${error != null ? "err=$error" : ""}',
      throttle: false,
      force: !success,
    );
  }

  void logStatusBreakdown({
    required int outboxSqlitePending,
    required int visitasSyncPendientes,
    required int displayedTotal,
    Map<String, int>? outboxByType,
  }) {
    fieldLog(
      'OutboxObs',
      '[OUTBOX][STATUS] '
      'sqlite_pending=$outboxSqlitePending '
      'visitas_sync_pendientes=$visitasSyncPendientes '
      'ui_total=$displayedTotal '
      '${outboxByType != null ? "sqlite_by_type=${outboxByType.entries.map((e) => "${e.key}:${e.value}").join(",")}" : ""}',
      throttle: false,
      force: outboxSqlitePending > 0 || visitasSyncPendientes > 0,
    );
  }

  void logScopeContext({
    required String event,
    OperationalScope? scope,
    int? serverClientes,
    int? cacheClientes,
    int? queuePending,
    int? visitasSyncPending,
    Map<String, int>? byType,
  }) {
    final parts = <String>[
      '[OUTBOX][SCOPE]',
      'event=$event',
      if (scope != null) 'scope=$scope',
      if (serverClientes != null) 'server_clientes=$serverClientes',
      if (cacheClientes != null) 'cache_clientes=$cacheClientes',
      if (queuePending != null) 'queue_sqlite=$queuePending',
      if (visitasSyncPending != null) 'visitas_sync=$visitasSyncPending',
      if (byType != null && byType.isNotEmpty)
        'sqlite_by_type=${byType.entries.map((e) => "${e.key}:${e.value}").join(",")}',
    ];
    fieldLog('OutboxObs', parts.join(' '), throttle: false);
  }

  void logGpsPointStored({
    required String vendedorId,
    required int totalUnuploaded,
  }) {
    fieldLog(
      'OutboxObs',
      '[GPS][STORE] v=$vendedorId unuploaded=$totalUnuploaded (no es outbox hasta fallo upload)',
      throttle: true,
    );
  }

  Map<String, int> get enqueueTotals => Map.unmodifiable(_enqueueByType);
  Map<String, int> get skipTotals => Map.unmodifiable(_skipByReason);
  List<OutboxEnqueueEvent> get recentEnqueues =>
      List.unmodifiable(_recentEnqueues);

  Map<String, int> get ratesPerMinuteThisWindow =>
      Map.unmodifiable(_enqueuePerTypeThisMinute);

  void _bumpMinuteWindow(String type) {
    final now = DateTime.now();
    if (_minuteWindowStart == null ||
        now.difference(_minuteWindowStart!) > const Duration(minutes: 1)) {
      _minuteWindowStart = now;
      _enqueueInWindow = 0;
      _enqueuePerTypeThisMinute.clear();
    }
    _enqueueInWindow++;
    _enqueuePerTypeThisMinute[type] =
        (_enqueuePerTypeThisMinute[type] ?? 0) + 1;
  }

  String _formatPerMinuteRates() {
    if (_enqueuePerTypeThisMinute.isEmpty) return '—';
    return _enqueuePerTypeThisMinute.entries
        .map((e) => '${e.key}:${e.value}/min')
        .join(',');
  }

  void _pushRecent(OutboxEnqueueEvent e) {
    _recentEnqueues.insert(0, e);
    while (_recentEnqueues.length > _maxRecentEvents) {
      _recentEnqueues.removeLast();
    }
  }
}
