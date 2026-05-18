import 'dart:async';

import '../../features/vendedor/services/location_service.dart';
import '../utils/field_log.dart';
import 'outbox_database.dart';
import 'telemetry_config.dart';

/// Seguimiento GPS continuo: tiempo (60–120 s) o movimiento > 100 m.
class GpsTrackingService {
  GpsTrackingService({
    required this.locationService,
    OutboxDatabase? database,
  }) : _db = database ?? OutboxDatabase.instance;

  final LocationService locationService;
  final OutboxDatabase _db;

  LocationSnapshot? _lastKnown;
  DateTime? _lastCaptureAt;
  Timer? _pollTimer;
  String? _vendedorId;
  bool _running = false;

  LocationSnapshot? get lastKnown => _lastKnown;

  void start(String vendedorId) {
    if (_running && _vendedorId == vendedorId) return;
    stop();
    _vendedorId = vendedorId;
    _running = true;
    fieldLog('GPS-Track', 'inicio vendedor=$vendedorId');
    _pollTimer = Timer.periodic(
      TelemetryConfig.gpsPollMinInterval,
      (_) => unawaited(_tick()),
    );
    unawaited(_tick());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _running = false;
    _vendedorId = null;
    fieldLog('GPS-Track', 'detenido');
  }

  Future<void> _tick() async {
    final vid = _vendedorId;
    if (vid == null || !_running) return;

    final now = DateTime.now();
    final elapsed = _lastCaptureAt == null
        ? TelemetryConfig.gpsPollMaxInterval
        : now.difference(_lastCaptureAt!);

    if (_lastCaptureAt != null &&
        elapsed < TelemetryConfig.gpsPollMinInterval) {
      return;
    }

    try {
      final available = await locationService.isGpsAvailable();
      if (!available) {
        fieldLog('GPS-Track', 'GPS no disponible');
        return;
      }

      final snap = await locationService.getCurrentPosition();
      _lastKnown = snap;

      var shouldStore = _lastCaptureAt == null ||
          elapsed >= TelemetryConfig.gpsPollMaxInterval;

      if (!shouldStore && _lastKnown != null) {
        final prev = await _db.lastGpsPoint(vid);
        if (prev != null) {
          final moved = locationService.distanceMeters(
            prev.latitude,
            prev.longitude,
            snap.latitude,
            snap.longitude,
          );
          if (moved >= TelemetryConfig.gpsMovementThresholdMeters) {
            shouldStore = true;
            fieldLog('GPS-Track', 'movimiento ${moved.toStringAsFixed(0)}m');
          }
        } else {
          shouldStore = true;
        }
      }

      if (shouldStore) {
        await _db.insertGpsPoint(
          vendedorId: vid,
          latitude: snap.latitude,
          longitude: snap.longitude,
          capturedAt: snap.capturedAt,
          accuracyMeters: snap.accuracyMeters,
        );
        _lastCaptureAt = now;
        await _db.setMeta(
          'last_gps_lat',
          snap.latitude.toString(),
        );
        await _db.setMeta(
          'last_gps_lon',
          snap.longitude.toString(),
        );
        await _db.setMeta(
          'last_gps_at',
          snap.capturedAt.toUtc().toIso8601String(),
        );
        fieldLog(
          'GPS-Track',
          'punto guardado (${snap.latitude.toStringAsFixed(5)}, '
          '${snap.longitude.toStringAsFixed(5)})',
        );
      }
    } catch (e) {
      fieldLog('GPS-Track', 'error tick: $e');
    }
  }

  Future<Map<String, dynamic>?> gpsPayloadForHeartbeat() async {
    final snap = _lastKnown;
    if (snap != null) {
      return {
        'lat': snap.latitude,
        'lon': snap.longitude,
        'accuracy_m': snap.accuracyMeters,
        'captured_at': snap.capturedAt.toUtc().toIso8601String(),
      };
    }
    final lat = await _db.getMeta('last_gps_lat');
    final lon = await _db.getMeta('last_gps_lon');
    final at = await _db.getMeta('last_gps_at');
    if (lat == null || lon == null) return null;
    return {
      'lat': double.tryParse(lat),
      'lon': double.tryParse(lon),
      'captured_at': at,
    };
  }
}
