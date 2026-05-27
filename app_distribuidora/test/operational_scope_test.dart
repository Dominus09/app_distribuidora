import 'package:flutter_test/flutter_test.dart';

import 'package:app_distribuidora/core/session/operational_scope.dart';
import 'package:app_distribuidora/features/vendedor/models/visita.dart';
import 'package:app_distribuidora/features/vendedor/services/vendedor_service.dart';

Visita _visita({
  required String id,
  VisitaEstado estado = VisitaEstado.pendiente,
  SyncStatus sync = SyncStatus.synced,
  String? localActionId,
  int? rutaId,
  String? diaOperativo,
}) {
  return Visita(
    id: id,
    rutaId: rutaId ?? 10,
    clienteNombre: 'Cliente $id',
    direccion: 'Dir',
    diaOperativo: diaOperativo ?? 'Miércoles',
    orden: 1,
    estado: estado,
    latCliente: -33.4,
    lonCliente: -70.6,
    syncStatus: sync,
    localActionId: localActionId,
  );
}

void main() {
  group('OperationalScope', () {
    test('cacheKey incluye vendedor, fecha y ruta', () {
      const scope = OperationalScope(
        vendedorId: 'v1',
        fechaOperativa: '2026-05-27',
        rutaId: 42,
      );
      expect(
        scope.cacheKey,
        'vendedor_ruta_visitas_json__v1__2026-05-27__r42',
      );
    });

    test('matchesVisita respeta dia operativo y ruta', () {
      const scope = OperationalScope(
        vendedorId: 'v1',
        fechaOperativa: '2026-05-27',
        rutaId: 10,
      );
      final ref = DateTime(2026, 5, 27);
      expect(
        scope.matchesVisita(
          _visita(id: '1', rutaId: 10, diaOperativo: 'Miércoles'),
          fechaCalendario: ref,
        ),
        isTrue,
      );
      expect(
        scope.matchesVisita(
          _visita(id: '2', rutaId: 99, diaOperativo: 'Miércoles'),
          fechaCalendario: ref,
        ),
        isFalse,
      );
    });
  });

  group('mergeServidorConLocales', () {
    test('no pisa visita local marcada con pendiente del servidor', () {
      final servidor = [
        _visita(id: '1', estado: VisitaEstado.pendiente),
      ];
      final locales = [
        _visita(
          id: '1',
          estado: VisitaEstado.visitado,
          sync: SyncStatus.pendingSync,
          localActionId: 'act_1',
        ),
      ];
      final merged = VendedorService.mergeServidorConLocales(
        servidor: servidor,
        locales: locales,
      );
      expect(merged.single.estado, VisitaEstado.visitado);
      expect(merged.single.syncStatus, SyncStatus.pendingSync);
    });

    test('servidor gana si local no tiene progreso', () {
      final servidor = [
        _visita(id: '1', estado: VisitaEstado.visitado),
      ];
      final locales = [
        _visita(id: '1', estado: VisitaEstado.pendiente),
      ];
      final merged = VendedorService.mergeServidorConLocales(
        servidor: servidor,
        locales: locales,
      );
      expect(merged.single.estado, VisitaEstado.visitado);
    });
  });

  group('filterForScope', () {
    test('excluye visitas de otra ruta', () {
      const scope = OperationalScope(
        vendedorId: 'v1',
        fechaOperativa: '2026-05-27',
        rutaId: 10,
      );
      final ref = DateTime(2026, 5, 27);
      final list = [
        _visita(id: '1', rutaId: 10, diaOperativo: 'Miércoles'),
        _visita(id: '2', rutaId: 20, diaOperativo: 'Miércoles'),
      ];
      final filtered = VendedorService.filterForScope(list, scope);
      expect(filtered.length, 1);
      expect(filtered.single.id, '1');
      expect(
        scope.matchesVisita(filtered.single, fechaCalendario: ref),
        isTrue,
      );
    });
  });
}
