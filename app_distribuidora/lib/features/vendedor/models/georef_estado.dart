/// Estado de georreferencia operacional (backend `georef_estado`).
enum GeorefEstado {
  pendiente,
  capturada,
  aplicada,
}

extension GeorefEstadoUi on GeorefEstado {
  String get label => switch (this) {
        GeorefEstado.pendiente => '🟡 Pendiente',
        GeorefEstado.capturada => '🔵 Capturada',
        GeorefEstado.aplicada => '🟢 Aplicada',
      };

  String get apiValue => switch (this) {
        GeorefEstado.pendiente => 'pendiente',
        GeorefEstado.capturada => 'capturada',
        GeorefEstado.aplicada => 'aplicada',
      };

  static GeorefEstado fromApi(String? raw) {
    if (raw == null || raw.isEmpty) return GeorefEstado.pendiente;
    final n = raw.trim().toLowerCase().replaceAll(' ', '_');
    return switch (n) {
      'capturada' => GeorefEstado.capturada,
      'aplicada' => GeorefEstado.aplicada,
      _ => GeorefEstado.pendiente,
    };
  }
}

GeorefEstado parseGeorefEstado(String? raw) => GeorefEstadoUi.fromApi(raw);

/// Sync local de capturas georef (cola outbox).
enum GeorefSyncStatus {
  synced,
  pendingSync,
  syncing,
  syncError,
}

extension GeorefSyncStatusUi on GeorefSyncStatus {
  bool get necesitaPush =>
      this == GeorefSyncStatus.pendingSync ||
      this == GeorefSyncStatus.syncError ||
      this == GeorefSyncStatus.syncing;
}
