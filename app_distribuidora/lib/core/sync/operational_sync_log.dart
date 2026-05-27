import '../session/operational_scope.dart';
import '../utils/field_log.dart';
import 'outbox_sync_state.dart';

/// Logs estructurados para operaciones offline/sync.
void opSyncLog({
  required String event,
  OperationalScope? scope,
  String? actionId,
  OutboxSyncState? syncState,
  String? extra,
}) {
  final parts = <String>[
    'event=$event',
    if (scope != null) 'scope=$scope',
    if (scope != null) 'vendedor=${scope.vendedorIdTrimmed}',
    if (scope != null) 'fecha=${scope.fechaOperativa}',
    if (scope?.rutaId != null) 'ruta=${scope!.rutaId}',
    if (actionId != null && actionId.isNotEmpty) 'action_id=$actionId',
    if (syncState != null) 'sync_state=${syncState.dbValue}',
    if (extra != null && extra.isNotEmpty) extra,
  ];
  fieldLog('OpSync', parts.join(' '), throttle: false);
}

void opSyncLogImportant({
  required String event,
  OperationalScope? scope,
  String? actionId,
  String? extra,
}) {
  opSyncLog(
    event: event,
    scope: scope,
    actionId: actionId,
    extra: extra,
  );
  fieldLogImportant('OpSync', event);
}
