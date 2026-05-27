import '../../features/vendedor/models/visita.dart';

/// Alcance operacional obligatorio: vendedor + fecha calendario + ruta del día.
///
/// Toda persistencia local de visitas/ruta debe usar [cacheKey].
class OperationalScope {
  const OperationalScope({
    required this.vendedorId,
    required this.fechaOperativa,
    this.rutaId,
  });

  final String vendedorId;

  /// Fecha operativa en formato `YYYY-MM-DD` (calendario del dispositivo).
  final String fechaOperativa;

  /// Identificador de ruta del día (`Visita.rutaId` del backend).
  final int? rutaId;

  String get vendedorIdTrimmed => vendedorId.trim();

  /// Clave compuesta para SharedPreferences.
  String get cacheKey {
    final v = vendedorIdTrimmed;
    final r = rutaId;
    if (r != null && r >= 1) {
      return 'vendedor_ruta_visitas_json__${v}__${fechaOperativa}__r$r';
    }
    return 'vendedor_ruta_visitas_json__${v}__${fechaOperativa}';
  }

  /// Prefijo legacy por vendedor (sin fecha/ruta) usado en migraciones.
  static String legacyVendorCacheKey(String vendedorId) =>
      'vendedor_ruta_visitas_json__${vendedorId.trim()}';

  static const legacyGlobalCacheKey = 'vendedor_ruta_visitas_json';

  static String fechaFromDateTime(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime? parseFechaOperativa(String fecha) {
    final parts = fecha.split('-');
    if (parts.length != 3) return DateTime.tryParse(fecha);
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  OperationalScope withRutaId(int? rutaId) {
    return OperationalScope(
      vendedorId: vendedorId,
      fechaOperativa: fechaOperativa,
      rutaId: rutaId ?? this.rutaId,
    );
  }

  /// Resuelve la ruta predominante en una lista de visitas del servidor.
  static int? resolveRutaIdFromVisitas(
    List<Visita> visitas, {
    int? hint,
  }) {
    if (hint != null && hint >= 1) return hint;
    final counts = <int, int>{};
    for (final v in visitas) {
      final r = v.rutaId;
      if (r != null && r >= 1) {
        counts[r] = (counts[r] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  /// True si la visita pertenece a este alcance operacional.
  bool matchesVisita(Visita v, {DateTime? fechaCalendario}) {
    final ref = fechaCalendario ??
        parseFechaOperativa(fechaOperativa) ??
        DateTime.now();
    if (!v.coincideDiaOperativoConCalendario(ref)) return false;
    final rid = rutaId;
    if (rid != null && rid >= 1) {
      final vr = v.rutaId;
      if (vr != null && vr >= 1 && vr != rid) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is OperationalScope &&
      other.vendedorIdTrimmed == vendedorIdTrimmed &&
      other.fechaOperativa == fechaOperativa &&
      other.rutaId == rutaId;

  @override
  int get hashCode => Object.hash(vendedorIdTrimmed, fechaOperativa, rutaId);

  @override
  String toString() =>
      'OperationalScope(v=$vendedorIdTrimmed, fecha=$fechaOperativa, ruta=$rutaId)';
}
