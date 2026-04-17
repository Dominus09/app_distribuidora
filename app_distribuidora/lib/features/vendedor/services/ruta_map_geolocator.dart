import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Posición del dispositivo para el mapa de ruta (no sustituye el GPS mock de visitas).
class RutaMapGeolocator {
  /// Devuelve `null` si servicio apagado, sin permiso o error.
  static Future<LatLng?> tryDeviceLatLng() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      return LatLng(pos.latitude, pos.longitude);
    } on Exception {
      return null;
    }
  }
}
