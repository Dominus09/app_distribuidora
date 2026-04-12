import 'dart:math' as math;

import '../models/visita.dart';

/// Lectura de posición simulada para terreno (sin plugin de geolocalización).
class LocationSnapshot {
  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.gpsAvailable,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final bool gpsAvailable;
}

/// Servicio reutilizable: GPS mock + Haversine para validar distancia al cliente.
class LocationService {
  LocationService({
    /// Posición del vendedor simulada (grados decimales).
    double? mockUserLatitude,
    double? mockUserLongitude,
    this.mockGpsAvailable = true,
  })  : _mockUserLat = mockUserLatitude ?? _defaultUserLat,
        _mockUserLon = mockUserLongitude ?? _defaultUserLon;

  /// Quito — referencia estable para mocks.
  static const double _defaultUserLat = -0.22985;
  static const double _defaultUserLon = -78.52495;

  final double _mockUserLat;
  final double _mockUserLon;

  /// Si es false, simula GPS apagado o sin fix (mutable para pruebas en dashboard).
  bool mockGpsAvailable;

  /// Radio de la Tierra en metros (aprox.).
  static const double _earthRadiusM = 6371000;

  /// Simula si el dispositivo puede entregar coordenadas.
  Future<bool> isGpsAvailable() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return mockGpsAvailable;
  }

  /// Posición actual mock (misma para toda la sesión salvo que cambies el servicio).
  Future<LocationSnapshot> getCurrentPosition() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return LocationSnapshot(
      latitude: _mockUserLat,
      longitude: _mockUserLon,
      capturedAt: DateTime.now(),
      gpsAvailable: mockGpsAvailable,
    );
  }

  /// Distancia en metros entre dos puntos WGS84.
  double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dLat = p2 - p1;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1) *
            math.cos(p2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusM * c;
  }

  /// Distancia del snapshot al punto del cliente de la visita.
  double distanceToCliente(LocationSnapshot snap, Visita visita) {
    return distanceMeters(
      snap.latitude,
      snap.longitude,
      visita.latCliente,
      visita.lonCliente,
    );
  }
}
