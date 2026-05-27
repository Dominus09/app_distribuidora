/// Estado de enlace mostrado al vendedor (lenguaje no técnico).
enum OperacionalEnlaceEstado {
  online,
  offline,
  reintentando,
}

/// Estado del GPS en terreno.
enum OperacionalGpsEstado {
  activo,
  buscando,
  sinSenal,
  inactivo,
}

/// Datos listos para la tarjeta operacional del Home.
class OperationalStatusSnapshot {
  const OperationalStatusSnapshot({
    required this.enlace,
    required this.gps,
    required this.pendientesCola,
    required this.visitasPendientes,
    this.visitasSyncPendientes,
    this.deadLetterCount = 0,
    this.legacyNullFechaPending = 0,
    required this.kmHoy,
    this.ultimoHeartbeat,
    required this.telemetriaActiva,
    required this.sincronizando,
  });

  final OperacionalEnlaceEstado enlace;
  final OperacionalGpsEstado gps;
  /// Ítems en SQLite outbox (heartbeat, gps, visita_sync).
  final int pendientesCola;
  /// Visitas en memoria con `pending_sync` / error (puede incluir GET servidor).
  final int visitasPendientes;
  final int? visitasSyncPendientes;
  final int deadLetterCount;
  /// Pendientes sin `fecha_operativa` (legacy fuera del scope actual).
  final int legacyNullFechaPending;
  final double kmHoy;
  final DateTime? ultimoHeartbeat;
  final bool telemetriaActiva;
  final bool sincronizando;

  int get visitasSyncCount => visitasSyncPendientes ?? visitasPendientes;

  /// Total mostrado en UI (desglosar con [colaSqliteLabel] / [visitasSyncLabel]).
  int get pendientesTotal => pendientesCola + visitasSyncCount;

  String get colaSqliteLabel =>
      pendientesCola == 0 ? '0' : '$pendientesCola';

  String get visitasSyncLabel =>
      visitasSyncCount == 0 ? '0' : '$visitasSyncCount';

  String get enlaceLabel => switch (enlace) {
        OperacionalEnlaceEstado.online => 'En línea',
        OperacionalEnlaceEstado.offline => 'Sin conexión',
        OperacionalEnlaceEstado.reintentando => 'Reenviando datos',
      };

  String get gpsLabel => switch (gps) {
        OperacionalGpsEstado.activo => 'Activo',
        OperacionalGpsEstado.buscando => 'Buscando GPS…',
        OperacionalGpsEstado.sinSenal => 'Sin señal',
        OperacionalGpsEstado.inactivo => 'Inactivo',
      };

  String get ultimoEnvioLabel {
    if (!telemetriaActiva) return 'Al iniciar ruta';
    final t = ultimoHeartbeat;
    if (t == null) return 'Aún no';
    return _tiempoRelativo(t);
  }

  static String _tiempoRelativo(DateTime momento) {
    final diff = DateTime.now().difference(momento);
    if (diff.inSeconds < 45) return 'Hace un momento';
    if (diff.inMinutes < 1) return 'Hace ${diff.inSeconds} s';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m == 1 ? 'Hace 1 min' : 'Hace $m min';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? 'Hace 1 h' : 'Hace $h h';
    }
    return 'Hace más de un día';
  }

  String get kmLabel {
    if (kmHoy < 0.1) return '0 km';
    if (kmHoy < 10) return '${kmHoy.toStringAsFixed(1)} km';
    return '${kmHoy.round()} km';
  }
}
