import '../../../core/coordenadas/coordenadas_efectivas.dart';
import 'georef_estado.dart';
import 'georef_origen.dart';
import 'visita.dart';
import '../utils/maps_navigation.dart';

/// Cliente pendiente o con georef operacional en curso.
class GeorefPendiente {
  const GeorefPendiente({
    required this.rutaId,
    required this.clienteId,
    required this.clienteNombre,
    required this.direccion,
    this.comuna,
    this.ciudad,
    this.ruteroId,
    required this.latEfectiva,
    required this.lonEfectiva,
    required this.georefEstado,
    this.georefOrigen,
    this.localSyncStatus = GeorefSyncStatus.synced,
    this.localActionId,
    this.observacion,
  });

  final int rutaId;
  final String clienteId;
  final String clienteNombre;
  final String direccion;
  final String? comuna;
  final String? ciudad;
  final int? ruteroId;
  final double latEfectiva;
  final double lonEfectiva;
  final GeorefEstado georefEstado;
  final GeorefOrigen? georefOrigen;
  final GeorefSyncStatus localSyncStatus;
  final String? localActionId;
  final String? observacion;

  String get claveLocal => '${rutaId}_$clienteId';

  /// Crea fila georef a partir de una visita en ruta.
  static GeorefPendiente fromVisita(Visita visita) {
    return GeorefPendiente(
      rutaId: visita.rutaId ?? 0,
      clienteId: visita.clienteId ?? visita.id,
      clienteNombre: visita.clienteNombre,
      direccion: visita.direccion,
      comuna: visita.comuna,
      latEfectiva: visita.latEfectiva,
      lonEfectiva: visita.lonEfectiva,
      georefEstado: visitaTieneCoordenadasCliente(
              visita.latEfectiva, visita.lonEfectiva)
          ? GeorefEstado.aplicada
          : GeorefEstado.pendiente,
    );
  }

  bool get tieneCoordenadasEfectivas =>
      latEfectiva.abs() > 1e-9 || lonEfectiva.abs() > 1e-9;

  String get estadoUiLabel {
    if (localSyncStatus == GeorefSyncStatus.pendingSync ||
        localSyncStatus == GeorefSyncStatus.syncing) {
      final origen = georefOrigen?.uxHint;
      if (origen != null) return '${GeorefEstado.capturada.label} · $origen';
      return GeorefEstado.capturada.label;
    }
    if (localSyncStatus == GeorefSyncStatus.syncError) {
      return '🔴 Error envío';
    }
    return georefEstado.label;
  }

  factory GeorefPendiente.fromJson(Map<String, dynamic> json) {
    final lat = CoordenadasEfectivas.latFromJson(json) ?? 0;
    final lon = CoordenadasEfectivas.lonFromJson(json) ?? 0;
    return GeorefPendiente(
      rutaId: _int(json['ruta_id']) ?? 0,
      clienteId: (json['cliente_id'] ?? json['id'] ?? '').toString(),
      clienteNombre: (json['cliente_nombre'] ??
              json['nombre'] ??
              json['nombre_fantasia'] ??
              'Cliente')
          .toString(),
      direccion: (json['direccion'] ?? json['address'] ?? '—').toString(),
      comuna: json['comuna']?.toString(),
      ciudad: json['ciudad']?.toString(),
      ruteroId: _int(json['rutero_id']),
      latEfectiva: lat,
      lonEfectiva: lon,
      georefEstado: parseGeorefEstado(json['georef_estado']?.toString()),
      georefOrigen: parseGeorefOrigen(json['georef_origen']?.toString()),
      localSyncStatus: _parseLocalSync(json['local_sync_status']?.toString()),
      localActionId: json['local_action_id']?.toString(),
      observacion: json['observacion']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ruta_id': rutaId,
        'cliente_id': clienteId,
        'cliente_nombre': clienteNombre,
        'direccion': direccion,
        if (comuna != null) 'comuna': comuna,
        if (ciudad != null) 'ciudad': ciudad,
        if (ruteroId != null) 'rutero_id': ruteroId,
        'lat_efectiva': latEfectiva,
        'lon_efectiva': lonEfectiva,
        'georef_estado': georefEstado.apiValue,
        if (georefOrigen != null) 'georef_origen': georefOrigen!.apiValue,
        'local_sync_status': localSyncStatus.name,
        if (localActionId != null) 'local_action_id': localActionId,
        if (observacion != null) 'observacion': observacion,
      };

  GeorefPendiente copyWith({
    int? rutaId,
    String? clienteId,
    String? clienteNombre,
    String? direccion,
    String? comuna,
    String? ciudad,
    int? ruteroId,
    double? latEfectiva,
    double? lonEfectiva,
    GeorefEstado? georefEstado,
    GeorefOrigen? georefOrigen,
    GeorefSyncStatus? localSyncStatus,
    String? localActionId,
    String? observacion,
  }) {
    return GeorefPendiente(
      rutaId: rutaId ?? this.rutaId,
      clienteId: clienteId ?? this.clienteId,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      direccion: direccion ?? this.direccion,
      comuna: comuna ?? this.comuna,
      ciudad: ciudad ?? this.ciudad,
      ruteroId: ruteroId ?? this.ruteroId,
      latEfectiva: latEfectiva ?? this.latEfectiva,
      lonEfectiva: lonEfectiva ?? this.lonEfectiva,
      georefEstado: georefEstado ?? this.georefEstado,
      georefOrigen: georefOrigen ?? this.georefOrigen,
      localSyncStatus: localSyncStatus ?? this.localSyncStatus,
      localActionId: localActionId ?? this.localActionId,
      observacion: observacion ?? this.observacion,
    );
  }

  Map<String, dynamic> toApiUpdatePayload({
    required String vendedorId,
    required double lat,
    required double lon,
    GeorefOrigen? origen,
  }) {
    final o = origen ?? georefOrigen;
    return {
      'ruta_id': rutaId,
      'lat': lat,
      'lon': lon,
      'vendedor_id': vendedorId,
      if (clienteId.isNotEmpty) 'cliente_id': clienteId,
      if (ruteroId != null) 'rutero_id': ruteroId,
      if (localActionId != null) 'local_action_id': localActionId,
      if (o != null) 'georef_origen': o.apiValue,
      if (observacion != null && observacion!.isNotEmpty)
        'observacion': observacion,
    };
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static GeorefSyncStatus _parseLocalSync(String? raw) {
    if (raw == null || raw.isEmpty) return GeorefSyncStatus.synced;
    for (final s in GeorefSyncStatus.values) {
      if (s.name == raw) return s;
    }
    return GeorefSyncStatus.synced;
  }
}
