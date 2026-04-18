import 'dart:async';
import 'dart:convert';

import '../models/visita.dart';
import 'api_service.dart';

const Duration _kRegistrarTimeout = Duration(seconds: 25);

/// Detalle de un fallo al enviar una visita (diálogo / SnackBar y trazas).
class SyncVisitaErrorDetail {
  const SyncVisitaErrorDetail({
    required this.visitaId,
    required this.clientLabel,
    required this.reason,
  });

  final String visitaId;
  final String clientLabel;
  final String reason;

  String get userMessage => 'Error en cliente $clientLabel: $reason';
}

/// Resultado de [SyncService.trySyncVisitaAfterLocalSave].
class TrySyncVisitaResult {
  const TrySyncVisitaResult({required this.visitas, this.error});

  final List<Visita> visitas;
  final SyncVisitaErrorDetail? error;
}

/// Resultado de una pasada de sincronización forzada (varios registros).
class SyncBatchResult {
  const SyncBatchResult({
    required this.visitas,
    required this.syncedCount,
    required this.omittedCount,
    required this.errorCount,
    required this.pendingAfterCount,
    required this.syncErrorAfterCount,
    this.duplicateRun = false,
    this.blockedMessage,
    this.errorDetails = const [],
  });

  final List<Visita> visitas;
  final int syncedCount;
  final int omittedCount;
  final int errorCount;
  final int pendingAfterCount;
  final int syncErrorAfterCount;
  final bool duplicateRun;
  final String? blockedMessage;
  final List<SyncVisitaErrorDetail> errorDetails;
}

