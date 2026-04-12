import '../models/visita.dart';
import 'api_service.dart';

/// Resultado de una pasada de sincronización con el backend.
class SyncBatchResult {
  const SyncBatchResult({
    required this.visitas,
    required this.newlySyncedCount,
    required this.skippedDuplicatesCount,
    required this.stillPendingCount,
    this.duplicateRun = false,
    this.errorMessage,
  });

  final List<Visita> visitas;
  final int newlySyncedCount;
  final int skippedDuplicatesCount;
  final int stillPendingCount;
  final bool duplicateRun;
  final String? errorMessage;
}

/// Sincronización con API + idempotencia local por `localActionId`.
class SyncService {
  final Set<String> _processedActionIds = <String>{};
  bool _syncInProgress = false;

  void acknowledgeActionProcessed(String actionId) {
    _processedActionIds.add(actionId);
  }

  /// Envía pendientes a POST `/visitas/sync` (`SyncResponse`: contadores, sin lista de visitas).
  Future<SyncBatchResult> forceSyncPending(
    List<Visita> source,
    ApiService api,
  ) async {
    if (_syncInProgress) {
      return SyncBatchResult(
        visitas: List<Visita>.from(source),
        newlySyncedCount: 0,
        skippedDuplicatesCount: 0,
        stillPendingCount:
            source.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        duplicateRun: true,
      );
    }

    final pending =
        source.where((v) => v.syncStatus == SyncStatus.pendingSync).toList();
    if (pending.isEmpty) {
      return SyncBatchResult(
        visitas: List<Visita>.from(source),
        newlySyncedCount: 0,
        skippedDuplicatesCount: 0,
        stillPendingCount: 0,
      );
    }

    _syncInProgress = true;
    try {
      var skippedDup = 0;
      final toSend = <Visita>[];

      for (final v in pending) {
        final id = v.localActionId;
        if (id == null || id.isEmpty) {
          continue;
        }
        if (!v.puedeEnviarseAlBackend) {
          return SyncBatchResult(
            visitas: List<Visita>.from(source),
            newlySyncedCount: 0,
            skippedDuplicatesCount: 0,
            stillPendingCount:
                source.where((x) => x.syncStatus == SyncStatus.pendingSync).length,
            errorMessage:
                'Una o más visitas pendientes no tienen ruta_id u orden válidos para sincronizar. '
                'Vuelve a cargar la ruta desde el servidor.',
          );
        }
        if (_processedActionIds.contains(id)) {
          skippedDup++;
          continue;
        }
        toSend.add(v);
      }

      if (toSend.isEmpty) {
        final repaired = source.map(_ensureSyncedIfProcessed).toList();
        return SyncBatchResult(
          visitas: repaired,
          newlySyncedCount: 0,
          skippedDuplicatesCount: skippedDup,
          stillPendingCount:
              repaired.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        );
      }

      final result = await api.syncVisitas(toSend);

      if (result.errores > 0) {
        return SyncBatchResult(
          visitas: List<Visita>.from(source),
          newlySyncedCount: 0,
          skippedDuplicatesCount: skippedDup,
          stillPendingCount:
              source.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
          errorMessage:
              'El servidor reportó ${result.errores} error(es). '
              'Sincronizados: ${result.sincronizados}, omitidos: ${result.omitidos}.',
        );
      }

      for (final v in toSend) {
        final lid = v.localActionId;
        if (lid != null) _processedActionIds.add(lid);
      }

      final byId = {for (final v in source) v.id: v};
      for (final sent in toSend) {
        final cur = byId[sent.id];
        if (cur != null) {
          byId[sent.id] = cur.copyWith(syncStatus: SyncStatus.synced);
        }
      }
      final merged = byId.values.toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

      return SyncBatchResult(
        visitas: merged,
        newlySyncedCount: result.sincronizados,
        skippedDuplicatesCount: skippedDup + result.omitidos,
        stillPendingCount:
            merged.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
      );
    } catch (e) {
      return SyncBatchResult(
        visitas: List<Visita>.from(source),
        newlySyncedCount: 0,
        skippedDuplicatesCount: 0,
        stillPendingCount:
            source.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        errorMessage: e.toString(),
      );
    } finally {
      _syncInProgress = false;
    }
  }

  Visita _ensureSyncedIfProcessed(Visita v) {
    final id = v.localActionId;
    if (v.syncStatus == SyncStatus.pendingSync &&
        id != null &&
        _processedActionIds.contains(id)) {
      return v.copyWith(syncStatus: SyncStatus.synced);
    }
    return v;
  }
}
