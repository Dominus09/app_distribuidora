/// Timeouts HTTP (UI no debe esperar minutos).
abstract final class ApiTimeouts {
  /// Preflight / openapi.json antes de POST visita.
  static const reachability = Duration(seconds: 4);

  /// POST visita en segundo plano tras guardado local.
  static const postVisita = Duration(seconds: 5);

  /// Sincronización batch manual.
  static const postVisitaBatch = Duration(seconds: 12);

  static const getRuta = Duration(seconds: 30);

  static const postTelemetry = Duration(seconds: 12);
}
