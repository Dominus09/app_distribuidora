import 'dart:async';

import '../../../core/session/operational_scope.dart';
import '../../../core/telemetry/outbox_queue_service.dart';
import '../../../core/ux/offline_ux.dart';
import '../../../core/utils/field_log.dart';
import '../models/georef_estado.dart';
import '../models/georef_origen.dart';
import '../models/georef_pendiente.dart';
import '../models/visita.dart';
import '../utils/georef_pendiente_filter.dart';
import 'api_service.dart';
import 'georef_local_store.dart';
import 'vendedor_service.dart';

/// Resultado del KPI Home (misma fuente que pantalla pendientes).
class GeorefKpiSnapshot {
  const GeorefKpiSnapshot({
    this.count,
    this.fromCache = false,
  });

  final int? count;
  final bool fromCache;

  bool get hasValue => count != null;
}

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

  static const kpiEndpoint = 'operaciones/georef-pendientes';

  final ApiService api;
  final VendedorService vendedorService;
  final OutboxQueueService queue;
  final GeorefLocalStore _store;
  final Future<void> Function()? _onEnqueuedForSync;

  Future<List<GeorefPendiente>> loadPendientes({
    required OperationalScope scope,
    bool fetchRemote = true,
  }) async {
    final snapshot = await _resolverPendientes(
      scope: scope,
      fetchRemote: fetchRemote,
      persistListCache: fetchRemote,
    );
    return snapshot.items;
  }

  /// KPI Home: misma lista filtrada que [loadPendientes] (vendedor + georef efectiva nula).
  Future<GeorefKpiSnapshot> loadPendientesKpi({
    required OperationalScope scope,
    bool fetchRemote = true,
  }) async {
    final cacheKey = GeorefLocalStore.pendingCountKeyFor(scope);
    if (!fetchRemote) {
      final cached = await GeorefLocalStore.loadPendingCountCache(scope);
      georefKpiLog(
        'vendedor=${scope.vendedorIdTrimmed} '
        'fecha=${scope.fechaOperativa} '
        'endpoint=$kpiEndpoint '
        'items_recibidos=n/a '
        'count_final=${cached ?? 'null'} '
        'cache_key=$cacheKey '
        'from_cache=true',
      );
      return GeorefKpiSnapshot(count: cached, fromCache: true);
    }

    try {
      final snapshot = await _resolverPendientes(
        scope: scope,
        fetchRemote: true,
        persistListCache: true,
      );
      final count = snapshot.items.length;
      await GeorefLocalStore.savePendingCountCache(scope, count);
      georefKpiLog(
        'vendedor=${scope.vendedorIdTrimmed} '
        'fecha=${scope.fechaOperativa} '
        'endpoint=$kpiEndpoint '
        'items_recibidos=${snapshot.rawRemoteCount} '
        'count_final=$count '
        'cache_key=$cacheKey '
        'from_cache=false',
      );
      return GeorefKpiSnapshot(count: count, fromCache: false);
    } catch (e) {
      fieldLog('Georef', 'KPI pendientes falló: $e');
      final cached = await GeorefLocalStore.loadPendingCountCache(scope);
      georefKpiLog(
        'vendedor=${scope.vendedorIdTrimmed} '
        'fecha=${scope.fechaOperativa} '
        'endpoint=$kpiEndpoint '
        'items_recibidos=error '
        'count_final=${cached ?? 'null'} '
        'cache_key=$cacheKey '
        'from_cache=${cached != null}',
      );
      return GeorefKpiSnapshot(count: cached, fromCache: cached != null);
    }
  }

  Future<_PendientesResueltos> _resolverPendientes({
    required OperationalScope scope,
    required bool fetchRemote,
    required bool persistListCache,
  }) async {
    final local = await _store.load(scope);
    if (!fetchRemote) {
      return _PendientesResueltos(
        items: filtrarGeorefPendientesEfectivos(local),
        rawRemoteCount: 0,
      );
    }

    final reach = await api.checkReachability();
    if (!reach.ok) {
      return _PendientesResueltos(
        items: filtrarGeorefPendientesEfectivos(local),
        rawRemoteCount: 0,
      );
    }

    final remote = await api.getGeorefPendientes(
      vendedor: scope.vendedorIdTrimmed,
    );
    final merged = GeorefLocalStore.mergeServidorConLocal(
      servidor: remote,
      local: local,
    );
    final filtrados = filtrarGeorefPendientesEfectivos(merged);
    if (persistListCache) {
      await _store.save(scope, filtrados);
    }
    return _PendientesResueltos(
      items: filtrados,
      rawRemoteCount: remote.length,
    );
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
      latOperacional: lat,
      lonOperacional: lon,
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
    await _store.save(scope, filtrarGeorefPendientesEfectivos(lista));

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

class _PendientesResueltos {
  const _PendientesResueltos({
    required this.items,
    required this.rawRemoteCount,
  });

  final List<GeorefPendiente> items;
  final int rawRemoteCount;
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
