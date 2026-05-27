/// Intervalos y umbrales de telemetría (balance rendimiento / batería / terreno).
abstract final class TelemetryConfig {
  /// Heartbeat automático mientras el vendedor está en ruta.
  static const Duration heartbeatInterval = Duration(seconds: 60);

  /// Un solo timer coordinador (evita 3+ timers paralelos).
  static const Duration coordinatorTickInterval = Duration(seconds: 30);

  /// Intervalo mínimo entre lecturas GPS de seguimiento (2 min).
  static const Duration gpsPollMinInterval = Duration(minutes: 2);

  /// Intervalo máximo entre lecturas GPS sin movimiento relevante.
  static const Duration gpsPollMaxInterval = Duration(minutes: 2);

  /// Nuevo punto GPS si el desplazamiento supera este umbral (metros).
  static const double gpsMovementThresholdMeters = 100;

  /// Cola offline: flush periódico (antes 30 s → menos agresivo).
  static const Duration outboxFlushInterval = Duration(seconds: 90);

  /// Máximo de ítems por pasada de flush (evita ráfagas HTTP).
  static const int maxOutboxFlushPerTick = 6;

  /// UI tarjeta operacional en Home.
  static const Duration operacionalUiRefreshInterval = Duration(seconds: 30);

  static const Duration operacionalDebounce = Duration(seconds: 2);

  static const Duration retryBaseDelay = Duration(seconds: 15);
  static const Duration retryMaxDelay = Duration(minutes: 10);
  static const int maxRetryAttempts = 12;

  static const Duration periodicVisitaSyncInterval = Duration(minutes: 3);
  static const Duration telemetryHttpTimeout = Duration(seconds: 20);

  /// GPS de seguimiento: precisión reducida vs visitas (menos batería).
  static const Duration trackingGpsTimeout = Duration(seconds: 18);
}
