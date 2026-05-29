import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/session/operational_scope.dart';
import '../../../core/network/api_timeouts.dart';
import '../../../core/ux/offline_ux.dart';
import '../../../core/utils/field_log.dart';
import '../models/georef_pendiente.dart';
import '../services/georef_service.dart';
import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../utils/maps_navigation.dart';
import '../utils/ruta_distancia_tarjeta.dart';
import '../widgets/terreno_sync_banner.dart';
import '../widgets/visita_card.dart';
import 'ruta_mapa_screen.dart';
import 'visita_detalle_screen.dart';

/// Cómo ordenar clientes dentro de pendientes y de completados.
enum _ModoOrdenLista { ordenRuta, distancia }

/// Lista operativa del día con base de salida y tarjetas por cliente.
class RutaScreen extends StatefulWidget {
  const RutaScreen({
    super.key,
    required this.visitas,
    required this.onVisitasChanged,
    required this.attemptRemoteSave,
    required this.interfaceConnectivityDetected,
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
    required this.apiService,
    this.reloadRuta,
    this.persistVisitaWriteAhead,
    this.operationalScope,
    this.georefService,
  });

  final List<Visita> visitas;
  final ValueChanged<List<Visita>> onVisitasChanged;
  final OperationalScope? operationalScope;
  final GeorefService? georefService;
  /// Persiste en disco + outbox antes de sync HTTP (write-ahead).
  final Future<List<Visita>> Function(
    Visita updated,
    List<Visita> current,
  )? persistVisitaWriteAhead;
  final bool attemptRemoteSave;
  /// `connectivity_plus` (wifi/móvil/ethernet…) — puede estar en fallo en PDA/industrial.
  final bool interfaceConnectivityDetected;
  final LocationService locationService;
  final VendedorService vendedorService;
  final SyncService syncService;
  final ApiService apiService;

  /// Recarga la ruta desde el servidor (pull-to-refresh).
  final Future<List<Visita>> Function()? reloadRuta;

  @override
  State<RutaScreen> createState() => _RutaScreenState();
}

class _RutaScreenState extends State<RutaScreen> {
  late List<Visita> _visitas;
  double? _userLat;
  double? _userLon;
  _ModoOrdenLista _modoOrden = _ModoOrdenLista.ordenRuta;

  /// API si el Home/diagnóstico lo permiten (incluye bypass si el servidor responde).
  bool get _puedeIntentarApi => widget.attemptRemoteSave;

  @override
  void initState() {
    super.initState();
    _visitas = List<Visita>.from(widget.visitas);
    unawaited(_actualizarUbicacionUsuario());
  }

