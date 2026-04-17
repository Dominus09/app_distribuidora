import 'package:geolocator/geolocator.dart';

import '../models/visita.dart';
import '../services/location_service.dart';
import '../services/ruta_map_geolocator.dart';
import 'maps_navigation.dart';

/// Posición del vendedor para calcular distancias en lista (Geolocator + respaldo [LocationService]).
Future<({double lat, double lon})?> obtenerPosicionUsuarioParaDistancias(
  LocationService locationService,
) async {
  final device = await RutaMapGeolocator.tryDeviceLatLng();
  if (device != null) {
    return (lat: device.latitude, lon: device.longitude);
  }
  final gpsOk = await locationService.isGpsAvailable();
  if (!gpsOk) return null;
  try {
    final snap = await locationService.getCurrentPosition();
    return (lat: snap.latitude, lon: snap.longitude);
  } on Object {
    return null;
  }
}

/// Distancia en metros; `null` si el cliente no tiene coordenadas válidas.
double? distanciaMetrosHaciaVisita(
  Visita visita,
  double latUsuario,
  double lonUsuario,
) {
  if (!visitaTieneCoordenadasCliente(visita.latCliente, visita.lonCliente)) {
    return null;
  }
  return Geolocator.distanceBetween(
    latUsuario,
    lonUsuario,
    visita.latCliente,
    visita.lonCliente,
  );
}

/// Texto tipo `120 m` o `1.4 km` (≥ 1000 m).
String formatearDistanciaLinea(double metros) {
  if (metros < 1000) return '${metros.round()} m';
  return '${(metros / 1000).toStringAsFixed(1)} km';
}
