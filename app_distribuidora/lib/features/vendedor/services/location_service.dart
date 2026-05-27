import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../../../core/config/terreno_config.dart';
import '../../../core/telemetry/telemetry_config.dart';
import '../../../core/utils/field_log.dart';
import '../models/visita.dart';

/// Lectura de posición para validación de visitas y distancias.
class LocationSnapshot {
  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.gpsAvailable,
    this.accuracyMeters,
    this.positionTimestamp,
    this.isMock = false,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final bool gpsAvailable;

  /// Radio de incertidumbre reportado por el SO (metros), si está disponible.
  final double? accuracyMeters;

  /// Marca de tiempo del fix según el proveedor (Android/iOS).
  final DateTime? positionTimestamp;

  /// `true` solo en modo simulación (tests / demos).
  final bool isMock;
}

/// GPS real con [Geolocator] o modo mock opcional (pruebas automatizadas).
class LocationService {
  LocationService({
    this.useMockGps = false,
    double? mockUserLatitude,
    double? mockUserLongitude,
    this.mockGpsAvailable = true,
  })  : _mockUserLat = mockUserLatitude ?? _defaultUserLat,
        _mockUserLon = mockUserLongitude ?? _defaultUserLon;

  /// Si es `true`, usa coordenadas fijas (no pide permisos ni hardware).
  final bool useMockGps;

  /// Quito — referencia estable para mocks.
  static const double _defaultUserLat = -0.22985;
  static const double _defaultUserLon = -78.52495;

  final double _mockUserLat;
  final double _mockUserLon;

  /// Si es false en mock, simula GPS apagado o sin fix.
  bool mockGpsAvailable;

  static const double _earthRadiusM = 6371000;

  Future<bool> isGpsAvailable() async {
    if (useMockGps) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return mockGpsAvailable;
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      fieldLog('GPS', 'isLocationServiceEnabled=false');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      fieldLog('GPS', 'permiso denegado: $permission');
      return false;
    }
    return true;
  }

  /// Fix actual: [LocationAccuracy.best], sin reutilizar lecturas obsoletas si se puede evitar.
  Future<LocationSnapshot> getCurrentPosition() async {
    if (useMockGps) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final now = DateTime.now();
      return LocationSnapshot(
        latitude: _mockUserLat,
        longitude: _mockUserLon,
        capturedAt: now,
        gpsAvailable: mockGpsAvailable,
        accuracyMeters: 5,
        positionTimestamp: now,
        isMock: true,
      );
    }

    LocationSnapshot? last;
    for (var intento = 0;
        intento <= TerrenoConfig.gpsFreshRetries;
        intento++) {
      final snap = await _leerPosicionReal();
      last = snap;
      final ts = snap.positionTimestamp;
      final age = ts != null
          ? snap.capturedAt.difference(ts).inSeconds.abs()
          : 0;
      fieldLog(
        'GPS',
        'fix user=(${snap.latitude.toStringAsFixed(6)},${snap.longitude.toStringAsFixed(6)}) '
        'accuracy=${snap.accuracyMeters?.toStringAsFixed(1) ?? "?"}m age=${age}s intento=$intento',
      );
      if (age <= TerrenoConfig.maxPositionAgeSeconds) {
        return snap;
      }
      if (intento < TerrenoConfig.gpsFreshRetries) {
        fieldLog('GPS', 'fix demasiado viejo (${age}s), reintentando…');
      }
    }
    fieldLog(
      'GPS',
      'ADVERTENCIA: se usa último fix posiblemente cacheado (>${TerrenoConfig.maxPositionAgeSeconds}s).',
    );
    if (last != null) return last;
    throw TimeoutException('No se obtuvo posición GPS');
  }

  /// Última posición conocida del SO (rápida, sin encender GPS de alto consumo).
  Future<LocationSnapshot?> tryGetLastKnownPosition({
    int maxAgeSeconds = 120,
  }) async {
    if (useMockGps) {
      return getCurrentPosition();
    }
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      final age = DateTime.now().difference(pos.timestamp).inSeconds.abs();
      if (age > maxAgeSeconds) return null;
      return LocationSnapshot(
        latitude: pos.latitude,
        longitude: pos.longitude,
        capturedAt: DateTime.now(),
        gpsAvailable: true,
        accuracyMeters: pos.accuracy.isFinite ? pos.accuracy : null,
        positionTimestamp: pos.timestamp,
        isMock: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// GPS de telemetría / mapa lista: precisión media, timeout corto.
  Future<LocationSnapshot> getTrackingPosition() async {
    if (useMockGps) {
      return getCurrentPosition();
    }
    final cached = await tryGetLastKnownPosition(maxAgeSeconds: 90);
    if (cached != null) return cached;

    final now = DateTime.now();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 0,
        timeLimit: TelemetryConfig.trackingGpsTimeout,
      ),
    );
    return LocationSnapshot(
      latitude: pos.latitude,
      longitude: pos.longitude,
      capturedAt: now,
      gpsAvailable: true,
      accuracyMeters: pos.accuracy.isFinite ? pos.accuracy : null,
      positionTimestamp: pos.timestamp,
      isMock: false,
    );
  }

  Future<LocationSnapshot> _leerPosicionReal() async {
    final now = DateTime.now();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        timeLimit: TerrenoConfig.gpsFixTimeout,
      ),
    );
    return LocationSnapshot(
      latitude: pos.latitude,
      longitude: pos.longitude,
      capturedAt: now,
      gpsAvailable: true,
      accuracyMeters: pos.accuracy.isFinite ? pos.accuracy : null,
      positionTimestamp: pos.timestamp,
      isMock: false,
    );
  }

  /// Distancia en metros entre dos puntos WGS84 (Haversine).
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

  double distanceToCliente(LocationSnapshot snap, Visita visita) {
    return distanceMeters(
      snap.latitude,
      snap.longitude,
      visita.latCliente,
      visita.lonCliente,
    );
  }

  /// `true` si la precisión declarada es aceptable para validación estricta en línea.
  bool accuracyAcceptableForStrictValidation(LocationSnapshot snap) {
    final a = snap.accuracyMeters;
    if (a == null || !a.isFinite) {
      return true;
    }
    return a <= TerrenoConfig.maxAcceptableAccuracyMeters;
  }
}
