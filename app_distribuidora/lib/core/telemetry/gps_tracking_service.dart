import 'dart:async';

import '../../features/vendedor/services/location_service.dart';
import '../utils/field_log.dart';
import 'outbox_database.dart';
import 'outbox_observability.dart';
import 'telemetry_config.dart';
import 'timer_registry.dart';

/// Seguimiento GPS: throttling, sin solapar ticks, precisión media.
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
  String? _fechaOperativa;
  bool _running = false;
  bool _tickInProgress = false;

  LocationSnapshot? get lastKnown => _lastKnown;

  void start(String vendedorId, {String? fechaOperativa}) {
    if (_running && _vendedorId == vendedorId) {
      fieldLogImportant(
        'GPS-Track',
        'start ignorado: ya activo v=$vendedorId',
      );
      _fechaOperativa = fechaOperativa;
      return;
    }
    stop();
    _vendedorId = vendedorId;
    _fechaOperativa = fechaOperativa;
    _lastKnown = null;
    _lastCaptureAt = null;
    _running = true;
    fieldLog('GPS-Track', 'inicio v=$vendedorId', force: true);
    _pollTimer = Timer.periodic(
      TelemetryConfig.gpsPollMinInterval,
      (_) => unawaited(_tick()),
    );
    TimerRegistry.instance.register(
      name: 'gps_poll',
      owner: 'GpsTrackingService',
      detail: 'v=$vendedorId',
    );
    Future<void>.delayed(Duration.zero, _tick);
  }

  void setFechaOperativa(String? fechaOperativa) {
    _fechaOperativa = fechaOperativa;
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    TimerRegistry.instance.unregister('gps_poll');
    _running = false;
    _tickInProgress = false;
    _vendedorId = null;
    _fechaOperativa = null;
    _lastKnown = null;
  }

  Future<void> _tick() async {
    if (_tickInProgress) return;
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

    _tickInProgress = true;
    try {
      final snap = await locationService.getTrackingPosition();
      _lastKnown = snap;

      var shouldStore = _lastCaptureAt == null ||
          elapsed >= TelemetryConfig.gpsPollMaxInterval;

      if (!shouldStore) {
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
          fechaOperativa: _fechaOperativa,
        );
        _lastCaptureAt = now;
        await _db.setMeta(
          vendedorId: vid,
          key: 'last_gps_lat',
          value: snap.latitude.toString(),
        );
        await _db.setMeta(
          vendedorId: vid,
          key: 'last_gps_lon',
          value: snap.longitude.toString(),
        );
        await _db.setMeta(
          vendedorId: vid,
          key: 'last_gps_at',
          value: snap.capturedAt.toUtc().toIso8601String(),
        );
        final unuploaded = await _db.unuploadedGpsPoints(
          vendedorId: vid,
          limit: 500,
        );
        OutboxObservability.instance.logGpsPointStored(
          vendedorId: vid,
          totalUnuploaded: unuploaded.length,
        );
        fieldLog('GPS-Track', 'punto v=$vid', throttle: true);
      }
    } catch (e) {
      fieldLogImportant('GPS-Track', 'error v=$vid: $e');
    } finally {
      _tickInProgress = false;
    }
  }

  Future<Map<String, dynamic>?> gpsPayloadForHeartbeat(String vendedorId) async {
    final snap = _lastKnown;
    if (snap != null) {
      return {
        'lat': snap.latitude,
        'lon': snap.longitude,
        'accuracy_m': snap.accuracyMeters,
        'captured_at': snap.capturedAt.toUtc().toIso8601String(),
      };
    }
    final lat = await _db.getMeta(vendedorId: vendedorId, key: 'last_gps_lat');
    final lon = await _db.getMeta(vendedorId: vendedorId, key: 'last_gps_lon');
    final at = await _db.getMeta(vendedorId: vendedorId, key: 'last_gps_at');
    if (lat == null || lon == null) return null;
    return {
      'lat': double.tryParse(lat),
      'lon': double.tryParse(lon),
      'captured_at': at,
    };
  }
}
