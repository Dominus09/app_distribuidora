import 'package:flutter/material.dart';

import '../models/visita.dart';
import '../services/location_service.dart';
import '../widgets/clientes_ruta_map.dart';

/// Pantalla dedicada al mapa de la ruta (lista en pantalla aparte).
class RutaMapaScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de ruta'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClientesRutaMap(
                  visitas: visitas,
                  locationService: locationService,
                  focusedVisitaId: initialFocusedVisitaId,
                  expand: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
