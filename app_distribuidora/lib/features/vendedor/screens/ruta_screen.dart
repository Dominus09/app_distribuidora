import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../services/vendedor_service.dart';
import '../utils/maps_navigation.dart';
import '../widgets/visita_card.dart';
import 'ruta_mapa_screen.dart';
import 'visita_detalle_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _visitas = List<Visita>.from(widget.visitas);
  }

  @override
  void didUpdateWidget(covariant RutaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitas != widget.visitas) {
      _visitas = List<Visita>.from(widget.visitas);
    }
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
          content: Text('Ningún cliente tiene coordenadas para mostrar en el mapa.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta del día'),
        actions: [
          TextButton.icon(
            onPressed: () => _abrirMapa(),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ver mapa'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final loader = widget.reloadRuta;
          if (loader == null) return;
          try {
            final fresh = await loader();
            if (!context.mounted) return;
            setState(() => _visitas = List<Visita>.from(fresh));
            widget.onVisitasChanged(fresh);
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
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final visita = _visitas[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VisitaCard(
                        visita: visita,
                        attemptRemoteSave: widget.attemptRemoteSave,
                        locationService: widget.locationService,
                        vendedorService: widget.vendedorService,
                        syncService: widget.syncService,
                        apiService: widget.apiService,
                        onVisitadoPressed: (v) => _replaceAt(i, v),
                        onIncidenciaPressed: (v) => _replaceAt(i, v),
                        onMapFocus: () => _centrarClienteEnMapa(visita),
                        onTapDetalle: () async {
                          final updated = await Navigator.of(context).push<Visita>(
                            MaterialPageRoute<Visita>(
                              builder: (_) => VisitaDetalleScreen(
                                visita: visita,
                                attemptRemoteSave: widget.attemptRemoteSave,
                                locationService: widget.locationService,
                                vendedorService: widget.vendedorService,
                                syncService: widget.syncService,
                                apiService: widget.apiService,
                              ),
                            ),
                          );
                          if (updated != null && context.mounted) {
                            _replaceAt(i, updated);
                          }
                        },
                      ),
                    );
                  },
                  childCount: _visitas.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
