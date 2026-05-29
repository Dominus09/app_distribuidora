/// Origen de la captura georef operacional (`georef_origen` en API).
enum GeorefOrigen {
  gpsTerreno,
  mapaManual,
}

extension GeorefOrigenUi on GeorefOrigen {
  String get apiValue => switch (this) {
        GeorefOrigen.gpsTerreno => 'gps_terreno',
        GeorefOrigen.mapaManual => 'mapa_manual',
      };

  String get uxHint => switch (this) {
        GeorefOrigen.gpsTerreno => '🟢 Captura en local',
        GeorefOrigen.mapaManual => '🟡 Ubicación estimada por dirección',
      };
}

GeorefOrigen? parseGeorefOrigen(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final n = raw.trim().toLowerCase().replaceAll(' ', '_');
  return switch (n) {
    'gps_terreno' => GeorefOrigen.gpsTerreno,
    'mapa_manual' => GeorefOrigen.mapaManual,
    _ => null,
  };
}
