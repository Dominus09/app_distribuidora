import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/chofer_mock_repository.dart';

/// Mapa mock: solo pendientes + posición simulada del chofer.
class ChoferMapaRutaMock extends StatelessWidget {
  const ChoferMapaRutaMock({super.key});

  static const LatLng _centro = LatLng(-43.116, -73.616);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChoferMockRepository.instance,
      builder: (context, _) {
        final repo = ChoferMockRepository.instance;
        final pend = repo.pendientesOrdenRuta();
        final markers = <Marker>{};
        for (final c in pend) {
          markers.add(
            Marker(
              markerId: MarkerId(c.id),
              position: LatLng(c.lat, c.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ),
              infoWindow: InfoWindow(title: c.nombreFantasia),
            ),
          );
        }
        markers.add(
          Marker(
            markerId: const MarkerId('chofer_sim'),
            position: const LatLng(
              ChoferMockRepository.simLat,
              ChoferMockRepository.simLng,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: 'Tu posición (simulada)'),
          ),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _centro,
                zoom: 12.2,
              ),
              markers: markers,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
        );
      },
    );
  }
}
