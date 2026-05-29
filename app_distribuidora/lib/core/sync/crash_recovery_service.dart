import '../../features/vendedor/models/visita.dart';
import '../../features/vendedor/services/sync_service.dart';
import '../../features/vendedor/services/vendedor_service.dart';
import '../session/operational_scope.dart';
import '../telemetry/outbox_database.dart';
import '../telemetry/outbox_queue_service.dart';
import 'operational_sync_log.dart';

/// Recuperación tras crash / kill del SO: normaliza estados atascados y reanuda cola.
class CrashRecoveryService {
  CrashRecoveryService({
    OutboxDatabase? database,
  }) : _db = database ?? OutboxDatabase.instance;

  final OutboxDatabase _db;

  Future<CrashRecoveryReport> recover({
    required OperationalScope scope,
    required SyncService syncService,
    required VendedorService vendedorService,
    required OutboxQueueService queue,
    List<Visita> runtimeVisitas = const [],
  }) async {
    opSyncLog(event: 'recovery_start', scope: scope);

    await _db.resetStuckOutboxSyncing(
      vendedorId: scope.vendedorIdTrimmed,
      scope: scope,
    );

    var visitas = syncService.normalizeStuckSyncing(runtimeVisitas);
    final hadStuckSyncing =
        runtimeVisitas.any((v) => v.syncStatus == SyncStatus.syncing);

    if (visitas.isEmpty) {
      final disk = await vendedorService.loadVisitasFromDisk(scope) ?? <Visita>[];
      if (disk.isNotEmpty) {
        visitas = VendedorService.fusionarDiscoYMemoria(
          disco: disk,
          memoria: visitas,
        );
        await vendedorService.persistVisitasToDisk(scope, visitas);
      }
    } else if (hadStuckSyncing) {
      await vendedorService.persistVisitasToDisk(scope, visitas);
    }

    final deadCount = await _db.deadLetterCount(
      vendedorId: scope.vendedorIdTrimmed,
      scope: scope,
    );
    final pendingOutbox = await _db.pendingCount(
      vendedorId: scope.vendedorIdTrimmed,
      scope: scope,
    );

    opSyncLog(
      event: 'recovery_done',
      scope: scope,
      extra: 'visitas=${visitas.length} outbox_pending=$pendingOutbox dead=$deadCount',
    );

    return CrashRecoveryReport(
      visitas: visitas,
      pendingOutboxCount: pendingOutbox,
      deadLetterCount: deadCount,
    );
  }
}

class CrashRecoveryReport {
  const CrashRecoveryReport({
    required this.visitas,
    required this.pendingOutboxCount,
    required this.deadLetterCount,
  });

  final List<Visita> visitas;
  final int pendingOutboxCount;
  final int deadLetterCount;

  bool get hasDeadLetters => deadLetterCount > 0;
}