String _truncate(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

String _humanizeHttpBody(ApiHttpException e) {
  try {
    final j = jsonDecode(e.body);
    if (j is Map<String, dynamic>) {
      final d = j['detail'];
      if (d is String && d.trim().isNotEmpty) {
        return _truncate(d.trim(), 220);
      }
      if (d is List<dynamic>) {
        final parts = <String>[];
        for (final item in d) {
          if (item is Map<String, dynamic>) {
            final msg = item['msg'];
            if (msg != null) parts.add(msg.toString());
          }
        }
        if (parts.isNotEmpty) return _truncate(parts.join('; '), 220);
      }
    }
  } catch (_) {}
  final raw = e.body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (raw.isNotEmpty) return _truncate(raw, 220);
  return 'HTTP ${e.statusCode}';
}

String _reasonForException(Object e) {
  if (e is ApiHttpException) return _humanizeHttpBody(e);
  if (e is TimeoutException) return 'Tiempo de espera agotado';
  if (e is FormatException) {
    final m = e.message.trim();
    if (m.isNotEmpty) return m;
    return 'Respuesta inválida';
  }
  final s = e.toString();
  return s.length > 220 ? '${s.substring(0, 220)}…' : s;
}

String _clientLabelForSync(Visita v) {
  final cid = v.clienteId?.trim();
  if (cid != null && cid.isNotEmpty) return cid;
  final t = v.tituloMapaCliente.trim();
  if (t.isNotEmpty) return t;
  final id = v.id.trim();
  return id.isEmpty ? '—' : id;
}

SyncVisitaErrorDetail _syncFailureDetail(Visita v, Object e) {
  // ignore: avoid_print — trazas solicitadas para depuración en terreno.
  print('Error sync visita ID: ${v.id}');
  return SyncVisitaErrorDetail(
    visitaId: v.id,
    clientLabel: _clientLabelForSync(v),
    reason: _reasonForException(e),
  );
}

/// Sincronización con API + idempotencia local por `localActionId`.
class SyncService {
  final Set<String> _processedActionIds = <String>{};
  bool _outboundBusy = false;

  void acknowledgeActionProcessed(String actionId) {
    _processedActionIds.add(actionId);
  }

  List<Visita> normalizeStuckSyncing(List<Visita> source) {
    return source
        .map(
          (v) => v.syncStatus == SyncStatus.syncing
              ? v.copyWith(syncStatus: SyncStatus.pendingSync)
              : v,
        )
        .toList();
  }

  bool _needsForceQueue(SyncStatus s) =>
      s == SyncStatus.pendingSync || s == SyncStatus.syncError;

  Visita _mergeServerResponse(Visita local, Visita fromServer) {
    final sid = fromServer.id.trim();
    return fromServer.copyWith(
      syncStatus: SyncStatus.synced,
      localActionId: local.localActionId,
      id: sid.isNotEmpty ? fromServer.id : local.id,
    );
  }

  bool _isDuplicateHttp(ApiHttpException e) {
    if (e.statusCode == 409) return true;
    final b = e.body.toLowerCase();
    return b.contains('duplic') ||
        b.contains('duplicate') ||
        b.contains('ya existe') ||
        b.contains('already exists') ||
        b.contains('omitido');
  }

  /// Tras guardar en local, intenta un POST si hay conectividad de app; el caller debe hacer `pingReachable` antes si lo desea.
  Future<TrySyncVisitaResult> trySyncVisitaAfterLocalSave(
    List<Visita> source,
    String visitaId,
    ApiService api,
  ) async {
    if (_outboundBusy) {
      return TrySyncVisitaResult(visitas: List<Visita>.from(source));
    }

    var list = normalizeStuckSyncing(List<Visita>.from(source));
    final idx = list.indexWhere((v) => v.id == visitaId);
    if (idx < 0) return TrySyncVisitaResult(visitas: list);

    var v = list[idx];
    if (!_needsForceQueue(v.syncStatus) && v.syncStatus != SyncStatus.syncing) {
      return TrySyncVisitaResult(visitas: list);
    }
    if (v.syncStatus == SyncStatus.syncing) {
      v = v.copyWith(syncStatus: SyncStatus.pendingSync);
      list[idx] = v;
    }

    final lid = v.localActionId;
    if (lid == null || lid.isEmpty || !v.puedeEnviarseAlBackend) {
      return TrySyncVisitaResult(visitas: list);
    }
    if (_processedActionIds.contains(lid)) {
      list[idx] = v.copyWith(syncStatus: SyncStatus.synced);
      return TrySyncVisitaResult(visitas: list);
    }

    _outboundBusy = true;
    SyncVisitaErrorDetail? errorOut;
    try {
      list[idx] = v.copyWith(syncStatus: SyncStatus.syncing);
      v = list[idx];

      try {
        final saved = await api
            .registrarVisita(v)
            .timeout(_kRegistrarTimeout);
        _processedActionIds.add(lid);
        list[idx] = _mergeServerResponse(v, saved);
      } on ApiHttpException catch (e) {
        if (_isDuplicateHttp(e)) {
          _processedActionIds.add(lid);
          list[idx] = v.copyWith(syncStatus: SyncStatus.synced);
        } else {
          errorOut = _syncFailureDetail(list[idx], e);
          list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
        }
      } on TimeoutException catch (e) {
        errorOut = _syncFailureDetail(list[idx], e);
        list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
      } on FormatException catch (e) {
        errorOut = _syncFailureDetail(list[idx], e);
        list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
      } catch (e) {
        errorOut = _syncFailureDetail(list[idx], e);
        list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
      }
      return TrySyncVisitaResult(visitas: list, error: errorOut);
    } finally {
      _outboundBusy = false;
    }
  }

  /// Envía uno a uno los pendientes con error o pendientes de envío (no reenvía `synced`).
  Future<SyncBatchResult> forceSyncPending(
    List<Visita> source,
    ApiService api,
  ) async {
    if (_outboundBusy) {
      final list = List<Visita>.from(source);
      return SyncBatchResult(
        visitas: list,
        syncedCount: 0,
        omittedCount: 0,
        errorCount: 0,
        pendingAfterCount:
            list.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        syncErrorAfterCount:
            list.where((v) => v.syncStatus == SyncStatus.syncError).length,
        duplicateRun: true,
      );
    }

    var list = normalizeStuckSyncing(List<Visita>.from(source));

    final queue = list
        .where((v) => _needsForceQueue(v.syncStatus))
        .toList();

    if (queue.isEmpty) {
      return SyncBatchResult(
        visitas: list,
        syncedCount: 0,
        omittedCount: 0,
        errorCount: 0,
        pendingAfterCount:
            list.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        syncErrorAfterCount:
            list.where((v) => v.syncStatus == SyncStatus.syncError).length,
      );
    }

    final ready = queue.where((v) => v.puedeEnviarseAlBackend).toList();
    final notReady = queue.where((v) => !v.puedeEnviarseAlBackend).toList();

    if (ready.isEmpty) {
      return SyncBatchResult(
        visitas: list,
        syncedCount: 0,
        omittedCount: 0,
        errorCount: 0,
        pendingAfterCount:
            list.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        syncErrorAfterCount:
            list.where((v) => v.syncStatus == SyncStatus.syncError).length,
        blockedMessage: notReady.isEmpty
            ? null
            : 'Hay ${notReady.length} registro(s) que no se pueden enviar (falta id de visita, '
                'ruta u orden). Vuelve a cargar la ruta desde el servidor.',
      );
    }

    _outboundBusy = true;
    var synced = 0;
    var omitted = 0;
    var errors = 0;
    final errorDetails = <SyncVisitaErrorDetail>[];

    try {
      for (final target in ready) {
        final idx = list.indexWhere((v) => v.id == target.id);
        if (idx < 0) continue;
        var v = list[idx];
        if (!_needsForceQueue(v.syncStatus)) continue;

        final lid = v.localActionId;
        if (lid == null || lid.isEmpty) continue;

        if (_processedActionIds.contains(lid)) {
          list[idx] = v.copyWith(syncStatus: SyncStatus.synced);
          omitted++;
          continue;
        }

        list[idx] = v.copyWith(syncStatus: SyncStatus.syncing);
        v = list[idx];

        try {
          final saved = await api
              .registrarVisita(v)
              .timeout(_kRegistrarTimeout);
          _processedActionIds.add(lid);
          list[idx] = _mergeServerResponse(v, saved);
          synced++;
        } on ApiHttpException catch (e) {
          if (_isDuplicateHttp(e)) {
            _processedActionIds.add(lid);
            list[idx] = v.copyWith(syncStatus: SyncStatus.synced);
            omitted++;
          } else {
            errorDetails.add(_syncFailureDetail(list[idx], e));
            list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
            errors++;
          }
        } on TimeoutException catch (e) {
          errorDetails.add(_syncFailureDetail(list[idx], e));
          list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
          errors++;
        } on FormatException catch (e) {
          errorDetails.add(_syncFailureDetail(list[idx], e));
          list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
          errors++;
        } catch (e) {
          errorDetails.add(_syncFailureDetail(list[idx], e));
          list[idx] = list[idx].copyWith(syncStatus: SyncStatus.pendingSync);
          errors++;
        }
      }

      list = list.map(_ensureSyncedIfProcessed).toList();

      final pendingAfter =
          list.where((v) => v.syncStatus == SyncStatus.pendingSync).length;
      final errAfter =
          list.where((v) => v.syncStatus == SyncStatus.syncError).length;

      return SyncBatchResult(
        visitas: list,
        syncedCount: synced,
        omittedCount: omitted,
        errorCount: errors,
        pendingAfterCount: pendingAfter,
        syncErrorAfterCount: errAfter,
        errorDetails: errorDetails,
        blockedMessage: notReady.isEmpty
            ? null
            : '${notReady.length} registro(s) no se intentaron enviar (falta id de visita, ruta u orden). '
                'Recarga la ruta y reintenta.',
      );
    } finally {
      _outboundBusy = false;
    }
  }

  Visita _ensureSyncedIfProcessed(Visita v) {
    final id = v.localActionId;
    if (_needsForceQueue(v.syncStatus) &&
        id != null &&
        _processedActionIds.contains(id)) {
      return v.copyWith(syncStatus: SyncStatus.synced);
    }
    return v;
  }
}
