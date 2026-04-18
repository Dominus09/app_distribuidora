import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

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
    required this.locationService,
    required this.vendedorService,
    required this.syncService,
    required this.apiService,
    this.reloadRuta,
  });

  final List<Visita> visitas;
  final ValueChanged<List<Visita>> onVisitasChanged;
  final bool attemptRemoteSave;
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

  /// Interfaz con datos (Wi‑Fi / datos); la pantalla de ruta escucha aparte del Home.
  bool _interfaceOk = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static bool _hayRedDatos(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    const conDatos = <ConnectivityResult>{
      ConnectivityResult.wifi,
      ConnectivityResult.mobile,
      ConnectivityResult.ethernet,
      ConnectivityResult.vpn,
      ConnectivityResult.other,
      ConnectivityResult.satellite,
    };
    return results.any(conDatos.contains);
  }

  /// API solo si el padre lo permite y hay interfaz de red activa.
  bool get _puedeIntentarApi => widget.attemptRemoteSave && _interfaceOk;

  @override
  void initState() {
    super.initState();
    _visitas = List<Visita>.from(widget.visitas);
    unawaited(_actualizarUbicacionUsuario());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final ok = _hayRedDatos(results);
      if (mounted) setState(() => _interfaceOk = ok);
    });
    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      setState(() => _interfaceOk = _hayRedDatos(results));
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RutaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitas != widget.visitas) {
      _visitas = List<Visita>.from(widget.visitas);
      unawaited(_actualizarUbicacionUsuario());
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

  void _replaceAt(int index, Visita v) {
    final next = [..._visitas];
    next[index] = v;
    _emit(next);
  }

  void _reemplazarVisitaPorId(Visita actualizada) {
    final idx = _visitas.indexWhere((v) => v.id == actualizada.id);
    if (idx < 0) return;
    _replaceAt(idx, actualizada);

    final debeIntentarRemoto = actualizada.syncStatus == SyncStatus.pendingSync ||
        actualizada.syncStatus == SyncStatus.syncError;
    if (debeIntentarRemoto) {
      unawaited(_intentarSincronizarTrasGuardado(actualizada.id));
    }
  }

  Future<void> _intentarSincronizarTrasGuardado(String visitaId) async {
    if (!widget.attemptRemoteSave) {
      return;
    }
    if (!_interfaceOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión. El registro quedó guardado; se sincronizará cuando haya red.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ping = await widget.apiService.pingReachable();
    if (!mounted) return;
    if (!ping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay conexión con el servidor. El registro quedó guardado; '
            'usa sincronización forzada más tarde.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final base = List<Visita>.from(_visitas);
    final siguiente = await widget.syncService.trySyncVisitaAfterLocalSave(
      base,
      visitaId,
      widget.apiService,
    );
    if (!mounted) return;
    _emit(siguiente);

    Visita? post;
    for (final v in siguiente) {
      if (v.id == visitaId) {
        post = v;
        break;
      }
    }
    if (post != null && post.syncStatus == SyncStatus.syncError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo sincronizar el registro. Quedó en cola para reintentar.',
          ),
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
          onVisitadoPressed: _reemplazarVisitaPorId,
          onIncidenciaPressed: _reemplazarVisitaPorId,
          onMapFocus: () => _centrarClienteEnMapa(visita),
          distanciaEtiqueta: _textoDistancia(visita),
          onTapDetalle: () async {
            final updated = await Navigator.of(context).push<Visita>(
              MaterialPageRoute<Visita>(
                builder: (_) => VisitaDetalleScreen(
                  visita: visita,
                  attemptRemoteSave: _puedeIntentarApi,
                  locationService: widget.locationService,
                  vendedorService: widget.vendedorService,
                  syncService: widget.syncService,
                  apiService: widget.apiService,
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
    final bannerConnected = widget.attemptRemoteSave && _interfaceOk;

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
            interfaceConnected: bannerConnected,
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
