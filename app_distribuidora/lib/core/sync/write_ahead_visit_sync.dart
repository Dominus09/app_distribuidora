import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/vendedor_service.dart';
import '../session/operational_scope.dart';
import '../telemetry/operational_telemetry_service.dart';
import 'operational_sync_log.dart';

/// Write-ahead: persistir local → enqueue → (caller envía HTTP).
class WriteAheadVisitSync {
  const WriteAheadVisitSync({
    required this.vendedorService,
    required this.telemetry,
  });

  final VendedorService vendedorService;
  final OperationalTelemetryService telemetry;

  /// 1. Persiste en disco  2. Encola respaldo outbox. No hace HTTP.
  Future<List<Visita>> persistAndEnqueue({
    required OperationalScope scope,
    required List<Visita> visitas,
    required Visita updated,
  }) async {
    final idx = visitas.indexWhere((v) => v.id == updated.id);
    if (idx < 0) return visitas;

    final next = [...visitas];
    next[idx] = updated;

    await vendedorService.persistVisitasToDisk(scope, next);

    if (updated.syncStatus.necesitaPushRemoto ||
        updated.syncStatus == SyncStatus.syncError) {
      await telemetry.backupPendingVisita(updated);
    }

    opSyncLog(
      event: 'write_ahead_persisted',
      scope: scope,
      actionId: updated.localActionId,
      syncState: null,
      extra: 'visita_id=${updated.id} sync=${updated.syncStatus.persistValue}',
    );

    return next;
  }
}
