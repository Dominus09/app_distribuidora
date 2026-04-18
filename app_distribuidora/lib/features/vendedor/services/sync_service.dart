import 'dart:async';

import '../models/visita.dart';
import 'api_service.dart';

const Duration _kRegistrarTimeout = Duration(seconds: 25);

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
  });

  final List<Visita> visitas;
  final int syncedCount;
  final int omittedCount;
  final int errorCount;
  final int pendingAfterCount;
  final int syncErrorAfterCount;
  final bool duplicateRun;
  final String? blockedMessage;
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
  Future<List<Visita>> trySyncVisitaAfterLocalSave(
    List<Visita> source,
    String visitaId,
    ApiService api,
  ) async {
    if (_outboundBusy) return List<Visita>.from(source);

    var list = normalizeStuckSyncing(List<Visita>.from(source));
    final idx = list.indexWhere((v) => v.id == visitaId);
    if (idx < 0) return list;

    var v = list[idx];
    if (!_needsForceQueue(v.syncStatus) && v.syncStatus != SyncStatus.syncing) {
      return list;
    }
    if (v.syncStatus == SyncStatus.syncing) {
      v = v.copyWith(syncStatus: SyncStatus.pendingSync);
      list[idx] = v;
    }

    final lid = v.localActionId;
    if (lid == null || lid.isEmpty || !v.puedeEnviarseAlBackend) {
      return list;
    }
    if (_processedActionIds.contains(lid)) {
      list[idx] = v.copyWith(syncStatus: SyncStatus.synced);
      return list;
    }

    _outboundBusy = true;
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
          list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
        }
      } on TimeoutException {
        list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
      } on FormatException {
        list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
      } catch (_) {
        list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
      }
      return list;
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
        pendingAfterCount: list.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        syncErrorAfterCount: list.where((v) => v.syncStatus == SyncStatus.syncError).length,
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
            list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
            errors++;
          }
        } on TimeoutException {
          list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
          errors++;
        } on FormatException {
          list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
          errors++;
        } catch (_) {
          list[idx] = v.copyWith(syncStatus: SyncStatus.syncError);
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
