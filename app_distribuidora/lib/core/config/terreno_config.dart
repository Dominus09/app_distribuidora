/// Parámetros operativos de terreno (GPS, radio de visita).
/// Ajustar aquí sin tocar lógica repartida en widgets.
abstract final class TerrenoConfig {
  /// Distancia máxima (metros) usuario → cliente para marcar “visitado” con GPS fiable.
  static const double maxDistanceVisitadoMetros = 500;

  /// Si la lectura GPS es más imprecisa que esto (metros), no se valida como “validado” en línea
  /// (se deja `pendienteValidacion` o se informa al usuario).
  static const double maxAcceptableAccuracyMeters = 75;

  /// Rechazar lecturas cuya marca de tiempo del fix sea más vieja que esto (segundos).
  static const int maxPositionAgeSeconds = 45;

  /// Tiempo máximo de espera a un fix GPS antes de fallar (en línea).
  static const Duration gpsFixTimeout = Duration(seconds: 35);

  /// Sin red: priorizar last-known y timeout corto (no bloquear guardado).
  static const Duration gpsFixTimeoutFast = Duration(seconds: 10);

  /// Reintento único si el primer fix llegó demasiado viejo.
  static const int gpsFreshRetries = 1;
}
