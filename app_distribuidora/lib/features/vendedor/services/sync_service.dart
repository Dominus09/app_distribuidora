import '../models/visita.dart';

/// Resultado de una pasada de sincronización mock (sin API real).
class SyncBatchResult {
  const SyncBatchResult({
    required this.visitas,
    required this.newlySyncedCount,
    required this.skippedDuplicatesCount,
    required this.stillPendingCount,
    this.duplicateRun = false,
  });

  final List<Visita> visitas;
  final int newlySyncedCount;
  final int skippedDuplicatesCount;
  final int stillPendingCount;

  /// True si ya había otra sincronización en curso (no se reintentó la cola).
  final bool duplicateRun;
}

/// Sincronización mock idempotente: evita duplicar `localActionId` ya enviados.
class SyncService {
  /// IDs de acciones ya confirmadas por el "servidor" mock.
  final Set<String> _processedActionIds = <String>{};

  bool _syncInProgress = false;

  /// Marca una acción como ya subida (p. ej. guardado online inmediato).
  void acknowledgeActionProcessed(String actionId) {
    _processedActionIds.add(actionId);
  }

  /// Sincroniza solo [SyncStatus.pendingSync]. Seguro ante múltiples toques seguidos.
  Future<SyncBatchResult> forceSyncPending(List<Visita> source) async {
    if (_syncInProgress) {
      return SyncBatchResult(
        visitas: List<Visita>.from(source),
        newlySyncedCount: 0,
        skippedDuplicatesCount: 0,
        stillPendingCount: source.where((v) => v.syncStatus == SyncStatus.pendingSync).length,
        duplicateRun: true,
      );
    }

    _syncInProgress = true;
    await Future<void>.delayed(const Duration(milliseconds: 550));

    try {
      var newlySynced = 0;
      var skippedDup = 0;
      final out = <Visita>[];

      for (final v in source) {
        if (v.syncStatus == SyncStatus.synced) {
          out.add(v);
          continue;
        }

        if (v.syncStatus == SyncStatus.pendingSync) {
          final id = v.localActionId;
          if (id == null) {
            out.add(v);
            continue;
          }
          if (_processedActionIds.contains(id)) {
            skippedDup++;
            out.add(v.copyWith(syncStatus: SyncStatus.synced));
            continue;
          }

          _processedActionIds.add(id);
          newlySynced++;
          out.add(_applyMockServerAck(v));
          continue;
        }

        out.add(v);
      }

      final stillPending =
          out.where((v) => v.syncStatus == SyncStatus.pendingSync).length;

      return SyncBatchResult(
        visitas: out,
        newlySyncedCount: newlySynced,
        skippedDuplicatesCount: skippedDup,
        stillPendingCount: stillPending,
      );
    } finally {
      _syncInProgress = false;
    }
  }

  /// Simula ACK del backend: cierra sync y confirma validaciones diferidas en visitas.
  Visita _applyMockServerAck(Visita v) {
    var nextVal = v.validacionEstado;
    if (v.estado == VisitaEstado.visitado) {
      if (nextVal == ValidacionEstado.offline ||
          nextVal == ValidacionEstado.pendienteValidacion ||
          nextVal == ValidacionEstado.sinGps) {
        nextVal = ValidacionEstado.validado;
      }
    }
    return v.copyWith(
      syncStatus: SyncStatus.synced,
      validacionEstado: nextVal,
    );
  }
}
