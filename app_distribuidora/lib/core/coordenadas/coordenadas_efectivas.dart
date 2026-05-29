/// Resolución de coordenadas efectivas (COALESCE operacional, réplica BSALE).
abstract final class CoordenadasEfectivas {
  /// Prioridad: explícitas efectivas → cliente (API ya puede venir con COALESCE)
  /// → operacional → réplica legacy (último recurso).
  static double? latFromJson(Map<String, dynamic> json) {
    return _pick(
      json['lat_efectiva'],
      json['lat_efectivo'],
      json['lat_cliente'],
      json['lat_operacional'],
      json['lat'],
    );
  }

  static double? lonFromJson(Map<String, dynamic> json) {
    return _pick(
      json['lon_efectiva'],
      json['lon_efectivo'],
      json['lon_cliente'],
      json['lon_operacional'],
      json['lon'],
    );
  }

  static double latOrZero(Map<String, dynamic> json) => latFromJson(json) ?? 0;

  static double lonOrZero(Map<String, dynamic> json) => lonFromJson(json) ?? 0;

  static double? _pick(Object? a, Object? b, Object? c, Object? d, Object? e) {
    for (final v in [a, b, c, d, e]) {
      final parsed = _parseCoord(v);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
}
