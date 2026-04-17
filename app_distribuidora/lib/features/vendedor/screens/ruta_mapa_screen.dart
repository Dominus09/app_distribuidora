import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../services/location_service.dart';
import '../widgets/clientes_ruta_map.dart';

/// Pantalla dedicada al mapa de la ruta (lista en pantalla aparte).
class RutaMapaScreen extends StatefulWidget {
  const RutaMapaScreen({
    super.key,
    required this.visitas,
    required this.locationService,
    this.initialFocusedVisitaId,
  });

  final List<Visita> visitas;
  final LocationService locationService;
  final String? initialFocusedVisitaId;

  @override
  State<RutaMapaScreen> createState() => _RutaMapaScreenState();
}

class _RutaMapaScreenState extends State<RutaMapaScreen> {
  final GlobalKey<ClientesRutaMapState> _mapKey = GlobalKey<ClientesRutaMapState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de ruta'),
      ),
      body: SafeArea(
        child: ClientesRutaMap(
          key: _mapKey,
          visitas: widget.visitas,
          locationService: widget.locationService,
          focusedVisitaId: widget.initialFocusedVisitaId,
          expand: true,
          centerOnFirstPending: true,
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'ruta_map_first_pending',
            tooltip: 'Primer pendiente',
            onPressed: () => _mapKey.currentState?.centerOnFirstPending(),
            child: const Icon(Icons.flag_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'ruta_map_my_location',
            tooltip: 'Mi ubicación',
            onPressed: () => _mapKey.currentState?.centerOnUserLocation(),
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}
