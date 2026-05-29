import 'dart:async';

import '../../../core/session/operational_scope.dart';
import '../../../core/telemetry/outbox_queue_service.dart';
import '../../../core/ux/offline_ux.dart';
import '../../../core/utils/field_log.dart';
import '../models/georef_estado.dart';
import '../models/georef_origen.dart';
import '../models/georef_pendiente.dart';
import '../models/visita.dart';
import 'api_service.dart';
import 'georef_local_store.dart';
import 'vendedor_service.dart';

/// Captura y sync de georreferencias operacionales (write-local-first + outbox).
class GeorefService {
  GeorefService({
    required this.api,
    required this.vendedorService,
    required this.queue,
    GeorefLocalStore? localStore,
    Future<void> Function()? onEnqueuedForSync,
  })  : _store = localStore ?? GeorefLocalStore(),
        _onEnqueuedForSync = onEnqueuedForSync;

  final ApiService api;
  final VendedorService vendedorService;
  final OutboxQueueService queue;
  final GeorefLocalStore _store;
  final Future<void> Function()? _onEnqueuedForSync;

  Future<List<GeorefPendiente>> loadPendientes({
    required OperationalScope scope,
    bool fetchRemote = true,
  }) async {
    final local = await _store.load(scope);
    if (!fetchRemote) return local;

    try {
      final reach = await api.checkReachability();
      if (!reach.ok) return local;
      final remote = await api.getGeorefPendientes(
        vendedor: scope.vendedorIdTrimmed,
      );
      final merged = GeorefLocalStore.mergeServidorConLocal(
        servidor: remote,
        local: local,
      );
      await _store.save(scope, merged);
      return merged;
    } catch (e) {
      fieldLog('Georef', 'GET pendientes falló: $e');
      return local;
    }
  }

  /// Contador KPI para Home: registros del GET (sin mezclar lista de ruta).
  Future<int> loadPendientesCount({
    required String vendedorId,
    bool fetchRemote = true,
  }) async {
    final vid = vendedorId.trim();
    final cached = await GeorefLocalStore.loadPendingCountCache(vid) ?? 0;
    if (!fetchRemote) return cached;

    try {
      final reach = await api.checkReachability();
      if (!reach.ok) return cached;
      final remote = await api.getGeorefPendientes(vendedor: vid);
      final count = remote.length;
      await GeorefLocalStore.savePendingCountCache(vid, count);
      return count;
    } catch (e) {
      fieldLog('Georef', 'KPI pendientes falló: $e');
      return cached;
    }
  }

  /// Captura GPS → persistencia local → outbox → HTTP async si hay red.
  Future<GeorefCaptureResult> capturarUbicacion({
    required OperationalScope scope,
    required GeorefPendiente item,
    required double lat,
    required double lon,
    String? observacion,
    List<Visita>? visitasActuales,
    GeorefOrigen origen = GeorefOrigen.gpsTerreno,
    bool omitirHttp = true,
  }) async {
    final actionId = vendedorService.generateLocalActionId();
    final actualizado = item.copyWith(
      latEfectiva: lat,
      lonEfectiva: lon,
      georefEstado: GeorefEstado.capturada,
      georefOrigen: origen,
      localSyncStatus: GeorefSyncStatus.pendingSync,
      localActionId: actionId,
      observacion: observacion ?? item.observacion,
    );

    final lista = await _store.load(scope);
    final idx = lista.indexWhere((e) => e.claveLocal == item.claveLocal);
    if (idx >= 0) {
      lista[idx] = actualizado;
    } else {
      lista.add(actualizado);
    }
    await _store.save(scope, lista);

    if (visitasActuales != null) {
      await _actualizarVisitasConGeoref(
        scope: scope,
        visitas: visitasActuales,
        clienteId: item.clienteId,
        lat: lat,
        lon: lon,
      );
    }

    await queue.enqueueGeorefUpdate(
      actualizado,
      vendedorId: scope.vendedorIdTrimmed,
      lat: lat,
      lon: lon,
      origen: origen,
      source: origen == GeorefOrigen.mapaManual
          ? 'GeorefService.capturarDesdeMapa'
          : 'GeorefService.capturarUbicacion',
    );

    if (!omitirHttp) {
      final flush = _onEnqueuedForSync;
      if (flush != null) unawaited(flush());
    }

    return GeorefCaptureResult(
      item: actualizado,
      mensajeUsuario:
          OfflineUx.mensajeTrasGuardarLocal(omitirHttp: omitirHttp),
      encolado: true,
    );
  }

  Future<void> _actualizarVisitasConGeoref({
    required OperationalScope scope,
    required List<Visita> visitas,
    required String clienteId,
    required double lat,
    required double lon,
  }) async {
    var changed = false;
    final next = visitas.map((v) {
      if (v.clienteId != clienteId && v.id != clienteId) return v;
      changed = true;
      return v.copyWith(latCliente: lat, lonCliente: lon);
    }).toList();
    if (!changed) return;
    await vendedorService.persistVisitasToDisk(scope, next);
  }
}

class GeorefCaptureResult {
  const GeorefCaptureResult({
    required this.item,
    required this.mensajeUsuario,
    required this.encolado,
  });

  final GeorefPendiente item;
  final String mensajeUsuario;
  final bool encolado;
}
