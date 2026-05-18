/// Intervalos y umbrales de telemetría operacional (heartbeat, GPS, cola).
abstract final class TelemetryConfig {
  /// Heartbeat automático mientras el vendedor está en ruta.
  static const Duration heartbeatInterval = Duration(seconds: 60);

  /// Intervalo mínimo entre lecturas GPS de seguimiento.
  static const Duration gpsPollMinInterval = Duration(seconds: 60);

  /// Intervalo máximo entre lecturas GPS aunque no haya movimiento.
  static const Duration gpsPollMaxInterval = Duration(seconds: 120);

  /// Nuevo punto GPS si el desplazamiento supera este umbral (metros).
  static const double gpsMovementThresholdMeters = 100;

  /// Reintento de cola offline: base para backoff exponencial.
  static const Duration retryBaseDelay = Duration(seconds: 15);

  /// Tope de espera entre reintentos.
  static const Duration retryMaxDelay = Duration(minutes: 10);

  /// Máximo de reintentos antes de marcar error persistente.
  static const int maxRetryAttempts = 12;

  /// Sincronización periódica de visitas pendientes (además de eventos).
  static const Duration periodicVisitaSyncInterval = Duration(minutes: 3);

  /// Timeout HTTP telemetría.
  static const Duration telemetryHttpTimeout = Duration(seconds: 20);
}
