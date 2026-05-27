import 'package:flutter_test/flutter_test.dart';

import 'package:app_distribuidora/core/sync/cache_integrity.dart';
import 'package:app_distribuidora/core/sync/outbox_sync_state.dart';
import 'package:app_distribuidora/core/sync/processed_action_record.dart';
import 'package:app_distribuidora/core/sync/visita_reconciliation.dart';
import 'package:app_distribuidora/core/session/operational_scope.dart';
import 'package:app_distribuidora/features/vendedor/models/visita.dart';
import 'package:app_distribuidora/features/vendedor/services/vendedor_service.dart';

Visita _v({
  String id = '1',
  VisitaEstado estado = VisitaEstado.pendiente,
  SyncStatus sync = SyncStatus.synced,
  TipoIncidencia? tipo,
  String? actionId,
}) {
  return Visita(
    id: id,
    rutaId: 10,
    clienteNombre: 'C',
    direccion: 'D',
    diaOperativo: 'Miércoles',
    orden: 1,
    estado: estado,
    latCliente: 0,
    lonCliente: 0,
    syncStatus: sync,
    tipoIncidencia: tipo,
    localActionId: actionId,
  );
}

void main() {
  group('ProcessedActionRecord', () {
    test('memoryKey incluye vendedor fecha ruta action', () {
      const scope = OperationalScope(
        vendedorId: 'v1',
        fechaOperativa: '2026-05-27',
        rutaId: 5,
      );
      final r = ProcessedActionRecord.fromScope(scope, 'uuid-abc');
      expect(r.memoryKey, 'v1|2026-05-27|5|uuid-abc');
    });
  });

  group('VisitaReconciliation prioridad', () {
    test('nunca degrada visitado a pendiente', () {
      final local = _v(
        id: '1',
        estado: VisitaEstado.visitado,
        sync: SyncStatus.pendingSync,
        actionId: 'u1',
      );
      final server = _v(id: '1', estado: VisitaEstado.pendiente);
      final out = VisitaReconciliation.reconciliar(servidor: server, local: local);
      expect(out.estado, VisitaEstado.visitado);
    });

    test('sin_compra (noCompra) gana sobre incidencia genérica', () {
      final a = _v(
        id: '1',
        estado: VisitaEstado.incidencia,
        tipo: TipoIncidencia.otros,
      );
      final b = _v(
        id: '1',
        estado: VisitaEstado.incidencia,
        tipo: TipoIncidencia.noCompra,
      );
      expect(VisitaReconciliation.estadoPrioridad(b), 3);
      expect(
        VisitaReconciliation.estadoPrioridad(b) >
            VisitaReconciliation.estadoPrioridad(a),
        isTrue,
      );
      final winner = VisitaReconciliation.pickWinner(a, b);
      expect(winner.tipoIncidencia, TipoIncidencia.noCompra);
    });
  });

  group('CacheIntegrity', () {
    test('detecta corrupción de checksum', () {
      final payload = CacheIntegrity.wrapWithIntegrity({
        'vendedor_codigo': 'v1',
        'visitas': [],
      });
      payload['visitas'] = [{'id': 'hacked'}];
      expect(CacheIntegrity.verifyPayload(payload), isFalse);
    });

    test('acepta payload sin checksum legacy', () {
      expect(
        CacheIntegrity.verifyPayload({'visitas': []}),
        isTrue,
      );
    });
  });

  group('OutboxSyncState', () {
    test('dead_letter es terminal', () {
      expect(OutboxSyncState.deadLetter.isTerminal, isTrue);
      expect(OutboxSyncState.pending.isRetryable, isTrue);
    });
  });

  group('UUID action ids', () {
    test('generateLocalActionId es UUID v4', () {
      final svc = VendedorService();
      final id = svc.generateLocalActionId();
      final re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(re.hasMatch(id), isTrue);
      expect(svc.generateLocalActionId(), isNot(id));
    });
  });
}
