import 'package:flutter/foundation.dart';

/// Métricas de arranque Home (ms).
class HomePerfMetrics {
  HomePerfMetrics({
    this.hydrateMs = 0,
    this.recoveryMs = 0,
    this.loadRouteMs = 0,
    this.georefKpiMs = 0,
    this.sqliteMs = 0,
    this.homeTotalMs = 0,
  });

  int hydrateMs;
  int recoveryMs;
  int loadRouteMs;
  int georefKpiMs;
  int sqliteMs;
  int homeTotalMs;

  void logSummary() {
    if (!kDebugMode) return;
    debugPrint(
      '[PERF] '
      'recovery_ms=$recoveryMs '
      'load_route_ms=$loadRouteMs '
      'georef_kpi_ms=$georefKpiMs '
      'sqlite_ms=$sqliteMs '
      'home_total_ms=$homeTotalMs '
      'cache_hydrate_ms=$hydrateMs',
    );
  }
}

void perfLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[PERF] $message');
}
