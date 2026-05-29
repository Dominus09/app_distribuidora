import 'package:flutter/foundation.dart';

import '../models/georef_pendiente.dart';
import '../models/visita.dart';
import '../utils/maps_navigation.dart';

/// COALESCE(lat_operacional, lat) y COALESCE(lon_operacional, lon) válidos.
bool coordenadasGeorefEfectivasValidas({
  double? latOperacional,
  double? lonOperacional,
  double? latReplica,
  double? lonReplica,
  double? latEfectivaFallback,
  double? lonEfectivaFallback,
}) {
  final lat = latOperacional ?? latReplica ?? latEfectivaFallback;
  final lon = lonOperacional ?? lonReplica ?? lonEfectivaFallback;
  if (lat == null || lon == null) return false;
  return visitaTieneCoordenadasCliente(lat, lon);
}

/// Regla ERP: pendiente si falta COALESCE operacional / réplica (o fallback ruta).
bool georefPendienteRequiereCaptura(GeorefPendiente item) {
  return !coordenadasGeorefEfectivasValidas(
    latOperacional: item.latOperacional,
    lonOperacional: item.lonOperacional,
    latReplica: item.latReplica,
    lonReplica: item.lonReplica,
    latEfectivaFallback: item.latEfectiva,
    lonEfectivaFallback: item.lonEfectiva,
  );
}

/// Misma regla que listado georef pendientes (ficha cliente / ruta).
bool visitaRequiereGeorefCaptura(Visita visita) {
  return georefPendienteRequiereCaptura(GeorefPendiente.fromVisita(visita));
}

/// Lista filtrada y sin duplicados (misma regla que KPI y pantalla pendientes).
List<GeorefPendiente> filtrarGeorefPendientesEfectivos(
  Iterable<GeorefPendiente> items,
) {
  final seen = <String>{};
  final out = <GeorefPendiente>[];
  for (final e in items) {
    if (!georefPendienteRequiereCaptura(e)) continue;
    if (!seen.add(e.claveLocal)) continue;
    out.add(e);
  }
  return out;
}

void georefKpiLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[GeorefKPI] $message');
}
