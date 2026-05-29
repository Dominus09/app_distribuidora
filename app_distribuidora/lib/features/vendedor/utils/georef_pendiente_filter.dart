import 'package:flutter/foundation.dart';

import '../models/georef_pendiente.dart';
import '../utils/maps_navigation.dart';

/// Regla ERP: pendiente si COALESCE(lat_operacional, lat) o lon es nulo/inválido.
bool georefPendienteRequiereCaptura(GeorefPendiente item) {
  final lat = item.latOperacional ?? item.latReplica;
  final lon = item.lonOperacional ?? item.lonReplica;
  if (lat == null || lon == null) return true;
  return !visitaTieneCoordenadasCliente(lat, lon);
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