  @override
  void didUpdateWidget(covariant RutaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitas != widget.visitas) {
      _visitas = List<Visita>.from(widget.visitas);
    }
  }

  Future<void> _actualizarUbicacionUsuario() async {
    final pos = await obtenerPosicionUsuarioParaDistancias(
      widget.locationService,
    );
    if (!mounted) return;
    setState(() {
      if (pos == null) {
        _userLat = null;
        _userLon = null;
      } else {
        _userLat = pos.lat;
        _userLon = pos.lon;
      }
    });
  }

  String? _textoDistancia(Visita visita) {
    final lat = _userLat;
    final lon = _userLon;
    if (lat == null || lon == null) return null;
    final m = distanciaMetrosHaciaVisita(visita, lat, lon);
    if (m == null) return null;
    return formatearDistanciaLinea(m);
  }

  /// Orden dentro de un grupo: por [orden] de ruta o por distancia (si hay GPS).
  void _ordenarGrupo(List<Visita> grupo, {required bool porDistancia}) {
    if (porDistancia) {
      final lat = _userLat;
      final lon = _userLon;
      if (lat != null && lon != null) {
        grupo.sort((a, b) {
          final da = distanciaMetrosHaciaVisita(a, lat, lon);
          final db = distanciaMetrosHaciaVisita(b, lat, lon);
          if (da == null && db == null) return a.orden.compareTo(b.orden);
          if (da == null) return 1;
          if (db == null) return -1;
          final cmp = da.compareTo(db);
          if (cmp != 0) return cmp;
          return a.orden.compareTo(b.orden);
        });
        return;
      }
    }
    grupo.sort((a, b) => a.orden.compareTo(b.orden));
  }

  Widget _selectorOrden(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ordenar por',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<_ModoOrdenLista>(
            segments: const [
              ButtonSegment<_ModoOrdenLista>(
                value: _ModoOrdenLista.ordenRuta,
                label: Text('Orden de ruta'),
                icon: Icon(Icons.route, size: 18),
              ),
              ButtonSegment<_ModoOrdenLista>(
                value: _ModoOrdenLista.distancia,
                label: Text('Distancia'),
                icon: Icon(Icons.straighten, size: 18),
              ),
            ],
            selected: {_modoOrden},
            onSelectionChanged: (next) {
              setState(() => _modoOrden = next.first);
            },
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _emit(List<Visita> next) {
    setState(() => _visitas = next);
    widget.onVisitasChanged(next);
  }

  void _reemplazarVisitaPorId(Visita actualizada) {
    unawaited(_guardarVisitaLocalPrimero(actualizada));
  }

  /// 1) UI inmediata  2) disco + outbox  3) mensaje éxito  4) HTTP en background.
  Future<void> _guardarVisitaLocalPrimero(Visita actualizada) async {
    final idx = _visitas.indexWhere((v) => v.id == actualizada.id);
    if (idx < 0) return;

    var next = [..._visitas];
    next[idx] = actualizada;
    _emit(next);

    final persist = widget.persistVisitaWriteAhead;
    if (persist != null) {
      try {
        next = await persist(actualizada, next);
        if (mounted) _emit(next);
      } catch (e) {
        fieldLogImportant('Ruta', 'persist local: $e');
      }
    }

    if (!mounted) return;
    final omitirHttp = OfflineUx.debeOmitirHttp(
      interfaceConnectivityDetected: widget.interfaceConnectivityDetected,
      attemptRemoteSave: widget.attemptRemoteSave,
      forceOffline: false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          OfflineUx.mensajeTrasGuardarLocal(omitirHttp: omitirHttp),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    final debeSync = actualizada.syncStatus == SyncStatus.pendingSync ||
        actualizada.syncStatus == SyncStatus.syncError;
    if (debeSync && widget.attemptRemoteSave) {
      unawaited(_sincronizarEnSegundoPlano(actualizada.id));
    }
  }

  Future<void> _capturarGeorefDesdeIncidencia({
    required Visita visita,
    required double lat,
    required double lon,
    String? observacion,
  }) async {
    final scope = widget.operationalScope;
    final svc = widget.georefService;
    if (scope == null || svc == null) return;
    final omitirHttp = OfflineUx.debeOmitirHttp(
      interfaceConnectivityDetected: widget.interfaceConnectivityDetected,
      attemptRemoteSave: widget.attemptRemoteSave,
      forceOffline: false,
    );
    await svc.capturarUbicacion(
      scope: scope,
      item: GeorefPendiente.fromVisita(visita),
      lat: lat,
      lon: lon,
      observacion: observacion,
      visitasActuales: _visitas,
      omitirHttp: omitirHttp,
    );
  }

  Future<void> _sincronizarEnSegundoPlano(String visitaId) async {
    if (OfflineUx.debeOmitirHttp(
      interfaceConnectivityDetected: widget.interfaceConnectivityDetected,
      attemptRemoteSave: widget.attemptRemoteSave,
      forceOffline: false,
    )) {
      return;
    }

    final antesIdx = _visitas.indexWhere((v) => v.id == visitaId);
    final estadoAntes = antesIdx >= 0
        ? _visitas[antesIdx].syncStatus
        : SyncStatus.pendingSync;

    final reach = await widget.apiService.checkReachability(
      timeout: ApiTimeouts.reachability,
    );
    fieldLog('Ruta sync bg', reach.logLine);
    if (!reach.ok) return;

    final syncTry = await widget.syncService.trySyncVisitaAfterLocalSave(
      List<Visita>.from(_visitas),
      visitaId,
      widget.apiService,
    );
    if (!mounted) return;
    _emit(syncTry.visitas);

    final despuesIdx = syncTry.visitas.indexWhere((v) => v.id == visitaId);
    final estadoDespues = despuesIdx >= 0
        ? syncTry.visitas[despuesIdx].syncStatus
        : estadoAntes;
    final sincronizado = estadoAntes != SyncStatus.synced &&
        estadoDespues == SyncStatus.synced;

    if (sincronizado && syncTry.error == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(OfflineUx.enviadoAlServidor),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final err = syncTry.error;
    if (err != null &&
        mounted &&
        OfflineUx.debeMostrarErrorAlUsuario(err.reason)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.userMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _hayCoordenadasEnRuta() {
    for (final v in _visitas) {
      if (visitaTieneCoordenadasCliente(v.latCliente, v.lonCliente)) {
        return true;
      }
    }
    return false;
  }

  void _abrirMapa({String? focusVisitaId}) {
    if (_visitas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay clientes en la ruta.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_hayCoordenadasEnRuta()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ningún cliente tiene coordenadas para mostrar en el mapa.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RutaMapaScreen(
          visitas: _visitas,
          locationService: widget.locationService,
          initialFocusedVisitaId: focusVisitaId,
        ),
      ),
    );
  }

  void _centrarClienteEnMapa(Visita v) {
    if (!visitaTieneCoordenadasCliente(v.latCliente, v.lonCliente)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este cliente no tiene coordenadas en el mapa.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _abrirMapa(focusVisitaId: v.id);
  }

  Widget _tituloSeccion(BuildContext context, String titulo) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Text(
        titulo,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  List<Widget> _sliversListaOrdenada(BuildContext context) {
    final porDistancia = _modoOrden == _ModoOrdenLista.distancia;
    final pendientes = _visitas
        .where((v) => v.estado == VisitaEstado.pendiente)
        .toList();
    final completados = _visitas
        .where((v) => v.estado != VisitaEstado.pendiente)
        .toList();
    _ordenarGrupo(pendientes, porDistancia: porDistancia);
    _ordenarGrupo(completados, porDistancia: porDistancia);

    Widget tarjeta(Visita visita) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: VisitaCard(
          visita: visita,
          attemptRemoteSave: _puedeIntentarApi,
          locationService: widget.locationService,
          vendedorService: widget.vendedorService,
          syncService: widget.syncService,
          apiService: widget.apiService,
          interfaceConnectivityDetected: widget.interfaceConnectivityDetected,
          onVisitadoPressed: _reemplazarVisitaPorId,
          onIncidenciaPressed: _reemplazarVisitaPorId,
          onGeorefDesdeIncidencia: _capturarGeorefDesdeIncidencia,
          onMapFocus: () => _centrarClienteEnMapa(visita),
          distanciaEtiqueta: _textoDistancia(visita),
          onTapDetalle: () async {
            final updated = await Navigator.of(context).push<Visita>(
              MaterialPageRoute<Visita>(
                builder: (_) => VisitaDetalleScreen(
                  visita: visita,
                  attemptRemoteSave: _puedeIntentarApi,
                  interfaceConnectivityDetected:
                      widget.interfaceConnectivityDetected,
                  locationService: widget.locationService,
                  vendedorService: widget.vendedorService,
                  syncService: widget.syncService,
                  apiService: widget.apiService,
                  onGeorefDesdeIncidencia: _capturarGeorefDesdeIncidencia,
                ),
              ),
            );
            if (updated != null && context.mounted) {
              _reemplazarVisitaPorId(updated);
            }
          },
        ),
      );
    }

    final out = <Widget>[SliverToBoxAdapter(child: _selectorOrden(context))];

    if (pendientes.isNotEmpty) {
      out.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _tituloSeccion(context, 'Pendientes'),
          ),
        ),
      );
      out.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, completados.isEmpty ? 24 : 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => tarjeta(pendientes[i]),
              childCount: pendientes.length,
            ),
          ),
        ),
      );
    }

    if (completados.isNotEmpty) {
      out.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              pendientes.isNotEmpty ? 8 : 0,
              16,
              0,
            ),
            child: _tituloSeccion(context, 'Completados'),
          ),
        ),
      );
      out.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => tarjeta(completados[i]),
              childCount: completados.length,
            ),
          ),
        ),
      );
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo_small.png',
              height: 30,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Ruta del día',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _abrirMapa(),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ver mapa'),
          ),
        ],
      ),
      body: Column(
        children: [
          TerrenoSyncBanner(
            canSyncWithServer: widget.attemptRemoteSave,
            interfaceConnectivityDetected:
                widget.interfaceConnectivityDetected,
            anyItemSyncing:
                _visitas.any((v) => v.syncStatus == SyncStatus.syncing),
            batchSyncing: false,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                final loader = widget.reloadRuta;
                if (loader == null) return;
                try {
                  final fresh = await loader();
                  if (!context.mounted) return;
                  setState(() => _visitas = List<Visita>.from(fresh));
                  widget.onVisitasChanged(fresh);
                  unawaited(_actualizarUbicacionUsuario());
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No se pudo actualizar la ruta. Reintenta.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warehouse_outlined,
                                size: 32,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  'Base de salida',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ..._sliversListaOrdenada(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
